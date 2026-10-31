-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/server/main.lua
--  Boot, schema, session wiring, chat commands, exports.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local DB = Mechanic.DB
local Jobs = Mechanic.Jobs
local Tools = Mechanic.Tools
local Hoard = Mechanic.Hoard
local Tow = Mechanic.Tow
local Jack = Mechanic.Jack
local Taxi = Mechanic.Taxi

local Log = DB.Log
local Notify = Jobs.Notify

-- ─── Startup ──────────────────────────────────────────────────
CreateThread(function()
    DB.CreateSchema()

    local partCount = 0
    for _ in pairs(Config.Parts) do partCount = partCount + 1 end

    -- any player already in when the resource starts gets a session
    for _, src in ipairs(GetPlayers()) do
        local id = tonumber(src)
        if id then
            local session = Jobs.Attach(id)
            if session then
                TriggerClientEvent('grand_mechanic:client:Session', id, {
                    cid = session.cid, job = session.job, xp = session.xp, level = session.level,
                    active = session.active, outstanding = math.floor(DB.OutstandingTotal(session.cid)),
                })
            end
        end
    end

    Log('info', ('workforce online — %d sites, %d impounds, %d parts')
        :format(#Config.Locations, #Config.Impound, partCount))
end)

AddEventHandler('playerSpawned', function()
    local src = tonumber(source)
    if not src then return end
    CreateThread(function()
        Wait(1500)
        Jobs.Attach(src)
    end)
end)

RegisterNetEvent('grand_mechanic:server:RequestSession', function()
    local src = tonumber(source)
    if not src then return end
    local session = Jobs.Attach(src)
    if not session then return end
    TriggerClientEvent('grand_mechanic:client:Session', src, {
        cid = session.cid, job = session.job, xp = session.xp, level = session.level,
        active = session.active, outstanding = math.floor(DB.OutstandingTotal(session.cid)),
    })
    TriggerClientEvent('grand_mechanic:client:JobSync', src, Jobs.Snapshot())
end)

-- refresh the cached job name after a clock-in / promotion elsewhere
RegisterNetEvent('grand_mechanic:server:RefreshJob', function()
    local src = tonumber(source)
    if not src then return end
    local session = Jobs.Sessions[src]
    if not session then return end
    session.job = Jobs.JobName(src)
end)

-- ─── Invoice settlement ───────────────────────────────────────
RegisterNetEvent('grand_mechanic:server:PayInvoice', function(ref, method)
    local src = tonumber(source)
    if not src then return end
    local session = Jobs.Sessions[src]
    if not session then return end

    local inv = DB.InvoiceByRef(tostring(ref or ''))
    if not inv then return Notify(src, 'Invoice not found', 'error') end
    if inv.paid == 1 then return Notify(src, 'That invoice is already settled', 'warning') end
    if inv.customer_cid ~= session.cid and not IsPlayerAceAllowed(src, 'grand.mechanic.waive') then
        return Notify(src, 'That is not your debt', 'error')
    end

    local kind = (method == 'bank') and 'bank' or 'cash'
    if Jobs.Money(src, kind) < (tonumber(inv.total) or 0) then
        return Notify(src, 'Not enough money in that wallet', 'error')
    end
    if not Jobs.Take(src, kind, math.floor(inv.total), 'invoice:' .. inv.invoice_ref) then
        return Notify(src, 'Payment failed', 'error')
    end
    if not DB.SettleInvoice(inv.invoice_ref, kind) then
        Jobs.Pay(src, kind, math.floor(inv.total), 'invoice-refund')
        return Notify(src, 'Invoice already settled', 'error')
    end

    local worker = Jobs.CitizenId(src)
    if worker ~= inv.worker_cid and inv.worker_cid then
        Jobs.Pay(src, 'bank', math.floor(inv.total * 0.6), 'invoice-cleared-late')
    end

    Notify(src, ('Invoice %s settled — $%s'):format(inv.invoice_ref, Shared.Money(inv.total)), 'success')
end)

RegisterNetEvent('grand_mechanic:server:MyInvoices', function()
    local src = tonumber(source)
    if not src then return end
    local session = Jobs.Sessions[src]
    if not session then return end
    local rows = DB.UnpaidInvoices(session.cid)
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            ref = r.invoice_ref, kind = r.kind, plate = r.plate or '', total = math.floor(r.total or 0),
            created = math.floor(r.created_at or 0), expires = math.floor(r.expires or 0),
        }
    end
    TriggerClientEvent('grand_mechanic:client:InvoiceList', src, out, math.floor(DB.OutstandingTotal(session.cid)))
end)

-- ─── Stats / leaderboard ──────────────────────────────────────
RegisterNetEvent('grand_mechanic:server:Stats', function(field)
    local src = tonumber(source)
    if not src then return end
    local rows = DB.Leaderboard(tostring(field or 'xp'), 20)
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            cid = r.citizenid, name = (r.firstname or '—') .. ' ' .. (r.lastname or ''),
            level = math.floor(r.level or 0), score = math.floor(r.score or 0),
        }
    end
    TriggerClientEvent('grand_mechanic:client:Leaderboard', src, out)
end)

