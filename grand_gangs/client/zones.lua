-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/client/zones.lua
--  The turf map: blips + ground rings + on-screen prompts.
--  Everything renders through grand_mechanic's GrandBlips engine
--  when it is running, with a raw AddBlip fallback so the map
--  still works if the mechanic resource is stopped.
--  NO NUI - only markers, 3D text and chat.
-- ─────────────────────────────────────────────────────────────

local Shared = GangsShared

GangsClient = GangsClient or {}
local C = GangsClient

C.Blips = {}          -- [record id] = engine id or raw handle
C.Zones = {}          -- [record id] = zone payload
C.UsingEngine = false
C.InZone = nil
C.LastWatch = 0
C.Counters = { entered = 0, left = 0 }

local PREFIX = (Config.Blips and Config.Blips.prefix) or 'gang_'

-- ─── Engine bridge ───────────────────────────────────────────
local function engineReady()
    return GetResourceState('grand_mechanic') == 'started'
end

local function engine(name, ...)
    if not engineReady() then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports['grand_mechanic'][name](table.unpack(args, 1, args.n))
    end)
    if not ok then
        if Config.Debug then
            print(('^3[gangs] grand_mechanic:%s failed: %s^7'):format(name, tostring(result)))
        end
        return nil
    end
    return result
end

-- ─── Blips ───────────────────────────────────────────────────
local function colourIndex(record)
    if type(record.colour) == 'number' then return record.colour end
    local names = {
        red = 1, green = 2, blue = 38, yellow = 5, orange = 17,
        purple = 27, pink = 48, white = 0, grey = 4, gold = 46,
        contested = 49, neutral = 4,
    }
    return names[tostring(record.colour or ''):lower()] or 4
end

local function removeBlip(recordId)
    local handle = C.Blips[recordId]
    if not handle then return end

    if type(handle) == 'table' and handle.engine then
        engine('RemoveBlip', handle.id)
    elseif type(handle) == 'number' then
        RemoveBlip(handle)
    elseif type(handle) == 'string' then
        engine('RemoveBlip', handle)
    end
    C.Blips[recordId] = nil
end

local function addBlip(record)
    if not record or not record.coords then return end

    -- attach to the engine first
    local engineId = engine('AddBlip', {
        id = record.id,
        coords = record.coords,
        sprite = tonumber(record.sprite) or 84,
        colour = record.colour,
        scale = tonumber(record.scale) or 0.82,
        label = record.label,
        range = tonumber(record.range) or (Config.Blips.distanceCull or 1400.0),
        hidden = record.hidden == true,
        short = record.short == true,
    })

    if engineId then
        C.UsingEngine = true
        C.Blips[record.id] = { engine = true, id = engineId }
        return
    end

    -- raw fallback
    local coords = record.coords
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, tonumber(record.sprite) or 84)
    SetBlipColour(blip, colourIndex(record))
    SetBlipScale(blip, tonumber(record.scale) or 0.82)
    SetBlipAsShortRange(blip, record.short ~= false)
    SetBlipDisplay(blip, record.hidden and 0 or 4)

    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(tostring(record.label or 'Turf'))
    EndTextCommandSetBlipName(blip)

    C.Blips[record.id] = blip
end

-- ─── Ground rings ────────────────────────────────────────────
local function removeZone(zone)
    if not zone then return end
    engine('RemoveZone', zone.id)
    C.Zones[zone.id] = nil
end

local function addZone(zone)
    if not zone or not zone.coords then return end

    local added = engine('AddZone', {
        id = zone.id,
        group = zone.group or 'gang_turf',
        coords = zone.coords,
        radius = tonumber(zone.radius) or 150.0,
        colour = zone.colour,
        height = tonumber(zone.height) or 30.0,
        label = zone.label or 'Turf',
        pvp = zone.pvp == true,
        rgba = zone.rgba,
        ghetto = zone.ghetto == true,
    })

    -- engine returns nil when it is missing; the zone table is still
    -- cached so our own marker loop can draw the ring.
    C.Zones[zone.id] = {
        payload = zone,
        engine = added ~= nil,
        coords = zone.coords,
        radius = tonumber(zone.radius) or 150.0,
        label = zone.label,
        ghetto = zone.ghetto == true,
        rgba = zone.rgba or (zone.ghetto and { 255, 30, 56, 110 } or { 150, 150, 150, 90 }),
    }
end

-- ─── Map sync ────────────────────────────────────────────────
local function clearMap()
    for id in pairs(C.Blips) do removeBlip(id) end
    for _, zone in pairs(C.Zones) do removeZone(zone.payload) end
    C.Blips, C.Zones = {}, {}
