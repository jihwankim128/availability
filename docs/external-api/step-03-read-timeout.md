# 3단계: Read Timeout

> 상태: 완료. 연결 후 5초 응답 지연이 Spring Read Timeout 1초 안에 종료되고 정상 API의 가용성이 유지되는 것을 확인했다.

## 목적

외부 서버와 TCP 연결은 성공했지만 응답 데이터가 늦게 도착할 때 `Read Timeout`으로 대기 시간을 1초로 제한한다. 외부 기능은 빠르게 실패시키고, 외부 응답을 기다리는 Thread가 쌓여 관계없는 정상 API까지 느려지는 장애 전파를 막는지 확인한다.

Connect Timeout은 연결 수립 과정만 제한하므로 이 문제를 해결하지 못한다. 3단계에서는 Connect Timeout과 Read Timeout을 각각 1초로 설정하지만, 실제로 발생하는 실패 원인은 `read_timeout`이어야 한다.

## 장애 구성

```text
k6 ──10 RPS──> Spring Boot ──연결 성공──> WireMock
 │                  │                      └─ 응답을 5초 지연
 └──2 RPS───> /api/info

Spring Read Timeout: 1초
k6 Client Timeout:   3초
WireMock 지연:       5초
```

- Spring Boot와 WireMock은 3단계 전용 Docker Compose 네트워크에서 실행한다.
- WireMock 제어 API로 15~40초 구간에만 5초 고정 지연을 적용한다.
- Spring은 약 1초 뒤 `read_timeout`으로 분류하고 사용자에게 HTTP 504를 반환한다.
- k6는 같은 실행 중 `/api/info`를 계속 호출해 다른 기능의 가용성을 확인한다.

## 실험 시간

| 구간 | 외부 API 상태 | 예상 결과 |
|---|---|---|
| 0~15초 | 정상 응답 | HTTP 200, 짧은 응답시간 |
| 15~40초 | 연결 후 응답 5초 지연 | 약 1초 뒤 Spring이 HTTP 504 반환 |
| 40~60초 | 지연 제거 | HTTP 200 흐름으로 복구 |

외부 기능은 하나의 10 RPS 시나리오로 유지하며 `150건 정상 → 250건 지연 → 200건 복구`로 구간을 나눈다. `/api/info`는 전체 구간에 2 RPS로 호출한다.

## 실행

관측 환경을 시작한다.

```bash
bash scripts/observability/start.sh
```

3단계 애플리케이션과 WireMock을 시작한다.

```bash
bash scripts/external-api/step-03/start.sh
```

실험을 실행한다.

```bash
bash scripts/external-api/step-03/run-experiment.sh
```

Grafana에서 현재 실행 ID를 선택한다.

<http://localhost:3000/d/external-api-step-03-read-timeout>

k6 실행 중에는 <http://127.0.0.1:5665>에서 실시간 지표를 볼 수 있다. 실행 후에는 `results/external-api/step-03/<실행 ID>/k6-report.html`을 브라우저에서 연다.

실험용 컨테이너를 종료한다.

```bash
bash scripts/external-api/step-03/stop.sh
```

## 1단계와 비교할 관측 항목

| 관측 항목 | 1단계: Read Timeout 없음 | 3단계: Read Timeout 1초 |
|---|---:|---:|
| 외부 지연 | 5초 | 5초 |
| 외부 기능 사용자 결과 | 3초 Client Timeout | 약 1초 후 HTTP 504 예상 |
| 외부 처리 중 요청 | 최대 39개 | 약 10개 예상 |
| Tomcat 사용 중 Thread | 최대 40/40개 | 약 11/40개 예상 |
| 정상 API | 121건 중 21건 Timeout | 모두 가용 예상 |

### 사용자 응답 결과

- 정상·복구 구간: HTTP 200
- 지연 구간: Spring Read Timeout 후 HTTP 504
- k6 Client Timeout: 0건

### Spring 외부 호출

- `external_api_failures_total{reason="read_timeout"}`이 지연 구간에만 증가
- `connect_timeout`은 발생하지 않음
- 외부 API 처리 중 요청 수가 `10 RPS × 약 1초` 수준으로 제한

### 서버 전체 가용성

- Tomcat 사용 중 Thread가 최대 40개보다 충분히 낮게 유지
- `/api/info`가 HTTP 200이면서 1초 안에 완료되는 비율이 100%에 가깝게 유지
- k6 `dropped_iterations` 0건

## 완료 기준

- [x] TCP 연결 후 응답만 5초 늦어지는 장애가 재현된다.
- [x] Spring이 약 1초 후 HTTP 504를 반환한다.
- [x] k6 Client Timeout은 발생하지 않는다.
- [x] Spring 메트릭에서 실패 원인이 `read_timeout`으로 분류된다.
- [x] 외부 처리 중 요청과 Tomcat Thread가 제한된다.
- [x] 정상 API 가용 요청 비율이 유지된다.
- [x] k6 JSON과 HTML 결과가 실행 ID별로 저장된다.

## 실제 검증 결과

2026-07-27 실행 ID `20260727-100600`에서 다음 결과를 확인했다.

| 관측 항목 | 결과 | 의미 |
|---|---:|---|
| 정상·복구 외부 기능 | HTTP 200 350건 | 정상 150건과 복구 200건이 모두 성공 |
| 응답 지연 외부 기능 | HTTP 504 250건 | 모든 지연 요청을 서버가 명시적으로 종료 |
| 응답 지연 p95 | 약 1.02초 | Read Timeout 1초가 의도대로 동작 |
| k6 Client Timeout | 0건 | 클라이언트 제한 3초보다 서버 실패 응답이 먼저 도착 |
| Spring `read_timeout` | 250건 | 연결 후 응답 대기 실패로 정확히 분류 |
| Spring `connect_timeout` | 0건 | TCP 연결 단계에는 문제가 없었음을 확인 |
| 외부 API 처리 중 요청 | 최대 10개 | `10 RPS × 약 1초` 수준으로 동시 점유 제한 |
| Tomcat 사용 중 Thread | 최대 11/40개 | 공유 Thread Pool이 포화되지 않음 |
| 정상 API | 121/121건 가용 | 모두 HTTP 200이면서 1초 안에 완료 |
| 정상 API p95 | 약 10.36ms | 외부 응답 지연이 정상 API에 전파되지 않음 |
| k6 누락 요청 | 0건 | 설정한 유입량을 끝까지 유지 |

외부 기능 요청은 최대 600건으로 제한해 `150건 정상 → 250건 지연 → 200건 복구`가 정확히 유지된다. 전체 k6 iteration은 외부 기능 시나리오의 경계 no-op 1건과 정상 API 120~121건을 포함할 수 있으므로, 기능별 Counter를 기준으로 결과를 읽는다.

## 결과 파일

`results/external-api/step-03/<실행 ID>/`에 다음 파일을 로컬로 누적한다.

- `server.log`
- `k6-summary.json`
- `k6-metrics.json`
- `k6-report.html`

## 다음 단계

4단계에서는 Timeout을 적용해도 외부 장애가 지속되는 동안 모든 요청이 매번 외부 호출을 시도하고 실패하는 한계를 확인한다. 이후 5단계에서 Circuit Breaker로 불필요한 호출 자체를 줄인다.
