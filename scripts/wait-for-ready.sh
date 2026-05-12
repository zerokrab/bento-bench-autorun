#!/bin/bash
set -e

# Defaults if variables are not set
PORT=${REST_API_PORT:-8000}
LOG_FILE=${LOG_DIR:-/var/log}/rest-api.log
MAX_WAIT=120
INTERVAL=2
COUNT=0

echo "Waiting for Bento REST API to be ready on port $PORT..."

while [ $COUNT -lt $MAX_WAIT ]; do
  if curl -s "http://localhost:${PORT}/health" > /dev/null; then
    echo "Bento REST API is ready!"
    exit 0
  fi
  
  COUNT=$((COUNT + INTERVAL))
  sleep $INTERVAL
done

echo "Timeout reached: Bento REST API did not become ready within ${MAX_WAIT}s"
if [ -f "$LOG_FILE" ]; then
  echo "Dumping the last 50 lines of $LOG_FILE:"
  tail -n 50 "$LOG_FILE"
else
  echo "Log file $LOG_FILE not found."
fi
exit 1