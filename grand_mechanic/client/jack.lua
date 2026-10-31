-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/jack.lua
--  Hotwire / key-snap flow: proximity, the 42-second window,
--  the alarm roll, and the police tip-off feedback loop.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local Mx = Mechanic.Client

local JackCli = {}
Mechanic.JackCli = JackCli

JackCli.Vehicle = nil
local busy = false

local function ClassLabel(class)
    local _, name = Shared.ClassKey(class)
    return name or 'VEHICLE'
end

-- ─── Find the mark ───────────────────────────────────────────
function JackCli.Target()
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local best, bestDist = 0, 8.0

    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(veh) and veh ~= ped then
            local driver = GetPedInVehicleSeat(veh, -1)
            if driver == 0 or IsPedAPlayer(driver) == false then
                local d = #(pos - GetEntityCoords(veh))
                local lock = GetVehicleDoorLockStatus(veh)
                -- locked cars are harder but worth it; open doors are free
                if d < bestDist and (lock >= 1) then
                    best, bestDist = veh, d
                end
            end
        end
    end
    return best
end

-- ─── The hotwire ─────────────────────────────────────────────
function JackCli.Jack()
    if busy then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        return Mx.Notify('Get out of the car first', 'error')
    end

    local veh = JackCli.Target()
    if veh == 0 then return Mx.Notify('No parked vehicle in reach', 'error') end

    local snap = Mx.Snapshot(veh)
    if snap.plate == '' then return Mx.Notify('No plate to read', 'error') end

    JackCli.Vehicle = veh
    busy = true

    local site = Mechanic.Yard and Mechanic.Yard.SiteAt() or nil
    local noise = 0.0
    local chance = Config.Failure.jackBaseChance + ((Mx.Session.level or 0) * Config.Failure.jackPerLevel)
    if snap.locked == false then chance = chance + 0.15 end
    local class = ClassLabel(snap.class)
    if class == 'SUPER' or class == 'SPORTS' then chance = chance - 0.10 end
    if site and site.kind == 'illegal' then chance = chance + 0.20 end

    chance = Shared.Clamp(chance, 0.08, 0.94)
    Mx.Notify(('%s — %.0f%% chance, %d seconds'):format(snap.plate, chance * 100.0, Config.Timing.jackSeconds), 'info')

    local window = Config.Timing.jackSeconds
    local ped2 = PlayerPedId()

    -- crouch behind it and work the lock
    RequestAnimDict('anim@robbery@car')
    local tries = 0
    while not HasAnimDictLoaded('anim@robbery@car') and tries < 40 do tries = tries + 1 Wait(50) end
    TaskPlayAnim(ped2, 'anim@robbery@car', 'crouch_walk_idle', 3.0, 3.0, -1, 49, 0, false, false, false)

    local finish = GetGameTimer() + (window * 1000)
    local aborted = false
    local alarmPlayed = false

    while GetGameTimer() < finish do
        if not DoesEntityExist(veh) or #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(veh)) > 14.0 then
            aborted = true
            break
        end
        if IsPedInAnyVehicle(PlayerPedId(), false) then aborted = true break end

        -- nearby cops / owners make the window tighter
        for _, player in ipairs(GetActivePlayers()) do
            if player ~= PlayerId() then
                local d = #(GetEntityCoords(PlayerPedId()) - GetEntityCoords(GetPlayerPed(player)))
                if d < 6.0 then noise = noise + 0.00025 end
            end
        end

        local pct = Shared.Clamp(1.0 - ((finish - GetGameTimer()) / (window * 1000)), 0.0, 1.0)
        local width = 0.30
        DrawRect(0.5, 0.90, width, 0.016, 10, 11, 14, 215)
        DrawRect(0.5 - (width / 2) + (width * pct / 2), 0.90, width * pct, 0.016, 255, 30, 56, 235)
        DrawRect(0.5 - (width / 2) + (width * Shared.Clamp(pct + noise, 0, 1) / 2), 0.90,
            width * 0.01, 0.022, 255, 188, 0, 255)

        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(('HOTWIRING %s  %ds  ^1noise %d%%'):format(
            snap.plate, math.ceil((finish - GetGameTimer()) / 1000), math.floor(noise * 100)))
        EndTextCommandDisplayText(0.5, 0.882)

        if not alarmPlayed and pct > 0.35 and math.random() < 0.004 then
            alarmPlayed = true
            TriggerEvent('grand_mechanic:client:JackAlarm', snap.plate)
        end

        Wait(0)
    end

    ClearPedTasks(PlayerPedId())
    busy = false

    if aborted then
        return Mx.Notify('You walked away from it — nothing happened', 'inform')
    end

    TriggerServerEvent('grand_mechanic:server:Jack', {
        netId = Mx.NetId and Mx.NetId(veh) or 0,
        plate = snap.plate,
        model = snap.modelName,
        class = (Shared.ClassKey(snap.class)),
        vehicleClass = snap.class,
        coords = snap.coords,
        locked = snap.locked,
        alarm = alarmPlayed,
        site = site and site.id,
    })

    -- hand it over so the driver seat is usable the instant the server agrees
    SetVehicleDoorsLocked(veh, 1)
    SetVehicleEngineHealth(veh, math.max(400.0, snap.engineHealth))
