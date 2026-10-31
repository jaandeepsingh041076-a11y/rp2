-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/config.lua
--  SECTION 06 — WORKFORCE TUNABLES
--  Every number a designer would ever want to move lives here.
-- ─────────────────────────────────────────────────────────────

Config = {}

-- vector helpers exist on the client; guarantee them for the server runtime
if vec3 == nil then
    vec3 = function(x, y, z) return vector3(x, y, z) end
end
if vec4 == nil then
    vec4 = function(x, y, z, w) return vector4(x, y, z, w) end
end

Config.Debug = GetConvar('grand_debug', 'false') == 'true'

-- ─── Job gates ─────────────────────────────────────────────────
Config.Jobs = {
    mechanic = { 'mechanic', 'mechanicgov' },
    tow      = { 'tow' },
    taxi     = { 'taxi' },
    -- anyone may jack a car (illegal), only these may use the hoarding tools
    police   = { 'lspd', 'sahp', 'fib' },
}

-- ─── Service fees the customer is charged (before tax) ─────────
Config.Fees = {
    repairFull      = 850,     -- full engine + body restore at a hoarding
    repairEngine    = 420,
    repairBody      = 380,
    repairGlass     = 160,
    repairTires     = 210,     -- all four
    repairElectrical= 540,
    tune            = 1200,
    flatbed         = 350,     -- tow fee
    unlock          = 120,
    hotwire        = 2400,     -- illegal, jack
    installParts    = 480,
    fuelTopUp       = 90,      -- jerry service in the field
    taxiBase        = 12,
    taxiPerKm       = 4,
    taxiWait        = 1,       -- per 10s of idle waiting
}

-- ─── Payout split: crew keeps this, the rest is business overhead ───
Config.PaySplit = {
    mechanic = 0.72,
    tow      = 0.78,
    taxi     = 0.80,
    jack     = 1.00,          -- illegal: 100% to the crew, laundered later
}

Config.TaxRate = 0.088        -- state sales tax applied to legal invoices

-- ─── Timing ────────────────────────────────────────────────────
Config.Timing = {
    repairSeconds     = 26,   -- one full service bench cycle
    towSeconds        = 18,   -- attach + winch
    jackSeconds       = 42,   -- hotwire window
    diagnosticSeconds = 6,
    partsSeconds      = 9,    -- per component fitted
    serviceCooldown   = 120,  -- per vehicle, seconds
    invoiceExpiry     = 900,  -- 15 min to settle an unpaid invoice
    taxiDispatchRtt   = 18,   -- seconds to answer a dispatch call
}

Config.Ranges = {
    workZone      = 12.0,   -- must be within this of the vehicle to work on it
    customerZone  = 6.0,    -- customer must stand this close to hand over keys
    flatbedLock   = 9.0,    -- winch reach
    hoardingEntry = 3.5,
    dispatchScan  = 250.0,  -- taxi dispatch radius
}

-- ─── Damage thresholds ────────────────────────────────────────
Config.Damage = {
    engineBreakAt   = 1000.0,   -- cumulative engine damage -> dead
    bodyBreakAt     = 1100.0,
    tireBlowAt      = 450.0,
    repairMinPayout = 180,      -- job is not worth taking below this
    payoutPerPoint  = 1.42,     -- damage points -> $
}

-- ─── Downtime / failure ───────────────────────────────────────
Config.Failure = {
    jackBaseChance     = 0.55,
    jackPerLevel       = 0.035,
    hotwireAlarmChance = 0.34,  -- triggers an alarm -> police callout
    partFitFailChance  = 0.06,  -- worn part refuses to seat
    towSlipChance      = 0.05,
}

