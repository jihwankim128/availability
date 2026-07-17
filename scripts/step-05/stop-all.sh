#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-05"
BLUE_PID_FILE="${RUNTIME_DIR}/blue.pid"
GREEN_PID_FILE="${RUNTIME_DIR}/green.pid"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/step-05/docker-compose.yml"

stop_server() {
  local name="$1"
  local pid_file="$2"

  if [[ ! -f "${pid_file}" ]]; then
    return
  fi

  local pid
  pid="$(<"${pid_file}")"
  if kill -0 "${pid}" 2>/dev/null; then
    kill -TERM "${pid}"
    echo "SIGTERM sent to ${name}. PID=${pid}"

    for _ in {1..50}; do
      if ! kill -0 "${pid}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
  fi

  rm -f "${pid_file}"
}

stop_server "Blue" "${BLUE_PID_FILE}"
stop_server "Green" "${GREEN_PID_FILE}"
docker compose -f "${COMPOSE_FILE}" down --remove-orphans
echo "Step 5 Blue, Green, and Nginx stopped."
