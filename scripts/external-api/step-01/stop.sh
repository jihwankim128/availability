#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/external-api/step-01"
PID_FILE="${RUNTIME_DIR}/server.pid"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/external-api/step-01/docker-compose.yml"

if [[ -f "${PID_FILE}" ]]; then
  SERVER_PID="$(<"${PID_FILE}")"
  if kill -0 "${SERVER_PID}" 2>/dev/null; then
    kill -TERM "${SERVER_PID}"
    echo "SIGTERM sent to External API Step 1 server. PID=${SERVER_PID}"

    for _ in {1..30}; do
      if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
  fi
  rm -f "${PID_FILE}"
fi

docker compose -f "${COMPOSE_FILE}" down --remove-orphans
echo "External API Step 1 server and WireMock stopped. Observability containers remain running."
