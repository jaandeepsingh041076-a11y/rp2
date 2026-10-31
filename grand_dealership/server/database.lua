-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_dealership/server/database.lua
--  Every SQL statement for the dealership network.
--  oxmysql MySQL.*.await only. Additive tables, no foreign keys.
--
--  Owned vehicles live in the root `grand_vehicles` table:
--    state 0 = out of the garage, 1 = stored, 2 = impounded.
-- ─────────────────────────────────────────────────────────────

DealerDB = DealerDB or {}
local DB = DealerDB

DB.Ready = false

-- ─── Schema ──────────────────────────────────────────────────
DB.Schema = {
    [[CREATE TABLE IF NOT EXISTS `grand_dealer_sales` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `citizenid` VARCHAR(50) NOT NULL,
        `model` VARCHAR(50) NOT NULL,
        `label` VARCHAR(96) DEFAULT NULL,
        `plate` VARCHAR(12) NOT NULL,
        `vehicle_id` BIGINT DEFAULT NULL,
        `price` INT NOT NULL DEFAULT 0,
        `tax` INT NOT NULL DEFAULT 0,
        `total` INT NOT NULL DEFAULT 0,
        `payment_type` VARCHAR(16) NOT NULL DEFAULT 'cash',
        `down_payment` INT NOT NULL DEFAULT 0,
        `financed` INT NOT NULL DEFAULT 0,
        `finance_id` BIGINT DEFAULT NULL,
        `lot` VARCHAR(32) DEFAULT NULL,
        `salesman_citizenid` VARCHAR(50) DEFAULT NULL,
        `salesman_name` VARCHAR(96) DEFAULT NULL,
        `sold_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY `idx_dealer_sale_cid` (`citizenid`, `sold_at`),
        KEY `idx_dealer_sale_plate` (`plate`),
        KEY `idx_dealer_sale_model` (`model`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_dealer_finance` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `sale_id` BIGINT DEFAULT NULL,
        `citizenid` VARCHAR(50) NOT NULL,
        `vehicle_id` BIGINT DEFAULT NULL,
        `plate` VARCHAR(12) NOT NULL,
        `model` VARCHAR(50) NOT NULL,
        `principal` INT NOT NULL DEFAULT 0,
        `down_payment` INT NOT NULL DEFAULT 0,
        `financed` INT NOT NULL DEFAULT 0,
        `term_weeks` INT NOT NULL DEFAULT 24,
        `weekly_payment` INT NOT NULL DEFAULT 0,
        `apr` FLOAT NOT NULL DEFAULT 0.0,
        `late_fees` INT NOT NULL DEFAULT 0,
        `weeks_paid` INT NOT NULL DEFAULT 0,
        `missed_weeks` INT NOT NULL DEFAULT 0,
        `next_due_at` TIMESTAMP NULL DEFAULT NULL,
        `last_payment_at` TIMESTAMP NULL DEFAULT NULL,
        `status` VARCHAR(16) NOT NULL DEFAULT 'active',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY `idx_dealer_fin_cid` (`citizenid`, `status`),
        KEY `idx_dealer_fin_due` (`status`, `next_due_at`),
        KEY `idx_dealer_fin_plate` (`plate`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_dealer_payments` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `finance_id` BIGINT NOT NULL,
        `citizenid` VARCHAR(50) NOT NULL,
        `amount` INT NOT NULL DEFAULT 0,
        `principal_part` INT NOT NULL DEFAULT 0,
        `interest_part` INT NOT NULL DEFAULT 0,
        `late_fee` INT NOT NULL DEFAULT 0,
        `weeks` INT NOT NULL DEFAULT 1,
        `source` VARCHAR(16) NOT NULL DEFAULT 'bank',
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY `idx_dealer_pay_fin` (`finance_id`, `created_at`),
        KEY `idx_dealer_pay_cid` (`citizenid`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_dealer_stock` (
        `model` VARCHAR(50) NOT NULL PRIMARY KEY,
        `stock` INT NOT NULL DEFAULT 0,
        `initial_stock` INT NOT NULL DEFAULT 0,
        `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_dealer_licences` (
        `citizenid` VARCHAR(50) NOT NULL PRIMARY KEY,
        `status` VARCHAR(16) NOT NULL DEFAULT 'valid',
        `issued_by` VARCHAR(96) DEFAULT NULL,
        `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `expires_at` TIMESTAMP NULL DEFAULT NULL,
        KEY `idx_dealer_licence_status` (`status`, `expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_dealer_testdrives` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `citizenid` VARCHAR(50) NOT NULL,
        `lot` VARCHAR(32) DEFAULT NULL,
        `model` VARCHAR(50) NOT NULL,
        `plate` VARCHAR(12) DEFAULT NULL,
        `deposit` INT NOT NULL DEFAULT 0,
        `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        `expires_at` TIMESTAMP NULL DEFAULT NULL,
        `returned_at` TIMESTAMP NULL DEFAULT NULL,
        `damage_fee` INT NOT NULL DEFAULT 0,
        `status` VARCHAR(16) NOT NULL DEFAULT 'active',
        KEY `idx_dealer_td_cid` (`citizenid`, `started_at`),
        KEY `idx_dealer_td_status` (`status`, `expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_dealer_repossessions` (
        `id` BIGINT AUTO_INCREMENT PRIMARY KEY,
        `finance_id` BIGINT DEFAULT NULL,
        `citizenid` VARCHAR(50) NOT NULL,
        `plate` VARCHAR(12) DEFAULT NULL,
        `model` VARCHAR(50) DEFAULT NULL,
        `reason` VARCHAR(190) DEFAULT NULL,
        `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
        KEY `idx_dealer_repo_cid` (`citizenid`, `created_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}

-- ─── Wrappers ────────────────────────────────────────────────
local function safe(fn, sql, params)
    local ok, result = pcall(fn, sql, params or {})
    if not ok then
        DealerShared.Log('error', ('query failed: %s'):format(tostring(result)))
        return nil
    end
    return result
end

function DB.Single(sql, params) return safe(MySQL.single.await, sql, params) end
function DB.Query(sql, params) return safe(MySQL.query.await, sql, params) or {} end
function DB.Scalar(sql, params) return safe(MySQL.scalar.await, sql, params) end
function DB.Insert(sql, params) return safe(MySQL.insert.await, sql, params) end
function DB.Update(sql, params) return safe(MySQL.update.await, sql, params) or 0 end

-- ─── Bootstrap ───────────────────────────────────────────────
function DB.Bootstrap()
    if DB.Ready then return true end

    for _, statement in ipairs(DB.Schema) do
        local ok, err = pcall(MySQL.query.await, statement)
        if not ok then
            DealerShared.Log('error', ('schema statement failed: %s'):format(tostring(err)))
        end
    end

    DB.SeedStock()
    DB.Ready = true
    DealerShared.Log('info', 'dealership schema ready')
    return true
end

--- Inserts a stock row for every catalogue model exactly once.
function DB.SeedStock()
    for _, entry in pairs(Config.ModelIndex) do
        pcall(MySQL.query.await, [[
            INSERT IGNORE INTO `grand_dealer_stock` (model, stock, initial_stock)
            VALUES (?, ?, ?)
        ]], { entry.model, DealerShared.Int(entry.stock) or 0, DealerShared.Int(entry.stock) or 0 })
    end
end

function DB.GetStock(model)
    local stock = DB.Scalar('SELECT stock FROM `grand_dealer_stock` WHERE model = ? LIMIT 1',
        { tostring(model) })
    return tonumber(stock) or 0
end

--- Adds `delta` to stock. Returns false when it would go negative.
function DB.AdjustStock(model, delta)
    delta = DealerShared.Int(delta) or 0
    if delta == 0 then return true end
    local changed = DB.Update([[
        UPDATE `grand_dealer_stock`
           SET stock = stock + ?
         WHERE model = ? AND stock + ? >= 0
    ]], { delta, tostring(model), delta })
    return changed == 1
end

function DB.RestockAll()
    DB.Update([[
        UPDATE `grand_dealer_stock`
           SET stock = LEAST(initial_stock, stock + 1)
         WHERE stock < initial_stock
    ]], {})
end

function DB.AllStock()
    return DB.Query([[
        SELECT model, stock, initial_stock, updated_at
          FROM `grand_dealer_stock`
         ORDER BY model ASC
    ]], {})
end

-- ─── Vehicles ────────────────────────────────────────────────
local plateChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

local function randomPlate()
    local out = { 'D', 'L' }
    for _ = 1, 5 do
        local index = math.random(1, #plateChars)
        out[#out + 1] = plateChars:sub(index, index)
    end
    return table.concat(out)
end

function DB.VehicleByPlate(plate)
    return DB.Single('SELECT * FROM `grand_vehicles` WHERE plate = ? LIMIT 1', { tostring(plate) })
end

function DB.VehicleById(id)
    return DB.Single('SELECT * FROM `grand_vehicles` WHERE id = ? LIMIT 1', { DealerShared.Int(id) or 0 })
end

function DB.VehiclesFor(citizenid, state)
    if state ~= nil then
        return DB.Query([[
            SELECT * FROM `grand_vehicles`
             WHERE citizenid = ? AND state = ?
             ORDER BY garage ASC, id ASC
        ]], { citizenid, state })
    end
    return DB.Query([[
        SELECT * FROM `grand_vehicles`
         WHERE citizenid = ?
         ORDER BY state ASC, garage ASC, id ASC
    ]], { citizenid })
end

function DB.OwnedCount(citizenid)
    return tonumber(DB.Scalar('SELECT COUNT(*) FROM `grand_vehicles` WHERE citizenid = ?',
        { citizenid })) or 0
end

--- Inserts a purchased vehicle and returns its id + plate.
function DB.AddVehicle(citizenid, model, garage, props)
    for _ = 1, 12 do
        local plate = randomPlate()
        if not DB.VehicleByPlate(plate) then
            local payload = DealerShared.SanitizeProps(props, model, plate)
            local id = DB.Insert([[
                INSERT INTO `grand_vehicles`
                    (citizenid, plate, model, props, garage, state, fuel)
                VALUES (?, ?, ?, ?, ?, 1, ?)
            ]], {
                citizenid, plate, tostring(model), json.encode(payload),
                garage or 'Legion_Square', payload.fuel or 100,
            })
            if id then return id, plate end
        end
    end
    return nil, nil
end

function DB.SetVehicleState(plate, state, garage)
    if garage then
        return DB.Update('UPDATE `grand_vehicles` SET state = ?, garage = ? WHERE plate = ?',
            { DealerShared.Int(state) or 1, garage, plate }) == 1
    end
    return DB.Update('UPDATE `grand_vehicles` SET state = ? WHERE plate = ?',
        { DealerShared.Int(state) or 1, plate }) == 1
end

function DB.SetVehicleGarage(plate, garage)
    return DB.Update('UPDATE `grand_vehicles` SET garage = ? WHERE plate = ?',
        { garage, plate }) == 1
end

function DB.SaveVehicleProps(plate, props, fuel)
    local payload = DealerShared.SanitizeProps(props, props and props.model, plate)
    return DB.Update([[
        UPDATE `grand_vehicles`
           SET props = ?, fuel = ?
         WHERE plate = ?
    ]], { json.encode(payload), DealerShared.Int(fuel) or payload.fuel or 100, plate }) == 1
end

function DB.TransferVehicle(plate, fromCitizenid, toCitizenid)
    return DB.Update([[
        UPDATE `grand_vehicles`
           SET citizenid = ?, garage = 'Legion_Square', state = 1
         WHERE plate = ? AND citizenid = ?
    ]], { toCitizenid, plate, fromCitizenid }) == 1
end

function DB.DeleteVehicle(plate, citizenid)
    return DB.Update('DELETE FROM `grand_vehicles` WHERE plate = ? AND citizenid = ?',
        { plate, citizenid }) == 1
end

-- ─── Sales ───────────────────────────────────────────────────
function DB.CreateSale(row)
    return DB.Insert([[
        INSERT INTO `grand_dealer_sales`
            (citizenid, model, label, plate, vehicle_id, price, tax, total,
             payment_type, down_payment, financed, finance_id, lot,
             salesman_citizenid, salesman_name)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        row.citizenid, row.model, row.label, row.plate, row.vehicle_id,
        row.price, row.tax, row.total, row.payment_type or 'cash',
        row.down_payment or 0, row.financed or 0, row.finance_id,
        row.lot, row.salesman_citizenid, row.salesman_name,
    })
end

function DB.SaleById(id)
    return DB.Single('SELECT * FROM `grand_dealer_sales` WHERE id = ? LIMIT 1',
        { DealerShared.Int(id) or 0 })
end

function DB.SalesFor(citizenid, limit)
    limit = DealerShared.Clamp(DealerShared.Int(limit) or 10, 1, 50)
    return DB.Query([[
        SELECT * FROM `grand_dealer_sales`
         WHERE citizenid = ?
         ORDER BY id DESC LIMIT ?
    ]], { citizenid, limit })
end

-- ─── Finance ─────────────────────────────────────────────────
function DB.CreateFinance(row)
    return DB.Insert([[
        INSERT INTO `grand_dealer_finance`
            (sale_id, citizenid, vehicle_id, plate, model, principal,
             down_payment, financed, term_weeks, weekly_payment, apr,
             weeks_paid, missed_weeks, next_due_at, status)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, FROM_UNIXTIME(?), 'active')
    ]], {
        row.sale_id, row.citizenid, row.vehicle_id, row.plate, row.model,
        row.principal, row.down_payment, row.financed, row.term_weeks,
        row.weekly_payment, row.apr, row.next_due_at,
    })
end

function DB.FinanceById(id)
    return DB.Single('SELECT * FROM `grand_dealer_finance` WHERE id = ? LIMIT 1',
        { DealerShared.Int(id) or 0 })
end

function DB.FinanceByPlate(plate)
    return DB.Single([[
        SELECT * FROM `grand_dealer_finance`
         WHERE plate = ? AND status = 'active'
         ORDER BY id DESC LIMIT 1
    ]], { tostring(plate) })
end

function DB.ActiveFinanceFor(citizenid, plate)
    if plate then
        return DB.Single([[
            SELECT * FROM `grand_dealer_finance`
             WHERE citizenid = ? AND plate = ? AND status = 'active'
             ORDER BY id DESC LIMIT 1
        ]], { citizenid, plate })
    end
    return DB.Query([[
        SELECT * FROM `grand_dealer_finance`
         WHERE citizenid = ? AND status = 'active'
         ORDER BY id ASC
    ]], { citizenid })
end

function DB.DueFinance()
    return DB.Query([[
        SELECT * FROM `grand_dealer_finance`
         WHERE status = 'active' AND next_due_at IS NOT NULL AND next_due_at <= NOW()
         ORDER BY next_due_at ASC LIMIT 100
    ]], {})
end

function DB.RecordPayment(row)
    return DB.Insert([[
        INSERT INTO `grand_dealer_payments`
            (finance_id, citizenid, amount, principal_part, interest_part,
             late_fee, weeks, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        row.finance_id, row.citizenid, row.amount, row.principal_part or 0,
        row.interest_part or 0, row.late_fee or 0, row.weeks or 1, row.source or 'bank',
    })
end

function DB.UpdateFinanceAfterPayment(id, weeksPaid, nextDueAt, lateFees)
    return DB.Update([[
        UPDATE `grand_dealer_finance`
           SET weeks_paid = ?, missed_weeks = 0,
               late_fees = ?,
               last_payment_at = NOW(), next_due_at = FROM_UNIXTIME(?)
         WHERE id = ? AND status = 'active'
    ]], { weeksPaid, math.max(0, DealerShared.Int(lateFees) or 0), nextDueAt, id }) == 1
end

function DB.SetFinanceStatus(id, status)
    return DB.Update('UPDATE `grand_dealer_finance` SET status = ? WHERE id = ?',
        { tostring(status), DealerShared.Int(id) or 0 }) == 1
end

function DB.SetFinanceDue(id, nextDueAt, missedWeeks, lateFees)
    return DB.Update([[
        UPDATE `grand_dealer_finance`
           SET next_due_at = FROM_UNIXTIME(?), missed_weeks = ?, late_fees = ?
         WHERE id = ? AND status = 'active'
    ]], { nextDueAt, missedWeeks, math.max(0, lateFees or 0), id }) == 1
end

function DB.RecordRepossession(row)
    return DB.Insert([[
        INSERT INTO `grand_dealer_repossessions`
            (finance_id, citizenid, plate, model, reason)
        VALUES (?, ?, ?, ?, ?)
    ]], {
        row.finance_id, row.citizenid, row.plate, row.model,
        DealerShared.SanitizeText(row.reason or 'defaulted finance', 190),
    })
end

function DB.Repossessions(limit)
    limit = DealerShared.Clamp(DealerShared.Int(limit) or 10, 1, 50)
    return DB.Query([[
        SELECT * FROM `grand_dealer_repossessions`
         ORDER BY id DESC LIMIT ?
    ]], { limit })
end

-- ─── Licences ────────────────────────────────────────────────
function DB.Licence(citizenid)
    return DB.Single('SELECT * FROM `grand_dealer_licences` WHERE citizenid = ? LIMIT 1',
        { citizenid })
end

function DB.SetLicence(citizenid, status, issuedBy, weeks)
    weeks = DealerShared.Clamp(DealerShared.Int(weeks) or Config.Licence.validityWeeks or 52, 1, 260)
    return DB.Insert([[
        INSERT INTO `grand_dealer_licences`
            (citizenid, status, issued_by, expires_at)
        VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? WEEK))
        ON DUPLICATE KEY UPDATE
            status = VALUES(status),
            issued_by = VALUES(issued_by),
            issued_at = NOW(),
            expires_at = VALUES(expires_at)
    ]], { citizenid, status, issuedBy, weeks }) ~= nil
end

-- ─── Test drives ─────────────────────────────────────────────
function DB.CreateTestDrive(row)
    return DB.Insert([[
        INSERT INTO `grand_dealer_testdrives`
            (citizenid, lot, model, plate, deposit, expires_at, status)
        VALUES (?, ?, ?, ?, ?, FROM_UNIXTIME(?), 'active')
    ]], {
        row.citizenid, row.lot, row.model, row.plate,
        row.deposit or 0, row.expires_at,
    })
end

function DB.ActiveTestDrive(citizenid)
    return DB.Single([[
        SELECT * FROM `grand_dealer_testdrives`
         WHERE citizenid = ? AND status = 'active'
         ORDER BY id DESC LIMIT 1
    ]], { citizenid })
end

function DB.RecentTestDrives(citizenid, windowSeconds)
    windowSeconds = DealerShared.Int(windowSeconds) or 3600
    return DB.Query([[
        SELECT * FROM `grand_dealer_testdrives`
         WHERE citizenid = ? AND started_at > DATE_SUB(NOW(), INTERVAL ? SECOND)
         ORDER BY id DESC
    ]], { citizenid, windowSeconds })
end

function DB.EndTestDrive(id, status, damageFee)
    return DB.Update([[
        UPDATE `grand_dealer_testdrives`
           SET status = ?, returned_at = NOW(), damage_fee = ?
         WHERE id = ? AND status = 'active'
    ]], { tostring(status or 'returned'), DealerShared.Int(damageFee) or 0, DealerShared.Int(id) or 0 }) == 1
end

function DB.ExpireTestDrives()
    return DB.Update([[
        UPDATE `grand_dealer_testdrives`
           SET status = 'expired', returned_at = NOW()
         WHERE status = 'active' AND expires_at IS NOT NULL AND expires_at <= NOW()
    ]], {})
end

-- ─── Stats ───────────────────────────────────────────────────
function DB.Stats()
    local row = DB.Single([[
        SELECT
          (SELECT COUNT(*) FROM `grand_dealer_sales`) AS total_sales,
          (SELECT COALESCE(SUM(total), 0) FROM `grand_dealer_sales`) AS total_value,
          (SELECT COUNT(*) FROM `grand_dealer_sales` WHERE sold_at >= CURDATE()) AS sales_today,
          (SELECT COUNT(*) FROM `grand_dealer_finance` WHERE status = 'active') AS active_finance,
          (SELECT COALESCE(SUM(financed - (weekly_payment * weeks_paid)), 0)
             FROM `grand_dealer_finance` WHERE status = 'active') AS outstanding,
          (SELECT COUNT(*) FROM `grand_dealer_finance` WHERE status = 'defaulted') AS defaulted,
          (SELECT COUNT(*) FROM `grand_vehicles` WHERE state = 1) AS stored_vehicles
    ]], {})
    return row or {}
end

return DB
