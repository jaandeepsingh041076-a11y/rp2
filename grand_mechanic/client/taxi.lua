-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/taxi.lua
--  Cab side of the workforce: live call markers on the street,
--  the meter overlay, route drop-off points, receipts in chat.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local Mx = Mechanic.Client

local Cab = {}
Mechanic.Cab = Cab

Cab.Calls = {}          -- [ref] = public call record
Cab.Run = nil           -- current job
local callMarkers = {}

-- ─── Call handling ───────────────────────────────────────────
RegisterNetEvent('grand_mechanic:client:TaxiCall', function(call)
    Cab.Calls[call.ref] = call
    Cab.RebuildMarkers()
    if Mx.IsOnDuty('taxi') then
        Mx.Notify(('Fare %s → %s  $%s'):format(
            call.dest, Shared.Money(call.fare), call.ref:sub(1, 8)), 'info')
        PlaySoundFrontend(-1, 'Check', 'HUD_FRONTEND_DEFAULT_SOUNDSET', false)
    end
end)

RegisterNetEvent('grand_mechanic:client:TaxiCallGone', function(ref)
    Cab.Calls[ref] = nil
    Cab.RebuildMarkers()
end)

RegisterNetEvent('grand_mechanic:client:TaxiBoard', function(rows)
    Cab.Calls = {}
    for _, call in ipairs(rows or {}) do Cab.Calls[call.ref] = call end
    Cab.RebuildMarkers()
    Cab.PrintBoard()
end)

