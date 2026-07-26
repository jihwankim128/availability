#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/external-api/step-01"
PID_FILE="${RUNTIME_DIR}/server.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
JAR_FILE="${PROJECT_ROOT}/build/libs/availability-0.0.1-SNAPSHOT.jar"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/external-api/step-01/docker-compose.yml"

cd "${PROJECT_ROOT}"
./gradlew bootJar
mkdir -p "${RUNTIME_DIR}"

if [[ -f "${PID_FILE}" ]] && kill -0 "$(<"${PID_FILE}")" 2>/dev/null; then
  echo "External API Step 1 server is already running. PID=$(<"${PID_FILE}")"
  exit 1
fi

docker compose -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true

for PORT in 8080 9091; do
  if nc -z localhost "${PORT}" 2>/dev/null; then
    echo "Port ${PORT} is already in use. Stop the previous lab first."
    exit 1
  fi
done

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULT_DIR="${PROJECT_ROOT}/results/external-api/step-01/${RUN_ID}"
SERVER_LOG_FILE="${RESULT_DIR}/server.log"
mkdir -p "${RESULT_DIR}"
echo "${RUN_ID}" >"${RUN_ID_FILE}"

docker compose -f "${COMPOSE_FILE}" up -d external-api

for _ in {1..30}; do
  if curl -fsS http://localhost:9091/external/products/featured >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

if ! curl -fsS http://localhost:9091/external/products/featured >/dev/null; then
  echo "WireMock did not become ready."
  docker compose -f "${COMPOSE_FILE}" logs external-api
  exit 1
fi

nohup env EXTERNAL_API_BASE_URL=http://localhost:9091 EXPERIMENT_RUN_ID="${RUN_ID}" \
  java -jar "${JAR_FILE}" \
  --spring.profiles.active=external-api \
  --server.port=8080 \
  >"${SERVER_LOG_FILE}" 2>&1 &

SERVER_PID=$!
echo "${SERVER_PID}" >"${PID_FILE}"

for _ in {1..30}; do
  if ! kill -0 "${SERVER_PID}" 2>/dev/null; then
    echo "Server exited before becoming ready. Check ${SERVER_LOG_FILE}"
    exit 1
  fi

  READINESS="$(curl -fsS http://localhost:8080/actuator/health/readiness 2>/dev/null || true)"
  FEATURED_PRODUCT="$(curl -fsS http://localhost:8080/api/external/featured-product 2>/dev/null || true)"
  NORMAL_API="$(curl -fsS http://localhost:8080/api/info 2>/dev/null || true)"
  if [[ "${READINESS}" == *'"status":"UP"'* ]] && \
     [[ "${FEATURED_PRODUCT}" == *'"id":"featured-1"'* ]] && \
     [[ "${NORMAL_API}" == *'"version"'* ]]; then
    echo "External API Step 1 server and WireMock started. PID=${SERVER_PID}"
    echo "Run ID: ${RUN_ID}"
    echo "Application: http://localhost:8080"
    echo "Independent API: http://localhost:8080/api/info"
    echo "WireMock: http://localhost:9091"
    echo "Log: ${SERVER_LOG_FILE}"
    exit 0
  fi
  sleep 1
done

echo "External API Step 1 server did not become ready. Check ${SERVER_LOG_FILE}"
exit 1
