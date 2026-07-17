#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-04"
PID_FILE="${RUNTIME_DIR}/server.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
VERSION_FILE="${RUNTIME_DIR}/version"
JAR_FILE="${PROJECT_ROOT}/build/libs/availability-0.0.1-SNAPSHOT.jar"
DOWNTIME_SECONDS="${DOWNTIME_SECONDS:-5}"

if [[ ! -f "${PID_FILE}" ]] || [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Step 4 runtime files do not exist. Start v1 first."
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-04/${RUN_ID}"
V2_LOG_FILE="${RESULT_DIR}/server-v2.log"
SERVER_PID="$(<"${PID_FILE}")"

if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
  echo "v1 is not running. PID=${SERVER_PID}"
  exit 1
fi

kill -TERM "${SERVER_PID}"
echo "SIGTERM sent to v1. Waiting for graceful shutdown. PID=${SERVER_PID}"

for _ in {1..50}; do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    break
  fi
  sleep 1
done

if kill -0 "${SERVER_PID}" 2>/dev/null; then
  echo "v1 is still running after the graceful shutdown timeout. PID=${SERVER_PID}"
  exit 1
fi

rm -f "${PID_FILE}"
echo "v1 stopped. Simulating a ${DOWNTIME_SECONDS}s deployment gap."
sleep "${DOWNTIME_SECONDS}"

nohup env APP_VERSION=v2 INSTANCE_ID=single-v2 \
  java -jar "${JAR_FILE}" --spring.profiles.active=single-server \
  >"${V2_LOG_FILE}" 2>&1 &

V2_PID=$!
echo "${V2_PID}" >"${PID_FILE}"
echo "v2" >"${VERSION_FILE}"

for _ in {1..30}; do
  if ! kill -0 "${V2_PID}" 2>/dev/null; then
    echo "v2 exited before becoming ready. Check ${V2_LOG_FILE}"
    exit 1
  fi

  SERVER_INFO="$(curl -fsS http://localhost:8080/api/info 2>/dev/null || true)"
  if [[ "${SERVER_INFO}" == *'"version":"v2"'* ]] && [[ "${SERVER_INFO}" == *'"instanceId":"single-v2"'* ]]; then
    echo "Single server v2 started. PID=${V2_PID}"
    echo "Log: ${V2_LOG_FILE}"
    exit 0
  fi
  sleep 1
done

echo "v2 did not become ready. Check ${V2_LOG_FILE}"
kill -TERM "${V2_PID}" 2>/dev/null || true
exit 1
