#!/usr/bin/env bash
# Run bento-bench with the configured suite and capture results.
#
# Called from entrypoint.sh step 7. Constructs the bento-bench command
# based on environment variables and propagates the exit code so the
# container exit code reflects the benchmark result.
#
# On failure, dumps agent logs to stdout for diagnosis.
#
# Environment variables:
#   BENCH_SUITE   - (required) Benchmark suite name to run
#   CHECK_TASKDB  - If "true", pass --check-taskdb flag
#   BENCH_JSON    - If set, pass --json $BENCH_JSON for structured output

set -euo pipefail

# --- Validate required env ---
if [ -z "${BENCH_SUITE:-}" ]; then
    echo "Error: BENCH_SUITE environment variable is required."
    exit 1
fi

# --- Build command arguments ---
ARGS=(run --fetch "${BENCH_SUITE}")

if [ "${CHECK_TASKDB:-}" = "true" ]; then
    ARGS+=(--check-taskdb)
fi

if [ -n "${BENCH_JSON:-}" ]; then
    ARGS+=(--json "${BENCH_JSON}")
fi

echo "Running bento-bench with args: ${ARGS[*]}"

# --- Execute bento-bench ---
# Temporarily disable exit-on-error so we can capture the exit code.
set +e
bento-bench "${ARGS[@]}"
EXIT_CODE=$?
set -e

# --- Failure handling: dump agent logs ---
if [ "${EXIT_CODE}" -ne 0 ]; then
    echo "bento-bench failed with exit code ${EXIT_CODE}. Dumping agent logs..."
    if [ -d "/tmp/bento-logs" ]; then
        tail -n 100 /tmp/bento-logs/*.log 2>/dev/null || echo "(no log files found in /tmp/bento-logs)"
    else
        echo "(log directory /tmp/bento-logs not found)"
    fi
fi

exit "${EXIT_CODE}"