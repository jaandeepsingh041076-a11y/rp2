-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/sql/schema.sql
--  Additive tables only. `grand_turfs` belongs to the root
--  database.sql and is never created here - gangs reads and
--  updates it through DB.SyncRootTurf.
--  MariaDB 10.2+: no CHECK constraints, no JSON defaults.
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `grand_gang_zones` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `zone_id` VARCHAR(32) NOT NULL,
    `name` VARCHAR(64) NOT NULL,
    `tier` TINYINT UNSIGNED NOT NULL DEFAULT 1,
    `ghetto` TINYINT(1) NOT NULL DEFAULT 0,
    `owner_family_id` INT DEFAULT NULL,
    `owner_gang` VARCHAR(32) DEFAULT NULL,
    `tag` VARCHAR(16) DEFAULT NULL,
    `radius` FLOAT NOT NULL DEFAULT 120.0,
    `pos_x` FLOAT NOT NULL DEFAULT 0.0,
    `pos_y` FLOAT NOT NULL DEFAULT 0.0,
    `pos_z` FLOAT NOT NULL DEFAULT 0.0,
    `hourly_reward` INT NOT NULL DEFAULT 10000,
    `last_payout` TIMESTAMP NULL DEFAULT NULL,
    `captured_total` INT NOT NULL DEFAULT 0,
    `defended_total` INT NOT NULL DEFAULT 0,
    `hot_score` INT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_gang_zone_id` (`zone_id`),
    KEY `idx_gang_zone_owner` (`owner_family_id`),
    KEY `idx_gang_zone_payout` (`last_payout`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_gang_wars` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `zone_id` VARCHAR(32) NOT NULL,
    `attacker_family` INT NOT NULL,
    `attacker_gang` VARCHAR(32) DEFAULT NULL,
    `defender_family` INT DEFAULT NULL,
    `defender_gang` VARCHAR(32) DEFAULT NULL,
    `progress` INT NOT NULL DEFAULT 0,
    `required` INT NOT NULL DEFAULT 30,
    `attacker_count` INT NOT NULL DEFAULT 0,
    `defender_count` INT NOT NULL DEFAULT 0,
    `status` VARCHAR(16) NOT NULL DEFAULT 'live',
    `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `last_tick` TIMESTAMP NULL DEFAULT NULL,
    `ends_at` TIMESTAMP NULL DEFAULT NULL,
    `winner_family` INT DEFAULT NULL,
    `reason` VARCHAR(64) DEFAULT NULL,
    UNIQUE KEY `uk_gang_war_zone` (`zone_id`, `status`),
    KEY `idx_gang_war_status` (`status`),
    KEY `idx_gang_war_attacker` (`attacker_family`, `status`),
    KEY `idx_gang_war_defender` (`defender_family`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_gang_members` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid` VARCHAR(20) NOT NULL,
    `family_id` INT DEFAULT NULL,
    `gang` VARCHAR(32) DEFAULT NULL,
    `rank` INT NOT NULL DEFAULT 0,
    `kills_in_turf` INT NOT NULL DEFAULT 0,
    `deaths_in_turf` INT NOT NULL DEFAULT 0,
    `assists_in_turf` INT NOT NULL DEFAULT 0,
    `wars_joined` INT NOT NULL DEFAULT 0,
    `wars_won` INT NOT NULL DEFAULT 0,
    `captures` INT NOT NULL DEFAULT 0,
    `bounty` INT NOT NULL DEFAULT 0,
    `friend_fires` INT NOT NULL DEFAULT 0,
    `tags_laid` INT NOT NULL DEFAULT 0,
    `last_seen` TIMESTAMP NULL DEFAULT NULL,
    `weapon_lock_until` TIMESTAMP NULL DEFAULT NULL,
    UNIQUE KEY `uk_gang_member_cid` (`citizenid`),
    KEY `idx_gang_member_family` (`family_id`),
    KEY `idx_gang_member_gang` (`gang`),
    KEY `idx_gang_member_bounty` (`bounty`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_turf_actions` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `zone_id` VARCHAR(32) NOT NULL,
    `action` VARCHAR(24) NOT NULL,
    `actor_citizenid` VARCHAR(20) DEFAULT NULL,
    `attacker_family` INT DEFAULT NULL,
    `defender_family` INT DEFAULT NULL,
    `amount` INT NOT NULL DEFAULT 0,
    `detail` VARCHAR(190) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_turf_action_zone` (`zone_id`, `created_at`),
    KEY `idx_turf_action_family` (`attacker_family`, `action`),
    KEY `idx_turf_action_time` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `grand_gang_stats` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `family_id` INT NOT NULL,
    `gang` VARCHAR(32) DEFAULT NULL,
    `turfs_held` INT NOT NULL DEFAULT 0,
    `hourly` INT NOT NULL DEFAULT 0,
    `wars_won` INT NOT NULL DEFAULT 0,
    `wars_lost` INT NOT NULL DEFAULT 0,
    `captures` INT NOT NULL DEFAULT 0,
    `defences` INT NOT NULL DEFAULT 0,
    `kills` INT NOT NULL DEFAULT 0,
    `income_paid` BIGINT NOT NULL DEFAULT 0,
    `notoriety` INT NOT NULL DEFAULT 0,
    `cooldown_until` TIMESTAMP NULL DEFAULT NULL,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY `uk_gang_stats_family` (`family_id`),
    KEY `idx_gang_stats_hourly` (`hourly`),
    KEY `idx_gang_stats_won` (`wars_won`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
