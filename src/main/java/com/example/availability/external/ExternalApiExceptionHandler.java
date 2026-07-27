package com.example.availability.external;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.client.ResourceAccessException;

@RestControllerAdvice(assignableTypes = ExternalApiController.class)
public class ExternalApiExceptionHandler {

	@ExceptionHandler(ResourceAccessException.class)
	ProblemDetail handleUnavailableExternalApi(ResourceAccessException exception) {
		ProblemDetail problem = ProblemDetail.forStatus(HttpStatus.GATEWAY_TIMEOUT);
		problem.setTitle("External API timeout");
		problem.setDetail("The external API did not respond within the configured network timeout.");
		return problem;
	}
}
