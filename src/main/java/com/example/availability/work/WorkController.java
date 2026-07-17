package com.example.availability.work;

import java.time.Instant;
import java.util.UUID;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@Slf4j
@RestController
@RequestMapping("/api")
public class WorkController {

	private static final long MAX_WORK_SECONDS = 60;

	private final String applicationVersion;
	private final String instanceId;

	public WorkController(
			@Value("${app.version}") String applicationVersion,
			@Value("${app.instance-id}") String instanceId
	) {
		this.applicationVersion = applicationVersion;
		this.instanceId = instanceId;
	}

	@GetMapping("/info")
	public InstanceInfo info() {
		return new InstanceInfo(applicationVersion, instanceId);
	}

	@GetMapping("/work")
	public WorkResult work(
			@RequestParam(defaultValue = "10") long seconds,
			@RequestHeader(name = "X-Request-Id", required = false) String requestedId
	) throws InterruptedException {
		validateSeconds(seconds);

		String requestId = resolveRequestId(requestedId);
		Instant startedAt = Instant.now();
		log.info(
				"work started: requestId={}, version={}, instance={}, seconds={}",
				requestId,
				applicationVersion,
				instanceId,
				seconds
		);

		try {
			Thread.sleep(seconds * 1_000);
		} catch (InterruptedException exception) {
			log.warn(
					"work interrupted: requestId={}, version={}, instance={}",
					requestId,
					applicationVersion,
					instanceId
			);
			Thread.currentThread().interrupt();
			throw exception;
		}

		Instant completedAt = Instant.now();
		log.info(
				"work completed: requestId={}, version={}, instance={}",
				requestId,
				applicationVersion,
				instanceId
		);

		return new WorkResult(
				requestId,
				applicationVersion,
				instanceId,
				startedAt,
				completedAt
		);
	}

	private String resolveRequestId(String requestedId) {
		if (requestedId == null || requestedId.isBlank()) {
			return UUID.randomUUID().toString();
		}
		return requestedId;
	}

	private void validateSeconds(long seconds) {
		if (seconds < 1 || seconds > MAX_WORK_SECONDS) {
			throw new ResponseStatusException(
					HttpStatus.BAD_REQUEST,
					"seconds must be between 1 and " + MAX_WORK_SECONDS
			);
		}
	}

	public record InstanceInfo(String version, String instanceId) {
	}

	public record WorkResult(
			String requestId,
			String version,
			String instanceId,
			Instant startedAt,
			Instant completedAt
	) {
	}
}