-- ─── Parts catalogue ─────────────────────────────────────────
-- `item` is the grand_items / inventory name, `group` is the fault class.
Config.Parts = {
    engine            = { item = 'part_engine',        label = 'Engine Block',        group = 'engine',     buy = 1800, sell = 2600, weight = 22.0, work = 14 },
    turbo             = { item = 'part_turbo',         label = 'Turbocharger',        group = 'engine',     buy = 2400, sell = 3400, weight = 6.0,  work = 9 },
    radiators         = { item = 'part_radiator',      label = 'Radiator',            group = 'engine',     buy = 460,  sell = 780,  weight = 4.5,  work = 6 },
    battery           = { item = 'part_battery',       label = 'Battery',             group = 'electrical', buy = 180,  sell = 320,  weight = 3.0,  work = 3 },
    alternator        = { item = 'part_alternator',    label = 'Alternator',          group = 'electrical', buy = 520,  sell = 810,  weight = 5.2,  work = 5 },
    brakes            = { item = 'part_brakes',        label = 'Brake Calipers',      group = 'brakes',     buy = 640,  sell = 980,  weight = 7.0,  work = 7 },
    suspension        = { item = 'part_suspension',    label = 'Suspension Kit',      group = 'suspension', buy = 900,  sell = 1450, weight = 12.0, work = 8 },
    tires_set         = { item = 'part_tires',         label = 'Tyre Set',            group = 'tires',      buy = 380,  sell = 620,  weight = 9.0,  work = 6 },
    glass             = { item = 'part_glass',         label = 'Windscreen',          group = 'body',       buy = 220,  sell = 400,  weight = 8.5,  work = 5 },
    panel_front       = { item = 'part_panel_front',   label = 'Front Panel',         group = 'body',       buy = 540,  sell = 860,  weight = 14.0, work = 7 },
    panel_rear        = { item = 'part_panel_rear',    label = 'Rear Panel',          group = 'body',       buy = 510,  sell = 820,  weight = 13.5, work = 7 },
    transmission      = { item = 'part_gearbox',       label = 'Gearbox',             group = 'drivetrain', buy = 1600, sell = 2450, weight = 18.0, work = 12 },
    driveshaft        = { item = 'part_driveshaft',    label = 'Driveshaft',          group = 'drivetrain', buy = 720,  sell = 1100, weight = 10.0, work = 8 },
    exhaust           = { item = 'part_exhaust',       label = 'Sport Exhaust',       group = 'engine',     buy = 640,  sell = 1080, weight = 7.5,  work = 5 },
    intercooler       = { item = 'part_intercooler',   label = 'Intercooler',         group = 'engine',     buy = 880,  sell = 1340, weight = 5.5,  work = 6 },
    nitrous           = { item = 'part_nitrous',       label = 'Nitrous Bottle',      group = 'tuning',     buy = 1450, sell = 2200, weight = 6.0,  work = 6 },
    armour_kit        = { item = 'part_armour',        label = 'Bolt-On Armour',      group = 'body',       buy = 3200, sell = 5200, weight = 34.0, work = 16 },
    winch             = { item = 'part_winch',         label = 'Winch Spool',         group = 'equipment',  buy = 400,  sell = 0,    weight = 11.0, work = 0 },
}

Config.Tools = {
    toolbox    = { item = 'toolbox',      label = 'Toolbox',      requiredFor = 'repair',  breakChance = 0.09 },
    wrench     = { item = 'wrench',       label = 'Pipe Wrench',  requiredFor = 'tires',   breakChance = 0.05 },
    diag_tablet= { item = 'diag_tablet',  label = 'OBD Tablet',   requiredFor = 'scan',    breakChance = 0.03 },
    jack_stand = { item = 'jack_stand',   label = 'Jack + Stand', requiredFor = 'lift',    breakChance = 0.02 },
    welder     = { item = 'welder',       label = 'Spot Welder',  requiredFor = 'body',    breakChance = 0.07 },
    key_generator = { item = 'lockpick_set', label = 'Key Kit',   requiredFor = 'jack',    breakChance = 0.12 },
}

