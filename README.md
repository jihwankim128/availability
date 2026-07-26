# Availability

서비스 가용성을 학습하고 간단한 실습을 진행하기 위한 Spring Boot 프로젝트입니다.

## 학습 주제

### 외부 API 장애

- 외부 API의 지연과 실패가 서비스에 미치는 영향 확인
- Connect Timeout과 Read Timeout으로 외부 호출 대기 시간 제한
- Circuit Breaker를 이용한 장애 전파 방지
- Retry, Rate Limit, Bulkhead는 핵심 실습 이후의 확장 주제로 구분
- 외부 API 실습은 별도 커리큘럼으로 분리하고 [`docs/external-api/README.md`](docs/external-api/README.md)에서 1단계부터 관리

### 무중단 배포

- Graceful Shutdown으로 처리 중인 요청 보호
- 새 서버가 준비된 이후 트래픽 전달
- Blue/Green 방식의 배포와 빠른 롤백 실습

## 실행

```bash
./gradlew bootRun
```

Java 21과 Spring Boot 4.1.0을 사용합니다.

## 실습 1: 무중단 배포

### 실습 기록 원칙

- 완료된 단계의 설정, 실행 스크립트, 결과는 다음 단계 작업으로 덮어쓰지 않는다.
- 단계별 설정은 Spring Profile처럼 분리하고, 단계별 k6 스크립트와 결과도 별도 경로에 추가한다.
- 실행 결과는 로컬에 누적하고 Git에는 실행 스크립트, 검증 방법, 결과 구조만 공유한다.
- README는 전체 진행 상황을 보여주는 인덱스로 사용하고 History를 누적한다.
- 공용 코드가 변경되더라도 각 단계의 커밋으로 이전 상태를 다시 확인할 수 있게 한다.
- 한 단계가 끝날 때마다 테스트한 뒤 커밋하고 `origin/main`에 푸시한다.

### 진행 현황

- [x] 1단계: 관측용 장기 요청 API와 버전·인스턴스 정보 추가
- [x] 2단계: Immediate Shutdown에서 처리 중 요청 중단 확인
- [x] 3단계: Graceful Shutdown에서 처리 중 요청 완료 확인
- [x] 4단계: 단일 서버 재배포 중 신규 요청 중단 확인
- [x] 5단계: Blue/Green 배포로 요청 중단 제거
- [x] 6단계: Blue/Green 전환 후 로컬 세션 유실 확인
- [x] 7단계: Redis 공유 세션으로 전환 후 로그인 상태 유지 확인
- [ ] 후속 과제: 버전 혼재에 따른 세션 직렬화·캐시 문제 확인

### History

#### 2026-07-18 — 1단계: 요청 관측 기반 구성

- 장기 처리 요청을 만드는 `/api/work` 추가
- 서버 버전과 인스턴스를 확인하는 `/api/info` 추가
- 요청 ID, 서버 버전, 인스턴스, 시작·완료 시각을 로그와 응답으로 확인

#### 2026-07-18 — 2단계 준비: 초기 관측 방법 결정

- 클라이언트 관점은 k6의 요청 수, 실패율, 응답 시간으로 확인
- 서버 관점은 요청 시작·완료·중단 로그로 확인
- 처음에는 Prometheus와 Loki를 제외했으나 발표용 시각화 요구를 확인한 뒤 Prometheus와 Grafana를 추가

#### 2026-07-18 — 2단계: Immediate Shutdown 검증 완료

- VU 5명이 각각 하나의 30초 요청을 실행하도록 구성
- Immediate Shutdown에서 사용자 5명의 처리 중 요청이 모두 중단되는 것을 확인
- Prometheus와 Grafana로 사용자별 처리 신호가 `5~1`에서 `0`으로 내려가는 장면을 시각화
- 실행 결과는 로컬에만 누적하고 설정, 스크립트, 검증 문서만 Git에 공유

#### 2026-07-18 — 3단계: Graceful Shutdown 검증 완료

- VU 5명이 각각 하나의 30초 요청을 실행하도록 3단계 실험을 분리
- 요청 처리 중 `SIGTERM`을 보낸 뒤에도 사용자 5명의 요청이 모두 정상 완료되는 것을 확인
- 완료 요청 5건, 중단 요청 0건, HTTP 요청 실패율 `0%`를 확인
- 서버가 기존 요청 완료를 기다린 뒤 Graceful Shutdown을 완료하는 흐름을 Grafana와 로그로 확인

#### 2026-07-18 — 4단계: 단일 서버 재배포 중 요청 중단 검증 완료

- VU 5명이 40초 동안 1초 간격으로 새 요청을 반복하도록 구성
- v1 종료 후 v2 준비 전까지 약 6초의 요청 실패 구간을 k6 시간 그래프로 확인
- 총 200개 요청에서 v1 응답 50개, 실패 35개, v2 응답 115개를 확인
- 지속 요청 실험은 사용자별 최종 상태 대신 k6의 시간대별 실패율과 버전 신호로 관측

