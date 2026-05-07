#!/bin/bash

# GPU Count detection
GPU_COUNT=$(nvidia-smi --list-gpus | wc -l)
export GPU_COUNT

# Segment Size detection
if [ -z "${SEGMENT_SIZE:-}" ]; then
    GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -n1)
    if echo "$GPU_NAME" | grep -q "5090"; then
        export SEGMENT_SIZE=21
    elif echo "$GPU_NAME" | grep -q "4090"; then
        export SEGMENT_SIZE=19
    elif echo "$GPU_NAME" | grep -q "2080"; then
        export SEGMENT_SIZE=17
    else
        export SEGMENT_SIZE=21  # default
    fi
    echo "Auto-detected: GPU=$GPU_NAME, SEGMENT_SIZE=$SEGMENT_SIZE"
else
    echo "Using override: SEGMENT_SIZE=$SEGMENT_SIZE"
fi