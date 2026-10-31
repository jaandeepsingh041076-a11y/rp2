-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
--  resources/[grand_systems]/grand_mechanic/server/database.lua
--  Schema bootstrap + every SQL statement the workforce uses.
--  Direct oxmysql: no framework dependency.
-- â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

local RESOURCE = GetCurrentResourceName()
local Shared = Mechanic.Shared

local DB = {}
Mechanic.DB = DB

local function Log(level, message)
    if Util and Util.Log then
        Util.Log(level, ('[mechanic] %s'):format(message))
    else
        print(('[grand_mechanic][%s] %s'):format(level, message))
    end
end
DB.Log = Log

-- â”€â”€â”€ DDL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
local SCHEMA = [[
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
    KEY idx_status (`status`),
    KEY idx_worker (`worker`),
    KEY idx_kind   (`kind`, `status`)
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
    KEY idx_customer (`customer_cid`, `paid`),
    KEY idx_expiry   (`expires`)
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
    KEY idx_plate (`plate`),
    KEY idx_state (`state`),
    KEY idx_site  (`site`)
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
    KEY idx_cid (`citizenid`),
    KEY idx_plate (`plate`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
]]

function DB.CreateSchema()
    if not Config.Persistence.autoCreateSchema then return end
    for statement in (SCHEMA .. ';'):gmatch('([^;]-)%;') do
        if statement:find('CREATE') then
            local ok, err = pcall(function() MySQL.query.await(statement) end)
            if not ok then
                Log('error', ('DDL failed: %s'):format(tostring(err)))
            end
        end
    end
    Log('info', 'workforce schema verified')
end

-- â”€â”€â”€ Character lookup (framework-agnostic) â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function DB.Character(citizenid)
    return MySQL.single.await([[
        SELECT citizenid, identifier, firstname, lastname, job, job_grade, family_id, money, inventory
          FROM characters WHERE citizenid = ? LIMIT 1
    ]], { citizenid })
end

function DB.CharacterByPlate(plate)
    return MySQL.single.await([[
        SELECT v.citizenid, v.plate, v.model, v.garage, v.state, v.fuel, c.firstname, c.lastname
          FROM grand_vehicles v
          LEFT JOIN characters c ON c.citizenid = v.citizenid
         WHERE v.plate = ? LIMIT 1
    ]], { plate })
end

function DB.OwnerOfPlate(plate)
    return MySQL.single.await('SELECT citizenid FROM grand_vehicles WHERE plate = ? LIMIT 1', { plate })
end

function DB.SetVehicleState(plate, state, garage)
    if garage then
        return MySQL.update.await('UPDATE grand_vehicles SET state = ?, garage = ? WHERE plate = ?',
            { state, garage, plate })
    end
    return MySQL.update.await('UPDATE grand_vehicles SET state = ? WHERE plate = ?', { state, plate })
end

-- â”€â”€â”€ Jobs â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function DB.CreateJob(row)
    MySQL.insert.await([[
        INSERT INTO grand_mechanic_jobs
            (job_ref, kind, status, vehicle, plate, model, coords, site, worker, customer, faults,
             estimate, payout, created_at)
        VALUES (?, ?, 'open', ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?)
    ]], {
        row.ref, row.kind, row.vehicle, row.plate or '', row.model or '',
        row.coords or '', row.site or '', row.worker or row.customer or '', row.customer or '',
        json.encode(row.faults or {}), math.floor(row.estimate or 0), math.floor(os.time()),
    })
end

function DB.ClaimJob(ref, workerCid)
    return MySQL.update.await([[
        UPDATE grand_mechanic_jobs
           SET worker = ?, status = 'active', claimed_at = ?
         WHERE job_ref = ? AND status = 'open'
    ]], { workerCid, math.floor(os.time()), ref }) == 1
end

function DB.ReleaseJob(ref)
    return MySQL.update.await(
        "UPDATE grand_mechanic_jobs SET worker = NULL, status = 'open', claimed_at = 0 WHERE job_ref = ?", { ref })
end

function DB.FinishJob(ref, payout)
    return MySQL.update.await([[
        UPDATE grand_mechanic_jobs
           SET status = 'done', payout = ?, finished_at = ?
         WHERE job_ref = ? AND status IN ('active', 'open')
    ]], { math.floor(payout or 0), math.floor(os.time()), ref }) == 1
end

function DB.FailJob(ref, status)
    return MySQL.update.await(
        "UPDATE grand_mechanic_jobs SET status = ?, finished_at = ? WHERE job_ref = ?",
        { status or 'failed', math.floor(os.time()), ref })
end

function DB.OpenJobs(kind, limit)
    return MySQL.rows.await([[
        SELECT * FROM grand_mechanic_jobs
         WHERE status = 'open' AND (? IS NULL OR kind = ?)
         ORDER BY created_at DESC LIMIT ?
    ]], { kind, kind, limit or 40 }) or {}
end

function DB.JobByRef(ref)
    return MySQL.single.await('SELECT * FROM grand_mechanic_jobs WHERE job_ref = ? LIMIT 1', { ref })
end

function DB.ActiveJobForWorker(workerCid)
    return MySQL.single.await([[
        SELECT * FROM grand_mechanic_jobs
         WHERE worker = ? AND status IN ('open', 'active')
         ORDER BY claimed_at DESC LIMIT 1
    ]], { workerCid })
end

function DB.SweepStaleJobs(maxAgeSeconds)
    local cutoff = math.floor(os.time() - (maxAgeSeconds or 1800))
    return MySQL.update.await([[
        UPDATE grand_mechanic_jobs SET status = 'expired'
         WHERE status IN ('open', 'active') AND created_at < ?
    ]], { cutoff })
end

-- â”€â”€â”€ Invoices â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function DB.CreateInvoice(inv)
    MySQL.insert.await([[
        INSERT INTO grand_mechanic_invoices
            (invoice_ref, job_ref, kind, customer_cid, worker_cid, plate, lines,
             labour, parts, tax, total, created_at, expires)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        inv.ref, inv.job or nil, inv.kind, inv.customer or nil, inv.worker or nil, inv.plate or nil,
        json.encode(inv.lines or {}), math.floor(inv.labour or 0), math.floor(inv.parts or 0),
        math.floor(inv.tax or 0), math.floor(inv.total or 0),
        math.floor(os.time()), math.floor(os.time() + (inv.ttl or Config.Timing.invoiceExpiry)),
    })
end

function DB.InvoiceByRef(ref)
    return MySQL.single.await('SELECT * FROM grand_mechanic_invoices WHERE invoice_ref = ? LIMIT 1', { ref })
end

function DB.SettleInvoice(ref, method)
    return MySQL.update.await([[
        UPDATE grand_mechanic_invoices
           SET paid = 1, paid_by = ?, settled_at = ?
         WHERE invoice_ref = ? AND paid = 0
    ]], { method or 'cash', math.floor(os.time()), ref }) == 1
end

function DB.UnpaidInvoices(cid)
    return MySQL.rows.await([[
        SELECT * FROM grand_mechanic_invoices
         WHERE customer_cid = ? AND paid = 0 AND expires > ?
         ORDER BY created_at DESC
    ]], { cid, math.floor(os.time()) }) or {}
end

function DB.OutstandingTotal(cid)
    return MySQL.scalar.await([[
        SELECT COALESCE(SUM(total), 0) FROM grand_mechanic_invoices
         WHERE customer_cid = ? AND paid = 0 AND expires > ?
    ]], { cid, math.floor(os.time()) }) or 0
end

function DB.ExpireInvoices()
    return MySQL.update.await([[
        UPDATE grand_mechanic_invoices SET paid = 0, expires = 0
         WHERE paid = 0 AND expires > 0 AND expires < ?
    ]], { math.floor(os.time()) })
end

function DB.LateInvoiceReport()
    return MySQL.rows.await([[
        SELECT i.invoice_ref, i.total, i.plate, i.kind, c.firstname, c.lastname
          FROM grand_mechanic_invoices i
          LEFT JOIN characters c ON c.citizenid = i.customer_cid
         WHERE i.paid = 0 AND i.expires > 0 AND i.expires < ?
         ORDER BY i.total DESC LIMIT 60
    ]], { math.floor(os.time()) }) or {}
end

-- â”€â”€â”€ Hoarding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function DB.Hoard(row)
    MySQL.insert.await([[
        INSERT INTO grand_hoardings
            (hoard_ref, job_ref, site, plate, model, stored_by, owner_cid, fees, hourly_fee,
             state, stolen, resprayed, new_plate, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        row.ref, row.job or nil, row.site, row.plate, row.model, row.storedBy or nil,
        row.owner or nil, math.floor(row.fees or 0), math.floor(row.hourly or 0),
        row.state or 'impounded', row.stolen and 1 or 0, row.resprayed and 1 or 0,
        row.newPlate or nil, math.floor(os.time()),
    })
end

function DB.HoardForPlate(plate)
    return MySQL.single.await([[
        SELECT * FROM grand_hoardings
         WHERE plate = ? AND state = 'impounded'
         ORDER BY created_at DESC LIMIT 1
    ]], { plate })
end

function DB.HoardForRef(ref)
    return MySQL.single.await('SELECT * FROM grand_hoardings WHERE hoard_ref = ? LIMIT 1', { ref })
end

function DB.ReleaseHoard(ref, paid)
    return MySQL.update.await([[
        UPDATE grand_hoardings
           SET state = 'released', released_at = ?, fees = fees + ?
         WHERE hoard_ref = ? AND state = 'impounded'
    ]], { math.floor(os.time()), math.floor(paid or 0), ref }) == 1
end

function DB.ActiveHoardings(limit)
    return MySQL.rows.await([[
        SELECT h.*, c.firstname, c.lastname
          FROM grand_hoardings h
          LEFT JOIN characters c ON c.citizenid = h.owner_cid
         WHERE h.state = 'impounded'
         ORDER BY h.created_at ASC LIMIT ?
    ]], { limit or 200 }) or {}
end

function DB.AccrueHoardFees()
    return MySQL.update.await([[
        UPDATE grand_hoardings
           SET fees = fees + hourly_fee, hours = hours + 1
         WHERE state = 'impounded' AND hourly_fee > 0 AND created_at < ?
    ]], { math.floor(os.time() - 3600) })
end

function DB.StolenVehicles(limit)
    return MySQL.rows.await([[
        SELECT h.*, c.firstname, c.lastname
          FROM grand_hoardings h
          LEFT JOIN characters c ON c.citizenid = h.stored_by
         WHERE h.state = 'stored' AND h.resprayed = 1
         ORDER BY h.created_at DESC LIMIT ?
    ]], { limit or 60 }) or {}
end

function DB.MarkRespray(ref, newPlate)
    return MySQL.update.await([[
        UPDATE grand_hoardings SET resprayed = 1, new_plate = ?, state = 'stored' WHERE hoard_ref = ?
    ]], { newPlate, ref })
end

-- â”€â”€â”€ Stats â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function DB.Stats(citizenid)
    return MySQL.single.await('SELECT * FROM grand_mechanic_stats WHERE citizenid = ? LIMIT 1', { citizenid })
end

function DB.EnsureStats(citizenid)
    MySQL.query.await(
        'INSERT IGNORE INTO grand_mechanic_stats (citizenid, xp, level, updated_at) VALUES (?, 0, 0, ?)',
        { citizenid, math.floor(os.time()) })
end

function DB.AddXp(citizenid, xp, field, amount)
    DB.EnsureStats(citizenid)
    local allowed = { repairs = 1, tows = 1, jacks = 1, fares = 1, perfect = 1, busted = 1 }
    if not allowed[field] then field = 'repairs' end

    MySQL.update.await(([[
        UPDATE grand_mechanic_stats
           SET xp = xp + ?,
               %s = %s + 1,
               earned = earned + ?,
               updated_at = ?
         WHERE citizenid = ?
    ]]):format(field, field), {
        math.floor(xp or 0),
        math.floor(amount or 0),
        math.floor(os.time()),
        citizenid,
    })

    return DB.Stats(citizenid)
end

function DB.SetLevel(citizenid, level)
    return MySQL.update.await('UPDATE grand_mechanic_stats SET level = ? WHERE citizenid = ?', { level, citizenid })
end

function DB.MarkBusted(citizenid)
    DB.EnsureStats(citizenid)
    return MySQL.update.await(
        'UPDATE grand_mechanic_stats SET busted = busted + 1, updated_at = ? WHERE citizenid = ?',
        { math.floor(os.time()), citizenid })
end

function DB.Leaderboard(field, limit)
    field = field or 'xp'
    local allowed = { xp = 1, repairs = 1, tows = 1, jacks = 1, fares = 1, earned = 1, perfect = 1 }
    if not allowed[field] then field = 'xp' end
    return MySQL.rows.await(([[
        SELECT s.citizenid, s.level, s.xp, s.%s AS score, c.firstname, c.lastname
          FROM grand_mechanic_stats s
          LEFT JOIN characters c ON c.citizenid = s.citizenid
         ORDER BY s.%s DESC LIMIT ?
    ]]):format(field, field), { limit or 25 }) or {}
end

function DB.LogTampering(cid, plate, action, site, wanted)
    MySQL.insert.await([[
        INSERT INTO grand_vehicle_tampering (citizenid, plate, action, site, wanted, created_at)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { cid, plate, action, site or nil, wanted and 1 or 0, math.floor(os.time()) })
end

function DB.TamperingRecent(minutes)
    local cutoff = math.floor(os.time() - (minutes or 15) * 60)
    return MySQL.rows.await([[
        SELECT t.*, c.firstname, c.lastname FROM grand_vehicle_tampering t
          LEFT JOIN characters c ON c.citizenid = t.citizenid
         WHERE t.created_at > ? ORDER BY t.created_at DESC LIMIT 80
    ]], { cutoff }) or {}
end

-- â”€â”€â”€ Helpers to read row JSON without exploding â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
function DB.Decode(raw, fallback)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return fallback or {} end
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == 'table' then return decoded end
    return fallback or {}
end

function DB.CoordsFromString(blob)
    local x, y, z = tostring(blob or ''):match('^([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)$')
    if not x then return nil end
    return vector3(tonumber(x), tonumber(y), tonumber(z))
end

function DB.CoordsToString(v)
    if not v then return '' end
    if type(v) == 'table' then
        return ('%.2f,%.2f,%.2f'):format(v.x or v[1] or 0, v.y or v[2] or 0, v.z or v[3] or 0)
    end
    return ('%.2f,%.2f,%.2f'):format(v.x, v.y, v.z)
end

Shared.DB = DB
return DB
