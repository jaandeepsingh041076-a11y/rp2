-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_dealership/client/garage.lua
--  Owned-vehicle garage: blips, forecourt markers, /garage
--  list|spawn|store|move. Chat and markers only - NO NUI.
--
--  Loads before client/sales.lua; both files share DealerClient.
-- ─────────────────────────────────────────────────────────────

DealerClient = DealerClient or {}
local C = DealerClient

C.GarageBlips = {}
C.GarageBlipsBuilt = false
C.GarageVehicles = {}
C.GarageVehicle = nil
C.GarageVehiclePlate = nil
C.SpawnPending = false

local PREFIX = Config.Blips.prefix or 'dealer_'
local COLOURS = {
    crimson = 1, green = 2, blue = 3, gold = 4, orange = 9, red = 1,
    purple = 5, teal = 6, pink = 8, yellow = 66, sky = 52, emerald = 25,
    grey = 26, white = 0, black = 29, sapphire = 52,
}

-- ─── Blip engine (GrandBlips with a raw fallback) ────────────
local function engine(name, ...)
    if GetResourceState('grand_mechanic') ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports['grand_mechanic'][name](table.unpack(args, 1, args.n))
    end)
    return ok and result or nil
end

local function colourOf(value)
    if type(value) == 'number' then return value end
    if type(value) == 'string' then return COLOURS[value:lower()] or 26 end
    return 26
end

