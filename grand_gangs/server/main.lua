-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/server/main.lua
--  Commands, client session bootstrap, graffiti tagging and the
--  public exports other resources consume. Loads last: Database,
--  Turfs, Wars and PvP are already global.
-- ─────────────────────────────────────────────────────────────

local Shared = GangsShared
local DB = Database

Gangs = Gangs or {}
local Gangs_ = Gangs

local RESOURCE = GetCurrentResourceName()

-- ─── Small helpers ───────────────────────────────────────────
local function notify(src, message, kind)
    if not Shared.ValidSource(src) then return end
    Shared.TryExport('grand_core', 'Notify', src, tostring(message), kind or 'info')
end

local function citizenOf(src)
    return Shared.TryExport('grand_core', 'GetCitizenId', src)
end

local function isAdmin(src)
    if src == 0 then return true end
    if not Shared.ValidSource(src) then return false end
    for _, ace in ipairs({ Config.Permissions.admin, Config.Permissions.force, Config.Permissions.reset }) do
        if ace and IsPlayerAceAllowed(src, ace) then return true end
    end
    for _, ace in ipairs(Config.Permissions.aceGroups or {}) do
        if IsPlayerAceAllowed(src, ace) then return true end
    end
    return false
end

--- Everything the client needs on join: who am I, what gang, what
--- zone am I standing in, and the live war board.
local function SessionFor(src)
    local cid = citizenOf(src)
    local familyId, familyName = nil, nil
    local gang, rank = nil, 0

    if cid then
        familyId, familyName = Turfs.FamilyOf(cid)
        local job = Shared.TryExport('grand_core', 'GetJob', src)
        if job and job.name then gang = job.name end
        if not gang then
            local member = DB.MemberRow(cid)
            gang = member and member.gang or nil
        end
        if familyId then
            rank = Turfs.RankOf and Turfs.RankOf(familyId, cid) or 0
        end
        DB.EnsureMember(cid, familyId, gang, rank)
    end

    local coords = GetEntityCoords(GetPlayerPed(src))
    local zone = coords and Turfs.ZoneAt(coords) or nil

    local wars = {}
    for _, war in ipairs(Wars.ActiveList()) do
        wars[#wars + 1] = war
    end

    return {
        citizenid = cid,
        familyId = familyId,
        familyName = familyName,
        gang = gang,
        rank = rank,
        zone = zone and zone.id or nil,
        zoneName = zone and zone.name or nil,
        wars = wars,
        bounties = PvP.TopBounties(10),
        config = {
            ghettoOnly = Config.PvP.ghettoOnly,
            bountyPerKill = Config.PvP.bountyPerKill,
            captureSeconds = Config.War.captureSeconds,
            prefix = Config.Blips.prefix,
        },
    }
end

--- Push the full map to one client, or to everyone when src is nil.
local function SyncMap(src)
    local blips, zones = Turfs.AllBlipPayloads()
    if src then
        TriggerClientEvent('grand_gangs:client:SyncMap', src, blips, zones)
    else
        TriggerClientEvent('grand_gangs:client:SyncMap', -1, blips, zones)
    end
end

-- ─── Client bootstrap ────────────────────────────────────────
RegisterNetEvent('grand_gangs:server:ClientReady', function()
    local src = source
    if not Shared.ValidSource(src) then return end
    if not Shared.Cooldown('ready:' .. src, 2) then return end

    -- Wait a beat so grand_core has finished loading the character.
    CreateThread(function()
        Wait(1200)
        if not GetPlayerName(src) then return end
        TriggerClientEvent('grand_gangs:client:Session', src, SessionFor(src))
        SyncMap(src)
    end)
end)

RegisterNetEvent('grand_gangs:server:RequestMap', function()
    local src = source
    if not Shared.ValidSource(src) or not Shared.Cooldown('map:' .. src, 5) then return end
    SyncMap(src)
end)

-- ─── /attackturf ─────────────────────────────────────────────
RegisterCommand(Config.Commands.attack, function(src, args)
    if not Shared.ValidSource(src) then
        print(('usage: %s <zone id>'):format(Config.Commands.attack))
        return
    end
    if not Shared.Cooldown('cmd:attack:' .. src, (Config.War.commandRateMs or 5000) / 1000) then
        notify(src, Config.Text.rateLimited:format((Config.War.commandRateMs or 5000) / 1000), 'warning')
        return
    end

    local zoneId = Shared.SanitizeKey(args[1] or '')
    if zoneId == '' then
        local list = {}
        for _, zone in ipairs(Turfs.All()) do list[#list + 1] = zone.id end
        notify(src, ('Usage: /%s <zone>. Zones: %s'):format(
            Config.Commands.attack, table.concat(list, ', ')), 'info')
        return
    end

    local ok, reason = Wars.Start(src, zoneId)
    if not ok then
        notify(src, tostring(reason), 'error')
        TriggerClientEvent('grand_gangs:client:AttackResult', src, false, reason)
        return
    end

    TriggerClientEvent('grand_gangs:client:AttackResult', src, true, zoneId)
end, false)

-- ─── /turf status|list|yield ─────────────────────────────────
RegisterCommand(Config.Commands.yield, function(src, args)
    if not Shared.ValidSource(src) then return end
    if not Shared.Cooldown('cmd:turf:' .. src, 2) then return end

    local sub = tostring(args[1] or 'status'):lower()

    if sub == 'yield' then
        local ok, reason = Wars.Yield(src, Shared.SanitizeKey(args[2] or ''))
        notify(src, tostring(reason or 'War yielded'), ok and 'warning' or 'error')

    elseif sub == 'list' then
        local rows = Turfs.All()
        notify(src, ('%d turfs on the map:'):format(#rows), 'info')
        for _, zone in ipairs(rows) do
            TriggerClientEvent('chat:addMessage', src, {
                color = { 255, 255, 255 },
                args = { '', ('%s - %s (tier %d, %s/hr)%s'):format(
                    zone.name, zone.ownerName or 'Neutral', zone.tier or 1,
                    Shared.FormatMoney(zone.hourly or 0),
                    zone.contested and ' [WAR]' or '') },
            })
        end

    else
        local cid = citizenOf(src)
        local zoneId = Shared.SanitizeKey(args[2] or '')
        local zone = zoneId ~= '' and Turfs.Raw(zoneId) or nil
        if not zone and cid then
            local coords = GetEntityCoords(GetPlayerPed(src))
            zone = Turfs.ZoneAt(coords)
        end
        if not zone then
            notify(src, Config.Text.noZone, 'info')
            return
        end

        local war = Wars.Info(zone.id)
        if war then
            notify(src, ('WAR: %s%% - attackers %d / defenders %d'):format(
                war.percent or 0, war.attackerCount or 0, war.defenderCount or 0), 'warning')
        else
            notify(src, ('%s: %s, %s/hr'):format(
                zone.name, zone.ownerName or 'Neutral',
                Shared.FormatMoney(zone.hourly or 0)), 'info')
        end
    end
end, false)

-- ─── /turfstats ──────────────────────────────────────────────
RegisterCommand(Config.Commands.stats, function(src)
    if not Shared.ValidSource(src) then return end
    local cid = citizenOf(src)
    if not cid then return end

    local familyId, familyName = Turfs.FamilyOf(cid)
    if not familyId then
        notify(src, Config.Text.needFamily, 'error')
        return
    end

    local stats = Wars.StatsFor(familyId)
    notify(src, ('%s - %d turfs, %s/hr, %d won / %d lost'):format(
        familyName or ('family #' .. familyId),
        stats.turfs or 0, Shared.FormatMoney(stats.hourly or 0),
        stats.wars_won or 0, stats.wars_lost or 0), 'info')
end, false)

-- ─── /turfmap ────────────────────────────────────────────────
RegisterCommand(Config.Commands.map, function(src)
    if not Shared.ValidSource(src) then return end
    if not Shared.Cooldown('cmd:map:' .. src, 5) then return end
    SyncMap(src)
    notify(src, 'Turf map refreshed', 'success')
end, false)

-- ─── /gangadmin ──────────────────────────────────────────────
RegisterCommand(Config.Commands.admin, function(src, args)
    if not isAdmin(src) then
        notify(src, 'Not authorised', 'error')
        return
    end

    local sub = tostring(args[1] or 'help'):lower()

    if sub == 'list' then
        for _, zone in ipairs(Turfs.All()) do
            print(('[gang] %-12s %-22s owner=%s hourly=%s war=%s'):format(
                zone.id, zone.name, tostring(zone.owner or 'none'),
                tostring(zone.hourly or 0), tostring(zone.contested or false)))
        end

    elseif sub == 'end' then
        local zoneId = Shared.SanitizeKey(args[2] or '')
        if zoneId == '' then
            notify(src, 'Usage: /gangadmin end <zone>', 'info')
            return
        end
        Wars.ForceEnd(zoneId, citizenOf(src) or 'admin')
        notify(src, ('War on %s force-ended'):format(zoneId), 'success')

    elseif sub == 'reset' then
        local zoneId = Shared.SanitizeKey(args[2] or '')
        if zoneId == '' then
            notify(src, 'Usage: /gangadmin reset <zone>', 'info')
            return
        end
        Turfs.MakeNeutral(zoneId, 'admin reset')
        notify(src, ('%s is neutral again'):format(zoneId), 'success')

    elseif sub == 'sync' then
        SyncMap(nil)
        notify(src, 'Map synced to all clients', 'success')

    elseif sub == 'bounties' then
        for _, row in ipairs(PvP.TopBounties(15)) do
            print(('[bounty] %s family=%s gang=%s %s'):format(
                row.citizenid, tostring(row.familyId), tostring(row.gang),
                Shared.FormatMoney(row.bounty)))
        end

    else
        notify(src, 'Usage: /gangadmin list | end <zone> | reset <zone> | sync | bounties', 'info')
    end
end, false)

-- ─── Graffiti tagging ────────────────────────────────────────
RegisterNetEvent('grand_gangs:server:GraffitiTag', function(spotId)
    local src = source
    if not Shared.ValidSource(src) then return end

    local spot
    for _, row in ipairs(Config.Graffiti.spots or {}) do
        if row.id == spotId then spot = row break end
    end
    if not spot then return end

    local cid = citizenOf(src)
    if not cid then return end
    if not Shared.Cooldown('tag:' .. src, Config.Graffiti.cooldownSeconds or 900) then
        notify(src, 'That wall is still wet', 'warning')
        return
    end

    local coords = GetEntityCoords(GetPlayerPed(src))
    if #(coords - spot.coords) > (Config.Graffiti.range or 18.0) then
        notify(src, 'Move closer to the wall', 'error')
        return
    end

    local familyId, familyName = Turfs.FamilyOf(cid)
    local gang = Turfs.GangOf(cid)
    if not familyId or not gang then
        notify(src, Config.Text.needGang, 'error')
        return
    end

    local zone = Turfs.ZoneAt(spot.coords)
    local reward = math.floor(Config.Graffiti.reward or 250)
    local paid = Turfs.PayFamily(familyId, reward, ('tag: %s'):format(spot.id))
    DB.BumpMember(cid, 'tags_laid', 1)
    if zone then DB.BumpZoneHot(zone.id, 5) end
    DB.LogAction(zone and zone.id or 'none', 'tag', cid, familyId, nil, paid, ('%s by %s'):format(spot.id, gang))
    TriggerClientEvent('grand_gangs:client:ZoneUpdate', -1,
        zone and Turfs.Snapshot(zone.id) or nil, zone and Turfs.BlipPayload(zone.id) or nil)

    notify(src, ('Tagged %s for %s'):format(spot.id, familyName or 'the family'), 'success')
end)

-- ─── Exports ─────────────────────────────────────────────────
--- The exact export names grand_families / phone / admin consume.
exports('Zones', function()
    return Turfs.All()
end)

exports('OwnerOf', function(zoneId)
    return Turfs.OwnerOf(Shared.SanitizeKey(tostring(zoneId or '')))
end)

exports('ZoneAt', function(coords)
    return Turfs.ZoneAt(coords)
end)

exports('IsContested', function(zoneId)
    return Wars.IsContested(Shared.SanitizeKey(tostring(zoneId or '')))
end)

exports('CanAttack', function(src, zoneId)
    return Wars.CanAttack(tonumber(src), Shared.SanitizeKey(tostring(zoneId or '')))
end)

exports('Attack', function(src, zoneId)
    return Wars.Start(tonumber(src), Shared.SanitizeKey(tostring(zoneId or '')))
end)

exports('FamilyStats', function(familyId)
    return Wars.StatsFor(tonumber(familyId) or 0)
end)

exports('ActiveWars', function()
    return Wars.ActiveList()
end)

exports('GangForCitizen', function(citizenid)
    return Turfs.GangOf(Shared.SanitizeCid(citizenid))
end)

exports('Bounties', function(limit)
    return PvP.TopBounties(limit)
end)

exports('LockWeapon', function(src, seconds, reason)
    return PvP.Lock(tonumber(src), tonumber(seconds) or Config.PvP.weaponCooldownSeconds, reason)
end)

exports('SyncMap', function(src)
    SyncMap(src)
end)

-- ─── Boot ────────────────────────────────────────────────────
AddEventHandler('onResourceStart', function(resource)
    if resource ~= RESOURCE then return end

    CreateThread(function()
        Wait(800)
        local ok = DB.Bootstrap()
        if not ok then
            Shared.Error('schema bootstrap failed - check the database')
        end

        Turfs.Boot()
        Wars.Resume()
        PvP.Boot()

        -- One-shot map sync after everything settled.
        Wait(4000)
        SyncMap(nil)
        Shared.Log(('grand_gangs online - %d zones'):format(#Turfs.All()))
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    Wars.StopAll('resource stop')
    TriggerClientEvent('grand_gangs:client:ClearMap', -1)
end)
