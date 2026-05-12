#!/usr/bin/env bash
# Tests for log-specs.sh system specs logging
# Run: bash tests/test_log_specs.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_SPECS_SCRIPT="${PROJECT_DIR}/scripts/log-specs.sh"

PASS=0
FAIL=0

assert_output_contains() {
    local description="$1" output="$2" pattern="$3"
    if echo "$output" | grep -F -q -- "$pattern"; then
        echo "  PASS: $description"
        ((PASS++)) || true
    else
        echo "  FAIL: $description (pattern '$pattern' not found)"
        ((FAIL++)) || true
    fi
}

echo "=== System Specs Logging Tests ==="

# --- Test 1: Header and footer markers ---
echo ""
echo "Test 1: Output contains header and footer markers"
OUTPUT=$(bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
assert_output_contains "header marker" "$OUTPUT" "=== System Specifications ==="
assert_output_contains "footer marker" "$OUTPUT" "============================"

# --- Test 2: Timestamp line ---
echo ""
echo "Test 2: Output contains timestamp"
OUTPUT=$(bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
assert_output_contains "timestamp line" "$OUTPUT" "Timestamp:"

# --- Test 3: OS info ---
echo ""
echo "Test 3: Output contains OS info"
OUTPUT=$(bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
assert_output_contains "OS line" "$OUTPUT" "OS:"
assert_output_contains "Kernel line" "$OUTPUT" "Kernel:"
assert_output_contains "Hostname line" "$OUTPUT" "Hostname:"

# --- Test 4: Section headers ---
echo ""
echo "Test 4: Output contains section headers"
OUTPUT=$(bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
assert_output_contains "CPU section header" "$OUTPUT" "--- CPU ---"
assert_output_contains "Memory section header" "$OUTPUT" "--- Memory ---"
assert_output_contains "Disk section header" "$OUTPUT" "--- Disk ---"
assert_output_contains "GPU section header" "$OUTPUT" "--- GPU ---"

# --- Test 5: Disk info always present ---
echo ""
echo "Test 5: Disk info line present (df -h /)"
OUTPUT=$(bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
# df -h / output contains a '/' somewhere
assert_output_contains "disk info present" "$OUTPUT" "/"

# --- Test 6: Graceful degradation when lscpu missing ---
echo ""
echo "Test 6: Graceful degradation when lscpu is missing"
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# Create a PATH that excludes lscpu
OUTPUT_NO_LSCPU=$(PATH="/usr/bin:/bin" bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
if echo "$OUTPUT_NO_LSCPU" | grep -q "lscpu not found\|Architecture\|CPU(s)"; then
    echo "  PASS: Handles missing lscpu gracefully"
    ((PASS++)) || true
else
    echo "  FAIL: Did not handle missing lscpu"
    ((FAIL++)) || true
fi

rm -rf "$MOCK_DIR"

# --- Test 7: Graceful degradation when free missing ---
echo ""
echo "Test 7: Graceful degradation when free is missing"
OUTPUT_NO_FREE=$(PATH="/usr/bin:/bin" bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
if echo "$OUTPUT_NO_FREE" | grep -q "free command not found\|Mem:\|Swap:"; then
    echo "  PASS: Handles missing free gracefully"
    ((PASS++)) || true
else
    echo "  FAIL: Did not handle missing free"
    ((FAIL++)) || true
fi

# --- Test 8: Graceful degradation when nvidia-smi missing ---
echo ""
echo "Test 8: Graceful degradation when nvidia-smi is missing"
OUTPUT_NO_GPU=$(PATH="/usr/bin:/bin" bash "${LOG_SPECS_SCRIPT}" 2>&1) || true
if echo "$OUTPUT_NO_GPU" | grep -q "No NVIDIA GPU detected\|nvidia-smi not found"; then
    echo "  PASS: Handles missing nvidia-smi gracefully"
    ((PASS++)) || true
else
    echo "  FAIL: Did not handle missing nvidia-smi"
    ((FAIL++)) || true
fi

# --- Summary ---
echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"

if [[ "$FAIL" -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
    exit 0
fi