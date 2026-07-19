# 7단계: Redis를 이용한 세션 연속성 확보

## 목적

6단계에서 재현한 로컬 세션 유실을 해결한다. Blue와 Green이 같은 Redis 세션 저장소를 사용하면 서버가 바뀌어도 기존 세션 쿠키로 로그인 상태를 이어갈 수 있는지 확인한다.

## 구성

- Nginx 컨테이너: `localhost:8080` 요청을 현재 서버로 전달
- Redis 컨테이너: `localhost:6379`, Blue와 Green의 공용 세션 저장소
- Blue v1: `localhost:8081`, Spring Session으로 Redis 사용
- Green v2: `localhost:8082`, 같은 Redis와 세션 네임스페이스 사용
- 결과: Blue에서 발급한 쿠키로 Green에 조회해도 `200 OK`

Redis와 Nginx는 Docker 컨테이너로만 실행한다. 로컬에 패키지를 설치하거나 시스템 설정을 변경하지 않으며 `stop-all.sh` 실행 시 컨테이너와 네트워크를 제거한다. 실습 결과 파일만 로컬에 남는다.

## 실행

Blue, Redis, Nginx를 시작한다.

```bash
bash scripts/step-07/start-blue.sh
```

Blue에서 Redis 기반 세션을 만들고 조회한다.

```bash
bash scripts/step-07/login.sh
```

응답에서 다음 값을 확인한다.

- `version`: `v1`
- `instanceId`: `blue`
- `sessionMode`: `redis`
- `username`: `crew`

같은 Redis를 바라보는 Green을 준비하고 트래픽을 전환한다.

```bash
bash scripts/step-07/deploy-green.sh
```

Blue에서 받은 쿠키를 그대로 보내 세션을 다시 조회한다.

```bash
bash scripts/step-07/check-after-switch.sh
```

성공 기준은 다음과 같다.

- HTTP 상태가 `200 OK`이다.
- `username`이 `crew`로 유지된다.
- `version`이 `v2`이다.
- `instanceId`가 `green`이다.
- `sessionMode`가 `redis`이다.

실습이 끝나면 모든 프로세스와 컨테이너를 종료한다.

```bash
bash scripts/step-07/stop-all.sh
```

## Grafana로 가시화

6단계와 같은 사용자와 요청 주기로 비교한다. 먼저 Prometheus와 Grafana를 시작한다.

```bash
bash scripts/observability/start.sh
bash scripts/step-07/start-blue.sh
```

다른 터미널에서 k6를 실행한다. k6가 Blue에서 로그인하고 같은 세션 쿠키를 40초 동안 재사용한다.

```bash
bash scripts/step-07/run-k6-visibility.sh
```

k6가 실행 중일 때 다른 터미널에서 Green으로 전환한다.

```bash
bash scripts/step-07/deploy-green.sh
```

Grafana의 <http://localhost:3000/d/session-continuity>에서 세션 저장소를 `redis`, 실행 ID를 현재 값으로 선택한다.

여러 결과를 찾거나 비교할 때는 세션 저장소와 실행 ID의 `All`을 선택한다. `All` 상태에서는 범례의 저장소와 실행 ID로 각 선을 구분한다.

- `Blue v1 → Green v2`: 실제 응답 서버가 전환됨
- `세션 유지(3)`: Redis에 저장한 동일 세션이 Green에서도 계속 조회됨
- `200 OK`: 서버 전환 전후 모두 같은 세션으로 정상 응답함

6단계 그래프와 같은 축을 사용하므로 발표 자료에서 `3 → 2`와 `3 유지`를 바로 비교할 수 있다.

k6가 정상 종료되면 Prometheus에 stale marker를 전송하므로 마지막 값이 현재 시각까지 이어지지 않고 실험 종료 시점에서 그래프도 끝난다.

k6 실행과 그래프 확인이 끝나면 Blue, Green, Nginx, Redis를 종료한다.

```bash
bash scripts/step-07/stop-all.sh
```

Prometheus와 Grafana는 종료하지 않으므로 6단계와 7단계 그래프를 계속 비교할 수 있다. 가시화 환경까지 종료하려면 별도로 `bash scripts/observability/stop.sh`를 실행한다.

## 결과 파일

`results/step-07/<실행 ID>/`에 다음 파일을 남긴다.

- `session-login.json`: Blue에서 세션을 만든 응답
- `session-before-switch.json`: 전환 전 Blue의 세션 조회 결과
- `session-after-switch.json`: 같은 세션을 조회한 Green의 응답
- `cookies.txt`: Blue와 Green에 동일하게 보낸 세션 쿠키
- `server-blue.log`, `server-green.log`: 인스턴스별 세션 로그
- `k6-summary.json`, `k6-metrics.json`: Grafana 가시화 실행 결과

실행 결과는 로컬에만 누적하고 Git에는 결과 구조만 공유한다.

## 범위

이번 단계는 상태 외부화가 사용자 관점의 가용성에 미치는 영향만 다룬다. 다음 항목은 별도 주제다.

- 실제 인증과 Spring Security
- Redis 자체의 고가용성과 영속성
- 서로 다른 애플리케이션 버전 사이의 세션 직렬화 호환성
- 서버별 로컬 캐시 불일치와 캐시 무효화
