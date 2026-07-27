package com.example.availability.external;

import java.time.Duration;

import io.micrometer.observation.ObservationRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

@Configuration(proxyBeanMethods = false)
public class ExternalApiConfiguration {

	@Bean
	RestClient externalApiRestClient(
			ObservationRegistry observationRegistry,
			@Value("${external-api.base-url}") String baseUrl,
			@Value("${external-api.connect-timeout:0}") Duration connectTimeout
	) {
		return createRestClient(observationRegistry, baseUrl, connectTimeout);
	}

	@Bean
	RestClient unreachableExternalApiRestClient(
			ObservationRegistry observationRegistry,
			@Value("${external-api.unreachable-base-url:${external-api.base-url}}") String baseUrl,
			@Value("${external-api.connect-timeout:0}") Duration connectTimeout
	) {
		return createRestClient(observationRegistry, baseUrl, connectTimeout);
	}

	private RestClient createRestClient(
			ObservationRegistry observationRegistry,
			String baseUrl,
			Duration connectTimeout
	) {
		RestClient.Builder builder = RestClient.builder()
				.baseUrl(baseUrl)
				.observationRegistry(observationRegistry);

		if (!connectTimeout.isZero()) {
			SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
			requestFactory.setConnectTimeout(connectTimeout);
			builder.requestFactory(requestFactory);
		}

		return builder.build();
	}
}
