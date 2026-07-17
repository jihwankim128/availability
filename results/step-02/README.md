# Step 02 Results

검증할 때마다 실행 시각을 ID로 사용하는 하위 폴더를 만들고 다음 결과를 누적한다.

- `<실행 ID>/server.log`: Immediate Shutdown 전후의 애플리케이션 로그
- `<실행 ID>/k6-report.html`: 발표와 재확인에 사용할 k6 Web Dashboard HTML
- `<실행 ID>/k6-summary.json`: k6 메트릭 원본 요약
- `<실행 ID>/k6-metrics.json`: 사용자 태그가 포함된 k6 시계열 원본

실제 실행 결과는 로컬에만 누적하며 Git에는 포함하지 않는다.
