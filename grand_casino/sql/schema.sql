-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/sql/schema.sql
--  Casino database schema - additive tables only
-- ─────────────────────────────────────────────────────────────

-- Rounds table for provably fair gaming
CREATE TABLE IF NOT EXISTS `grand_casino_rounds` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `round_id` VARCHAR(64) NOT NULL UNIQUE,
    `game_type` VARCHAR(32) NOT NULL,
    `player_citizenid` VARCHAR(50) NOT NULL,
    `bet_amount` INT NOT NULL,
    `currency_type` VARCHAR(16) DEFAULT 'coins',
    `seed` VARCHAR(128) NOT NULL,
    `result` JSON NOT NULL,
    `payout` INT DEFAULT 0,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_player` (`player_citizenid`),
    KEY `idx_round` (`round_id`),
    KEY `idx_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Individual bets within rounds
CREATE TABLE IF NOT EXISTS `grand_casino_bets` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `round_id` VARCHAR(64) NOT NULL,
    `player_citizenid` VARCHAR(50) NOT NULL,
    `bet_type` VARCHAR(32) NOT NULL,
    `bet_amount` INT NOT NULL,
    `bet_details` JSON NOT NULL,
    `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_round` (`round_id`),
    KEY `idx_player` (`player_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Player sessions for responsible gambling tracking
CREATE TABLE IF NOT EXISTS `grand_casino_sessions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `player_citizenid` VARCHAR(50) NOT NULL,
    `session_start` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `session_end` TIMESTAMP NULL DEFAULT NULL,
    `total_bet` INT DEFAULT 0,
    `total_won` INT DEFAULT 0,
    `net_result` INT DEFAULT 0,
    KEY `idx_player` (`player_citizenid`),
    KEY `idx_session` (`session_start`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Player exclusions (self-exclusion or admin-enforced)
CREATE TABLE IF NOT EXISTS `grand_casino_exclusions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `player_citizenid` VARCHAR(50) NOT NULL UNIQUE,
    `exclusion_type` VARCHAR(32) DEFAULT 'self',
    `exclusion_start` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    `exclusion_end` TIMESTAMP NULL DEFAULT NULL,
    `reason` TEXT,
    `enforced_by` VARCHAR(50) DEFAULT NULL,
    KEY `idx_player` (`player_citizenid`),
    KEY `idx_end` (`exclusion_end`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Progressive jackpots
CREATE TABLE IF NOT EXISTS `grand_casino_jackpot` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `jackpot_type` VARCHAR(32) DEFAULT 'wheel',
    `current_amount` INT DEFAULT 0,
    `seed_amount` INT DEFAULT 0,
    `last_winner` VARCHAR(50) DEFAULT NULL,
    `last_win_amount` INT DEFAULT 0,
    `last_win_time` TIMESTAMP NULL DEFAULT NULL,
    `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `idx_type` (`jackpot_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;