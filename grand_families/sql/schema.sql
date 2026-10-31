-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/sql/schema.sql
--  Additive schema. `grand_families` is declared in the root
--  database.sql with (name, leader_citizenid, balance, points,
--  rating, level, solar_panels, oil_wells, mansion_coords,
--  created_at). This file re-declares it as a full union so a
--  fresh install works, and server/database.lua reconciles any
--  missing additive column at boot.
--
--  `balance` is the vault. `vault_balance` is a legacy alias kept
--  only in old exports - never read it here.
--  MariaDB 10.2+: no CHECK constraints, no JSON defaults, no FKs
--  to `characters` (it may not exist at import time).
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `grand_families` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `name` VARCHAR(50) NOT NULL,
    `tag` VARCHAR(5) DEFAULT NULL,
    `leader_citizenid` VARCHAR(50) NOT NULL,
    `balance` BIGINT NOT NULL DEFAULT 0,
    `points` INT NOT NULL DEFAULT 0,
    `rating` INT NOT NULL DEFAULT 0,
    `level` INT NOT NULL DEFAULT 1,
    `solar_panels` INT NOT NULL DEFAULT 0,
    `oil_wells` INT NOT NULL DEFAULT 0,
    `mansion_coords` TEXT DEFAULT NULL,
    `color` VARCHAR(7) NOT NULL DEFAULT '#FFFFFF',
    `tax_rate` DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    `active_members` INT NOT NULL DEFAULT 1,
    `total_properties` INT NOT NULL DEFAULT 0,
    `total_turfs` INT NOT NULL DEFAULT 0,
    `description` TEXT DEFAULT NULL,
    `deleted` TINYINT(1) NOT NULL DEFAULT 0,
    `vault_cap` BIGINT NOT NULL DEFAULT 0,
    `last_income_at` TIMESTAMP NULL DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_family_name` (`name`),
    UNIQUE KEY `uk_family_tag` (`tag`),
    KEY `idx_family_leader` (`leader_citizenid`),
    KEY `idx_family_deleted` (`deleted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_family_members` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `family_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `rank` INT NOT NULL DEFAULT 1,
    `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    `total_deposits` BIGINT NOT NULL DEFAULT 0,
    `total_withdrawals` BIGINT NOT NULL DEFAULT 0,
    `kills_in_turf` INT NOT NULL DEFAULT 0,
    `captures_assisted` INT NOT NULL DEFAULT 0,
    UNIQUE KEY `uk_member_family_cid` (`family_id`, `citizenid`),
    KEY `idx_member_cid` (`citizenid`),
    KEY `idx_member_active` (`active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_family_properties` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `family_id` INT NOT NULL,
    `property_type` VARCHAR(24) NOT NULL,
    `location_name` VARCHAR(64) DEFAULT NULL,
    `coords_x` FLOAT NOT NULL DEFAULT 0.0,
    `coords_y` FLOAT NOT NULL DEFAULT 0.0,
    `coords_z` FLOAT NOT NULL DEFAULT 0.0,
    `purchase_price` INT NOT NULL DEFAULT 0,
    `last_payout` TIMESTAMP NULL DEFAULT NULL,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    KEY `idx_prop_family` (`family_id`, `active`),
    KEY `idx_prop_type` (`property_type`),
    KEY `idx_prop_payout` (`last_payout`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_family_turfs` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `family_id` INT NOT NULL,
    `turf_name` VARCHAR(40) NOT NULL,
    `coords_x` FLOAT NOT NULL DEFAULT 0.0,
    `coords_y` FLOAT NOT NULL DEFAULT 0.0,
    `coords_z` FLOAT NOT NULL DEFAULT 0.0,
    `radius` FLOAT NOT NULL DEFAULT 150.0,
    `tier` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `captured_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_bonus_payout` TIMESTAMP NULL DEFAULT NULL,
    `active` TINYINT(1) NOT NULL DEFAULT 1,
    UNIQUE KEY `uk_turf_name` (`turf_name`),
    KEY `idx_turf_family` (`family_id`, `active`),
    KEY `idx_turf_payout` (`last_bonus_payout`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_turf_wars` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `turf_name` VARCHAR(40) NOT NULL,
    `attacking_family_id` INT NOT NULL,
    `defending_family_id` INT DEFAULT NULL,
    `attacking_members` TEXT DEFAULT NULL,
    `progress_percent` INT NOT NULL DEFAULT 0,
    `holding_since` BIGINT NOT NULL DEFAULT 0,
    `start_time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `ended_at` TIMESTAMP NULL DEFAULT NULL,
    `completed` TINYINT(1) NOT NULL DEFAULT 0,
    `outcome` VARCHAR(24) DEFAULT NULL,
    `winner_family_id` INT DEFAULT NULL,
    KEY `idx_war_turf` (`turf_name`, `completed`),
    KEY `idx_war_attacker` (`attacking_family_id`, `completed`),
    KEY `idx_war_defender` (`defending_family_id`, `completed`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_family_vault_logs` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `family_id` INT NOT NULL,
    `citizenid` VARCHAR(50) DEFAULT NULL,
    `transaction_type` VARCHAR(24) NOT NULL,
    `amount` BIGINT NOT NULL DEFAULT 0,
    `balance_before` BIGINT NOT NULL DEFAULT 0,
    `balance_after` BIGINT NOT NULL DEFAULT 0,
    `description` VARCHAR(190) DEFAULT NULL,
    `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_vault_family` (`family_id`, `id`),
    KEY `idx_vault_type` (`transaction_type`),
    KEY `idx_vault_time` (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_family_logs` (
    `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
    `family_id` INT NOT NULL,
    `citizenid` VARCHAR(50) DEFAULT NULL,
    `action_type` VARCHAR(24) NOT NULL,
    `details` VARCHAR(190) DEFAULT NULL,
    `timestamp` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_log_family` (`family_id`, `id`),
    KEY `idx_log_action` (`action_type`),
    KEY `idx_log_time` (`timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_family_invites` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `family_id` INT NOT NULL,
    `citizenid` VARCHAR(50) NOT NULL,
    `inviter` VARCHAR(64) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_invite_cid` (`citizenid`),
    KEY `idx_invite_family` (`family_id`),
    KEY `idx_invite_time` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
