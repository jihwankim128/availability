#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-04"
PID_FILE="${RUNTIME_DIR}/server.pid"
VERSION_FILE="${RUNTIME_DIR}/version"

if [[ ! -f "${PID_FILE}" ]]; then
  echo "PID file does not exist: ${PID_FILE}"
  exit 1
fi

SERVER_PID="$(<"${PID_FILE}")"
SERVER_VERSION="unknown"
if [[ -f "${VERSION_FILE}" ]]; then
  SERVER_VERSION="$(<"${VERSION_FILE}")"
fi

if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  echo "Server is not running. PID=${SERVER_PID}"
  exit 1
fi

kill -TERM "${SERVER_PID}"
echo "SIGTERM sent to ${SERVER_VERSION}. PID=${SERVER_PID}"

for _ in {1..50}; do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    rm -f "${PID_FILE}" "${VERSION_FILE}"
    echo "${SERVER_VERSION} stopped."
    exit 0
  fi
  sleep 1
done

echo "Server is still running after the graceful shutdown timeout. PID=${SERVER_PID}"
exit 1
