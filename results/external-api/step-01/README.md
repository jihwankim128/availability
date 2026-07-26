# External API Step 01 Results

외부 API 지연이 사용자 요청과 애플리케이션 처리량에 전파되는 실험 결과가 저장됩니다.

- `<실행 ID>/server.log`: Spring Boot 실행 로그
- `<실행 ID>/k6-summary.json`: k6 집계 결과
- `<실행 ID>/k6-metrics.json`: 시간대별 원본 k6 메트릭
- `<실행 ID>/k6-report.html`: 그래프로 다시 확인할 수 있는 k6 Web Dashboard HTML

실행 결과 디렉터리는 로컬에만 보관하며 Git에는 이 안내 파일만 포함합니다.
