package com.example.commerce.controller;


import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import com.example.commerce.service.DbCheckService;

@RestController
public class HealthController {

    private final DbCheckService dbCheckService;

    public HealthController(DbCheckService dbCheckService) {
        this.dbCheckService = dbCheckService;
    }
    
        

    @GetMapping("/healthz")
    public String healthCheck() {
        return "200 OK";
    }
    @GetMapping("/dbz")
    public String dbCheck() {
        return "DB OK, product count: " + dbCheckService.productCount();
    }
}
