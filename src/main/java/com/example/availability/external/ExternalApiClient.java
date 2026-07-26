package com.example.availability.external;

import java.util.concurrent.atomic.AtomicInteger;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class ExternalApiClient {

	private final RestClient restClient;
	private final AtomicInteger inFlight = new AtomicInteger();
	private final Counter successfulCalls;
	private final Counter failedCalls;
	private final Timer callDuration;

	public ExternalApiClient(RestClient externalApiRestClient, MeterRegistry meterRegistry) {
		this.restClient = externalApiRestClient;
		this.successfulCalls = meterRegistry.counter("external.api.calls", "outcome", "success");
		this.failedCalls = meterRegistry.counter("external.api.calls", "outcome", "failure");
		this.callDuration = meterRegistry.timer("external.api.duration");
		Gauge.builder("external.api.in.flight", inFlight, AtomicInteger::get)
				.description("Number of requests currently waiting for the external API")
				.register(meterRegistry);
	}

	public FeaturedProduct getFeaturedProduct() {
		Timer.Sample sample = Timer.start();
		inFlight.incrementAndGet();

		try {
			FeaturedProduct product = restClient.get()
					.uri("/external/products/featured")
					.retrieve()
					.body(FeaturedProduct.class);
			successfulCalls.increment();
			return product;
		} catch (RuntimeException exception) {
			failedCalls.increment();
			throw exception;
		} finally {
			inFlight.decrementAndGet();
			sample.stop(callDuration);
		}
	}

	public record FeaturedProduct(String id, String name) {
	}
}
