-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/sql/schema.sql
--  Additive tables only, no foreign keys. MariaDB 10.2+ safe.
--
--  The resource also runs these CREATE TABLE IF NOT EXISTS
--  statements at boot via server/database.lua when
--  Config.Persistence.autoCreateSchema is enabled, so importing
--  this file is optional but recommended for a clean install.
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `grand_mechanic_jobs` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `job_ref`       VARCHAR(40)  NOT NULL UNIQUE,
    `kind`          VARCHAR(16)  NOT NULL,
    `status`        VARCHAR(16)  NOT NULL DEFAULT 'open',
    `vehicle`       VARCHAR(60)  NOT NULL,
    `plate`         VARCHAR(12)  DEFAULT NULL,
    `model`         VARCHAR(60)  DEFAULT NULL,
    `coords`        VARCHAR(64)  DEFAULT NULL,
    `site`          VARCHAR(40)  DEFAULT NULL,
    `worker`        VARCHAR(50)  DEFAULT NULL,
    `customer`      VARCHAR(50)  DEFAULT NULL,
    `faults`        LONGTEXT     DEFAULT NULL,
    `estimate`      INT          DEFAULT 0,
    `payout`        INT          DEFAULT 0,
    `created_at`    INT          DEFAULT 0,
    `claimed_at`    INT          DEFAULT 0,
    `finished_at`   INT          DEFAULT 0,
    KEY `idx_status` (`status`),
    KEY `idx_worker` (`worker`),
    KEY `idx_kind`   (`kind`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `grand_mechanic_invoices` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `invoice_ref`   VARCHAR(40)  NOT NULL UNIQUE,
    `job_ref`       VARCHAR(40)  DEFAULT NULL,
    `customer_cid`  VARCHAR(50)  DEFAULT NULL,
    `worker_cid`    VARCHAR(50)  DEFAULT NULL,
    `kind`          VARCHAR(16)  NOT NULL,
    `plate`         VARCHAR(12)  DEFAULT NULL,
    `lines`         LONGTEXT     DEFAULT NULL,
    `labour`        INT          DEFAULT 0,
    `parts`         INT          DEFAULT 0,
    `tax`           INT          DEFAULT 0,
    `total`         INT          NOT NULL DEFAULT 0,
    `paid`          TINYINT(1)   NOT NULL DEFAULT 0,
    `paid_by`       VARCHAR(16)  DEFAULT NULL,
    `created_at`    INT          DEFAULT 0,
    `settled_at`    INT          DEFAULT 0,
    `expires`       INT          DEFAULT 0,
    KEY `idx_customer` (`customer_cid`, `paid`),
    KEY `idx_expiry`   (`expires`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `grand_hoardings` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `hoard_ref`     VARCHAR(40)  NOT NULL UNIQUE,
    `job_ref`       VARCHAR(40)  DEFAULT NULL,
    `site`          VARCHAR(40)  NOT NULL,
    `plate`         VARCHAR(12)  NOT NULL,
    `model`         VARCHAR(60)  NOT NULL,
    `stored_by`     VARCHAR(50)  DEFAULT NULL,
    `owner_cid`     VARCHAR(50)  DEFAULT NULL,
    `fees`          INT          DEFAULT 0,
    `hourly_fee`    INT          DEFAULT 0,
    `state`         VARCHAR(16)  NOT NULL DEFAULT 'impounded',
    `stolen`        TINYINT(1)   NOT NULL DEFAULT 0,
    `resprayed`     TINYINT(1)   NOT NULL DEFAULT 0,
    `new_plate`     VARCHAR(12)  DEFAULT NULL,
    `hours`         INT          DEFAULT 0,
    `created_at`    INT          DEFAULT 0,
    `released_at`   INT          DEFAULT 0,
    KEY `idx_plate` (`plate`),
    KEY `idx_state` (`state`),
    KEY `idx_site`  (`site`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `grand_mechanic_stats` (
    `citizenid`     VARCHAR(50)  NOT NULL PRIMARY KEY,
    `xp`            INT          DEFAULT 0,
    `level`         INT          DEFAULT 0,
    `repairs`       INT          DEFAULT 0,
    `tows`          INT          DEFAULT 0,
    `jacks`         INT          DEFAULT 0,
    `fares`         INT          DEFAULT 0,
    `earned`        BIGINT       DEFAULT 0,
    `busted`        INT          DEFAULT 0,
    `perfect`       INT          DEFAULT 0,
    `updated_at`    INT          DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `grand_vehicle_tampering` (
    `id`            INT AUTO_INCREMENT PRIMARY KEY,
    `citizenid`     VARCHAR(50)  NOT NULL,
    `plate`         VARCHAR(12)  NOT NULL,
    `action`        VARCHAR(24)  NOT NULL,
    `site`          VARCHAR(40)  DEFAULT NULL,
    `wanted`        TINYINT(1)   DEFAULT 0,
    `created_at`    INT          DEFAULT 0,
    KEY `idx_cid` (`citizenid`),
    KEY `idx_plate` (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
