-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/server/wars.lua
--  THE /attackturf CAPTURE ENGINE.
--  One live war per zone, one 30s presence tick per war.
--  Presence is counted SERVER-SIDE from GetPlayerPed coords -
--  the client never gets a vote. Progress is stored in seconds of
--  net favourable hold time and completes at Config.War.captureSeconds.
-- ─────────────────────────────────────────────────────────────

local Shared = GangsShared
local DB = Database

Wars = Wars or {}
local Wars_ = Wars

-- [zone_id] = live war record
Wars_.Active = {}
Wars_.Sequence = 0

local function tickSeconds()
    return Shared.Clamp((Config.War and Config.War.tickSeconds) or 30, 5, 300)
end

local function captureSeconds()
    return Shared.Clamp((Config.War and Config.War.captureSeconds) or 900, tickSeconds(), 86400)
end

local function requiredTicks()
    return math.max(1, math.ceil(captureSeconds() / tickSeconds()))
end

--- The footprint a war is actually fought inside: never larger than the turf.
function Wars_.ContestRadius(zone)
    if type(zone) ~= 'table' then return 110.0 end
    local cfg = (Config.War and Config.War.contestRadius) or 110.0
    local own = tonumber(zone.contestRadius) or cfg
    return Shared.Clamp(math.min(own, zone.radius or cfg), 40.0, 400.0)
end

-- ─── Presence ────────────────────────────────────────────────
--- Living, online members of `familyId` inside `radius` of the zone centre.
function Wars_.Presence(familyId, centre, radius)
    if type(familyId) ~= 'number' or familyId <= 0 then return 0, {} end
    local members = Turfs.OnlineMembers(familyId)
    local inside = {}
    for i = 1, #members do
        local src = members[i].source
        local ped = GetPlayerPed(src)
        if ped and ped ~= 0 and DoesEntityExist(ped) and not IsEntityDead(ped) then
            local coords = GetEntityCoords(ped)
            if coords and #(coords - centre) <= radius then
                inside[#inside + 1] = {
                    source = src, citizenid = members[i].citizenid,
                    rank = members[i].rank, dist = #(coords - centre),
                }
            end
        end
    end
    return #inside, inside
end

function Wars_.NotifyFamily(familyId, message, kind)
    if type(familyId) ~= 'number' then return end
    local members = Turfs.OnlineMembers(familyId)
    for i = 1, #members do
        Shared.TryExport('grand_core', 'Notify', members[i].source, message, kind or 'info')
    end
end

function Wars_.Broadcast(war, eventName, extra)
    if not war then return end
    local snap = Turfs.Snapshot(war.zoneId)
    if not snap then return end
    snap.contested = true
    snap.war = extra or Wars_.Info(war.zoneId)
    TriggerClientEvent('grand_gangs:client:' .. eventName, -1, snap, extra)
end

-- ─── Lookup / state ──────────────────────────────────────────
function Wars_.IsContested(zoneId)
    if type(zoneId) ~= 'string' then return false end
    local war = Wars_.Active[zoneId:lower()]
    return war ~= nil and war.status == 'live', war
end

function Wars_.Info(zoneId)
    local war = Wars_.Active[type(zoneId) == 'string' and zoneId:lower() or '']
    if not war then return nil end
    return {
        id = war.id, zoneId = war.zoneId, name = war.zoneName,
        attackerFamily = war.attackerFamily, attackerName = war.attackerName, attackerGang = war.attackerGang,
        defenderFamily = war.defenderFamily, defenderName = war.defenderName,
        progress = war.progress, required = war.required,
        requiredTicks = requiredTicks(), percent = war.percent,
        attackerCount = war.attackerCount, defenderCount = war.defenderCount,
        startedAt = war.startedAt, lastTick = war.lastTick,
        secondsLeft = math.max(0, math.ceil((war.required - war.progress) / tickSeconds()) * tickSeconds()),
        status = war.status,
    }
end