end

C.ClearMap = clearMap

RegisterNetEvent('grand_gangs:client:SyncMap', function(blips, zones)
    clearMap()

    for _, blip in ipairs(blips or {}) do addBlip(blip) end
    for _, zone in ipairs(zones or {}) do addZone(zone) end

    if Config.Debug then
        print(('^2[gangs] map synced: %d blips, %d zones^7'):format(
            #(blips or {}), #(zones or {})))
    end
end)

RegisterNetEvent('grand_gangs:client:ZoneUpdate', function(snapshot, blip)
    if blip and blip.id then
        removeBlip(blip.id)
        addBlip(blip)
    end
    if snapshot and snapshot.id then
        local key = PREFIX .. 'z_' .. snapshot.id
        local zone = C.Zones[key]
        if zone then
            zone.label = snapshot.name or zone.label
            zone.ghetto = snapshot.ghetto == true
        end
    end
    C.LastWatch = 0
end)

RegisterNetEvent('grand_gangs:client:ClearMap', function()
    clearMap()
end)

-- ─── Local zone resolution ───────────────────────────────────
local function zoneAtPlayer()
    local coords = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, math.huge
    for _, zone in pairs(C.Zones) do
        local centre = zone.coords
        local flat = #(vector2(coords.x, coords.y) - vector2(centre.x, centre.y))
        if flat <= zone.radius + 1.0 and flat < bestDist then
            best, bestDist = zone, flat
        end
    end
    return best, bestDist
end

C.ZoneAtPlayer = zoneAtPlayer

-- ─── Watch loop: enter/exit + ground markers ─────────────────
CreateThread(function()
    local lastLabel = nil

    while true do
        local sleep = 500
        local zone = zoneAtPlayer()

        -- boundary change
        if zone ~= C.InZone then
            local previous = C.InZone
            C.InZone = zone

            if previous then
                TriggerServerEvent('grand_gangs:server:ZoneWatch', previous.payload.id, false)
                if Config.Blips.notifyOnZoneChange then
                    TriggerEvent('chat:addMessage', {
                        color = { 180, 180, 180 },
                        args = { 'Turf', ('Left %s'):format(previous.label or 'the turf') },
                    })
                end
            end

            if zone then
                TriggerServerEvent('grand_gangs:server:ZoneWatch', zone.payload.id, true)
                if Config.Blips.notifyOnZoneChange then
                    TriggerEvent('chat:addMessage', {
                        color = zone.ghetto and { 255, 80, 80 } or { 120, 220, 120 },
                        args = { 'Turf', zone.ghetto
                            and ('%s - RED ZONE, hostile fire is sanctioned'):format(zone.label)
                            or ('%s - turf ground'):format(zone.label) },
                    })
                end
            end
        end

        -- marker rendering near the player
        local coords = GetEntityCoords(PlayerPedId())
        local drawn = 0
        for _, zone in pairs(C.Zones) do
            local centre = zone.coords
            local flat = #(vector2(coords.x, coords.y) - vector2(centre.x, centre.y))
            local drawDist = Config.Blips.drawDistance or 420.0

            if flat <= drawDist then
                drawn = drawn + 1
                local rgb = zone.rgba or { 150, 150, 150, 90 }
                DrawMarker(1, centre.x, centre.y, centre.z - 1.0,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    zone.radius * 2.0, zone.radius * 2.0, 2.0,
                    rgb[1], rgb[2], rgb[3], math.min(rgb[4] or 90, 110),
                    false, true, 2, false, nil, nil, false)

                local promptDist = Config.Blips.promptDistance or 260.0
                if flat <= promptDist then
                    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(centre.x, centre.y, centre.z + 2.0)
                    if onScreen then
                        SetTextScale(0.32, 0.32)
                        SetTextFont(4)
                        SetTextProportional(1)
                        SetTextColour(rgb[1], rgb[2], rgb[3], 235)
                        SetTextOutline()
                        SetTextEntry('STRING')
                        AddTextComponentString(tostring(zone.label or 'Turf'))
                        DrawText(sx, sy)
                    end
                end

                if drawn >= 6 then break end
            end
        end

        if drawn > 0 then sleep = 0 end
        if Config.Debug and zone and zone.label ~= lastLabel then
            lastLabel = zone.label
            print(('^5[gangs] in %s^7'):format(tostring(zone.label)))
        end

        Wait(sleep)
    end
end)

-- ─── Resource lifecycle ─────────────────────────────────────
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Wait(1500)
    TriggerServerEvent('grand_gangs:server:ClientReady')
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearMap()
    engine('ClearBlips', PREFIX)
end)

return C
