#!/bin/bash
# Fetch risc0 proving artifacts at runtime
#
# Downloads groth16 and blake3_groth16 artifacts to BENTO_ARTIFACTS_DIR.
# Skips if artifacts are already present (checks for settings.toml and verify_for_guest_final.zkey).
# Supports env var overrides for artifact directories and download URLs.

set -euo pipefail

ARTIFACTS_DIR="${BENTO_ARTIFACTS_DIR:-/opt/bento/artifacts}"
GROTH16_DIR="${ARTIFACTS_DIR}/groth_16"
BLAKE3_DIR="${ARTIFACTS_DIR}/blake3_groth16"

GROTH16_URL="${GROTH16_ARTIFACTS_URL:-https://hancho-worker.cloudflare-y513l.workers.dev/artifacts/groth16_artifacts.tar.zst}"
BLAKE3_URL="${BLAKE3_ARTIFACTS_URL:-https://staging-signal-artifacts.beboundless.xyz/v3/proving/blake3_groth16_artifacts.tar.xz}"

# Skip if artifacts are already present
# groth16 archive extracts to: settings.toml, .rzup, extensions/, tmp/
# blake3 archive extracts to: verify_for_guest_final.zkey, etc.
echo "Checking for existing risc0 artifacts in ${ARTIFACTS_DIR}..."
echo "  groth16 sentinel: ${GROTH16_DIR}/settings.toml ($([ -f "${GROTH16_DIR}/settings.toml" ] && echo 'FOUND' || echo 'MISSING'))"
echo "  blake3 sentinel:  ${BLAKE3_DIR}/verify_for_guest_final.zkey ($([ -f "${BLAKE3_DIR}/verify_for_guest_final.zkey" ] && echo 'FOUND' || echo 'MISSING'))"
if [ -f "${GROTH16_DIR}/settings.toml" ] && [ -f "${BLAKE3_DIR}/verify_for_guest_final.zkey" ]; then
    echo "risc0 artifacts already present, skipping download"
    exit 0
fi

mkdir -p "${GROTH16_DIR}" "${BLAKE3_DIR}"

echo "Downloading risc0 artifacts (this may take several minutes)..."

echo "Fetching groth16 artifacts..."
curl -fSL "${GROTH16_URL}" | tar --zstd -x -C "${GROTH16_DIR}" --strip-components=1

echo "Fetching blake3_groth16 artifacts..."
curl -fSL "${BLAKE3_URL}" | tar -xJ -C "${BLAKE3_DIR}" --strip-components=1

echo "risc0 artifacts ready"