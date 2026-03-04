package com.example.commerce.repository;


import org.springframework.data.jpa.repository.JpaRepository;

import com.example.commerce.entity.Product;

public interface ProductRepository extends JpaRepository<Product, Long> {
    
}