local function addBlip(record)
    local id = engine('AddBlip', {
        id = record.id,
        coords = record.coords,
        sprite = record.sprite or 357,
        colour = record.colour or 'grey',
        scale = record.scale or 0.7,
        label = record.label,
        range = Config.Blips.distanceCull or 1400.0,
    })

    if id then
        C.GarageBlips[record.id] = { id = id, engine = true }
        return id
    end

    local handle = AddBlipForCoord(record.coords.x, record.coords.y, record.coords.z)
    SetBlipSprite(handle, record.sprite or 357)
    SetBlipColour(handle, colourOf(record.colour))
    SetBlipScale(handle, record.scale or 0.7)
    SetBlipAsShortRange(handle, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(tostring(record.label))
    EndTextCommandSetBlipName(handle)

    C.GarageBlips[record.id] = { handle = handle, engine = false }
    return handle
end

local function clearGarageBlips()
    for key, entry in pairs(C.GarageBlips) do
        if entry.engine then
            engine('RemoveBlip', entry.id)
        elseif type(entry.handle) == 'number' then
            RemoveBlip(entry.handle)
        end
        C.GarageBlips[key] = nil
    end
    C.GarageBlipsBuilt = false
end

local function buildGarageBlips()
    if C.GarageBlipsBuilt then return end
    if not Config.Blips.enabled or Config.Blips.showGarages == false then return end
    C.GarageBlipsBuilt = true

    for _, garage in ipairs(Config.Garages) do
        local blip = garage.blip or {}
        addBlip({
            id = PREFIX .. 'garage_' .. garage.id,
            coords = garage.coords,
            sprite = blip.sprite or 357,
            colour = blip.colour or 'grey',
            scale = blip.scale or 0.7,
            label = garage.name,
        })
    end
end

-- ─── Chat helpers ────────────────────────────────────────────
local function chat(title, text, colour)
    TriggerEvent('chat:addMessage', {
        color = colour or { 255, 200, 90 },
        multiline = true,
        args = { title or 'Garage', tostring(text or '') },
    })
end

local function notify(message, kind)
    DealerShared.Notify(message, kind)
end

local function trimPlate(text)
    return (tostring(text or ''):gsub('^%s+', ''):gsub('%s+$', '')):upper()
end

-- ─── Location helpers ────────────────────────────────────────
local function nearestGarage()
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDistance = nil, math.huge

    for _, garage in ipairs(Config.Garages) do
        local distance = #(coords - garage.coords)
        if distance < bestDistance then
            best, bestDistance = garage, distance
        end
    end

    return best, bestDistance
end

local function garageName(id)
    local garage = DealerShared.Garage(id)
    return garage and garage.name or tostring(id or '?')
end

local function findLocalVehicleByPlate(plate)
    plate = trimPlate(plate)
    if plate == '' then return 0 end

    if C.GarageVehicle and DoesEntityExist(C.GarageVehicle) then
        if trimPlate(GetVehicleNumberPlateText(C.GarageVehicle)) == plate then
            return C.GarageVehicle
        end
    end

    for _, vehicle in ipairs(GetGamePool('CVehicle')) do
        if DoesEntityExist(vehicle) and trimPlate(GetVehicleNumberPlateText(vehicle)) == plate then
            return vehicle
        end
    end
    return 0
end

-- ─── Props: capture ──────────────────────────────────────────
local function captureProps(vehicle)
    local props = {
        plate = trimPlate(GetVehicleNumberPlateText(vehicle)),
        tyreHealth = {},
        mods = {},
    }

    -- Optional getters are guarded so a missing native never breaks a store.
    if GetVehicleFuelLevel then props.fuel = math.floor(GetVehicleFuelLevel(vehicle) + 0.5) end
    if GetVehicleBodyHealth then props.bodyHealth = GetVehicleBodyHealth(vehicle) end
    if GetVehicleEngineHealth then props.engineHealth = GetVehicleEngineHealth(vehicle) end
    if GetVehiclePetrolTankHealth then props.petrolTankHealth = GetVehiclePetrolTankHealth(vehicle) end

    local primary, secondary = GetVehicleColours(vehicle)
    props.primaryColour = primary
    props.secondaryColour = secondary

    local pearlescent = GetVehicleExtraColours(vehicle)
    props.pearlescentColour = pearlescent
    props.windowTints = GetVehicleWindowTint(vehicle)

    for modType = 0, 49 do
        local modIndex = GetVehicleMod(vehicle, modType)
        if modIndex and modIndex >= 0 then props.mods[modType] = modIndex end
    end

    local r, g, b = GetVehicleNeonLightsColour(vehicle)
    props.neon = {
        r = r or 0, g = g or 0, b = b or 0,
        enabled = IsVehicleNeonLightEnabled(vehicle, 0) == true,
    }

    return props
end

-- ─── Props: apply ────────────────────────────────────────────
local function applyProps(vehicle, props, plate, fuel)
    if type(props) ~= 'table' then props = {} end

    SetVehicleNumberPlateText(vehicle, trimPlate(plate))
    SetVehicleModKit(vehicle, 0)

    if props.primaryColour then
        SetVehicleColours(vehicle, tonumber(props.primaryColour) or 0,
            tonumber(props.secondaryColour) or tonumber(props.primaryColour) or 0)
    end
    if props.pearlescentColour then
        SetVehicleExtraColours(vehicle, tonumber(props.pearlescentColour) or 0, 0)
    end
    if props.windowTints then
        SetVehicleWindowTint(vehicle, tonumber(props.windowTints) or 0)
    end

    for modType, modIndex in pairs(props.mods or {}) do
        local slot = tonumber(modType)
        local index = tonumber(modIndex)
        if slot and index and slot >= 0 and slot <= 49 and index >= 0 then
            SetVehicleMod(vehicle, slot, index, false)
        end
    end

    SetVehicleBodyHealth(vehicle, tonumber(props.bodyHealth) or 1000.0)
    SetVehicleEngineHealth(vehicle, tonumber(props.engineHealth) or 1000.0)
    SetVehiclePetrolTankHealth(vehicle, tonumber(props.petrolTankHealth) or 1000.0)

    local level = tonumber(fuel) or tonumber(props.fuel) or 100
    if SetVehicleFuelLevel then
        SetVehicleFuelLevel(vehicle, math.max(0, math.min(100, level)))
    end

    local neon = props.neon
    if type(neon) == 'table' then
        SetVehicleNeonLightsColour(vehicle, tonumber(neon.r) or 0,
            tonumber(neon.g) or 0, tonumber(neon.b) or 0)
        for light = 0, 3 do
            SetVehicleNeonLightEnabled(vehicle, light, neon.enabled == true)
        end
    end

    pcall(function()
        Entity(vehicle).state:set('plate', trimPlate(plate), true)
        Entity(vehicle).state:set('fuel', level, true)
    end)
end

-- ─── Store ───────────────────────────────────────────────────
local function storeVehicle()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)

    if not vehicle or vehicle == 0 then
        notify('Get in the vehicle you want to store first', 'warning')
        return
    end

    local garage, distance = nearestGarage()
    if not garage or distance > (garage.radius or 28.0) then
        notify('You are not inside a garage bay', 'error')
        return
    end

    if GetPedInVehicleSeat(vehicle, -1) ~= ped then
        notify('Only the driver can store this vehicle', 'warning')
        return
    end

    local plate = trimPlate(GetVehicleNumberPlateText(vehicle))
    if plate == '' then
        notify('That vehicle has no readable plate', 'error')
        return
    end

    TriggerServerEvent('grand_dealership:server:GarageStore', plate, captureProps(vehicle))
