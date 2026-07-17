#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-03"
PID_FILE="${RUNTIME_DIR}/server.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "PID file does not exist: ${PID_FILE}"
  exit 1
fi

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Run ID file does not exist: ${RUN_ID_FILE}"
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
LOG_FILE="${PROJECT_ROOT}/results/step-03/${RUN_ID}/server.log"
SERVER_PID="$(<"${PID_FILE}")"
if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  echo "Server is not running. PID=${SERVER_PID}"
  exit 1
fi

ANNOTATION_TIME="$(date +%s)000"
curl -fsS \
  -u admin:admin \
  -H "Content-Type: application/json" \
  -X POST \
  -d "{\"dashboardUID\":\"step-03-graceful-shutdown\",\"time\":${ANNOTATION_TIME},\"tags\":[\"shutdown\",\"${RUN_ID}\"],\"text\":\"SIGTERM (${RUN_ID})\"}" \
  http://localhost:3000/api/annotations \
  >/dev/null 2>&1 || true

kill -TERM "${SERVER_PID}"
echo "SIGTERM sent to graceful server. Waiting for active requests. PID=${SERVER_PID}"

for _ in {1..50}; do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    rm -f "${PID_FILE}"
    echo "Graceful server stopped after active requests completed."
    echo "Log: ${LOG_FILE}"
    exit 0
  fi
  sleep 1
done

echo "Server is still running after the graceful shutdown timeout. PID=${SERVER_PID}"
exit 1