end

RegisterNetEvent('grand_mechanic:client:JackSuccess', function(data)
    Mx.Notify(('%s started — move it'):format(data.plate), 'success')
    if JackCli.Vehicle and DoesEntityExist(JackCli.Vehicle) then
        TaskWarpPedIntoVehicle(PlayerPedId(), JackCli.Vehicle, -1)
    end
end)

RegisterNetEvent('grand_mechanic:client:JackFailed', function(data)
    Mx.Notify(('%s winned you — the kit jammed'):format(data.plate or 'That car'), 'error')
    ShakeGameViewWeak(0.35, 900)
end)

RegisterNetEvent('grand_mechanic:client:JackDenied', function(reason)
    Mx.Notify(('The job is off: %s'):format(tostring(reason)), 'error')
end)

RegisterNetEvent('grand_mechanic:client:JackAlarm', function(plate)
    Mx.Notify(('Alarm on %s — someone will call it in'):format(plate), 'warning')
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    PlaySoundFrontend(-1, 'Beast_Call_Attention', 'DLC_HEISTS_GENERAL_FRONTEND_SOUNDS', true)
    PlaySoundFrontend(-1, 'Alarm', 'HEIST_FLIPBOARD', true)
    TriggerServerEvent('grand_mechanic:server:BustJack', plate, 'vehicle alarm triggered')
end)

RegisterNetEvent('grand_mechanic:client:PoliceTipoff', function(data)
    Mx.Notify(('LSPD tipped off: %s (%s)'):format(data.plate, data.reason), 'error')
    if data.coords and data.coords.x then
        JackCli.FlashWanted(2, 'Stolen vehicle reported')
    end
end)

function JackCli.FlashWanted(levels, reason)
    SetPlayerWantedLevel(PlayerId(), levels, false)
    SetPlayerWantedLevelNow(PlayerId(), false)
    if reason then
        ShowSubtitle(('~r~%s'):format(reason), 4000)
    end
end

RegisterNetEvent('grand_mechanic:client:StripDone', function(data)
    local lines = { ('^1▚ STRIPPED %s'):format(data.plate) }
    for _, item in ipairs(data.haul or {}) do
        lines[#lines + 1] = ('  + ^7%s'):format(item)
    end
    TriggerEvent('chat:addMessage', { multiline = true, args = lines })
end)

RegisterNetEvent('grand_mechanic:client:ResprayDone', function(data)
    Mx.Notify(('%s → %s'):format(data.old, data.new), 'success')
    if JackCli.Vehicle and DoesEntityExist(JackCli.Vehicle) then
        SetVehicleNumberPlateText(JackCli.Vehicle, data.new)
    end
end)

RegisterNetEvent('grand_mechanic:client:SaleDone', function(data)
    Mx.Notify(('$%s gross, $%s net in crypto'):format(Shared.Money(data.gross), Shared.Money(data.net)), 'success')
    if JackCli.Vehicle and DoesEntityExist(JackCli.Vehicle) then
        local veh = JackCli.Vehicle
        CreateThread(function()
            SetEntityAsMissionEntity(veh, true, true)
            DeleteVehicle(veh)
        end)
    end
    JackCli.Vehicle = nil
end)

RegisterNetEvent('grand_mechanic:client:ChopOpen', function(sites)
    local lines = { '^1▚ UNLISTED WORKSHOPS' }
    for _, s in ipairs(sites or {}) do
        lines[#lines + 1] = ('  ^3%s ^7%s  ^1%d%% yard cut'):format(s.id, s.name, math.floor((s.cut or 0.3) * 100))
    end
    lines[#lines + 1] = '^7/chop strip|respray|sell <plate> <site>'
    TriggerEvent('chat:addMessage', { multiline = true, args = lines })
end)

RegisterCommand('jack', function() JackCli.Jack() end, false, { help = 'Hotwire the nearest parked vehicle' })
RegisterKeyMapping('jack', 'Grand RP: hotwire nearest vehicle', 'keyboard', 'H')

exports('Jack', JackCli.Jack)
exports('Target', JackCli.Target)

return JackCli