end

-- ─── Net events ──────────────────────────────────────────────
RegisterNetEvent('grand_dealership:client:GarageList', function(vehicles)
    C.GarageVehicles = type(vehicles) == 'table' and vehicles or {}

    if #C.GarageVehicles == 0 then
        chat('Garage', 'Your garage is empty.', { 255, 180, 120 })
        return
    end

    local lines = {}
    for _, row in ipairs(C.GarageVehicles) do
        local status = 'unknown'
        if row.stored then status = 'stored'
        elseif row.out then status = 'OUT'
        elseif row.impounded then status = 'SEIZED' end

        lines[#lines + 1] = ('%-9s %-16s %-7s %-18s%s'):format(
            tostring(row.plate), tostring(row.model), status,
            garageName(row.garage), row.finance == true and ' [finance]' or '')
    end

    chat(('Your vehicles (%d)'):format(#C.GarageVehicles), table.concat(lines, '\n'),
        { 210, 220, 240 })
    chat('Garage', ('/%s spawn <plate> | /%s store | /%s move <plate> <garage_id> | /%s garages'):format(
        Config.Commands.garage, Config.Commands.garage,
        Config.Commands.garage, Config.Commands.garage), { 120, 220, 140 })
end)

RegisterNetEvent('grand_dealership:client:SpawnVehicle', function(payload)
    if type(payload) ~= 'table' or not payload.model or not payload.plate then return end

    if C.SpawnPending then
        notify('A vehicle is already being released', 'warning')
        return
    end
    C.SpawnPending = true

    CreateThread(function()
        local model = tostring(payload.model)
        local hash = GetHashKey(model)

        if not IsModelInCdimage(hash) then
            C.SpawnPending = false
            TriggerServerEvent('grand_dealership:server:SpawnFailed', payload.plate)
            notify('That vehicle model is not available on this server', 'error')
            return
        end

        RequestModel(hash)
        local deadline = GetGameTimer() + 10000
        while not HasModelLoaded(hash) do
            if GetGameTimer() > deadline then
                C.SpawnPending = false
                TriggerServerEvent('grand_dealership:server:SpawnFailed', payload.plate)
                notify('The vehicle model failed to load', 'error')
                return
            end
            Wait(100)
        end

        local spawn = payload.spawn
        if type(spawn) ~= 'table' or not spawn.x then
            spawn = vector4(215.0, -791.0, 30.7, 160.0)
        end

        local vehicle = CreateVehicle(hash, spawn.x, spawn.y, spawn.z,
            tonumber(spawn.w) or 0.0, true, false)
        if not vehicle or vehicle == 0 then
            C.SpawnPending = false
            SetModelAsNoLongerNeeded(hash)
            TriggerServerEvent('grand_dealership:server:SpawnFailed', payload.plate)
            notify('There was no room to release the vehicle', 'error')
            return
        end

        SetEntityAsMissionEntity(vehicle, true, true)
        applyProps(vehicle, payload.props, payload.plate, payload.fuel)
        SetVehicleOnGroundProperly(vehicle)
        SetVehicleEngineOn(vehicle, true, true, false)
        SetVehicleDirtLevel(vehicle, 0.0)
        SetModelAsNoLongerNeeded(hash)

        C.GarageVehicle = vehicle
        C.GarageVehiclePlate = trimPlate(payload.plate)
        C.SpawnPending = false

        SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
        notify(('%s (%s) released'):format(model, tostring(payload.plate)), 'success')
    end)
end)

RegisterNetEvent('grand_dealership:client:VehicleStored', function(plate)
    local vehicle = findLocalVehicleByPlate(plate)
    if vehicle ~= 0 then
        SetEntityAsMissionEntity(vehicle, true, true)
        DeleteVehicle(vehicle)
    end
    C.GarageVehicle = nil
    C.GarageVehiclePlate = nil
end)

-- ─── Command ─────────────────────────────────────────────────
RegisterCommand(Config.Commands.garage, function(_, args)
    local sub = tostring(args[1] or ''):lower()

    if sub == '' then
        local ped = PlayerPedId()
        local vehicle = GetVehiclePedIsIn(ped, false)
        local garage, distance = nearestGarage()

        if vehicle ~= 0 and garage and distance <= (garage.radius or 28.0) then
            storeVehicle()
        else
            TriggerServerEvent('grand_dealership:server:RequestGarage')
        end
        return
    end

    if sub == 'list' then
        TriggerServerEvent('grand_dealership:server:RequestGarage')
        return
    end

    if sub == 'spawn' or sub == 'take' or sub == 'out' then
        local plate = args[2]
        if not plate then
            notify(('usage: /%s spawn <plate>'):format(Config.Commands.garage), 'info')
            return
        end
        TriggerServerEvent('grand_dealership:server:GarageSpawn', plate)
        return
    end

    if sub == 'store' then
        storeVehicle()
        return
    end

    if sub == 'move' then
        if not args[2] or not args[3] then
            notify(('usage: /%s move <plate> <garage_id>'):format(Config.Commands.garage), 'info')
            return
        end
        TriggerServerEvent('grand_dealership:server:GarageMove', args[2], args[3])
        return
    end

    if sub == 'garages' then
        local lines = {}
        for _, garage in ipairs(Config.Garages) do
            lines[#lines + 1] = ('%-14s %s'):format(tostring(garage.id), tostring(garage.name))
        end
        chat('Garage locations', table.concat(lines, '\n'), { 210, 220, 240 })
        return
    end

    notify(('usage: /%s [list | spawn <plate> | store | move <plate> <garage_id> | garages]'):format(
        Config.Commands.garage), 'info')
end, false)

-- ─── Garage markers ──────────────────────────────────────────
CreateThread(function()
    while true do
        local sleep = 800
        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local vehicle = GetVehiclePedIsIn(ped, false)

        for _, garage in ipairs(Config.Garages) do
            local distance = #(coords - garage.coords)
            if distance < 140.0 then
                sleep = 0
                DrawMarker(1, garage.coords.x, garage.coords.y, garage.coords.z - 0.95,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 1.2,
                    180, 200, 255, 100, false, true, 2, false, nil, nil, false)

                if distance <= (garage.radius or 28.0) then
                    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(
                        garage.coords.x, garage.coords.y, garage.coords.z + 1.1)
                    if onScreen then
                        local prompt = vehicle ~= 0 and ('/%s store'):format(Config.Commands.garage)
                            or ('/%s list'):format(Config.Commands.garage)
                        SetTextScale(0.34, 0.34)
                        SetTextFont(4)
                        SetTextProportional(1)
                        SetTextColour(200, 220, 255, 235)
                        SetTextOutline()
                        SetTextEntry('STRING')
                        AddTextComponentString(('%s - %s'):format(garage.name, prompt))
                        DrawText(sx, sy)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ─── Lifecycle ───────────────────────────────────────────────
CreateThread(function()
    Wait(3000)
    buildGarageBlips()
end)

AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(1000)
        buildGarageBlips()
    end)
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearGarageBlips()
    engine('ClearBlips', PREFIX .. 'garage_')
end)

RegisterNetEvent('grand_dealership:client:ClearMap', function()
    clearGarageBlips()
end)

return C
