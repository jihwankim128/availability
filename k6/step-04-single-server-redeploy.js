import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Gauge } from 'k6/metrics';

const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
const runId = __ENV.RUN_ID || 'manual';
const virtualUsers = Number(__ENV.VUS || 5);
const duration = __ENV.DURATION || '40s';
const requestIntervalSeconds = Number(__ENV.REQUEST_INTERVAL_SECONDS || 1);

const deploymentVersionSignal = new Gauge('deployment_version_signal');
const deploymentV1Response = new Counter('deployment_v1_response');
const deploymentV2Response = new Counter('deployment_v2_response');

export const options = {
  noConnectionReuse: true,
  tags: {
    deployment_mode: 'single-server',
    run_id: runId,
    step: '04',
  },
  scenarios: {
    continuous_requests: {
      executor: 'constant-vus',
      exec: 'sendContinuousRequests',
      vus: virtualUsers,
      duration,
      gracefulStop: '5s',
    },
  },
  thresholds: {
    http_req_failed: ['rate>0'],
    deployment_v1_response: ['count>0'],
    deployment_v2_response: ['count>0'],
  },
};

export function sendContinuousRequests() {
  const response = http.get(`${baseUrl}/api/info`, {
    tags: {
      experiment: 'step-04-single-server-redeploy',
      request_type: 'continuous',
    },
    timeout: '2s',
  });

  let version = 'unavailable';
  if (response.status === 200) {
    try {
      version = response.json('version');
    } catch (_) {
      version = 'unknown';
    }
  }

  const succeeded = response.status === 200 && (version === 'v1' || version === 'v2');
  const versionSignal = version === 'v1' ? 1 : version === 'v2' ? 2 : 0;

  deploymentVersionSignal.add(versionSignal);
  deploymentV1Response.add(version === 'v1' ? 1 : 0);
  deploymentV2Response.add(version === 'v2' ? 1 : 0);

  check(response, {
    '서버 응답 수신': () => succeeded,
  });

  sleep(requestIntervalSeconds);
}
