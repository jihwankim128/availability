import http from 'k6/http';
import { check } from 'k6';
import exec from 'k6/execution';
import { Counter, Gauge } from 'k6/metrics';

const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
const runId = __ENV.RUN_ID || 'manual';
const inFlightVirtualUsers = Number(__ENV.IN_FLIGHT_VUS || 5);
const workSeconds = Number(__ENV.WORK_SECONDS || 30);

const inFlightUserSignal = new Gauge('in_flight_user_signal');
const inFlightRequestCompleted = new Counter('in_flight_request_completed');
const inFlightRequestInterrupted = new Counter('in_flight_request_interrupted');

export const options = {
  noConnectionReuse: true,
  tags: {
    run_id: runId,
    shutdown_mode: 'immediate',
    step: '02',
  },
  scenarios: {
    in_flight_requests: {
      executor: 'per-vu-iterations',
      exec: 'inFlightRequests',
      vus: inFlightVirtualUsers,
      iterations: 1,
      maxDuration: `${workSeconds + 15}s`,
    },
  },
  thresholds: {
    http_req_failed: ['rate>0'],
    in_flight_request_completed: ['count==0'],
    in_flight_request_interrupted: ['count>0'],
  },
};

export async function inFlightRequests() {
  const userNumber = exec.scenario.iterationInTest + 1;
  const userId = `user-${userNumber}`;
  const requestId = `step-02-${userId}`;
  const signalLevel = inFlightVirtualUsers - userNumber + 1;
  const resultTags = {
    user_id: userId,
    request_id: requestId,
  };
  const request = http.asyncRequest('GET', `${baseUrl}/api/work?seconds=${workSeconds}`, null, {
    headers: {
      'X-Request-Id': requestId,
    },
    tags: {
      experiment: 'step-02-immediate-shutdown',
      request_type: 'in_flight',
      ...resultTags,
    },
    timeout: `${workSeconds + 10}s`,
  });

  inFlightUserSignal.add(signalLevel, resultTags);
  const signalInterval = setInterval(() => {
    inFlightUserSignal.add(signalLevel, resultTags);
  }, 500);

  let response;
  try {
    response = await request;
  } catch (_) {
    response = { status: 0 };
  } finally {
    clearInterval(signalInterval);
    inFlightUserSignal.add(0, resultTags);
  }

  const completed = response.status === 200;
  inFlightRequestCompleted.add(completed ? 1 : 0, resultTags);
  inFlightRequestInterrupted.add(completed ? 0 : 1, resultTags);

  check(response, {
    [`${userId} 처리 중 요청 중단`]: () => !completed,
  });
}
