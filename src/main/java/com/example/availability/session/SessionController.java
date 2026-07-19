package com.example.availability.session;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@Slf4j
@RestController
@RequestMapping("/api/session")
public class SessionController {

	private static final String USERNAME_ATTRIBUTE = "username";

	private final String applicationVersion;
	private final String instanceId;
	private final String sessionMode;

	public SessionController(
			@Value("${app.version}") String applicationVersion,
			@Value("${app.instance-id}") String instanceId,
			@Value("${app.session-mode:disabled}") String sessionMode
	) {
		this.applicationVersion = applicationVersion;
		this.instanceId = instanceId;
		this.sessionMode = sessionMode;
	}

	@PostMapping("/login")
	public SessionResult login(
			@RequestParam String username,
			HttpSession session
	) {
		if (username.isBlank()) {
			throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "username must not be blank");
		}

		session.setAttribute(USERNAME_ATTRIBUTE, username);
		log.info(
				"session login: sessionId={}, username={}, version={}, instance={}, mode={}",
				session.getId(),
				username,
				applicationVersion,
				instanceId,
				sessionMode
		);
		return result(session, username);
	}

	@GetMapping("/me")
	public SessionResult me(HttpServletRequest request) {
		HttpSession session = request.getSession(false);
		if (session == null || session.getAttribute(USERNAME_ATTRIBUTE) == null) {
			log.warn(
					"session missing: version={}, instance={}, mode={}",
					applicationVersion,
					instanceId,
					sessionMode
			);
			throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "session not found");
		}

		String username = session.getAttribute(USERNAME_ATTRIBUTE).toString();
		log.info(
				"session found: sessionId={}, username={}, version={}, instance={}, mode={}",
				session.getId(),
				username,
				applicationVersion,
				instanceId,
				sessionMode
		);
		return result(session, username);
	}

	@DeleteMapping
	public void logout(HttpServletRequest request) {
		HttpSession session = request.getSession(false);
		if (session != null) {
			log.info("session logout: sessionId={}", session.getId());
			session.invalidate();
		}
	}

	private SessionResult result(HttpSession session, String username) {
		return new SessionResult(
				session.getId(),
				username,
				applicationVersion,
				instanceId,
				sessionMode
		);
	}

	public record SessionResult(
			String sessionId,
			String username,
			String version,
			String instanceId,
			String sessionMode
	) {
	}
}
