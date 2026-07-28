package com.example.availability.external;

import java.time.Duration;

import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreakerRegistry;
import io.github.resilience4j.micrometer.tagged.TaggedCircuitBreakerMetrics;
import io.micrometer.core.instrument.MeterRegistry;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.ResourceAccessException;

@Slf4j
@Configuration(proxyBeanMethods = false)
@ConditionalOnProperty(name = "external-api.circuit-breaker.enabled", havingValue = "true")
public class ExternalApiCircuitBreakerConfiguration {

	@Bean
	CircuitBreakerRegistry externalApiCircuitBreakerRegistry(
			MeterRegistry meterRegistry,
			@Value("${external-api.circuit-breaker.sliding-window-size:20}") int slidingWindowSize,
			@Value("${external-api.circuit-breaker.minimum-number-of-calls:20}") int minimumNumberOfCalls,
			@Value("${external-api.circuit-breaker.failure-rate-threshold:50}") float failureRateThreshold,
			@Value("${external-api.circuit-breaker.wait-duration-in-open-state:10s}") Duration waitDuration,
			@Value("${external-api.circuit-breaker.permitted-calls-in-half-open-state:5}") int permittedCallsInHalfOpenState
	) {
		CircuitBreakerConfig config = CircuitBreakerConfig.custom()
				.slidingWindowType(CircuitBreakerConfig.SlidingWindowType.COUNT_BASED)
				.slidingWindowSize(slidingWindowSize)
				.minimumNumberOfCalls(minimumNumberOfCalls)
				.failureRateThreshold(failureRateThreshold)
				.waitDurationInOpenState(waitDuration)
				.permittedNumberOfCallsInHalfOpenState(permittedCallsInHalfOpenState)
				.automaticTransitionFromOpenToHalfOpenEnabled(true)
				.recordExceptions(ResourceAccessException.class)
				.build();

		CircuitBreakerRegistry registry = CircuitBreakerRegistry.of(config);
		TaggedCircuitBreakerMetrics.ofCircuitBreakerRegistry(registry).bindTo(meterRegistry);
		return registry;
	}

	@Bean
	CircuitBreaker externalApiCircuitBreaker(CircuitBreakerRegistry registry) {
		CircuitBreaker circuitBreaker = registry.circuitBreaker("externalApi");
		circuitBreaker.getEventPublisher().onStateTransition(event ->
				log.info("external-api circuit-breaker transition: {}", event.getStateTransition()));
		return circuitBreaker;
	}
}
