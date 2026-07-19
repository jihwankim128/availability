# Step 06 Results

Blue/Green 전환 후 로컬 세션이 유실되는 실험 결과가 저장됩니다.

- `<실행 ID>/`: 서버 메모리에 저장한 세션 유실 결과
- `cookies.txt`: Blue에서 발급받은 세션 쿠키
- `session-before-switch.json`: 전환 전 Blue 세션 응답
- `session-after-switch.json`: 전환 후 Green 세션 응답
- `server-blue.log`, `server-green.log`: 서버별 세션 조회 로그
- `k6-summary.json`, `k6-metrics.json`: 세션 가시화 실행 결과

실행 결과 디렉터리는 로컬에만 보관하며 Git에는 이 안내 파일만 포함합니다.
