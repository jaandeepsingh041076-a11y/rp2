-- resources/[grand_systems]/grand_admin/sql/schema.sql
CREATE TABLE IF NOT EXISTS `grand_admin_bans` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `license` VARCHAR(128) NOT NULL DEFAULT '',
  `discord` VARCHAR(128) NOT NULL DEFAULT '',
  `ip` VARCHAR(64) NOT NULL DEFAULT '',
  `name` VARCHAR(128) NOT NULL DEFAULT '',
  `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
  `reason` TEXT,
  `banned_by` VARCHAR(128) NOT NULL DEFAULT '',
  `expires` BIGINT NOT NULL DEFAULT 0,
  `timestamp` BIGINT NOT NULL DEFAULT 0,
  `unbanned` TINYINT(1) DEFAULT 0,
  `unbanned_at` BIGINT DEFAULT 0,
  `unbanned_by` VARCHAR(128) DEFAULT '',
  KEY `idx_license` (`license`),
  KEY `idx_citizenid` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_admin_logs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `admin` VARCHAR(128) NOT NULL DEFAULT '',
  `admin_citizenid` VARCHAR(64) NOT NULL DEFAULT '',
  `action` VARCHAR(64) NOT NULL DEFAULT '',
  `target` VARCHAR(32) DEFAULT '',
  `details` TEXT,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
