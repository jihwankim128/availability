package com.example.availability.session;

import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.session.data.redis.config.annotation.web.http.EnableRedisHttpSession;

@Configuration(proxyBeanMethods = false)
@Profile("session-redis")
@EnableRedisHttpSession(
		maxInactiveIntervalInSeconds = 600,
		redisNamespace = "availability:session"
)
public class RedisSessionConfiguration {
}
