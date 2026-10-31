-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/client/pvp.lua
--  Client half of the red-zone rules:
--    * reports the local player's killer once per death
--    * obeys weapon locks handed down by the server
--    * renders war banners / capture progress as screen text
--  NO NUI.
-- ─────────────────────────────────────────────────────────────

local Shared = GangsShared

GangsClient = GangsClient or {}
local C = GangsClient

C.WeaponLocked = false
C.WeaponLockUntil = 0
C.LastDeathAt = 0
C.ReportedDeath = false
C.WarBanner = nil
C.WarBannerUntil = 0
C.Session = nil

local function now()
    return GetGameTimer()
end

local function chat(prefix, message, colour)
    TriggerEvent('chat:addMessage', {
        color = colour or { 255, 255, 255 },
        multiline = true,
        args = { prefix or 'Turf', tostring(message) },
    })
end

local function notify(message, kind)
    if GetResourceState('ox_lib') == 'started' then
        local ok = pcall(function()
            lib.notify({ description = tostring(message), type = kind or 'inform' })
        end)
        if ok then return end
    end
    chat('Turf', message)
end

-- ─── Session ─────────────────────────────────────────────────
RegisterNetEvent('grand_gangs:client:Session', function(session)
    C.Session = session
    if not session then return end

    if session.gang then
        chat('Gang', ('You are rolling with %s%s'):format(
            tostring(session.gang),
            session.familyName and (' (' .. session.familyName .. ')') or ''), { 200, 160, 255 })
    end
end)

-- ─── Weapon lock ─────────────────────────────────────────────
RegisterNetEvent('grand_gangs:client:WeaponLock', function(seconds, reason)
    C.WeaponLocked = true
    C.WeaponLockUntil = now() + math.floor((tonumber(seconds) or 8) * 1000)
    notify(('Weapons locked for %ss (%s)'):format(
        math.floor(tonumber(seconds) or 8), tostring(reason or 'turf rules')), 'error')
end)

RegisterNetEvent('grand_gangs:client:WeaponUnlock', function()
    C.WeaponLocked = false
    C.WeaponLockUntil = 0
    notify('Weapons free', 'success')
end)

local function lockExpired()
    if not C.WeaponLocked then return true end
    if now() >= C.WeaponLockUntil then
        C.WeaponLocked = false
        return true
    end
    return false
end

-- Enforce the lock locally: drop the weapon if the player tries to
-- fire during the cooldown.
CreateThread(function()
    while true do
        local sleep = 500
        if C.WeaponLocked then
            sleep = 100
            if lockExpired() then
                notify('Weapons free', 'success')
            else
                local ped = PlayerPedId()
                if IsPedArmed(ped, 4) and IsControlPressed(0, 24) then
                    DisableControlAction(0, 24, true)
                    DisableControlAction(0, 257, true)
                    DisablePlayerFiring(PlayerId(), true)
                end
            end
        end
        Wait(sleep)
    end
end)

-- ─── Death reporting ─────────────────────────────────────────
--- Watches for the local player's death, resolves the killer ped to a
--- server id once, and reports it. The server re-verifies everything.
CreateThread(function()
    local wasDead = false

    while true do
        Wait(400)
        local ped = PlayerPedId()
        local dead = IsEntityDead(ped) or IsPedFatallyInjured(ped)

        if dead and not wasDead then
            wasDead = true
            C.ReportedDeath = false
            C.LastDeathAt = now()

            local killerPed = GetPedSourceOfDeath(ped)
            local killerPlayer = killerPed and killerPed ~= 0
                and GetPlayerFromEntity(killerPed) or -1

            if killerPlayer and killerPlayer >= 0 then
                local killerServer = GetPlayerServerId(killerPlayer)
                if killerServer and killerServer > 0 then
                    C.ReportedDeath = true
                    TriggerServerEvent('grand_gangs:server:TurfKill', killerServer)
                    TriggerServerEvent('grand_gangs:server:VictimDown')
                end
            end

            if not C.ReportedDeath then
                notify('You went down. No attacker on record.', 'inform')
            end

        elseif not dead and wasDead then
            wasDead = false
            C.ReportedDeath = false
        end
    end
end)

RegisterNetEvent('grand_gangs:client:KillCredited', function(amount, victim, zoneName)
    notify(('Bounty collected: $%s (%s)'):format(
        tostring(math.floor(tonumber(amount) or 0)), tostring(zoneName or 'turf')), 'success')
    chat('Bounty', ('%s is down. The turf remembers.'):format(tostring(victim or 'Target')),
        { 255, 200, 80 })
end)

