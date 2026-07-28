#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/external-api/step-05"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/external-api/step-05/docker-compose.yml"

cd "${PROJECT_ROOT}"
./gradlew bootJar
mkdir -p "${RUNTIME_DIR}"

docker compose -f "${COMPOSE_FILE}" down --remove-orphans >/dev/null 2>&1 || true

for PORT in 8080 9091; do
  if nc -z localhost "${PORT}" 2>/dev/null; then
    echo "Port ${PORT} is already in use. Stop the previous lab first."
    exit 1
  fi
done

RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
RESULT_DIR="${PROJECT_ROOT}/results/external-api/step-05/${RUN_ID}"
SERVER_LOG_FILE="${RESULT_DIR}/server.log"
mkdir -p "${RESULT_DIR}"
echo "${RUN_ID}" >"${RUN_ID_FILE}"

EXPERIMENT_RUN_ID="${RUN_ID}" docker compose -f "${COMPOSE_FILE}" up -d

for _ in {1..60}; do
  READINESS="$(curl -fsS http://localhost:8080/actuator/health/readiness 2>/dev/null || true)"
  FEATURED_PRODUCT="$(curl -fsS http://localhost:8080/api/external/featured-product 2>/dev/null || true)"
  NORMAL_API="$(curl -fsS http://localhost:8080/api/info 2>/dev/null || true)"
  if [[ "${READINESS}" == *'"status":"UP"'* ]] && \
     [[ "${FEATURED_PRODUCT}" == *'"id":"featured-1"'* ]] && \
     [[ "${NORMAL_API}" == *'"version"'* ]]; then
    docker compose -f "${COMPOSE_FILE}" logs --no-color application >"${SERVER_LOG_FILE}"
    echo "External API Step 5 application and WireMock started."
    echo "Run ID: ${RUN_ID}"
    echo "Application: http://localhost:8080"
    echo "WireMock: http://localhost:9091"
    echo "Circuit Breaker: 20-call window, 50% failure, 10-second open state"
    echo "Read Timeout: 1 second"
    echo "Tomcat max threads: 40"
    echo "Log: ${SERVER_LOG_FILE}"
    exit 0
  fi
  sleep 1
done

docker compose -f "${COMPOSE_FILE}" logs --no-color >"${SERVER_LOG_FILE}"
echo "External API Step 5 application did not become ready. Check ${SERVER_LOG_FILE}"
exit 1
