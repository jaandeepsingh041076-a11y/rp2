-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/shared/util.lua
--  Pure-Lua helpers shared by client + server. No NUI, no DB.
--  Owns the damage->fault translation and the invoice maths.
-- ─────────────────────────────────────────────────────────────

Mechanic = Mechanic or {}
Mechanic.Shared = {}

local Shared = Mechanic.Shared

-- ─── Fault classes ────────────────────────────────────────────
Shared.Faults = {
    engine     = { label = 'Engine',        partGroup = 'engine',     severity = 1.00, field = 'engineHealth' },
    electrical = { label = 'Electrical',    partGroup = 'electrical', severity = 0.62, field = 'engineHealth' },
    brakes     = { label = 'Brakes',        partGroup = 'brakes',     severity = 0.86, field = 'brakes' },
    suspension = { label = 'Suspension',    partGroup = 'suspension', severity = 0.71, field = 'suspension' },
    transmission = { label = 'Transmission', partGroup = 'drivetrain', severity = 0.94, field = 'engineHealth' },
    drivetrain = { label = 'Drivetrain',    partGroup = 'drivetrain', severity = 0.88, field = 'engineHealth' },
    tires      = { label = 'Tyres',         partGroup = 'tires',      severity = 0.44, field = 'tires' },
    body       = { label = 'Bodywork',      partGroup = 'body',       severity = 0.55, field = 'bodyHealth' },
    glass      = { label = 'Glass',         partGroup = 'body',       severity = 0.30, field = 'glass' },
    cooling    = { label = 'Cooling',       partGroup = 'engine',     severity = 0.58, field = 'engineHealth' },
    turbo      = { label = 'Forced Induction', partGroup = 'engine',  severity = 0.66, field = 'engineHealth' },
    exhaust    = { label = 'Exhaust',       partGroup = 'engine',     severity = 0.28, field = 'engineHealth' },
}

Shared.FaultOrder = {
    'engine', 'transmission', 'drivetrain', 'brakes', 'suspension',
    'cooling', 'turbo', 'electrical', 'tires', 'body', 'glass', 'exhaust',
}

Shared.FieldToFaults = {
    engineHealth = { 'engine', 'cooling', 'turbo', 'exhaust', 'electrical' },
    bodyHealth   = { 'body', 'glass' },
    brakes       = { 'brakes' },
    suspension   = { 'suspension' },
    tires        = { 'tires', 'suspension' },
    petrolTankHealth = { 'fuel' },
}

-- ─── Maths ────────────────────────────────────────────────────
function Shared.Clamp(value, lo, hi)
    if type(value) ~= 'number' then return lo end
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

function Shared.Round(value, places)
    local m = 10 ^ (places or 0)
    return math.floor((value * m) + 0.5) / m
end

function Shared.Money(value)
    return Shared.Round(Shared.Clamp(tonumber(value) or 0, -999999999, 999999999))
end

function Shared.Percent(remaining)
    return Shared.Clamp(Shared.Round((1.0 - Shared.Clamp(remaining, 0.0, 1000.0) / 1000.0) * 100.0, 1), 0.0, 100.0)
end

-- ─── Vehicle identity ─────────────────────────────────────────
local CLASS_NAMES = {
    'comp', 'sedan', 'suv', 'coupe', 'muscle', 'sportsclassics', 'sports',
    'super', 'motorcycle', 'offroad', 'industrial', 'van', 'emergency',
    'service', 'military', 'container', 'train', 'openwheel', 'plane', 'heli', 'boat', 'utility',
}

local CLASS_TO_RESALE = {
    comp = 'compact', sedan = 'sedan', suv = 'suv', coupe = 'coupe',
    muscle = 'coupe', sportsclassics = 'sports', sports = 'sports',
    super = 'super', motorcycle = 'motorcycle', offroad = 'offroad',
    van = 'van', industrial = 'van', utility = 'van', service = 'van',
}

--- Human-readable vehicle class key used by Config.Resale.classes
function Shared.ClassKey(vehicleClass)
    local idx = tonumber(vehicleClass)
    if not idx then return nil end
    local name = CLASS_NAMES[idx + 1]
    if not name then return nil end
    return CLASS_TO_RESALE[name] or name, name
end