RegisterNetEvent('grand_gangs:client:VictimDown', function(citizenid)
    -- Intentionally quiet on other clients: only the attacker and the
    -- victim are told, so no global kill spam.
    if Config.Debug then
        print(('[gangs] victim down: %s'):format(tostring(citizenid)))
    end
end)

-- ─── War banners ─────────────────────────────────────────────
local function banner(title, subtitle, seconds, colour)
    C.WarBanner = { title = title, subtitle = subtitle, colour = colour or { 255, 255, 255 } }
    C.WarBannerUntil = now() + math.floor((tonumber(seconds) or 6) * 1000)
end

RegisterNetEvent('grand_gangs:client:WarStart', function(info)
    if not info then return end
    local mine = C.Session and C.Session.familyId
    if mine and info.attackerFamily == mine then
        banner('TURF WAR', ('Attacking %s'):format(tostring(info.zoneName)), 8, { 255, 120, 80 })
    elseif mine and info.defenderFamily == mine then
        banner('TURF UNDER ATTACK', tostring(info.zoneName), 8, { 255, 60, 60 })
    else
        banner('TURF WAR LIVE', tostring(info.zoneName), 5, { 255, 200, 80 })
    end
end)

RegisterNetEvent('grand_gangs:client:WarState', function(info)
    if not info then return end
    local percent = math.floor(tonumber(info.percent) or 0)
    local label = ('%s - %d%% (%d v %d)'):format(
        tostring(info.zoneName or 'Turf'), percent,
        tonumber(info.attackerCount) or 0, tonumber(info.defenderCount) or 0)

    C.WarBanner = { title = 'TURF WAR', subtitle = label, colour = { 255, 200, 80 } }
    C.WarBannerUntil = now() + 5000
end)

RegisterNetEvent('grand_gangs:client:WarEnd', function(info)
    if not info then return end
    local text
    if info.winnerFamily and info.winnerName then
        text = ('%s took %s'):format(tostring(info.winnerName), tostring(info.zoneName or 'the turf'))
    elseif info.reason then
        text = ('War on %s ended: %s'):format(tostring(info.zoneName or 'turf'), tostring(info.reason))
    else
        text = 'The war is over'
    end
    banner('WAR OVER', text, 7, { 180, 200, 255 })
    chat('Turf', text, { 180, 200, 255 })
end)

RegisterNetEvent('grand_gangs:client:AttackResult', function(ok, reason)
    if ok then
        chat('Turf', 'The attack has begun. Hold the ground.', { 255, 200, 80 })
    else
        chat('Turf', ('Attack refused: %s'):format(tostring(reason or 'unknown')), { 255, 90, 90 })
    end
end)

-- ─── Banner renderer ─────────────────────────────────────────
CreateThread(function()
    while true do
        local sleep = 500
        if C.WarBanner and now() < C.WarBannerUntil then
            sleep = 0
            local banner_ = C.WarBanner
            local colour = banner_.colour or { 255, 255, 255 }
            SetTextScale(0.55, 0.55)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(colour[1], colour[2], colour[3], 235)
            SetTextOutline()
            SetTextCentre(true)
            SetTextEntry('STRING')
            AddTextComponentString(tostring(banner_.title))
            DrawText(0.5, 0.12)

            SetTextScale(0.36, 0.36)
            SetTextColour(235, 235, 235, 230)
            SetTextEntry('STRING')
            AddTextComponentString(tostring(banner_.subtitle or ''))
            DrawText(0.5, 0.155)
        elseif C.WarBanner and now() >= C.WarBannerUntil then
            C.WarBanner = nil
        end
        Wait(sleep)
    end
end)

-- ─── Commands: quick war status ──────────────────────────────
RegisterCommand('warfocus', function()
    if not C.Session then return end
    local mine = C.Session.familyId
    local wars = C.Session.wars or {}
    if #wars == 0 then
        notify('No live wars right now', 'inform')
        return
    end
    for _, war in ipairs(wars) do
        local role = (mine and war.attackerFamily == mine) and 'ATTACKING'
            or (mine and war.defenderFamily == mine) and 'DEFENDING' or 'SPECTATING'
        chat('War', ('%s - %s %d%%'):format(
            tostring(war.zoneName or war.zoneId), role, tonumber(war.percent) or 0))
    end
end, false)

return C
