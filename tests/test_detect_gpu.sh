#!/usr/bin/env bash
# Tests for detect-gpu.sh GPU counting logic
# Run: bash tests/test_detect_gpu.sh

set -euo pipefail

PASS=0
FAIL=0

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  PASS: $description (expected=$expected actual=$actual)"
        ((PASS++)) || true
    else
        echo "  FAIL: $description (expected=$expected actual=$actual)"
        ((FAIL++)) || true
    fi
}

echo "=== GPU Count Detection Tests ==="

# Create a temporary mock directory
MOCK_DIR=$(mktemp -d)
trap 'rm -rf "$MOCK_DIR"' EXIT

# --- Test 1: Single GPU ---
echo ""
echo "Test 1: Single GPU detection"
cat > "$MOCK_DIR/nvidia-smi" <<'MOCK'
#!/bin/bash
if [[ "$1" == "--list-gpus" ]]; then
    echo "GPU 0: NVIDIA GeForce RTX 4090 (UUID: gpu-xxx)"
elif [[ "$1" == "--query-gpu" ]]; then
    echo "NVIDIA GeForce RTX 4090"
fi
MOCK
chmod +x "$MOCK_DIR/nvidia-smi"

export PATH="$MOCK_DIR:$PATH"
GPU_COUNT=$(nvidia-smi --list-gpus | grep -c "GPU")
assert_eq "Single GPU count" "1" "$GPU_COUNT"

# --- Test 2: Multiple GPUs (the bug this fix addresses) ---
echo ""
echo "Test 2: Multiple GPU detection (4 GPUs)"
cat > "$MOCK_DIR/nvidia-smi" <<'MOCK'
#!/bin/bash
if [[ "$1" == "--list-gpus" ]]; then
    echo "GPU 0: NVIDIA GeForce RTX 5090 (UUID: gpu-aaa)"
    echo "GPU 1: NVIDIA GeForce RTX 5090 (UUID: gpu-bbb)"
    echo "GPU 2: NVIDIA GeForce RTX 5090 (UUID: gpu-ccc)"
    echo "GPU 3: NVIDIA GeForce RTX 5090 (UUID: gpu-ddd)"
elif [[ "$1" == "--query-gpu" ]]; then
    echo "NVIDIA GeForce RTX 5090"
fi
MOCK
chmod +x "$MOCK_DIR/nvidia-smi"

GPU_COUNT=$(nvidia-smi --list-gpus | grep -c "GPU")
assert_eq "4-GPU count" "4" "$GPU_COUNT"

# --- Test 3: Multiple GPUs with trailing blank line (wc -l would overcount) ---
echo ""
echo "Test 3: Multiple GPUs with trailing newline"
cat > "$MOCK_DIR/nvidia-smi" <<'MOCKEOF'
#!/bin/bash
if [[ "$1" == "--list-gpus" ]]; then
    echo "GPU 0: NVIDIA GeForce RTX 5090 (UUID: gpu-aaa)"
    echo "GPU 1: NVIDIA GeForce RTX 5090 (UUID: gpu-bbb)"
    echo "GPU 2: NVIDIA GeForce RTX 5090 (UUID: gpu-ccc)"
    echo "GPU 3: NVIDIA GeForce RTX 5090 (UUID: gpu-ddd)"
    echo ""
elif [[ "$1" == "--query-gpu" ]]; then
    echo "NVIDIA GeForce RTX 5090"
fi
MOCKEOF
chmod +x "$MOCK_DIR/nvidia-smi"

GPU_COUNT=$(nvidia-smi --list-gpus | grep -c "GPU")
assert_eq "4-GPU count with trailing blank line" "4" "$GPU_COUNT"

# Verify old wc -l approach would have overcounted
OLD_COUNT=$(nvidia-smi --list-gpus | wc -l)
assert_eq "Old wc -l would give 5 (wrong)" "5" "$OLD_COUNT"

# --- Test 4: 8 GPUs ---
echo ""
echo "Test 4: Eight GPUs"
cat > "$MOCK_DIR/nvidia-smi" <<'MOCK8'
#!/bin/bash
if [[ "$1" == "--list-gpus" ]]; then
    for i in $(seq 0 7); do
        echo "GPU $i: NVIDIA A100-SXM4-80GB (UUID: gpu-$i)"
    done
elif [[ "$1" == "--query-gpu" ]]; then
    echo "NVIDIA A100-SXM4-80GB"
fi
MOCK8
chmod +x "$MOCK_DIR/nvidia-smi"

GPU_COUNT=$(nvidia-smi --list-gpus | grep -c "GPU")
assert_eq "8-GPU count" "8" "$GPU_COUNT"

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