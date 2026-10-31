-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/server/database.lua
--  Schema bootstrap + every SQL statement in the resource.
--  oxmysql MySQL.*.await ONLY - never exports.oxmysql:fetch.
--  `grand_turfs` belongs to the root database.sql: we read and
--  update it, we never CREATE or ALTER it.
-- ─────────────────────────────────────────────────────────────

local Shared = GangsShared

Database = Database or {}
local DB = Database

DB.Ready = false
DB.Failures = 0

-- ─── Additive tables (all IF NOT EXISTS, all ours) ───────────
-- Column names avoid Lua keyword collisions: ends_at / expires_at.
DB.Schema = {
    [[CREATE TABLE IF NOT EXISTS `grand_gang_zones` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_gang_wars` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_gang_members` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_turf_actions` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],

    [[CREATE TABLE IF NOT EXISTS `grand_gang_stats` (
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
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci]],
}

function DB.Bootstrap()
    for i = 1, #DB.Schema do
        local ok, err = pcall(function()
            return MySQL.query.await(DB.Schema[i])
        end)
        if not ok then
            DB.Failures = DB.Failures + 1
            Shared.Error('schema bootstrap failed:', err)
        end
    end
    DB.Ready = true
    Shared.Log('schema ready (' .. #DB.Schema .. ' additive tables)')
    return DB.Ready
end

-- ─── Low-level wrappers (all awaited, all pcall-guarded) ─────
function DB.Single(sql, params)
    local ok, res = pcall(function()
        return MySQL.single.await(sql, params or {})
    end)
    if not ok then
        DB.Failures = DB.Failures + 1
        Shared.Error('MySQL.single.await failed:', res, sql:sub(1, 90))
        return nil
    end
    return res
end

function DB.Query(sql, params)
    local ok, res = pcall(function()
        return MySQL.query.await(sql, params or {})
    end)
    if not ok then
        DB.Failures = DB.Failures + 1
        Shared.Error('MySQL.query.await failed:', res, sql:sub(1, 90))
        return nil
    end
    return res or {}
end

function DB.Update(sql, params)
    local ok, res = pcall(function()
        return MySQL.update.await(sql, params or {})
    end)
    if not ok then
        DB.Failures = DB.Failures + 1
        Shared.Error('MySQL.update.await failed:', res, sql:sub(1, 90))
        return 0
    end
    return res or 0
end

function DB.Insert(sql, params)
    local ok, res = pcall(function()
        return MySQL.insert.await(sql, params or {})
    end)
    if not ok then
        DB.Failures = DB.Failures + 1
        Shared.Error('MySQL.insert.await failed:', res, sql:sub(1, 90))
        return nil
    end
    return res
end

function DB.Scalar(sql, params)
    local row = DB.Single(sql, params)
    if not row then return nil end
    for _, v in pairs(row) do return v end
    return nil
end

-- ─── Zones ───────────────────────────────────────────────────
function DB.LoadZones()
    return DB.Query('SELECT * FROM grand_gang_zones')
end

function DB.UpsertZone(z)
    return DB.Update([[INSERT INTO grand_gang_zones
        (zone_id, name, tier, ghetto, radius, pos_x, pos_y, pos_z, hourly_reward, last_payout)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
            name = VALUES(name), tier = VALUES(tier), ghetto = VALUES(ghetto),
            radius = VALUES(radius), pos_x = VALUES(pos_x), pos_y = VALUES(pos_y),
            pos_z = VALUES(pos_z), hourly_reward = VALUES(hourly_reward)]], {
        z.id, Shared.SanitizeText(z.name, 64) or z.id,
        Shared.Clamp(tonumber(z.tier) or 1, 1, 3),
        z.ghetto and 1 or 0,
        tonumber(z.radius) or 120.0,
        z.pos.x, z.pos.y, z.pos.z,
        Shared.TierIncome(z),
    })
end

function DB.SetZoneOwner(zoneId, familyId, gang, tag)
    return DB.Update([[UPDATE grand_gang_zones
        SET owner_family_id = ?, owner_gang = ?, tag = ?, captured_total = captured_total + 1
        WHERE zone_id = ?]], {
        familyId, gang, Shared.SanitizeText(tag, 16), zoneId,
    })
end

function DB.ClearZoneOwner(zoneId)
    return DB.Update('UPDATE grand_gang_zones SET owner_family_id = NULL, owner_gang = NULL, tag = NULL WHERE zone_id = ?', { zoneId })
end

function DB.TouchZonePayout(zoneId, hours)
    return DB.Update([[UPDATE grand_gang_zones
        SET last_payout = NOW(), hourly_reward = ?
        WHERE zone_id = ? AND owner_family_id IS NOT NULL]], { math.floor(hours or 0), zoneId })
end

function DB.BumpZoneHot(zoneId, amount)
    return DB.Update('UPDATE grand_gang_zones SET hot_score = hot_score + ? WHERE zone_id = ?', {
        math.floor(Shared.Clamp(amount or 1, -1000, 1000)), zoneId,
    })
end

function DB.CountZoneWins(zoneId)
    return DB.Scalar('SELECT captured_total FROM grand_gang_zones WHERE zone_id = ?', { zoneId })
end

-- Mirrors the ownership row into root `grand_turfs` (best effort only).
function DB.SyncRootTurf(zoneId, familyId, underAttack, endsInMinutes)
    local ok = pcall(function()
        MySQL.update.await([[UPDATE grand_turfs
            SET owner_family_id = ?, under_attack = ?, attack_ends = DATE_ADD(NOW(), INTERVAL ? MINUTE)
            WHERE zone_name = ?]], {
            familyId, underAttack and 1 or 0, math.floor(endsInMinutes or 0), zoneId,
        })
    end)
    return ok
end

-- ─── Wars ────────────────────────────────────────────────────
function DB.CreateWar(w)
    return DB.Insert([[INSERT INTO grand_gang_wars
        (zone_id, attacker_family, attacker_gang, defender_family, defender_gang,
         progress, required, status, last_tick)
        VALUES (?, ?, ?, ?, ?, ?, ?, 'live', NOW())]], {
        w.zoneId, w.attackerFamily, w.attackerGang,
        w.defenderFamily, w.defenderGang,
        math.floor(Shared.Clamp(w.progress or 0, 0, 100000)), math.floor(w.required or 30),
    })
end

function DB.UpdateWarState(id, progress, attackerCount, defenderCount)
    return DB.Update([[UPDATE grand_gang_wars
        SET progress = ?, attacker_count = ?, defender_count = ?, last_tick = NOW()
        WHERE id = ?]], {
        math.floor(progress or 0), math.floor(attackerCount or 0), math.floor(defenderCount or 0), id,
    })
end

function DB.CloseWar(id, status, winnerFamily, reason)
    return DB.Update([[UPDATE grand_gang_wars
        SET status = ?, winner_family = ?, reason = ?, ends_at = NOW(),
            attacker_count = 0, defender_count = 0
        WHERE id = ?]], {
        Shared.SanitizeText(status, 16) or 'closed', winnerFamily,
        Shared.SanitizeText(reason, 64), id,
    })
end

function DB.LoadOpenWars()
    return DB.Query("SELECT * FROM grand_gang_wars WHERE status = 'live' ORDER BY id ASC")
end

function DB.AbandonUnfinished(reason)
    return DB.Update([[UPDATE grand_gang_wars
        SET status = 'aborted', reason = ?, ends_at = NOW()
        WHERE status = 'live' OR status = 'paused']], {
        Shared.SanitizeText(reason, 64) or 'restart',
    })
end

function DB.WarOnZone(zoneId)
    return DB.Single([[SELECT * FROM grand_gang_wars
        WHERE zone_id = ? AND status = 'live'
        ORDER BY id DESC LIMIT 1]], { zoneId })
end

-- ─── Members ─────────────────────────────────────────────────
function DB.MemberRow(citizenid)
    return DB.Single('SELECT * FROM grand_gang_members WHERE citizenid = ?', { citizenid })
end

function DB.EnsureMember(citizenid, familyId, gang, rank)
    return DB.Update([[INSERT INTO grand_gang_members (citizenid, family_id, gang, rank, last_seen)
        VALUES (?, ?, ?, ?, NOW())
        ON DUPLICATE KEY UPDATE
            family_id = VALUES(family_id), gang = VALUES(gang),
            rank = VALUES(rank), last_seen = NOW()]], {
        citizenid, familyId, gang, math.floor(Shared.Clamp(rank or 0, 0, 5)),
    })
end

function DB.BumpMember(citizenid, column, amount)
    local allowed = {
        kills_in_turf = true, deaths_in_turf = true, assists_in_turf = true,
        wars_joined = true, wars_won = true, captures = true, friend_fires = true, tags_laid = true,
    }
    if not allowed[column] then return 0 end
    return DB.Update(('UPDATE grand_gang_members SET %s = %s + ? WHERE citizenid = ?'):format(column, column), {
        math.floor(Shared.Clamp(amount or 1, -1000, 1000)), citizenid,
    })
end

function DB.SetBounty(citizenid, amount)
    return DB.Update('UPDATE grand_gang_members SET bounty = ? WHERE citizenid = ?', {
        math.floor(Shared.Clamp(amount or 0, 0, Config.PvP.maxBounty or 25000)), citizenid,
    })
end

function DB.AddBounty(citizenid, amount)
    return DB.Update([[UPDATE grand_gang_members
        SET bounty = LEAST(bounty + ?, ?) WHERE citizenid = ?]], {
        math.floor(amount or 0), math.floor(Config.PvP.maxBounty or 25000), citizenid,
    })
end

function DB.BountyOf(citizenid)
    return DB.Scalar('SELECT bounty FROM grand_gang_members WHERE citizenid = ?', { citizenid })
end

function DB.LockWeapon(citizenid, seconds)
    return DB.Update('UPDATE grand_gang_members SET weapon_lock_until = DATE_ADD(NOW(), INTERVAL ? SECOND) WHERE citizenid = ?', {
        math.floor(Shared.Clamp(seconds or 0, 0, 3600)), citizenid,
    })
end

function DB.ReleaseWeaponLock(citizenid)
    return DB.Update('UPDATE grand_gang_members SET weapon_lock_until = NULL WHERE citizenid = ?', { citizenid })
end

function DB.IsWeaponLocked(citizenid)
    local row = DB.Single('SELECT weapon_lock_until FROM grand_gang_members WHERE citizenid = ?', { citizenid })
    if not row or not row.weapon_lock_until then return false end
    return DB.Scalar('SELECT NOW() < ? AS still', { row.weapon_lock_until }) and true or false
end

function DB.DecayBounties(rate, floorValue)
    return DB.Update([[UPDATE grand_gang_members
        SET bounty = GREATEST(FLOOR(bounty * ?), ?)
        WHERE bounty > ?]], {
        Shared.Clamp(rate or 0.9, 0.1, 1.0), math.floor(floorValue or 0), math.floor(floorValue or 0),
    })
end

function DB.FamilyMembers(citizenids, familyId)
    local list = citizenids or {}
    if #list == 0 then return {} end
    local marks = {}
    local params = {}
    for i = 1, #list do
        marks[i] = '?'
        params[i] = list[i]
    end
    params[#params + 1] = familyId
    return DB.Query('SELECT * FROM grand_gang_members WHERE citizenid IN ('
        .. table.concat(marks, ',') .. ') AND family_id = ?', params)
end

function DB.TopBounties(limit)
    return DB.Query([[SELECT citizenid, gang, bounty, kills_in_turf FROM grand_gang_members
        WHERE bounty > 0 ORDER BY bounty DESC LIMIT ?]], {
        math.floor(Shared.Clamp(limit or 10, 1, 50)),
    })
end

function DB.ResetFamilyStats(familyId)
    return DB.Update('UPDATE grand_gang_stats SET turfs_held = 0, hourly = 0 WHERE family_id = ?', { familyId })
end

-- ─── Stats ───────────────────────────────────────────────────
function DB.EnsureStats(familyId, gang)
    return DB.Update([[INSERT INTO grand_gang_stats (family_id, gang) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE gang = COALESCE(gang, VALUES(gang))]], { familyId, gang })
end

function DB.GetStats(familyId)
    return DB.Single('SELECT * FROM grand_gang_stats WHERE family_id = ?', { familyId })
end

function DB.WonWar(familyId, gang, hourly, captures)
    DB.EnsureStats(familyId, gang)
    return DB.Update([[UPDATE grand_gang_stats
        SET wars_won = wars_won + 1, captures = captures + 1,
            turfs_held = turfs_held + 1, hourly = hourly + ?, notoriety = notoriety + 5
        WHERE family_id = ?]], { math.floor(hourly or 0), familyId })
end

function DB.LostWar(familyId, gang)
    if not familyId then return 0 end
    DB.EnsureStats(familyId, gang)
    return DB.Update([[UPDATE grand_gang_stats
        SET wars_lost = wars_lost + 1, turfs_held = GREATEST(turfs_held - 1, 0),
            hourly = GREATEST(hourly - ?, 0), notoriety = notoriety + 2
        WHERE family_id = ?]], { math.floor(10000), familyId })
end

function DB.Defended(familyId, gang)
    if not familyId then return 0 end
    DB.EnsureStats(familyId, gang)
    return DB.Update('UPDATE grand_gang_stats SET defences = defences + 1 WHERE family_id = ?', { familyId })
end

function DB.AddKill(citizenid, familyId, amount)
    if familyId then DB.EnsureStats(familyId, nil) end
    return DB.Update('UPDATE grand_gang_stats SET kills = kills + 1 WHERE family_id = ?', { familyId })
end

function DB.AwardIncome(familyId, amount)
    DB.EnsureStats(familyId, nil)
    return DB.Update('UPDATE grand_gang_stats SET income_paid = income_paid + ? WHERE family_id = ?', {
        math.floor(Shared.Clamp(amount or 0, 0, 10000000)), familyId,
    })
end

function DB.SetCooldown(familyId, seconds)
    return DB.Update('UPDATE grand_gang_stats SET cooldown_until = DATE_ADD(NOW(), INTERVAL ? SECOND) WHERE family_id = ?', {
        math.floor(Shared.Clamp(seconds or 0, 0, 86400)), familyId,
    })
end

function DB.CoolingDown(familyId)
    local row = DB.Single([[SELECT TIMESTAMPDIFF(SECOND, NOW(), cooldown_until) AS left
        FROM grand_gang_stats WHERE family_id = ?]], { familyId })
    if not row then return 0 end
    return math.max(0, tonumber(row.left) or 0)
end

function DB.AllStats()
    return DB.Query('SELECT * FROM grand_gang_stats ORDER BY hourly DESC')
end

-- ─── Action log ──────────────────────────────────────────────
function DB.LogAction(zoneId, action, cid, attackerFamily, defenderFamily, amount, detail)
    return DB.Insert([[INSERT INTO grand_turf_actions
        (zone_id, action, actor_citizenid, attacker_family, defender_family, amount, detail)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        Shared.SanitizeText(zoneId, 32) or 'unknown',
        Shared.SanitizeText(action, 24) or 'note',
        Shared.SanitizeCid(cid),
        Shared.ValidInt(attackerFamily, 0, 1000000),
        Shared.ValidInt(defenderFamily, 0, 1000000),
        math.floor(Shared.Clamp(amount or 0, -10000000, 10000000)),
        Shared.SanitizeText(detail, 190),
    })
end

function DB.RecentActions(zoneId, limit)
    return DB.Query([[SELECT * FROM grand_turf_actions
        WHERE zone_id = ? ORDER BY created_at DESC LIMIT ?]], {
        zoneId, math.floor(Shared.Clamp(limit or 20, 1, 100)),
    })
end

function DB.KillLogIn(windowSeconds, victimCid)
    return DB.Query([[SELECT * FROM grand_turf_actions
        WHERE action = 'kill' AND created_at > DATE_SUB(NOW(), INTERVAL ? SECOND)
          AND (actor_citizenid = ? OR detail LIKE ?)
        ORDER BY created_at DESC LIMIT 8]], {
        math.floor(Shared.Clamp(windowSeconds or 60, 10, 86400)),
        victimCid, ('%%%s%%'):format(tostring(victimCid or '')),
    })
end

-- ─── Family vault fallback (grand_families.balance exists in root schema)
function DB.VaultTopUp(familyId, amount)
    return DB.Update('UPDATE grand_families SET balance = balance + ? WHERE id = ?', {
        math.floor(amount or 0), familyId,
    })
end

function DB.VaultOf(familyId)
    return DB.Scalar('SELECT balance FROM grand_families WHERE id = ?', { familyId })
end

function DB.FamilyName(familyId)
    return DB.Scalar('SELECT name FROM grand_families WHERE id = ?', { familyId })
end

function DB.OwnerOf(zoneId)
    return DB.Scalar('SELECT owner_family_id FROM grand_gang_zones WHERE zone_id = ?', { zoneId })
end

return DB