-- ─── Work locations (blips + interaction targets) ────────────
-- kind: 'hoarding' | 'towing' | 'taxi' | 'legal' | 'illegal'
Config.Locations = {
    {
        id = 'grille_benny',
        name = 'Benny\'s Original Motor Works',
        kind = 'hoarding',
        jobs = { 'mechanic' },
        coords = vec3(205.78, -1059.61, 28.43),
        heading = 307.0,
        radius = 18.0,
        blip = { sprite = 478, colour = 28, scale = 0.85, label = 'Benny\'s Motor Works' },
        spawn = vec4(208.7, -1052.1, 28.43, 306.0),
        hasLift = true,
        hasPaint = true,
        hasTuning = true,
        storage = 'hoarding:grille_benny',
        slots = 60,
    },
    {
        id = 'legion_square',
        name = 'Legion Square Service Bay',
        kind = 'hoarding',
        jobs = { 'mechanic' },
        coords = vec3(-214.32, -1300.62, 30.22),
        heading = 205.0,
        radius = 14.0,
        blip = { sprite = 478, colour = 28, scale = 0.8, label = 'Service Bay' },
        spawn = vec4(-210.0, -1296.4, 30.0, 205.0),
        hasLift = true,
        storage = 'hoarding:legion_square',
        slots = 45,
    },
    {
        id = 'peachier',
        name = 'LS Car Meet',
        kind = 'legal',
        jobs = { 'mechanic' },
        coords = vec3(1392.6, -1718.25, 70.19),
        heading = 92.0,
        radius = 22.0,
        blip = { sprite = 72, colour = 4, scale = 0.8, label = 'LS Car Meet' },
        storage = 'hoarding:peachier',
        slots = 40,
    },
    {
        id = 'cavalor_blvd',
        name = 'Cavalor Blvd Tyre Shop',
        kind = 'hoarding',
        jobs = { 'mechanic' },
        coords = vec3(-302.9, -1390.5, 30.1),
        heading = 8.0,
        radius = 12.0,
        blip = { sprite = 478, colour = 28, scale = 0.7, label = 'Tyre Shop' },
        storage = 'hoarding:cavalor_blvd',
        slots = 30,
    },
    {
        id = 'vespucci_tow',
        name = 'Vespucci Towing Yard',
        kind = 'towing',
        jobs = { 'tow' },
        coords = vec3(410.2, -2058.4, 22.6),
        heading = 141.0,
        radius = 16.0,
        blip = { sprite = 481, colour = 17, scale = 0.8, label = 'Vespucci Towing' },
        spawn = vec4(412.9, -2053.6, 22.02, 141.0),
        impound = true,
        storage = 'hoarding:vespucci_tow',
        slots = 35,
    },
    {
        id = 'mirror_park_tow',
        name = 'Mirror Park Recovery',
        kind = 'towing',
        jobs = { 'tow' },
        coords = vec3(1116.6, 2330.4, 79.3),
        heading = 252.0,
        radius = 14.0,
        blip = { sprite = 481, colour = 17, scale = 0.75, label = 'Mirror Park Recovery' },
        spawn = vec4(1119.4, 2326.1, 78.0, 252.0),
        impound = true,
        storage = 'hoarding:mirror_park_tow',
        slots = 30,
    },
    {
        id = 'airplane_tow',
        name = 'Airplane Hangar Recovery',
        kind = 'towing',
        jobs = { 'tow' },
        coords = vec3(-1032.6, -2732.5, 20.17),
        heading = 130.0,
        radius = 20.0,
        blip = { sprite = 481, colour = 17, scale = 0.75, label = 'Hangar Recovery' },
        spawn = vec4(-1028.0, -2726.0, 20.17, 130.0),
        impound = true,
        storage = 'hoarding:airplane_tow',
        slots = 40,
    },
    {
        id = 'downtown_taxi',
        name = 'Downtown Taxi HQ',
        kind = 'taxi',
        jobs = { 'taxi' },
        coords = vec3(-617.5, -1163.1, 18.9),
        heading = 344.0,
        radius = 12.0,
        blip = { sprite = 476, colour = 5, scale = 0.8, label = 'Downtown Taxi HQ' },
        spawn = vec4(-614.9, -1159.4, 18.9, 344.0),
    },
    {
        id = 'airport_taxi',
        name = 'Airport Taxi Rank',
        kind = 'taxi',
        jobs = { 'taxi' },
        coords = vec3(-1038.6, -2755.2, 20.1),
        heading = 78.0,
        radius = 10.0,
        blip = { sprite = 476, colour = 5, scale = 0.7, label = 'Airport Taxi Rank' },
        spawn = vec4(-1035.9, -2751.6, 20.1, 78.0),
    },
    {
        id = 'del_perro_taxi',
        name = 'Del Perro Taxi Rank',
        kind = 'taxi',
        jobs = { 'taxi' },
        coords = vec3(-783.6, -1526.4, 5.1),
        heading = 118.0,
        radius = 10.0,
        blip = { sprite = 476, colour = 5, scale = 0.7, label = 'Del Perro Taxi' },
        spawn = vec4(-780.2, -1522.9, 4.0, 118.0),
    },
    {
        id = 'chiliad_jack',
        name = 'Chiliad Chop Shop',
        kind = 'illegal',
        jobs = {},     -- any player
        coords = vec3(995.54, -1352.06, 31.28),
        heading = 190.0,
        radius = 26.0,
        blip = { sprite = 481, colour = 1, scale = 0.7, label = 'Unlisted Workshop', hidden = true },
        storage = 'hoarding:chiliad_jack',
        slots = 24,
        resaleCut = 0.34,
        policeWatch = true,
    },
    {
        id = 'sandy_jack',
        name = 'Sandy Shores Backyard',
        kind = 'illegal',
        jobs = {},
        coords = vec3(1722.4, 2328.9, 49.7),
        heading = 60.0,
        radius = 22.0,
        blip = { sprite = 481, colour = 1, scale = 0.6, label = 'Backyard Workshop', hidden = true },
        storage = 'hoarding:sandy_jack',
        slots = 20,
        resaleCut = 0.31,
        policeWatch = true,
    },
    {
        id = 'cypress_jack',
        name = 'Cypress Flats Garage',
        kind = 'illegal',
        jobs = {},
        coords = vec3(-1352.4, 612.9, 30.6),
        heading = 300.0,
        radius = 20.0,
        blip = { sprite = 481, colour = 1, scale = 0.6, label = 'Cypress Garage', hidden = true },
        storage = 'hoarding:cypress_jack',
        slots = 20,
        resaleCut = 0.29,
        policeWatch = true,
    },
}

