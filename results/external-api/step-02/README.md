# External API Step 02 Results

TCP 연결 장애에 Connect Timeout을 적용한 실험 결과가 저장됩니다.

- `<실행 ID>/server.log`: Spring Boot 컨테이너 로그
- `<실행 ID>/k6-summary.json`: k6 집계 결과
- `<실행 ID>/k6-metrics.json`: 시간대별 원본 k6 메트릭
- `<실행 ID>/k6-report.html`: 그래프로 다시 확인할 수 있는 k6 Web Dashboard HTML

실행 결과 디렉터리는 로컬에만 보관하며 Git에는 이 안내 파일만 포함합니다.
