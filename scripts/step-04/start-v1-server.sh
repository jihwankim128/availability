#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-04"
PID_FILE="${RUNTIME_DIR}/server.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
VERSION_FILE="${RUNTIME_DIR}/version"
JAR_FILE="${PROJECT_ROOT}/build/libs/availability-0.0.1-SNAPSHOT.jar"

cd "${PROJECT_ROOT}"
./gradlew bootJar
mkdir -p "${RUNTIME_DIR}"

if [[ -f "${PID_FILE}" ]] && kill -0 "$(<"${PID_FILE}")" 2>/dev/null; then
  echo "Step 4 server is already running. PID=$(<"${PID_FILE}")"
  exit 1
fi

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULT_DIR="${PROJECT_ROOT}/results/step-04/${RUN_ID}"
LOG_FILE="${RESULT_DIR}/server-v1.log"
mkdir -p "${RESULT_DIR}"
echo "${RUN_ID}" >"${RUN_ID_FILE}"

nohup env APP_VERSION=v1 INSTANCE_ID=single-v1 \
  java -jar "${JAR_FILE}" --spring.profiles.active=single-server \
  >"${LOG_FILE}" 2>&1 &

SERVER_PID=$!
echo "${SERVER_PID}" >"${PID_FILE}"
echo "v1" >"${VERSION_FILE}"

for _ in {1..30}; do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "v1 exited before becoming ready. Check ${LOG_FILE}"
    exit 1
  fi

  SERVER_INFO="$(curl -fsS http://localhost:8080/api/info 2>/dev/null || true)"
  if [[ "${SERVER_INFO}" == *'"version":"v1"'* ]] && [[ "${SERVER_INFO}" == *'"instanceId":"single-v1"'* ]]; then
    echo "Single server v1 started. PID=${SERVER_PID}"
    echo "Run ID: ${RUN_ID}"
    echo "Log: ${LOG_FILE}"
    exit 0
  fi
  sleep 1
done

echo "v1 did not become ready. Check ${LOG_FILE}"
kill -TERM "${SERVER_PID}" 2>/dev/null || true
exit 1