#### 2026-07-18 — 5단계: Blue/Green 무중단 배포 검증 완료

- Nginx를 통해 Blue v1을 제공하면서 Green v2를 별도 포트에서 준비
- Green readiness와 Nginx 설정을 검증한 뒤 graceful reload로 트래픽 전환
- 총 200개 요청에서 Blue 응답 65개, Green 응답 135개, 실패 0개를 확인
- Green 전환 확인 후 Blue를 Graceful Shutdown하고 전환 전 실패 시 Blue로 롤백하도록 구성

#### 2026-07-19 — 6단계: 로컬 세션 유실 검증 완료

- Blue에서 발급한 세션 쿠키를 유지한 채 Green으로 트래픽 전환
- HTTP 요청은 Green에 정상 도달하지만 프로세스 메모리가 분리되어 `401 Unauthorized`가 반환되는 것을 확인
- Grafana에서 응답 서버가 `Blue v1 → Green v2`, 세션 조회 결과가 `3(200) → 2(401)`로 바뀌는 흐름을 시각화

#### 2026-07-19 — 7단계: Redis 공유 세션 연속성 검증 완료

- Blue와 Green이 같은 Redis 세션 저장소와 네임스페이스를 사용하도록 구성
- Blue에서 발급한 쿠키로 Green 전환 후에도 같은 세션 ID와 사용자 정보가 `200 OK`로 유지되는 것을 확인
- Grafana에서 응답 서버가 바뀌어도 세션 조회 결과가 `3(200)`을 유지하는 흐름을 6단계와 같은 축으로 비교

### 2단계 관측 전략

Immediate Shutdown 실험에서는 k6와 애플리케이션 로그를 함께 사용한다.

- k6: 종료 시점에 가상 사용자의 요청이 실제로 실패하는지 `http_reqs`, `http_req_failed`, `http_req_duration`으로 확인한다.
- k6 Web Dashboard: 사용자별 처리 중 요청 신호와 완료·중단 메트릭을 같은 시간축의 그래프로 확인하고 HTML로 보존한다.
- Prometheus와 Grafana: 실행별 k6 메트릭을 로컬에 누적하고 한글 제목·범례로 시각화한다.
- 애플리케이션 로그: 같은 요청의 시작 로그가 있지만 완료 로그가 남지 않거나 중단 로그가 남는지 확인한다.
- 성공 조건: 처리 시간이 긴 요청을 실행한 상태에서 서버를 종료했을 때 k6 실패가 발생하고, 서버 로그에서도 해당 요청이 완료되지 않았음을 확인한다.

Loki는 2단계의 필수 구성에서 제외한다.

- Prometheus와 Grafana: 사용자별 처리 신호를 실행별로 분리하고 한글 대시보드에서 비교한다.
- Loki: Blue/Green처럼 여러 인스턴스의 로그를 한곳에서 검색해야 할 때 추가한다.
- 학습용으로 범위가 고정된 `user-1`부터 `user-5`까지를 Prometheus 라벨로 사용한다.

2단계의 실행 방법과 검증 기준은 [`docs/experiments/step-02-immediate-shutdown.md`](docs/experiments/step-02-immediate-shutdown.md)에 별도로 누적한다.

3단계의 실행 방법과 검증 기준은 [`docs/experiments/step-03-graceful-shutdown.md`](docs/experiments/step-03-graceful-shutdown.md)에 별도로 누적한다.

4단계의 실행 방법과 검증 기준은 [`docs/experiments/step-04-single-server-redeploy.md`](docs/experiments/step-04-single-server-redeploy.md)에 별도로 누적한다.

5단계의 실행 방법과 검증 기준은 [`docs/experiments/step-05-blue-green-deployment.md`](docs/experiments/step-05-blue-green-deployment.md)에 별도로 누적한다.

6단계의 실행 방법과 검증 기준은 [`docs/experiments/step-06-local-session-loss.md`](docs/experiments/step-06-local-session-loss.md)에 별도로 누적한다.

7단계의 실행 방법과 검증 기준은 [`docs/experiments/step-07-redis-session-continuity.md`](docs/experiments/step-07-redis-session-continuity.md)에 별도로 누적한다.

### 1단계 실행 방법

먼저 요청을 관측하기 위한 API를 실행합니다.

```bash
./gradlew bootRun
```

현재 서버의 버전과 인스턴스를 확인합니다.

```bash
curl http://localhost:8080/api/info
```

10초 동안 처리되는 요청을 실행합니다. 서버 로그와 응답에서 요청 ID, 버전, 인스턴스, 시작·완료 시각을 확인할 수 있습니다.

```bash
curl 'http://localhost:8080/api/work?seconds=10'
```
