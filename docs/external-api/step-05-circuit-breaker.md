# 5단계: Circuit Breaker로 장애 전파 차단

> 상태: 완료. 4단계와 같은 장애·부하 조건에서 Circuit Breaker가 불필요한 외부 호출을 줄이고 정상 API 가용성을 보호하는 것을 확인했다.

## 목적

Read Timeout은 호출 하나의 대기시간을 제한하지만 외부 장애 중에도 모든 요청이 외부 API 호출을 시도한다. Circuit Breaker는 최근 실패율이 임계치를 넘으면 일정 시간 실제 호출을 차단하고 빠르게 실패시킨다.

외부 기능은 장애 중 HTTP 503을 받으므로 정상화되지 않는다. 이번 단계의 성공 기준은 **고장 난 기능을 성공시키는 것**이 아니라 **장애가 관계없는 정상 API까지 전파되지 않도록 서비스의 나머지 가용성을 지키는 것**이다.

## 4단계와 동일하게 유지하는 조건

- 외부 API: WireMock 응답 5초 지연
- 외부 기능 유입: 정상·복구 10 RPS, 장애 중 50 RPS
- 독립적인 정상 API `/api/info`: 2 RPS
- Spring Connect/Read Timeout: 각각 1초
- k6 Client Timeout: 3초
- Tomcat 최대 Thread: 40개
- 총 관측 시간: 70초

변경점은 Circuit Breaker 적용 하나뿐이므로 4단계와 직접 비교할 수 있다.

## Circuit Breaker 설정

| 설정 | 값 | 학습 목적 |
|---|---:|---|
| Sliding Window | 최근 20회 | 짧은 실험에서 최근 실패율 계산 |
| Minimum Calls | 20회 | 20회 전에는 성급하게 차단하지 않음 |
| Failure Rate Threshold | 50% | 실패가 절반 이상이면 OPEN |
| Open Duration | 10초 | 10초 동안 실제 외부 호출 차단 |
| Half-open Calls | 5회 | 5회 시험 호출로 회복 여부 확인 |

Resilience4j core API를 직접 적용한다. 외부 API별 상태와 지표를 분리하기 위해 `externalApi`라는 전용 Circuit Breaker 인스턴스를 사용한다.

## 상태 전환

```text
CLOSED ──최근 20회 중 50% 이상 실패──> OPEN
   ▲                                  │
   │                                  │ 10초 후
   │                                  ▼
   └────시험 호출 5회 성공────── HALF_OPEN
                  │
                  └─실패하면 다시 OPEN
```

- `CLOSED`: 요청을 외부 API로 전달하고 결과를 기록한다.
- `OPEN`: 외부 API를 호출하지 않고 즉시 HTTP 503을 반환한다.
- `HALF_OPEN`: 제한된 시험 호출로 복구 여부를 확인한다.

HTTP 504는 실제 외부 호출이 Read Timeout에 도달했다는 뜻이고, HTTP 503은 Circuit Breaker가 외부 호출 전에 차단했다는 뜻이다.

## 실험 시간

| 구간 | 외부 API | 외부 기능 유입 | 예상 상태와 결과 |
|---|---|---:|---|
| 0~10초 | 정상 | 10 RPS | CLOSED, HTTP 200 |
| 10~50초 | 5초 지연 | 50 RPS | 초기 504 후 OPEN, 대부분 즉시 503 |
| 장애 중 매 10초 | 5초 지연 | 50 RPS | HALF_OPEN 시험 실패 후 다시 OPEN |
| 50~70초 | 정상 복구 | 10 RPS | HALF_OPEN 시험 성공 후 CLOSED, HTTP 200 |

## 실행

관측 환경과 5단계 애플리케이션을 시작한다.

```bash
bash scripts/observability/start.sh
bash scripts/external-api/step-05/start.sh
```

실험을 실행한다.

```bash
bash scripts/external-api/step-05/run-experiment.sh
```

Grafana에서 현재 실행 ID를 선택한다.

<http://localhost:3000/d/external-api-step-05-circuit-breaker>

