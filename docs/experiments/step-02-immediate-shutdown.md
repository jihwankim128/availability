# Step 02: Immediate Shutdown

## 목표

처리 시간이 긴 요청이 실행 중일 때 서버에 `SIGTERM`을 보내면, Immediate Shutdown은 요청 완료를 기다리지 않고 연결을 종료한다는 것을 확인한다.

1단계의 API와 실행 방법은 변경하지 않는다. 이 실험은 `immediate` Profile과 2단계 전용 스크립트만 사용한다.

## 준비

- Java 21
- k6
- Docker Desktop
- 로컬 포트 `8080`
- 관측 도구 포트 `3000`, `9090`

## 실행

Prometheus와 Grafana를 먼저 실행한다.

```bash
bash scripts/observability/start.sh
```

Grafana의 `2단계 - Immediate Shutdown` 대시보드는 한글 제목과 범례를 사용한다. 학습용 고정 사용자 `user-1`부터 `user-5`까지의 결과를 `user_id` 라벨로 구분한다.

터미널 A에서 Immediate Shutdown 서버를 실행한다.

```bash
bash scripts/step-02/start-immediate-server.sh
RUN_ID="$(cat build/step-02/run-id)"
tail -f "results/step-02/${RUN_ID}/server.log"
```

터미널 B에서 k6 Web Dashboard와 실험을 실행한다. 브라우저에서 k6 Web Dashboard가 자동으로 열리며, Grafana는 `http://localhost:3000/d/step-02-immediate-shutdown`에서 확인한다.

```bash
bash scripts/step-02/run-k6-dashboard.sh
```

실험은 5명의 가상 사용자가 각각 하나의 30초 요청을 전송한다. VU 수와 실제 요청 수는 모두 5개다.

각 사용자는 요청 처리 중 0.5초마다 자신의 신호를 기록한다. 사용자별 신호는 서로 겹치지 않도록 `user-1`부터 각각 `5`, `4`, `3`, `2`, `1`을 사용하고 요청이 완료되거나 중단되면 `0`으로 내려간다. 신호 값은 처리량이 아니라 사용자 구분을 위한 높이다.

서버 로그에 `step-02-user-1`부터 `step-02-user-5`까지 긴 요청의 시작 로그가 출력되면 터미널 C에서 서버에 `SIGTERM`을 보낸다.

```bash
bash scripts/step-02/stop-immediate-server.sh
```

## 검증 기준

- `사용자별 처리 중 요청 신호`에서 사용자 5명의 선이 가로로 유지되다가 SIGTERM 시점에 `0`으로 내려간다.
- Grafana에 `SIGTERM (<실행 ID>)` 세로 주석이 표시된다.
- `in_flight_request_completed`는 `0`이고 `in_flight_request_interrupted`는 증가한다.
- k6의 `http_req_failed`가 `0%`보다 크다.
- 서버 로그에 `work started`는 있지만 같은 요청 ID의 `work completed`는 없다.
- 실험 후 `/api/info` 요청은 연결할 수 없다.

## 그래프 해석

| 메트릭 | 2단계 Immediate Shutdown | 3단계 Graceful Shutdown 예상 |
| --- | --- | --- |
| `in_flight_user_signal` | SIGTERM 시점에 즉시 `0` | SIGTERM 이후에도 유지되고 요청 완료 시 `0` |
| `in_flight_request_completed` | 증가하지 않음 | 종료 이후에도 증가 |
| `in_flight_request_interrupted` | 종료 시점에 증가 | 증가하지 않음 |

두 단계가 같은 k6 메트릭 이름을 사용하면 발표 자료에서 그래프를 나란히 비교할 수 있다.

실험이 끝나면 `results/step-02/<실행 ID>/`에 다음 파일이 생성된다. 새 실험은 새로운 실행 ID를 사용하므로 이전 결과를 덮어쓰지 않는다.

- `server.log`
- `k6-report.html`
- `k6-summary.json`
- `k6-metrics.json`

## 검증 결과

실행 ID `20260718-042945`로 사용자 검증을 완료했다.

- VU: 5명
- HTTP 요청: 5개
- 처리 중 요청 정상 완료: 0개
- 처리 중 요청 중단: 5개 (`user-1`~`user-5`)
- 사용자 신호: 각각 `5`, `4`, `3`, `2`, `1`로 유지된 뒤 SIGTERM 시점에 `0`으로 변경
- Grafana의 한글 제목, 사용자별 범례, SIGTERM 주석 확인

원본 로그, k6 시계열, HTML 보고서는 로컬 결과 폴더에 보존하며 Git에는 포함하지 않는다.
