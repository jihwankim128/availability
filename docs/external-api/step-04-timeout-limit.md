# 4단계: 지속 장애와 Timeout의 한계

> 상태: 완료. Read Timeout이 있어도 지속 장애와 높은 유입량에서는 Thread가 다시 포화되고 정상 API 가용성이 하락하는 것을 확인했다.

## 목적

Read Timeout이 호출 하나의 대기시간을 제한해도, 외부 장애가 지속되는 동안 유입량이 서버 처리 용량을 넘으면 공유 Thread Pool이 다시 포화될 수 있음을 확인한다. 외부 API와 관계없는 정상 API의 가용성이 다시 떨어지는 것이 핵심 관측 결과다.

Timeout이 트래픽을 만드는 것은 아니다. 외부 기능의 유입량과 Timeout까지의 자원 점유시간을 곱한 값이 서버의 동시 처리 용량을 넘는 것이 문제다.

```text
50 RPS × Read Timeout 1초 ≈ 동시 대기 50개
Tomcat 최대 Thread = 40개
```

## 장애 구성

```text
k6 ──외부 기능 50 RPS──> Spring Boot ──연결 성공──> WireMock
 │                            │                     └─ 응답을 5초 지연
 └──정상 API 2 RPS────────> /api/info

Spring Read Timeout: 1초
k6 Client Timeout:   3초
Tomcat Thread:       최대 40개
```

- 3단계와 동일하게 Connect/Read Timeout을 각각 1초로 유지한다.
- 장애 구간에만 외부 기능 유입을 10 RPS에서 50 RPS로 높인다.
- WireMock의 5초 지연은 Read Timeout보다 길기 때문에 외부 호출은 약 1초 동안 Thread를 점유한다.
- 외부 호출 대기와 Tomcat Thread가 40개에 도달하면 `/api/info`도 대기열에 갇힐 수 있다.

## 실험 시간

| 구간 | 외부 API | 외부 기능 유입 | 예상 결과 |
|---|---|---:|---|
| 0~10초 | 정상 | 10 RPS | 모든 API가 빠르게 성공 |
| 10~50초 | 5초 지연 | 50 RPS | Thread 40개 포화, 정상 API 가용성 하락 |
| 50~70초 | 정상 복구 | 10 RPS | 대기열과 Thread가 해소되고 정상 API 회복 |

`ramping-arrival-rate`를 사용해 응답이 느려져도 목표 유입량을 유지한다. 부하 발생기의 VU가 부족해 요청이 누락되는 상황과 서버가 처리하지 못하는 상황을 구분하기 위해 `dropped_iterations`는 0건이어야 한다.

## 실행

관측 환경을 시작한다.

```bash
bash scripts/observability/start.sh
```

4단계 애플리케이션과 WireMock을 시작한다.

```bash
bash scripts/external-api/step-04/start.sh
```

실험을 실행한다.

```bash
bash scripts/external-api/step-04/run-experiment.sh
```

Grafana에서 현재 실행 ID를 선택한다.

<http://localhost:3000/d/external-api-step-04-timeout-limit>

k6 실행 중에는 <http://127.0.0.1:5665>에서 실시간 지표를 볼 수 있다. 실행 후에는 `results/external-api/step-04/<실행 ID>/k6-report.html`을 브라우저에서 연다.

실험용 컨테이너를 종료한다.

```bash
bash scripts/external-api/step-04/stop.sh
```

## 관측 항목

### 외부 기능 사용자 결과

- Tomcat Thread를 배정받은 요청: 약 1초 후 HTTP 504
- 대기열에서 k6 Client Timeout 3초를 넘긴 요청: status 0
- 정상·복구 구간: HTTP 200

### 서버 자원

- 외부 API 처리 중 요청 수가 약 40개까지 증가
- Tomcat 사용 중 Thread가 `40/40`에 도달
- `read_timeout`이 장애 구간 내내 반복

### 정상 API 가용성

- `/api/info` HTTP 실패 또는 1초 초과 응답 발생
- 정상 API p95가 1초를 초과
- `HTTP 200 + 1초 이내` 가용 요청 비율이 하락
- 복구 구간에는 정상 수준으로 돌아옴

## 완료 기준

- [x] 5초 지연과 50 RPS 유입이 40초 동안 유지된다.
- [x] 외부 API 처리 중 요청이 최대 39개, Tomcat Thread가 최대 40개에 도달한다.
- [x] 서버 HTTP 504뿐 아니라 k6 Client Timeout도 발생한다.
- [x] 정상 API의 HTTP 실패와 1초 초과 응답이 발생한다.
- [x] 정상 API 가용 요청 비율이 100% 아래로 내려간다.
- [x] 복구 후 처리 중 요청과 Thread가 정상 수준으로 돌아온다.
- [x] k6 `dropped_iterations`는 0건이다.
- [x] k6 JSON과 HTML 결과가 실행 ID별로 저장된다.

## 실제 검증 결과

2026-07-28 실행 ID `20260728-010358`에서 다음 결과를 확인했다.

| 관측 항목 | 결과 | 의미 |
|---|---:|---|
| 외부 기능 HTTP 200 | 464건 | 정상·복구 구간과 대기열 해소 후 성공 |
| 외부 기능 HTTP 504 | 412건 | Thread를 배정받아 Read Timeout까지 실행된 사용자 요청 |
| 외부 기능 k6 Client Timeout | 1,423건 | Tomcat 대기열에서 사용자 제한 3초를 넘긴 요청 |
| Spring `read_timeout` | 1,581건 | 사용자가 포기한 뒤에도 서버가 계속 처리한 요청 포함 |
| 외부 API 처리 중 요청 | 최대 39개 | 외부 응답 대기가 Tomcat Thread 대부분을 점유 |
| Tomcat 사용 중 Thread | 최대 40/40개 | 공유 Thread Pool이 다시 완전히 포화 |
| 정상 API HTTP 200 | 92/141건 | 관계없는 API도 49건 실패 |
| 정상 API 가용 요청 | 72/141건 | 약 51.1%만 HTTP 200이면서 1초 안에 완료 |
| 정상 API p95 | 약 2.99초 | k6 Client Timeout 3초 한계까지 대기 |
| 실제 최대 VU | 156명 | 막힌 요청을 유지하면서 목표 유입량 생성 |
| k6 누락 요청 | 0건 | 부하 발생기 부족이 아니라 서버 포화로 확인 |
| 복구 후 서버 상태 | 처리 중 0개, 사용 중 Thread 1개 | 지연과 과부하 제거 후 정상 상태로 회복 |

사용자에게 전달된 HTTP 504 412건보다 Spring의 `read_timeout` 1,581건이 훨씬 많다. k6가 3초 뒤 연결을 포기해도 Tomcat 대기열에 들어온 작업이 자동 취소되지 않아, 서버가 이미 떠난 사용자의 외부 호출까지 계속 수행했기 때문이다. Timeout은 호출 하나의 대기시간을 제한하지만 호출 시도 자체를 줄이지는 못한다.

## 결과 파일

`results/external-api/step-04/<실행 ID>/`에 다음 파일을 로컬로 누적한다.

- `server.log`
- `k6-summary.json`
- `k6-metrics.json`
- `k6-report.html`

## 다음 단계

5단계에서는 동일한 지속 장애와 50 RPS 조건에 Circuit Breaker를 적용한다. 실패율 임계치를 넘으면 외부 호출을 즉시 차단해 대기 중 요청과 Tomcat Thread를 줄이고 정상 API 가용성을 유지하는지 비교한다.
