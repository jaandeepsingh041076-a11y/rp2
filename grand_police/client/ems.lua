-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_police/client/ems.lua
--  EMS side: revive handling, death watch, medical call markers
--  and hospital blips. No NUI - markers and chat only.
-- ─────────────────────────────────────────────────────────────

PoliceClient = PoliceClient or {}
local C = PoliceClient

C.IsDead = false
C.LastDeathAt = 0
C.ReviveBlips = {}
C.MedicalCalls = {}

local REVIVE_EVENT = 'grand_police:client:Revive'

-- ─── Revive ──────────────────────────────────────────────────
RegisterNetEvent(REVIVE_EVENT, function()
    -- Resurrection must happen after the death screen has settled.
    CreateThread(function()
        Wait(500)
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, GetEntityHeading(ped), true, true, true)
        Wait(500)
        ped = PlayerPedId()
        SetEntityHealth(ped, 200)
        ClearPedBloodDamage(ped)
        SetPlayerSprint(PlayerId(), true)
        C.IsDead = false
        TriggerEvent('grand_police:client:Revived')
    end)
end)

-- ─── Death watch ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(1000)

        local ped = PlayerPedId()
        local dead = IsEntityDead(ped) or IsPedDeadOrDying(ped, true)

        if dead and not C.IsDead then
            C.IsDead = true
            C.LastDeathAt = GetGameTimer()

            local coords = GetEntityCoords(ped)
            TriggerEvent('chat:addMessage', {
                color = { 255, 80, 80 },
                multiline = true,
                args = { 'EMS', ('You are down at %.1f, %.1f, %.1f. Use /911 <message> for help.'):format(
                    coords.x, coords.y, coords.z) },
            })
        elseif not dead and C.IsDead then
            C.IsDead = false
        end
    end
end)

-- ─── Medical call markers ────────────────────────────────────
RegisterNetEvent('grand_police:client:Dispatch', function(call)
    if not call then return end
    if call.kind ~= 'ems' and call.kind ~= 'panic' then return end
    if not C.IsEMS then return end

    local coords = call.coords
    if type(coords) ~= 'table' or not coords.x then return end

    C.MedicalCalls[#C.MedicalCalls + 1] = {
        id = call.id,
        message = call.message,
        priority = call.priority,
        coords = vector3(coords.x, coords.y, coords.z),
        expire = GetGameTimer() + (Config.Blips.callDuration or 180) * 1000,
    }
end)

-- ─── Medical HUD markers ─────────────────────────────────────
CreateThread(function()
    while true do
        local sleep = 600
        local now = GetGameTimer()

        for index = #C.MedicalCalls, 1, -1 do
            local call = C.MedicalCalls[index]
            if now >= call.expire then
                table.remove(C.MedicalCalls, index)
            else
                local coords = GetEntityCoords(PlayerPedId())
                local distance = #(coords - call.coords)
                if distance < 300.0 then
                    sleep = 0
                    local colour = (tonumber(call.priority) or 2) >= 4 and { 255, 60, 60 } or { 255, 160, 80 }
                    DrawMarker(1, call.coords.x, call.coords.y, call.coords.z - 0.95,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 1.0,
                        colour[1], colour[2], colour[3], 140, false, true, 2, false, nil, nil, false)

                    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(
                        call.coords.x, call.coords.y, call.coords.z + 0.8)
                    if onScreen then
                        SetTextScale(0.30, 0.30)
                        SetTextFont(4)
                        SetTextProportional(1)
                        SetTextColour(colour[1], colour[2], colour[3], 235)
                        SetTextOutline()
                        SetTextEntry('STRING')
                        AddTextComponentString(('MEDICAL CALL: %s'):format(tostring(call.message or '')))
                        DrawText(sx, sy)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ─── Revive the nearest downed player as EMS ─────────────────
RegisterCommand('revivenear', function()
    if not C.IsEMS or not C.OnDuty then
        PoliceUtil.Notify(Config.Text.noDuty, 'error')
        return
    end

    local myCoords = GetEntityCoords(PlayerPedId())
    local mySrc = GetPlayerServerId(PlayerId())
    local closest, closestDistance = nil, 6.0

    for _, playerIndex in ipairs(GetActivePlayers()) do
        local src = GetPlayerServerId(playerIndex)
        if src ~= mySrc then
            local ped = GetPlayerPed(playerIndex)
            if ped ~= 0 and IsEntityDead(ped) then
                local distance = #(myCoords - GetEntityCoords(ped))
                if distance < closestDistance then
                    closest, closestDistance = src, distance
                end
            end
        end
    end

    if not closest then
        PoliceUtil.Notify('No downed player within 6m', 'info')
        return
    end

    TriggerServerEvent('grand_police:server:RequestRevive', closest)
end, false)

-- ─── Hospital hint while down ────────────────────────────────
CreateThread(function()
    Wait(5000)

    local nearest, nearestDistance
    local myCoords = GetEntityCoords(PlayerPedId())

    for _, station in ipairs(Config.Stations) do
        if station.services and station.services.ems then
            local distance = #(myCoords - station.station)
            if not nearestDistance or distance < nearestDistance then
                nearest, nearestDistance = station, distance
            end
        end
    end

    while true do
        Wait(15000)
        if C.IsDead and nearest then
            TriggerEvent('chat:addMessage', {
                color = { 255, 200, 120 },
                args = { 'EMS', ('Nearest hospital: %s'):format(tostring(nearest.label)) },
            })
        end
    end
end)

-- ─── EMS station blips ───────────────────────────────────────
CreateThread(function()
    Wait(4000)
    for _, station in ipairs(Config.Stations) do
        if station.services and station.services.ems then
            local blip = AddBlipForCoord(station.station.x, station.station.y, station.station.z)
            SetBlipSprite(blip, 61)
            SetBlipColour(blip, 1)
            SetBlipScale(blip, 0.8)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(station.label)
            EndTextCommandSetBlipName(blip)
            C.ReviveBlips[#C.ReviveBlips + 1] = blip
        end
    end
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, blip in ipairs(C.ReviveBlips or {}) do
        RemoveBlip(blip)
    end
    C.ReviveBlips = {}
end)

return C
