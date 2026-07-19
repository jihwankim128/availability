#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RUNTIME_DIR="${PROJECT_ROOT}/build/step-06"
RUN_ID_FILE="${RUNTIME_DIR}/run-id"

if [[ ! -f "${RUN_ID_FILE}" ]]; then
  echo "Run ID file does not exist. Start Blue first."
  exit 1
fi

if ! curl -fsS http://localhost:9090/-/ready >/dev/null; then
  echo "Prometheus is not ready. Run: bash scripts/observability/start.sh"
  exit 1
fi

RUN_ID="$(<"${RUN_ID_FILE}")"
RESULT_DIR="${PROJECT_ROOT}/results/step-06/${RUN_ID}"
SUMMARY_FILE="${RESULT_DIR}/k6-summary.json"
RAW_METRICS_FILE="${RESULT_DIR}/k6-metrics.json"

mkdir -p "${RESULT_DIR}"
cd "${PROJECT_ROOT}"

echo "Grafana: http://localhost:3000/d/session-continuity"
echo "Run ID: ${RUN_ID}"
echo "While k6 is running, execute: bash scripts/step-06/deploy-green.sh"

K6_PROMETHEUS_RW_SERVER_URL="http://localhost:9090/api/v1/write" \
K6_PROMETHEUS_RW_PUSH_INTERVAL=1s \
K6_PROMETHEUS_RW_STALE_MARKERS=true \
RUN_ID="${RUN_ID}" \
  k6 run \
  --out experimental-prometheus-rw \
  --out "json=${RAW_METRICS_FILE}" \
  --summary-export "${SUMMARY_FILE}" \
  k6/step-06-local-session-loss.js

echo "JSON summary: ${SUMMARY_FILE}"