-- ─── Impound lots ─────────────────────────────────────────────
Config.Impound = {
    { id = 'righer_lot',   name = 'Righer Avenue Impound',   coords = vec3(245.9, -996.4, 29.2),   fee = 350,  blip = { sprite = 345, colour = 47, scale = 0.7, label = 'Impound Lot' } },
    { id = 'vespucci_lot', name = 'Vespucci Canal Impound',  coords = vec3(-228.7, -1613.4, 29.7),  fee = 420,  blip = { sprite = 345, colour = 47, scale = 0.7, label = 'Impound Lot' } },
    { id = 'airport_lot',  name = 'FSR Airport Impound',     coords = vec3(-1041.2, -2782.3, 20.2),fee = 680,  blip = { sprite = 345, colour = 47, scale = 0.7, label = 'Impound Lot' } },
    { id = 'sandy_lot',    name = 'Alamo Impound',           coords = vec3(1912.6, 3721.4, 33.9),  fee = 780,  blip = { sprite = 345, colour = 47, scale = 0.7, label = 'Impound Lot' } },
}

-- ─── Fuel / tyre / water pump services (public, no job needed) ───
Config.PublicServices = {
    { id = 'gasoline_mirror', name = 'Mirror Park Petrol', coords = vec3(1068.2, -318.5, 42.35), radius = 14.0, blip = { sprite = 360, colour = 5, scale = 0.8, label = 'Petrol Station' } },
    { id = 'gasoline_hanch',  name = 'Hanchley Petrol',    coords = vec3(2500.4, 1606.5, 40.9),  radius = 14.0, blip = { sprite = 360, colour = 5, scale = 0.75, label = 'Petrol Station' } },
    { id = 'gasoline_brian',  name = 'South Main Petrol',  coords = vec3(372.6, 325.9, 103.4),   radius = 12.0, blip = { sprite = 360, colour = 5, scale = 0.75, label = 'Petrol Station' } },
}

