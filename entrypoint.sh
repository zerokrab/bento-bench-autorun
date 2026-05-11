#!/bin/bash
# bento-bench-autorun Entrypoint
#
# Orchestrates startup, runs a background watchdog for service health,
# and ensures clean shutdown on exit or signal.
#
# Startup sequence:
#   1. detect-gpu.sh     -> sets GPU_COUNT, SEGMENT_SIZE
#   2. init-artifacts.sh  -> fetch risc0 artifacts if not baked into image
#   3. init-services.sh   -> starts postgres, redis, minio
#   4. init-agents.sh     -> starts bento-rest-api, aux, exec, prove agents
#   5. watchdog           -> background loop monitoring service PIDs
#   6. wait-for-ready.sh -> polls REST API /health until 200
#   7. run-bench.sh       -> runs bento-bench, captures exit code
#   8. Cleanup and exit with bento-bench exit code

set -euo pipefail

echo "=== bento-bench-autorun starting ==="

# --- Runtime configuration ---
export STORAGE_ROOT="${STORAGE_ROOT:-/storage}"
export VARS_DIR="${STORAGE_ROOT}/vars"
export PGDATA="${STORAGE_ROOT}/postgres"

mkdir -p "${STORAGE_ROOT}"/{vars,logs,postgres} "${VARS_DIR}"

# --- Service PID tracking ---
SERVICE_PIDS=()

# --- Cleanup function ---
# shellcheck disable=SC2317 # invoked via trap
cleanup() {
    local exit_code=$?
    echo "Shutting down services..."

    # Kill the watchdog if running
    if [[ -n "${WATCHDOG_PID:-}" ]] && kill -0 "${WATCHDOG_PID}" 2>/dev/null; then
        kill -TERM "${WATCHDOG_PID}" 2>/dev/null || true
        wait "${WATCHDOG_PID}" 2>/dev/null || true
    fi

    # Kill all tracked service PIDs
    for pid in "${SERVICE_PIDS[@]}"; do
        kill -TERM "${pid}" 2>/dev/null || true
    done

    # Give processes a moment to terminate gracefully
    sleep 1

    # Force-kill anything still running
    for pid in "${SERVICE_PIDS[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            kill -KILL "${pid}" 2>/dev/null || true
        fi
    done

    exit "${exit_code}"
}

trap cleanup SIGTERM SIGINT EXIT