-- ─── Commands ─────────────────────────────────────────────────
RegisterCommand('mechanic', function(src, args)
    local command = tostring(args[1] or 'board'):lower()
    if src == 0 then return print('[grand_mechanic] this command is in-game only') end

    if command == 'board' then
        TriggerClientEvent('grand_mechanic:client:OpenBoard', src, Jobs.Snapshot())
    elseif command == 'invoices' then
        TriggerClientEvent('grand_mechanic:server:MyInvoices', src)
    elseif command == 'claim' then
        Jobs.Claim(src, tostring(args[2] or ''))
    elseif command == 'abandon' then
        Jobs.Abandon(src)
    elseif command == 'yard' then
        Hoard.Listing(src)
    elseif command == 'plate' then
        Hoard.PlateLookup(src, tostring(args[2] or ''))
    elseif command == 'lookup' then
        TriggerClientEvent('grand_mechanic:client:JackBoard', src, DB.TamperingRecent(tonumber(args[2]) or 30))
    elseif command == 'stats' then
        TriggerClientEvent('grand_mechanic:server:Stats', src, args[2] or 'xp')
    elseif command == 'fleet' then
        TriggerClientEvent('grand_mechanic:client:FleetSpawn', src, tostring(args[2] or 'flatbed'))
    else
        TriggerClientEvent('grand_mechanic:client:OpenBoard', src, Jobs.Snapshot())
    end
end, false, { help = 'Workforce console: board | claim | abandon | invoices | yard | plate | stats | fleet' })

RegisterCommand('taxi', function(src, args)
    if src == 0 then return end
    local sub = tostring(args[1] or 'call'):lower()
    if sub == 'call' then
        local coords = GetEntityCoords(GetPlayerPed(src))
        Taxi.Call(src, { coords = coords, dest = nil, note = 'street hail' })
    else
        TriggerClientEvent('grand_mechanic:client:TaxiBoard', src, {})
        TriggerClientEvent('grand_mechanic:server:TaxiBoard', src)
    end
end, false, { help = 'Hail a cab, or open the cab dispatch board' })

RegisterCommand('impound', function(src, args)
    if src == 0 then return end
    local session = Jobs.Sessions[src]
    if not session then
        Jobs.Attach(src)
        session = Jobs.Sessions[src]
    end
    if not session then return end

    local plate = Shared.NormalisePlate(args[1] or '')
    if plate == '' then
        local coords = GetEntityCoords(GetPlayerPed(src))
        local lot = Hoard.NearestImpound(coords)
        TriggerClientEvent('grand_mechanic:client:ImpoundOpen', src, {
            id = lot and lot.id, name = lot and lot.name, fee = lot and lot.fee,
            listing = Hoard.Listing(src),
        })
        return
    end

    local hoard = DB.HoardForPlate(plate)
    if not hoard then
        return Notify(src, ('%s is not in any yard'):format(plate), 'error')
    end
    if not IsPlayerAceAllowed(src, 'grand.mechanic.impound')
        and session.cid ~= hoard.owner_cid and session.cid ~= hoard.stored_by then
        return Notify(src, 'You do not hold the paperwork for that vehicle', 'error')
    end

    local ok, result = Hoard.Release(src, hoard.hoard_ref, args[2] or 'cash')
    if not ok then Notify(src, ('Cannot release %s: %s'):format(plate, tostring(result)), 'error') end
end, false, { help = 'Open the nearest impound, or release a plate: /impound [plate] [cash|bank]' })

