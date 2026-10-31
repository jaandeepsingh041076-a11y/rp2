-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_coin/server/database.lua
--  Every SQL statement in the resource. oxmysql MySQL.*.await
--  only - never exports.oxmysql:fetch/:insert.
--
--  `users.grand_coins` is the canonical balance (root
--  database.sql). `users` is keyed by identifier, so we join
--  through `characters` to resolve a citizenid.
-- ─────────────────────────────────────────────────────────────

Database = Database or {}
local DB = Database

DB.Ready = false

-- ─── Schema ──────────────────────────────────────────────────
DB.Schema = {
    [[CREATE TABLE IF NOT EXISTS `grand_coin_ledger` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_coin_purchases` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_coin_exchange` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `player_citizenid` VARCHAR(50) NOT NULL,
        `exchange_type` VARCHAR(24) NOT NULL,
        `coin_amount` INT NOT NULL DEFAULT 0,
        `cash_amount` INT NOT NULL DEFAULT 0,
        `fee_amount` INT NOT NULL DEFAULT 0,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY `idx_coin_ex_player` (`player_citizenid`, `created_at`),
        KEY `idx_coin_ex_type` (`exchange_type`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_coin_liquidity` (
        `id` INT AUTO_INCREMENT PRIMARY KEY,
        `pool_date` DATE NOT NULL,
        `total_pool` BIGINT NOT NULL DEFAULT 0,
        `remaining_pool` BIGINT NOT NULL DEFAULT 0,
        `cash_outs` BIGINT NOT NULL DEFAULT 0,
        `cash_ins` BIGINT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        UNIQUE KEY `uk_coin_pool_date` (`pool_date`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}

-- ─── Thin query wrappers with pcall ──────────────────────────
local function safe(fn, sql, params)
    local ok, result = pcall(fn, sql, params)
    if not ok then
        Util.Log('error', ('query failed: %s'):format(tostring(result)))
        return nil
    end
    return result
end

function DB.Single(sql, params)
    return safe(MySQL.single.await, sql, params or {})
end

function DB.Query(sql, params)
    return safe(MySQL.query.await, sql, params or {}) or {}
end

function DB.Scalar(sql, params)
    return safe(MySQL.scalar.await, sql, params or {})
end

function DB.Insert(sql, params)
    return safe(MySQL.insert.await, sql, params or {})
end

function DB.Update(sql, params)
    return safe(MySQL.update.await, sql, params or {}) or 0
end

-- ─── Bootstrap ───────────────────────────────────────────────
function DB.Bootstrap()
    if DB.Ready then return true end

    -- users.grand_coins must exist even on an older dump.
    pcall(function()
        MySQL.query.await([[ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `grand_coins` INT NOT NULL DEFAULT 0]])
    end)
    pcall(function()
        MySQL.query.await([[ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `vip_level` INT NOT NULL DEFAULT 0]])
    end)
    pcall(function()
        MySQL.query.await([[ALTER TABLE `users` ADD COLUMN IF NOT EXISTS `vip_expires` TIMESTAMP NULL DEFAULT NULL]])
    end)

    for _, statement in ipairs(DB.Schema) do
        local ok = pcall(MySQL.query.await, statement)
        if not ok then
            Util.Log('error', 'schema statement failed - check the database user privileges')
        end
    end

    DB.EnsurePool()
    DB.Ready = true
    Util.Log('info', 'Grand Coins schema ready')
    return true
end

-- ─── Account / balance ───────────────────────────────────────
--- Resolves a citizenid to the owning account row.
--- Returns { id, identifier, grand_coins, vip_level, vip_expires }.
function DB.Account(citizenid)
    if type(citizenid) ~= 'string' or citizenid == '' then return nil end

    local row = DB.Single([[
        SELECT u.id, u.identifier, u.grand_coins, u.vip_level, u.vip_expires
          FROM users u
          JOIN characters c ON c.identifier = u.identifier
         WHERE c.citizenid = ?
         LIMIT 1
    ]], { citizenid })

    if row then return row end

    -- Offline / account-identifier callers (identifier happens to be
    -- passed in) still resolve against users directly.
    return DB.Single([[
        SELECT id, identifier, grand_coins, vip_level, vip_expires
          FROM users WHERE identifier = ? LIMIT 1
    ]], { citizenid })
end

function DB.GetBalance(citizenid)
    local account = DB.Account(citizenid)
    return account and (tonumber(account.grand_coins) or 0) or 0
end

--- Optimistic, guarded adjustment. Returns newBalance, before or nil, reason.
function DB.AdjustBalance(citizenid, delta, maxBalance)
    delta = Util.Int(delta)
    if not delta or delta == 0 then return nil, 'invalid amount' end

    local unlock = Util.Lock('balance:' .. tostring(citizenid))
    if not unlock then return nil, 'another transaction is in progress' end

    local ok, newBalance, before = pcall(function()
        local account = DB.Account(citizenid)
        if not account then return nil, 'no account for that citizen' end

        local current = tonumber(account.grand_coins) or 0
        local after = current + delta
        if after < 0 then return nil, 'insufficient balance' end
        if maxBalance and after > maxBalance then return nil, 'balance cap reached' end

        local changed = DB.Update([[
            UPDATE users SET grand_coins = ?
             WHERE id = ? AND grand_coins = ?
        ]], { after, account.id, current })

        if changed ~= 1 then return nil, 'balance changed, try again' end
        return after, current
    end)

    unlock()

    if not ok then
        Util.Log('error', ('adjustment failed: %s'):format(tostring(newBalance)))
        return nil, 'transaction failed'
    end
    return newBalance, before
end

function DB.SetBalance(citizenid, value)
    local account = DB.Account(citizenid)
    if not account then return false end
    return DB.Update('UPDATE users SET grand_coins = ? WHERE id = ?', {
        math.max(0, Util.Int(value) or 0), account.id,
    }) == 1
end

function DB.SetVip(citizenid, hours)
    hours = Util.Int(hours) or 0
    if hours <= 0 then return false end
    local account = DB.Account(citizenid)
    if not account then return false end
    return DB.Update([[
        UPDATE users
           SET vip_level = GREATEST(COALESCE(vip_level, 0), 1),
               vip_expires = DATE_ADD(GREATEST(COALESCE(vip_expires, NOW()), NOW()), INTERVAL ? HOUR)
         WHERE id = ?
    ]], { hours, account.id }) == 1
end

-- ─── Ledger ──────────────────────────────────────────────────
function DB.Ledger(txnId, citizenid, delta, kind, reason, before, after, meta, sourcePlayer, targetPlayer)
    return DB.Insert([[
        INSERT INTO `grand_coin_ledger`
            (transaction_id, player_citizenid, change_amount, transaction_type,
             reason, balance_before, balance_after, source_player, target_player, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        tostring(txnId or Util.TxnId()), citizenid, delta, kind,
        Util.SanitizeText(reason or kind, 190),
        before or 0, after or 0, sourcePlayer, targetPlayer,
        meta and json.encode(meta) or nil,
    })
end

function DB.History(citizenid, limit, offset)
    limit = Util.Clamp(Util.Int(limit) or 20, 1, 100)
    offset = math.max(Util.Int(offset) or 0, 0)
    return DB.Query([[
        SELECT id, transaction_id, change_amount, transaction_type, reason,
               balance_before, balance_after, created_at
          FROM `grand_coin_ledger`
         WHERE player_citizenid = ?
         ORDER BY id DESC
         LIMIT ? OFFSET ?
    ]], { citizenid, limit, offset })
end

function DB.Transaction(transactionId)
    return DB.Single('SELECT * FROM `grand_coin_ledger` WHERE transaction_id = ? LIMIT 1',
        { tostring(transactionId) })
end

--- Total earned from gameplay today (daily cap input).
function DB.EarnedToday(citizenid)
    local total = DB.Scalar([[
        SELECT COALESCE(SUM(change_amount), 0)
          FROM `grand_coin_ledger`
         WHERE player_citizenid = ?
           AND change_amount > 0
           AND transaction_type IN ('job_reward', 'event_reward', 'daily_reward')
           AND created_at >= CURDATE()
    ]], { citizenid })
    return tonumber(total) or 0
end

function DB.Stats(citizenid, days)
    days = Util.Clamp(Util.Int(days) or 30, 1, 365)
    local row = DB.Single([[
        SELECT COUNT(*) AS total_transactions,
               COALESCE(SUM(CASE WHEN change_amount > 0 THEN change_amount ELSE 0 END), 0) AS total_incoming,
               COALESCE(SUM(CASE WHEN change_amount < 0 THEN -change_amount ELSE 0 END), 0) AS total_outgoing,
               MIN(created_at) AS first_transaction,
               MAX(created_at) AS last_transaction
          FROM `grand_coin_ledger`
         WHERE player_citizenid = ?
           AND created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { citizenid, days })

    return row or { total_transactions = 0, total_incoming = 0, total_outgoing = 0 }
end

function DB.LedgerSum(citizenid)
    return tonumber(DB.Scalar([[
        SELECT COALESCE(SUM(change_amount), 0)
          FROM `grand_coin_ledger` WHERE player_citizenid = ?
    ]], { citizenid })) or 0
end

--- Players with ledger activity in the last `days` days.
function DB.ActiveCitizens(days, limit)
    days = Util.Clamp(Util.Int(days) or 7, 1, 90)
    limit = Util.Clamp(Util.Int(limit) or 100, 1, 500)
    return DB.Query([[
        SELECT DISTINCT player_citizenid
          FROM `grand_coin_ledger`
         WHERE created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
         LIMIT ?
    ]], { days, limit })
end

-- ─── Purchases ───────────────────────────────────────────────
function DB.RecordPurchase(transactionId, citizenid, item, quantity, totalCost)
    local delivery = {
        type = item.type,
        vehicle = item.vehicle,
        duration = item.duration,
        amount = item.amount,
        purchased_at = os.time(),
    }
    return DB.Insert([[
        INSERT INTO `grand_coin_purchases`
            (transaction_id, player_citizenid, item_slug, item_name, item_type,
             quantity, total_cost, delivery_status, delivery_data)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', ?)
    ]], {
        tostring(transactionId), citizenid, item.slug, Util.SanitizeText(item.name, 128),
        item.type, quantity, totalCost, json.encode(delivery),
    })
end

function DB.PurchaseStatus(transactionId, status, data)
    return DB.Update([[
        UPDATE `grand_coin_purchases`
           SET delivery_status = ?, delivery_data = COALESCE(?, delivery_data)
         WHERE transaction_id = ?
    ]], { tostring(status), data and json.encode(data) or nil, tostring(transactionId) })
end

function DB.Purchases(citizenid, limit)
    limit = Util.Clamp(Util.Int(limit) or 10, 1, 50)
    return DB.Query([[
        SELECT id, transaction_id, item_slug, item_name, item_type, quantity,
               total_cost, delivery_status, created_at
          FROM `grand_coin_purchases`
         WHERE player_citizenid = ?
         ORDER BY id DESC
         LIMIT ?
    ]], { citizenid, limit })
end

-- ─── Exchange ────────────────────────────────────────────────
function DB.RecordExchange(citizenid, kind, coins, cash, fee)
    return DB.Insert([[
        INSERT INTO `grand_coin_exchange`
            (player_citizenid, exchange_type, coin_amount, cash_amount, fee_amount)
        VALUES (?, ?, ?, ?, ?)
    ]], { citizenid, kind, coins or 0, cash or 0, fee or 0 })
end

function DB.ExchangeTotals(citizenid, hours)
    hours = Util.Clamp(Util.Int(hours) or 1, 1, 168)
    local row = DB.Single([[
        SELECT COALESCE(SUM(CASE WHEN exchange_type = 'cash_out' THEN coin_amount ELSE 0 END), 0) AS cash_out_coins,
               COALESCE(SUM(CASE WHEN exchange_type = 'cash_in' THEN coin_amount ELSE 0 END), 0) AS cash_in_coins,
               COALESCE(SUM(CASE WHEN exchange_type = 'cash_out' THEN cash_amount ELSE 0 END), 0) AS cash_out_amount,
               COALESCE(SUM(CASE WHEN exchange_type = 'cash_in' THEN cash_amount ELSE 0 END), 0) AS cash_in_amount
          FROM `grand_coin_exchange`
         WHERE player_citizenid = ?
           AND created_at > DATE_SUB(NOW(), INTERVAL ? HOUR)
    ]], { citizenid, hours })

    return row or { cash_out_coins = 0, cash_in_coins = 0, cash_out_amount = 0, cash_in_amount = 0 }
end

-- ─── Liquidity pool ──────────────────────────────────────────
function DB.EnsurePool()
    local pool = DB.Query([[
        INSERT IGNORE INTO `grand_coin_liquidity` (pool_date, total_pool, remaining_pool)
        VALUES (CURDATE(), ?, ?)
    ]], { Config.Exchange.dailyLiquidityPool, Config.Exchange.dailyLiquidityPool })
    return pool ~= nil
end

function DB.Pool()
    return DB.Single('SELECT * FROM `grand_coin_liquidity` WHERE pool_date = CURDATE() LIMIT 1')
end

--- Reserves cash from today's pool. Returns true when the cash was
--- reserved; false when the pool is empty.
function DB.SpendPool(cash)
    cash = Util.Int(cash) or 0
    if cash <= 0 then return true end
    local changed = DB.Update([[
        UPDATE `grand_coin_liquidity`
           SET remaining_pool = remaining_pool - ?,
               cash_outs = cash_outs + ?
         WHERE pool_date = CURDATE() AND remaining_pool >= ?
    ]], { cash, cash, cash })
    return changed == 1
end

function DB.ReturnPool(cash)
    cash = Util.Int(cash) or 0
    if cash <= 0 then return end
    DB.Update([[
        UPDATE `grand_coin_liquidity`
           SET remaining_pool = remaining_pool + ?,
               cash_outs = GREATEST(0, cash_outs - ?)
         WHERE pool_date = CURDATE()
    ]], { cash, cash })
end

function DB.AddPool(cash)
    cash = Util.Int(cash) or 0
    if cash <= 0 then return end
    DB.Update([[
        UPDATE `grand_coin_liquidity`
           SET remaining_pool = remaining_pool + ?,
               cash_ins = cash_ins + ?
         WHERE pool_date = CURDATE()
    ]], { cash, cash })
end

--- Midnight-safe: insert today's row when the server crosses days.
function DB.RollPool()
    DB.EnsurePool()
end

-- ─── Housekeeping ────────────────────────────────────────────
function DB.Cleanup()
    local days = Util.Int(Config.Ledger.retentionDays) or 90
    if days <= 0 then return end
    DB.Update('DELETE FROM `grand_coin_ledger` WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
    DB.Update('DELETE FROM `grand_coin_exchange` WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)', { days })
    DB.Update([[
        DELETE FROM `grand_coin_purchases`
         WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)
           AND delivery_status <> 'pending'
    ]], { days })
    DB.Update('DELETE FROM `grand_coin_liquidity` WHERE pool_date < DATE_SUB(CURDATE(), INTERVAL 60 DAY)', {})
end

function DB.CheckLedger(citizenid)
    local balance = DB.GetBalance(citizenid)
    local ledger = DB.LedgerSum(citizenid)
    local drift = balance - ledger
    return {
        citizenid = citizenid,
        balance = balance,
        ledger = ledger,
        drift = drift,
        consistent = math.abs(drift) <= (Config.Ledger.maxDriftAllowed or 100),
    }
end

--- Offline correction: writes a ledger row so the books stay flat.
function DB.Correct(citizenid, delta, reason)
    local after, before = DB.AdjustBalance(citizenid, delta, Config.Limits.maxBalance)
    if not after then return nil end
    local txn = Util.TxnId()
    DB.Ledger(txn, citizenid, delta, 'correction', reason or 'manual correction', before, after, { automated = true })
    return txn, after
end

--- Adds a shop vehicle to the root grand_vehicles table. Plate is
--- generated and guaranteed unique by the UNIQUE key.
function DB.AddVehicle(citizenid, model, garage)
    local plate = ('GC%05d'):format(math.random(0, 99999))
    local ok = DB.Insert([[
        INSERT INTO `grand_vehicles` (citizenid, plate, model, props, garage, state, fuel)
        VALUES (?, ?, ?, '{}', ?, 1, 100)
    ]], { citizenid, plate, tostring(model), garage or 'Legion_Square' })
    if not ok then return nil end
    return plate
end

return DB
