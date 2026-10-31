-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_coin/sql/schema.sql
--  Additive tables only. `users.grand_coins` belongs to the root
--  database.sql; database.lua adds it defensively at boot.
--  MariaDB 10.2+: no CHECK constraints, no JSON defaults.
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `grand_coin_ledger` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `transaction_id` VARCHAR(64) NOT NULL,
    `player_citizenid` VARCHAR(50) NOT NULL,
    `change_amount` INT NOT NULL,
    `transaction_type` VARCHAR(32) NOT NULL,
    `reason` VARCHAR(190) DEFAULT NULL,
    `balance_before` INT NOT NULL DEFAULT 0,
    `balance_after` INT NOT NULL DEFAULT 0,
    `source_player` VARCHAR(50) DEFAULT NULL,
    `target_player` VARCHAR(50) DEFAULT NULL,
    `metadata` LONGTEXT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_coin_txn` (`transaction_id`),
    KEY `idx_coin_player` (`player_citizenid`, `id`),
    KEY `idx_coin_type` (`transaction_type`, `created_at`),
    KEY `idx_coin_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_coin_purchases` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `transaction_id` VARCHAR(64) NOT NULL,
    `player_citizenid` VARCHAR(50) NOT NULL,
    `item_slug` VARCHAR(64) NOT NULL,
    `item_name` VARCHAR(128) NOT NULL,
    `item_type` VARCHAR(32) NOT NULL,
    `quantity` INT NOT NULL DEFAULT 1,
    `total_cost` INT NOT NULL DEFAULT 0,
    `delivery_status` VARCHAR(24) NOT NULL DEFAULT 'pending',
    `delivery_data` LONGTEXT DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_coin_buy_player` (`player_citizenid`, `id`),
    KEY `idx_coin_buy_txn` (`transaction_id`),
    KEY `idx_coin_buy_item` (`item_slug`),
    KEY `idx_coin_buy_status` (`delivery_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_coin_exchange` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `player_citizenid` VARCHAR(50) NOT NULL,
    `exchange_type` VARCHAR(24) NOT NULL,
    `coin_amount` INT NOT NULL DEFAULT 0,
    `cash_amount` INT NOT NULL DEFAULT 0,
    `fee_amount` INT NOT NULL DEFAULT 0,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_coin_ex_player` (`player_citizenid`, `created_at`),
    KEY `idx_coin_ex_type` (`exchange_type`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_coin_liquidity` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `pool_date` DATE NOT NULL,
    `total_pool` BIGINT NOT NULL DEFAULT 0,
    `remaining_pool` BIGINT NOT NULL DEFAULT 0,
    `cash_outs` BIGINT NOT NULL DEFAULT 0,
    `cash_ins` BIGINT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_coin_pool_date` (`pool_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
