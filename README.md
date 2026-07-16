# Availability

서비스 가용성을 학습하고 간단한 실습을 진행하기 위한 Spring Boot 프로젝트입니다.

## 학습 주제

### 외부 API 장애

- 외부 API의 지연과 실패가 서비스에 미치는 영향 확인
- Timeout과 Retry의 동작 이해
- Circuit Breaker를 이용한 장애 전파 방지

### 무중단 배포

- Graceful Shutdown으로 처리 중인 요청 보호
- 새 서버가 준비된 이후 트래픽 전달
- Blue/Green 방식의 배포와 빠른 롤백 실습

## 실행

```bash
./gradlew bootRun
```

Java 21과 Spring Boot 4.1.0을 사용합니다.
