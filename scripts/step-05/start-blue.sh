#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-05"
NGINX_CONFIG_DIR="${RUNTIME_DIR}/nginx"
BLUE_PID_FILE="${RUNTIME_DIR}/blue.pid"
GREEN_PID_FILE="${RUNTIME_DIR}/green.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
JAR_FILE="${PROJECT_ROOT}/build/libs/availability-0.0.1-SNAPSHOT.jar"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/step-05/docker-compose.yml"
NGINX_TEMPLATE="${PROJECT_ROOT}/deploy/step-05/nginx/default.conf.template"

cd "${PROJECT_ROOT}"
./gradlew bootJar
mkdir -p "${RUNTIME_DIR}" "${NGINX_CONFIG_DIR}"

for PID_FILE in "${BLUE_PID_FILE}" "${GREEN_PID_FILE}"; do
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(<"${PID_FILE}")" 2>/dev/null; then
    echo "Step 5 server is already running. PID=$(<"${PID_FILE}")"
    exit 1
  fi
done

docker compose -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true

if curl -sS --connect-timeout 1 -o /dev/null http://localhost:8080 2>/dev/null; then
  echo "Port 8080 is already in use. Stop the previous lab server first."
  exit 1
fi

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULT_DIR="${PROJECT_ROOT}/results/step-05/${RUN_ID}"
BLUE_LOG_FILE="${RESULT_DIR}/server-blue.log"
mkdir -p "${RESULT_DIR}"
echo "${RUN_ID}" >"${RUN_ID_FILE}"

nohup env APP_VERSION=v1 INSTANCE_ID=blue \
  java -jar "${JAR_FILE}" --spring.profiles.active=blue-green --server.port=8081 \
  >"${BLUE_LOG_FILE}" 2>&1 &

BLUE_PID=$!
echo "${BLUE_PID}" >"${BLUE_PID_FILE}"

for _ in {1..30}; do
  if ! kill -0 "${BLUE_PID}" 2>/dev/null; then
    echo "Blue exited before becoming ready. Check ${BLUE_LOG_FILE}"
    exit 1
  fi

  BLUE_READINESS="$(curl -fsS http://localhost:8081/actuator/health/readiness 2>/dev/null || true)"
  BLUE_INFO="$(curl -fsS http://localhost:8081/api/info 2>/dev/null || true)"
  if [[ "${BLUE_READINESS}" == *'"status":"UP"'* ]] && \
     [[ "${BLUE_INFO}" == *'"version":"v1"'* ]] && \
     [[ "${BLUE_INFO}" == *'"instanceId":"blue"'* ]]; then
    break
  fi
  sleep 1
done

BLUE_READINESS="$(curl -fsS http://localhost:8081/actuator/health/readiness 2>/dev/null || true)"
BLUE_INFO="$(curl -fsS http://localhost:8081/api/info 2>/dev/null || true)"
if [[ "${BLUE_READINESS}" != *'"status":"UP"'* ]] || \
   [[ "${BLUE_INFO}" != *'"instanceId":"blue"'* ]]; then
  echo "Blue did not become ready. Check ${BLUE_LOG_FILE}"
  kill -TERM "${BLUE_PID}" 2>/dev/null || true
  exit 1
fi

sed 's/__BACKEND_PORT__/8081/g' "${NGINX_TEMPLATE}" >"${NGINX_CONFIG_DIR}/default.conf"
docker compose -f "${COMPOSE_FILE}" up -d

for _ in {1..30}; do
  PROXY_READINESS="$(curl -fsS http://localhost:8080/actuator/health/readiness 2>/dev/null || true)"
  PROXY_INFO="$(curl -fsS http://localhost:8080/api/info 2>/dev/null || true)"
  if [[ "${PROXY_READINESS}" == *'"status":"UP"'* ]] && \
     [[ "${PROXY_INFO}" == *'"version":"v1"'* ]] && \
     [[ "${PROXY_INFO}" == *'"instanceId":"blue"'* ]]; then
    echo "Blue v1 and Nginx proxy started. Blue PID=${BLUE_PID}"
    echo "Run ID: ${RUN_ID}"
    echo "Proxy: http://localhost:8080"
    echo "Blue direct: http://localhost:8081"
    echo "Log: ${BLUE_LOG_FILE}"
    exit 0
  fi
  sleep 1
done

echo "Nginx did not route traffic to Blue."
docker compose -f "${COMPOSE_FILE}" logs proxy
exit 1
