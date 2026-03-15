package com.example.commerce.global;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

@Component
public class HttpMetricsFilter extends OncePerRequestFilter {
    private final CustomMetrics customMetrics;

    public HttpMetricsFilter(CustomMetrics customMetrics){
        this.customMetrics = customMetrics;
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain
    ) throws ServletException, IOException {
        filterChain.doFilter(request, response);

        String path = request.getRequestURI();
        String status = String.valueOf(response.getStatus());

        customMetrics.incrementHttpRequest(path, status);
    }
}
