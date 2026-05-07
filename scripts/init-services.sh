#!/usr/bin/env bash
# Initialize and start PostgreSQL, Redis, and MinIO services.
#
# Called from entrypoint.sh step 3. Starts all infrastructure services
# required by bento-bench-autorun and registers their PIDs so the
# watchdog can monitor them.
#
# PIDs are written to ${VARS_DIR}/.service_pids (one per line) for the
# calling entrypoint.sh to register with its watchdog.
#
# Environment variables (set by entrypoint.sh or defaults):
#   STORAGE_ROOT  - Base storage directory (default: /storage)
#   PGDATA        - PostgreSQL data directory (default: ${STORAGE_ROOT}/postgres)
#   VARS_DIR      - Marker/state directory (default: ${STORAGE_ROOT}/vars)
#   REDIS_PORT    - Redis port (default: 6379)
#   S3_ACCESS_KEY - MinIO root user (default: minioadmin)
#   S3_SECRET_KEY - MinIO root password (default: minioadmin)
#   S3_BUCKET     - Bucket name (default: workflow)

set -euo pipefail

STORAGE_ROOT="${STORAGE_ROOT:-/storage}"
PGDATA="${PGDATA:-${STORAGE_ROOT}/postgres}"
VARS_DIR="${VARS_DIR:-${STORAGE_ROOT}/vars}"
REDIS_PORT="${REDIS_PORT:-6379}"
S3_ACCESS_KEY="${S3_ACCESS_KEY:-minioadmin}"
S3_SECRET_KEY="${S3_SECRET_KEY:-minioadmin}"
S3_BUCKET="${S3_BUCKET:-workflow}"

SERVICE_PIDS_FILE="${VARS_DIR}/.service_pids"

# --- PostgreSQL ---
echo "Starting PostgreSQL..."
/scripts/start-postgres.sh || { echo "start-postgres failed"; exit 1; }

# --- Redis ---
echo "Starting Redis..."
redis-server --daemonize yes --port "${REDIS_PORT}"
echo "Redis started on port ${REDIS_PORT}."

# --- MinIO ---
echo "Starting MinIO..."
mkdir -p "${STORAGE_ROOT}/minio-data"

export MINIO_ROOT_USER="${S3_ACCESS_KEY}"
export MINIO_ROOT_PASSWORD="${S3_SECRET_KEY}"

minio server "${STORAGE_ROOT}/minio-data" --console-address ":9001" &
MINIO_PID=$!
echo "MinIO started (PID ${MINIO_PID})."

# Wait for MinIO health check
echo "Waiting for MinIO to be ready..."
for i in $(seq 1 30); do
    if curl -sf http://localhost:9000/minio/health/live > /dev/null 2>&1; then
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
mc alias set local http://localhost:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null || true
mc mb "local/${S3_BUCKET}" 2>/dev/null || true
echo "MinIO bucket '${S3_BUCKET}' ensured."

# --- Register service PIDs for the watchdog ---
# Write MinIO PID to file so entrypoint.sh can add it to SERVICE_PIDS.
# PostgreSQL is managed by pg_ctl (tracked via pg_isready health checks).
# Redis daemonizes itself and is tracked via redis-cli ping.
# MinIO is the only foreground service we launch that needs PID monitoring.
echo "${MINIO_PID}" > "${SERVICE_PIDS_FILE}"

echo "All services initialized."