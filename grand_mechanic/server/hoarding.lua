-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/server/hoarding.lua
--  Impound / hoarding authority: store a vehicle, accrue hourly fees,
--  release against payment, police-plate lookups, yard listings.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local DB = Mechanic.DB
local Jobs = Mechanic.Jobs

local Hoard = {}
Mechanic.Hoard = Hoard

local Notify = Jobs.Notify

-- ─── Sites ────────────────────────────────────────────────────
local SiteById = {}
for _, site in ipairs(Config.Locations) do SiteById[site.id] = site end
Hoard.Sites = SiteById

local ImpoundById = {}
for _, lot in ipairs(Config.Impound) do ImpoundById[lot.id] = lot end
Hoard.Impounds = ImpoundById

function Hoard.NearestImpound(coords)
    local best, dist
    for _, lot in ipairs(Config.Impound) do
        local d = #(coords - lot.coords)
        if not dist or d < dist then best, dist = lot, d end
    end
    return best, dist
end

-- ─── Store a vehicle ─────────────────────────────────────────
---@param source number worker
---@param payload table { plate, model, site, kind, hoursFree }
function Hoard.Store(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    payload = payload or {}

    local plate = Shared.NormalisePlate(payload.plate)
    if plate == '' then return false, 'no-plate' end

    local site = SiteById[tostring(payload.site or '')]
    if not site then return false, 'unknown-site' end

    local allowedKind = Shared.InList({ 'hoarding', 'towing', 'illegal', 'legal' }, site.kind)
    if not allowedKind then return false, 'site-not-a-yard' end

    if site.kind ~= 'illegal' and not Jobs.CanWork(session.job, site.kind == 'towing' and 'tow' or 'mechanic') then
        if not IsPlayerAceAllowed(source, 'grand.mechanic.impound') then
            return false, 'off-duty'
        end
    end

    if not Jobs.Throttle(source, 'store:' .. plate, 8) then return false, 'already-processed' end

    local existing = DB.HoardForPlate(plate)
    if existing then return false, 'already-hoarded' end

    local owner = DB.OwnerOfPlate(plate)
    local lot, _ = Hoard.NearestImpound(payload.coords or site.coords)
    local hourly = math.floor((lot and lot.fee or 120) / 6)
    if site.kind == 'illegal' then hourly = 0 end

    local row = {
        ref = Shared.Id('hoard'),
        job = payload.job,
        site = site.id,
        plate = plate,
        model = tostring(payload.model or 'unknown'),
        storedBy = session.cid,
        owner = owner and owner.citizenid or nil,
        fees = math.floor(payload.fee or (lot and lot.fee or 350)),
        hourly = hourly,
        state = site.kind == 'illegal' and 'stored' or 'impounded',
        stolen = site.kind == 'illegal',
    }

    DB.Hoard(row)
    DB.SetVehicleState(plate, 2, site.id)

    TriggerClientEvent('grand_mechanic:client:HoardSync', -1, {
        ref = row.ref, plate = plate, site = site.id, model = row.model, state = row.state,
    })

    return true, row
end

-- ─── Release ─────────────────────────────────────────────────
function Hoard.Release(source, ref, method)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    local row = DB.HoardForRef(tostring(ref or ''))
    if not row then return false, 'not-found' end
    if row.state ~= 'impounded' then return false, 'already-released' end

    local amount = math.floor(tonumber(row.fees) or 0)
    local site = SiteById[row.site]

    -- whoever holds the vehicle's paperwork gets a discount
    local owner = DB.OwnerOfPlate(row.plate)
    local isOwner = owner and owner.citizenid == session.cid
    if not isOwner and not Jobs.CanWork(session.job, 'tow') and not Jobs.CanWork(session.job, 'mechanic') then
        if not IsPlayerAceAllowed(source, 'grand.mechanic.impound') then
            return false, 'not-authorised'
        end
    end

    if amount > 0 and method ~= 'waived' then
        if Jobs.Money(source, method or 'cash') < amount then
            return false, 'cant-pay'
        end
        if not Jobs.Take(source, method or 'cash', amount, 'impound:' .. row.plate) then
            return false, 'payment-failed'
        end
        -- the yard banks it
        if site and site.kind == 'towing' then
            Jobs.Pay(source, 'bank', math.floor(amount * 0.25), 'yard-commission')
        end
    elseif method == 'waived' and not IsPlayerAceAllowed(source, 'grand.mechanic.waive') then
        return false, 'no-waiver-rights'
    end

    if not DB.ReleaseHoard(row.hoard_ref, 0) then return false, 'race' end
    DB.SetVehicleState(row.plate, 0, row.site)

    TriggerClientEvent('grand_mechanic:client:HoardReleased', -1, { ref = row.hoard_ref, plate = row.plate })
    Notify(source, ('%s released from %s'):format(row.plate, (site and site.name or 'the yard')), 'success')
    return true, row
end

-- ─── Yard listing ────────────────────────────────────────────
function Hoard.Listing(source)
    local rows = DB.ActiveHoardings(200)
    local out = {}
    for _, r in ipairs(rows) do
        out[#out + 1] = {
            ref = r.hoard_ref,
            plate = r.plate,
            model = r.model,
            site = r.site,
            fees = math.floor(r.fees or 0),
            hourly = math.floor(r.hourly or 0),
            hours = math.floor(r.hours or 0),
            state = r.state,
            stolen = r.stolen == 1,
            owner = r.firstname and (r.firstname .. ' ' .. r.lastname) or 'UNREGISTERED',
        }
    end
    TriggerClientEvent('grand_mechanic:client:HoardList', source or -1, out)
    return out
end

function Hoard.PlateLookup(source, plate)
    plate = Shared.NormalisePlate(plate)
    local hoard = DB.HoardForPlate(plate)
    local vehicle = DB.CharacterByPlate(plate)
    local flags = {}
    if hoard then flags[#flags + 1] = 'HOARDED' end
    if vehicle and vehicle.state == 2 then flags[#flags + 1] = 'IMPOUNDED' end
    if vehicle and not vehicle.citizenid then flags[#flags + 1] = 'NO-REGISTRATION' end

    TriggerClientEvent('grand_mechanic:client:PlateResult', source, {
        plate = plate,
        hoard = hoard,
        owner = vehicle and vehicle.firstname and (vehicle.firstname .. ' ' .. vehicle.lastname) or nil,
        ownerCid = vehicle and vehicle.citizenid,
        garage = vehicle and vehicle.garage,
        model = vehicle and vehicle.model,
        flags = flags,
    })
end

-- ─── Fees + auto-crush ───────────────────────────────────────
CreateThread(function()
    Wait(15000)
    while true do
        DB.AccrueHoardFees()
        Wait(60 * 60 * 1000)   -- hourly
    end
end)

CreateThread(function()
    Wait(120000)
    while true do
        -- vehicles parked on the street past the timeout get collected by the county
        MySQL.update.await([[
            UPDATE grand_vehicles SET state = 2
             WHERE state = 0 AND plate IN (
                SELECT plate FROM grand_hoardings WHERE state = 'impounded' AND hours > ?
             )
        ]], { Config.Legal.impoundAfterHours })
        Wait(10 * 60 * 1000)
    end
end)

-- ─── RPC ──────────────────────────────────────────────────────
RegisterNetEvent('grand_mechanic:server:Store', function(payload)
    local source = tonumber(source)
    if not source then return end
    local ok, result = Hoard.Store(source, payload)
    if not ok then
        Notify(source, ('Cannot hoard that vehicle: %s'):format(tostring(result)), 'error')
    else
        Notify(source, ('%s booked into %s — $%s'):format(result.plate, result.site,
            Shared.Money(result.fees)), 'success')
    end
end)

RegisterNetEvent('grand_mechanic:server:Release', function(ref, method)
    local source = tonumber(source)
    if not source then return end
    local ok, result = Hoard.Release(source, ref, method)
    if not ok then
        Notify(source, ('Release failed: %s'):format(tostring(result)), 'error')
    end
end)

RegisterNetEvent('grand_mechanic:server:HoardList', function()
    local source = tonumber(source)
    if source then Hoard.Listing(source) end
end)

RegisterNetEvent('grand_mechanic:server:PlateLookup', function(plate)
    local source = tonumber(source)
    if source then Hoard.PlateLookup(source, plate) end
end)

exports('Store', Hoard.Store)
exports('Release', Hoard.Release)
exports('Listing', Hoard.Listing)

return Hoard