# --- Watchdog function ---
watchdog() {
    while true; do
        for pid in "${SERVICE_PIDS[@]}"; do
            if ! kill -0 "${pid}" 2>/dev/null; then
                echo "FATAL: Service PID ${pid} crashed"
                echo "Dumping logs from /tmp/bento-logs/..."
                cat /tmp/bento-logs/*.log 2>/dev/null || echo "(no log files found)"
                # Send SIGTERM to the parent entrypoint process so the EXIT
                # trap fires and cleans up all child services.  A bare
                # `exit 1` only exits the watchdog subshell, leaving the
                # container running as a zombie.
                kill -TERM "$$" 2>/dev/null
                # Must exit the watchdog subshell immediately — without this,
                # the loop would re-detect the same dead PID every 5 seconds,
                # flooding the logs and preventing the parent's trap from
                # completing cleanup.
                return 1
            fi
        done
        sleep 5
    done
}

# --- Sequential startup ---

# 1. Detect GPU
echo "--- Detecting GPU ---"
if [[ -x /scripts/detect-gpu.sh ]]; then
    /scripts/detect-gpu.sh || { echo "detect-gpu failed"; exit 1; }
fi

# 2. Initialize risc0 artifacts (unless skipped)
if [[ "${SKIP_R0_INIT:-false}" != "true" ]]; then
    echo "--- Fetching risc0 artifacts ---"
    /scripts/init-artifacts.sh || { echo "init-artifacts failed"; exit 1; }
fi

# 3. Start services (postgres, redis, minio)
echo "--- Starting services ---"
if [[ -x /scripts/init-services.sh ]]; then
    /scripts/init-services.sh || { echo "init-services failed"; exit 1; }
    # Read PIDs registered by init-services.sh into the watchdog array
    if [[ -f "${VARS_DIR}/.service_pids" ]]; then
        while IFS= read -r pid; do
            SERVICE_PIDS+=("${pid}")
        done < "${VARS_DIR}/.service_pids"
    fi
else
    # Inline service startup when init-services.sh is not present
    # Start PostgreSQL
    echo "Starting PostgreSQL..."
    /scripts/start-postgres.sh || { echo "start-postgres failed"; exit 1; }

    # Start Redis
    echo "Starting Redis..."
    redis-server --daemonize yes --port "${REDIS_PORT:-6379}"

    # Start MinIO
    echo "Starting MinIO..."
    export MINIO_ROOT_USER="${S3_ACCESS_KEY:-minioadmin}"
    export MINIO_ROOT_PASSWORD="${S3_SECRET_KEY:-minioadmin}"
    minio server "${STORAGE_ROOT}/minio-data" --console-address ":9001" &
    MINIO_PID=$!
    SERVICE_PIDS+=("${MINIO_PID}")

    # Wait for MinIO to be ready
    echo "Waiting for MinIO to start..."
    for i in $(seq 1 30); do
        if curl -sf "http://localhost:9000/minio/health/live" > /dev/null 2>&1; then
            echo "MinIO is ready."
            break
        fi
        if [[ "${i}" -eq 30 ]]; then
            echo "MinIO failed to start within 30 seconds"
            exit 1
        fi
        sleep 1
    done

    # Create the bucket if it doesn't exist
    mc alias set local "http://localhost:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null || true
    mc mb "local/${S3_BUCKET:-workflow}" 2>/dev/null || true
fi

# 4. Start agents (bento-rest-api, aux, exec, prove)
echo "--- Starting agents ---"
if [[ -x /scripts/init-agents.sh ]]; then
    /scripts/init-agents.sh || { echo "init-agents failed"; exit 1; }
    # Read agent PIDs registered by init-agents.sh into the watchdog array
    if [[ -f "${VARS_DIR}/.agent_pids" ]]; then
        while IFS= read -r pid; do
            SERVICE_PIDS+=("${pid}")
        done < "${VARS_DIR}/.agent_pids"
    fi
else
    # Inline agent startup when init-agents.sh is not present
    # CLI: bento-rest-api --bind-addr <ADDR> <DATABASE_URL> <S3_BUCKET> <S3_ACCESS_KEY> <S3_SECRET_KEY> <S3_URL> <S3_REGION>
    echo "Starting bento-rest-api..."
    bento-rest-api \
        --bind-addr "0.0.0.0:${REST_API_PORT:-8081}" \
        "${DATABASE_URL}" \
        "${S3_BUCKET:-workflow}" \
        "${S3_ACCESS_KEY:-minioadmin}" \
        "${S3_SECRET_KEY:-minioadmin}" \
        "${S3_ENDPOINT:-http://localhost:9000}" \
        "${S3_REGION:-auto}" \
        &
    REST_API_PID=$!
    SERVICE_PIDS+=("${REST_API_PID}")
fi

# 5. Start watchdog
echo "--- Starting watchdog ---"
watchdog &
WATCHDOG_PID=$!

# 6. Wait for REST API readiness
echo "--- Waiting for API readiness ---"
if [[ -x /scripts/wait-for-ready.sh ]]; then
    /scripts/wait-for-ready.sh || { echo "Services never became ready"; exit 1; }
else
    # Inline readiness check when wait-for-ready.sh is not present
    echo "Waiting for bento-rest-api on port ${REST_API_PORT:-8081}..."
    for i in $(seq 1 120); do
        if curl -sf "http://localhost:${REST_API_PORT:-8081}/health" > /dev/null 2>&1; then
            echo "bento-rest-api is ready."
            break
        fi
        if [[ "${i}" -eq 120 ]]; then
            echo "bento-rest-api never became ready within 120 seconds"
            exit 1
        fi
        sleep 1
    done
fi

# 7. Run benchmark
echo "--- Running bento-bench ---"
if [[ -x /scripts/run-bench.sh ]]; then
    /scripts/run-bench.sh
    BENCH_EXIT_CODE=$?
else
    bento-bench "$@"
    BENCH_EXIT_CODE=$?
fi

# 8. Cleanup and exit (trap EXIT will run cleanup)
echo "bento-bench exited with code ${BENCH_EXIT_CODE}"
exit "${BENCH_EXIT_CODE}"