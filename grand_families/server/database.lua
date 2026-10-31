-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/server/database.lua
--  Schema bootstrap, column reconciliation and every query the
--  family layer runs. oxmysql ONLY (`MySQL.*.await`) — the old
--  `exports.oxmysql:fetch(...)` style does not exist.
--
--  Canonical column ownership:
--    root database.sql owns  grand_families(id, name, leader_citizenid,
--        balance, points, rating, level, solar_panels, oil_wells,
--        mansion_coords, created_at)
--    this resource adds, additively and only if missing:
--        tag, color, tax_rate, active_members, total_properties,
--        total_turfs, description, deleted, last_income_at, vault_cap
--  `balance` is the vault (BIGINT). We never fight the root schema.
-- ─────────────────────────────────────────────────────────────

-- Globals inside this resource: shared/util.lua runs first in every
-- context, then these modules attach to the same table.
DB = {}
Families = Families or {}
Families.DB = DB

local RESOURCE = GetCurrentResourceName()

-- ─── Logging ──────────────────────────────────────────────────
local LEVELS = { debug = 3, info = 2, warn = 1, error = 0 }

function DB.Log(level, message)
    if (LEVELS[level] or 2) < (LEVELS[Config.LogLevel] or 2) then return end
    local colour = ({ error = '^1', warn = '^3', info = '^7', debug = '^8' })[level] or '^7'
    print(('%s[%s][db] %s^7'):format(colour, RESOURCE, tostring(message)))
end

-- ─── JSON helpers (money/position/inventory are JSON columns) ──
function DB.Decode(value, fallback)
    if type(value) == 'table' then return value end
    if value == nil or value == '' then return fallback end
    local ok, decoded = pcall(json.decode, tostring(value))
    if ok and type(decoded) == 'table' then return decoded end
    return fallback
end

function DB.Encode(value)
    local ok, encoded = pcall(json.encode, value or {})
    return ok and encoded or '{}'
end

