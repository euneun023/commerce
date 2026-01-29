-- 데이터베이스 생성 (없을 경우)
CREATE DATABASE IF NOT EXISTS `commerce` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE `commerce`;

-- 테이블 구조 수정: id를 BIGINT, PRIMARY KEY, AUTO_INCREMENT로 설정
CREATE TABLE IF NOT EXISTS `products` (
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `product_name` VARCHAR(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- 초기 데이터 삽입
INSERT INTO `products` (`product_name`) VALUES 
    ('스마트폰'),
    ('노트북'),
    ('모니터'),
    ('TV'),
    ('키보드');