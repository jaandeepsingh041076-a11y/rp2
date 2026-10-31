-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_dealership/config.lua
--  Every tunable for the dealership network. Shared client+server.
--  Real GTA V model names only. The server always re-reads prices
--  from this file; a client can never name its own price.
-- ─────────────────────────────────────────────────────────────

Config = {}

Config.Debug = false
Config.Prefix = 'dealer_'

-- ─── Forecourt lots ──────────────────────────────────────────
Config.Lots = {
    {
        id = 'legendary',
        name = 'Legendary Motorsport',
        coords = vector3(-735.0, -1447.0, 27.0),
        spawn = vector4(-738.0, -1465.0, 26.2, 115.0),
        heading = 115.0,
        radius = 40.0,
        blip = { sprite = 326, colour = 'gold', scale = 0.9 },
        types = { 'super', 'sports', 'muscle' },
        testTrack = { coords = vector3(-744.0, -1398.0, 24.0), radius = 260.0, seconds = 300 },
    },
    {
        id = 'premium',
        name = 'Premium Deluxe Motorsport',
        coords = vector3(489.0, -1342.0, 29.5),
        spawn = vector4(479.0, -1348.0, 28.6, 9.0),
        heading = 9.0,
        radius = 38.0,
        blip = { sprite = 326, colour = 'gold', scale = 0.9 },
        types = { 'sedan', 'suv', 'compact', 'sports', 'motorcycle' },
        testTrack = { coords = vector3(455.0, -1290.0, 31.0), radius = 220.0, seconds = 300 },
    },
    {
        id = 'sandy',
        name = 'Sandy Shores Auto & Super',
        coords = vector3(1728.0, -1631.0, 29.0),
        spawn = vector4(1720.0, -1640.0, 28.2, 265.0),
        heading = 265.0,
        radius = 36.0,
        blip = { sprite = 326, colour = 'orange', scale = 0.85 },
        types = { 'offroad', 'industrial', 'suv', 'muscle' },
        testTrack = { coords = vector3(1712.0, -1585.0, 29.0), radius = 300.0, seconds = 330 },
    },
}

Config.LotIndex = {}
for _, lot in ipairs(Config.Lots) do
    Config.LotIndex[lot.id] = lot
end

