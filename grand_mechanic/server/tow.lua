-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/server/tow.lua
--  Flatbed authority: attach / winch / tow-in, per-minute accrual
--  while a car rides the bed, hand-off into the hoarding ledger.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local DB = Mechanic.DB
local Jobs = Mechanic.Jobs
local Hoard = Mechanic.Hoard

local Tow = {}
Mechanic.Tow = Tow

local Notify = Jobs.Notify

-- [netId] = { plate, worker, cid, started, fee, job }
local OnBed = {}
Tow.OnBed = OnBed

local function Now()
    return math.floor(os.time())
end

-- ─── Eligibility ──────────────────────────────────────────────
function Tow.Allowed(source)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    if Jobs.CanWork(session.job, 'tow') then return true, session end
    if IsPlayerAceAllowed(source, 'grand.mechanic.impound') then return true, session end
    return false, 'off-duty'
end

-- ─── Attach a vehicle to the flatbed ─────────────────────────
---@param source number
---@param payload table { netId, plate, model, coords, job }
function Tow.Attach(source, payload)
    local ok, session = Tow.Allowed(source)
    if not ok then return false, session end

    payload = type(payload) == 'table' and payload or {}
    local netId = tonumber(payload.netId) or 0
    if netId == 0 then return false, 'no-vehicle' end

    local plate = Shared.NormalisePlate(payload.plate)
    if plate == '' then return false, 'no-plate' end

    if OnBed[netId] then return false, 'already-loaded' end
    if not Jobs.Throttle(source, 'tow-attach', 3) then return false, 'slow-down' end

    local existing = DB.HoardForPlate(plate)
    if existing then return false, 'already-hoarded' end

    local fee = Config.Fees.flatbed
    local distance
    local site = Shared.NearestSite(payload.coords or vector3(0, 0, 0), session.job, { 'towing', 'hoarding' })
    if site then
        fee, distance = Shared.TravelFee(site.coords, payload.coords, Config.Fees.taxiPerKm)
        fee = fee + Config.Fees.flatbed
    end

    local record = {
        netId = netId,
        plate = plate,
        model = tostring(payload.model or 'unknown'),
        cid = session.cid,
        worker = source,
        started = Now(),
        fee = Shared.Money(fee),
        site = site and site.id or nil,
        coords = payload.coords,
        job = payload.job,
        unpaid = false,
    }

    OnBed[netId] = record
    DB.LogTampering(session.cid, plate, 'tow-attach', record.site, false)

    TriggerClientEvent('grand_mechanic:client:TowAttached', -1, {
        netId = netId, plate = plate, cid = session.cid, fee = record.fee, site = record.site,
    })

    Notify(source, ('Winched %s — meter running at $%s/min'):format(plate, Config.Legal.towFeePerMinute), 'info')
    return true, record
end

-- ─── Detach / drop off ───────────────────────────────────────
function Tow.Detach(source, netId, opts)
    opts = type(opts) == 'table' and opts or {}
    netId = tonumber(netId) or 0
    local record = OnBed[netId]
    if not record then return false, 'not-loaded' end

    local minutes = math.max(1, math.ceil((Now() - record.started) / 60))
    local accrued = minutes * Config.Legal.towFeePerMinute
    local total = Shared.Money(record.fee + accrued)

    OnBed[netId] = nil
    TriggerClientEvent('grand_mechanic:client:TowDetached', -1, { netId = netId, plate = record.plate })

    -- if it is being dropped into a yard, book it into the hoarding ledger
    if opts.hoard then
        local ok, result = Hoard.Store(source, {
            plate = record.plate,
            model = record.model,
            site = opts.site or record.site,
            coords = opts.coords or record.coords,
            fee = total,
            job = record.job,
        })
        if not ok then
            DB.LogTampering(record.cid, record.plate, 'tow-drop', record.site, false)
            return false, result
        end
        Notify(source, ('%s booked in — invoice $%s (%d min on the bed)'):format(
            record.plate, Shared.Money(total), minutes), 'success')
        return true, { hoard = result, total = total, minutes = minutes }
    end

    return true, { total = total, minutes = minutes, plate = record.plate }
end

