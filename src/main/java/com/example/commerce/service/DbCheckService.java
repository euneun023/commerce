package com.example.commerce.service;

import com.example.commerce.global.CustomMetrics;
import lombok.extern.slf4j.Slf4j;
import org.springframework.cache.annotation.Cacheable;
import org.springframework.stereotype.Service;

import com.example.commerce.repository.ProductRepository;

@Slf4j
@Service
public class DbCheckService {

    private final ProductRepository productRepository;
    private final CustomMetrics customMetrics;

    public DbCheckService(ProductRepository productRepository, CustomMetrics customMetrics) {
        this.productRepository = productRepository;
        this.customMetrics = customMetrics;
    }

    @Cacheable(value = "productCount")
    public long productCount() {
        long start = System.currentTimeMillis();

        log.info("[redis - cache test] DB 조회 실행 - product count");

        long count = productRepository.count();
        long elapsed = System.currentTimeMillis() - start;

        customMetrics.recordDbQuery(elapsed);
        return count;
    }
}
