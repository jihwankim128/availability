import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Counter, Gauge, Trend } from 'k6/metrics';

const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
const runId = __ENV.RUN_ID || 'manual';
const requestRate = Number(__ENV.REQUEST_RATE || 10);
const normalApiRate = Number(__ENV.NORMAL_API_RATE || 2);
const clientTimeout = __ENV.CLIENT_TIMEOUT || '3s';
const availabilityTargetMs = Number(__ENV.AVAILABILITY_TARGET_MS || 1000);
const healthySeconds = Number(__ENV.HEALTHY_SECONDS || 15);
const faultSeconds = Number(__ENV.FAULT_SECONDS || 25);
const recoverySeconds = Number(__ENV.RECOVERY_SECONDS || 20);
const totalDurationSeconds = healthySeconds + faultSeconds + recoverySeconds;

const externalUserDuration = new Trend('external_user_duration', true);
const externalFailureDuration = new Trend('external_failure_duration', true);
const externalUserSuccess = new Counter('external_user_success');
const externalGatewayTimeout = new Counter('external_gateway_timeout');
const externalClientTimeout = new Counter('external_client_timeout');
const normalApiDuration = new Trend('normal_api_duration', true);
const normalApiSuccess = new Counter('normal_api_success');
const normalApiFailure = new Counter('normal_api_failure');
const normalApiAvailable = new Counter('normal_api_available');
const normalApiUnavailable = new Counter('normal_api_unavailable');
const externalConnectFaultSignal = new Gauge('external_connect_fault_signal');

export const options = {
  noConnectionReuse: true,
  systemTags: ['status', 'method', 'name'],
  tags: {
    run_id: runId,
    step: '02',
  },
  scenarios: {
    external_api_load: arrivalRateScenario(
      'requestFeaturedProductByPhase',
      requestRate,
      '0s',
      `${totalDurationSeconds}s`,
    ),
    normal_api_probe: arrivalRateScenario(
      'requestNormalApi',
      normalApiRate,
      '0s',
      `${totalDurationSeconds}s`,
    ),
  },
  thresholds: {
    external_user_success: ['count>0'],
    external_gateway_timeout: ['count>0'],
    external_client_timeout: ['count==0'],
    external_failure_duration: ['p(95)<1500'],
    normal_api_duration: ['p(95)<1000'],
    normal_api_unavailable: ['count==0'],
    dropped_iterations: ['count==0'],
  },
};

function arrivalRateScenario(exec, rate, startTime, duration) {
  return {
    executor: 'constant-arrival-rate',
    exec,
    rate,
    timeUnit: '1s',
    startTime,
    duration,
    preAllocatedVUs: Math.max(20, rate * 3),
    maxVUs: Math.max(60, rate * 6),
    gracefulStop: '5s',
  };
}

export function requestFeaturedProductByPhase() {
  const iteration = exec.scenario.iterationInTest;
  const faultStartsAt = requestRate * healthySeconds;
  const recoveryStartsAt = requestRate * (healthySeconds + faultSeconds);

  if (iteration >= faultStartsAt && iteration < recoveryStartsAt) {
    requestUnreachableFeaturedProduct();
    return;
  }

  requestHealthyFeaturedProduct();
}

function requestHealthyFeaturedProduct() {
  const response = requestExternal('/api/external/featured-product', 'normal');
  externalConnectFaultSignal.add(0);
  externalUserSuccess.add(response.status === 200 ? 1 : 0);

  check(response, {
    '정상 외부 API 사용 요청 성공': (result) => result.status === 200,
  });
}

function requestUnreachableFeaturedProduct() {
  const response = requestExternal('/api/external/unreachable-product', 'connect_failure');
  const gatewayTimedOut = response.status === 504;
  const clientTimedOut = response.status === 0;

  externalConnectFaultSignal.add(1);
  externalGatewayTimeout.add(gatewayTimedOut ? 1 : 0);
  externalClientTimeout.add(clientTimedOut ? 1 : 0);
  externalFailureDuration.add(response.timings.duration);

  check(response, {
    '서버가 Connect Timeout 후 504 응답': (result) => result.status === 504,
    'k6 Client Timeout 전에 서버 응답 수신': (result) => result.status !== 0,
  });
}

export function requestNormalApi() {
  const response = http.get(`${baseUrl}/api/info`, {
    tags: {
      experiment: 'external-api-step-02-connect-timeout',
      request_type: 'normal_api',
      name: 'GET /api/info',
    },
    timeout: clientTimeout,
  });
  const succeeded = response.status === 200;
  const available = succeeded && response.timings.duration <= availabilityTargetMs;

  normalApiDuration.add(response.timings.duration);
  normalApiSuccess.add(succeeded ? 1 : 0);
  normalApiFailure.add(succeeded ? 0 : 1);
  normalApiAvailable.add(available ? 1 : 0);
  normalApiUnavailable.add(available ? 0 : 1);

  check(response, {
    '정상 API HTTP 응답 성공': (result) => result.status === 200,
    '정상 API 1초 이내 응답': (result) =>
      result.status === 200 && result.timings.duration <= availabilityTargetMs,
  });
}

function requestExternal(path, phase) {
  const response = http.get(`${baseUrl}${path}`, {
    tags: {
      experiment: 'external-api-step-02-connect-timeout',
      request_type: 'external_api',
      phase,
      name: `GET ${path}`,
    },
    timeout: clientTimeout,
  });
  externalUserDuration.add(response.timings.duration, { phase });
  return response;
}