-- ─── Schema bootstrap ─────────────────────────────────────────
-- Loads sql/schema.sql statement-by-statement so one bad statement
-- cannot abort the rest, and so `CREATE TABLE` conflicts with the
-- root database.sql are impossible (everything is IF NOT EXISTS).
function DB.CreateSchema()
    if not Config.Database.AutoCreate then
        DB.Log('info', 'schema auto-create disabled')
        return false
    end

    local ok, schema = pcall(LoadResourceFile, RESOURCE, 'sql/schema.sql')
    if not ok or not schema or schema == '' then
        DB.Log('warn', 'sql/schema.sql not readable - run it manually')
        return false
    end

    local created = 0
    for statement in (schema .. ';'):gmatch('([^;]-)%;') do
        local trimmed = statement:gsub('^%s+', ''):gsub('%s+$', '')
        if trimmed ~= '' and trimmed:upper():find('CREATE') then
            -- strip comment-only lines so the driver sees a clean statement
            local lines = {}
            for line in (trimmed .. '\n'):gmatch('([^\n]-)\n') do
                if not line:match('^%s*%-%-') then lines[#lines + 1] = line end
            end
            local sql = table.concat(lines, ' ')
            if sql:find('CREATE') then
                local callOk, err = pcall(function()
                    return MySQL.query.await(sql)
                end)
                if callOk then
                    created = created + 1
                else
                    DB.Log('warn', ('statement skipped: %s'):format(tostring(err)))
                end
            end
        end
    end

    DB.Log('info', ('schema verified (%d statements ran)'):format(created))
    DB.ReconcileColumns()
    return true
end

--- Adds any column the root database.sql did not create, and never
--- touches a column that already exists. Safe to run on every boot.
function DB.ReconcileColumns()
    local additions = Config.Database.Columns or {}
    for table_, columns in pairs(additions) do
        local have = {}
        local ok, rows = pcall(function()
            return MySQL.query.await(
                'SELECT COLUMN_NAME AS name FROM information_schema.COLUMNS ' ..
                'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?', { table_ })
        end)
        if ok and rows then
            for _, row in ipairs(rows) do
                have[tostring(row.name):lower()] = true
            end
        else
            DB.Log('debug', ('cannot inspect %s - assuming complete'):format(table_))
            return
        end

        for _, column in ipairs(columns) do
            if not have[column.name:lower()] then
                local sql = ('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `%s` %s'):format(
                    table_, column.name, column.definition)
                local alterOk, err = pcall(function()
                    return MySQL.query.await(sql)
                end)
                if alterOk then
                    DB.Log('info', ('%s.%s added'):format(table_, column.name))
                else
                    DB.Log('warn', ('%s.%s not added: %s'):format(table_, column.name, tostring(err)))
                end
            end
        end
    end
end

-- ─── Generic query wrappers (all guarded, all .await) ─────────
function DB.Single(sql, params)
    local ok, row = pcall(MySQL.single.await, sql, params or {})
    if not ok then
        DB.Log('error', ('single failed: %s'):format(tostring(row)))
        return nil
    end
    return row
end

function DB.Rows(sql, params)
    local ok, rows = pcall(MySQL.query.await, sql, params or {})
    if not ok then
        DB.Log('error', ('query failed: %s'):format(tostring(rows)))
        return {}
    end
    return rows or {}
end

function DB.Scalar(sql, params)
    local ok, value = pcall(MySQL.scalar.await, sql, params or {})
    if not ok then
        DB.Log('error', ('scalar failed: %s'):format(tostring(value)))
        return nil
    end
    return value
end

function DB.Insert(sql, params)
    local ok, id = pcall(MySQL.insert.await, sql, params or {})
    if not ok then
        DB.Log('error', ('insert failed: %s'):format(tostring(id)))
        return nil
    end
    return tonumber(id)
end

function DB.Execute(sql, params)
    local ok, affected = pcall(MySQL.update.await, sql, params or {})
    if not ok then
        DB.Log('error', ('update failed: %s'):format(tostring(affected)))
        return 0
    end
    return tonumber(affected) or 0
end

-- ─── Characters (read-only: `characters` belongs to grand_core) ─
function DB.Character(citizenid)
    return DB.Single([[
        SELECT citizenid, identifier, firstname, lastname, level, job, job_grade,
               family_id, family_rank, money, position
          FROM characters WHERE citizenid = ? LIMIT 1
    ]], { citizenid })
end

function DB.CharacterName(citizenid)
    local row = DB.Single('SELECT firstname, lastname FROM characters WHERE citizenid = ? LIMIT 1',
        { citizenid })
    if not row then return 'Unknown' end
    return ('%s %s'):format(row.firstname or '?', row.lastname or '')
end

--- Writes the denormalised family pointer onto the character row so
--- other resources (phone MDT, admin) can join without a round trip.
function DB.SetCharacterFamily(citizenid, familyId, rank)
    return DB.Execute('UPDATE characters SET family_id = ?, family_rank = ? WHERE citizenid = ?',
        { familyId, rank or 0, citizenid })
end

-- ─── Families ─────────────────────────────────────────────────
function DB.CreateFamily(name, leader, tag, colour, startingBalance)
    return DB.Insert([[
        INSERT INTO grand_families (name, leader_citizenid, tag, color, balance,
                                    active_members, total_properties, total_turfs, level)
        VALUES (?, ?, ?, ?, ?, 1, 0, 0, 1)
    ]], { name, leader, tag, colour, math.floor(tonumber(startingBalance) or 0) })
end

function DB.Family(familyId)
    return DB.Single('SELECT * FROM grand_families WHERE id = ? AND deleted = 0 LIMIT 1',
        { tonumber(familyId) })
end

function DB.FamilyByName(name)
    return DB.Single('SELECT * FROM grand_families WHERE name = ? AND deleted = 0 LIMIT 1', { name })
end

function DB.FamilyForCitizen(citizenid)
    return DB.Single([[
        SELECT f.*, m.rank AS member_rank, m.joined_at AS member_joined,
               m.total_deposits, m.total_withdrawals
          FROM grand_family_members m
          JOIN grand_families f ON f.id = m.family_id
         WHERE m.citizenid = ? AND m.active = 1 AND f.deleted = 0
         LIMIT 1
    ]], { citizenid })
end

function DB.ListFamilies(limit)
    local n = math.floor(tonumber(limit) or 50)
    local sql = [[
        SELECT id, name, tag, color, leader_citizenid, balance, level,
               active_members, total_turfs, total_properties, points, rating
          FROM grand_families
         WHERE deleted = 0
         ORDER BY total_turfs DESC, balance DESC
    ]]
    if n > 0 then
        sql = sql .. ' LIMIT ?'
        return DB.Rows(sql, { n })
    end
    return DB.Rows(sql)
end

function DB.UpdateFamilyRow(familyId, column, value)
    local whitelist = {
        name = true, tag = true, color = true, leader_citizenid = true, balance = true,
        tax_rate = true, active_members = true, total_properties = true, total_turfs = true,
        level = true, points = true, rating = true, solar_panels = true, oil_wells = true,
        description = true, deleted = true, vault_cap = true, mansion_coords = true,
        last_income_at = true,
    }
    if not whitelist[column] then
        DB.Log('error', ('refusing to write unlisted column %s'):format(tostring(column)))
        return 0
    end
    return DB.Execute(('UPDATE grand_families SET `%s` = ? WHERE id = ?'):format(column),
        { value, tonumber(familyId) })
end

function DB.RecountMembers(familyId)
    local count = tonumber(DB.Scalar(
        'SELECT COUNT(*) FROM grand_family_members WHERE family_id = ? AND active = 1',
        { tonumber(familyId) })) or 0
    DB.Execute('UPDATE grand_families SET active_members = ? WHERE id = ?', { count, tonumber(familyId) })
    return count
end

function DB.RecountTurfs(familyId)
    local count = tonumber(DB.Scalar(
        'SELECT COUNT(*) FROM grand_family_turfs WHERE family_id = ? AND active = 1',
        { tonumber(familyId) })) or 0
    DB.Execute('UPDATE grand_families SET total_turfs = ? WHERE id = ?', { count, tonumber(familyId) })
    return count
end

function DB.Dissolve(familyId)
    local id = tonumber(familyId)
    DB.Execute('UPDATE grand_family_turfs SET active = 0 WHERE family_id = ?', { id })
    DB.Execute('UPDATE grand_family_properties SET active = 0 WHERE family_id = ?', { id })
    DB.Execute('UPDATE grand_family_members SET active = 0 WHERE family_id = ?', { id })
    DB.Execute('UPDATE grand_turf_wars SET completed = 1, outcome = ? WHERE attacking_family_id = ? AND completed = 0',
        { 'dissolved', id })
    DB.Execute('UPDATE grand_turf_wars SET completed = 1, outcome = ? WHERE defending_family_id = ? AND completed = 0',
        { 'dissolved', id })
    DB.Execute('UPDATE characters SET family_id = NULL, family_rank = 0 WHERE family_id = ?', { id })
    return DB.Execute('UPDATE grand_families SET deleted = 1, active_members = 0, total_turfs = 0 WHERE id = ?', { id })
end

-- ─── Members ──────────────────────────────────────────────────
function DB.AddMember(familyId, citizenid, rank)
    local existing = DB.Single('SELECT id, active FROM grand_family_members WHERE family_id = ? AND citizenid = ? LIMIT 1',
        { tonumber(familyId), citizenid })
    if existing then
        DB.Execute('UPDATE grand_family_members SET active = 1, rank = ?, joined_at = NOW() WHERE id = ?',
            { math.floor(tonumber(rank) or 1), existing.id })
        return existing.id
    end
    return DB.Insert('INSERT INTO grand_family_members (family_id, citizenid, rank) VALUES (?, ?, ?)',
        { tonumber(familyId), citizenid, math.floor(tonumber(rank) or 1) })
end

function DB.LeaveMember(familyId, citizenid)
    return DB.Execute('UPDATE grand_family_members SET active = 0 WHERE family_id = ? AND citizenid = ?',
        { tonumber(familyId), citizenid })
end

function DB.SetRank(familyId, citizenid, rank)
    return DB.Execute('UPDATE grand_family_members SET rank = ? WHERE family_id = ? AND citizenid = ? AND active = 1',
        { math.floor(tonumber(rank) or 1), tonumber(familyId), citizenid })
end

function DB.Membership(familyId, citizenid)
    return DB.Single('SELECT * FROM grand_family_members WHERE family_id = ? AND citizenid = ? AND active = 1 LIMIT 1',
        { tonumber(familyId), citizenid })
end

function DB.Roster(familyId)
    return DB.Rows([[
        SELECT m.citizenid, m.rank, m.joined_at, m.total_deposits, m.total_withdrawals,
               m.kills_in_turf, m.captures_assisted, c.firstname, c.lastname, c.job
          FROM grand_family_members m
          LEFT JOIN characters c ON c.citizenid = m.citizenid
         WHERE m.family_id = ? AND m.active = 1
         ORDER BY m.rank DESC, m.joined_at ASC
    ]], { tonumber(familyId) })
end

function DB.FamilyCitizenIds(familyId)
    return DB.Rows('SELECT citizenid FROM grand_family_members WHERE family_id = ? AND active = 1',
        { tonumber(familyId) })
end

function DB.AddMemberWallet(familyId, citizenid, column, amount)
    if column ~= 'total_deposits' and column ~= 'total_withdrawals'
        and column ~= 'kills_in_turf' and column ~= 'captures_assisted' then return 0 end
    return DB.Execute(('UPDATE grand_family_members SET `%s` = `%s` + ? WHERE family_id = ? AND citizenid = ?'):format(column, column),
        { math.floor(tonumber(amount) or 0), tonumber(familyId), citizenid })
end

-- ─── Vault (the money column is `balance`, per root database.sql) ─
function DB.VaultBalance(familyId)
    return math.floor(tonumber(DB.Scalar('SELECT balance FROM grand_families WHERE id = ? AND deleted = 0 LIMIT 1',
        { tonumber(familyId) })) or 0)
end

--- Atomic vault movement. Reads, clamps, writes and logs in one pass;
--- returns the new balance or nil when the move was refused.
function DB.MoveVault(familyId, amount, transactionType, citizenid, description)
    local id = tonumber(familyId)
    local delta = math.floor(tonumber(amount) or 0)
    if not id or delta == 0 then return nil end

    local row = DB.Single('SELECT balance, vault_cap, deleted FROM grand_families WHERE id = ? LIMIT 1', { id })
    if not row or tonumber(row.deleted) == 1 then return nil end

    local before = math.floor(tonumber(row.balance) or 0)
    local after = before + delta
    if after < 0 then return nil end

    local cap = math.floor(tonumber(row.vault_cap) or 0)
    if cap > 0 and after > cap then
        DB.Log('warn', ('vault %d refused: %d exceeds cap %d'):format(id, after, cap))
        return nil
    end

    local updated = DB.Execute('UPDATE grand_families SET balance = ? WHERE id = ? AND balance = ?',
        { after, id, before })
    if updated < 1 then
        DB.Log('warn', ('vault %d lost a race, refusing duplicate'):format(id))
        return nil
    end

    DB.Insert([[
        INSERT INTO grand_family_vault_logs
            (family_id, citizenid, transaction_type, amount, balance_before, balance_after, description)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    ]], { id, citizenid, transactionType, math.abs(delta), before, after, tostring(description or '') })

    return after, before, delta
end

function DB.VaultHistory(familyId, limit)
    return DB.Rows([[
        SELECT transaction_type, amount, balance_before, balance_after, description, timestamp
          FROM grand_family_vault_logs
         WHERE family_id = ?
         ORDER BY id DESC
         LIMIT ?
    ]], { tonumber(familyId), math.floor(tonumber(limit) or 25) })
end

-- ─── Activity log ─────────────────────────────────────────────
function DB.Activity(familyId, citizenid, actionType, details)
    if not familyId or not actionType then return nil end
    return DB.Insert('INSERT INTO grand_family_logs (family_id, citizenid, action_type, details) VALUES (?, ?, ?, ?)',
        { tonumber(familyId), citizenid, actionType, tostring(details or '') })
end

-- ─── Properties: solar panels + oil wells ─────────────────────
function DB.AddProperty(familyId, propertyType, location, coords, price)
    if propertyType ~= 'solar_panel' and propertyType ~= 'oil_well' then return nil end
    local id = DB.Insert([[
        INSERT INTO grand_family_properties
            (family_id, property_type, location_name, coords_x, coords_y, coords_z, purchase_price, last_payout)
        VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
    ]], {
        tonumber(familyId), propertyType, tostring(location or ''),
        coords and coords.x or 0.0, coords and coords.y or 0.0, coords and coords.z or 0.0,
        math.floor(tonumber(price) or 0),
    })
    if id then
        local column = propertyType == 'solar_panel' and 'solar_panels' or 'oil_wells'
        DB.Execute(('UPDATE grand_families SET `%s` = `%s` + 1, total_properties = total_properties + 1 WHERE id = ?'):format(column, column),
            { tonumber(familyId) })
    end
    return id
end

function DB.Properties(familyId)
    return DB.Rows('SELECT * FROM grand_family_properties WHERE family_id = ? AND active = 1 ORDER BY id ASC',
        { tonumber(familyId) })
end

function DB.CountProperties(familyId, propertyType)
    return tonumber(DB.Scalar(
        'SELECT COUNT(*) FROM grand_family_properties WHERE family_id = ? AND property_type = ? AND active = 1',
        { tonumber(familyId), propertyType })) or 0
end

function DB.SellProperty(propertyId, familyId)
    local row = DB.Single('SELECT property_type FROM grand_family_properties WHERE id = ? AND family_id = ? AND active = 1',
        { tonumber(propertyId), tonumber(familyId) })
    if not row then return false end
    DB.Execute('UPDATE grand_family_properties SET active = 0 WHERE id = ?', { tonumber(propertyId) })
    local column = row.property_type == 'solar_panel' and 'solar_panels' or 'oil_wells'
    DB.Execute(('UPDATE grand_families SET `%s` = GREATEST(`%s` - 1, 0), total_properties = GREATEST(total_properties - 1, 0) WHERE id = ?'):format(column, column),
        { tonumber(familyId) })
    return true
end

--- All active properties for every live family (income loop).
function DB.AllActiveProperties()
    return DB.Rows([[
        SELECT p.id, p.family_id, p.property_type, p.last_payout, f.name
          FROM grand_family_properties p
          JOIN grand_families f ON f.id = p.family_id
         WHERE p.active = 1 AND f.deleted = 0
    ]])
end

function DB.TouchPropertyPayout(propertyId)
    return DB.Execute('UPDATE grand_family_properties SET last_payout = NOW() WHERE id = ?', { tonumber(propertyId) })
end

-- ─── Turf ownership (the authoritative list) ──────────────────
function DB.TurfRows(familyId)
    return DB.Rows('SELECT * FROM grand_family_turfs WHERE family_id = ? AND active = 1 ORDER BY captured_at DESC',
        { tonumber(familyId) })
end

function DB.TurfByName(turfName)
    return DB.Single('SELECT * FROM grand_family_turfs WHERE turf_name = ? AND active = 1 LIMIT 1', { turfName })
end

function DB.OwnsTurf(familyId, turfName)
    local id = tonumber(DB.Scalar(
        'SELECT id FROM grand_family_turfs WHERE turf_name = ? AND family_id = ? AND active = 1 LIMIT 1',
        { turfName, tonumber(familyId) }))
    return id ~= nil
end

function DB.ClaimTurf(familyId, turfName, coords, radius, tier)
    local existing = DB.TurfByName(turfName)
    local id = tonumber(familyId)

    if existing then
        DB.Execute('UPDATE grand_family_turfs SET active = 0 WHERE id = ?', { existing.id })
        DB.RecountTurfs(existing.family_id)
    end

    local inserted = DB.Insert([[
        INSERT INTO grand_family_turfs
            (family_id, turf_name, coords_x, coords_y, coords_z, radius, tier, last_bonus_payout)
        VALUES (?, ?, ?, ?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE family_id = VALUES(family_id), active = 1,
            captured_at = NOW(), coords_x = VALUES(coords_x), coords_y = VALUES(coords_y),
            coords_z = VALUES(coords_z), radius = VALUES(radius), tier = VALUES(tier),
            last_bonus_payout = NOW()
    ]], {
        id, turfName, coords and coords.x or 0.0, coords and coords.y or 0.0,
        coords and coords.z or 0.0, tonumber(radius) or 150.0, math.floor(tonumber(tier) or 1),
    })

    DB.RecountTurfs(id)
    DB.Execute('UPDATE grand_families SET points = points + ? WHERE id = ?',
        { Config.Progress.turfPoints, id })
    return inserted, existing
end

function DB.LoseTurf(turfName, previousFamilyId)
    DB.Execute('UPDATE grand_family_turfs SET active = 0 WHERE turf_name = ?', { turfName })
    if previousFamilyId then
        DB.RecountTurfs(previousFamilyId)
        DB.Execute('UPDATE grand_families SET rating = GREATEST(rating - ?, 0) WHERE id = ?',
            { Config.Progress.ratingLoss, tonumber(previousFamilyId) })
    end
end

function DB.AllOwnedTurfs()
    return DB.Rows([[
        SELECT t.id, t.family_id, t.turf_name, t.coords_x, t.coords_y, t.coords_z,
               t.radius, t.tier, t.last_bonus_payout, f.name AS family_name, f.tag
          FROM grand_family_turfs t
          JOIN grand_families f ON f.id = t.family_id
         WHERE t.active = 1 AND f.deleted = 0
    ]])
end

function DB.TouchTurfPayout(turfId)
    return DB.Execute('UPDATE grand_family_turfs SET last_bonus_payout = NOW() WHERE id = ?', { tonumber(turfId) })
end

-- ─── Turf wars ────────────────────────────────────────────────
function DB.OpenWar(turfName, attackerId, defenderId, members)
    return DB.Insert([[
        INSERT INTO grand_turf_wars (turf_name, attacking_family_id, defending_family_id, attacking_members, progress_percent)
        VALUES (?, ?, ?, ?, 0)
    ]], { turfName, tonumber(attackerId), defenderId and tonumber(defenderId) or nil, DB.Encode(members or {}) })
end

function DB.War(warId)
    return DB.Single('SELECT * FROM grand_turf_wars WHERE id = ? LIMIT 1', { tonumber(warId) })
end

function DB.ActiveWarForTurf(turfName)
    return DB.Single('SELECT * FROM grand_turf_wars WHERE turf_name = ? AND completed = 0 ORDER BY id DESC LIMIT 1',
        { turfName })
end

function DB.ActiveWars()
    return DB.Rows('SELECT * FROM grand_turf_wars WHERE completed = 0')
end

function DB.CountActiveWarsForFamily(familyId)
    local id = tonumber(familyId)
    return tonumber(DB.Scalar(
        'SELECT COUNT(*) FROM grand_turf_wars WHERE completed = 0 AND (attacking_family_id = ? OR defending_family_id = ?)',
        { id, id })) or 0
end

function DB.SetWarProgress(warId, percent, holdingSince)
    return DB.Execute('UPDATE grand_turf_wars SET progress_percent = ?, holding_since = ? WHERE id = ?',
        { math.floor(tonumber(percent) or 0), math.floor(tonumber(holdingSince) or 0), tonumber(warId) })
end

function DB.CloseWar(warId, outcome, winnerFamilyId)
    return DB.Execute([[
        UPDATE grand_turf_wars
           SET completed = 1, outcome = ?, winner_family_id = ?, ended_at = NOW()
         WHERE id = ?
    ]], { tostring(outcome or 'ended'), winnerFamilyId and tonumber(winnerFamilyId) or nil, tonumber(warId) })
end

--- Called on boot: unfinished rows cannot be resumed cleanly, so they
--- are all marked aborted and every turf's under-attack flag is cleared.
function DB.AbandonOrphanWars()
    local closed = DB.Execute("UPDATE grand_turf_wars SET completed = 1, outcome = 'restart_abort' WHERE completed = 0")
    if closed > 0 then DB.Log('info', ('%d orphaned turf wars aborted'):format(closed)) end
    return closed
end

function DB.WarHistory(familyId, limit)
    local id = tonumber(familyId)
    return DB.Rows([[
        SELECT turf_name, outcome, winner_family_id, start_time, ended_at
          FROM grand_turf_wars
         WHERE completed = 1 AND (attacking_family_id = ? OR defending_family_id = ?)
         ORDER BY id DESC LIMIT ?
    ]], { id, id, math.floor(tonumber(limit) or 20) })
end

-- ─── Invitations (server-side pending state, never client-held) ─
function DB.AddInvite(familyId, citizenid, inviter)
    DB.Execute('DELETE FROM grand_family_invites WHERE citizenid = ?', { citizenid })
    return DB.Insert('INSERT INTO grand_family_invites (family_id, citizenid, inviter, created_at) VALUES (?, ?, ?, NOW())',
        { tonumber(familyId), citizenid, tostring(inviter or '') })
end

function DB.HasInvite(familyId, citizenid)
    local row = DB.Single('SELECT * FROM grand_family_invites WHERE family_id = ? AND citizenid = ? LIMIT 1',
        { tonumber(familyId), citizenid })
    if not row then return nil end
    local age = tonumber(DB.Scalar('SELECT TIMESTAMPDIFF(SECOND, created_at, NOW()) FROM grand_family_invites WHERE id = ?',
        { row.id })) or 0
    if age > Config.Invites.ttlSeconds then
        DB.Execute('DELETE FROM grand_family_invites WHERE id = ?', { row.id })
        return nil
    end
    return row
end

function DB.ClearInvite(familyId, citizenid)
    return DB.Execute('DELETE FROM grand_family_invites WHERE family_id = ? AND citizenid = ?',
        { tonumber(familyId), citizenid })
end

function DB.PruneInvites()
    return DB.Execute('DELETE FROM grand_family_invites WHERE created_at < (NOW() - INTERVAL ? SECOND)',
        { Config.Invites.ttlSeconds })
end

-- ─── Exports used by other resources ──────────────────────────
exports('FamilyOf', function(citizenid)
    return citizenid and DB.FamilyForCitizen(tostring(citizenid)) or nil
end)

exports('VaultBalance', function(familyId)
    return DB.VaultBalance(familyId)
end)

exports('RosterOf', function(familyId)
    return DB.Roster(familyId)
end)

exports('TurfsOf', function(familyId)
    return DB.TurfRows(familyId)
end)

exports('AllOwnedTurfs', DB.AllOwnedTurfs)

return DB
