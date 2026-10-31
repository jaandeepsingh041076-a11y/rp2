-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/server/turfs.lua
--  Turf registry: config zones merged with DB ownership, blip
--  payload building, lookups and the offline-safe income accrual
--  loop. Income ALWAYS lands in the family vault, never a pocket.
-- ─────────────────────────────────────────────────────────────

local Shared = GangsShared
local DB = Database

Turfs = Turfs or {}
local Turfs_ = Turfs

-- [zone_id] = live zone record
Turfs_.Registry = {}
Turfs_.IncomeThreadRunning = false
Turfs_.LastSettle = 0

-- ─── Family helpers (grand_families first, DB fallback second) ──
function Turfs_.FamilyOf(citizenid)
    if type(citizenid) ~= 'string' then return nil end
    local direct = Shared.TryExport('grand_families', 'GetFamilyByCitizenId', citizenid)
    if type(direct) == 'table' then
        return direct.id or direct.familyId, direct.name or direct.label, direct
    end
    if type(direct) == 'number' then
        return direct, DB.FamilyName(direct)
    end
    local row = DB.Single('SELECT family_id FROM grand_family_members WHERE citizenid = ? LIMIT 1', { citizenid })
    if row and row.family_id and row.family_id > 0 then
        return row.family_id, DB.FamilyName(row.family_id)
    end
    local byChar = DB.Single('SELECT family_id FROM characters WHERE citizenid = ? LIMIT 1', { citizenid })
    if byChar and byChar.family_id and byChar.family_id > 0 then
        return byChar.family_id, DB.FamilyName(byChar.family_id)
    end
    return nil
end

