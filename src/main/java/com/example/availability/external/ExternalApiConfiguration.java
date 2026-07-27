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
			@Value("${external-api.connect-timeout:0}") Duration connectTimeout,
			@Value("${external-api.read-timeout:0}") Duration readTimeout
	) {
		return createRestClient(observationRegistry, baseUrl, connectTimeout, readTimeout);
	}

	@Bean
	RestClient unreachableExternalApiRestClient(
			ObservationRegistry observationRegistry,
			@Value("${external-api.unreachable-base-url:${external-api.base-url}}") String baseUrl,
			@Value("${external-api.connect-timeout:0}") Duration connectTimeout,
			@Value("${external-api.read-timeout:0}") Duration readTimeout
	) {
		return createRestClient(observationRegistry, baseUrl, connectTimeout, readTimeout);
	}

	private RestClient createRestClient(
			ObservationRegistry observationRegistry,
			String baseUrl,
			Duration connectTimeout,
			Duration readTimeout
	) {
		RestClient.Builder builder = RestClient.builder()
				.baseUrl(baseUrl)
				.observationRegistry(observationRegistry);

		if (!connectTimeout.isZero() || !readTimeout.isZero()) {
			SimpleClientHttpRequestFactory requestFactory = new SimpleClientHttpRequestFactory();
			if (!connectTimeout.isZero()) {
				requestFactory.setConnectTimeout(connectTimeout);
			}
			if (!readTimeout.isZero()) {
				requestFactory.setReadTimeout(readTimeout);
			}
			builder.requestFactory(requestFactory);
		}

		return builder.build();
	}
}
