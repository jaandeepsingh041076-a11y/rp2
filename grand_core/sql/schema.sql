-- resources/[grand_systems]/grand_core/sql/schema.sql
-- Grand RP Core: player progression, payouts and persistence

-- Player progression / stats table (level + exp + playtime tracking)
CREATE TABLE IF NOT EXISTS `grand_player_stats` (
  `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
  `level` INT NOT NULL DEFAULT 1,
  `exp` INT NOT NULL DEFAULT 0,
  `active_seconds` BIGINT NOT NULL DEFAULT 0,
  `total_seconds` BIGINT NOT NULL DEFAULT 0,
  `exp_accumulator` INT NOT NULL DEFAULT 0,
  `last_payday` TIMESTAMP NULL DEFAULT NULL,
  `last_saved` TIMESTAMP NULL DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT `chk_grand_level` CHECK (`level` >= 1),
  CONSTRAINT `chk_grand_exp` CHECK (`exp` >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Payout ledger so every salary / interest credit is auditable and idempotent
CREATE TABLE IF NOT EXISTS `grand_payday_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL,
  `payout_type` ENUM('salary', 'interest', 'exp') NOT NULL,
  `amount` INT NOT NULL DEFAULT 0,
  `level_at_payout` INT NOT NULL DEFAULT 1,
  `job` VARCHAR(50) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_grand_payday_citizen` (`citizenid`, `created_at`),
  INDEX `idx_grand_payday_type` (`payout_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Snapshot of character money / job written by this resource
CREATE TABLE IF NOT EXISTS `grand_character_snapshots` (
  `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
  `firstname` VARCHAR(50) NOT NULL DEFAULT '',
  `lastname` VARCHAR(50) NOT NULL DEFAULT '',
  `cash` INT NOT NULL DEFAULT 0,
  `bank` INT NOT NULL DEFAULT 0,
  `job` VARCHAR(50) NOT NULL DEFAULT 'unemployed',
  `job_grade` INT NOT NULL DEFAULT 0,
  `level` INT NOT NULL DEFAULT 1,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Inventory item persistence (mirrors ox_inventory's `inventory` table).
-- If ox_inventory is installed, its own table is used; this one is the fallback store.
CREATE TABLE IF NOT EXISTS `grand_inventory_items` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL,
  `slot` INT NOT NULL,
  `item_name` VARCHAR(64) NOT NULL,
  `count` INT NOT NULL DEFAULT 0,
  `metadata` TEXT,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_grand_inv_slot` (`citizenid`, `slot`),
  INDEX `idx_grand_inv_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- Saved outfits (clothing / components) per citizen
CREATE TABLE IF NOT EXISTS grand_outfits (
  id INT AUTO_INCREMENT PRIMARY KEY,
  citizenid VARCHAR(50) NOT NULL,
  slug VARCHAR(64) NOT NULL,
  display VARCHAR(96) NOT NULL DEFAULT '',
  components LONGTEXT,
  props LONGTEXT,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_grand_outfit (citizenid, slug),
  INDEX idx_grand_outfit_citizen (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;