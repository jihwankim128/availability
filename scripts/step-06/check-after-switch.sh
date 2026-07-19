#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-06"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Step 6 runtime files do not exist."
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-06/${RUN_ID}"
COOKIE_FILE="${RESULT_DIR}/cookies.txt"
AFTER_FILE="${RESULT_DIR}/session-after-switch.json"

if [[ ! -f "${COOKIE_FILE}" ]]; then
  echo "Cookie file does not exist. Run the login script first."
  exit 1
fi

HTTP_STATUS="$(curl -sS \
  -b "${COOKIE_FILE}" \
  -o "${AFTER_FILE}" \
  -w '%{http_code}' \
  http://localhost:8080/api/session/me)"

cat "${AFTER_FILE}"
echo

if [[ "${HTTP_STATUS}" == "401" ]]; then
  echo "Expected result: local session was lost after switching to Green. HTTP ${HTTP_STATUS}"
  exit 0
fi

echo "Unexpected result: the local session should be unavailable on Green. HTTP ${HTTP_STATUS}"
exit 1
