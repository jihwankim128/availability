#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-07"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"
USERNAME="${USERNAME:-crew}"

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Start the Step 7 Blue server first."
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-07/${RUN_ID}"
COOKIE_FILE="${RESULT_DIR}/cookies.txt"
LOGIN_FILE="${RESULT_DIR}/session-login.json"
BEFORE_FILE="${RESULT_DIR}/session-before-switch.json"

curl -fsS \
  -c "${COOKIE_FILE}" \
  -X POST \
  "http://localhost:8080/api/session/login?username=${USERNAME}" \
  >"${LOGIN_FILE}"

curl -fsS \
  -b "${COOKIE_FILE}" \
  http://localhost:8080/api/session/me \
  >"${BEFORE_FILE}"

echo "Redis-backed session created on Blue."
cat "${BEFORE_FILE}"
echo
echo "Now run: bash scripts/step-07/deploy-green.sh"
