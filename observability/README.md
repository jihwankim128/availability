# Observability

종료 동작과 세션 연속성을 Grafana에서 확인하기 위한 로컬 관측 환경이다.

## 구성

- Prometheus: k6 Remote Write 메트릭을 7일 동안 로컬 볼륨에 저장
- Grafana: 한글 제목과 범례가 적용된 대시보드 제공
- Loki: 다중 서버 로그 수집이 필요한 후속 단계에서 검토

Grafana 대시보드는 `observability/grafana/dashboards`의 JSON 파일을 기준으로 동기화한다. 파일을 이름 변경하거나 삭제하면 Grafana의 기존 대시보드 항목도 정리되지만, Prometheus에 저장된 실험 메트릭은 유지된다.

학습을 위해 `user-1`부터 `user-5`까지 고정된 사용자 ID를 Prometheus 라벨로 사용한다. 실제 서비스의 제한되지 않은 사용자 ID를 메트릭 라벨로 사용하는 방식은 권장하지 않는다.

## 실행

```bash
bash scripts/observability/start.sh
```

- Grafana: <http://localhost:3000/d/step-02-immediate-shutdown>
- 세션 연속성 대시보드: <http://localhost:3000/d/session-continuity>
- 외부 API 지연 대시보드: <http://localhost:3000/d/external-api-step-01-latency-propagation>
- 계정: `admin` / `admin`
- Prometheus: <http://localhost:9090>

## 종료

```bash
bash scripts/observability/stop.sh
```

종료해도 Prometheus와 Grafana의 Docker 볼륨은 유지된다.
