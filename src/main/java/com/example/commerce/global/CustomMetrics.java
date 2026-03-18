package com.example.commerce.global;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Component;

import java.util.concurrent.TimeUnit;

@Component
public class CustomMetrics {

    private final MeterRegistry registry;
    private final Counter cacheHitCounter;
    private final Counter cacheMissCounter;
    private final Timer dbQueryTimer;

    public CustomMetrics(MeterRegistry registry){
        this.registry = registry;
        this.cacheHitCounter = Counter.builder("cache_hit_total")
                .description("Total cache hits")
                .register(registry);

        this.cacheMissCounter = Counter.builder("cache_miss_total")
                .description("Total cache misses")
                .register(registry);

        this.dbQueryTimer = Timer.builder("db_query_latency_seconds")
                .description("DB query latency")
                .publishPercentileHistogram()
                .register(registry);
    }

    public void incrementHttpRequest(String path, String status){
        Counter.builder("http_request_total")
                .description("http_request_total")
                .tag("path", path)
                .tag("status", status)
                .register(registry)
                .increment();
    }

    public void cacheHit(){
        cacheHitCounter.increment();
    }
    public void cacheMiss(){
        cacheMissCounter.increment();
    }
    public void recordDbQuery(long millis){
        dbQueryTimer.record(millis, TimeUnit.MILLISECONDS);
    }

}
