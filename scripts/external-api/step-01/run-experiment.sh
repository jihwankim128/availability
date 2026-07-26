#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/external-api/step-01"
PID_FILE="${RUNTIME_DIR}/server.pid"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"

if [[ ! -f "${PID_FILE}" ]] || ! kill -0 "$(<"${PID_FILE}")" 2>/dev/null; then
  echo "External API Step 1 server is not running. Run: bash scripts/external-api/step-01/start.sh"
  exit 1
fi

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Run ID file does not exist. Start External API Step 1 first."
  exit 1
fi

if ! curl -fsS http://localhost:9090/-/ready >/dev/null; then
  echo "Prometheus is not ready. Run: bash scripts/observability/start.sh"
  exit 1
fi

if ! curl -fsS http://localhost:9091/external/products/featured >/dev/null; then
  echo "WireMock is not ready. Run: bash scripts/external-api/step-01/start.sh"
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
CLIENT_TIMEOUT="${CLIENT_TIMEOUT:-3s}"
RESULT_DIR="${PROJECT_ROOT}/results/external-api/step-01/${RUN_ID}"
SUMMARY_FILE="${RESULT_DIR}/k6-summary.json"
RAW_METRICS_FILE="${RESULT_DIR}/k6-metrics.json"
REPORT_FILE="${RESULT_DIR}/k6-report.html"

mkdir -p "${RESULT_DIR}"
cd "${PROJECT_ROOT}"

echo "Run ID: ${RUN_ID}"
echo "Timeline: 0~15s normal, 15~40s external API 5s delay, 40~60s recovery"
echo "Load: external API 10 RPS + independent /api/info 2 RPS"
echo "Client timeout: ${CLIENT_TIMEOUT} for both API requests"
echo "Availability target: /api/info returns 200 within 1 second"
echo "Grafana: http://localhost:3000/d/external-api-step-01-latency-propagation"

K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write" \
K6_PROMETHEUS_RW_PUSH_INTERVAL=1s \
K6_PROMETHEUS_RW_TREND_STATS="avg,p(95),max" \
K6_PROMETHEUS_RW_STALE_MARKERS=true \
K6_WEB_DASHBOARD=true \
K6_WEB_DASHBOARD_PERIOD=1s \
K6_WEB_DASHBOARD_EXPORT="${REPORT_FILE}" \
RUN_ID="${RUN_ID}" \
CLIENT_TIMEOUT="${CLIENT_TIMEOUT}" \
  k6 run \
  --out experimental-prometheus-rw \
  --out "json=${RAW_METRICS_FILE}" \
  --summary-export "${SUMMARY_FILE}" \
  k6/external-api/step-01-latency-propagation.js

echo "JSON summary: ${SUMMARY_FILE}"
echo "HTML report: ${REPORT_FILE}"
