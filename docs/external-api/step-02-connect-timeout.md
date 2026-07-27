# 2단계: Connect Timeout

> 상태: 완료. TCP 연결 장애가 Spring Connect Timeout 1초 안에 종료되고 정상 API의 가용성이 유지되는 것을 확인했다.

## 목적

외부 서버와 TCP 연결 자체가 성립하지 않을 때 Spring의 outbound 요청이 운영체제 기본 연결 대기시간에 의존하지 않도록 `Connect Timeout`을 1초로 제한한다. 외부 기능은 빠르게 실패하더라도 관계없는 정상 API의 가용성은 유지되는지 확인한다.

Connect Timeout은 연결이 완료된 뒤 응답이 늦는 문제를 해결하지 않는다. 그 상황은 3단계의 Read Timeout에서 별도로 다룬다.

## 장애 구성

```text
k6 ──10 RPS──> Spring Boot ──TCP SYN──> Docker blackhole
 │                  │                     └─ SYN 폐기
 └──2 RPS───> /api/info

Spring Connect Timeout: 1초
k6 Client Timeout:      3초
```

- Spring Boot, WireMock, blackhole은 2단계 전용 Docker Compose 네트워크에서 실행한다.
- `blackhole` 컨테이너는 8080 포트로 들어오는 TCP SYN을 `iptables DROP`한다.
- 연결 거절처럼 즉시 실패시키지 않고 실제 TCP 연결 대기를 발생시킨다.
- macOS 방화벽이나 라우팅 설정은 변경하지 않는다.
- Spring이 1초 뒤 `connect_timeout`으로 분류하고 사용자에게 HTTP 504를 반환한다.

`nicolaka/netshoot` 컨테이너에 `NET_ADMIN` 권한을 주는 이유는 이 전용 컨테이너 내부의 방화벽 규칙 하나를 설정하기 위해서다. 호스트 네트워크 설정에는 영향을 주지 않는다.

## 실험 시간

| 구간 | 외부 기능 호출 대상 | 예상 결과 |
|---|---|---|
| 0~15초 | 정상 WireMock | HTTP 200, 짧은 응답시간 |
| 15~40초 | TCP blackhole | 약 1초 뒤 Spring이 HTTP 504 반환 |
| 40~60초 | 정상 WireMock | HTTP 200 흐름으로 복구 |

전체 구간에 `/api/info`를 2 RPS로 호출한다. 장애 구간에도 1초 Connect Timeout 덕분에 외부 요청의 동시 점유량은 대략 `10 RPS × 1초` 수준에 머물고, Tomcat 최대 Thread 40개를 고갈시키지 않아야 한다.

## 실행

관측 환경을 시작한다.

```bash
bash scripts/observability/start.sh
```

2단계 애플리케이션과 외부 서버를 시작한다.

```bash
bash scripts/external-api/step-02/start.sh
```

실험을 실행한다.

```bash
bash scripts/external-api/step-02/run-experiment.sh
```

Grafana에서 현재 실행 ID를 선택한다.

<http://localhost:3000/d/external-api-step-02-connect-timeout>

k6 실행 중에는 <http://127.0.0.1:5665>에서 실시간 지표를 볼 수 있다. 실행 후에는 `results/external-api/step-02/<실행 ID>/k6-report.html`을 브라우저에서 연다.

실험용 컨테이너를 종료한다.

```bash
bash scripts/external-api/step-02/stop.sh
```

## 관측 항목

### 사용자 응답 결과

- 정상·복구 구간: HTTP 200
- 연결 장애 구간: Spring Connect Timeout 후 HTTP 504
- k6 Client Timeout: 0건

서버 Connect Timeout 1초가 클라이언트 제한 3초보다 먼저 동작해야 사용자는 무응답으로 연결을 포기하지 않고 서버가 명시한 실패 응답을 받는다.

### 응답시간

- 정상 구간: 수십 ms 수준
- 연결 장애 구간: 약 1초
- 연결 장애 p95가 1.5초 이내인지 확인

### Spring 외부 호출

- `external_api_failures_total{reason="connect_timeout"}`이 장애 구간에만 증가
- 외부 API 처리 중 요청 수가 약 10개 수준에서 제한
- 클라이언트가 포기한 뒤에도 장시간 남아 있는 요청이 없어야 함

### 서버 전체 가용성

- Tomcat 사용 중 Thread가 최대 40개보다 충분히 낮게 유지
- `/api/info`가 HTTP 200이면서 1초 이내 완료되는 비율이 100%에 가깝게 유지
- k6 `dropped_iterations` 0건

## 완료 기준

- [x] TCP 연결이 성립하지 않는 장애가 재현된다.
- [x] Spring이 약 1초 후 HTTP 504를 반환한다.
- [x] k6 Client Timeout은 발생하지 않는다.
- [x] Spring 메트릭에서 실패 원인이 `connect_timeout`으로 분류된다.
- [x] Tomcat Thread와 외부 처리 중 요청 수가 제한된다.
- [x] 정상 API 가용 요청 비율이 유지된다.
- [x] k6 JSON과 HTML 결과가 실행 ID별로 저장된다.

## 실제 검증 결과

2026-07-26 실행 ID `20260726-210955`에서 다음 결과를 확인했다.

| 관측 항목 | 결과 | 의미 |
|---|---:|---|
| 정상·복구 외부 기능 | HTTP 200 350건 | 정상 150건과 복구 200건이 모두 성공 |
| 연결 장애 외부 기능 | HTTP 504 250건 | 모든 연결 장애 요청을 서버가 명시적으로 종료 |
| 연결 장애 응답시간 p95 | 약 1.01초 | Connect Timeout 1초가 의도대로 동작 |
| k6 Client Timeout | 0건 | 클라이언트 제한 3초보다 서버 실패 응답이 먼저 도착 |
| Spring `connect_timeout` | 250건 | 외부 호출 실패 원인을 서버 메트릭으로 확인 |
| 외부 API 처리 중 요청 | 최대 10개 | `10 RPS × 약 1초` 수준으로 동시 점유 제한 |
| Tomcat 사용 중 Thread | 최대 11/40개 | 공유 Thread Pool이 포화되지 않음 |
| 정상 API | 121/121건 가용 | 모두 HTTP 200이면서 1초 안에 완료 |
| 정상 API p95 | 약 7.82ms | 외부 연결 장애가 정상 API에 전파되지 않음 |
| k6 누락 요청 | 0건 | 설정한 유입량을 끝까지 유지 |

전체 k6 iteration은 외부 기능 600건과 정상 API 121건을 합친 721건이다. 외부 기능은 하나의 10 RPS 시나리오에서 iteration 번호로 구간을 나누므로 단계 경계에서 요청 수가 겹치지 않는다.

## 결과 파일

`results/external-api/step-02/<실행 ID>/`에 다음 파일을 로컬로 누적한다.

- `server.log`
- `k6-summary.json`
- `k6-metrics.json`
- `k6-report.html`

## 다음 단계

3단계에서는 TCP 연결은 성공하지만 외부 서버가 응답을 늦게 보내는 상황에 Read Timeout을 적용한다. Connect Timeout만으로는 이 장애를 제한할 수 없다는 차이를 같은 지표로 확인한다.
