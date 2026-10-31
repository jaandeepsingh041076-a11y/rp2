-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/server/pvp.lua
--  Red-zone PvP enforcement and the bounty economy.
--
--  Nothing here trusts the client. A reported kill is re-verified
--  from server-side coordinates: both players must be online, the
--  victim must be dead (or the kill claimed within the window),
--  the distance must be inside Config.PvP.maxDistanceToVictim, and
--  the ground must be a sanctioned PvP turf.
-- ─────────────────────────────────────────────────────────────

local Shared = GangsShared
local DB = Database

PvP = PvP or {}
local PvP_ = PvP

PvP_.Booted = false
-- [citizenid] = { x, y, z, zone, at }
PvP_.LastKnown = {}

-- ─── Helpers ─────────────────────────────────────────────────
local function enabled()
    return Config.PvP ~= nil
end

local function coordsOf(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function citizenOf(src)
    return Shared.TryExport('grand_core', 'GetCitizenId', src)
end

local function gangOf(src)
    local gang = Shared.TryExport('grand_core', 'IsGangMember', src)
    if type(gang) == 'string' and gang ~= '' then return gang end
    if gang == true then
        local job = Shared.TryExport('grand_core', 'GetJob', src)
        if job and job.name then return job.name end
    end
    return nil
end

local function factionOf(src)
    local faction = Shared.TryExport('grand_core', 'GetFaction', src)
    if type(faction) == 'string' then return faction end
    return nil
end

local function isEmergency(src)
    local faction = factionOf(src)
    return faction ~= nil and (Config.PvP.policeFactions or {})[faction] == true
end

local function familyOf(src)
    local cid = citizenOf(src)
    if not cid then return nil end
    return Turfs.FamilyOf(cid)
end

local function notify(src, message, kind)
    if not Shared.ValidSource(src) then return end
    Shared.TryExport('grand_core', 'Notify', src, tostring(message), kind or 'info')
end

local function zoneAtCoords(coords)
    if not coords then return nil end
    return Turfs.ZoneAt(coords)
end

--- A kill is sanctioned when the ground is a ghetto turf, or a turf
--- currently under war, or the killer is standing on their own turf.
local function sanctioned(zone, killerFamily)
    if not zone then return false end
    if zone.ghetto then return true end
    if Wars.IsContested(zone.id) then return true end
    if killerFamily and zone.owner == killerFamily then return true end
    if not Config.PvP.ghettoOnly then return true end
    return false
end

local function creditCash(src, citizenid, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    local landed = Shared.TryExport('grand_core', 'AddMoney', src, 'cash', amount, reason)
    if landed ~= nil then return true end

    -- fallback: write characters.money JSON directly
    local row = Database.Single('SELECT money FROM characters WHERE citizenid = ? LIMIT 1', { citizenid })
    if not row then return false end
    local money = Shared.DecodeMoney and Shared.DecodeMoney(row.money) or nil
    if not money then
        local ok, decoded = pcall(json.decode, tostring(row.money or '{}'))
        if ok and type(decoded) == 'table' then money = decoded end
    end
    if not money then return false end
    money.cash = math.min((tonumber(money.cash) or 0) + amount, 50000)
    local encoded = json.encode(money)
    return Database.Update('UPDATE characters SET money = ? WHERE citizenid = ?', { encoded, citizenid }) > 0
end

-- ─── Zone tracking ───────────────────────────────────────────
--- Called by client/zones.lua whenever the local player crosses a
--- boundary, and internally whenever a kill is reported.
RegisterNetEvent('grand_gangs:server:ZoneWatch', function(zoneId, entered)
    local src = source
    if not Shared.ValidSource(src) then return end
    if not Shared.Cooldown('zonewatch:' .. src, 1) then return end

    local cid = citizenOf(src)
    if not cid then return end
    local coords = coordsOf(src)
    if not coords then return end

    local zone = zoneAtCoords(coords)
    PvP_.LastKnown[cid] = {
        x = coords.x, y = coords.y, z = coords.z,
        zone = zone and zone.id or nil,
        at = os.time(),
    }

    -- Weapon lock state survives zone changes; just refresh the UI.
    if DB.IsWeaponLocked(cid) then
        TriggerClientEvent('grand_gangs:client:WeaponLock', src,
            Config.PvP.weaponCooldownSeconds or 8, 'turf')
    end
end)

-- ─── Kill reporting ──────────────────────────────────────────
--- Payload from client/pvp.lua: the source the victim believes killed
--- them. Everything is re-derived here.
RegisterNetEvent('grand_gangs:server:TurfKill', function(killerSource)
    local victim = source
    if not Shared.ValidSource(victim) then return end
    if not enabled() then return end
    if not Shared.Cooldown('killreport:' .. victim, 3) then return end

    local killer = tonumber(killerSource)
    if not killer or killer == victim or not Shared.ValidSource(killer) then
        return
    end

    local victimCid = citizenOf(victim)
    local killerCid = citizenOf(killer)
    if not victimCid or not killerCid or victimCid == killerCid then return end

    -- One kill per victim per life, replayed reports are dropped.
    if not Shared.Cooldown('killed:' .. victimCid .. ':' .. killerCid, 20) then
        return
    end

    -- Distance check from server coordinates.
    local victimCoords = coordsOf(victim)
    local killerCoords = coordsOf(killer)
    if not victimCoords or not killerCoords then return end
    local distance = #(victimCoords - killerCoords)
    if distance > (Config.PvP.maxDistanceToVictim or 90.0) then
        Shared.Debug(('kill rejected: distance %.1f'):format(distance))
        return
    end

    local zone = zoneAtCoords(victimCoords) or zoneAtCoords(killerCoords)
    local killerFamily = familyOf(killer)
    if not sanctioned(zone, killerFamily) then
        notify(killer, 'That kill was not in sanctioned turf', 'warning')
        return
    end

    local victimFamily = familyOf(victim)
    local killerGang = gangOf(killer)
    local victimGang = gangOf(victim)

    -- Friendly fire: same family or an ally.
    local sameFamily = killerFamily ~= nil and killerFamily == victimFamily
    local allied = killerGang and victimGang and Shared.IsAlly(killerGang, victimGang)
    if sameFamily or allied then
        local penalty = math.floor(Config.PvP.allyPenalty or 1500)
        DB.AddBounty(killerCid, -penalty)
        DB.LockWeapon(killerCid, Config.PvP.allyLockSeconds or 45)
        DB.BumpMember(killerCid, 'friend_fires', 1)
        DB.LogAction(zone.id, 'friendly_fire', killerCid, killerFamily, victimFamily,
            penalty, 'ally kill')
        TriggerClientEvent('grand_gangs:client:WeaponLock', killer,
            Config.PvP.allyLockSeconds or 45, 'friendly fire')
        notify(killer, Config.Text.friendFire:format(Shared.FormatMoney(penalty)), 'error')
        return
    end

    -- Emergency services are never bounty targets.
    if isEmergency(killer) then
        DB.LogAction(zone.id, 'duty_kill', killerCid, killerFamily, victimFamily, 0, 'emergency kill')
        return
    end

    local bounty = math.floor(Config.PvP.bountyPerKill or 750)
    local cap = math.floor(Config.PvP.maxBounty or 25000)
    local current = tonumber(DB.BountyOf(victimCid)) or 0
    local payout = math.min(bounty + current, cap)
    if payout <= 0 then payout = bounty end

    DB.AddKill(killerCid, killerFamily, payout)
    DB.SetBounty(victimCid, 0)
    DB.BumpMember(victimCid, 'deaths_in_turf', 1)
    if killerFamily then
        DB.EnsureMember(killerCid, killerFamily, killerGang, 0)
        DB.BumpMember(killerCid, 'kills_in_turf', 1)
    end

    local paid = creditCash(killer, killerCid, payout, 'turf bounty')
    DB.LogAction(zone.id, 'kill', killerCid, killerFamily, victimFamily, payout,
        ('%s downed %s at %.0fm'):format(killerCid, victimCid, distance))

    TriggerClientEvent('grand_gangs:client:KillCredited', killer, payout, victimCid,
        zone and zone.name or 'Turf')
    notify(killer, Config.Text.bounty:format(Shared.FormatMoney(payout)), 'success')

    if paid then
        Shared.Log(('bounty %s paid to %s'):format(Shared.FormatMoney(payout), killerCid))
    end
end)

-- ─── Victim notification (client shows the respawn timer) ────
RegisterNetEvent('grand_gangs:server:VictimDown', function()
    local src = source
    if not Shared.ValidSource(src) then return end
    TriggerClientEvent('grand_gangs:client:VictimDown', -1, Shared.TryExport('grand_core', 'GetCitizenId', src))
end)

-- ─── Weapon lock state queries ───────────────────────────────
function PvP_.IsLocked(src)
    local cid = citizenOf(src)
    if not cid then return false end
    return DB.IsWeaponLocked(cid)
end

function PvP_.Lock(src, seconds, reason)
    local cid = citizenOf(src)
    if not cid then return false end
    DB.LockWeapon(cid, seconds)
    TriggerClientEvent('grand_gangs:client:WeaponLock', src, seconds, reason or 'turf')
    return true
end

function PvP_.Release(src)
    local cid = citizenOf(src)
    if not cid then return false end
    DB.ReleaseWeaponLock(cid)
    TriggerClientEvent('grand_gangs:client:WeaponUnlock', src)
    return true
end

-- ─── Leaderboard / bounty board ──────────────────────────────
function PvP_.TopBounties(limit)
    local rows = DB.TopBounties(math.floor(tonumber(limit) or 10))
    local out = {}
    for _, row in ipairs(rows or {}) do
        out[#out + 1] = {
            citizenid = row.citizenid,
            familyId = row.family_id,
            gang = row.gang,
            bounty = tonumber(row.bounty) or 0,
        }
    end
    return out
end

--- Applies the configured decay to every bounty. Called from the
--- turf income loop so it stays in one scheduler.
function PvP_.Decay()
    if not enabled() then return 0 end
    return DB.DecayBounties(Config.PvP.bountyDecay or 0.9, 100)
end

-- ─── Boot ────────────────────────────────────────────────────
function PvP_.Boot()
    if PvP_.Booted then return end
    PvP_.Booted = true

    -- Clear weapon locks left over from a previous session.
    Database.Update('UPDATE grand_gang_members SET weapon_lock_until = NULL WHERE weapon_lock_until IS NOT NULL', {})

    CreateThread(function()
        while true do
            Wait(60000)
            local released = 0
            local rows = Database.Query([[
                SELECT citizenid FROM grand_gang_members
                 WHERE weapon_lock_until IS NOT NULL AND weapon_lock_until <= NOW()
            ]], {})
            for _, row in ipairs(rows or {}) do
                local src = Shared.TryExport('grand_core', 'GetSourceByCitizenId', row.citizenid)
                if src and tonumber(src) then
                    TriggerClientEvent('grand_gangs:client:WeaponUnlock', tonumber(src))
                    released = released + 1
                end
                DB.ReleaseWeaponLock(row.citizenid)
            end
            if released > 0 then
                Shared.Debug(('%d weapon locks expired'):format(released))
            end
        end
    end)
end

return PvP_
