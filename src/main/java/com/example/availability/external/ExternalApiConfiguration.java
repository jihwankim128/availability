package com.example.availability.external;

import io.micrometer.observation.ObservationRegistry;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestClient;

@Configuration(proxyBeanMethods = false)
public class ExternalApiConfiguration {

	@Bean
	RestClient externalApiRestClient(
			ObservationRegistry observationRegistry,
			@Value("${external-api.base-url}") String baseUrl
	) {
		return RestClient.builder()
				.baseUrl(baseUrl)
				.observationRegistry(observationRegistry)
				.build();
	}
}
