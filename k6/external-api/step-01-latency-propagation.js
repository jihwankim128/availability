import http from 'k6/http';
import { check } from 'k6';
import { Counter, Gauge, Trend } from 'k6/metrics';

const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
const wireMockUrl = __ENV.WIREMOCK_URL || 'http://localhost:9091';
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
const externalUserSuccess = new Counter('external_user_success');
const externalUserFailure = new Counter('external_user_failure');
const normalApiDuration = new Trend('normal_api_duration', true);
const normalApiSuccess = new Counter('normal_api_success');
const normalApiFailure = new Counter('normal_api_failure');
const normalApiAvailable = new Counter('normal_api_available');
const normalApiUnavailable = new Counter('normal_api_unavailable');
const externalFaultSignal = new Gauge('external_fault_signal');

export const options = {
  noConnectionReuse: true,
  systemTags: ['status', 'method', 'name'],
  tags: {
    run_id: runId,
    step: '01',
  },
  scenarios: {
    external_api_load: {
      executor: 'constant-arrival-rate',
      exec: 'requestFeaturedProduct',
      rate: requestRate,
      timeUnit: '1s',
      duration: `${totalDurationSeconds}s`,
      preAllocatedVUs: 150,
      maxVUs: 300,
      gracefulStop: '20s',
    },
    normal_api_probe: {
      executor: 'constant-arrival-rate',
      exec: 'requestNormalApi',
      rate: normalApiRate,
      timeUnit: '1s',
      duration: `${totalDurationSeconds}s`,
      preAllocatedVUs: 30,
      maxVUs: 100,
      gracefulStop: '10s',
    },
    initialize_external_api: {
      executor: 'shared-iterations',
      exec: 'initializeExternalApi',
      vus: 1,
      iterations: 1,
      maxDuration: '5s',
    },
    inject_external_delay: {
      executor: 'shared-iterations',
      exec: 'injectExternalDelay',
      vus: 1,
      iterations: 1,
      startTime: `${healthySeconds}s`,
      maxDuration: '5s',
    },
    recover_external_api: {
      executor: 'shared-iterations',
      exec: 'recoverExternalApi',
      vus: 1,
      iterations: 1,
      startTime: `${healthySeconds + faultSeconds}s`,
      maxDuration: '5s',
    },
  },
  thresholds: {
    external_user_success: ['count>0'],
    external_user_failure: ['count>0'],
    external_user_duration: ['p(95)>2500'],
    normal_api_duration: ['p(95)>1000'],
    normal_api_unavailable: ['count>0'],
    dropped_iterations: ['count==0'],
  },
};

export function requestFeaturedProduct() {
  const response = http.get(`${baseUrl}/api/external/featured-product`, {
    tags: {
      experiment: 'external-api-step-01-latency-propagation',
      request_type: 'user_request',
    },
    timeout: clientTimeout,
  });

  externalUserDuration.add(response.timings.duration);
  externalUserSuccess.add(response.status === 200 ? 1 : 0);
  externalUserFailure.add(response.status === 200 ? 0 : 1);

  check(response, {
    '외부 API를 포함한 사용자 요청 성공': (result) => result.status === 200,
  });
}

export function requestNormalApi() {
  const response = http.get(`${baseUrl}/api/info`, {
    tags: {
      experiment: 'external-api-step-01-latency-propagation',
      request_type: 'normal_api',
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
}

export function injectExternalDelay() {
  setExternalMode('/__lab/control/slow');
  externalFaultSignal.add(1);
}

export function recoverExternalApi() {
  setExternalMode('/__lab/control/normal');
  externalFaultSignal.add(0);
}

export function teardown() {
  setExternalMode('/__lab/control/normal');
}

function setExternalMode(path) {
  const response = http.post(`${wireMockUrl}${path}`, null, {
    tags: { request_type: 'fault_control' },
    timeout: '3s',
  });

  if (response.status !== 200) {
    throw new Error(`WireMock 상태 변경 실패: path=${path}, status=${response.status}`);
  }

  return response;
}
