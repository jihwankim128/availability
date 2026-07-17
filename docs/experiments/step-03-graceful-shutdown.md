# Step 03: Graceful Shutdown

## 목표

처리 시간이 긴 요청이 실행 중일 때 서버에 `SIGTERM`을 보내더라도, Graceful Shutdown은 기존 요청이 완료될 때까지 기다린 뒤 서버를 종료한다는 것을 확인한다.

2단계의 Immediate Shutdown 설정과 실행 파일은 변경하지 않는다. 이 실험은 `graceful` Profile과 3단계 전용 스크립트만 사용한다.

## 설정

Spring Boot 4.1은 Graceful Shutdown이 기본값이지만 실습 의도를 명시하기 위해 다음 설정을 사용한다.

```properties
server.shutdown=graceful
spring.lifecycle.timeout-per-shutdown-phase=40s
```

## 실행

Prometheus와 Grafana가 실행 중이 아니라면 먼저 시작한다.

```bash
bash scripts/observability/start.sh
```

터미널 A에서 Graceful Shutdown 서버를 실행하고 로그를 확인한다.

```bash
bash scripts/step-03/start-graceful-server.sh
RUN_ID="$(cat build/step-03/run-id)"
tail -f "results/step-03/${RUN_ID}/server.log"
```

터미널 B에서 사용자 5명의 30초 요청을 실행한다.

```bash
bash scripts/step-03/run-k6-dashboard.sh
```

서버 로그에 `step-03-user-1`부터 `step-03-user-5`까지 요청 시작 로그가 출력되면 터미널 C에서 `SIGTERM`을 보낸다.

```bash
bash scripts/step-03/stop-graceful-server.sh
```

종료 스크립트는 처리 중인 요청이 완료되어 서버 프로세스가 종료될 때까지 기다린다.

## 검증 기준

- VU 수와 HTTP 요청 수가 각각 5개다.
- Grafana에 `SIGTERM (<실행 ID>)` 세로 주석이 표시된다.
- 사용자별 처리 신호가 SIGTERM 이후에도 유지되다가 요청이 완료될 때 `0`으로 내려간다.
- `in_flight_request_completed`는 5이고 `in_flight_request_interrupted`는 0이다.
- `http_req_failed`는 `0%`다.
- 서버 로그에 사용자 5명의 `work started`와 `work completed`가 모두 존재한다.
- `work interrupted` 로그는 존재하지 않는다.

## 검증 결과

2026-07-18 실행(`20260718-044124`)에서 다음 결과를 확인했다.

- VU 5명이 각각 하나의 요청을 보내 총 5개의 HTTP 요청이 실행됐다.
- `SIGTERM`은 요청 시작 약 7초 후 전달됐고, 서버는 남은 요청 처리를 기다렸다.
- 사용자 5명의 요청이 모두 정상 완료됐다.
- `in_flight_request_completed`는 5, `in_flight_request_interrupted`는 0이었다.
- `http_req_failed`는 `0%`였다.
- 서버 로그에서 `work started` 5건과 `work completed` 5건을 확인했으며 `work interrupted`는 없었다.
- 마지막 요청 완료 직후 `Graceful shutdown complete` 로그가 기록됐다.

실행 결과 파일은 Git에 포함하지 않고 로컬 `results/step-03/20260718-044124/`에 보관한다.
