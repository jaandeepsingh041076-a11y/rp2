-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/server/taxi.lua
--  Dispatch board, fixed-fare routes, metered jobs, and the
--  fare settlement loop. Drivers see calls, customers get picked up.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local DB = Mechanic.DB
local Jobs = Mechanic.Jobs

local Taxi = {}
Mechanic.Taxi = Taxi

local Notify = Jobs.Notify

local function Now()
    return math.floor(os.time())
end

-- [ref] = call record
local Calls = {}
Taxi.Calls = Calls

-- [cid] = { ref, started, meter, drop }
local Active = {}
Taxi.Active = Active

local RouteById = {}
for _, r in ipairs(Config.TaxiRoutes) do RouteById[r.id] = r end
Taxi.Routes = RouteById

-- ─── Post a call ─────────────────────────────────────────────
function Taxi.Call(source, payload)
    payload = type(payload) == 'table' and payload or {}
    local coords = payload.coords or GetEntityCoords(GetPlayerPed(source))
    local ref = Shared.Id('taxi')

    local call = {
        ref = ref,
        customer = source,
        customerCid = Jobs.CitizenId(source),
        coords = coords,
        dest = payload.dest,
        destLabel = tostring(payload.destLabel or 'Downtown'),
        route = RouteById[tostring(payload.route or '')],
        driver = nil,
        started = Now(),
        base = Config.Fees.taxiBase,
        note = string.sub(tostring(payload.note or ''), 1, 90),
    }

    if call.route then
        call.fare = call.route.fare
        call.dest = call.route.to
        call.destLabel = call.route.name
    else
        local fee = Config.Fees.taxiBase
        if payload.dest then
            fee = fee + Shared.TravelFee(coords, payload.dest, Config.Fees.taxiPerKm)
        end
        call.fare = Shared.Money(fee)
    end

    Calls[ref] = call

    -- broadcast to every cab on the street
    for src, session in pairs(Jobs.Sessions) do
        if Jobs.CanWork(session.job, 'taxi') then
            TriggerClientEvent('grand_mechanic:client:TaxiCall', src, Taxi.Public(call))
        end
    end

    Notify(source, ('Cab dispatched — fare about $%s'):format(Shared.Money(call.fare)), 'info')

    CreateThread(function()
        Wait(Config.Timing.taxiDispatchRtt * 1000)
        if Calls[ref] and not Calls[ref].driver then
            Calls[ref] = nil
            Notify(source, 'No cab answered your call', 'error')
        end
    end)

    return true, call
end

function Taxi.Public(call)
    if not call then return nil end
    return {
        ref = call.ref, x = call.coords.x, y = call.coords.y, z = call.coords.z,
        dest = call.destLabel, fare = call.fare, route = call.route and call.route.id or nil,
        note = call.note, waiting = Now() - call.started, driver = call.driver,
    }
end

-- ─── Driver accepts ──────────────────────────────────────────
function Taxi.Accept(source, ref)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    if not Jobs.CanWork(session.job, 'taxi') then return false, 'off-duty' end

    local call = Calls[tostring(ref or '')]
    if not call then return false, 'gone' end
    if call.driver then return false, 'taken' end
    if not Jobs.Throttle(source, 'taxi-accept', 2) then return false, 'slow-down' end

    call.driver = source
    call.started = Now()
    Active[session.cid] = { ref = call.ref, started = Now(), meter = 0, pickup = call.coords, drop = call.dest }

    TriggerClientEvent('grand_mechanic:client:TaxiAccepted', call.customer, {
        ref = call.ref, driver = GetPlayerName(source), fare = call.fare, dest = call.destLabel,
    })
    for src in pairs(Jobs.Sessions) do
        if src ~= source then
            TriggerClientEvent('grand_mechanic:client:TaxiCallGone', src, call.ref)
        end
    end

    DB.CreateJob({
        ref = call.ref, kind = 'taxi', vehicle = 'taxi', plate = '',
        model = 'taxi', coords = DB.CoordsToString(call.coords),
        site = 'taxi', customer = call.customerCid, worker = session.cid,
        estimate = call.fare, faults = {},
    })
    return true, call
end

-- ─── Start / stop the meter ──────────────────────────────────
function Taxi.Meter(source, ref, start)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    local run = Active[session.cid]
    if not run or run.ref ~= tostring(ref or '') then return false, 'not-your-call' end

    if start then
        run.meterStarted = Now()
    else
        if run.meterStarted then
            local idle = math.max(0, Now() - run.meterStarted)
            run.meter = run.meter + math.floor(idle / 10) * Config.Fees.taxiWait
            run.meterStarted = nil
        end
    end
    return true, run.meter
