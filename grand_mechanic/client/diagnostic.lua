-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/diagnostic.lua
--  OBD-II scan tool: reads live damage, derives faults, quotes the
--  job, drives the wrench loop and hands the result to the server.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local Mx = Mechanic.Client

local Diag = {}
Mechanic.Diag = Diag

Diag.Last = nil        -- last snapshot
Diag.Faults = nil      -- last derived faults
Diag.Quote = nil

local ANIM = { dict = 'anim@prop_tmp@mechanic', clip = 'work_on_car_01_mech' }
local ANIM_ALT = { dict = 'mini@repair', clip = 'fixing_a_ped' }

-- ─── Helpers ──────────────────────────────────────────────────
function Diag.GetTargetVehicle(maxDistance)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local handle, dist = 0, (maxDistance or Config.Ranges.workZone)

    local models = GetGamePool('CVehicle')
    for _, veh in ipairs(models) do
        if DoesEntityExist(veh) and not IsEntityAPed(veh) then
            local d = #(pos - GetEntityCoords(veh))
            if d < dist then
                handle, dist = veh, d
            end
        end
    end
    return handle
end

--- Chat print instead of NUI: the spec says no UI, so the scan reads out.
function Diag.Report(faults, quote, snap)
    local lines = { ('^1▚ DIAGNOSTIC  %s  ^7%s'):format(snap.plate, snap.modelName or '') }
    if #faults == 0 then
        lines[#lines + 1] = '^2  no faults stored — drivable'
    else
        for _, f in ipairs(faults) do
            lines[#lines + 1] = ('^3  %-14s ^7%s%%  →  %s'):format(
                f.label, Shared.Round(f.severity * 100.0, 0),
                (f.part and Config.Parts[f.part] and Config.Parts[f.part].label) or 'labour only')
        end
    end
    local cond = Shared.Condition(faults)
    lines[#lines + 1] = ('^7  condition: ^1%s  ^7labour $%s  parts $%s  tax $%s  ^1total $%s'):format(
        cond:upper(), Shared.Money(quote.labour or 0), Shared.Money(quote.parts or 0),
        Shared.Money(quote.tax or 0), Shared.Money(quote.total or 0))
    lines[#lines + 1] = ('^7  bench time: ^3%.0fs ^7| rank ^3%d'):format(quote.seconds or 0, (quote.rank or 0) + 1)
    TriggerEvent('chat:addMessage', { multiline = true, args = lines })
end

-- ─── Scan ─────────────────────────────────────────────────────
function Diag.Scan(veh)
    veh = veh or Diag.GetTargetVehicle()
    if veh == 0 then
        return Mx.Notify('No vehicle in scan range', 'error')
    end

    local snap = Mx.Snapshot(veh)
    if not snap then return Mx.Notify('Scanner lost the vehicle', 'error') end

    Mx.Progress('OBD SCAN', Config.Timing.diagnosticSeconds, ANIM_ALT)

    local faults = Shared.DeriveFaults(snap)
    for _, f in ipairs(faults) do
        f.part = Shared.PickPart(f.id, snap)
        snap['_fault_' .. f.id] = f.severity
    end
    local quote = Shared.Quote(faults, snap, Mx.Session.level or 0, 'mechanic')

    Diag.Last, Diag.Faults, Diag.Quote = snap, faults, quote
    Diag.Report(faults, quote, snap)

    TriggerServerEvent('grand_mechanic:server:CreateJob', 'mechanic', {
        plate = snap.plate, model = snap.modelName, coords = snap.coords,
        faults = faults, estimate = quote.total, site = Mx.NearSite and Mx.NearSite() or nil,
        customer = nil,
    })

    return true, { snap = snap, faults = faults, quote = quote }
end

RegisterNetEvent('grand_mechanic:client:RunScan', function()
    Diag.Scan()
end)

-- ─── The actual wrench loop ──────────────────────────────────
---@param veh number
---@param opts table { job, customer, site }
function Diag.Repair(veh, opts)
    opts = opts or {}
    veh = veh or Diag.GetTargetVehicle()
    if veh == 0 then return Mx.Notify('Bring the vehicle closer', 'error') end

    if IsPedInAnyVehicle(PlayerPedId(), false) then
        return Mx.Notify('Get out of the car to work on it', 'error')
    end

    local snap = Mx.Snapshot(veh)
    local faults = Shared.DeriveFaults(snap)
    for _, f in ipairs(faults) do
        f.part = Shared.PickPart(f.id, snap)
        snap['_fault_' .. f.id] = f.severity
    end
    if #faults == 0 then return Mx.Notify('Nothing on this car is faulted', 'inform') end

    local quote = Shared.Quote(faults, snap, Mx.Session.level or 0, 'mechanic')
    if quote.total < Config.Damage.repairMinPayout then
        return Mx.Notify('Too little work to bill — not worth the time', 'error')
    end

    local total = math.max(Config.Timing.repairSeconds, quote.seconds)
    local perFault = total / #faults

    -- work each fault in order of severity, one animation per component
    for _, fault in ipairs(faults) do
        local part = fault.part and Config.Parts[fault.part]
        local name = (part and part.label or 'Labour'):upper()
        Mx.Progress('FITTING ' .. name, math.max(3, perFault), ANIM)

        if not DoesEntityExist(veh) then
            return Mx.Notify('The vehicle disappeared mid-job', 'error')
        end
    end

    TriggerServerEvent('grand_mechanic:server:Repair', {
        plate = snap.plate,
        netId = snap.netId,
        model = snap.modelName,
        faults = faults,
        quote = quote,
        snap = snap,
        site = opts.site,
        customer = opts.customer,
    })

    -- restore it locally so the owner can drive off immediately
    Diag.Restore(veh)
    return true
end

function Diag.Restore(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return end
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleFixed(veh)
    SetVehicleDeformationFixed(veh)
    for i = 0, 5 do
        Mx.Native('SetVehiclePanelStatus', nil, veh, i, 0)
    end
    SetVehicleEngineHealth(veh, 1000.0)
    ClearPedTasks(PlayerPedId())
end

-- ─── Field services the customer can buy at the roadside ─────
function Diag.JumpStart(veh)
    veh = veh or Diag.GetTargetVehicle()
    if veh == 0 then return Mx.Notify('No vehicle in reach', 'error') end
    local snap = Mx.Snapshot(veh)
    if snap.engineHealth > 500.0 then
        return Mx.Notify('That engine turns over fine', 'inform')
    end
    Mx.Progress('JUMP LEADS', 6, ANIM_ALT)
    SetVehicleEngineHealth(veh, math.max(snap.engineHealth, 620.0))
    TriggerServerEvent('grand_mechanic:server:Complete', Mx.Session.active, {
        payout = Config.Fees.repairEngine, wallet = 'cash',
    })
    Mx.Notify('Engine caught — bill them for the visit', 'success')
end

function Diag.ChangeTyres(veh)
    veh = veh or Diag.GetTargetVehicle()
    if veh == 0 then return Mx.Notify('No vehicle in reach', 'error') end

    local anyBurst = false
    for index = 0, 11 do
        if Mx.Native('IsVehicleTyreBurst', false, veh, index, false) then anyBurst = true end
    end
    if not anyBurst then return Mx.Notify('No flat on this car', 'inform') end

    Mx.Progress('TYRE CHANGE', Config.Timing.partsSeconds, ANIM)
    for index = 0, 11 do
        Mx.Native('SetVehicleTyreVariable', nil, veh, index, 0, 1.0)
        SetVehicleTyreFixed(veh, index)
    end
    TriggerServerEvent('grand_mechanic:server:Complete', Mx.Session.active, {
        payout = Config.Fees.repairTires, wallet = 'cash',
    })
    Mx.Notify('All four round and holding pressure', 'success')
end

function Diag.Refuel(veh)
    veh = veh or Diag.GetTargetVehicle()
    if veh == 0 then return Mx.Notify('No vehicle in reach', 'error') end
    local level = GetVehiclePetrolTankHealth(veh) / 1000.0
    if level > 0.9 then return Mx.Notify('Tank is already full', 'inform') end
    Mx.Progress('Jerry can', 5, ANIM_ALT)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    Mx.Native('SetVehicleFuelLevel', nil, veh, 100.0)
    TriggerServerEvent('grand_mechanic:server:Complete', Mx.Session.active, {
        payout = Config.Fees.fuelTopUp, wallet = 'cash',
    })
    Mx.Notify('Top-up done', 'success')
end

function Diag.Unlock(veh)
    veh = veh or Diag.GetTargetVehicle()
    if veh == 0 then return Mx.Notify('No vehicle in reach', 'error') end
    Mx.Progress('AIR WEDGE', 4, { dict = 'anim@heists@stick_caulgun', clip = 'fire' })
    SetVehicleDoorsLocked(veh, 1)
    TriggerServerEvent('grand_mechanic:server:Complete', Mx.Session.active, {
        payout = Config.Fees.unlock, wallet = 'cash',
    })
    Mx.Notify('Doors popped', 'success')
end

-- ─── Site-bound services (bench work, tuning) ────────────────
function Diag.FullService(veh, site)
    if not Mx.IsOnDuty('mechanic') then return Mx.Notify('You are not a mechanic', 'error') end
    veh = veh or Diag.GetTargetVehicle(site and site.radius or 12.0)
    if veh == 0 then return Mx.Notify('Push a vehicle onto the bay', 'error') end

    local snap = Mx.Snapshot(veh)
    local faults = Shared.DeriveFaults(snap)
    local quote = Shared.Quote(faults, snap, Mx.Session.level or 0, 'mechanic')

    if site and site.hasLift then
        Mx.Progress('ON THE LIFT', Config.Timing.repairSeconds, ANIM)
    else
        Mx.Progress('FULL SERVICE', Config.Timing.repairSeconds * 1.4, ANIM)
    end

    SetVehicleFixed(veh)
    SetVehicleEngineHealth(veh, 1000.0)
    SetVehicleBodyHealth(veh, 1000.0)
    SetVehiclePetrolTankHealth(veh, 1000.0)
    SetVehicleDeformationFixed(veh)

    TriggerServerEvent('grand_mechanic:server:Repair', {
        plate = snap.plate, netId = snap.netId, model = snap.modelName,
        faults = #faults > 0 and faults or { { id = 'engine', label = 'Full Service', severity = 0.35 } },
        quote = quote, snap = snap, site = site and site.id,
    })
    Mx.Notify(('%s serviced — bill $%s'):format(snap.plate, Shared.Money(quote.total)), 'success')
end

function Diag.Tune(veh, site)
    if not (site and site.hasTuning) then return Mx.Notify('No dyno at this site', 'error') end
    veh = veh or Diag.GetTargetVehicle(site.radius)
    if veh == 0 then return Mx.Notify('No vehicle on the dyno', 'error') end

    Mx.Progress('DYNO RUN', 14, ANIM)
    SetVehicleModKit(veh, 0)
    ToggleVehicleMod(veh, 11, true)   -- turbo
    SetVehicleEngineHealth(veh, 1000.0)

    TriggerServerEvent('grand_mechanic:server:Bench', {
        plate = Mx.Snapshot(veh).plate, faults = { { id = 'engine', label = 'Dyno Tune', severity = 0.4 } },
        quote = { total = Config.Fees.tune, labour = Config.Fees.tune, parts = 0, tax = 0 },
        site = site.id,
    })
    Mx.Notify(('Dyno complete — $%s'):format(Shared.Money(Config.Fees.tune)), 'success')
end

-- ─── Text helper ──────────────────────────────────────────────
function Diag.LabelFor(partKey)
    local def = partKey and Config.Parts[partKey]
    return def and def.label or 'LABOUR'
end

-- ─── RPC feedback ─────────────────────────────────────────────
RegisterNetEvent('grand_mechanic:client:RepairDone', function(data)
    Mx.Notify(('%s restored — $%s'):format(data.plate or '', Shared.Money((data.quote or {}).total or 0)), 'success')
end)

RegisterNetEvent('grand_mechanic:client:RepairDenied', function(reason)
    Mx.Notify(('Workshop refused the job: %s'):format(reason), 'error')
end)

RegisterNetEvent('grand_mechanic:client:StockSync', function(stock)
    local out = { '^1▚ BENCH STOCK' }
    for part, qty in pairs(stock or {}) do
        local def = Config.Parts[part]
        if def then out[#out + 1] = ('  %-20s ^7%s'):format(def.label, qty) end
    end
    TriggerEvent('chat:addMessage', { multiline = true, args = out })
end)

-- ─── Commands wired straight into the diagnostic tool ────────
RegisterCommand('scan', function() Diag.Scan() end, false)
RegisterCommand('repair', function() Diag.Repair() end, false)
RegisterCommand('flat', function() Diag.ChangeTyres() end, false)
RegisterCommand('jump', function() Diag.JumpStart() end, false)
RegisterCommand('wrench', function(_, args)
    local sub = tostring(args[1] or '')
    local near = Mx.NearSite and Mx.NearSite() or nil

    if sub == 'unlock' then
        Diag.Unlock()
    elseif sub == 'fuel' then
        Diag.Refuel()
    elseif sub == 'service' then
        Diag.FullService(nil, near)
    elseif sub == 'tune' then
        Diag.Tune(nil, near)
    elseif sub == 'buy' then
        TriggerServerEvent('grand_mechanic:server:BuyPart', args[2], args[3])
    elseif sub == 'tool' then
        TriggerServerEvent('grand_mechanic:server:BuyTool', args[2])
    else
        Mx.Notify('usage: /wrench unlock|fuel|service|tune|buy|tool', 'inform')
    end
end, false)

exports('Scan', Diag.Scan)
exports('Repair', Diag.Repair)
exports('Snapshot', Mx.Snapshot)

return Diag