function Shared.ModelLabel(model)
    local hash = GetHashKey and GetHashKey(model) or 0
    local label = GetDisplayNameFromVehicleModel and GetDisplayNameFromVehicleModel(hash) or nil
    if label and label ~= 'CANNOT_FOUND' then
        return label:gsub('_', ' '):gsub('^%w', string.upper)
    end
    return (model or 'UNKNOWN'):upper()
end

-- ─── Fault derivation from raw damage ────────────────────────
--- Reads a FiveM networked vehicle state table (or our cached snapshot)
--- and returns an ordered list of faults with severity 0..1.
---@param snap table {engineHealth, bodyHealth, petrolTankHealth, brakes, suspension, tires, doors, lights, electricHealth}
---@return table list of { id, label, severity, part, work }
function Shared.DeriveFaults(snap)
    if type(snap) ~= 'table' then return {} end
    local faults = {}

    local engine = snap.engineHealth or 1000.0
    local body   = snap.bodyHealth or 1000.0
    local brake  = snap.brakes or 100
    local susp   = snap.suspension or 100
    local tires  = snap.tires or 100
    local fuel   = snap.petrolTankHealth or 100
    local elec   = snap.electricHealth or 1000
    local glass  = snap.glass or 100
    local doors  = snap.doors or {}

    local function push(id, damage)
        damage = Shared.Clamp(damage or 0, 0.0, 1.0)
        if damage < 0.06 then return end
        local def = Shared.Faults[id]
        if not def then return end
        faults[#faults + 1] = {
            id = id,
            label = def.label,
            severity = Shared.Round(damage * def.severity, 3),
            raw = Shared.Round(damage, 3),
        }
    end

    -- engine block wear
    push('engine', (1000.0 - Shared.Clamp(engine, 0.0, 1000.0)) / 1000.0)
    -- electrical: separate from engine so a car can crank but not charge
    push('electrical', (1000.0 - Shared.Clamp(elec, 0.0, 1000.0)) / 1000.0)
    push('cooling', math.max(0.0, (700.0 - Shared.Clamp(engine, 0.0, 700.0)) / 700.0) * 0.7)
    push('brakes', (100.0 - Shared.Clamp(brake, 0.0, 100.0)) / 100.0)
    push('suspension', (100.0 - Shared.Clamp(susp, 0.0, 100.0)) / 100.0)
    push('tires', (100.0 - Shared.Clamp(tires, 0.0, 100.0)) / 100.0)
    push('body', (1000.0 - Shared.Clamp(body, 0.0, 1000.0)) / 1000.0)

    local brokenPanels = 0
    for _, state in pairs(doors) do
        if state == 0 or state == false then brokenPanels = brokenPanels + 1 end
    end
    if brokenPanels > 0 then
        push('body', math.min(1.0, brokenPanels * 0.18))
    end

    push('glass', (100.0 - Shared.Clamp(glass, 0.0, 100.0)) / 100.0)

    if Shared.Clamp(fuel, 0.0, 100.0) < 12.0 then
        faults[#faults + 1] = { id = 'fuel', label = 'Fuel Starvation', severity = 0.12, raw = 0.12 }
    end

    table.sort(faults, function(a, b) return a.severity > b.severity end)
    return faults
end

--- Overall condition band, used for pricing + blip colouring.
function Shared.Condition(faults)
    local worst = 0.0
    local sum = 0.0
    for _, f in ipairs(faults or {}) do
        if f.severity > worst then worst = f.severity end
        sum = sum + f.severity
    end
    if worst >= 0.75 then return 'critical', sum end
    if worst >= 0.45 then return 'damaged', sum end
    if worst >= 0.18 then return 'worn', sum end
    if worst > 0.0 then return 'tired', sum end
    return 'pristine', sum
end

-- ─── Pricing ──────────────────────────────────────────────────
--- Quote = labour + parts + tax, weighted by crew rank.
---@param faults table
---@param snap table
---@param rankLevel number
---@param kind string 'mechanic'|'tow'|'taxi'|'jack'
---@return table quote
function Shared.Quote(faults, snap, rankLevel, kind)
    rankLevel = Shared.Clamp(rankLevel or 0, 0, #Config.Progression.levels - 1)
    local bonus = 1.0 + (Config.Progression.bonusPerRank[rankLevel + 1] or 0.0)

    local labour = 0.0
    local partCost = 0.0
    local seconds = 0.0
    local lines = {}

    for _, fault in ipairs(faults or {}) do
        local def = Shared.Faults[fault.id]
        local part = Mechanic.Shared.PickPart(fault.id, snap)
        local work = (part and Config.Parts[part].work or 4) * (0.6 + fault.severity)
        local fee = (part and Config.Parts[part].sell or 0) + (work * Config.Damage.payoutPerPoint)

        labour = labour + (work * Config.Damage.payoutPerPoint)
        partCost = partCost + (part and Config.Parts[part].sell * 1.0 or 0.0)
        seconds = seconds + work

        lines[#lines + 1] = {
            fault = fault.id,
            label = fault.label,
            severity = fault.severity,
            part = part,
            cost = Shared.Money(fee * bonus),
            work = work,
        }
    end

    if kind == 'jack' then
        -- illegal work is priced as a lump-sum, no tax, no receipt
        local value = Shared.Money((labour + partCost) * 0.55)
        return {
            kind = kind, lines = {}, labour = 0, parts = 0, tax = 0,
            seconds = Config.Timing.jackSeconds, total = value, rank = rankLevel, illegal = true,
        }
    end

    local subtotal = labour + partCost
    subtotal = subtotal * bonus
    local tax = kind == 'mechanic' or kind == 'tow' or kind == 'taxi'
        and Shared.Money(subtotal * Config.TaxRate) or 0
    local total = Shared.Money(subtotal + tax)

    return {
        kind = kind,
        lines = lines,
        labour = Shared.Money(labour * bonus),
        parts = Shared.Money(partCost * bonus),
        tax = tax,
        total = total,
        seconds = Shared.Round(math.max(Config.Timing.diagnosticSeconds, seconds), 1),
        rank = rankLevel,
    }
end

--- Which part would fix this fault, considering what is already fitted.
function Shared.PickPart(faultId, snap)
    local def = Shared.Faults[faultId]
    if not def then return nil end
    local chosen, bestWork = nil, -1
    for key, part in pairs(Config.Parts) do
        if part.group == def.partGroup then
            local sev = (snap and snap['_fault_' .. faultId]) or def.severity
            local score = part.work * (sev or 1.0)
            if score > bestWork then
                bestWork, chosen = score, key
            end
        end
    end
    return chosen
end

-- ─── Validation ───────────────────────────────────────────────
function Shared.IsPlate(plate)
    if type(plate) ~= 'string' then return false end
    local p = plate:upper():gsub('%s', '')
    return p:match('^%w?%w?%d?%d?%d?%d?%w?%w?$') ~= nil and #p >= 2 and #p <= 8
end

function Shared.NormalisePlate(plate)
    return (tostring(plate or ''):upper():gsub('%s', ''):gsub('[^%w]', ''))
end

function Shared.Id(kind, seed)
    local t = GetGameTimer and GetGameTimer() or 0
    return ('%s-%x-%x'):format(kind, t, math.random(0, 0xFFFF) + (seed or 0))
end

function Shared.DeepCopy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Shared.DeepCopy(v) end
    return out
end

--- Nearest Config.Locations entry that the given job is allowed to use.
function Shared.NearestSite(coords, jobName, kinds)
    local best, bestDist
    for _, site in ipairs(Config.Locations) do
        if kinds == nil or Util_InList(kinds, site.kind) then
            local allowed = #site.jobs == 0
            if not allowed and jobName then
                for _, j in ipairs(site.jobs) do
                    if j == jobName then allowed = true break end
                end
            end
            if allowed then
                local d = #(coords - site.coords)
                if not bestDist or d < bestDist then best, bestDist = site, d end
            end
        end
    end
    return best, bestDist
end

local function inList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end
Util_InList = inList
Shared.InList = inList

--- Distance-scaled travel fee for flatbed / taxi dispatch.
function Shared.TravelFee(from, to, perKm)
    local d = #(vector3(from.x or from[1] or 0, from.y or from[2] or 0, from.z or from[3] or 0)
             - vector3(to.x or to[1] or 0, to.y or to[2] or 0, to.z or to[3] or 0))
    local km = d / 1000.0
    return Shared.Money((perKm or Config.Fees.taxiPerKm) * km * 6.2), d
end

return Shared