-- ─── Bill the customer for a completed tow ───────────────────
function Tow.Settle(source, netId, opts)
    opts = type(opts) == 'table' and opts or {}
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end

    local record = OnBed[tonumber(netId) or 0]
    if not record then return false, 'not-loaded' end

    local minutes = math.max(1, math.ceil((Now() - record.started) / 60))
    local total = Shared.Money(record.fee + minutes * Config.Legal.towFeePerMinute)

    local payer = tonumber(opts.customer) or 0
    if payer > 0 and payer ~= source then
        if Jobs.Money(payer, 'cash') >= total then
            if not Jobs.Take(payer, 'cash', total, 'tow:' .. record.plate) then
                return false, 'payment-failed'
            end
        else
            DB.CreateInvoice({
                ref = Shared.Id('inv'), kind = 'tow', job = record.job,
                customer = Jobs.CitizenId(payer), worker = session.cid, plate = record.plate,
                lines = { { label = 'Flatbed recovery', cost = record.fee },
                          { label = ('%d minutes on the bed'):format(minutes), cost = minutes * Config.Legal.towFeePerMinute } },
                labour = total, parts = 0, tax = Shared.Money(total * Config.TaxRate),
                total = Shared.Money(total * (1 + Config.TaxRate)),
            })
            Notify(payer, ('Tow invoice issued for %s — settle at any yard'):format(record.plate), 'warning')
        end
    end

    local crew = math.floor(total * (Config.PaySplit.tow or 0.78))
    Jobs.Pay(source, 'cash', crew, 'tow:' .. record.plate)
    Jobs.RegisterAction(source, 'tow', crew)

    Tow.Detach(source, netId, { hoard = opts.hoard, site = opts.site, coords = opts.coords })
    TriggerClientEvent('grand_mechanic:client:TowSettled', source, {
        plate = record.plate, total = total, crew = crew, minutes = minutes,
    })
    return true, { total = total, crew = crew }
end

-- ─── Recover an abandoned / wrecked vehicle ──────────────────
function Tow.Scrap(source, netId, plate)
    local ok, session = Tow.Allowed(source)
    if not ok then return false, session end

    plate = Shared.NormalisePlate(plate)
    if plate == '' then return false, 'no-plate' end
    if not Jobs.Throttle(source, 'scrap', 12) then return false, 'slow-down' end

    local row = DB.CharacterByPlate(plate)
    if row and row.state == 2 then return false, 'already-impounded' end

    local lot = Hoard.NearestImpound(session.coords or GetEntityCoords(GetPlayerPed(source)))
    DB.Hoard({
        ref = Shared.Id('hoard'),
        site = (lot and lot.id or 'righer_lot'),
        plate = plate,
        model = (row and row.model) or 'unknown',
        storedBy = session.cid,
        owner = row and row.citizenid or nil,
        fees = (lot and lot.fee or 350),
        hourly = math.floor((lot and lot.fee or 350) / 6),
        state = 'impounded',
    })
    DB.SetVehicleState(plate, 2, (lot and lot.id or 'righer_lot'))
    DB.LogTampering(session.cid, plate, 'scrap', lot and lot.id, false)

    Jobs.Pay(source, 'cash', Config.Fees.flatbed, 'scrap-bounty')
    Notify(source, ('%s crushed and claimed — $%s'):format(plate, Shared.Money(Config.Fees.flatbed)), 'success')
    return true
end

-- ─── Meter loop: warn on long unpaid rides ───────────────────
CreateThread(function()
    Wait(30000)
    while true do
        for netId, record in pairs(OnBed) do
            local minutes = math.ceil((Now() - record.started) / 60)
            if minutes >= 20 and not record.warned then
                record.warned = true
                Notify(record.worker, ('%s has been on your bed %d minutes — settle it or drop it'):format(
                    record.plate, minutes), 'error')
            end
            if minutes >= 45 then
                OnBed[netId] = nil
                TriggerClientEvent('grand_mechanic:client:TowDetached', -1, { netId = netId, plate = record.plate })
                DB.LogTampering(record.cid, record.plate, 'tow-abandoned', record.site, false)
            end
        end
        Wait(20000)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    for netId, record in pairs(OnBed) do
        if record.worker == src then OnBed[netId] = nil end
    end
end)

-- ─── RPC ──────────────────────────────────────────────────────
RegisterNetEvent('grand_mechanic:server:TowAttach', function(payload)
    local src = tonumber(source)
    if not src then return end
    local ok, result = Tow.Attach(src, payload)
    if not ok then Notify(src, ('Cannot hook that vehicle: %s'):format(tostring(result)), 'error') end
end)

RegisterNetEvent('grand_mechanic:server:TowDetach', function(netId, opts)
    local src = tonumber(source)
    if not src then return end
    Tow.Detach(src, netId, opts)
end)

RegisterNetEvent('grand_mechanic:server:TowSettle', function(netId, opts)
    local src = tonumber(source)
    if not src then return end
    local ok, result = Tow.Settle(src, netId, opts)
    if not ok then Notify(src, ('Tow settle failed: %s'):format(tostring(result)), 'error') end
end)

RegisterNetEvent('grand_mechanic:server:TowScrap', function(netId, plate)
    local src = tonumber(source)
    if not src then return end
    Tow.Scrap(src, netId, plate)
end)

RegisterNetEvent('grand_mechanic:server:TowMeter', function()
    local src = tonumber(source)
    if not src then return end
    local out = {}
    for netId, record in pairs(OnBed) do
        out[#out + 1] = {
            netId = netId, plate = record.plate, cid = record.cid,
            minutes = math.ceil((Now() - record.started) / 60), fee = record.fee,
        }
    end
    TriggerClientEvent('grand_mechanic:client:TowMeter', src, out)
end)

exports('Attach', Tow.Attach)
exports('Detach', Tow.Detach)
exports('Allowed', Tow.Allowed)

return Tow
