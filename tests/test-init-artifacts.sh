#!/bin/bash
# Test that init-artifacts.sh correctly skips download when artifacts are present
# and correctly proceeds when they are missing.
#
# Because the script calls curl for actual downloads, we cannot run full download
# tests without network access. Instead, we test the skip logic and then validate
# the diagnostic output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
INIT_SCRIPT="${PROJECT_DIR}/scripts/init-artifacts.sh"

PASS=0
FAIL=0

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  PASS: ${description}"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: ${description}"
        echo "    expected: ${expected}"
        echo "    actual:   ${actual}"
        FAIL=$((FAIL + 1))
    fi
}

# --- Test 1: Skip download when both sentinel files exist ---
echo "Test 1: Skip download when artifacts are present"
MOCK_DIR=$(mktemp -d)
export BENTO_ARTIFACTS_DIR="${MOCK_DIR}"
mkdir -p "${MOCK_DIR}/groth_16" "${MOCK_DIR}/blake3_groth16"
touch "${MOCK_DIR}/groth_16/settings.toml"
touch "${MOCK_DIR}/blake3_groth16/verify_for_guest_final.zkey"

OUTPUT=$(bash "${INIT_SCRIPT}" 2>&1) || true
echo "${OUTPUT}" | grep -q "risc0 artifacts already present, skipping download"
assert_eq "skips download when both sentinel files exist" "0" "$?"

rm -rf "${MOCK_DIR}"

# --- Test 2: Does NOT skip when groth16 sentinel is missing ---
echo "Test 2: Does NOT skip when groth16 sentinel is missing"
MOCK_DIR=$(mktemp -d)
export BENTO_ARTIFACTS_DIR="${MOCK_DIR}"
mkdir -p "${MOCK_DIR}/groth_16" "${MOCK_DIR}/blake3_groth16"
touch "${MOCK_DIR}/blake3_groth16/verify_for_guest_final.zkey"

set +e
OUTPUT=$(timeout 5 bash "${INIT_SCRIPT}" 2>&1 || true)
set -e

SKIP_MSG_FOUND=0
echo "${OUTPUT}" | grep -q "risc0 artifacts already present, skipping download" && SKIP_MSG_FOUND=1
assert_eq "does NOT skip when groth16 sentinel missing" "0" "${SKIP_MSG_FOUND}"

rm -rf "${MOCK_DIR}"

# --- Test 3: Does NOT skip when blake3 sentinel is missing ---
echo "Test 3: Does NOT skip when blake3 sentinel is missing"
MOCK_DIR=$(mktemp -d)
export BENTO_ARTIFACTS_DIR="${MOCK_DIR}"
mkdir -p "${MOCK_DIR}/groth_16" "${MOCK_DIR}/blake3_groth16"
touch "${MOCK_DIR}/groth_16/settings.toml"

set +e
OUTPUT=$(timeout 5 bash "${INIT_SCRIPT}" 2>&1 || true)
set -e

SKIP_MSG_FOUND=0
echo "${OUTPUT}" | grep -q "risc0 artifacts already present, skipping download" && SKIP_MSG_FOUND=1
assert_eq "does NOT skip when blake3 sentinel missing" "0" "${SKIP_MSG_FOUND}"

rm -rf "${MOCK_DIR}"

# --- Test 4: Diagnostic output shows sentinel presence ---
echo "Test 4: Diagnostic output reports sentinel status correctly"
MOCK_DIR=$(mktemp -d)
export BENTO_ARTIFACTS_DIR="${MOCK_DIR}"
mkdir -p "${MOCK_DIR}/groth_16" "${MOCK_DIR}/blake3_groth16"
touch "${MOCK_DIR}/groth_16/settings.toml"
touch "${MOCK_DIR}/blake3_groth16/verify_for_guest_final.zkey"

OUTPUT=$(bash "${INIT_SCRIPT}" 2>&1) || true
echo "${OUTPUT}" | grep -q "groth16 sentinel.*FOUND"
assert_eq "reports groth16 sentinel as FOUND" "0" "$?"

echo "${OUTPUT}" | grep -q "blake3 sentinel.*FOUND"
assert_eq "reports blake3 sentinel as FOUND" "0" "$?"

rm -rf "${MOCK_DIR}"

# --- Test 5: Diagnostic output shows MISSING when files absent ---
echo "Test 5: Diagnostic output reports sentinel status as MISSING"
MOCK_DIR=$(mktemp -d)
export BENTO_ARTIFACTS_DIR="${MOCK_DIR}"
mkdir -p "${MOCK_DIR}/groth_16" "${MOCK_DIR}/blake3_groth16"

set +e
OUTPUT=$(timeout 5 bash "${INIT_SCRIPT}" 2>&1 || true)
set -e

echo "${OUTPUT}" | grep -q "groth16 sentinel.*MISSING"
assert_eq "reports groth16 sentinel as MISSING" "0" "$?"

echo "${OUTPUT}" | grep -q "blake3 sentinel.*MISSING"
assert_eq "reports blake3 sentinel as MISSING" "0" "$?"

rm -rf "${MOCK_DIR}"

# --- Summary ---
echo ""
echo "=============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "=============================="
if [ "${FAIL}" -gt 0 ]; then
    exit 1
fi
exit 0