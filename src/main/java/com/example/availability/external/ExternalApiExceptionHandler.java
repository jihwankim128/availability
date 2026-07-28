package com.example.availability.external;

import io.github.resilience4j.circuitbreaker.CallNotPermittedException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.ResourceAccessException;

@RestControllerAdvice(assignableTypes = ExternalApiController.class)
public class ExternalApiExceptionHandler {

	@ExceptionHandler(CallNotPermittedException.class)
	ProblemDetail handleOpenCircuit(CallNotPermittedException exception) {
		ProblemDetail problem = ProblemDetail.forStatus(HttpStatus.SERVICE_UNAVAILABLE);
		problem.setTitle("External API circuit is open");
		problem.setDetail("The external API call was rejected immediately to protect this service.");
		return problem;
	}

	@ExceptionHandler(ResourceAccessException.class)
	ProblemDetail handleUnavailableExternalApi(ResourceAccessException exception) {
		ProblemDetail problem = ProblemDetail.forStatus(HttpStatus.GATEWAY_TIMEOUT);
		problem.setTitle("External API timeout");
		problem.setDetail("The external API did not respond within the configured network timeout.");
		return problem;
	}
}
