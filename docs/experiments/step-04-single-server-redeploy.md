# Step 04: 단일 서버 재배포 중 요청 중단

## 목표

Graceful Shutdown은 이미 처리 중인 요청을 보호하지만, 단일 서버가 종료된 뒤 다음 버전이 준비될 때까지 새 요청을 받을 서버가 없다는 점을 확인한다.

2·3단계의 설정과 실행 파일은 변경하지 않는다. 이 실험은 `single-server` Profile과 4단계 전용 스크립트만 사용한다.

## 실험 구조

- k6의 고정 VU 5명이 1초마다 `/api/info`를 반복 호출한다.
- v1 서버를 Graceful Shutdown으로 종료한다.
- 발표에서 중단 구간을 명확히 관측할 수 있도록 기본 5초의 배포 공백을 둔다.
- 같은 포트에 v2 서버를 시작한다.
- 시간대별 새 요청이 `성공 → 실패 → 성공`으로 바뀌는지 확인한다.

4단계는 지속 요청의 시간대별 실패가 핵심이므로 Prometheus와 Grafana를 사용하지 않는다. k6 Web Dashboard와 HTML 보고서에서 `http_req_failed`, 요청률, 체크 결과를 직접 확인한다.

## 실행

터미널 A에서 단일 서버 v1을 시작한다.

```bash
bash scripts/step-04/start-v1-server.sh
```

터미널 B에서 40초 동안 지속 요청을 실행한다.

```bash
bash scripts/step-04/run-k6-dashboard.sh
```

k6 Web Dashboard에서 v1 요청이 성공하는 것을 확인한 뒤 터미널 C에서 v2를 배포한다.

```bash
bash scripts/step-04/deploy-v2-server.sh
```

기본 5초의 배포 공백은 환경 변수로 조절할 수 있다.

```bash
DOWNTIME_SECONDS=10 bash scripts/step-04/deploy-v2-server.sh
```

k6 실행이 끝난 뒤 v2 서버를 종료한다.

```bash
bash scripts/step-04/stop-server.sh
```

k6 실행 중에는 `http://127.0.0.1:5665`에서 실시간 그래프를 확인한다. 실행이 끝나면 `results/step-04/<실행 ID>/k6-report.html`에서 같은 결과를 다시 볼 수 있다.

## 검증 기준

- v1 종료 전에는 지속 요청이 성공한다.
- v1 종료부터 v2 준비 전까지 `http_req_failed`와 `checks` 실패가 발생한다.
- 배포 공백이 끝나면 요청이 다시 성공하며 실패 구간이 끝난다.
- `deployment_version_signal`이 `v1(1) → 요청 실패(0) → v2(2)`로 바뀐다.
- k6 결과에 v1 응답, 실패 응답, v2 응답이 모두 존재한다.

## 검증 결과

2026-07-18 실행(`20260718-045953`)에서 다음 결과를 확인했다.

- VU 5명이 40초 동안 총 200개의 HTTP 요청을 보냈다.
- v1 응답은 50개, 실패 응답은 35개, v2 응답은 115개였다.
- 첫 실패는 `05:00:10.339`, 마지막 실패는 `05:00:16.348`에 기록되어 약 6초간 새 요청이 중단됐다.
- `deployment_version_signal`에서 `v1(1)`, 요청 실패 `(0)`, `v2(2)`가 모두 기록됐다.
- 서버 로그에서 v1의 Graceful Shutdown 완료 후 v2가 같은 포트에서 준비된 것을 확인했다.
- k6 시간 그래프에서 요청이 `성공 → 실패 → 성공`으로 전환되는 구간을 확인했다.

실행 결과 파일은 Git에 포함하지 않고 로컬 `results/step-04/20260718-045953/`에 보관한다.