k6 실행 중에는 <http://127.0.0.1:5665>에서 실시간 지표를 볼 수 있다. 실행 후에는 `results/external-api/step-05/<실행 ID>/k6-report.html`을 브라우저에서 연다.

실험용 컨테이너를 종료한다.

```bash
bash scripts/external-api/step-05/stop.sh
```

## 관측 항목

- Circuit Breaker의 `CLOSED → OPEN → HALF_OPEN → CLOSED` 전환
- 실제 외부 호출, Read Timeout, 즉시 차단 요청의 초당 발생량
- 사용자 결과 HTTP 200·504·503과 k6 Client Timeout
- 외부 API 처리 중 요청과 Tomcat 사용 중 Thread
- `/api/info` 성공·실패, 1초 이내 가용 요청 비율과 p95
- 외부 API 복구 후 HTTP 200과 CLOSED 상태 회복

## 완료 기준

- [x] 장애 감지 후 Circuit Breaker가 OPEN 상태로 전환된다.
- [x] OPEN 상태의 요청은 외부 API를 호출하지 않고 HTTP 503으로 빠르게 끝난다.
- [x] 장애 중 HALF_OPEN 시험 실패 후 다시 OPEN으로 돌아간다.
- [x] 외부 API 복구 후 HALF_OPEN을 거쳐 CLOSED로 돌아간다.
- [x] k6 Client Timeout과 정상 API 실패가 0건이다.
- [x] 정상 API 요청이 모두 1초 안에 완료된다.
- [x] 실제 외부 호출과 Read Timeout이 4단계보다 크게 감소한다.
- [x] k6 `dropped_iterations`는 0건이다.
- [x] k6 JSON과 HTML 결과가 실행 ID별로 저장된다.

## 실제 검증 결과

2026-07-28 실행 ID `20260728-080147`에서 다음 결과를 확인했다.

| 관측 항목 | 4단계 Timeout만 적용 | 5단계 Circuit Breaker 적용 |
|---|---:|---:|
| 외부 기능 전체 요청 | 2,299건 | 2,299건 |
| 외부 기능 HTTP 200 | 464건 | 251건 |
| 외부 기능 HTTP 504 | 412건 | 64건 |
| Circuit OPEN HTTP 503 | 없음 | 1,984건 |
| k6 Client Timeout | 1,423건 | 0건 |
| Spring `read_timeout` | 1,581건 | 64건 |
| 실제 외부 호출 | 약 2,046건 | 316건 |
| 외부 API 처리 중 요청 | 최대 39개 | 최대 26개 |
| Tomcat 사용 중 Thread | 최대 40/40개 | 최대 27/40개 |
| 정상 API HTTP 200 | 92/141건 | 141/141건 |
| 정상 API 가용 요청 | 72/141건, 약 51.1% | 141/141건, 100% |
| 정상 API p95 | 약 2.99초 | 약 10.57ms |
| 실제 최대 VU | 156명 | 29명 |
| k6 누락 요청 | 0건 | 0건 |

Circuit Breaker는 장애 중 외부 기능을 성공시키지 않았다. 대신 1,984건을 외부 API에 보내지 않고 즉시 끝내 실제 외부 호출을 약 84.6%, Read Timeout을 약 96.0% 줄였다. 그 결과 4단계에서 포화됐던 Tomcat Thread가 최대 27개로 제한되고, 관계없는 정상 API 가용성은 51.1%에서 100%로 회복됐다.

서버 로그에서도 다음 순서를 확인했다.

```text
CLOSED → OPEN
OPEN → HALF_OPEN → OPEN  (장애 중 세 차례)
OPEN → HALF_OPEN → CLOSED (외부 API 복구 후)
```

## 결과 파일

`results/external-api/step-05/<실행 ID>/`에 다음 파일을 로컬로 누적한다.

- `server.log`
- `k6-summary.json`
- `k6-metrics.json`
- `k6-report.html`

## 참고

- [Resilience4j CircuitBreaker 공식 문서](https://resilience4j.readme.io/docs/circuitbreaker)
- [Resilience4j Micrometer 공식 문서](https://resilience4j.readme.io/docs/micrometer)
