-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/server/database.lua
--  Database layer – all SQL queries live here
-- ─────────────────────────────────────────────────────────────

local Config = require 'config'
local Util = require 'shared.util'

local Database = {}

-- Initialize tables
function Database.Initialize()
    MySQL.query.await([[
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    MySQL.query.await([[
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
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])

    -- Initialize wheel jackpot
    MySQL.insert.await([[
        INSERT IGNORE INTO `grand_casino_jackpot` (jackpot_type, current_amount, seed_amount)
        VALUES ('wheel', ?, ?)
    ]], { Config.WheelOfFortune.jackpotSeed, Config.WheelOfFortune.jackpotSeed })

    print('[grand_casino] Database tables initialized')
end

-- Record a new round
function Database.RecordRound(roundId, gameType, playerCitizenId, betAmount, currencyType, seed, result, payout)
    return MySQL.insert.await([[
        INSERT INTO `grand_casino_rounds` 
        (round_id, game_type, player_citizenid, bet_amount, currency_type, seed, result, payout)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { roundId, gameType, playerCitizenId, betAmount, currencyType, seed, json.encode(result), payout })
end

-- Get round by ID
function Database.GetRound(roundId)
    return MySQL.single.await([[
        SELECT * FROM `grand_casino_rounds` WHERE round_id = ?
    ]], { roundId })
end

-- Record a bet
function Database.RecordBet(roundId, playerCitizenId, betType, betAmount, betDetails)
    return MySQL.insert.await([[
        INSERT INTO `grand_casino_bets` 
        (round_id, player_citizenid, bet_type, bet_amount, bet_details)
        VALUES (?, ?, ?, ?, ?)
    ]], { roundId, playerCitizenId, betType, betAmount, json.encode(betDetails) })
end

-- Start a new session
function Database.StartSession(playerCitizenId)
    return MySQL.insert.await([[
        INSERT INTO `grand_casino_sessions` (player_citizenid)
        VALUES (?)
    ]], { playerCitizenId })
end

-- End a session
function Database.EndSession(sessionId, totalBet, totalWon, netResult)
    return MySQL.update.await([[
        UPDATE `grand_casino_sessions` 
        SET session_end = CURRENT_TIMESTAMP, total_bet = ?, total_won = ?, net_result = ?
        WHERE id = ?
    ]], { totalBet, totalWon, netResult, sessionId })
end

-- Get active session for player
function Database.GetActiveSession(playerCitizenId)
    return MySQL.single.await([[
        SELECT * FROM `grand_casino_sessions` 
        WHERE player_citizenid = ? AND session_end IS NULL
        ORDER BY session_start DESC LIMIT 1
    ]], { playerCitizenId })
end

-- Check if player is excluded
function Database.IsPlayerExcluded(playerCitizenId)
    local result = MySQL.single.await([[
        SELECT * FROM `grand_casino_exclusions` 
        WHERE player_citizenid = ? 
        AND (exclusion_end IS NULL OR exclusion_end > CURRENT_TIMESTAMP)
    ]], { playerCitizenId })
    return result ~= nil
end

-- Add player exclusion
function Database.AddExclusion(playerCitizenId, exclusionType, hours, reason, enforcedBy)
    local exclusionEnd = nil
    if hours > 0 then
        exclusionEnd = os.date('!%Y-%m-%d %H:%M:%S', os.time() + (hours * 3600))
    end
    
    return MySQL.insert.await([[
        INSERT INTO `grand_casino_exclusions` 
        (player_citizenid, exclusion_type, exclusion_end, reason, enforced_by)
        VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        exclusion_type = VALUES(exclusion_type),
        exclusion_end = VALUES(exclusion_end),
        reason = VALUES(reason),
        enforced_by = VALUES(enforced_by)
    ]], { playerCitizenId, exclusionType, exclusionEnd, reason, enforcedBy })
end

-- Remove player exclusion
function Database.RemoveExclusion(playerCitizenId)
    return MySQL.update.await([[
        DELETE FROM `grand_casino_exclusions` WHERE player_citizenid = ?
    ]], { playerCitizenId })
end

-- Get player statistics
function Database.GetPlayerStats(playerCitizenId, days)
    days = days or 30
    local result = MySQL.single.await([[
        SELECT 
            COUNT(*) as total_rounds,
            SUM(bet_amount) as total_bet,
            SUM(payout) as total_won,
            SUM(payout - bet_amount) as net_result,
            MAX(created_at) as last_played
        FROM `grand_casino_rounds`
        WHERE player_citizenid = ? 
        AND created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { playerCitizenId, days })
    
    return result or { total_rounds = 0, total_bet = 0, total_won = 0, net_result = 0, last_played = nil }
end

-- Get player hourly loss
function Database.GetPlayerHourlyLoss(playerCitizenId)
    local result = MySQL.single.await([[
        SELECT COALESCE(SUM(bet_amount - payout), 0) as hourly_loss
        FROM `grand_casino_rounds`
        WHERE player_citizenid = ? 
        AND created_at > DATE_SUB(NOW(), INTERVAL 1 HOUR)
        AND payout < bet_amount
    ]], { playerCitizenId })
    
    return tonumber(result.hourly_loss) or 0
end

-- Get player daily loss
function Database.GetPlayerDailyLoss(playerCitizenId)
    local result = MySQL.single.await([[
        SELECT COALESCE(SUM(bet_amount - payout), 0) as daily_loss
        FROM `grand_casino_rounds`
        WHERE player_citizenid = ? 
        AND created_at > DATE_SUB(NOW(), INTERVAL 1 DAY)
        AND payout < bet_amount
    ]], { playerCitizenId })
    
    return tonumber(result.daily_loss) or 0
end

-- Update jackpot amount
function Database.UpdateJackpot(jackpotType, amountChange)
    if amountChange > 0 then
        return MySQL.update.await([[
            UPDATE `grand_casino_jackpot` 
            SET current_amount = current_amount + ?
            WHERE jackpot_type = ?
        ]], { amountChange, jackpotType })
    else
        return MySQL.update.await([[
            UPDATE `grand_casino_jackpot` 
            SET current_amount = GREATEST(0, current_amount + ?)
            WHERE jackpot_type = ?
        ]], { amountChange, jackpotType })
    end
end

-- Win jackpot
function Database.WinJackpot(jackpotType, playerCitizenId, winAmount)
    return MySQL.update.await([[
        UPDATE `grand_casino_jackpot` 
        SET current_amount = GREATEST(0, current_amount - ?),
            last_winner = ?,
            last_win_amount = ?,
            last_win_time = CURRENT_TIMESTAMP
        WHERE jackpot_type = ?
    ]], { winAmount, playerCitizenId, winAmount, jackpotType })
end

-- Get jackpot info
function Database.GetJackpot(jackpotType)
    return MySQL.single.await([[
        SELECT * FROM `grand_casino_jackpot` WHERE jackpot_type = ?
    ]], { jackpotType })
end

-- Clean up old data
function Database.CleanupOldData()
    local roundDays = Config.Database.roundRetentionDays
    local sessionHours = Config.Database.sessionCleanupHours
    
    if roundDays > 0 then
        MySQL.update.await([[
            DELETE FROM `grand_casino_rounds` 
            WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
        ]], { roundDays })
    end
    
    if sessionHours > 0 then
        MySQL.update.await([[
            DELETE FROM `grand_casino_sessions` 
            WHERE session_end < DATE_SUB(NOW(), INTERVAL ? HOUR)
            OR (session_end IS NULL AND session_start < DATE_SUB(NOW(), INTERVAL 24 HOUR))
        ]], { sessionHours })
    end
    
    -- Clean expired exclusions
    MySQL.update.await([[
        DELETE FROM `grand_casino_exclusions` 
        WHERE exclusion_end IS NOT NULL 
        AND exclusion_end < CURRENT_TIMESTAMP
    ]])
end

-- Get player's recent rounds
function Database.GetPlayerRounds(playerCitizenId, limit)
    limit = limit or 10
    return MySQL.query.await([[
        SELECT * FROM `grand_casino_rounds` 
        WHERE player_citizenid = ? 
        ORDER BY created_at DESC 
        LIMIT ?
    ]], { playerCitizenId, limit })
end

-- Verify round seed and result
function Database.VerifyRound(roundId, expectedSeed, expectedResult)
    local round = Database.GetRound(roundId)
    if not round then return false end
    
    local result = json.decode(round.result)
    return round.seed == expectedSeed and result == expectedResult
end

return Database