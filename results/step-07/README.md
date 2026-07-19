# Step 07 Results

Blue/Green 전환 후 Redis 공유 세션이 유지되는 실험 결과가 저장됩니다.

- `<실행 ID>/`: Redis에 저장한 세션 유지 결과
- `cookies.txt`: Blue에서 발급받은 세션 쿠키
- `session-before-switch.json`: 전환 전 Blue 세션 응답
- `session-after-switch.json`: 전환 후 Green 세션 응답
- `server-blue.log`, `server-green.log`: 서버별 세션 조회 로그
- `k6-summary.json`, `k6-metrics.json`: 세션 가시화 실행 결과

실행 결과 디렉터리는 로컬에만 보관하며 Git에는 이 안내 파일만 포함합니다.
