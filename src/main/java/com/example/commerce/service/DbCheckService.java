package com.example.commerce.service;

import org.springframework.stereotype.Service;

import com.example.commerce.repository.ProductRepository;

@Service
public class DbCheckService {

    private final ProductRepository productRepository;

    public DbCheckService(ProductRepository productRepository) {
        this.productRepository = productRepository;
    }

    public long productCount() {
        return productRepository.count();
    }
}
