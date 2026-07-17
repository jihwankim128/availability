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

## 실습 1: 무중단 배포

### 진행 현황

- [x] 1단계: 관측용 장기 요청 API와 버전·인스턴스 정보 추가
- [ ] 2단계: Immediate Shutdown에서 처리 중 요청 중단 확인
- [ ] 3단계: Graceful Shutdown에서 처리 중 요청 완료 확인
- [ ] 4단계: 단일 서버 재배포 중 신규 요청 중단 확인
- [ ] 5단계: Blue/Green 배포로 요청 중단 제거
- [ ] 후속 과제: 서버 버전 혼재에 따른 세션·캐시 문제 확인

### History

#### 2026-07-18 — 1단계: 요청 관측 기반 구성

- 장기 처리 요청을 만드는 `/api/work` 추가
- 서버 버전과 인스턴스를 확인하는 `/api/info` 추가
- 요청 ID, 서버 버전, 인스턴스, 시작·완료 시각을 로그와 응답으로 확인

### 1단계 실행 방법

먼저 요청을 관측하기 위한 API를 실행합니다.

```bash
./gradlew bootRun
```

현재 서버의 버전과 인스턴스를 확인합니다.

```bash
curl http://localhost:8080/api/info
```

10초 동안 처리되는 요청을 실행합니다. 서버 로그와 응답에서 요청 ID, 버전, 인스턴스, 시작·완료 시각을 확인할 수 있습니다.

```bash
curl 'http://localhost:8080/api/work?seconds=10'
```
