#!/usr/bin/env bash
# Start bento agents (REST API, Aux, Exec, Prove) in the correct order.
#
# Called from entrypoint.sh step 4. Starts all bento agent processes
# and writes their PIDs to ${VARS_DIR}/.agent_pids so the entrypoint
# watchdog can monitor them.
#
# Start order:
#   1. REST API  — must be up before agents connect
#   2. Aux agent — monitor-requeue + 16h Redis TTL
#   3. Exec agents — 1 per GPU (overridable via EXEC_AGENTS env var)
#   4. Prove agents — 1 per GPU
#
# Environment variables (set by entrypoint.sh or defaults):
#   REST_API_PORT  - Port for REST API (default: 8080)
#   SEGMENT_SIZE   - segment-po2 value for exec agents (default: from detect-gpu.sh)
#   EXEC_AGENTS    - Number of exec agents (default: 1 per GPU)
#   GPU_COUNT      - Number of GPUs, set by detect-gpu.sh (default: 1)
#   VARS_DIR       - Marker/state directory (default: /storage/vars)

set -euo pipefail

REST_API_PORT="${REST_API_PORT:-8080}"
SEGMENT_SIZE="${SEGMENT_SIZE:-21}"
GPU_COUNT="${GPU_COUNT:-1}"
EXEC_AGENTS="${EXEC_AGENTS:-${GPU_COUNT}}"
PROVE_AGENTS="${GPU_COUNT}"
VARS_DIR="${VARS_DIR:-/storage/vars}"

LOG_DIR="/tmp/bento-logs"
mkdir -p "${LOG_DIR}"

AGENT_PIDS_FILE="${VARS_DIR}/.agent_pids"

AGENT_PIDS=()

echo "Starting Bento agents..."
echo "  REST_API_PORT=${REST_API_PORT}"
echo "  SEGMENT_SIZE=${SEGMENT_SIZE}"
echo "  EXEC_AGENTS=${EXEC_AGENTS}"
echo "  PROVE_AGENTS=${PROVE_AGENTS}"

# 1. REST API (must start first — other agents connect to it)
# CLI: bento-rest-api --bind-addr <ADDR> <DATABASE_URL> <S3_BUCKET> <S3_ACCESS_KEY> <S3_SECRET_KEY> <S3_URL> <S3_REGION>
echo "Starting REST API on port ${REST_API_PORT}..."
bento-rest-api --bind-addr "0.0.0.0:${REST_API_PORT}" \
    "${DATABASE_URL}" \
    "${S3_BUCKET}" \
    "${S3_ACCESS_KEY}" \
    "${S3_SECRET_KEY}" \
    "${S3_ENDPOINT}" \
    "${S3_REGION}" \
    > "${LOG_DIR}/rest-api.log" 2>&1 &
AGENT_PIDS+=("$!")

# Wait for API to be ready
echo "Waiting for REST API..."
for i in $(seq 1 180); do
    if curl -sf "http://localhost:${REST_API_PORT}/health" > /dev/null 2>&1; then
        echo "REST API is online."
        break
    fi
    # Check if the process is still alive every 10 seconds
    if [[ $((i % 10)) -eq 0 ]]; then
        if ! kill -0 "${AGENT_PIDS[0]}" 2>/dev/null; then
            echo "FATAL: REST API process (PID ${AGENT_PIDS[0]}) has exited unexpectedly"
            echo "--- REST API log (last 80 lines) ---"
            tail -n 80 "${LOG_DIR}/rest-api.log" 2>/dev/null || echo "(no log file found)"
            exit 1
        fi
    fi
    if [[ "${i}" -eq 180 ]]; then
        echo "REST API failed to become ready within 180 seconds"
        echo "--- REST API process status ---"
        if kill -0 "${AGENT_PIDS[0]}" 2>/dev/null; then
            echo "Process ${AGENT_PIDS[0]} is still running"
        else
            echo "Process ${AGENT_PIDS[0]} has exited"
        fi
        echo "--- REST API log (last 80 lines) ---"
        tail -n 80 "${LOG_DIR}/rest-api.log" 2>/dev/null || echo "(no log file found)"
        exit 1
    fi
    sleep 1
done

# 2. Aux Agent
# CLI: bento-agent --task-stream <TASK_STREAM> --monitor-requeue --redis-ttl <REDIS_TTL> <DATABASE_URL> <REDIS_URL> <S3_BUCKET> <S3_ACCESS_KEY> <S3_SECRET_KEY> <S3_URL> <S3_REGION>
echo "Starting Aux agent..."
bento-agent \
    -t aux --monitor-requeue --redis-ttl 57600 \
    "${DATABASE_URL}" \
    "${REDIS_URL}" \
    "${S3_BUCKET}" \
    "${S3_ACCESS_KEY}" \
    "${S3_SECRET_KEY}" \
    "${S3_ENDPOINT}" \
    "${S3_REGION}" \
    > "${LOG_DIR}/aux-agent.log" 2>&1 &
AGENT_PIDS+=("$!")

# 3. Exec Agents (1 per GPU by default, override with EXEC_AGENTS)
# CLI: bento-agent --task-stream <TASK_STREAM> --segment-po2 <SEGMENT_PO2> --redis-ttl <REDIS_TTL> <DATABASE_URL> <REDIS_URL> <S3_BUCKET> <S3_ACCESS_KEY> <S3_SECRET_KEY> <S3_URL> <S3_REGION>
echo "Starting ${EXEC_AGENTS} Exec agent(s)..."
for i in $(seq 1 "${EXEC_AGENTS}"); do
    bento-agent \
        -t exec --segment-po2 "${SEGMENT_SIZE}" --redis-ttl 57600 \
        "${DATABASE_URL}" \
        "${REDIS_URL}" \
        "${S3_BUCKET}" \
        "${S3_ACCESS_KEY}" \
        "${S3_SECRET_KEY}" \
        "${S3_ENDPOINT}" \
        "${S3_REGION}" \
        > "${LOG_DIR}/exec-agent-${i}.log" 2>&1 &
    AGENT_PIDS+=("$!")
done

# 4. Prove Agents (1 per GPU)
# CLI: bento-agent --task-stream <TASK_STREAM> --redis-ttl <REDIS_TTL> <DATABASE_URL> <REDIS_URL> <S3_BUCKET> <S3_ACCESS_KEY> <S3_SECRET_KEY> <S3_URL> <S3_REGION>
echo "Starting ${PROVE_AGENTS} Prove agent(s)..."
for i in $(seq 1 "${PROVE_AGENTS}"); do
    bento-agent \
        -t prove --redis-ttl 57600 \
        "${DATABASE_URL}" \
        "${REDIS_URL}" \
        "${S3_BUCKET}" \
        "${S3_ACCESS_KEY}" \
        "${S3_SECRET_KEY}" \
        "${S3_ENDPOINT}" \
        "${S3_REGION}" \
        > "${LOG_DIR}/prove-agent-${i}.log" 2>&1 &
    AGENT_PIDS+=("$!")
done

# --- Register PIDs for the watchdog ---
printf '%s\n' "${AGENT_PIDS[@]}" > "${AGENT_PIDS_FILE}"

echo "All agents started successfully."
echo "PIDs: ${AGENT_PIDS[*]}"