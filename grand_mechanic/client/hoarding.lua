-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/hoarding.lua
--  Yards, bays, lifts and impound counters. Registers the world
--  interaction points from Config.Locations / Config.Impound and
--  drives store / release / listing / plate lookups.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local Mx = Mechanic.Client

local Yard = {}
Mechanic.Yard = Yard

Yard.Handles = {}
Yard.Site = nil
local handlesBySite = {}

local function chat(lines)
    TriggerEvent('chat:addMessage', { multiline = true, args = lines })
end

-- ─── Which site am I standing in? ────────────────────────────
function Yard.SiteAt(coords)
    coords = coords or GetEntityCoords(PlayerPedId())
    for _, site in ipairs(Config.Locations) do
        if #(coords - site.coords) <= (site.radius or 15.0) then
            return site, #(coords - site.coords)
        end
    end
    return nil
end

function Mx.NearSite()
    return Yard.SiteAt()
end

-- ─── Register every site as an interaction ───────────────────
function Yard.Build()
    Yard.Clear()

    for _, site in ipairs(Config.Locations) do
        local usable = Mx.IsOnDuty(site.kind == 'towing' and 'tow'
            or site.kind == 'taxi' and 'taxi' or 'mechanic')
        local isIllegal = site.kind == 'illegal'

        if usable or isIllegal or site.kind == 'legal' then
            local actions = Yard.SiteActions(site)
            for _, entry in ipairs(actions) do
                local handle = Mx.Add(entry.coords or site.coords, entry.radius or 3.4,
                    entry.label, entry.action, {
                        key = entry.key or 'E',
                        job = entry.job,
                        hidden = entry.hidden,
                        data = entry.data or site,
                        icon = entry.icon,
                    })
                Yard.Handles[#Yard.Handles + 1] = handle
                handlesBySite[site.id] = handlesBySite[site.id] or {}
                handlesBySite[site.id][#handlesBySite[site.id] + 1] = handle
            end
        end
    end

    for _, lot in ipairs(Config.Impound) do
        local handle = Mx.Add(lot.coords, 3.2, ('Impound counter — %s ($%s)'):format(lot.name, lot.fee),
            function() Yard.OpenImpound(lot) end, { key = 'E' })
        Yard.Handles[#Yard.Handles + 1] = handle
    end

    for _, pub in ipairs(Config.PublicServices) do
        local handle = Mx.Add(pub.coords, pub.radius or 12.0, 'Pumps — siphon / top-up', function()
            local veh = Mx.Native('GetVehicleInFrontOfPlayer', 0) or 0
            TriggerEvent('grand_mechanic:client:Pump', pub)
        end, { key = 'E' })
        Yard.Handles[#Yard.Handles + 1] = handle
    end
end

function Yard.Clear()
    for _, h in ipairs(Yard.Handles) do Mx.Remove(h) end
    Yard.Handles = {}
    handlesBySite = {}
end

-- ─── The actions a site exposes ──────────────────────────────
function Yard.SiteActions(site)
    local out = {}
    local kind = site.kind

    if kind == 'hoarding' then
        out[#out + 1] = {
            label = 'Service bay — full restore', radius = 4.0, job = 'mechanic',
            coords = site.coords,
            action = function()
                local mech = Mechanic.Diag
                if mech then mech.FullService(nil, site) end
            end,
        }
        if site.hasTuning then
            out[#out + 1] = {
                label = 'Dyno — performance tune', coords = site.coords + vector3(2.4, 0.0, 0.0),
                job = 'mechanic', action = function()
                    local mech = Mechanic.Diag
                    if mech then mech.Tune(nil, site) end
                end,
            }
        end
        out[#out + 1] = {
            label = 'Parts counter', coords = site.coords + vector3(-2.4, 0.0, 0.0),
            action = function() Yard.OpenParts(site) end,
        }
        out[#out + 1] = {
            label = 'Bench stock', coords = site.coords + vector3(0.0, 2.4, 0.0),
            job = 'mechanic', action = function()
                TriggerServerEvent('grand_mechanic:server:Stock', site.id)
            end,
        }
    elseif kind == 'towing' then
        out[#out + 1] = {
            label = 'Tow yard — check out a flatbed', coords = site.spawn and site.coords or site.coords,
            job = 'tow', action = function() Yard.Checkout(site) end,
        }
        out[#out + 1] = {
            label = 'Yard ledger — book vehicles in', coords = site.coords + vector3(3.0, 0.0, 0.0),
            job = 'tow', action = function() Yard.OpenYard(site) end,
        }
        out[#out + 1] = {
            label = 'Hoarding bay — put this car in', coords = site.coords + vector3(0.0, 3.4, 0.0),
            radius = 6.0, job = 'tow', action = function() Yard.StoreNearby(site) end,
        }
    elseif kind == 'taxi' then
        out[#out + 1] = {
            label = 'Taxi dispatch desk', coords = site.coords, job = 'taxi',
            action = function()
                TriggerServerEvent('grand_mechanic:server:TaxiBoard')
                Yard.OpenTaxiRanks(site)
            end,
        }
        out[#out + 1] = {
            label = 'Cab pool — check out a taxi', coords = site.coords + vector3(2.6, 0.0, 0.0),
            job = 'taxi', action = function() Yard.Checkout(site, 'taxi') end,
        }
    elseif kind == 'legal' then
        out[#out + 1] = {
            label = 'Meeting bay', coords = site.coords,
            action = function()
                chat({ '^1▚ LS CAR MEET', '^7  street mechanics welcome — bring your own tools' })
            end,
        }
    elseif kind == 'illegal' then
        out[#out + 1] = {
            label = 'Chop: strip this car', coords = site.coords, radius = 5.0,
            action = function() Yard.ChopStrip(site) end,
        }
        out[#out + 1] = {
            label = 'Chop: respray + plates', coords = site.coords + vector3(3.2, 0.0, 0.0),
            action = function() Yard.ChopRespray(site) end,
        }
        out[#out + 1] = {
            label = 'Chop: sell to the buyer', coords = site.coords + vector3(-3.2, 0.0, 0.0),
            action = function() Yard.ChopSell(site) end,
        }
        out[#out + 1] = {
            label = 'Chop: tools and stock', coords = site.coords + vector3(0.0, 3.2, 0.0),
            action = function() Yard.OpenParts(site) end,
        }
    end

    return out
end

-- ─── Vehicle checkout from a yard ────────────────────────────
function Yard.Checkout(site, preferKind)
    local kind = preferKind or (site.kind == 'taxi' and 'taxi' or site.kind == 'towing' and 'tow' or 'mechanic')
    local pool = Config.Fleet[kind]
    if not pool or #pool == 0 then return Mx.Notify('No fleet at this site', 'error') end

    local model = pool[math.random(#pool)]
    local spawn = (Config.FleetSpawn and Config.FleetSpawn[model]) or site.spawn or site.coords
    TriggerEvent('grand_mechanic:client:SpawnFleet', { model = model, spawn = spawn, site = site.id, kind = kind })
end

RegisterNetEvent('grand_mechanic:client:SpawnFleet', function(data)
    local hash = GetHashKey(data.model)
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 80 do tries = tries + 1 Wait(50) end
    if not HasModelLoaded(hash) then
        return Mx.Notify('That yard has no ' .. data.model .. ' on the lot', 'error')
    end

    local ped = PlayerPedId()
    local spawn = data.spawn
    local x, y, z, h
    if type(spawn) == 'table' or (spawn and spawn.w) then
        x, y, z, h = spawn.x or spawn[1], spawn.y or spawn[2], spawn.z or spawn[3], spawn.w or spawn[4] or 0.0
    else
        local fwd = GetEntityForwardVector(ped)
        x, y, z = GetEntityCoords(ped + (fwd * 6.0)).x, GetEntityCoords(ped + (fwd * 6.0)).y, GetEntityCoords(ped + (fwd * 6.0)).z
        h = GetEntityHeading(ped)
    end

    local veh = CreateVehicle(hash, x, y, z, h, true, false)
    SetEntityAsMissionEntity(veh, true, true)
    SetVehicleNumberPlateText(veh, ('GRND%04d'):format(math.random(0, 9999)))
    SetVehicleOnGroundProperly(veh)
    SetModelAsNoLongerNeeded(hash)
    TaskWarpPedIntoVehicle(ped, veh, -1)

    Mx.Notify(('Checked out %s — return it to %s before shift end'):format(data.model:upper(), data.site), 'info')
    TriggerServerEvent('grand_mechanic:server:RefreshJob')
end)

-- ─── Parts counter (chat driven) ─────────────────────────────
function Yard.OpenParts(site)
    local lines = { ('^1▚ %s — PARTS'):format(site.name) }
    local cash = 0
    for _, key in ipairs({ 'engine', 'turbo', 'radiators', 'battery', 'alternator', 'brakes', 'suspension',
        'tires_set', 'glass', 'panel_front', 'panel_rear', 'transmission', 'driveshaft', 'exhaust',
        'intercooler', 'nitrous', 'armour_kit' }) do
        local def = Config.Parts[key]
        if def and def.sell > 0 then
            lines[#lines + 1] = ('  ^3/wrench buy %s %s ^7$%s  ^5%.1fkg'):format(
                site.id, key, Shared.Money(def.sell), def.weight)
        end
    end
    lines[#lines + 1] = '^7Tools: ^3/wrench tool toolbox ^7| ^3/wrench tool diag_tablet ^7| ^3/wrench tool welder'
    chat(lines)
end

-- ─── Yard ledger ─────────────────────────────────────────────
function Yard.OpenYard(site)
    TriggerServerEvent('grand_mechanic:server:HoardList')
    CreateThread(function()
        Wait(600)
        local lines = { ('^1▚ %s — IN THE YARD'):format(site.name) }
        if #Mx.HoardList == 0 then lines[#lines + 1] = '^7  empty' end
        for _, row in ipairs(Mx.HoardList) do
            if not row.stolen then
                lines[#lines + 1] = ('  ^3%s ^7%s  %s  ^1$%s ^7(%dh)  ^5%s'):format(
                    row.plate, (row.model or ''):sub(1, 12), row.site,
                    Shared.Money(row.fees), row.hours, row.owner or '—')
            end
        end
        lines[#lines + 1] = '^7Release: ^3/impound <plate> [cash|bank]'
        chat(lines)
    end)
end

-- ─── Impound counter ─────────────────────────────────────────
function Yard.OpenImpound(lot)
    TriggerServerEvent('grand_mechanic:server:HoardList')
    CreateThread(function()
        Wait(600)
        local lines = { ('^1▚ %s'):format(lot.name) }
        local count = 0
        for _, row in ipairs(Mx.HoardList) do
            if row.site == lot.id and not row.stolen then
                count = count + 1
                lines[#lines + 1] = ('  ^3%s ^7%s  ^1$%s ^7(%dh @ $%s/h)'):format(
                    row.plate, (row.model or ''):sub(1, 14), Shared.Money(row.fees), row.hours, Shared.Money(row.hourly))
            end
        end
        if count == 0 then lines[#lines + 1] = '^7  no vehicles held at this lot' end
        lines[#lines + 1] = ('^7  walk-up fee $%s — ^3/impound <plate> cash'):format(Shared.Money(lot.fee))
        chat(lines)
    end)
end

RegisterNetEvent('grand_mechanic:client:ImpoundOpen', function(data)
    Yard.OpenImpound(data)
end)

RegisterNetEvent('grand_mechanic:client:HoardSync', function(row)
    Mx.Notify(('%s booked into %s'):format(row.plate, row.site), 'info')
end)

RegisterNetEvent('grand_mechanic:client:HoardReleased', function(row)
    Mx.Notify(('%s is out of the yard'):format(row.plate), 'success')
end)

RegisterNetEvent('grand_mechanic:client:PlateResult', function(data)
    local lines = { ('^1▚ PLATE READ — %s'):format(data.plate) }
    lines[#lines + 1] = ('  owner: ^7%s ^5(%s)'):format(data.owner or 'NONE ON FILE', data.ownerCid or '—')
    lines[#lines + 1] = ('  model: ^7%s  garage: ^7%s'):format(data.model or '—', data.garage or '—')
    if data.hoard then
        lines[#lines + 1] = ('  ^1HELD AT %s — $%s (%d hours)'):format(
            data.hoard.site, Shared.Money(data.hoard.fees), data.hoard.hours or 0)
    end
    for _, flag in ipairs(data.flags or {}) do
        lines[#lines + 1] = ('  ^3▲ %s'):format(flag)
    end
    chat(lines)
end)

RegisterCommand('plate', function(_, args)
    TriggerServerEvent('grand_mechanic:server:PlateLookup', args[1] or '')
end, false)

-- ─── Hoard a vehicle in front of you (tow / police) ─────────
function Yard.StoreNearby(site)
    local veh = Mechanic.Diag and Mechanic.Diag.GetTargetVehicle(Config.Ranges.flatbedLock) or 0
    if veh == 0 then return Mx.Notify('No vehicle to hoard', 'error') end
    local snap = Mx.Snapshot(veh)
    TriggerServerEvent('grand_mechanic:server:Store', {
        plate = snap.plate, model = snap.modelName, site = site.id,
        coords = snap.coords, netId = snap.netId,
    })
end

-- ─── Chop shop flows ─────────────────────────────────────────
function Yard.ChopStrip(site)
    local veh = Mechanic.Diag and Mechanic.Diag.GetTargetVehicle(14.0) or 0
    if veh == 0 then return Mx.Notify('Bring a car into the shop', 'error') end
    local snap = Mx.Snapshot(veh)
    Mx.Progress('STRIPPING ' .. snap.plate, 16, { dict = 'mini@repair', clip = 'fixing_a_vehicle_b_1' })
    TriggerServerEvent('grand_mechanic:server:Strip', { plate = snap.plate, site = site.id })
    SetVehicleBodyHealth(veh, math.max(120.0, snap.bodyHealth - 380.0))
    for i = 0, 5 do Mx.Native('SetVehiclePanelStatus', nil, veh, i, 3) end
end

function Yard.ChopRespray(site)
    local veh = Mechanic.Diag and Mechanic.Diag.GetTargetVehicle(14.0) or 0
    if veh == 0 then return Mx.Notify('No car on the paint ramp', 'error') end
    local snap = Mx.Snapshot(veh)
    Mx.Progress('PRIMER + PAINT', 22, { dict = 'anim@heists@paint', clip = 'painting_01' })
    SetVehiclePaintJob(veh, 2)
    SetVehicleColours(veh, math.random(0, 159), math.random(0, 159))
    TriggerServerEvent('grand_mechanic:server:Respray', {
        plate = snap.plate, site = site.id, model = snap.modelName,
    })
end

function Yard.ChopSell(site)
    local veh = Mechanic.Diag and Mechanic.Diag.GetTargetVehicle(20.0) or 0
    if veh == 0 then return Mx.Notify('The buyer wants to see the car', 'error') end
    local snap = Mx.Snapshot(veh)
    Mx.Progress('NEGOTIATING', 10, { dict = 'anim@amb@business@cocaine@cocainex@look_out', clip = 'idle_a' })
    TriggerServerEvent('grand_mechanic:server:SellCar', {
        plate = snap.plate, site = site.id, vehicleClass = snap.class, coords = snap.coords,
    })
    local net = NetworkGetNetworkIdFromEntity(veh)
    if net and net > 0 then
        TriggerServerEvent('grand_mechanic:server:ClearVehicle', net)
    end
end

function Yard.OpenTaxiRanks(site)
    local lines = { ('^1▚ %s — RANK'):format(site.name) }
    for _, route in ipairs(Config.TaxiRoutes) do
        if route.from == site.id then
            lines[#lines + 1] = ('  ^3/taxi %s ^7%s  ^1$%s'):format(route.id, route.name, Shared.Money(route.fare))
        end
    end
    lines[#lines + 1] = '^7Hail: ^3/taxi call ^7| board: ^3/taxi board'
    chat(lines)
end

RegisterNetEvent('grand_mechanic:client:Pump', function(pub)
    Mx.Notify(('%s pumps — use /fuel or /siphon'):format(pub.name), 'info')
end)

-- ─── Fuel commands (public, no job needed) ───────────────────
RegisterCommand('fuel', function()
    local veh = Mechanic.Diag and Mechanic.Diag.GetTargetVehicle(10.0) or 0
    if veh == 0 then return Mx.Notify('No vehicle', 'error') end
    local site = Yard.SiteAt()
    if not site or (site.kind ~= 'legal' and site.kind ~= 'hoarding') then
        return Mx.Notify('Not at a pump', 'error')
    end
    TriggerServerEvent('grand_mechanic:server:BuyFuel', site.id)
end, false)

RegisterCommand('siphon', function()
    local veh = Mechanic.Diag and Mechanic.Diag.GetTargetVehicle(6.0) or 0
    if veh == 0 then return Mx.Notify('No vehicle', 'error') end
    Mx.Progress('SIPHONING', 12, { dict = 'mini@strip_club@backstage', clip = 'strip_pole_transition' })
    TriggerServerEvent('grand_mechanic:server:Siphon', Mx.Snapshot(veh).plate, veh)
end, false)

CreateThread(function()
    Wait(2500)
    Yard.Build()
    RegisterNetEvent('grand_mechanic:client:SessionReady', function() Yard.Build() end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Yard.Clear() end
end)

exports('SiteAt', Yard.SiteAt)
exports('Build', Yard.Build)

return Yard
