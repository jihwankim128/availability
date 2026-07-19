#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/observability/docker-compose.yml"

docker compose -f "${COMPOSE_FILE}" up -d

for _ in {1..60}; do
  PROMETHEUS_READY=false
  GRAFANA_READY=false

  if curl -fsS http://localhost:9090/-/ready >/dev/null 2>&1; then
    PROMETHEUS_READY=true
  fi
  if curl -fsS http://localhost:3000/api/health >/dev/null 2>&1; then
    GRAFANA_READY=true
  fi

  if [[ "${PROMETHEUS_READY}" == true && "${GRAFANA_READY}" == true ]]; then
    echo "Prometheus: http://localhost:9090"
    echo "Grafana shutdown dashboard: http://localhost:3000/d/step-02-immediate-shutdown"
    echo "Grafana session dashboard: http://localhost:3000/d/session-continuity"
    echo "Grafana login: admin / admin"
    exit 0
  fi

  sleep 1
done

echo "Observability stack did not become ready."
docker compose -f "${COMPOSE_FILE}" ps
exit 1