function Cab.PrintBoard()
    local lines = { '^1▚ CAB DISPATCH' }
    local count = 0
    for _, call in pairs(Cab.Calls) do
        if not call.driver then
            count = count + 1
            lines[#lines + 1] = ('  ^3/taxi take %s ^7→ %s  ^1$%s ^7(%dm)'):format(
                call.ref:sub(1, 10), call.dest, Shared.Money(call.fare), math.floor(call.waiting or 0))
        end
    end
    if count == 0 then lines[#lines + 1] = '^7  nothing on the board' end
    TriggerEvent('chat:addMessage', { multiline = true, args = lines })
end

-- ─── World markers for open calls ────────────────────────────
function Cab.RebuildMarkers()
    for _, h in ipairs(callMarkers) do Mx.Remove(h) end
    callMarkers = {}

    if not Mx.IsOnDuty('taxi') then return end

    local pos = GetEntityCoords(PlayerPedId())
    for ref, call in pairs(Cab.Calls) do
        if not call.driver then
            local coords = vector3(call.x, call.y, call.z)
            if #(pos - coords) <= Config.Ranges.dispatchScan then
                local h = Mx.Add(coords, 6.0,
                    ('FARE → %s ($%s) [ accept ]'):format(call.dest, Shared.Money(call.fare)),
                    function() Cab.Take(ref) end, { key = 'E' })
                callMarkers[#callMarkers + 1] = h
            end
        end
    end
end

CreateThread(function()
    while true do
        Wait(12000)
        Cab.RebuildMarkers()
    end
end)

function Cab.Take(ref)
    if Cab.Run then return Mx.Notify('Finish the fare you already have', 'error') end
    TriggerServerEvent('grand_mechanic:server:TaxiAccept', ref)
end

RegisterNetEvent('grand_mechanic:client:TaxiAccepted', function(data)
    Cab.Run = { ref = data.ref, driver = data.driver, fare = data.fare, dest = data.dest, started = GetGameTimer() }
    Cab.Blip = nil
    Cab.DestBlip = Cab.AddNavBlip(data)
    Mx.Notify(('Pickup accepted — %s is waiting'):format(data.dest), 'success')
    PlaySoundFrontend(-1, 'Event_Start_Text', 'GTAO_FM_Events_Soundset', true)
end)

function Cab.AddNavBlip(data)
    if not data.coords then return nil end
    local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
    SetBlipSprite(blip, 476)
    SetBlipColour(blip, 5)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Pickup — ' .. (data.dest or 'customer'))
    EndTextCommandSetBlipName(blip)
    return blip
end

-- ─── Meter ───────────────────────────────────────────────────
function Cab.ToggleMeter()
    if not Cab.Run then return Mx.Notify('No fare running', 'error') end
    Cab.Run.running = not Cab.Run.running
    TriggerServerEvent('grand_mechanic:server:TaxiMeter', Cab.Run.ref, Cab.Run.running)
    Mx.Notify(Cab.Run.running and 'Meter ON' or 'Meter HELD', 'info')
end

CreateThread(function()
    while true do
        Wait(0)
        if Cab.Run and Cab.Run.running then
            local secs = math.floor((GetGameTimer() - Cab.Run.started) / 1000)
            local owed = Cab.Run.fare + math.floor(secs / 10) * Config.Fees.taxiWait
            SetTextFont(4)
            SetTextScale(0.0, 0.42)
            SetTextColour(255, 188, 0, 240)
            SetTextOutline()
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(('METER  $%s'):format(Shared.Money(owed)))
            EndTextCommandDisplayText(0.86, 0.05)
        end
    end
end)

-- ─── Drop off / collect ─────────────────────────────────────
function Cab.DropOff(rating)
    if not Cab.Run then return Mx.Notify('No fare running', 'error') end
    local ref = Cab.Run.ref
    TriggerServerEvent('grand_mechanic:server:TaxiDrop', { ref = ref, tip = 0, rating = rating or 0 })
    Cab.ClearRun()
end

function Cab.ClearRun()
    Cab.Run = nil
    if Cab.DestBlip then RemoveBlip(Cab.DestBlip) Cab.DestBlip = nil end
end

RegisterNetEvent('grand_mechanic:client:TaxiEnded', function(data)
    if data.receipt then
        TriggerEvent('chat:addMessage', { args = { ('^1FARE RECEIPT ^7— $%s paid'):format(Shared.Money(data.total or 0)) } })
    else
        Mx.Notify(('Fare closed — $%s banked'):format(Shared.Money(data.crew or 0)), 'success')
        Cab.ClearRun()
    end
end)

-- ─── Fixed-fare routes from a rank ──────────────────────────
function Cab.Route(id)
    for _, route in ipairs(Config.TaxiRoutes) do
        if route.id == id then
            TriggerServerEvent('grand_mechanic:server:TaxiCall', {
                coords = GetEntityCoords(PlayerPedId()),
                dest = route.to, destLabel = route.name, route = route.id,
            })
            Mx.Notify(('Booking the %s run — $%s'):format(route.name, Shared.Money(route.fare)), 'info')
            return true
        end
    end
    return false, 'unknown route'
end

function Cab.RankPoints()
    local out = {}
    local pos = GetEntityCoords(PlayerPedId())
    for _, site in ipairs(Config.Locations) do
        if site.kind == 'taxi' then
            out[#out + 1] = { site = site, dist = #(pos - site.coords) }
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

-- ─── Passengers: hail the nearest cab ────────────────────────
function Cab.Hail(dest)
    local pos = GetEntityCoords(PlayerPedId())
    TriggerServerEvent('grand_mechanic:server:TaxiCall', {
        coords = pos, dest = dest, destLabel = dest and 'picked destination' or 'Downtown',
        note = 'street hail',
    })
end

RegisterCommand('taxi', function(_, args)
    local sub = tostring(args[1] or 'hail'):lower()
    if sub == 'call' or sub == 'hail' then
        Cab.Hail(nil)
    elseif sub == 'board' then
        TriggerServerEvent('grand_mechanic:server:TaxiBoard')
    elseif sub == 'take' then
        Cab.Take(args[2] or '')
    elseif sub == 'meter' then
        Cab.ToggleMeter()
    elseif sub == 'drop' or sub == 'finish' then
        Cab.DropOff(tonumber(args[2]))
    elseif sub == 'cancel' then
        TriggerServerEvent('grand_mechanic:server:TaxiCancel')
        Cab.ClearRun()
    elseif sub == 'route' then
        if not Cab.Route(args[2] or '') then
            local lines = { '^1▚ FIXED RUNS' }
            for _, r in ipairs(Config.TaxiRoutes) do
                lines[#lines + 1] = ('  ^3/taxi route %s ^7%s  $%s'):format(r.id, r.name, Shared.Money(r.fare))
            end
            TriggerEvent('chat:addMessage', { multiline = true, args = lines })
        end
    else
        TriggerServerEvent('grand_mechanic:server:TaxiBoard')
    end
end, false, { help = 'hail | board | take <ref> | meter | drop | route <id>' })

RegisterCommand('cabmeter', Cab.ToggleMeter, false)
RegisterKeyMapping('cabmeter', 'Grand RP: taxi meter on/off', 'keyboard', 'F10')

RegisterCommand('cabdrop', function() Cab.DropOff(0) end, false)
RegisterKeyMapping('cabdrop', 'Grand RP: end the fare', 'keyboard', 'F11')

exports('Hail', Cab.Hail)
exports('Take', Cab.Take)

return Cab
