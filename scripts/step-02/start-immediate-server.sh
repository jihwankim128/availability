#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-02"
PID_FILE="${RUNTIME_DIR}/server.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
JAR_FILE="${PROJECT_ROOT}/build/libs/availability-0.0.1-SNAPSHOT.jar"

cd "${PROJECT_ROOT}"
./gradlew bootJar
mkdir -p "${RUNTIME_DIR}"

if [[ -f "${PID_FILE}" ]] && kill -0 "$(<"${PID_FILE}")" 2>/dev/null; then
  echo "Immediate server is already running. PID=$(<"${PID_FILE}")"
  exit 1
fi

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULT_DIR="${PROJECT_ROOT}/results/step-02/${RUN_ID}"
LOG_FILE="${RESULT_DIR}/server.log"
mkdir -p "${RESULT_DIR}"
echo "${RUN_ID}" >"${RUN_ID_FILE}"

nohup env APP_VERSION=v1 INSTANCE_ID=immediate \
  java -jar "${JAR_FILE}" --spring.profiles.active=immediate \
  >"${LOG_FILE}" 2>&1 &

SERVER_PID=$!
echo "${SERVER_PID}" >"${PID_FILE}"

for _ in {1..30}; do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "Server process exited before becoming ready. Check ${LOG_FILE}"
    exit 1
  fi

  SERVER_INFO="$(curl -fsS http://localhost:8080/api/info 2>/dev/null || true)"
  if [[ "${SERVER_INFO}" == *'"instanceId":"immediate"'* ]]; then
    echo "Immediate server started. PID=${SERVER_PID}"
    echo "Run ID: ${RUN_ID}"
    echo "Log: ${LOG_FILE}"
    exit 0
  fi
  sleep 1
done

echo "Server did not become ready. Check ${LOG_FILE}"
kill -TERM "${SERVER_PID}" 2>/dev/null || true
exit 1
