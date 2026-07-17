# Step 03 Results

검증할 때마다 실행 시각을 ID로 사용하는 하위 폴더를 만들고 다음 결과를 로컬에 누적한다.

- `<실행 ID>/server.log`: SIGTERM 이후 요청 완료까지의 애플리케이션 로그
- `<실행 ID>/k6-report.html`: k6 Web Dashboard HTML
- `<실행 ID>/k6-summary.json`: k6 메트릭 요약
- `<실행 ID>/k6-metrics.json`: 사용자 태그가 포함된 k6 시계열 원본

실제 실행 결과는 Git에 포함하지 않는다.
