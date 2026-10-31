-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/tow.lua
--  Flatbed work: hook up, winch onto the bed, tow to the yard,
--  and the roadside job board a tow driver actually drives around.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local Mx = Mechanic.Client

local TowCli = {}
Mechanic.TowCli = TowCli

TowCli.Loaded = {}     -- [plate] = { plate, model }
local bedHandle = nil
local bedNet = 0
local winching = false

--- Stable network id for a vehicle (client-side EntityToNet, guarded).
local function NetOf(veh)
    return tonumber(Mx.Native('EntityToNet', 0, veh)) or 0
end
TowCli.NetOf = NetOf

-- ─── Where is the bed of my truck? ───────────────────────────
function TowCli.Truck()
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then return nil end
    local veh = GetVehiclePedIsIn(ped, false)
    local model = GetEntityModel(veh)
    for _, name in ipairs({ 'flatbed', 'towtruck', 'buckeler' }) do
        if model == GetHashKey(name) then return veh end
    end
    -- anything with a winch counts if it is a truck class with an open rear
    if GetVehicleClass(veh) == 20 then return veh end
    return nil
end

function TowCli.BedPoint(truck)
    local fwd = GetEntityForwardVector(truck)
    local pos = GetEntityCoords(truck) - (fwd * 4.2)
    return pos
end

-- ─── Hook up ─────────────────────────────────────────────────
function TowCli.Attach()
    if winching then return end
    local truck = TowCli.Truck()
    if not truck then return Mx.Notify('You need to be on a flatbed', 'error') end

    local bed = TowCli.BedPoint(truck)
    local target, dist = 0, Config.Ranges.flatbedLock
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if veh ~= truck and DoesEntityExist(veh) then
            local d = #(bed - GetEntityCoords(veh))
            if d < dist then target, dist = veh, d end
        end
    end

    if target == 0 then return Mx.Notify('Nothing within winch reach', 'error') end

    local snap = Mx.Snapshot(target)
    if snap.plate == '' then return Mx.Notify('No readable plate', 'error') end

    winching = true
    Mx.Progress('WINCHING ' .. snap.plate, Config.Timing.towSeconds, {
        dict = 'anim@heists@boxcutter_01', clip = 'idle_a',
    })
    winching = false

    if not DoesEntityExist(target) then return Mx.Notify('The vehicle vanished', 'error') end

    -- physically drop it on the bed and lock it to the truck
    local bedPos = TowCli.BedPoint(truck)
    DetachEntity(target, true, true)
    SetEntityCoordsNoOffset(target, bedPos.x, bedPos.y, bedPos.z + 0.30, false, false, false)
    SetEntityHeading(target, GetEntityHeading(truck))
    FreezeEntityPosition(target, false)
    AttachEntityToEntity(target, truck, 2, 0.0, -3.4, 0.70, 0.0, 0.0, 0.0,
        false, false, false, false, 0, false)

    TowCli.Loaded[snap.plate] = { plate = snap.plate, model = snap.modelName, truck = truck }
    bedHandle = target
    bedNet = NetOf(target)

    TriggerServerEvent('grand_mechanic:server:TowAttach', {
        netId = bedNet, plate = snap.plate, model = snap.modelName, coords = snap.coords,
        job = Mx.Session.active,
    })
    TriggerEvent('chat:addMessage', { args = { ('^1WINCHED ^7%s ^7— meter is running'):format(snap.plate) } })
end

-- ─── Drop it ────────────────────────────────────────────────
function TowCli.Detach(hoard)
    if not bedHandle or not DoesEntityExist(bedHandle) then
        return Mx.Notify('Nothing is on your bed', 'error')
    end
    local truck = TowCli.Truck()
    if not truck then return Mx.Notify('Get back on the flatbed', 'error') end

    local site = Mechanic.Yard and Mechanic.Yard.SiteAt() or nil
    if hoard and not site then
        return Mx.Notify('Drive into a yard to book it in', 'error')
    end

    local snap = Mx.Snapshot(bedHandle)
    DetachEntity(bedHandle, true, true)
    local drop = GetEntityCoords(truck) - (GetEntityForwardVector(truck) * 7.0)
    SetEntityCoordsNoOffset(bedHandle, drop.x, drop.y, drop.z + 0.2, false, false, false)
    SetVehicleOnGroundProperly(bedHandle)
    FreezeEntityPosition(bedHandle, false)

    TriggerServerEvent('grand_mechanic:server:TowDetach', bedNet, {
        hoard = hoard and true or false,
        site = site and site.id,
        coords = GetEntityCoords(bedHandle),
    })

    if snap then TowCli.Loaded[snap.plate] = nil end
    bedHandle, bedNet = nil, 0
end