local function IllegalSiteNames()
    local out = {}
    for id, site in pairs(Jack.Sites) do
        out[#out + 1] = { id = id, name = site.name, coords = site.coords, cut = site.resaleCut }
    end
    return out
end

RegisterCommand('chop', function(src, args)
    if src == 0 then return end
    local sub = tostring(args[1] or ''):lower()
    if sub == 'respray' then
        Jack.Respray(src, { plate = args[2], site = args[3], model = args[4] })
    elseif sub == 'sell' then
        Jack.Sell(src, { plate = args[2], site = args[3] })
    elseif sub == 'strip' then
        Jack.Strip(src, { plate = args[2], site = args[3] })
    else
        TriggerClientEvent('grand_mechanic:client:ChopOpen', src, IllegalSiteNames())
    end
end, false, { help = 'Chop shop: respray | strip | sell' })

-- ─── Admin glue ───────────────────────────────────────────────
RegisterCommand('mechtest', function(_, args)
    local what = tostring(args[1] or 'schema')
    if what == 'schema' then
        DB.CreateSchema()
    elseif what == 'sweep' then
        print(('swept %d stale jobs'):format(DB.SweepStaleJobs(tonumber(args[2]) or 1800) or 0))
    elseif what == 'fees' then
        print(('accrued fees on %d rows'):format(DB.AccrueHoardFees() or 0))
    elseif what == 'invoices' then
        for _, r in ipairs(DB.LateInvoiceReport()) do
            print(('%s  $%s  %s  %s %s'):format(r.invoice_ref, r.total, r.plate or '', r.firstname or '?', r.lastname or '?'))
        end
    elseif what == 'tampering' then
        for _, r in ipairs(DB.TamperingRecent(tonumber(args[2]) or 30)) do
            print(('%s  %s  %s  %s'):format(os.date('%H:%M', r.created_at), r.citizenid, r.plate, r.action))
        end
    end
end, true)

AddCommand('grand_mechanic', function(src)
    TriggerClientEvent('grand_mechanic:client:OpenBoard', src, Jobs.Snapshot())
end)

-- ─── Exports (see GRAND_SPEC.lua) ─────────────────────────────
exports('Board', Jobs.Snapshot)
exports('CreateJob', function(source, kind, payload) return Jobs.Create(source, kind, payload) end)
exports('Quote', function(faults, snap, level, kind) return Shared.Quote(faults, snap, level, kind) end)
exports('DeriveFaults', function(snap) return Shared.DeriveFaults(snap) end)
exports('Store', Hoard.Store)
exports('Release', Hoard.Release)
exports('Listing', Hoard.Listing)
exports('TowAttach', Tow.Attach)
exports('TowDetach', Tow.Detach)
exports('Hotwire', Jack.Hotwire)
exports('Respray', Jack.Respray)
exports('TaxiCall', Taxi.Call)
exports('Sites', function() return Config.Locations end)
exports('Impounds', function() return Config.Impound end)
exports('HasItem', Tools.HasItem)
exports('AddItem', Tools.AddItem)
exports('RemoveItem', Tools.RemoveItem)
exports('Stats', function(cid) return DB.Stats(cid) end)
exports('Outstanding', function(cid) return DB.OutstandingTotal(cid) end)
exports('Session', function(source) return Jobs.Sessions[tonumber(source)] end)

Log('info', 'server modules loaded: jobs, tools, hoarding, tow, jack, taxi')
