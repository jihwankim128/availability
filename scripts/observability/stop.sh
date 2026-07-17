#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPOSE_FILE="${PROJECT_ROOT}/observability/docker-compose.yml"

docker compose -f "${COMPOSE_FILE}" down

echo "Prometheus and Grafana stopped. Data volumes were preserved."
