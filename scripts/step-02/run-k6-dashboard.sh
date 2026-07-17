#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-02"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Run ID file does not exist. Start the immediate server first."
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-02/${RUN_ID}"
REPORT_FILE="${RESULT_DIR}/k6-report.html"
SUMMARY_FILE="${RESULT_DIR}/k6-summary.json"
RAW_METRICS_FILE="${RESULT_DIR}/k6-metrics.json"

mkdir -p "${RESULT_DIR}"
cd "${PROJECT_ROOT}"

if ! curl -fsS http://localhost:9090/-/ready >/dev/null; then
  echo "Prometheus is not ready. Run: bash scripts/observability/start.sh"
  exit 1
fi

echo "Live dashboard: http://127.0.0.1:5665"
echo "Grafana dashboard: http://localhost:3000/d/step-02-immediate-shutdown"
echo "Run ID: ${RUN_ID}"
echo "Stop the server after the in-flight requests have started."

K6_WEB_DASHBOARD=true \
K6_WEB_DASHBOARD_OPEN=true \
K6_WEB_DASHBOARD_PERIOD=1s \
K6_WEB_DASHBOARD_EXPORT="${REPORT_FILE}" \
K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write" \
K6_PROMETHEUS_RW_PUSH_INTERVAL=1s \
RUN_ID="${RUN_ID}" \
  k6 run \
  --out experimental-prometheus-rw \
  --out "json=${RAW_METRICS_FILE}" \
  --summary-export "${SUMMARY_FILE}" \
  k6/step-02-immediate-shutdown.js

echo "HTML report: ${REPORT_FILE}"
echo "JSON summary: ${SUMMARY_FILE}"
