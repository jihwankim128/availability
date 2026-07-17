#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-04"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Run ID file does not exist. Start the v1 server first."
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-04/${RUN_ID}"
REPORT_FILE="${RESULT_DIR}/k6-report.html"
SUMMARY_FILE="${RESULT_DIR}/k6-summary.json"
RAW_METRICS_FILE="${RESULT_DIR}/k6-metrics.json"

mkdir -p "${RESULT_DIR}"
cd "${PROJECT_ROOT}"

echo "Live dashboard: http://127.0.0.1:5665"
echo "Run ID: ${RUN_ID}"
echo "While k6 is running, execute: bash scripts/step-04/deploy-v2-server.sh"

K6_WEB_DASHBOARD=true \
K6_WEB_DASHBOARD_OPEN=true \
K6_WEB_DASHBOARD_PERIOD=1s \
K6_WEB_DASHBOARD_EXPORT="${REPORT_FILE}" \
RUN_ID="${RUN_ID}" \
  k6 run \
  --out "json=${RAW_METRICS_FILE}" \
  --summary-export "${SUMMARY_FILE}" \
  k6/step-04-single-server-redeploy.js

echo "HTML report: ${REPORT_FILE}"
echo "JSON summary: ${SUMMARY_FILE}"
