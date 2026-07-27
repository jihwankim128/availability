package com.example.availability.external;

import java.time.Instant;

import com.example.availability.external.ExternalApiClient.FeaturedProduct;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/external")
public class ExternalApiController {

	private final ExternalApiClient externalApiClient;

	public ExternalApiController(ExternalApiClient externalApiClient) {
		this.externalApiClient = externalApiClient;
	}

	@GetMapping("/featured-product")
	public ExternalApiResult featuredProduct() {
		Instant startedAt = Instant.now();
		FeaturedProduct product = externalApiClient.getFeaturedProduct();
		return result(product, startedAt);
	}

	@GetMapping("/unreachable-product")
	public ExternalApiResult unreachableProduct() {
		Instant startedAt = Instant.now();
		FeaturedProduct product = externalApiClient.getFeaturedProductFromUnreachableHost();
		return result(product, startedAt);
	}

	private ExternalApiResult result(FeaturedProduct product, Instant startedAt) {
		return new ExternalApiResult(product.id(), product.name(), startedAt, Instant.now());
	}

	public record ExternalApiResult(
			String id,
			String name,
			Instant startedAt,
			Instant completedAt
	) {
	}
}
