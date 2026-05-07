#!/usr/bin/env bash
# Fetch risc0 proving artifacts at runtime
#
# Downloads groth16 and blake3_groth16 artifacts to BENTO_ARTIFACTS_DIR.
# Skips if already present (checks .r0_fetched marker file).

set -euo pipefail

ARTIFACTS_DIR="${BENTO_ARTIFACTS_DIR:-/opt/bento/artifacts}"
MARKER="${VARS_DIR:-/storage/vars}/.r0_fetched"

GROTH16_URL="${GROTH16_ARTIFACTS_URL:-https://hancho-worker.cloudflare-y513l.workers.dev/artifacts/groth16_artifacts.tar.zst}"
BLAKE3_URL="${BLAKE3_ARTIFACTS_URL:-https://staging-signal-artifacts.beboundless.xyz/v3/proving/blake3_groth16_artifacts.tar.xz}"

mkdir -p "${ARTIFACTS_DIR}" "$(dirname "${MARKER}")"

if [[ -f "${MARKER}" ]]; then
    echo "Risc0 artifacts already fetched, skipping."
    exit 0
fi

echo "Fetching groth16 artifacts..."
curl -fSL -o /tmp/groth16_artifacts.tar.zst "${GROTH16_URL}"
mkdir -p "${ARTIFACTS_DIR}/groth_16"
tar --zstd -xf /tmp/groth16_artifacts.tar.zst -C /tmp
mv /tmp/risc0 "${ARTIFACTS_DIR}/groth_16" 2>/dev/null || true
rm -f /tmp/groth16_artifacts.tar.zst

echo "Fetching blake3_groth16 artifacts..."
curl -fSL -o /tmp/blake3_groth16.tar.xz "${BLAKE3_URL}"
mkdir -p "${ARTIFACTS_DIR}/blake3_groth16"
tar -xJf /tmp/blake3_groth16.tar.xz -C /tmp
mv /tmp/blake3_groth16_artifacts "${ARTIFACTS_DIR}/blake3_groth16" 2>/dev/null || true
rm -f /tmp/blake3_groth16.tar.xz

touch "${MARKER}"
echo "Risc0 artifacts fetched successfully."