end

-- ─── Drop the passenger off and collect ─────────────────────
function Taxi.DropOff(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    payload = type(payload) == 'table' and payload or {}

    local run = Active[session.cid]
    if not run then return false, 'no-call' end
    local call = Calls[run.ref]
    if not call then return false, 'gone' end

    local total = Shared.Money((call.fare or 0) + (run.meter or 0))
    local tip = Shared.Clamp(math.floor(tonumber(payload.tip) or 0), 0, 500)

    if call.customer and call.customer > 0 and GetPlayerPing(call.customer) then
        local payable = Jobs.Money(call.customer, 'cash')
        if payable >= total then
            Jobs.Take(call.customer, 'cash', total, 'taxi:' .. call.ref)
        else
            -- they pay what they carry, the rest is a bad-debt write-off
            total = Shared.Money(math.max(0, payable))
            if total > 0 then Jobs.Take(call.customer, 'cash', total, 'taxi-partial') end
            Notify(call.customer, 'You could not cover the fare', 'error')
            Notify(source, 'Short-paid fare', 'warning')
        end
    end

    local crew = Shared.Money(total * (Config.PaySplit.taxi or 0.80))
    Jobs.Pay(source, 'cash', crew, 'taxi-fare')
    if tip > 0 then Jobs.Pay(source, 'cash', tip, 'tip') end
    Jobs.RegisterAction(source, 'taxi', crew)

    local rating = tonumber(payload.rating)
    if rating and rating >= 4 then
        MySQL.update.await('UPDATE grand_mechanic_jobs SET payout = payout + ? WHERE job_ref = ?', { crew, call.ref })
    end

    Calls[run.ref] = nil
    Active[session.cid] = nil
    DB.FinishJob(call.ref, total)

    TriggerClientEvent('grand_mechanic:client:TaxiEnded', source, {
        ref = call.ref, total = total, crew = crew, tip = tip,
    })
    if call.customer then
        TriggerClientEvent('grand_mechanic:client:TaxiEnded', call.customer, {
            ref = call.ref, total = total, receipt = true,
        })
    end
    return true, { total = total, crew = crew, tip = tip }
end

function Taxi.Cancel(source)
    local session = Jobs.Get(source)
    if not session then return false end
    local run = Active[session.cid]
    if not run then return false end
    local call = Calls[run.ref]
    if call and call.customer then
        Notify(call.customer, 'Your cab cancelled the ride', 'error')
    end
    Calls[run.ref] = nil
    Active[session.cid] = nil
    return true
end

-- ─── Expire unanswered calls ─────────────────────────────────
CreateThread(function()
    Wait(20000)
    while true do
        for ref, call in pairs(Calls) do
            if not call.driver and (Now() - call.started) > 120 then
                Calls[ref] = nil
            end
        end
        Wait(15000)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    for ref, call in pairs(Calls) do
        if call.customer == src then Calls[ref] = nil end
        if call.driver == src then call.driver = nil end
    end
    local session = Jobs.Sessions[src]
    if session then Active[session.cid] = nil end
end)

-- ─── RPC ──────────────────────────────────────────────────────
RegisterNetEvent('grand_mechanic:server:TaxiCall', function(payload)
    local src = tonumber(source)
    if not src then return end
    Taxi.Call(src, payload)
end)

RegisterNetEvent('grand_mechanic:server:TaxiAccept', function(ref)
    local src = tonumber(source)
    if not src then return end
    local ok, result = Taxi.Accept(src, ref)
    if not ok then Notify(src, ('Cannot take that fare: %s'):format(tostring(result)), 'error') end
end)

RegisterNetEvent('grand_mechanic:server:TaxiMeter', function(ref, start)
    local src = tonumber(source)
    if not src then return end
    Taxi.Meter(src, ref, start)
end)

RegisterNetEvent('grand_mechanic:server:TaxiDrop', function(payload)
    local src = tonumber(source)
    if not src then return end
    Taxi.DropOff(src, payload)
end)

RegisterNetEvent('grand_mechanic:server:TaxiCancel', function()
    local src = tonumber(source)
    if not src then return end
    Taxi.Cancel(src)
end)

RegisterNetEvent('grand_mechanic:server:TaxiBoard', function()
    local src = tonumber(source)
    if not src then return end
    local out = {}
    for _, call in pairs(Calls) do
        if not call.driver then out[#out + 1] = Taxi.Public(call) end
    end
    TriggerClientEvent('grand_mechanic:client:TaxiBoard', src, out)
end)

exports('Call', Taxi.Call)
exports('Active', function(cid) return Active[cid] end)

return Taxi