function Wars_.ActiveList()
    local out = {}
    for _, war in pairs(Wars_.Active) do
        if war.status == 'live' then out[#out + 1] = Wars_.Info(war.zoneId) end
    end
    table.sort(out, function(a, b) return (a.percent or 0) > (b.percent or 0) end)
    return out
end

function Wars_.WarsOf(familyId)
    local n = 0
    for _, war in pairs(Wars_.Active) do
        if war.status == 'live' and (war.attackerFamily == familyId or war.defenderFamily == familyId) then
            n = n + 1
        end
    end
    return n
end

function Wars_.LiveCount()
    local n = 0
    for _, war in pairs(Wars_.Active) do
        if war.status == 'live' then n = n + 1 end
    end
    return n
end

-- ─── Authorisation ───────────────────────────────────────────
--- Every rule that gates an attack, in one place, reused by the
--- command and the export so neither can drift.
function Wars_.CanAttack(src, zoneId)
    if not Shared.ValidSource(src) then return false, 'invalid source' end
    local zone = Turfs.Raw(zoneId)
    if not zone then return false, 'no such turf' end

    local cid = Shared.TryExport('grand_core', 'GetCitizenId', src)
    cid = Shared.SanitizeCid(cid)
    if not cid then return false, 'identity not loaded' end

    local rateKey = ('war_cmd_%d'):format(src)
    local ready = Shared.Cooldown(rateKey, math.floor(((Config.War.commandRateMs or 5000) / 1000) + 0.5))
    if not ready then return false, Config.Text.rateLimited:format(math.ceil((Config.War.commandRateMs or 5000) / 1000)) end

    local familyId, familyName = Turfs.FamilyOf(cid)
    if type(familyId) ~= 'number' then return false, Config.Text.needFamily end

    local gang = Shared.TryExport('grand_core', 'IsGangMember', src)
    local gangKey = (type(gang) == 'string' and Shared.Gang(gang)) and gang or nil
    local job = Shared.TryExport('grand_core', 'GetJob', src)
    if not gangKey and type(job) == 'table' and job.name and Shared.Gang(job.name) then
        gangKey = job.name
    end
    if not gangKey then
        local faction = Shared.TryExport('grand_core', 'GetFaction', src)
        if type(faction) == 'string' and Shared.Gang(faction) then gangKey = faction end
    end
    if not gangKey then
        gangKey = Turfs.GangOf(cid)
    end
    if not gangKey then return false, Config.Text.needGang end
    local onDuty = Shared.TryExport('grand_core', 'IsOnDuty', src)
    if onDuty == false then return false, Config.Text.needGang end

    if zone.owner == familyId then return false, 'that is already your turf' end
    if not Config.War.neutralCap and not zone.owner then return false, 'neutral turfs are locked' end

    if Wars_.Active[zone.id] then return false, 'a war is already running there' end
    if Wars_.LiveCount() >= (Config.War.maxTotalWars or 6) then return false, 'the city is saturated with wars' end
    if Wars_.WarsOf(familyId) >= (Config.War.maxConcurrentWars or 3) then
        return false, ('your family is already fighting %d wars'):format(Config.War.maxConcurrentWars or 3)
    end

    local cooling = DB.CoolingDown(familyId)
    if cooling > 0 then return false, ('in cooldown for %s'):format(Shared.Duration(cooling)) end

    local stored = DB.WarOnZone(zone.id)
    if stored and stored.attacker_family == familyId and stored.status == 'live' then
        return false, 'your family is already attacking there'
    end

    -- rank gate: only Shot and above may call a war
    local roster = Turfs.FamilyRoster(familyId)
    local myRank = 0
    for i = 1, #roster do
        if roster[i].citizenid == cid then myRank = tonumber(roster[i].rank) or 0 break end
    end
    if myRank < (Config.Ranks.MinAttackRank or 1) then
        return false, ('rank %d cannot start wars'):format(myRank)
    end

    local radius = Wars_.ContestRadius(zone)
    local count, present = Wars_.Presence(familyId, zone.coords, radius)
    if count < (Config.War.minAttackers or 3) then
        return false, Config.Text.notEnough:format(Config.War.minAttackers or 3)
    end

    return true, {
        zone = zone, familyId = familyId, familyName = familyName or ('Family %d'):format(familyId),
        citizenid = cid, gangKey = type(gangKey) == 'string' and gangKey or nil,
        rank = myRank, inside = present, count = count, radius = radius,
    }
end

-- ─── Start ───────────────────────────────────────────────────
function Wars_.Start(src, zoneId)
    local ok, ctx = Wars_.CanAttack(src, zoneId)
    if not ok then
        if Shared.ValidSource(src) then
            Shared.TryExport('grand_core', 'Notify', src,
                Config.Text.denied:format(tostring(zoneId), tostring(ctx)), 'error')
        end
        return false, ctx
    end

    local zone, familyId = ctx.zone, ctx.familyId
    local defenderId = zone.owner
    local required = requiredTicks()

    Wars_.Sequence = Wars_.Sequence + 1
    local war = {
        ref = ('W%d-%d'):format(GetGameTimer(), Wars_.Sequence),
        zoneId = zone.id, zoneName = zone.name,
        attackerFamily = familyId, attackerName = ctx.familyName, attackerGang = ctx.gangKey,
        attackerLead = ctx.citizenid, attackerRank = ctx.rank,
        defenderFamily = defenderId, defenderName = defenderId and zone.ownerName or nil,
        defenderGang = defenderId and zone.ownerGang or nil,
        progress = 0, required = required, percent = 0,
        attackerCount = ctx.count, defenderCount = 0,
        radius = ctx.radius, centre = zone.coords,
        status = 'live',
        startedAt = os.time(), lastTick = os.time(),
        lastAttackerSeen = os.time(),
        ticks = 0, thread = nil, roster = {}, seen = {},
    }

    local rowId = DB.CreateWar({
        zoneId = war.zoneId, attackerFamily = war.attackerFamily, attackerGang = war.attackerGang,
        defenderFamily = war.defenderFamily, defenderGang = war.defenderGang,
        progress = 0, required = required,
    })
    war.id = tonumber(rowId) or war.Sequence
    war.rowId = war.id

    DB.LogAction(zone.id, 'attack', ctx.citizenid, familyId, defenderId, 0,
        ('%s attacks %s with %d'):format(war.attackerName, zone.name, ctx.count))
    DB.EnsureMember(ctx.citizenid, familyId, war.attackerGang, ctx.rank)
    for i = 1, #ctx.inside do
        DB.EnsureMember(ctx.inside[i].citizenid, familyId, war.attackerGang, ctx.inside[i].rank)
        DB.BumpMember(ctx.inside[i].citizenid, 'wars_joined', 1)
    end
    DB.BumpZoneHot(zone.id, 10)

    Wars_.Active[zone.id] = war
    war.progress = tickSeconds()
    Turfs.Broadcast(zone.id)
    Wars_.Broadcast(war, 'WarStart', Wars_.Info(zone.id))
    Wars_.Loop(war)

    Shared.TryExport('grand_core', 'Notify', src, Config.Text.warMine:format(zone.name), 'primary')
    Wars_.NotifyFamily(familyId, Config.Text.warStart:format(war.attackerName, zone.name), 'primary')
    if defenderId then
        Wars_.NotifyFamily(defenderId, Config.Text.warDefend:format(war.attackerName, zone.name), 'error')
    end

    Shared.Log(('war %s: family %d -> turf %s'):format(war.ref, familyId, zone.id))
    return true, war
end

-- ─── Tick ────────────────────────────────────────────────────
local function resolveOutcome(war)
    local a, at = war.attackerCount, war.defenderCount
    local step = tickSeconds()
    if a > at then
        -- attacker presence dominates: they hold the ground
        war.progress = war.progress + step
    elseif at > a then
        -- outnumbered on the turf: the hold collapses
        war.progress = 0
    elseif a == 0 and at == 0 then
        -- nobody fighting: bleed it off
        if Config.War.idleDecay then
            war.progress = math.max(0, war.progress - ((Config.War.decayPerTick or 2) * step))
        end
    end
    war.progress = Shared.Clamp(war.progress, 0, war.required * step)
end

function Wars_.Tick(war)
    if not war or war.status ~= 'live' then return end

    local zone = Turfs.Raw(war.zoneId)
    if not zone then
        Wars_.End(war, 'aborted', nil, 'zone vanished')
        return
    end

    local attackerCount, attackers = Wars_.Presence(war.attackerFamily, war.centre, war.radius)
    local defenderCount = 0
    if war.defenderFamily then
        defenderCount = Wars_.Presence(war.defenderFamily, war.centre, war.radius)
    end

    war.attackerCount, war.defenderCount = attackerCount, defenderCount
    war.ticks = war.ticks + 1
    war.lastTick = os.time()
    if attackerCount > 0 then war.lastAttackerSeen = os.time() end

    resolveOutcome(war)
    war.percent = math.floor((war.progress / math.max(1, war.required * tickSeconds())) * 100)

    local elapsed = os.time() - war.startedAt
    if elapsed > (Config.War.maxWarSeconds or 5400) then
        Wars_.End(war, 'aborted', nil, 'timeout')
        return
    end
    if (os.time() - war.lastAttackerSeen) > (Config.War.forfeitAfterSeconds or 120) then
        Wars_.End(war, 'forfeited', war.defenderFamily, 'attackers gone to ground')
        return
    end

    if war.progress >= (war.required * tickSeconds()) then
        Wars_.Complete(war)
        return
    end

    DB.UpdateWarState(war.rowId, war.progress, attackerCount, defenderCount)
    if war.ticks % 4 == 0 or war.percent >= 75 then
        DB.LogAction(war.zoneId, 'tick', nil, war.attackerFamily, war.defenderFamily, attackerCount,
            ('%d/%d ticks'):format(math.floor(war.progress / tickSeconds()), war.required))
    end
    Wars_.Broadcast(war, 'WarUpdate', Wars_.Info(war.zoneId))

    -- remember everyone who actually showed up, for capture credit
    for i = 1, #attackers do
        local cid = attackers[i].citizenid
        if cid and not war.seen[cid] then
            war.seen[cid] = true
            DB.EnsureMember(cid, war.attackerFamily, war.attackerGang, attackers[i].rank)
            DB.BumpMember(cid, 'wars_joined', 1)
            war.roster[#war.roster + 1] = cid
        end
    end
end

function Wars_.Loop(war)
    CreateThread(function()
        local period = tickSeconds()
        while war and war.status == 'live' do
            local ok, err = pcall(Wars_.Tick, war)
            if not ok then
                Shared.Error('war tick failed', war.zoneId, err)
            end
            Wait(period * 1000)
        end
    end)
end

-- ─── Resolution ──────────────────────────────────────────────
function Wars_.Complete(war)
    if not war or war.status ~= 'live' then return false end
    local zone = Turfs.Raw(war.zoneId)
    local previous = war.defenderFamily

    war.status = 'captured'
    DB.CloseWar(war.rowId, 'captured', war.attackerFamily, 'hold time complete')
    DB.WonWar(war.attackerFamily, war.attackerGang, zone and zone.hourly or 10000, 1)
    if previous then DB.LostWar(previous, zone and zone.ownerGang or nil) end
    DB.SetCooldown(war.attackerFamily, Config.War.cooldownSeconds or 1800)

    for _, cid in ipairs(war.roster or {}) do
        DB.BumpMember(cid, 'wars_won', 1)
        DB.BumpMember(cid, 'captures', 1)
    end

    if zone then
        Turfs.SetOwner(zone.id, war.attackerFamily, war.attackerGang,
            (Shared.Logos and Shared.Logos[war.attackerGang] and Shared.Logos[war.attackerGang].tag) or war.attackerName,
            ('war %s captured'):format(war.ref))
    end
    if previous then
        -- the ousted family loses the turf income line; recount rebuilds it
        DB.ResetFamilyStats(previous)
        Turfs.RecountHourly(previous)
    end

    DB.LogAction(war.zoneId, 'captured', war.attackerLead, war.attackerFamily, previous, 0, war.attackerName)

    if zone then
        Turfs.Broadcast(zone.id)
        local info = { zoneId = zone.id, winner = war.attackerFamily, loser = previous }
        TriggerClientEvent('grand_gangs:client:WarEnd', -1, info)
        if previous then
            Wars_.NotifyFamily(previous, Config.Text.captured:format(zone.name, war.attackerName), 'error')
        end
        Wars_.NotifyFamily(war.attackerFamily, Config.Text.gained:format(zone.name), 'success')
    end

    Shared.Log(('war %s captured by family %d: %s'):format(war.ref, war.attackerFamily, war.zoneId))
    Wars_.Active[war.zoneId] = nil
    return true
end

function Wars_.End(war, status, winner, reason)
    if not war then return false end
    if Wars_.Active[war.zoneId] == war then Wars_.Active[war.zoneId] = nil end
    war.status = status or 'closed'
    DB.CloseWar(war.rowId, war.status, winner, reason)
    DB.LogAction(war.zoneId, war.status, war.attackerLead, war.attackerFamily, war.defenderFamily, 0, reason or '')

    local zone = Turfs.Raw(war.zoneId)
    if zone then
        Turfs.Broadcast(zone.id)
        TriggerClientEvent('grand_gangs:client:WarEnd', -1, {
            zoneId = zone.id, status = war.status, winner = winner, reason = reason,
        })
        if war.status == 'forfeited' then
            DB.SetCooldown(war.attackerFamily, math.floor((Config.War.cooldownSeconds or 1800) * 0.5))
            Wars_.NotifyFamily(war.attackerFamily, Config.Text.forfeit:format(zone.name), 'warning')
            if war.defenderFamily then
                DB.Defended(war.defenderFamily, zone.ownerGang)
                Wars_.NotifyFamily(war.defenderFamily, ('%s held %s'):format(war.defenderName or 'Your family', zone.name), 'success')
            end
        elseif war.status == 'aborted' or war.status == 'yielded' then
            if war.defenderFamily then DB.Defended(war.defenderFamily, zone.ownerGang) end
        end
    end
    Shared.Log(('war %s %s (%s)'):format(war.ref or war.zoneId, war.status, reason or '-'))
    return true
end

--- /turf yield - attacker leadership only, verified server-side.
function Wars_.Yield(src, zoneId)
    if not Shared.ValidSource(src) then return false, 'invalid source' end
    local cid = Shared.SanitizeCid(Shared.TryExport('grand_core', 'GetCitizenId', src))
    if not cid then return false, 'identity not loaded' end

    local war = Wars_.Active[type(zoneId) == 'string' and zoneId:lower() or '']
    if war then
        zoneId = war.zoneId
    else
        local zone = Turfs.ZoneAt(GetEntityCoords(GetPlayerPed(src)) or vector3(0, 0, 0))
        if not zone then return false, Config.Text.noZone end
        war = Wars_.Active[zone.id]
    end
    if not war or war.status ~= 'live' then return false, 'no war on that turf' end

    local familyId = Turfs.FamilyOf(cid)
    if familyId ~= war.attackerFamily then return false, 'that is not your war' end

    local present = Wars_.Presence(familyId, war.centre, war.radius)
    if present > 0 and (os.time() - war.lastAttackerSeen) < 30 then
        -- leaders on the ground may fold immediately; absent ones must wait out a dead war
        local rank = 0
        local roster = Turfs.FamilyRoster(familyId)
        for i = 1, #roster do
            if roster[i].citizenid == cid then rank = tonumber(roster[i].rank) or 0 break end
        end
        if not (Config.Ranks.OfficerRanks[rank] or rank >= (Config.Ranks.LeaderRank or 5)) then
            return false, 'only OG and above may yield a war'
        end
    else
        if (os.time() - war.lastAttackerSeen) < 30 then return false, 'your people are still fighting' end
    end

    return Wars_.End(war, 'yielded', war.defenderFamily, 'yielded by ' .. cid), 'yielded'
end

--- Admin / boot force-end.
function Wars_.ForceEnd(zoneId, actorCid)
    local war = Wars_.Active[type(zoneId) == 'string' and zoneId:lower() or '']
    if not war then return false, 'no live war on that turf' end
    return Wars_.End(war, 'aborted', nil, ('forced by %s'):format(tostring(actorCid or 'admin'))), 'aborted'
end

-- ─── Persistence on restart ──────────────────────────────────
--- Live rows are never resumed silently: a war whose last tick is older
--- than two ticks is stale and must not leave orphaned rows behind.
function Wars_.Resume()
    local rows = DB.LoadOpenWars() or {}
    local stale, live = 0, 0
    local freshness = math.max(180, tickSeconds() * 6)

    for i = 1, #rows do
        local row = rows[i]
        local zone = row and row.zone_id and Turfs.Raw(row.zone_id) or nil
        local lastTick = row and row.last_tick or nil
        local age = 999999
        if lastTick then
            local diff = DB.Scalar('SELECT TIMESTAMPDIFF(SECOND, ?, NOW()) AS d', { lastTick })
            age = tonumber(diff) or 999999
        end

        if not zone or row.attacker_family == nil or age > freshness then
            DB.CloseWar(row.id, 'aborted', nil, 'stale on restart')
            stale = stale + 1
        else
            live = live + 1
            local required = requiredTicks()
            local war = {
                ref = ('R%d'):format(row.id), id = row.id, rowId = row.id,
                zoneId = zone.id, zoneName = zone.name,
                attackerFamily = tonumber(row.attacker_family), attackerName = DB.FamilyName(row.attacker_family),
                attackerGang = row.attacker_gang, attackerLead = nil,
                defenderFamily = tonumber(row.defender_family), defenderName = zone.ownerName,
                defenderGang = zone.ownerGang,
                progress = math.floor((tonumber(row.progress) or 0) / tickSeconds()) * tickSeconds(),
                required = required, percent = 0,
                attackerCount = tonumber(row.attacker_count) or 0, defenderCount = tonumber(row.defender_count) or 0,
                radius = Wars_.ContestRadius(zone), centre = zone.coords,
                status = 'live', startedAt = os.time(), lastTick = os.time(),
                lastAttackerSeen = os.time(), ticks = 0, roster = {}, seen = {},
            }
            war.progress = Shared.Clamp(war.progress, 0, required * tickSeconds())
            war.percent = math.floor((war.progress / (required * tickSeconds())) * 100)
            Wars_.Active[zone.id] = war
            Wars_.Loop(war)
            Turfs.Broadcast(zone.id)
        end
    end

    if stale > 0 then Shared.Log(('cleared %d stale wars on boot'):format(stale)) end
    if live > 0 then Shared.Log(('resumed %d live wars'):format(live)) end
    return live, stale
end

function Wars_.StopAll(reason)
    for _, war in pairs(Wars_.Active) do
        Wars_.End(war, 'aborted', nil, reason or 'resource stop')
    end
    Wars_.Active = {}
end

function Wars_.StatsFor(familyId)
    local held, hourly = 0, 0
    for _, zone in pairs(Turfs.Registry) do
        if zone.owner == familyId then held = held + 1 hourly = hourly + zone.hourly end
    end
    local row = DB.GetStats(familyId)
    return {
        turfs = held, hourly = hourly,
        wars_won = row and tonumber(row.wars_won) or 0,
        wars_lost = row and tonumber(row.wars_lost) or 0,
        captures = row and tonumber(row.captures) or 0,
        defences = row and tonumber(row.defences) or 0,
        kills = row and tonumber(row.kills) or 0,
        income_paid = row and tonumber(row.income_paid) or 0,
        notoriety = row and tonumber(row.notoriety) or 0,
        cooldown = DB.CoolingDown(familyId),
        activeWars = Wars_.WarsOf(familyId),
    }
end

--- Global safety net: nothing may stay live without a thread.
CreateThread(function()
    Wait(45000)
    while true do
        for zoneId, war in pairs(Wars_.Active) do
            if war.status ~= 'live' or not Turfs.Raw(zoneId) then
                Wars_.Active[zoneId] = nil
            elseif (os.time() - (war.lastTick or 0)) > (tickSeconds() * 12) then
                Wars_.End(war, 'aborted', nil, 'watchdog')
            end
        end
        Wait(30000)
    end
end)

return Wars_