-- ─── Settle with the owner standing next to you ─────────────
function TowCli.Settle()
    if not bedHandle or not DoesEntityExist(bedHandle) then
        return Mx.Notify('No vehicle on the bed', 'error')
    end
    local snap = Mx.Snapshot(bedHandle)
    local nearest = TowCli.ClosestPlayer(snap.coords, Config.Ranges.customerZone)
    local payer = nearest and GetPlayerServerId(nearest) or 0

    TriggerServerEvent('grand_mechanic:server:TowSettle', bedNet, {
        customer = payer,
        coords = snap.coords,
    })

    Mx.Notify(payer > 0
        and ('Billing player ' .. payer .. ' for ' .. snap.plate)
        or 'No customer in range — the crew fronts this one', 'info')
end

function TowCli.ClosestPlayer(coords, maxDist)
    local best, bestD = nil, maxDist or 5.0
    for _, player in ipairs(GetActivePlayers()) do
        if player ~= PlayerId() then
            local d = #(coords - GetEntityCoords(GetPlayerPed(player)))
            if d < bestD then best, bestD = player, d end
        end
    end
    return best
end

-- ─── Job board as world markers (no NUI) ─────────────────────
local boardHandles = {}
function TowCli.RefreshBoardMarkers()
    for _, h in ipairs(boardHandles) do Mx.Remove(h) end
    boardHandles = {}

    for _, job in ipairs(Mx.Board) do
        if job.kind == 'tow' and (job.status == 'open' or job.worker == Mx.Session.cid) then
            local coords = vector3(job.x, job.y, job.z)
            if #(GetEntityCoords(PlayerPedId()) - coords) < 900.0 then
                local h = Mx.Add(coords, 12.0,
                    ('TOW %s — %s ($%s) %s'):format(job.plate, job.model or '', Shared.Money(job.estimate),
                        job.status == 'open' and '[ claim ]' or '[ yours ]'),
                    function()
                        if job.status == 'open' then
                            TriggerServerEvent('grand_mechanic:server:Claim', job.ref)
                        else
                            TowCli.Attach()
                        end
                    end, { job = 'tow' })
                boardHandles[#boardHandles + 1] = h
            end
        end
    end
end

RegisterNetEvent('grand_mechanic:client:BoardChanged', function()
    TowCli.RefreshBoardMarkers()
end)

CreateThread(function()
    Wait(4000)
    TowCli.RefreshBoardMarkers()
    while true do
        Wait(20000)
        TowCli.RefreshBoardMarkers()
    end
end)

-- ─── Server feedback ─────────────────────────────────────────
RegisterNetEvent('grand_mechanic:client:TowAttached', function(data)
    if data.cid ~= Mx.Session.cid then
        Mx.Notify(('%s winched %s'):format(data.cid:sub(1, 6), data.plate), 'inform')
    end
end)

RegisterNetEvent('grand_mechanic:client:TowDetached', function(data)
    if bedHandle and data.netId and data.netId == bedNet then
        bedHandle, bedNet = nil, 0
    end
end)

RegisterNetEvent('grand_mechanic:client:TowSettled', function(data)
    Mx.Notify(('%s settled — $%s in your pocket (%d min)'):format(
        data.plate or '', Shared.Money(data.crew or 0), data.minutes or 0), 'success')
end)

-- ─── Commands ─────────────────────────────────────────────────
RegisterCommand('tow', function(_, args)
    local sub = tostring(args[1] or 'attach'):lower()
    if sub == 'attach' or sub == 'winch' then TowCli.Attach()
    elseif sub == 'drop' then TowCli.Detach(false)
    elseif sub == 'hoard' or sub == 'yard' then TowCli.Detach(true)
    elseif sub == 'settle' or sub == 'pay' then TowCli.Settle()
    elseif sub == 'scrap' then
        local snap = Mx.Snapshot(Mechanic.Diag and Mechanic.Diag.GetTargetVehicle(12.0) or 0)
        if snap then TriggerServerEvent('grand_mechanic:server:TowScrap', 0, snap.plate) end
    elseif sub == 'list' or sub == 'board' then
        TriggerEvent('grand_mechanic:client:OpenBoard', Mx.Board)
    elseif sub == 'meter' then
        TriggerServerEvent('grand_mechanic:server:TowMeter')
    else
        Mx.Notify('usage: /tow attach|drop|hoard|settle|scrap|board|meter', 'inform')
    end
end, false, { help = 'Flatbed controls' })

RegisterCommand('winch', TowCli.Attach, false)
RegisterKeyMapping('winch', 'Grand RP: winch nearest vehicle', 'keyboard', 'F8')

RegisterCommand('droptow', function() TowCli.Detach(false) end, false)
RegisterKeyMapping('droptow', 'Grand RP: release the towed vehicle', 'keyboard', 'F9')

exports('Attach', TowCli.Attach)
exports('Detach', TowCli.Detach)

return TowCli
