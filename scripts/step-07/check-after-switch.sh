#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-07"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Step 7 runtime files do not exist."
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-07/${RUN_ID}"
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

if [[ "${HTTP_STATUS}" == "200" ]] && \
   grep -q '"version":"v2"' "${AFTER_FILE}" && \
   grep -q '"instanceId":"green"' "${AFTER_FILE}"; then
  echo "Expected result: the Redis session remained available on Green. HTTP ${HTTP_STATUS}"
  exit 0
fi

echo "Unexpected result: the Redis session should be available from Green. HTTP ${HTTP_STATUS}"
exit 1
