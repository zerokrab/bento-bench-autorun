#!/usr/bin/env bash
# Log system specs (CPU, memory, OS, disk, GPU) for benchmark reproducibility.
set -euo pipefail

echo "=== System Specifications ==="
echo "Timestamp: $(date -u)"
echo "OS: $(uname -a)"
echo "Kernel: $(uname -r)"
echo "Hostname: $(hostname)"

echo "--- CPU ---"
if command -v lscpu >/dev/null 2>&1; then
    lscpu | grep -E 'Architecture|CPU\(s\)|Model name|CPU MHz|Vendor'
else
    echo "lscpu not found. CPU info unavailable."
fi

echo "--- Memory ---"
if command -v free >/dev/null 2>&1; then
    free -h
else
    echo "free command not found. Memory info unavailable."
fi

echo "--- Disk ---"
df -h / | grep '/'

echo "--- GPU ---"
if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
else
    echo "No NVIDIA GPU detected or nvidia-smi not found."
fi
echo "============================"