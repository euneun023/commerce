package com.example.commerce.service;

import com.example.commerce.global.CustomMetrics;
import org.springframework.stereotype.Service;

import com.example.commerce.repository.ProductRepository;

@Service
public class DbCheckService {

    private final ProductRepository productRepository;
    private final CustomMetrics customMetrics;

    public DbCheckService(ProductRepository productRepository, CustomMetrics customMetrics) {
        this.productRepository = productRepository;
        this.customMetrics = customMetrics;
    }

    public long productCount() {
        long start = System.currentTimeMillis();
        long count = productRepository.count();
        long elapsed = System.currentTimeMillis() - start;

        customMetrics.recordDbQuery(elapsed);
        return count;
    }
}
