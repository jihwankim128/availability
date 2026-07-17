# Step 05: Blue/Green 무중단 배포

## 목표

기존 Blue 서버가 요청을 처리하는 동안 Green 서버를 먼저 준비하고, 준비가 끝난 뒤 트래픽을 전환하여 새 요청의 중단 없이 v2를 배포한다.

4단계의 단일 서버 재배포 파일은 변경하지 않는다. 이 실험은 `blue-green` Profile, Spring Boot Actuator readiness, Nginx 프록시, 5단계 전용 스크립트를 사용한다.

## 실험 구조

- Nginx가 `localhost:8080`에서 클라이언트 요청을 받는다.
- 최초에는 Blue v1(`localhost:8081`)으로 모든 요청을 전달한다.
- Blue가 계속 요청을 처리하는 동안 Green v2(`localhost:8082`)를 시작한다.
- Green의 `/actuator/health/readiness`가 연속 3회 `UP`이고 서버 정보가 v2인 것을 확인한 뒤 Nginx 설정을 reload하여 트래픽을 전환한다.
- Green 전환을 확인한 뒤 Blue를 Graceful Shutdown한다.

이 단계는 고가용성이나 다중 인스턴스 로드밸런싱을 다루지 않는다. Blue와 Green은 각각 한 개이며, Nginx는 활성 환경으로 요청을 전달하는 reverse proxy와 트래픽 스위치 역할을 한다.

Nginx OSS가 Green을 능동적으로 헬스체크하는 구조가 아니라 배포 스크립트가 readiness를 확인하는 구조다. 배포 스크립트는 `nginx -t`, graceful reload, 프록시를 통한 Green 연속 확인까지 성공해야 Blue를 종료한다. 전환 전에 실패하면 Nginx 설정을 Blue로 복구하고 Green을 종료한다.

Nginx reload는 기존 worker가 처리 중인 연결을 마무리하면서 새 worker가 Green으로 새 연결을 전달하도록 한다. k6는 연결을 재사용하지 않아 전환 이후의 새 요청이 Green으로 향하는 것을 명확히 관측한다.

## 실행

Docker가 실행 중이어야 한다. Nginx는 Docker 컨테이너로만 실행하며 로컬 시스템에 설치하거나 `/etc/nginx` 설정을 변경하지 않는다. 실행 중 생성되는 설정은 Git에서 제외된 `build/step-05/`에만 저장되고, `stop-all.sh`가 컨테이너와 Compose 네트워크를 정리한다.

터미널 A에서 Blue v1과 Nginx를 시작한다.

```bash
bash scripts/step-05/start-blue.sh
```

터미널 B에서 40초 동안 지속 요청을 실행한다.

```bash
bash scripts/step-05/run-k6-dashboard.sh
```

k6 Web Dashboard에서 v1 요청이 성공하는 것을 확인한 뒤 터미널 C에서 Green을 배포한다.

```bash
bash scripts/step-05/deploy-green.sh
```

k6 실행이 끝난 뒤 모든 프로세스와 Nginx를 종료한다.

```bash
bash scripts/step-05/stop-all.sh
```

k6 실행 중에는 `http://127.0.0.1:5665`에서 실시간 그래프를 확인한다. 실행 후에는 `results/step-05/<실행 ID>/k6-report.html`에서 다시 볼 수 있다.

## 검증 기준

- k6 요청이 Blue v1 응답에서 Green v2 응답으로 전환된다.
- `deployment_version_signal`은 `v1(1) → v2(2)`로 바뀌며 `0`이 기록되지 않는다.
- `http_req_failed`는 `0%`다.
- `checks` 성공률은 `100%`다.
- `deployment_unavailable_response`는 0이다.
- Blue와 Green 응답이 모두 존재한다.
- Green 전환이 확인된 뒤 Blue의 Graceful Shutdown 로그가 기록된다.
- Green readiness 또는 Nginx 전환 검증이 실패하면 Blue가 계속 요청을 처리한다.

## 검증 결과

2026-07-18 실행(`20260718-055800`)에서 다음 결과를 확인했다.

- VU 5명이 40초 동안 총 200개의 HTTP 요청을 보냈다.
- Blue v1 응답은 65개, Green v2 응답은 135개였다.
- HTTP 요청 실패와 `deployment_unavailable_response`는 모두 0개였다.
- `deployment_version_signal`에는 `v1(1)`과 `v2(2)`만 기록되고 실패 `(0)`은 기록되지 않았다.
- k6 시간 그래프에서 요청 중단 없이 Blue 응답이 Green 응답으로 전환되는 것을 확인했다.
- Green 전환 후 Blue 서버에 Graceful Shutdown 로그가 기록됐다.

실행 결과 파일은 Git에 포함하지 않고 로컬 `results/step-05/20260718-055800/`에 보관한다.
