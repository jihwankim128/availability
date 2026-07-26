# 1단계: 외부 API 지연 전파

> 상태: 완료. 외부 API 지연이 Tomcat Thread를 포화시키고 관계없는 정상 API의 가용성까지 떨어뜨리는 것을 확인했다.

## 목적

외부 API에 서비스 기준의 명시적 Timeout 같은 보호 장치가 없을 때 응답 지연이 우리 서버와 사용자에게 그대로 전달되는 모습을 확인한다. 이 단계는 Connect/Read Timeout과 Circuit Breaker를 적용하기 전 비교 기준이다.

## 구성

```text
k6 --외부 기능 10 RPS--> Spring Boot :8080 --HTTP--> WireMock :9091
  \--정상 API 2 RPS--->       |
                              +--Actuator--> Prometheus --> Grafana
k6 --Remote Write--------------------------------------->
```

- Spring Boot: 실제 프로덕션 코드와 같은 `RestClient`로 외부 API 호출
- Tomcat: `T4g Micro` 학습 조건을 단순화해 최대 Thread를 40개로 고정
- WireMock: Docker 컨테이너로만 실행하고 정상 응답과 5초 지연을 제공
- k6 외부 기능: `/api/external/featured-product`에 초당 10개 요청을 고정
- k6 정상 API: 외부 API를 사용하지 않는 `/api/info`에 초당 2개 요청을 고정
- k6 Client Timeout: 두 API 모두 3초로 고정해 외부 지연 5초보다 먼저 사용자가 요청을 포기하도록 구성
- Prometheus: k6 결과와 Spring의 외부 호출 메트릭 수집
- Grafana: 장애 시점, 두 API 응답시간·가용 요청 비율, Tomcat Thread, 외부 처리 중 요청 수를 같은 시간축에 표시

Mock 서버는 애플리케이션 코드에 포함하지 않는다. `EXTERNAL_API_BASE_URL`만 실습에서는 WireMock 주소로 지정하며, 이후 단계도 같은 `ExternalApiClient`와 엔드포인트를 재사용한다.

WireMock은 지연 응답 자체가 병목이 되지 않도록 비동기 응답 모드와 100개의 요청·응답 스레드를 사용한다. 요청별 verbose 로그도 비활성화한다. 이 설정이 없으면 Mock 서버가 먼저 포화되어 의도한 5초 지연보다 대기시간이 길어질 수 있다.

## 실험 시간

전체 실험은 60초이며 k6가 WireMock의 상태 시나리오를 자동으로 변경한다. 외부 API 응답에만 지연을 적용하므로 장애 주입과 복구를 수행하는 제어 요청은 지연되지 않는다.

| 구간 | 외부 API 상태 | 예상 결과 |
|---|---|---|
| 0~15초 | 정상 | 외부 기능과 정상 API가 빠르게 완료됨 |
| 15~40초 | 모든 응답 5초 지연 | 3초를 기다린 외부 기능 클라이언트 실패, Tomcat Thread 40개 포화, 정상 API 지연·실패 |
| 40~60초 | 정상 복구 | 밀린 요청이 완료되며 Thread와 두 API 지표가 정상 수준으로 복구 |

`constant-vus`가 아니라 `constant-arrival-rate`를 사용한다. 응답이 느려져도 외부 기능 10 RPS와 정상 API 2 RPS 유입을 유지해야 외부 응답을 기다리는 요청이 누적되고 관계없는 요청까지 밀리는 모습을 확인할 수 있기 때문이다.

## 실행

Prometheus와 Grafana를 시작한다.

```bash
bash scripts/observability/start.sh
```

WireMock과 Spring Boot를 시작한다.

```bash
bash scripts/external-api/step-01/start.sh
```

실험을 실행한다. 장애 주입과 복구는 k6가 각각 15초와 40초에 자동으로 수행한다.

```bash
bash scripts/external-api/step-01/run-experiment.sh
```

Grafana에서 현재 실행 ID를 선택한다.

<http://localhost:3000/d/external-api-step-01-latency-propagation>

실험이 끝나면 Spring Boot와 WireMock을 종료한다.

```bash
bash scripts/external-api/step-01/stop.sh
```

Prometheus와 Grafana는 과거 그래프 비교를 위해 계속 실행된다. 관측 환경까지 종료하려면 다음 명령을 별도로 실행한다.