-- ─── Vehicle fleet the crew can check out ─────────────────────
Config.Fleet = {
    mechanic = { 'towtruck', 'flatbed', 'boxville' },
    tow      = { 'flatbed', 'towtruck', 'buckeler' },
    taxi     = { 'taxi', 'taxi2' },
}

Config.FleetSpawn = {
    flatbed   = vec4(413.6, -2051.2, 22.02, 141.0),
    towtruck  = vec4(416.9, -2047.6, 22.02, 141.0),
    taxi      = vec4(-611.4, -1156.7, 18.9, 344.0),
    buckeler  = vec4(-218.6, -1292.4, 30.1, 205.0),
    boxville  = vec4(-204.9, -1287.6, 30.1, 205.0),
}

-- ─── Taxi drop-off points (fixed-fare routes) ─────────────────
Config.TaxiRoutes = {
    { id = 'airport_run',   from = 'airport_taxi',   to = vec3(-79.2, -818.4, 44.0),  name = 'Airport → Legend Tours', fare = 145 },
    { id = 'del_perro_run', from = 'downtown_taxi',  to = vec3(-667.5, -1425.2, 37.0), name = 'Downtown → Del Perro Pier', fare = 95 },
    { id = 'vinewood_run',  from = 'downtown_taxi',  to = vec3(-373.6, 608.0, 147.8),  name = 'Downtown → Vinewood Hills', fare = 130 },
    { id = 'sandy_run',     from = 'airport_taxi',   to = vec3(1915.4, 3728.2, 33.9),  name = 'Airport → Sandy Shores',  fare = 380 },
    { id = 'paleto_run',    from = 'airport_taxi',   to = vec3(118.1, -138.8, 54.5),   name = 'Airport → Paleto Bay',    fare = 420 },
    { id = 'cavalor_run',   from = 'downtown_taxi',  to = vec3(265.4, -982.1, 29.2),   name = 'Downtown → La Mesa',      fare = 70 },
}

-- ─── Black market (jack -> respray -> sell) ───────────────────
Config.Resale = {
    classes = {
        compact   = { min = 1800, max = 3200 },
        sedan     = { min = 2600, max = 4800 },
        suv       = { min = 3400, max = 6200 },
        coupe      = { min = 4200, max = 8600 },
        sports    = { min = 7400, max = 14500 },
        sports2   = { min = 11000, max = 22000 },
        super     = { min = 18000, max = 44000 },
        motorcycle= { min = 2400, max = 6800 },
        offroad   = { min = 3600, max = 9200 },
        van       = { min = 2000, max = 4400 },
    },
    defaultRange = { min = 1400, max = 2600 },
    resprayCost  = 650,
    plateCost    = 380,
    coolDown     = 900,       -- 15 min per vehicle class, per player
    wantedChance = 0.42,      -- selling a flagged car adds a wanted level
}

-- ─── Police / LSPD related ────────────────────────────────────
Config.Legal = {
    impoundAfterHours = 24,       -- hours abandoned before auto-impound
    towFeePerMinute   = 6,        -- accrued while a car is on a flatbed unpaid
    evidenceItems     = { 'part_winch', 'lockpick_set' },
}

-- ─── Persistence ──────────────────────────────────────────────
Config.Persistence = {
    autoCreateSchema = true,
    saveInterval     = 300,
    invoiceTable     = 'grand_mechanic_invoices',
    jobTable         = 'grand_mechanic_jobs',
    hoardTable       = 'grand_hoardings',
    statTable        = 'grand_mechanic_stats',
}

-- ─── Ranking: crew XP -> level -> better payouts ──────────────
Config.Progression = {
    xpPerJob     = 12,
    xpPerTow     = 9,
    xpPerJack    = 22,
    xpPerTaxi    = 4,
    levels       = { 0, 250, 700, 1500, 2800, 4800, 7600, 11500, 17000, 25000 },
    bonusPerRank = { 0.00, 0.02, 0.04, 0.07, 0.10, 0.13, 0.16, 0.20, 0.25, 0.32 },
}

-- ─── Blip master switch ───────────────────────────────────────
Config.Blips = {
    enable       = true,
    onlyOnDuty   = false,
    distanceCull = 1200.0,
}
