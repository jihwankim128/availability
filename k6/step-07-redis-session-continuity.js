import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Gauge } from 'k6/metrics';

const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
const runId = __ENV.RUN_ID || 'manual';
const duration = __ENV.DURATION || '40s';

const sessionAvailableSignal = new Gauge('session_available_signal');
const sessionBackendSignal = new Gauge('session_backend_signal');
const sessionHttpStatusSignal = new Gauge('session_http_status_signal');
const sessionFound = new Counter('session_found');
const sessionMissing = new Counter('session_missing');
const sessionBlueResponse = new Counter('session_blue_response');
const sessionGreenResponse = new Counter('session_green_response');

export const options = {
  noConnectionReuse: true,
  tags: {
    run_id: runId,
    session_mode: 'redis',
    step: '07',
  },
  scenarios: {
    session_continuity: {
      executor: 'constant-vus',
      vus: 1,
      duration,
      gracefulStop: '2s',
    },
  },
  thresholds: {
    session_found: ['count>0'],
    session_missing: ['count==0'],
    session_blue_response: ['count>0'],
    session_green_response: ['count>0'],
  },
};

export function setup() {
  const response = http.post(`${baseUrl}/api/session/login?username=crew`, null, {
    tags: { request_type: 'login' },
  });
  const sessionCookie = response.cookies.SESSION?.[0]?.value;

  if (response.status !== 200 || !sessionCookie) {
    throw new Error('Blue에서 SESSION 쿠키를 발급받지 못했습니다.');
  }

  return { sessionCookie };
}

export default function (data) {
  const metricTags = { user_id: 'crew' };
  const infoResponse = http.get(`${baseUrl}/api/info`, {
    tags: { request_type: 'server_info' },
    timeout: '2s',
  });
  const sessionResponse = http.get(`${baseUrl}/api/session/me`, {
    headers: { Cookie: `SESSION=${data.sessionCookie}` },
    tags: { request_type: 'session_check' },
    timeout: '2s',
  });

  const version = readJsonValue(infoResponse, 'version');
  const sessionAvailable = sessionResponse.status === 200;
  const backendSignal = version === 'v1' ? 1 : version === 'v2' ? 2 : 0;

  sessionAvailableSignal.add(sessionAvailable ? 1 : 0, metricTags);
  sessionBackendSignal.add(backendSignal, metricTags);
  sessionHttpStatusSignal.add(sessionResponse.status, metricTags);
  sessionFound.add(sessionAvailable ? 1 : 0, metricTags);
  sessionMissing.add(sessionResponse.status === 401 ? 1 : 0, metricTags);
  sessionBlueResponse.add(version === 'v1' ? 1 : 0, metricTags);
  sessionGreenResponse.add(version === 'v2' ? 1 : 0, metricTags);

  check(sessionResponse, {
    'Redis 세션 조회 성공': (response) => response.status === 200,
  });

  sleep(1);
}

function readJsonValue(response, key) {
  if (response.status !== 200) {
    return 'unavailable';
  }

  try {
    return response.json(key);
  } catch (_) {
    return 'unknown';
  }
}