```bash
bash scripts/observability/stop.sh
```

## 관측 항목

### 외부 API 장애 주입 구간

- `0`: 정상
- `1`: WireMock 5초 지연
- 15초에 `0 → 1`, 40초에 `1 → 0`으로 변경되는지 확인한다.

### 사용자 요청 응답시간

- 정상 구간: 수십 ms 수준
- 지연 구간: 클라이언트가 최대 3초를 기다린 뒤 Timeout으로 실패
- 복구 구간: 정상 수준으로 하락

k6가 3초 뒤 연결을 포기해도 Spring의 동기식 외부 호출이 즉시 취소된다고 보장할 수 없다. 서버에는 outbound Timeout이 없으므로 Tomcat Thread가 WireMock의 5초 응답을 계속 기다리는지 함께 확인한다.

### 정상 API 응답시간과 가용 요청 비율

- `/api/info`는 외부 API를 사용하지 않는다.
- HTTP 200이면서 1초 안에 완료된 요청만 가용한 요청으로 계산한다.
- 정상 구간에는 가용 요청 비율이 100%에 가깝게 유지된다.
- Tomcat Thread 포화 구간에는 응답시간이 상승하고 가용 요청 비율이 하락한다.
- 외부 API 복구 후 다시 정상 수준으로 돌아온다.

### 외부 API 호출 응답시간

- Spring 애플리케이션에서 측정한 실제 외부 HTTP 호출시간
- 사용자 응답시간과 거의 같은 시점에 약 5초로 상승하는지 확인한다.

### 외부 API 처리 중 요청 수

- 정상 구간: 거의 0
- 제한이 없다면 `10 RPS × 5초`로 약 50개가 필요하지만, Tomcat 최대 Thread가 40개이므로 실제 값은 약 40개에서 포화
- 복구 후: 0으로 감소

### Tomcat Thread

- 정상 구간: 사용 중 Thread가 최대 40개보다 충분히 낮음
- 지연 구간: 외부 API 응답을 기다리며 사용 중 Thread가 40개에 도달
- 복구 구간: 밀린 요청이 완료되며 사용 중 Thread가 정상 수준으로 감소

### 초당 완료 처리량

- 외부 기능 10 RPS와 정상 API 2 RPS를 계속 시작한다.
- 장애 구간에는 외부 기능의 성공이 줄고 3초 뒤 Client Timeout 실패가 나타난다.
- 복구 순간에는 지연 중이던 요청과 새 요청이 함께 완료될 수 있다.

## 초안에서 확인한 기준

- 60초 동안 약 600개의 사용자 요청을 시작한다.
- 사용자 HTTP 실패와 k6 `dropped_iterations`가 없다.
- 지연 구간의 사용자 p95 응답시간이 4초를 초과한다.
- 외부 API 지연 중 처리 중 요청 수가 증가하고 복구 후 0으로 돌아온다.
- Grafana에서 정상, 지연, 복구 구간이 같은 시간축에 구분된다.

## 보강 후 완료 기준

- [x] Tomcat 최대 Thread를 실험값으로 고정하고 Grafana에서 사용 중 Thread가 한계에 도달하는지 확인한다.
- [x] 외부 API 사용 요청과 정상 API 요청을 동시에 보내고 서로 다른 시계열로 표시한다.
- [x] 지연 구간에 정상 API의 응답시간 또는 제한 시간 내 성공률이 악화되는지 확인한다.
- [x] 정상 API의 `HTTP 200`뿐 아니라 발표에서 정한 응답시간 안에 끝난 요청을 가용한 요청으로 계산한다.
- [x] 외부 API가 복구되면 사용 중 Thread와 두 API의 응답시간·성공률이 정상 수준으로 돌아오는지 확인한다.
- [x] 외부 API 지연보다 짧은 Client Timeout을 적용해 사용자가 서버 응답을 포기하는 실패를 확인한다.
- [x] 클라이언트가 포기한 뒤에도 outbound 호출을 기다리는 서버 Thread가 즉시 해소되지 않는지 확인한다.

## 실제 검증 결과

2026-07-24 실행 ID `20260724-172458`에서 다음 결과를 확인했다.

