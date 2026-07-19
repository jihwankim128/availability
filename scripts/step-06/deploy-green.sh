#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-06"
NGINX_CONFIG_DIR="${RUNTIME_DIR}/nginx"
BLUE_PID_FILE="${RUNTIME_DIR}/blue.pid"
GREEN_PID_FILE="${RUNTIME_DIR}/green.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
JAR_FILE="${PROJECT_ROOT}/build/libs/availability-0.0.1-SNAPSHOT.jar"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/step-06/docker-compose.yml"
NGINX_TEMPLATE="${PROJECT_ROOT}/deploy/step-06/nginx/default.conf.template"
ACTIVE_CONFIG="${NGINX_CONFIG_DIR}/default.conf"
BLUE_CONFIG_BACKUP="${NGINX_CONFIG_DIR}/default.conf.blue"
DRAIN_SECONDS="${DRAIN_SECONDS:-2}"
READINESS_PASSES="${READINESS_PASSES:-3}"
TRAFFIC_SWITCHED=false
ROLLBACK_ARMED=false

stop_green() {
  if [[ ! -f "${GREEN_PID_FILE}" ]]; then
    return
  fi

  local green_pid
  green_pid="$(<"${GREEN_PID_FILE}")"
  if kill -0 "${green_pid}" 2>/dev/null; then
    kill -TERM "${green_pid}" 2>/dev/null || true
    for _ in {1..50}; do
      if ! kill -0 "${green_pid}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
  fi
  rm -f "${GREEN_PID_FILE}"
}

rollback_before_switch() {
  local exit_code=$?

  if [[ "${exit_code}" -ne 0 ]] && \
     [[ "${ROLLBACK_ARMED}" == "true" ]] && \
     [[ "${TRAFFIC_SWITCHED}" == "false" ]]; then
    echo "Green deployment failed before traffic switch. Restoring Blue."
    if [[ -f "${BLUE_CONFIG_BACKUP}" ]]; then
      cp "${BLUE_CONFIG_BACKUP}" "${ACTIVE_CONFIG}"
      docker compose -f "${COMPOSE_FILE}" exec -T proxy nginx -t >/dev/null 2>&1 || true
      docker compose -f "${COMPOSE_FILE}" exec -T proxy nginx -s reload >/dev/null 2>&1 || true
    fi
    stop_green
    echo "Blue remains active."
  fi
}

trap rollback_before_switch EXIT

if [[ ! -f "${BLUE_PID_FILE}" ]] || [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Step 6 runtime files do not exist. Start Blue first."
  exit 1
fi

BLUE_PID="$(<"${BLUE_PID_FILE}")"
if ! kill -0 "${BLUE_PID}" 2>/dev/null; then
  echo "Blue is not running. PID=${BLUE_PID}"
  exit 1
fi

if [[ -f "${GREEN_PID_FILE}" ]] && kill -0 "$(<"${GREEN_PID_FILE}")" 2>/dev/null; then
  echo "Green is already running. PID=$(<"${GREEN_PID_FILE}")"
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-06/${RUN_ID}"
GREEN_LOG_FILE="${RESULT_DIR}/server-green.log"

nohup env APP_VERSION=v2 INSTANCE_ID=green \
  java -jar "${JAR_FILE}" \
  --spring.profiles.active="blue-green,session-local" \
  --server.port=8082 \
  >"${GREEN_LOG_FILE}" 2>&1 &

GREEN_PID=$!
echo "${GREEN_PID}" >"${GREEN_PID_FILE}"
ROLLBACK_ARMED=true
echo "Green v2 is starting. Blue continues serving traffic. Green PID=${GREEN_PID}"

READY_COUNT=0
for _ in {1..60}; do
  if ! kill -0 "${GREEN_PID}" 2>/dev/null; then
    echo "Green exited before becoming ready. Check ${GREEN_LOG_FILE}"
    exit 1
  fi

  GREEN_READINESS="$(curl -fsS http://localhost:8082/actuator/health/readiness 2>/dev/null || true)"
  GREEN_INFO="$(curl -fsS http://localhost:8082/api/info 2>/dev/null || true)"
  if [[ "${GREEN_READINESS}" == *'"status":"UP"'* ]] && \
     [[ "${GREEN_INFO}" == *'"version":"v2"'* ]] && \
     [[ "${GREEN_INFO}" == *'"instanceId":"green"'* ]]; then
    READY_COUNT=$((READY_COUNT + 1))
    if [[ "${READY_COUNT}" -ge "${READINESS_PASSES}" ]]; then
      break
    fi
  else
    READY_COUNT=0
  fi
  sleep 1
done

if [[ "${READY_COUNT}" -lt "${READINESS_PASSES}" ]]; then
  echo "Green readiness did not pass ${READINESS_PASSES} consecutive checks. Blue remains active."
  exit 1
fi

echo "Green readiness passed ${READINESS_PASSES} consecutive checks."
cp "${ACTIVE_CONFIG}" "${BLUE_CONFIG_BACKUP}"
sed 's/__BACKEND_PORT__/8082/g' "${NGINX_TEMPLATE}" >"${NGINX_CONFIG_DIR}/default.conf.next"
mv "${NGINX_CONFIG_DIR}/default.conf.next" "${ACTIVE_CONFIG}"
docker compose -f "${COMPOSE_FILE}" exec -T proxy nginx -t
docker compose -f "${COMPOSE_FILE}" exec -T proxy nginx -s reload
echo "Nginx reloaded. Verifying Green through the proxy."

PROXY_READY_COUNT=0
for _ in {1..30}; do
  PROXY_READINESS="$(curl -fsS http://localhost:8080/actuator/health/readiness 2>/dev/null || true)"
  PROXY_INFO="$(curl -fsS http://localhost:8080/api/info 2>/dev/null || true)"
  if [[ "${PROXY_READINESS}" == *'"status":"UP"'* ]] && \
     [[ "${PROXY_INFO}" == *'"version":"v2"'* ]] && \
     [[ "${PROXY_INFO}" == *'"instanceId":"green"'* ]]; then
    PROXY_READY_COUNT=$((PROXY_READY_COUNT + 1))
    if [[ "${PROXY_READY_COUNT}" -ge "${READINESS_PASSES}" ]]; then
      TRAFFIC_SWITCHED=true
      break
    fi
  else
    PROXY_READY_COUNT=0
  fi
  sleep 1
done

if [[ "${TRAFFIC_SWITCHED}" != "true" ]]; then
  echo "Green could not be verified through Nginx."
  exit 1
fi

echo "Traffic switch to Green verified ${READINESS_PASSES} consecutive times."
sleep "${DRAIN_SECONDS}"
kill -TERM "${BLUE_PID}"
echo "SIGTERM sent to drained Blue. PID=${BLUE_PID}"

for _ in {1..50}; do
  if ! kill -0 "${BLUE_PID}" 2>/dev/null; then
    rm -f "${BLUE_PID_FILE}" "${BLUE_CONFIG_BACKUP}"
    trap - EXIT
    echo "Blue stopped after traffic switch. Green PID=${GREEN_PID}"
    echo "The Blue session now becomes unavailable on Green."
    exit 0
  fi
  sleep 1
done

trap - EXIT
echo "Blue is still running after the graceful shutdown timeout. Green remains active. PID=${BLUE_PID}"
exit 1