function Turfs_.FamilyRoster(familyId)
    if type(familyId) ~= 'number' then return {} end
    local list = Shared.TryExport('grand_families', 'GetFamilyMembers', familyId)
    if type(list) == 'table' and #list > 0 then return list end

    local out = {}
    local rows = DB.Query('SELECT citizenid, rank FROM grand_family_members WHERE family_id = ? AND active = 1', { familyId })
    if rows and #rows > 0 then
        for i = 1, #rows do out[#out + 1] = { citizenid = rows[i].citizenid, rank = rows[i].rank } end
        return out
    end
    rows = DB.Query('SELECT citizenid, family_rank AS rank FROM characters WHERE family_id = ?', { familyId })
    if rows then
        for i = 1, #rows do
            if rows[i].citizenid then out[#out + 1] = { citizenid = rows[i].citizenid, rank = tonumber(rows[i].rank) or 0 } end
        end
    end
    return out
end

--- Every currently-online source belonging to a family.
function Turfs_.OnlineMembers(familyId)
    local roster = Turfs_.FamilyRoster(familyId)
    local sources = {}
    for i = 1, #roster do
        local cid = roster[i].citizenid
        if type(cid) == 'string' then
            local src = Shared.TryExport('grand_core', 'GetSourceByCitizenId', cid)
            src = tonumber(src)
            if src and src > 0 then
                sources[#sources + 1] = { source = src, citizenid = cid, rank = tonumber(roster[i].rank) or 0 }
            end
        end
    end
    return sources
end

function Turfs_.GangOf(citizenid)
    if type(citizenid) ~= 'string' then return nil end
    local row = DB.Single('SELECT job, job_grade FROM characters WHERE citizenid = ?', { citizenid })
    if row and row.job and Shared.Gang(row.job) then
        return row.job, tonumber(row.job_grade) or 0
    end
    local session = Shared.TryExport('grand_core', 'GetCharacter', citizenid)
    if type(session) == 'table' and session.job and Shared.Gang(session.job) then
        return session.job, tonumber(session.job_grade or session.grade) or 0
    end
    return nil
end

-- A gang's configured home turf (used as the fallback owner hint).
local function gangKeyFromZone(zoneId)
    if type(zoneId) ~= 'string' then return nil end
    for key, def in pairs((Config and Config.Gangs) or {}) do
        if def.homeTurf == zoneId then return key end
    end
    return nil
end

-- ─── Registry build ──────────────────────────────────────────
function Turfs_.Build()
    local list = Shared.Zones()
    local rows = DB.LoadZones() or {}
    local byId = {}
    for i = 1, #rows do
        if rows[i] and rows[i].zone_id then byId[rows[i].zone_id] = rows[i] end
    end

    local count = 0
    for i = 1, #list do
        local cfg = list[i]
        if type(cfg.id) == 'string' and cfg.coords then
            local pos = Shared.AsVec(cfg.coords)
            if pos then
                local stored = byId[cfg.id]
                local familyId = stored and tonumber(stored.owner_family_id) or nil
                if type(familyId) ~= 'number' or familyId <= 0 then familyId = nil end
                Turfs_.Registry[cfg.id] = {
                    id = cfg.id,
                    name = cfg.name or cfg.id,
                    tier = tonumber(cfg.tier) or 1,
                    ghetto = cfg.ghetto == true,
                    coords = pos,
                    radius = tonumber(cfg.radius) or 140.0,
                    hourly = Shared.TierIncome(cfg),
                    blip = cfg.blip or {},
                    marker = cfg.marker or {},
                    owner = familyId,
                    ownerGang = stored and stored.owner_gang or nil,
                    ownerName = nil,
                    homeGang = gangKeyFromZone(cfg.id),
                    tag = stored and stored.tag or nil,
                    hot = stored and tonumber(stored.hot_score) or 0,
                    lastPayout = stored and stored.last_payout or nil,
                }
                count = count + 1
                DB.UpsertZone({
                    id = cfg.id, name = cfg.name, tier = cfg.tier, ghetto = cfg.ghetto,
                    radius = cfg.radius, pos = pos,
                })
            end
        end
    end

    -- resolve owner display names once, at boot
    for _, zone in pairs(Turfs_.Registry) do
        if zone.owner then
            zone.ownerName = DB.FamilyName(zone.owner)
            if not zone.ownerGang then
                zone.ownerGang = Turfs_.GangOf(DB.Scalar('SELECT leader_citizenid FROM grand_families WHERE id = ?', { zone.owner }))
            end
        end
    end

    Shared.Log(('turf registry built: %d zones'):format(count))
    return count
end

function Turfs_.All()
    local out = {}
    for _, zone in pairs(Turfs_.Registry) do out[#out + 1] = Turfs_.Snapshot(zone.id) end
    table.sort(out, function(a, b) return tostring(a.id) < tostring(b.id) end)
    return out
end

function Turfs_.Snapshot(zoneId)
    local zone = Turfs_.Registry[type(zoneId) == 'string' and zoneId or '']
    if not zone then return nil end
    local contested, war = Wars.IsContested and Wars.IsContested(zone.id) or false, nil
    if contested then war = Wars.Info and Wars.Info(zone.id) end
    return {
        id = zone.id, name = zone.name, tier = zone.tier, ghetto = zone.ghetto,
        coords = { x = zone.coords.x, y = zone.coords.y, z = zone.coords.z },
        radius = zone.radius, hourly = zone.hourly,
        ownerFamilyId = zone.owner, ownerName = zone.ownerName, ownerGang = zone.ownerGang,
        tag = zone.tag, hot = zone.hot, contested = contested, war = war,
        blip = zone.blip, marker = zone.marker,
    }
end

function Turfs_.OwnerOf(zoneId)
    local zone = Turfs_.Registry[type(zoneId) == 'string' and zoneId or '']
    return zone and zone.owner or nil
end

function Turfs_.ZoneAt(coords)
    local pos = Shared.AsVec(coords)
    if not pos then return nil end
    local best, bestDist
    for _, zone in pairs(Turfs_.Registry) do
        local d = #(pos - zone.coords)
        if d <= zone.radius and (not bestDist or d < bestDist) then
            best, bestDist = zone, d
        end
    end
    if not best then return nil end
    return Turfs_.Snapshot(best.id), bestDist
end

function Turfs_.Raw(zoneId)
    return Turfs_.Registry[type(zoneId) == 'string' and zoneId or '']
end

-- ─── Ownership changes ───────────────────────────────────────
function Turfs_.SetOwner(zoneId, familyId, gangKey, tag, reason)
    local zone = Turfs_.Raw(zoneId)
    if not zone then return false, 'unknown zone' end
    if type(familyId) ~= 'number' or familyId <= 0 then return false, 'invalid family' end

    local previous = zone.owner
    zone.owner = familyId
    zone.ownerGang = gangKey or Turfs_.GangOf(DB.Scalar('SELECT leader_citizenid FROM grand_families WHERE id = ?', { familyId }))
    zone.ownerName = DB.FamilyName(familyId) or ('Family %d'):format(familyId)
    zone.tag = tag or (Shared.Logos and Shared.Logos[zone.ownerGang] and Shared.Logos[zone.ownerGang].tag)
    zone.lastPayout = nil

    DB.SetZoneOwner(zone.id, familyId, zone.ownerGang, zone.tag)
    DB.SyncRootTurf(zone.id, familyId, false, 0)
    DB.LogAction(zone.id, 'capture', nil, familyId, previous, zone.hourly, reason or 'turf war')

    Turfs_.Broadcast(zone.id)
    Turfs_.RecountHourly(familyId)
    if previous then Turfs_.RecountHourly(previous) end
    Shared.Log(('turf %s now owned by family %d (%s)'):format(zone.id, familyId, tostring(zone.ownerName)))
    return true, zone
end

function Turfs_.MakeNeutral(zoneId, reason)
    local zone = Turfs_.Raw(zoneId)
    if not zone then return false, 'unknown zone' end
    local previous = zone.owner
    zone.owner, zone.ownerGang, zone.ownerName, zone.tag = nil, nil, nil, nil
    DB.ClearZoneOwner(zone.id)
    DB.SyncRootTurf(zone.id, nil, false, 0)
    DB.LogAction(zone.id, 'neutral', nil, previous, nil, 0, reason or 'abandoned')
    Turfs_.Broadcast(zone.id)
    if previous then Turfs_.RecountHourly(previous) end
    return true, zone
end

function Turfs_.RecountHourly(familyId)
    if type(familyId) ~= 'number' then return 0 end
    local hourly, held = 0, 0
    for _, zone in pairs(Turfs_.Registry) do
        if zone.owner == familyId then
            hourly = hourly + zone.hourly
            held = held + 1
        end
    end
    DB.EnsureStats(familyId, nil)
    DB.Update([[UPDATE grand_gang_stats SET turfs_held = ?, hourly = ? WHERE family_id = ?]], { held, hourly, familyId })
    return hourly, held
end

-- ─── Blip payload for the map engine ─────────────────────────
--- Everything the client needs to hand grand_mechanic. No NUI.
function Turfs_.BlipPayload(zoneId)
    local zone = Turfs_.Raw(zoneId)
    if not zone then return nil end
    local prefix = (Config.Blips and Config.Blips.prefix) or 'gang_'
    local ownerGang = zone.ownerGang
    local def = Shared.Gang(ownerGang)
    local colour
    if Config.Blips.showOwnerColours and def then
        colour = def.blipColour
    elseif zone.ghetto then
        colour = Shared.ColourNames.contested
    else
        colour = (zone.blip and tonumber(zone.blip.colour)) or Shared.ColourNames.neutral
    end
    if zone.contested then colour = Shared.ColourNames.contested end

    local label = ('%s%s'):format(zone.name, zone.ownerName and (' - ' .. zone.ownerName) or ' - Neutral')
    return {
        id = prefix .. zone.id,
        coords = zone.coords,
        sprite = (zone.blip and tonumber(zone.blip.sprite)) or (Config.Blips.zoneSprite or 84),
        colour = colour,
        scale = Config.Blips.labelScale or 0.82,
        label = label,
        range = Config.Blips.distanceCull or 1400.0,
        short = true,
        hidden = not (Config.Blips.enabled ~= false),
    }
end

function Turfs_.ZonePayload(zoneId)
    local zone = Turfs_.Raw(zoneId)
    if not zone then return nil end
    local prefix = (Config.Blips and Config.Blips.prefix) or 'gang_'
    local rgb = zone.marker and zone.marker.colour or nil
    return {
        id = prefix .. 'z_' .. zone.id,
        group = 'gang_turf',
        coords = zone.coords,
        radius = zone.radius,
        colour = (Turfs_.BlipPayload(zoneId) or {}).colour,
        height = Config.Blips.ringHeight or 30.0,
        label = zone.name,
        pvp = zone.ghetto and true or false,
        rgba = rgb,
        ghetto = zone.ghetto,
    }
end

function Turfs_.AllBlipPayloads()
    local blips, zones = {}, {}
    for id in pairs(Turfs_.Registry) do
        blips[#blips + 1] = Turfs_.BlipPayload(id)
        zones[#zones + 1] = Turfs_.ZonePayload(id)
    end
    return blips, zones
end

--- Push a live map update to every client (owner flip, war start/end).
function Turfs_.Broadcast(zoneId)
    local snap = Turfs_.Snapshot(zoneId)
    if not snap then return end
    snap.contested = Wars.IsContested and Wars.IsContested(zoneId) or false
    local payload = Turfs_.BlipPayload(zoneId)
    TriggerClientEvent('grand_gangs:client:ZoneUpdate', -1, snap, payload)
end

-- ─── Income ──────────────────────────────────────────────────
--- Credit the family vault, honouring the per-family cap and the
--- grand_core transaction ceiling by chunking large payouts.
function Turfs_.PayFamily(familyId, amount, label)
    if type(familyId) ~= 'number' or familyId <= 0 then return 0 end
    local cap = Config.Income.capPerFamily or 90000
    local balance = tonumber(DB.VaultOf(familyId)) or 0
    local payable = math.min(math.floor(math.max(amount or 0, 0)), math.max(cap - balance, 0))
    if payable <= 0 then return 0 end

    local chunkMax = Config.Income.maxTransaction or 48000
    local remaining = payable
    local paid = 0
    local guard = 0
    while remaining > 0 and guard < 64 do
        guard = guard + 1
        local chunk = math.min(remaining, chunkMax)
        local landed, result = Shared.TryExportOk('grand_families', 'AddVault', familyId, chunk, label or 'turf income')
        if not landed or result == nil or result == false then
            -- the vault export is unavailable: fall back to the root column
            local rows = DB.VaultTopUp(familyId, chunk)
            landed = rows and rows > 0
        end
        if not landed then break end
        remaining = remaining - chunk
        paid = paid + chunk
    end
    if paid > 0 then
        DB.AwardIncome(familyId, paid)
        DB.LogAction('all', 'income', nil, familyId, nil, paid, label or 'turf income')
    end
    return paid
end

function Turfs_.SettleZone(zone, reason)
    if not zone or not zone.owner then return 0 end
    local since = nil
    if type(zone.lastPayout) == 'string' then
        since = DB.Scalar('SELECT TIMESTAMPDIFF(SECOND, ?, NOW()) AS s', { zone.lastPayout })
    end
    since = tonumber(since)
    if not since then since = 0 end
    if since <= 0 then return 0 end

    local hours = since / 3600.0
    local gross = Shared.Money(zone.hourly * hours)
    local tax = Config.Income.taxToCity or 0.0
    local net = Shared.Money(gross * (1.0 - Shared.Clamp(tax, 0.0, 0.5)))
    if net <= 0 then return 0 end

    local paid = Turfs_.PayFamily(zone.owner, net, ('turf income: %s'):format(zone.name))
    if paid > 0 then
        zone.lastPayout = DB.Scalar('SELECT NOW() AS n')
        DB.TouchZonePayout(zone.id, zone.hourly)
        DB.LogAction(zone.id, 'payout', nil, zone.owner, nil, paid, reason or 'accrued')
        local members = Turfs_.OnlineMembers(zone.owner)
        for i = 1, #members do
            Shared.TryExport('grand_core', 'Notify', members[i].source,
                Config.Text.income:format(Shared.FormatMoney(paid)), 'success')
        end
    end
    return paid
end

--- Boot-time catch-up: pay out every hour that elapsed while offline.
function Turfs_.SettleOwed()
    if not Config.Income.offlineAccrual then return 0 end
    local total = 0
    for _, zone in pairs(Turfs_.Registry) do
        if zone.owner then
            local rows = DB.Single('SELECT last_payout FROM grand_gang_zones WHERE zone_id = ?', { zone.id })
            zone.lastPayout = rows and rows.last_payout or DB.Scalar('SELECT NOW() AS n')
            total = total + Turfs_.SettleZone(zone, 'offline accrual')
        end
    end
    Turfs_.LastSettle = GetGameTimer()
    if total > 0 then Shared.Log(('offline turf income settled: %s'):format(Shared.FormatMoney(total))) end
    return total
end

--- Steady-state loop. Deliberately a `while true` + Wait so it can
--- never lose its own scheduling.
function Turfs_.StartIncomeLoop()
    if Turfs_.IncomeThreadRunning then return end
    Turfs_.IncomeThreadRunning = true
    local period = Shared.Clamp(Config.Income.payoutSeconds or 3600, 60, 86400)

    CreateThread(function()
        Wait(15000)
        while true do
            local settled = 0
            for _, zone in pairs(Turfs_.Registry) do
                if zone.owner then
                    local rows = DB.Single('SELECT last_payout FROM grand_gang_zones WHERE zone_id = ?', { zone.id })
                    if rows then zone.lastPayout = rows.last_payout end
                    settled = settled + Turfs_.SettleZone(zone, 'hourly loop')
                end
            end
            DB.DecayBounties(Config.PvP.bountyDecay or 0.9, 100)
            Shared.PruneCooldowns()
            Turfs_.LastSettle = GetGameTimer()
            if Config.Debug then Shared.Debug(('income tick done, settled %s'):format(Shared.FormatMoney(settled))) end
            Wait(period * 1000)
        end
    end)
    Shared.Log('turf income loop scheduled')
end

function Turfs_.Boot()
    Turfs_.Build()
    Turfs_.SettleOwed()
    for _, zone in pairs(Turfs_.Registry) do
        Turfs_.RecountHourly(zone.owner)
    end
    Turfs_.StartIncomeLoop()
end

return Turfs_
