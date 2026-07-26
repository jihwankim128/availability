# 실습 2: 외부 API 장애 전파

외부 API 가용성 실습은 이 폴더에서 1단계부터 독립적으로 관리한다. 무중단 배포 1~7단계 기록은 루트 [`README.md`](../../README.md)에 유지한다.

## 발표 범위

10분 발표에서는 Inbound 과부하는 가용성을 위협하는 다른 경계로만 소개하고, 실제 실습은 외부 API 장애 전파에 집중한다.

- 포함: 외부 API 지연, Connect Timeout, Read Timeout, 지속 장애, Circuit Breaker
- 제외: Retry, Inbound·Outbound Rate Limit
- 후속: Bulkhead를 이용한 동시 자원 격리

## 진행 현황

- [x] 1단계: 외부 API 지연이 정상 API까지 전파되는 현상 확인
- [ ] 2단계: Connect/Read Timeout으로 외부 호출 대기 시간 제한
- [ ] 3단계: Timeout 적용 후에도 지속되는 외부 호출과 실패 확인
- [ ] 4단계: Circuit Breaker로 연쇄 장애 차단
- [ ] 후속 과제: Retry, Bulkhead, Inbound·Outbound Rate Limit, Idempotency Key

## 단계별 진행 순서

| 단계 | 실험과 관측 목표 |
|---|---|
| 1단계 | 서비스 기준의 명시적 Timeout이 없는 외부 API 지연이 Thread를 고갈시키고 정상 API까지 영향을 주는지 확인 |
| 2단계 | Connect Timeout과 Read Timeout을 명시해 호출당 대기 시간과 동시 점유 Thread를 제한 |
| 3단계 | Timeout이 있어도 지속 장애 중에는 모든 요청이 외부 호출과 실패를 반복하는 한계 확인 |
| 4단계 | Circuit Breaker의 `CLOSED → OPEN → HALF_OPEN`과 실제 외부 호출 감소, 정상 API 보호 확인 |

## History

### 2026-07-19 — 1단계 초안: 외부 API 지연 전파 기초 관측

- 초당 10개 요청을 60초 동안 보내고, 15~40초 구간에 외부 API 응답을 5초 지연
- 사용자 요청 600개가 모두 성공했지만 p95 응답 시간이 약 5.01초로 증가하는 것을 확인
- 유실 요청과 누락된 iteration은 0개였으며, 동시 처리 요청은 최대 약 50개까지 증가
- Grafana에서 장애 신호, 사용자·외부 API 응답 시간, 처리 중 요청 수, 처리량과 복구 구간을 같은 시간축으로 시각화
- Tomcat Thread 포화와 정상 API 영향이 빠져 있어 최종 1단계 완료 전 보강하기로 결정

### 2026-07-24 — 1단계: 외부 API 지연의 정상 API 전파 검증 완료

- Tomcat 최대 Thread를 40개로 고정하고 외부 기능 10 RPS와 독립적인 정상 API 2 RPS를 동시에 실행
- WireMock의 5초 지연 구간에서 외부 API 처리 중 요청이 최대 39개, Tomcat 사용 중 Thread가 `40/40`에 도달
- 외부 기능 p95가 약 9.07초, 외부 API를 사용하지 않는 `/api/info` p95도 약 4.14초까지 증가
- 정상 API 121건 중 80건만 `HTTP 200 + 1초 이내` 기준을 만족하고, 41건은 가용하지 않은 요청으로 집계
- 외부 API 복구 후 밀린 요청과 Thread가 해소되는 흐름을 Grafana의 동일 시간축에서 확인

### 2026-07-26 — 1단계 보강: 클라이언트가 서버 응답을 포기하는 흐름 추가

- 외부 기능과 정상 API의 k6 Client Timeout을 모두 3초로 고정하고 단계 간 동일하게 사용
- WireMock 5초 지연 구간에서 외부 기능 요청 221건과 정상 API 요청 21건이 Client Timeout으로 실패
- 클라이언트가 3초에 연결을 포기해도 서버의 outbound 호출은 즉시 취소되지 않아 외부 대기 요청 최대 39개와 Tomcat Thread `40/40` 포화를 확인
- Grafana에서 HTTP 성공과 Client Timeout 실패를 별도 시계열로 표시해 사용자 관점의 장애를 확인
- 실행 결과의 k6 기본 메트릭과 그래프를 `k6-report.html`로 로컬에 보존

## 단계별 문서

- [1단계: 외부 API 지연 전파](step-01-latency-propagation.md)
