-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/server/jack.lua
--  Illegal side of the workforce: hotwire, strip, respray, resale.
--  Every action is journalled to grand_vehicle_tampering so the
--  police resource can pull a live board of recent reports.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local DB = Mechanic.DB
local Jobs = Mechanic.Jobs
local Tools = Mechanic.Tools
local Hoard = Mechanic.Hoard

local Jack = {}
Mechanic.Jack = Jack

local Notify = Jobs.Notify

-- [cid] = { last = os.time, class = 'super' }
local CoolDown = {}
-- [plate] = os.time the car went 'missing'
local Reported = {}
Jack.Reported = Reported

local function Now()
    return math.floor(os.time())
end

local IllegalSites = {}
for _, site in ipairs(Config.Locations) do
    if site.kind == 'illegal' then IllegalSites[site.id] = site end
end
Jack.Sites = IllegalSites

-- ─── Anti-duplicate guard on stolen vehicles ─────────────────
local function AlreadyStolen(plate)
    if Reported[plate] then return true end
    local row = MySQL.single.await(
        "SELECT hoard_ref FROM grand_hoardings WHERE plate = ? AND stolen = 1 AND state IN ('stored', 'impounded') LIMIT 1",
        { plate })
    return row ~= nil
end

-- ─── Hotwire ─────────────────────────────────────────────────
---@param source number
---@param payload table { netId, plate, model, class, coords, alarm, locked }
function Jack.Hotwire(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end

    payload = type(payload) == 'table' and payload or {}
    local plate = Shared.NormalisePlate(payload.plate)
    if plate == '' then return false, 'no-plate' end
    if AlreadyStolen(plate) then return false, 'already-reported' end

    if not Tools.HasItem(source, 'lockpick_set', 1) then
        return false, 'missing-tool:Key Kit'
    end

    if not Jobs.Throttle(source, 'jack', 20) then return false, 'slow-down' end

    local level = session.level or 0
    local chance = Config.Failure.jackBaseChance + (level * Config.Failure.jackPerLevel)
    if payload.locked == false then chance = chance + 0.15 end
    if payload.class == 'super' or payload.class == 'sports2' then chance = chance - 0.12 end
    chance = Shared.Clamp(chance, 0.08, 0.94)

    local roll = math.random()
    DB.LogTampering(session.cid, plate, 'hotwire-attempt', payload.site, false)

    if roll > chance then
        -- failed: tools jam, alarm screams, someone calls it in
        Tools.RemoveItem(source, 'lockpick_set', 1, 'jammed')
        if roll > chance + 0.94 then
            Jack.AlertPolice(source, plate, payload.coords, 'failed hotwire attempt')
        end
        Notify(source, ('The immobiliser on %s fought back (%d%% chance)'):format(
            plate, math.floor(chance * 100)), 'error')
        TriggerClientEvent('grand_mechanic:client:JackFailed', source, { plate = plate })
        return false, 'failed'
    end

    if payload.alarm and math.random() < Config.Failure.hotwireAlarmChance then
        Jack.AlertPolice(source, plate, payload.coords, 'vehicle alarm')
    end

    Reported[plate] = Now()
    CoolDown[session.cid] = { last = Now(), class = payload.class }

    TriggerClientEvent('grand_mechanic:client:JackSuccess', source, {
        plate = plate, model = payload.model, class = payload.class,
    })
    Notify(source, ('%s is on the money — get it to a chop shop'):format(plate), 'success')
    return true, { plate = plate, class = payload.class }
end

-- ─── Strip for parts ────────────────────────────────────────
function Jack.Strip(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    payload = type(payload) == 'table' and payload or {}

    local plate = Shared.NormalisePlate(payload.plate)
    if plate == '' then return false, 'no-plate' end
    if not Reported[plate] and not AlreadyStolen(plate) then return false, 'not-jacked' end
    if not Jobs.Throttle(source, 'strip', 10) then return false, 'slow-down' end

    local site = IllegalSites[tostring(payload.site or '')]
    if not site then return false, 'not-a-chop-shop' end
    if not Tools.HasItem(source, 'toolbox', 1) then return false, 'missing-tool:Toolbox' end

    local wanted = math.floor(tonumber(payload.wanted) or 0)
    local pool = {}
    for _, def in pairs(Config.Parts) do
        if def.sell > 0 and def.weight < 20.0 then pool[#pool + 1] = def.item end
    end

    local haul = {}
    local count = Shared.Clamp(2 + math.floor((session.level or 0) / 2) + wanted, 1, 5)
    for _ = 1, count do
        local item = pool[math.random(#pool)]
        if Tools.HasItem(source, item, 1) == false or true then
            if Tools.AddItem(source, item, 1, { source = 'strip', plate = plate }) then
                haul[#haul + 1] = item
            end
        end
    end

    if #haul == 0 then return false, 'pack-full' end

    DB.LogTampering(session.cid, plate, 'strip', site.id, false)
    Jobs.RegisterAction(source, 'jack', 0)
    Notify(source, ('Pulled %d parts off %s'):format(#haul, plate), 'success')
    TriggerClientEvent('grand_mechanic:client:StripDone', source, { plate = plate, haul = haul })
    return true, haul
end

-- ─── Respray + fresh plates ─────────────────────────────────
function Jack.Respray(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    payload = type(payload) == 'table' and payload or {}

    local plate = Shared.NormalisePlate(payload.plate)
    local site = IllegalSites[tostring(payload.site or '')]
    if plate == '' then return false, 'no-plate' end
    if not site then return false, 'not-a-chop-shop' end
    if not AlreadyStolen(plate) then return false, 'clean-car' end

    local cost = Config.Resale.resprayCost + Config.Resale.plateCost
    if Jobs.Money(source, 'cash') < cost then return false, 'no-cash' end
    if not Jobs.Take(source, 'cash', cost, 'respray') then return false, 'payment-failed' end

    local newPlate = Jack.NewPlate()
    local row = DB.HoardForPlate(plate)
    if row then
        DB.MarkRespray(row.hoard_ref, newPlate)
    else
        DB.Hoard({
            ref = Shared.Id('hoard'), site = site.id, plate = plate,
            model = tostring(payload.model or 'unknown'), storedBy = session.cid,
            fees = 0, hourly = 0, state = 'stored', stolen = true, resprayed = true, newPlate = newPlate,
        })
    end

    DB.LogTampering(session.cid, plate, 'respray:' .. newPlate, site.id, false)
    Reported[newPlate] = Now()

    Notify(source, ('Fresh paint, plates now %s — $%s'):format(newPlate, Shared.Money(cost)), 'success')
    TriggerClientEvent('grand_mechanic:client:ResprayDone', source, { old = plate, new = newPlate })
    return true, { plate = newPlate, cost = cost }
end

-- ─── Sell the car ────────────────────────────────────────────
function Jack.Sell(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    payload = type(payload) == 'table' and payload or {}

    local plate = Shared.NormalisePlate(payload.plate)
    local site = IllegalSites[tostring(payload.site or '')]
    if plate == '' then return false, 'no-plate' end
    if not site then return false, 'no-sale-yard' end
    if not AlreadyStolen(plate) then return false, 'not-yours' end

    local cool = CoolDown[session.cid]
    if cool and (Now() - cool.last) < Config.Resale.coolDown then
        local left = Config.Resale.coolDown - (Now() - cool.last)
        return false, ('buyer-wait:%ds'):format(left)
    end

    local classKey = Shared.ClassKey(payload.vehicleClass) or 'default'
    local range = Config.Resale.classes[classKey] or Config.Resale.defaultRange
    local roll = math.random(math.floor(range.min), math.floor(range.max))
    local cut = site.resaleCut or 0.3
    local net = Shared.Money(roll - (roll * cut))

    Jobs.Pay(source, 'crypto', net, 'resale:' .. plate)
    CoolDown[session.cid] = { last = Now(), class = classKey }
    Reported[plate] = nil

    MySQL.update.await(
        "UPDATE grand_hoardings SET state = 'sold', released_at = ? WHERE plate = ? AND state IN ('stored', 'impounded')",
        { Now(), plate })
    DB.LogTampering(session.cid, plate, 'resale', site.id, false)
    Jobs.RegisterAction(source, 'jack', net)

    if math.random() < (Config.Resale.wantedChance or 0.42) then
        Jack.AlertPolice(source, plate, payload.coords, 'suspicious vehicle sale')
    end

    TriggerClientEvent('grand_mechanic:client:SaleDone', source, { plate = plate, gross = roll, net = net })
    Notify(source, ('Car moved for $%s — $%s after the yard cut'):format(
        Shared.Money(roll), Shared.Money(net)), 'success')
    return true, { gross = roll, net = net }
end

-- ─── Plate generator for resprayed cars ─────────────────────
function Jack.NewPlate()
    local letters = 'ABCDEFGHJKLMNPRSTUVWXYZ'
    local digits = '0123456789'
    for _ = 1, 40 do
        local p = {}
        p[1] = letters:sub(math.random(#letters), math.random(#letters))
        p[2] = letters:sub(math.random(#letters), math.random(#letters))
        p[3] = digits:sub(math.random(#digits), math.random(#digits))
        p[4] = digits:sub(math.random(#digits), math.random(#digits))
        p[5] = digits:sub(math.random(#digits), math.random(#digits))
        p[6] = digits:sub(math.random(#digits), math.random(#digits))
        p[7] = letters:sub(math.random(#letters), math.random(#letters))
        p[8] = letters:sub(math.random(#letters), math.random(#letters))
        local plate = table.concat(p)
        local taken = MySQL.scalar.await(
            'SELECT 1 FROM grand_hoardings WHERE plate = ? OR new_plate = ? LIMIT 1', { plate, plate })
        if not taken then return plate end
    end
    return ('GND%d'):format(math.random(100000, 999999))
end

-- ─── Police tip-off ──────────────────────────────────────────
function Jack.AlertPolice(source, plate, coords, reason)
    local session = Jobs.Get(source)
    if session then DB.MarkBusted(session.cid) end
    DB.LogTampering(session and session.cid or 'UNKNOWN', plate, 'alert:' .. reason, nil, true)

    TriggerClientEvent('grand_mechanic:client:PoliceTipoff', -1, {
        plate = plate, reason = reason,
        coords = coords or vector3(0, 0, 0),
        reporter = GetPlayerName(source),
    })

    -- anyone running the police resource gets a dispatch entry
    pcall(function()
        if GetResourceState('grand_police') == 'started' then
            exports['grand_police'].DispatchCall('vehicle', plate, coords, reason)
        end
    end)
    pcall(function()
        if GetResourceState('grand_phone') == 'started' then
            exports['grand_phone'].EmergencyCall('lspd', plate, reason, coords)
        end
    end)
end

function Jack.ClearReported(plate)
    Reported[Shared.NormalisePlate(plate)] = nil
end

-- ─── Cleanup loop ────────────────────────────────────────────
CreateThread(function()
    Wait(60000)
    while true do
        local cutoff = Now() - 3600
        for plate, when in pairs(Reported) do
            if when < cutoff then Reported[plate] = nil end
        end
        Wait(60000)
    end
end)

AddEventHandler('playerDropped', function()
    local src = tonumber(source)
    local session = Jobs.Sessions[src]
    if session then CoolDown[session.cid] = nil end
end)

-- ─── RPC ──────────────────────────────────────────────────────
RegisterNetEvent('grand_mechanic:server:Jack', function(payload)
    local src = tonumber(source)
    if not src then return end
    local ok, result = Jack.Hotwire(src, payload)
    if not ok then TriggerClientEvent('grand_mechanic:client:JackDenied', src, tostring(result)) end
end)

RegisterNetEvent('grand_mechanic:server:Strip', function(payload)
    local src = tonumber(source)
    if not src then return end
    Jack.Strip(src, payload)
end)

RegisterNetEvent('grand_mechanic:server:Respray', function(payload)
    local src = tonumber(source)
    if not src then return end
    local ok, result = Jack.Respray(src, payload)
    if not ok then Notify(src, ('Paint shop says: %s'):format(tostring(result)), 'error') end
end)

RegisterNetEvent('grand_mechanic:server:SellCar', function(payload)
    local src = tonumber(source)
    if not src then return end
    local ok, result = Jack.Sell(src, payload)
    if not ok then Notify(src, ('No buyer: %s'):format(tostring(result)), 'error') end
end)

RegisterNetEvent('grand_mechanic:server:BustJack', function(plate, reason)
    local src = tonumber(source)
    if not src then return end
    if not Jobs.CanWork(Jobs.JobName(src), 'police') and not IsPlayerAceAllowed(src, 'grand.mechanic.impound') then
        return
    end
    Jack.AlertPolice(src, plate, GetEntityCoords(GetPlayerPed(src)), reason or 'reported stolen')
    Jack.ClearReported(plate)
end)

exports('Hotwire', Jack.Hotwire)
exports('Respray', Jack.Respray)
exports('NewPlate', Jack.NewPlate)

return Jack