-- ─── Catalogue ───────────────────────────────────────────────
-- price = sticker price before Config.Sales.taxRate is applied.
Config.Catalogue = {
    compact = {
        label = 'Compact',
        taxBand = 0.04,
        items = {
            { label = 'Bollokan Prairie',       model = 'prairie',   price = 7500,   seats = 4, stock = 8, requiresLicense = false, financed = true },
            { label = 'Karin Diletante',        model = 'dilettante', price = 8200,  seats = 4, stock = 8, requiresLicense = false, financed = true },
            { label = 'Declasse Rhapsody',      model = 'rhapsody',  price = 8900,   seats = 4, stock = 6, requiresLicense = false, financed = true },
            { label = 'Karin Blista',           model = 'blista',    price = 9800,   seats = 4, stock = 7, requiresLicense = false, financed = true },
            { label = 'Benefactor Panto',       model = 'panto',     price = 11500,  seats = 2, stock = 5, requiresLicense = false, financed = true },
            { label = 'Weeny Issi',             model = 'issi2',     price = 13800,  seats = 4, stock = 6, requiresLicense = false, financed = true },
        },
    },
    sedan = {
        label = 'Saloon',
        taxBand = 0.06,
        items = {
            { label = 'Cheval Surge',           model = 'surge',     price = 9600,   seats = 4, stock = 6, requiresLicense = false, financed = true },
            { label = 'Albany Asea',            model = 'asea',      price = 10500,  seats = 4, stock = 8, requiresLicense = false, financed = true },
            { label = 'Declasse Premier',       model = 'premier',   price = 11800,  seats = 4, stock = 8, requiresLicense = false, financed = true },
            { label = 'Vapid Stanier',          model = 'stanier',   price = 13200,  seats = 4, stock = 7, requiresLicense = false, financed = true },
            { label = 'Willard Faction',        model = 'faction',   price = 14500,  seats = 4, stock = 6, requiresLicense = false, financed = true },
            { label = 'Albany Washington',      model = 'washington', price = 16900, seats = 4, stock = 6, requiresLicense = false, financed = true },
            { label = 'Obey Tailgater',         model = 'tailgater', price = 24500,  seats = 4, stock = 5, requiresLicense = false, financed = true },
            { label = 'Benefactor Schafter',    model = 'schafter2', price = 28500,  seats = 4, stock = 4, requiresLicense = false, financed = true },
        },
    },
    sports = {
        label = 'Sports',
        taxBand = 0.09,
        items = {
            { label = 'Karin Sultan',           model = 'sultan',    price = 92000,  seats = 4, stock = 4, requiresLicense = true, financed = true },
            { label = 'Maibatsu Penumbra',      model = 'penumbra',  price = 98000,  seats = 2, stock = 4, requiresLicense = true, financed = true },
            { label = 'Bravado Buffalo',        model = 'buffalo',   price = 105000, seats = 4, stock = 3, requiresLicense = true, financed = true },
            { label = 'Karin Futo',             model = 'futo',      price = 112000, seats = 2, stock = 4, requiresLicense = true, financed = true },
            { label = 'Karin Neon',             model = 'neon',      price = 118000, seats = 4, stock = 3, requiresLicense = true, financed = true },
            { label = 'Vapid Dominator',        model = 'dominator', price = 124000, seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Annis Elegy RH8',        model = 'elegy2',    price = 132000, seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Bravado Tampa',          model = 'tampa',     price = 138000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'Declasse Drift Tampa',   model = 'tampa2',    price = 145000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'Obey Omnis',             model = 'omnis',     price = 156000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'Pfister Comet',          model = 'comet2',    price = 164000, seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Dewbauchee Rapid GT',    model = 'rapidgt',   price = 178000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'Grotti Carbonizzare',    model = 'carbonizzare', price = 195000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'Dinka Jester',           model = 'jester',    price = 212000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'Dewbauchee Massacro',    model = 'massacro',  price = 228000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'Grotti Furia',           model = 'furia',     price = 245000, seats = 2, stock = 1, requiresLicense = true, financed = true },
        },
    },
    muscle = {
        label = 'Muscle',
        taxBand = 0.08,
        items = {
            { label = 'Declasse Sabre Turbo',   model = 'sabregt',   price = 42000,  seats = 2, stock = 5, requiresLicense = false, financed = true },
            { label = 'Vapid Dominator GTT',    model = 'dominator7', price = 48000, seats = 2, stock = 4, requiresLicense = true, financed = true },
            { label = 'Bravado Gauntlet',       model = 'gauntlet',  price = 54000,  seats = 2, stock = 4, requiresLicense = true, financed = true },
            { label = 'Albany Buccaneer',       model = 'buccaneer', price = 58000,  seats = 2, stock = 4, requiresLicense = true, financed = true },
            { label = 'Vapid Blade',            model = 'blade',     price = 62000,  seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Imponte Phoenix',        model = 'phoenix',   price = 68000,  seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Declasse Voodoo',        model = 'voodoo',    price = 74000,  seats = 2, stock = 3, requiresLicense = true, financed = true },
        },
    },
    suv = {
        label = 'SUV',
        taxBand = 0.07,
        items = {
            { label = 'Gallivanter Baller',     model = 'baller',    price = 22000,  seats = 4, stock = 6, requiresLicense = false, financed = true },
            { label = 'Canis Seminole',         model = 'seminole',  price = 26000,  seats = 4, stock = 5, requiresLicense = false, financed = true },
            { label = 'Vapid Radius',           model = 'radi',      price = 29000,  seats = 4, stock = 5, requiresLicense = false, financed = true },
            { label = 'Dundreary Landstalker',  model = 'landstalker', price = 34000, seats = 4, stock = 4, requiresLicense = false, financed = true },
            { label = 'Mammoth Patriot',        model = 'patriot',   price = 38000,  seats = 4, stock = 4, requiresLicense = false, financed = true },
            { label = 'Enus Huntley S',         model = 'huntley',   price = 43000,  seats = 4, stock = 3, requiresLicense = false, financed = true },
            { label = 'Declasse Granger',       model = 'granger',   price = 48000,  seats = 4, stock = 3, requiresLicense = false, financed = true },
        },
    },
    offroad = {
        label = 'Off-Road',
        taxBand = 0.05,
        items = {
            { label = 'Karin Rebel',            model = 'rebel',     price = 24000,  seats = 2, stock = 5, requiresLicense = false, financed = true },
            { label = 'Canis Mesa',             model = 'mesa',      price = 28000,  seats = 2, stock = 5, requiresLicense = false, financed = true },
            { label = 'Vapid Rancher XL',       model = 'rancherxl', price = 32000,  seats = 4, stock = 5, requiresLicense = false, financed = true },
            { label = 'Vapid Bodhi',            model = 'bodhi2',    price = 46000,  seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Vapid Caracara',         model = 'caracara',  price = 61000,  seats = 4, stock = 3, requiresLicense = true, financed = true },
            { label = 'Vapid Sandking XL',      model = 'sandking',  price = 68000,  seats = 4, stock = 3, requiresLicense = true, financed = true },
            { label = 'Vapid Sandking SWB',     model = 'sandking2', price = 79000,  seats = 2, stock = 2, requiresLicense = true, financed = true },
        },
    },
    motorcycle = {
        label = 'Motorcycles',
        taxBand = 0.05,
        items = {
            { label = 'Maibatsu Sanchez',       model = 'sanchez',   price = 14000,  seats = 2, stock = 6, requiresLicense = false, financed = true },
            { label = 'Pegassi Ruffian',        model = 'ruffian',   price = 18000,  seats = 2, stock = 5, requiresLicense = true, financed = true },
            { label = 'Pegassi Bati 801',       model = 'bati',      price = 26000,  seats = 2, stock = 5, requiresLicense = true, financed = true },
            { label = 'Shitzu Akuma',           model = 'akuma',     price = 34000,  seats = 2, stock = 4, requiresLicense = true, financed = true },
            { label = 'LCC Defiler',            model = 'defiler',   price = 48000,  seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Shitzu Hakuchou',        model = 'hakuchou',  price = 55000,  seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'Principe Thrust',        model = 'thrust',    price = 62000,  seats = 2, stock = 2, requiresLicense = true, financed = true },
        },
    },
    industrial = {
        label = 'Commercial',
        taxBand = 0.04,
        items = {
            { label = 'Vapid Speedo',           model = 'speedo',    price = 28000,  seats = 4, stock = 5, requiresLicense = false, financed = true },
            { label = 'Vapid Boxville',         model = 'boxville',  price = 38000,  seats = 2, stock = 4, requiresLicense = false, financed = true },
            { label = 'Maibatsu Mule',          model = 'mule',      price = 45000,  seats = 2, stock = 4, requiresLicense = false, financed = true },
            { label = 'Dundreary Benson',       model = 'benson',    price = 64000,  seats = 2, stock = 3, requiresLicense = true, financed = true },
            { label = 'JoBuilt Phantom',        model = 'phantom',   price = 118000, seats = 2, stock = 2, requiresLicense = true, financed = true },
            { label = 'JoBuilt Hauler',         model = 'hauler',    price = 145000, seats = 2, stock = 2, requiresLicense = true, financed = true },
        },
    },
}

Config.ModelIndex = {}
Config.ClassList = {}
for classKey, class in pairs(Config.Catalogue) do
    Config.ClassList[#Config.ClassList + 1] = classKey
    for _, item in ipairs(class.items or {}) do
        local entry = {}
        for key, value in pairs(item) do entry[key] = value end
        entry.class = classKey
        entry.classLabel = class.label
        entry.taxBand = class.taxBand or 0
        Config.ModelIndex[item.model] = entry
    end
end
table.sort(Config.ClassList)

-- ─── Finance / credit agreements ─────────────────────────────
Config.Finance = {
    enabled = true,
    minTerm = 4,                  -- weeks
    maxTerm = 96,
    minDownPercent = 0.10,
    apr = 0.085,                  -- annual rate
    maxWeeklyPayment = 15000,     -- a single week may never exceed this
    lateFeePercent = 0.12,        -- of one instalment
    graceWeeks = 1,
    defaultAfterWeeks = 3,        -- consecutive missed instalments
    weekSeconds = 7 * 24 * 60 * 60,
    repossessible = true,
    minBankBuffer = 1500,         -- must keep this after the down payment
}

-- ─── Test drives ─────────────────────────────────────────────
Config.TestDrive = {
    enabled = true,
    seconds = 300,
    limitPerHour = 2,
    windowSeconds = 3600,
    returnRadius = 260.0,
    insuranceFee = 1500,
    minCash = 2000,
    damageChargePercent = 0.05,   -- of sticker, if returned wrecked
    damageHealthThreshold = 400,  -- body health below this counts as wrecked
}

-- ─── Garages ─────────────────────────────────────────────────
Config.Garages = {
    {
        id = 'Legion_Square', name = 'Legion Square Garage',
        coords = vector3(215.0, -791.0, 30.7),
        spawn = vector4(222.0, -803.0, 30.6, 160.0),
        radius = 30.0,
        blip = { sprite = 357, colour = 'grey', scale = 0.7 },
        slots = 8,
    },
    {
        id = 'Mirror_Park', name = 'Mirror Park Garage',
        coords = vector3(1039.0, -763.0, 57.6),
        spawn = vector4(1034.0, -775.0, 58.0, 90.0),
        radius = 28.0,
        blip = { sprite = 357, colour = 'grey', scale = 0.7 },
        slots = 8,
    },
    {
        id = 'Sandy_Shores', name = 'Sandy Shores Storage',
        coords = vector3(1730.0, 3710.0, 34.1),
        spawn = vector4(1734.0, 3712.0, 34.2, 180.0),
        radius = 30.0,
        blip = { sprite = 357, colour = 'orange', scale = 0.7 },
        slots = 6,
    },
    {
        id = 'Paleto', name = 'Paleto Bay Lock-Up',
        coords = vector3(-200.0, 6250.0, 31.5),
        spawn = vector4(-193.0, 6260.0, 31.5, 45.0),
        radius = 26.0,
        blip = { sprite = 357, colour = 'green', scale = 0.7 },
        slots = 4,
    },
    {
        id = 'Airport', name = 'Airport Ring Secure Store',
        coords = vector3(-796.0, -2020.0, 9.2),
        spawn = vector4(-790.0, -2028.0, 9.2, 230.0),
        radius = 26.0,
        blip = { sprite = 357, colour = 'sapphire', scale = 0.7 },
        slots = 6,
    },
    {
        id = 'Vespucci', name = 'Vespucci Canals Lock-Up',
        coords = vector3(-1150.0, -1510.0, 4.4),
        spawn = vector4(-1144.0, -1518.0, 4.4, 300.0),
        radius = 24.0,
        blip = { sprite = 357, colour = 'crimson', scale = 0.7 },
        slots = 10,
    },
}

Config.GarageIndex = {}
for _, garage in ipairs(Config.Garages) do
    Config.GarageIndex[garage.id] = garage
end

--- Flat fee to relocate a stored vehicle between garages.
Config.GarageMoveFee = 1200

-- ─── Dealer trade licence ────────────────────────────────────
Config.Licence = {
    requireDriverLicence = false,  -- flip to true once police licences are seeded
    tradeLicenceRequired = false,  -- staff need a trade licence to sell on a lot
    validityWeeks = 52,
    buyFrom = 'premium',
}

-- ─── Blips ───────────────────────────────────────────────────
Config.Blips = {
    enabled = true,
    prefix = 'dealer_',
    distanceCull = 1400.0,
    showGarages = true,
    promptDistance = 60.0,
}

-- ─── Money rules ─────────────────────────────────────────────
Config.Money = {
    maxCard = 2500000,
    duplicateWindow = 4,           -- same model purchases inside this = rejected
    transferFee = 2500,            -- player-to-player transfer paperwork
}

-- ─── Permissions ─────────────────────────────────────────────
Config.Permissions = {
    manage = 'grand.dealership.manage',
    gift = 'grand.dealership.gift',
    aceGroups = { 'group.admin', 'group.mod' },
}

--- Jobs that may work a forecourt without an ace.
Config.StaffJobs = { 'cardealer', 'dealer' }

-- ─── Sales rules ─────────────────────────────────────────────
Config.Sales = {
    taxRate = 0.08,
    maxOwnedVehicles = 20,
    cooldownSeconds = 6,
    browseCooldown = 2,
    restockMinutes = 45,
    giftMaxPrice = 500000,
    sellBackPercent = 0.55,        -- dealer buys back at this of sticker
    warrantyDays = 14,
}

-- ─── Timing ──────────────────────────────────────────────────
Config.Timing = {
    financeTickMs = 60000,
    testDriveTickMs = 1000,
    garageTickMs = 500,
    stockRefreshMs = 60000,
    saveIntervalMs = 300000,
}

-- ─── Commands ────────────────────────────────────────────────
Config.Commands = {
    dealership = 'dealership',
    catalogue = 'catalogue',
    buycar = 'buycar',
    testdrive = 'testdrive',
    garage = 'garage',
    dealeradmin = 'dealeradmin',
    paycar = 'paycar',
    sellcar = 'sellcar',
}

-- ─── Messages ────────────────────────────────────────────────
Config.Messages = {
    notStaff = 'You are not on the payroll at this lot.',
    tooFar = 'Walk up to the dealership first.',
    noFunds = 'You cannot cover that amount.',
    needsLicence = 'You need a valid driver licence for that class.',
    purchaseOk = 'The vehicle is registered to you and stored in your garage.',
    testDriveOk = 'Test drive started. Bring it back before the timer runs out.',
    testDriveEnd = 'Test drive closed out.',
    impounded = 'That vehicle is impounded. Sort it out before collecting it.',
    noVehicles = 'Your garage is empty.',
    vehicleOut = 'That vehicle is already out.',
    notYours = 'That vehicle is not registered to you.',
    stored = 'Vehicle stored.',
}
