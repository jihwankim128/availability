# 6단계: Blue/Green 전환 후 로컬 세션 유실

## 목적

5단계에서는 HTTP 요청이 끊기지 않았지만, 서버 메모리에만 저장한 사용자 상태는 새 서버가 알 수 없다. 6단계에서는 Blue에서 만든 세션 쿠키를 그대로 사용해도 Green 전환 후 로그인 상태가 사라지는 것을 확인한다.

이 실험의 로그인은 인증 기능을 구현하려는 것이 아니라 세션 연속성만 관찰하기 위한 가짜 로그인이다. `HttpSession`과 세션 쿠키의 동작은 실제로 사용하고, 사용자 이름 하나만 세션에 저장한다.

## 구성

- Nginx 컨테이너: `localhost:8080` 요청을 현재 서버로 전달
- Blue v1: `localhost:8081`, 프로세스 메모리에 세션 저장
- Green v2: `localhost:8082`, 별도의 프로세스 메모리에 세션 저장
- 결과: Blue에서 발급한 쿠키로 Green에 조회하면 `401 Unauthorized`

Blue와 Green이 같은 쿠키 이름을 사용하더라도 저장 공간은 서로 다르다. 서버끼리 메모리를 동기화하지 않고, Green에는 해당 세션 ID의 데이터가 없기 때문이다.

## 실행

이전 단계에서 실행 중인 서버와 컨테이너를 먼저 종료한다.

```bash
bash scripts/step-06/start-blue.sh
```

Blue에서 세션을 만들고 같은 쿠키로 조회되는지 확인한다.

```bash
bash scripts/step-06/login.sh
```

응답에서 다음 값을 확인한다.

- `version`: `v1`
- `instanceId`: `blue`
- `sessionMode`: `local`
- `username`: `crew`

Green을 준비하고 Nginx 트래픽을 전환한 뒤 Blue를 종료한다.

```bash
bash scripts/step-06/deploy-green.sh
```

Blue에서 받은 쿠키를 그대로 보내 세션을 다시 조회한다.

```bash
bash scripts/step-06/check-after-switch.sh
```

정상적인 실패 결과는 `401 Unauthorized`이다. HTTP 요청 자체는 Green에 도달했지만 사용자 관점에서는 로그인 상태가 사라졌으므로 기능 가용성이 깨진 상태다.

실습이 끝나면 종료한다.

```bash
bash scripts/step-06/stop-all.sh
```

## Grafana로 가시화

한 명의 사용자가 같은 세션 쿠키로 1초마다 요청하도록 k6를 실행한다. 먼저 Prometheus와 Grafana를 시작한다.

```bash
bash scripts/observability/start.sh
bash scripts/step-06/start-blue.sh
```

다른 터미널에서 40초 동안 세션을 조회한다. k6가 Blue에서 로그인하고 쿠키를 계속 재사용하므로 `login.sh`는 별도로 실행하지 않는다.

```bash
bash scripts/step-06/run-k6-visibility.sh
```

k6가 실행 중일 때 다른 터미널에서 Green으로 전환한다.

```bash
bash scripts/step-06/deploy-green.sh
```

Grafana의 <http://localhost:3000/d/session-continuity>에서 세션 저장소를 `local`, 실행 ID를 현재 값으로 선택한다.

여러 결과를 찾거나 비교할 때는 세션 저장소와 실행 ID의 `All`을 선택한다. `All` 상태에서는 범례의 저장소와 실행 ID로 각 선을 구분한다.

- `Blue v1 → Green v2`: 실제 응답 서버가 전환됨
- `세션 유지(3) → 세션 유실(2)`: 같은 쿠키가 Green에서는 조회되지 않음
- `200 OK → 401 Unauthorized`: 서버는 응답하지만 로그인 세션이 유실됨

이 가시화는 여러 사용자의 부하를 측정하는 실험이 아니다. 고정 사용자 `crew` 한 명이 같은 쿠키로 반복 요청해 전환 전후의 세션 상태만 선명하게 보여준다.

k6가 정상 종료되면 Prometheus에 stale marker를 전송하므로 마지막 값이 현재 시각까지 이어지지 않고 실험 종료 시점에서 그래프도 끝난다.

k6 실행과 그래프 확인이 끝나면 Blue, Green, Nginx를 종료한다.

```bash
bash scripts/step-06/stop-all.sh
```

Prometheus와 Grafana는 종료하지 않으므로 다음 실습에서도 기존 그래프를 확인할 수 있다. 가시화 환경까지 종료하려면 별도로 `bash scripts/observability/stop.sh`를 실행한다.

## 결과 파일

`results/step-06/<실행 ID>/`에 다음 파일을 남긴다.

- `session-login.json`: Blue에서 세션을 만든 응답
- `session-before-switch.json`: 전환 전 세션 조회 결과
- `session-after-switch.json`: 전환 후 `401` 응답 본문
- `cookies.txt`: 동일 사용자를 재현하기 위한 세션 쿠키
- `server-blue.log`, `server-green.log`: 인스턴스별 세션 로그
- `k6-summary.json`, `k6-metrics.json`: Grafana 가시화 실행 결과

실행 결과는 로컬에만 누적하고 Git에는 결과 구조만 공유한다.

## 다음 단계

7단계에서는 Blue와 Green이 Redis라는 외부 저장소를 함께 사용하도록 바꾼다. 서버 간 데이터를 직접 복제하는 방식이 아니라 상태를 서버 프로세스 밖으로 분리하는 방식이다.
