package com.example.availability.external;

import java.net.ConnectException;
import java.net.SocketTimeoutException;
import java.util.concurrent.atomic.AtomicInteger;

import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

@Component
public class ExternalApiClient {

	private final RestClient restClient;
	private final RestClient unreachableRestClient;
	private final MeterRegistry meterRegistry;
	private final AtomicInteger inFlight = new AtomicInteger();

	public ExternalApiClient(
			@Qualifier("externalApiRestClient") RestClient externalApiRestClient,
			@Qualifier("unreachableExternalApiRestClient") RestClient unreachableExternalApiRestClient,
			MeterRegistry meterRegistry
	) {
		this.restClient = externalApiRestClient;
		this.unreachableRestClient = unreachableExternalApiRestClient;
		this.meterRegistry = meterRegistry;
		Gauge.builder("external.api.in.flight", inFlight, AtomicInteger::get)
				.description("Number of requests currently waiting for the external API")
				.register(meterRegistry);
	}

	public FeaturedProduct getFeaturedProduct() {
		return getFeaturedProduct(restClient, "normal");
	}

	public FeaturedProduct getFeaturedProductFromUnreachableHost() {
		return getFeaturedProduct(unreachableRestClient, "unreachable");
	}

	private FeaturedProduct getFeaturedProduct(RestClient client, String target) {
		Timer.Sample sample = Timer.start();
		inFlight.incrementAndGet();

		try {
			FeaturedProduct product = client.get()
					.uri("/external/products/featured")
					.retrieve()
					.body(FeaturedProduct.class);
			meterRegistry.counter("external.api.calls", "outcome", "success", "target", target).increment();
			return product;
		} catch (RuntimeException exception) {
			String reason = failureReason(exception);
			meterRegistry.counter("external.api.calls", "outcome", "failure", "target", target).increment();
			meterRegistry.counter("external.api.failures", "reason", reason, "target", target).increment();
			throw exception;
		} finally {
			inFlight.decrementAndGet();
			sample.stop(meterRegistry.timer("external.api.duration", "target", target));
		}
	}

	private String failureReason(Throwable throwable) {
		Throwable current = throwable;
		while (current != null) {
			if (current instanceof SocketTimeoutException) {
				String message = current.getMessage();
				return message != null && message.toLowerCase().contains("connect")
						? "connect_timeout"
						: "read_timeout";
			}
			if (current instanceof ConnectException) {
				return "connection_refused";
			}
			current = current.getCause();
		}
		return "other";
	}

	public record FeaturedProduct(String id, String name) {
	}
}