| 관측 항목 | 결과 | 의미 |
|---|---:|---|
| 외부 기능 요청 | 성공 600건, 실패 0건 | 요청 유실 없이 지연과 회복을 끝까지 관측 |
| 외부 기능 p95 | 9.07초 | 5초 외부 지연에 Thread 대기열이 더해져 사용자 대기시간이 증가 |
| 외부 API 처리 중 요청 | 최대 39개 | 외부 응답 대기 요청이 서버 자원을 점유 |
| Tomcat 사용 중 Thread | 최대 40/40개 | 공유 Thread Pool이 완전히 포화 |
| 정상 API 요청 | 성공 120건, 실패 1건 | 외부 API를 사용하지 않아도 한 요청은 제한 시간 초과 |
| 정상 API p95 | 4.14초 | 관계없는 `/api/info`까지 장애가 전파 |
| 정상 API 가용 요청 | 80/121건 | `HTTP 200 + 1초 이내` 기준으로 약 66.1%만 가용 |
| k6 누락 요청 | 0건 | 부하 발생기 용량 부족이 아니라 서버 내부 경합으로 확인 |

Grafana에서는 외부 장애 주입 구간, 외부 기능·정상 API 응답시간, 외부 처리 중 요청, Tomcat Thread `40/40`, 정상 API 가용 요청 비율과 복구를 같은 시간축에서 확인한다. 순간 포화를 그래프 간격에서 놓치지 않도록 처리 중 요청과 사용 중 Thread는 10초 구간 최댓값을 표시한다.

### 3초 Client Timeout 적용 결과

2026-07-26 실행 ID `20260726-195355`에서는 두 사용자 요청에 3초 Client Timeout을 적용했다.

| 관측 항목 | 결과 | 의미 |
|---|---:|---|
| 외부 기능 요청 | 성공 379건, Timeout 221건 | 정상·복구 구간은 성공하고 외부 지연 구간의 사용자는 3초 뒤 요청을 포기 |
| 외부 기능 p95 | 2.99초 | Client Timeout이 사용자 최대 대기시간을 제한 |
| 외부 API 처리 중 요청 | 최대 39개 | 클라이언트가 포기해도 서버의 동기식 outbound 호출은 즉시 해소되지 않음 |
| Tomcat 사용 중 Thread | 최대 40/40개 | Client Timeout만으로는 서버의 Thread 포화를 해결하지 못함 |
| 정상 API 요청 | 성공 100건, Timeout 21건 | 외부 API를 사용하지 않는 요청에도 사용자 관점의 실패가 전파 |
| 정상 API p95 | 2.99초 | 정상 API도 Client Timeout 한계까지 대기 |
| 정상 API 가용 요청 | 80/121건 | `HTTP 200 + 1초 이내` 기준으로 약 66.1%만 가용 |
| 전체 HTTP 실패 | 242/725건 | 클라이언트 관점 실패율 약 33.4% |
| k6 누락 요청 | 0건 | 부하 발생기 용량 부족 없이 요청 유입을 유지 |

이 결과가 2단계의 비교 기준이다. 2단계에서도 k6 Client Timeout은 3초로 유지하고, Spring의 outbound Timeout만 추가해 사용자 실패와 서버 Thread 점유 시간이 얼마나 줄어드는지 비교한다.

### k6 HTML 결과 확인

2026-07-26 실행 ID `20260726-203451`에서 같은 실험을 다시 실행해 `k6-report.html`이 생성되는 것을 확인했다. 이 실행에서는 외부 기능이 성공 379건·Timeout 222건, 정상 API가 성공 100건·Timeout 20건으로 집계됐으며, HTML 안에서 요청 수·실패율·응답시간 등의 k6 메트릭을 그래프로 다시 볼 수 있다.

## 결과 파일

`results/external-api/step-01/<실행 ID>/`에 다음 파일을 남긴다.

- `server.log`: Spring Boot 실행 로그
- `k6-summary.json`: 요청 수, 실패율, p95 등 집계 결과
- `k6-metrics.json`: 시간대별 원본 k6 메트릭
- `k6-report.html`: 브라우저에서 그래프로 다시 확인하는 k6 Web Dashboard 결과

실행 결과는 로컬에만 누적하고 Git에는 결과 구조만 공유한다.

## 다음 단계

2단계에서는 Connect Timeout과 Read Timeout을 명시한다. 연결 단계의 네트워크 장애와 연결 후 5초 응답 지연을 나누어 관측하고, 사용자 요청이 설정한 제한 시간 안에 실패하며 처리 중 요청 수가 빠르게 해소되는지 비교한다.
