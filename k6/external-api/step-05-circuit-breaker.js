import http from 'k6/http';
import { check } from 'k6';
import { Counter, Gauge, Trend } from 'k6/metrics';

const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
const wireMockUrl = __ENV.WIREMOCK_URL || 'http://localhost:9091';
const runId = __ENV.RUN_ID || 'manual';
const clientTimeout = __ENV.CLIENT_TIMEOUT || '3s';
const availabilityTargetMs = Number(__ENV.AVAILABILITY_TARGET_MS || 1000);

const externalUserDuration = new Trend('external_user_duration', true);
const externalUserSuccess = new Counter('external_user_success');
const externalServerTimeout = new Counter('external_server_timeout');
const externalCircuitOpen = new Counter('external_circuit_open');
const externalClientTimeout = new Counter('external_client_timeout');
const normalApiDuration = new Trend('normal_api_duration', true);
const normalApiSuccess = new Counter('normal_api_success');
const normalApiFailure = new Counter('normal_api_failure');
const normalApiAvailable = new Counter('normal_api_available');
const normalApiUnavailable = new Counter('normal_api_unavailable');
const externalFaultSignal = new Gauge('external_fault_signal');
const externalRequestRateSignal = new Gauge('external_request_rate_signal');

export const options = {
  noConnectionReuse: true,
  systemTags: ['status', 'method', 'name'],
  tags: {
    run_id: runId,
    step: '05',
  },
  scenarios: {
    external_api_load: {
      executor: 'ramping-arrival-rate',
      exec: 'requestFeaturedProduct',
      startRate: 10,
      timeUnit: '1s',
      stages: [
        { target: 10, duration: '10s' },
        { target: 50, duration: '1s' },
        { target: 50, duration: '39s' },
        { target: 10, duration: '1s' },
        { target: 10, duration: '19s' },
      ],
      preAllocatedVUs: 250,
      maxVUs: 500,
      gracefulStop: '5s',
    },
    normal_api_probe: {
      executor: 'constant-arrival-rate',
      exec: 'requestNormalApi',
      rate: 2,
      timeUnit: '1s',
      duration: '70s',
      preAllocatedVUs: 20,
      maxVUs: 100,
      gracefulStop: '5s',
    },
    initialize_external_api: controlScenario('initializeExternalApi', '0s'),
    inject_external_delay: controlScenario('injectExternalDelay', '10s'),
    recover_external_api: controlScenario('recoverExternalApi', '50s'),
  },
  thresholds: {
    external_user_success: ['count>0'],
    external_server_timeout: ['count>0'],
    external_circuit_open: ['count>0'],
    external_client_timeout: ['count==0'],
    normal_api_success: ['count>0'],
    normal_api_failure: ['count==0'],
    normal_api_unavailable: ['count==0'],
    normal_api_duration: ['p(95)<1000'],
    dropped_iterations: ['count==0'],
  },
};

function controlScenario(exec, startTime) {
  return {
    executor: 'shared-iterations',
    exec,
    vus: 1,
    iterations: 1,
    startTime,
    maxDuration: '5s',
  };
}

export function requestFeaturedProduct() {
  const response = http.get(`${baseUrl}/api/external/featured-product`, {
    tags: {
      experiment: 'external-api-step-05-circuit-breaker',
      request_type: 'external_api',
      name: 'GET /api/external/featured-product',
    },
    timeout: clientTimeout,
  });
  const succeeded = response.status === 200;
  const serverTimedOut = response.status === 504;
  const circuitOpen = response.status === 503;
  const clientTimedOut = response.status === 0;

  externalUserDuration.add(response.timings.duration);
  externalUserSuccess.add(succeeded ? 1 : 0);
  externalServerTimeout.add(serverTimedOut ? 1 : 0);
  externalCircuitOpen.add(circuitOpen ? 1 : 0);
  externalClientTimeout.add(clientTimedOut ? 1 : 0);

  check(response, {
    '외부 기능이 정상 또는 의도한 실패로 빠르게 종료': (result) =>
      result.status === 200 || result.status === 503 || result.status === 504,
  });
}

export function requestNormalApi() {
  const response = http.get(`${baseUrl}/api/info`, {
    tags: {
      experiment: 'external-api-step-05-circuit-breaker',
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

export function initializeExternalApi() {
  setExternalMode('/__lab/control/normal');
  externalFaultSignal.add(0);
  externalRequestRateSignal.add(10);
}

export function injectExternalDelay() {
  setExternalMode('/__lab/control/slow');
  externalFaultSignal.add(1);
  externalRequestRateSignal.add(50);
}

export function recoverExternalApi() {
  setExternalMode('/__lab/control/normal');
  externalFaultSignal.add(0);
  externalRequestRateSignal.add(10);
}

export function teardown() {
  setExternalMode('/__lab/control/normal');
}

function setExternalMode(path) {
  const response = http.post(`${wireMockUrl}${path}`, null, {
    tags: {
      experiment: 'external-api-step-05-circuit-breaker',
      request_type: 'fault_control',
      name: `POST ${path}`,
    },
    timeout: '3s',
  });

  if (response.status !== 200) {
    throw new Error(`WireMock 상태 변경 실패: path=${path}, status=${response.status}`);
  }
}
