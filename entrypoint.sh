#!/bin/bash
# bento-bench-autorun Entrypoint
#
# Starts postgres, redis, minio, then runs bento services and bento-bench.
# Risc0 artifacts are fetched at runtime via init-artifacts.sh unless
# SKIP_R0_INIT=true is set.

set -euo pipefail

echo "=== bento-bench-autorun starting ==="

# --- Runtime configuration ---
export STORAGE_ROOT="${STORAGE_ROOT:-/storage}"
export VARS_DIR="${STORAGE_ROOT}/vars"
export PGDATA="${STORAGE_ROOT}/postgres"

mkdir -p "${STORAGE_ROOT}"/{vars,logs,postgres} "${VARS_DIR}"

# --- Initialize risc0 artifacts (unless skipped) ---
if [[ "${SKIP_R0_INIT:-false}" != "true" ]]; then
  echo "--- Fetching risc0 artifacts ---"
  /scripts/init-artifacts.sh
fi

# --- Start PostgreSQL ---
echo "--- Starting PostgreSQL ---"
/scripts/start-postgres.sh

# --- Start Redis ---
echo "--- Starting Redis ---"
redis-server --daemonize yes --port "${REDIS_PORT:-6379}"

# --- Start MinIO ---
echo "--- Starting MinIO ---"
export MINIO_ROOT_USER="${S3_ACCESS_KEY:-minioadmin}"
export MINIO_ROOT_PASSWORD="${S3_SECRET_KEY:-minioadmin}"
minio server "${STORAGE_ROOT}/minio-data" --console-address ":9001" &
MINIO_PID=$!

# Wait for MinIO to be ready
echo "Waiting for MinIO to start..."
for i in $(seq 1 30); do
  if curl -sf "http://localhost:9000/minio/health/live" > /dev/null 2>&1; then
    echo "MinIO is ready."
    break
  fi
  sleep 1
done

# Create the bucket if it doesn't exist
mc alias set local "http://localhost:9000" "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}" 2>/dev/null || true
mc mb "local/${S3_BUCKET:-workflow}" 2>/dev/null || true

# --- Start bento-rest-api ---
echo "--- Starting bento-rest-api ---"
bento-rest-api &
REST_API_PID=$!

# Wait for REST API to be ready
echo "Waiting for bento-rest-api on port ${REST_API_PORT:-8081}..."
for i in $(seq 1 60); do
  if curl -sf "http://localhost:${REST_API_PORT:-8081}/health" > /dev/null 2>&1; then
    echo "bento-rest-api is ready."
    break
  fi
  sleep 1
done

# --- Run bento-bench ---
echo "--- Running bento-bench ---"
exec bento-bench "$@"