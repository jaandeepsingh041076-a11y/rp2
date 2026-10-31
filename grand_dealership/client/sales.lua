-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_dealership/client/sales.lua
--  Forecourt markers, catalogue output in chat, test drives and
--  quote display. NO NUI.
-- ─────────────────────────────────────────────────────────────

DealerClient = DealerClient or {}
local C = DealerClient

C.Session = nil
C.Catalogue = {}
C.Blips = {}
C.UsingEngine = false
C.TestDrive = nil
C.TestVehicle = nil
C.LastPromptLot = nil
C.PromptCooldown = 0

local PREFIX = Config.Blips.prefix or 'dealer_'

-- ─── Blip engine ─────────────────────────────────────────────
local function engine(name, ...)
    if GetResourceState('grand_mechanic') ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports['grand_mechanic'][name](table.unpack(args, 1, args.n))
    end)
    return ok and result or nil
end

local function addBlip(record)
    local engineId = engine('AddBlip', {
        id = record.id,
        coords = record.coords,
        sprite = record.sprite or 326,
        colour = record.colour or 'gold',
        scale = record.scale or 0.85,
        label = record.label,
        range = Config.Blips.distanceCull or 1400.0,
        short = record.short == true,
    })

    if engineId then
        C.UsingEngine = true
        C.Blips[record.id] = engineId
        return engineId
    end

    local blip = AddBlipForCoord(record.coords.x, record.coords.y, record.coords.z)
    SetBlipSprite(blip, record.sprite or 326)
    SetBlipColour(blip, 46)
    SetBlipScale(blip, record.scale or 0.85)
    SetBlipAsShortRange(blip, record.short == true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(tostring(record.label))
    EndTextCommandSetBlipName(blip)
    C.Blips[record.id] = blip
    return blip
end

local function removeBlip(id)
    local handle = C.Blips[id]
    if not handle then return end
    if C.UsingEngine then
        engine('RemoveBlip', handle)
    elseif type(handle) == 'number' then
        RemoveBlip(handle)
    end
    C.Blips[id] = nil
end

local function buildMap()
    if not Config.Blips.enabled then return end

    for _, lot in ipairs(Config.Lots) do
        addBlip({
            id = PREFIX .. 'lot_' .. lot.id,
            coords = lot.coords,
            sprite = lot.blip and lot.blip.sprite or 326,
            colour = lot.blip and lot.blip.colour or 'gold',
            scale = lot.blip and lot.blip.scale or 0.85,
            label = lot.name,
            short = false,
        })
    end
end

local function clearMap()
    for id in pairs(C.Blips) do removeBlip(id) end
    C.Blips = {}
end

-- ─── Chat helpers ────────────────────────────────────────────
local function chat(title, text, colour)
    TriggerEvent('chat:addMessage', {
        color = colour or { 255, 200, 90 },
        multiline = true,
        args = { title or 'Dealership', tostring(text or '') },
    })
end

-- ─── Session / catalogue ─────────────────────────────────────
RegisterNetEvent('grand_dealership:client:Session', function(session)
    C.Session = session
    C.Catalogue = session and session.catalogue or C.Catalogue

    if session and session.testDrive then
        C.PendingTestDrive = session.testDrive
    end
end)

RegisterNetEvent('grand_dealership:client:Catalogue', function(rows)
    C.Catalogue = rows or {}

    if #C.Catalogue == 0 then
        chat('Catalogue', 'No models matched that class.', { 255, 150, 120 })
        return
    end

    for _, class in ipairs(C.Catalogue) do
        local lines = {}
        for _, item in ipairs(class.items or {}) do
            local tags = {}
            if item.stock <= 0 then tags[#tags + 1] = 'SOLD OUT' end
            if item.requiresLicense then tags[#tags + 1] = 'licence' end
            if not item.financed then tags[#tags + 1] = 'cash only' end

            lines[#lines + 1] = ('%-16s %-22s %10s  [%d in stock]%s'):format(
                tostring(item.model), tostring(item.label), DealerShared.Money(item.price),
                tonumber(item.stock) or 0,
                #tags > 0 and (' ' .. table.concat(tags, ', ')) or '')
        end
        chat(('%s (%d)'):format(tostring(class.label), #(class.items or {})),
            table.concat(lines, '\n'), { 220, 225, 240 })
    end

    chat('Buy', ('/%s <model> [cash|finance] [weeks] [deposit] | /%s <model> | /%s for garages'):format(
        Config.Commands.buycar, Config.Commands.testdrive, Config.Commands.garage), { 120, 220, 140 })
end)

RegisterNetEvent('grand_dealership:client:Quote', function(quote, text)
    C.LastQuote = quote
    chat(('Quote #%s'):format(tostring(quote.model)), text, { 200, 220, 255 })
end)

RegisterNetEvent('grand_dealership:client:Purchased', function(result)
    if not result then return end
    chat('Purchase complete', ('%s is registered as %s and stored at %s.\nUse /%s to collect it.'):format(
        tostring(result.quote and result.quote.label or result.model),
        tostring(result.plate), tostring(result.garage), Config.Commands.garage), { 120, 220, 140 })
end)

RegisterNetEvent('grand_dealership:client:Finance', function(rows)
    if not rows or #rows == 0 then
        chat('Finance', 'No active agreements.', { 200, 210, 255 })
        return
    end
    for _, row in ipairs(rows) do
        chat(('Finance #%s'):format(tostring(row.id)), table.concat({
            ('Vehicle: %s (%s)'):format(tostring(row.model), tostring(row.plate)),
            ('Weekly: %s | paid %d/%d | missed %d'):format(
                DealerShared.Money(row.weekly), row.weeksPaid, row.termWeeks, row.missedWeeks),
            ('Remaining: %s | next due %s'):format(
                DealerShared.Money(row.remaining), tostring(row.nextDue)),
            ('Pay with /%s %s'):format(Config.Commands.paycar, tostring(row.id)),
        }, '\n'), { 200, 210, 255 })
    end
end)

RegisterNetEvent('grand_dealership:client:Notify', function(message, kind)
    DealerShared.Notify(message, kind)
end)

-- ─── Catalogue command ───────────────────────────────────────
RegisterCommand(Config.Commands.catalogue, function(_, args)
    TriggerServerEvent('grand_dealership:server:RequestCatalogue', args[1])
end, false)

-- ─── Test drive ──────────────────────────────────────────────
local function deleteTestVehicle()
    if C.TestVehicle and DoesEntityExist(C.TestVehicle) then
        SetEntityAsMissionEntity(C.TestVehicle, true, true)
        DeleteVehicle(C.TestVehicle)
    end
    C.TestVehicle = nil
end

local function endTestDrive(reason, damaged)
    if not C.TestDrive then return end
    C.TestDrive = nil
    deleteTestVehicle()
    TriggerServerEvent('grand_dealership:server:EndTestDrive', damaged == true, reason or 'returned')
end

RegisterNetEvent('grand_dealership:client:StartTestDrive', function(payload)
    if not payload then return end
    if C.TestDrive then
        DealerShared.Notify('You already have a test drive out', 'warning')
        return
    end

    local model = payload.model
    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then
        TriggerServerEvent('grand_dealership:server:EndTestDrive', false, 'bad_model')
        return
    end

    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > timeout then
            TriggerServerEvent('grand_dealership:server:EndTestDrive', false, 'bad_model')
            DealerShared.Notify('That showroom model could not be loaded', 'error')
            return
        end
        Wait(100)
    end

    local spawn = payload.spawn or vector4(-738.0, -1465.0, 26.2, 115.0)
    local vehicle = CreateVehicle(hash, spawn.x, spawn.y, spawn.z, spawn.w or 0.0, true, false)
    if not vehicle or vehicle == 0 then
        TriggerServerEvent('grand_dealership:server:EndTestDrive', false, 'spawn_failed')
        return
    end

    SetVehicleNumberPlateText(vehicle, payload.plate or 'TEST')
    SetVehicleOnGroundProperly(vehicle)
    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetModelAsNoLongerNeeded(hash)

    C.TestVehicle = vehicle
    C.TestDrive = {
        id = payload.id,
        model = payload.model,
        label = payload.label,
        plate = payload.plate,
        lot = payload.lot,
        lotName = payload.lotName,
        expires = GetGameTimer() + (tonumber(payload.seconds) or 300) * 1000,
        track = payload.track,
        spawn = spawn,
        warned = false,
    }

    SetPedIntoVehicle(PlayerPedId(), vehicle, -1)
    chat('Test drive', ('%s (%s) - %d seconds. /testdrive return to bring it back.'):format(
        tostring(payload.label), tostring(payload.plate), tonumber(payload.seconds) or 300),
        { 120, 220, 140 })
end)

RegisterNetEvent('grand_dealership:client:StopTestDrive', function(reason)
    C.TestDrive = nil
    deleteTestVehicle()
    DealerShared.Notify(('Test drive ended (%s)'):format(tostring(reason or 'returned')), 'info')
end)

RegisterNetEvent('grand_dealership:client:ReturnTestDrive', function()
    if not C.TestDrive then return end

    local damaged = false
    if C.TestVehicle and DoesEntityExist(C.TestVehicle) then
        damaged = GetVehicleBodyHealth(C.TestVehicle) < (Config.TestDrive.damageHealthThreshold or 400)
    end
    endTestDrive('returned', damaged)
end)

-- ─── Test drive HUD + recall ─────────────────────────────────
CreateThread(function()
    while true do
        local sleep = 700
        local drive = C.TestDrive

        if drive then
            sleep = 0
            local remaining = math.max(0, math.floor((drive.expires - GetGameTimer()) / 1000))
            local minutes = math.floor(remaining / 60)
            local seconds = remaining % 60

            SetTextScale(0.40, 0.40)
            SetTextFont(4)
            SetTextProportional(1)
            SetTextColour(255, 220, 120, 235)
            SetTextOutline()
            SetTextRightJustify(true)
            SetTextWrap(0.0, 0.97)
            SetTextEntry('STRING')
            AddTextComponentString(('TEST DRIVE %02d:%02d'):format(minutes, seconds))
            DrawText(0.0, 0.06)

            if remaining <= 0 then
                local damaged = false
                if C.TestVehicle and DoesEntityExist(C.TestVehicle) then
                    damaged = GetVehicleBodyHealth(C.TestVehicle) < (Config.TestDrive.damageHealthThreshold or 400)
                end
                endTestDrive('expired', damaged)
            else
                local track = drive.track
                if track and track.coords then
                    local ped = PlayerPedId()
                    local coords = GetEntityCoords(ped)
                    local distance = #(coords - track.coords)
                    local radius = tonumber(track.radius) or 260.0

                    if distance > radius + 80.0 then
                        DealerShared.Notify('You left the test route - returning the car', 'warning')
                        endTestDrive('left_route', false)
                    elseif distance > radius and not drive.warned then
                        drive.warned = true
                        DealerShared.Notify('Turn back: you are leaving the test route', 'warning')
                    elseif distance <= radius then
                        drive.warned = false
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

-- ─── Forecourt markers ───────────────────────────────────────
CreateThread(function()
    while true do
        local sleep = 700
        local coords = GetEntityCoords(PlayerPedId())
        local nearest, nearestDistance = nil, math.huge

        for _, lot in ipairs(Config.Lots) do
            local distance = #(coords - lot.coords)
            if distance < nearestDistance then
                nearest, nearestDistance = lot, distance
            end

            if distance <= (Config.Blips.distanceCull or 1400.0) then
                DrawMarker(1, lot.coords.x, lot.coords.y, lot.coords.z - 0.95,
                    0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.0, 3.0, 1.2,
                    255, 200, 60, 110, false, true, 2, false, nil, nil, false)
            end
        end

        if nearest and nearestDistance <= (nearest.radius or 35.0) + 6.0 then
            sleep = 0
            local onScreen, sx, sy = GetScreenCoordFromWorldCoord(
                nearest.coords.x, nearest.coords.y, nearest.coords.z + 1.1)
            if onScreen then
                SetTextScale(0.34, 0.34)
                SetTextFont(4)
                SetTextProportional(1)
                SetTextColour(255, 230, 160, 235)
                SetTextOutline()
                SetTextEntry('STRING')
                AddTextComponentString(('%s - /%s to browse'):format(
                    nearest.name, Config.Commands.catalogue))
                DrawText(sx, sy)
            end

            if not C.LastPromptLot or C.LastPromptLot ~= nearest.id then
                C.LastPromptLot = nearest.id
                if GetGameTimer() - C.PromptCooldown > 4000 then
                    C.PromptCooldown = GetGameTimer()
                    DealerShared.Notify(('%s: /%s, /%s <model>, /%s <model>'):format(
                        nearest.name, Config.Commands.catalogue,
                        Config.Commands.buycar, Config.Commands.testdrive), 'info')
                end
            end
        else
            C.LastPromptLot = nil
        end

        Wait(sleep)
    end
end)

-- ─── Lifecycle ───────────────────────────────────────────────
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    buildMap()
    CreateThread(function()
        Wait(2500)
        TriggerServerEvent('grand_dealership:server:ClientReady')
    end)
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    deleteTestVehicle()
    clearMap()
    engine('ClearBlips', PREFIX)
end)

RegisterNetEvent('grand_dealership:client:ClearMap', function()
    clearMap()
end)

return C
