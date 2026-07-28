#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/external-api/step-05"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
COMPOSE_FILE="${PROJECT_ROOT}/deploy/external-api/step-05/docker-compose.yml"

if [[ -f "${RUN_ID_FILE}" ]]; then
  RUN_ID="$(<"${RUN_ID_FILE}")"
  RESULT_DIR="${PROJECT_ROOT}/results/external-api/step-05/${RUN_ID}"
  mkdir -p "${RESULT_DIR}"
  docker compose -f "${COMPOSE_FILE}" logs --no-color application >"${RESULT_DIR}/server.log" 2>/dev/null || true
fi

docker compose -f "${COMPOSE_FILE}" down --remove-orphans
echo "External API Step 5 application and WireMock stopped. Observability containers remain running."
