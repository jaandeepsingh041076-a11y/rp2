-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/config.lua
--  Every tunable the core engine reads. Nothing is hard-coded
--  inside the server or client scripts — change it here.
--
--  Framework-agnostic: no qb-core, no qbx, no esx.
-- ─────────────────────────────────────────────────────────────

Config = {}

Config.Debug = false

-- ─── Identity / citizenid ────────────────────────────────────
Config.Identity = {
    -- Citizen IDs look like ABJKLM12345 — 6 letters + 5 digits.
    Prefix            = '',
    Letters           = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ',
    LetterLength      = 6,
    NumberLength      = 5,

    -- Vehicle plates this resource generates: GRxxxx (see Util.GeneratePlate)
    PlatePrefix       = 'GR',
    PlateDigits       = 4,

    MaxCharacters     = 4,        -- characters allowed per license
    MinNameLength     = 2,
    MaxNameLength     = 20,

    -- Blocked substrings in first/last names (lower-case compare)
    BlockedNames      = {
        'admin', 'root', 'console', 'npc', 'police', 'fbi',
        'test', 'fuck', 'shit', 'retard', 'nigger'
    },
    BlockedExact      = { 'unemployed', 'unknown' },
}

-- ─── Money / economy ─────────────────────────────────────────
Config.Money = {
    -- Hard ceilings. AddMoney clamps to these, so a runaway loop
    -- can never mint more than the cap.
    Caps = {
        cash   = 50000,
        bank   = 2500000,
        crypto = 1000000,
    },

    -- Applied to a brand new character (money JSON column)
    Starting = {
        cash   = 5000,
        bank   = 25000,
        crypto = 0,
    },

    -- Sales tax charged on registered vendor transactions
    TaxRate  = 0.08,

    -- Seconds between two identical transactions from the same source.
    -- Guards against a double-firing UI button duplicating money.
    DuplicateWindowSeconds = 2,

    -- Single-transaction ceiling regardless of caps
    MaxTransaction = 250000,

    -- Deposits at or under this amount are never taxed
    TaxFreeDeposit = 5000,

    -- Log every movement into grand_money_logs
    LogTransactions = true,

    -- Mirror the money JSON to `characters.money` on every mutation
    -- (not just on autosave). Slightly more queries, zero lost cash.
    FlushOnEveryChange = true,
}

Config.Bank = {
    Enabled        = true,
    InterestRate   = 0.005,      -- 0.5% per interest tick
    InterestTick   = 3600,       -- seconds between ticks
    MaxInterest    = 50000,      -- cap per tick so the economy can't break
    MinBalance     = 100,        -- no interest under this balance
    MaxBankBalance = 2500000,
}

-- ─── Salaries ────────────────────────────────────────────────
Config.Salary = {
    Enabled              = true,
    PayoutInterval       = 3600,  -- seconds between paydays
    FirstPayoutDelay     = 20,    -- seconds after boot before the first payday
    BasePay              = 100,   -- everyone gets this, even unemployed
    LevelMultiplier      = 25,    -- + level * multiplier
    RequireOnDuty        = true,  -- unpaid when off duty (job.CanBeOffDuty overrides)
    OffDutyMultiplier    = 0.0,   -- off-duty share of the paycheck
    DefaultJobPay        = 300,   -- fallback for jobs with no entry
    DebitTo              = 'bank',
}

-- ─── Persistence ─────────────────────────────────────────────
Config.Persistence = {
    AutosaveInterval   = 300,     -- seconds between dirty flushes
    SaveOnDrop         = true,
    SaveOnShutdown     = true,
    PositionInterval   = 60,      -- seconds between passive position writes
    AutoCreateSchema   = true,    -- run sql/schema.sql at boot (CREATE IF NOT EXISTS only)
}

-- ─── Progression / EXP ───────────────────────────────────────
Config.Progress = {
    MaxLevel          = 100,
    ExpInterval       = 900,      -- seconds of activity per EXP point
    AFKTimeout        = 180,      -- idle longer than this and EXP stops accruing
    ActivityInterval  = 30,       -- seconds between client activity heartbeats
    -- EXP needed to climb FROM a level. Gentle quadratic grind.
    ExpCurve          = function(level)
        return 100 + (level * 25) + (level * level * 2)
    end,
}

--- EXP required to advance from `level` to `level + 1`.
---@param level number
---@return number
function Config.ExpForLevel(level)
    local curve = Config.Progress.ExpCurve
    local need = type(curve) == 'function' and curve(level) or tonumber(curve) or 100
    return math.max(1, Util.Floor(need))
end

-- ─── Logins / spawning ───────────────────────────────────────
Config.Logins = {
    -- Seconds a session may take to reach the character screen.
    LoadTimeout        = 120,
    -- Kick reason strings (shown to the client by FiveM)
    KickDuplicate      = 'You already have an active session on this server.',
    KickWhitelist      = 'Your license is not whitelisted for Grand RP.',
    KickTooManyChars   = 'You have reached the maximum number of characters.',
    -- How many login attempts before the character screen rate-limits
    MaxCreateAttempts  = 5,
    CreateCooldown     = 30,       -- seconds between character creations
}

Config.Whitelist = {
    Enabled            = false,   -- gate joins behind the list below
    -- Licenses allowed when Enabled is true ('license:xxxx' or '*' for all)
    Identifiers        = { '*' },
    -- Job/whitelist gate for specific high-tier jobs (LSPD/FIB etc.)
    JobWhitelist       = {
        Enabled = false,
        -- identifier fragments allowed to take these jobs
        Jobs    = { 'lspd', 'sahp', 'fib', 'judge', 'lawyer' },
    },
    -- VIP-only jobs, keyed by minimum users.vip_level
    VipJobs            = {},
}

-- ─── Positions ───────────────────────────────────────────────
Config.Positions = {
    -- Where a fresh character wakes up
    Spawn = {
        { x = -1037.0, y = -2737.0, z = 20.16, heading = 335.0, name = 'Legion Square' },
        { x = 445.0,   y = -981.4,  z = 29.69, heading = 175.0, name = 'Legion Square Garage' },
    },

    -- Hospitals a body is transported to when they bleed out
    Hospital = {
        { x = 306.0,  y = -586.4, z = 43.28, heading = 73.0,  name = 'Pillbox Hill' },
        { x = 1839.9, y = 475.0,  z = 34.9,  heading = 284.0, name = 'Sandy Shores' },
        { x = -247.8, y = 6302.0, z = 31.48, heading = 115.0, name = 'Paleto Bay' },
    },

    -- Where the character-select / loading screen parks the ped
    Lounge = { x = -1549.4, y = -952.5, z = 10.9, heading = 65.0 },

    -- Police stations used by the wanted-level teleport helper
    Police = {
        { x = 441.0,  y = -985.0, z = 29.0,  name = 'Mission Row' },
        { x = -44.0,  y = -585.5, z = 37.95, name = 'Paleto' },
        { x = 45.0,   y = -1095.0, z = 29.5, name = 'Davis' },
    },
}

-- ─── Death / respawn ─────────────────────────────────────────
Config.Death = {
    BleedOutSeconds   = 60,      -- time before a downed ped dies properly
    ReviveWindow      = 12,      -- seconds after death where EMS can revive free
    RespawnCost       = 500,     -- flat hospital bill
    RespawnCostPerStar = 250,    -- + this * wanted level
    MaxRespawnCost    = 5000,
    ChargeBankFirst   = true,    -- try bank, then cash
    -- Wanted levels still active after respawn get an extra penalty
    KeepWantedOnRespawn = false,
    InsuranceJobs     = { 'lspd', 'sahp', 'fib', 'ambulance', 'paramedic' },
    InsuranceDiscount = 1.0,     -- 100% off the bill for these jobs on duty
    FadeInMs          = 2000,
    FadeOutMs         = 1500,
}

Config.Wanted = {
    -- Penalty applied on respawn, indexed by wanted star count (1-5)
    Penalties = {
        [1] = { cost = 0,    weaponStrip = false },
        [2] = { cost = 250,  weaponStrip = false },
        [3] = { cost = 500,  weaponStrip = true  },
        [4] = { cost = 1000, weaponStrip = true  },
        [5] = { cost = 2000, weaponStrip = true  },
    },
    ClearOnRespawn = true,
}

-- ─── Keybinds ────────────────────────────────────────────────
-- ox_lib is optional; when it is missing we fall back to raw controls.
Config.Keys = {
    -- control ids (see FiveM control list)
    SeatbeltToggle = 80,        -- [X] left control
    Interact       = 38,        -- [E]
    CancelDowned   = 202,       -- [Backspace] / clear-2
    StatusMenu     = 47,        -- [G]
    RegisterKeyMapping = {
        StatusMenu = { command = 'grandstatus', label = 'Open Grand RP status', default = 'G' },
    },
}

-- ─── Vitals ──────────────────────────────────────────────────
Config.Vitals = {
    HungerDecayPerMinute = 0.35,
    ThirstDecayPerMinute = 0.50,
    StressPerDeath       = 12,
    StressDecayPerMinute = 0.25,
    OverflowDamage       = true,   -- hit 0 hunger/thirst and the ped starts dying
    MinStress            = 0,
    MaxStress            = 100,
}

-- ─── HUD bridge ──────────────────────────────────────────────
Config.Hud = {
    Interval          = 1000,      -- ms between pushes
    StateBagKey       = 'grand_hud',
    -- Resources that may want our data; missing ones are skipped safely
    Consumers         = { 'grand_hud', 'grand_phone', 'grand_radial' },
    NuiMessageAction  = 'grand:hud',
}

-- ─── Jobs ────────────────────────────────────────────────────
-- Every entry is a real GTA-side profession. `Pay` is the hourly
-- supplement on top of Config.Salary.BasePay. `Weapons` / `Vehicles`
-- are advisory: other resources read them through the GetJobList export.
Config.Jobs = {}

local function Job(key, label, type, pay, grades, options)
    options = options or {}
    Config.Jobs[#Config.Jobs + 1] = {
        name        = key,
        label       = label,
        type        = type,          -- 'legal' | 'illegal' | 'emergency' | 'government'
        pay         = pay,
        grades      = grades or { [0] = { label = 'Employee', multiplier = 1.0 } },
        whitelisted = options.whitelisted or false,
        canBeOffDuty = options.offDuty ~= false,
        onDutyOnly  = options.onDutyOnly or false,
        gang        = options.gang or false,
        faction     = options.faction or nil,
        vehicles    = options.vehicles or {},
        weapons     = options.weapons or {},
        outfit      = options.outfit or nil,
        spawn       = options.spawn or nil,
    }
end

-- ─── Legal / civilian ────────────────────────────────────────
Job('unemployed',   'Unemployed',    'legal', 0,    { [0] = { label = 'Citizen', multiplier = 1.0 } })
Job('citizen',      'Citizen',       'legal', 0)
Job('taxi',         'Taxi Driver',   'legal', 700,  {
    [0] = { label = 'Driver', multiplier = 1.0 },
    [1] = { label = 'Senior Driver', multiplier = 1.15 },
    [2] = { label = 'Dispatcher', multiplier = 1.35 },
}, { vehicles = { 'taxi', 'taxi2' }, spawn = { x = 870.1, y = -1310.4, z = 81.0 } })
Job('tow',          'Tow Truck',     'legal', 600,  {
    [0] = { label = 'Driver', multiplier = 1.0 },
    [1] = { label = 'Foreman', multiplier = 1.2 },
}, { vehicles = { 'towtruck2', 'towtruck' } })
Job('trucker',      'Long Haul',     'legal', 850,  {
    [0] = { label = 'Driver', multiplier = 1.0 },
    [1] = { label = 'Lead Driver', multiplier = 1.2 },
    [2] = { label = 'Fleet Manager', multiplier = 1.45 },
}, { vehicles = { 'phaeton', 'rentaltruck' } })
Job('bus',          'Bus Driver',    'legal', 600)
Job('garbage',      'Sanitation',    'legal', 500,  nil, { vehicles = { 'trashc' } })
Job('miner',        'Miner',         'legal', 850,  {
    [0] = { label = 'Hauler', multiplier = 1.0 },
    [1] = { label = 'Excavator', multiplier = 1.25 },
    [2] = { label = 'Foreman', multiplier = 1.5 },
}, { spawn = { x = 2972.8, y = -3890.1, z = 37.7 } })
Job('fisher',       'Fisherman',     'legal', 750,  nil, { spawn = { x = -1370.0, y = -44.0, z = 8.6 } })
Job('farmer',       'Farmer',        'legal', 700,  {
    [0] = { label = 'Hand', multiplier = 1.0 },
    [1] = { label = 'Ranch Hand', multiplier = 1.2 },
    [2] = { label = 'Foreman', multiplier = 1.4 },
}, { spawn = { x = 1693.0, y = -981.0, z = 38.9 } })
Job('logger',       'Lumberjack',    'legal', 800)
Job('rancher',      'Rancher',       'legal', 780)
Job('dockworker',   'Docks Crew',    'legal', 650)
Job('pilot',        'Cargo Pilot',   'legal', 1400, {
    [0] = { label = 'Co-Pilot', multiplier = 1.0 },
    [1] = { label = 'Captain', multiplier = 1.3 },
}, { vehicles = { 'mule', 'vestra' } })
Job('mechanic',     'Auto Mechanic', 'legal', 900,  {
    [0] = { label = 'Apprentice', multiplier = 1.0 },
    [1] = { label = 'Mechanic', multiplier = 1.2 },
    [2] = { label = 'Lead Tech', multiplier = 1.4 },
    [3] = { label = 'Owner', multiplier = 1.7 },
}, { vehicles = { 'flat', 'towtruck' } })
Job('cardealer',    'Car Dealer',    'legal', 1100)
Job('realestate',   'Real Estate',   'legal', 1300)
Job('bartender',    'Bartender',     'legal', 550)
Job('chef',         'Chef',          'legal', 800)
Job('retail',       'Shop Clerk',    'legal', 450)
Job('security',     'Security Guard', 'legal', 750, {
    [0] = { label = 'Guard', multiplier = 1.0 },
    [1] = { label = 'Shift Lead', multiplier = 1.2 },
    [2] = { label = 'Operations', multiplier = 1.5 },
})
Job('newsreporter', 'Journalist',    'legal', 950)
Job('pilotmedic',   'Air Medevac',   'emergency', 1500, nil, { faction = 'ems', vehicles = { 'mav' } })

-- ─── Emergency / government ──────────────────────────────────
local PoliceGrades = {
    [0] = { label = 'Cadet',            multiplier = 1.0 },
    [1] = { label = 'Trooper',          multiplier = 1.1 },
    [2] = { label = 'Senior Trooper',   multiplier = 1.2 },
    [3] = { label = 'Sergeant',         multiplier = 1.35 },
    [4] = { label = 'Lieutenant',       multiplier = 1.5 },
    [5] = { label = 'Captain',          multiplier = 1.75 },
    [6] = { label = 'Chief',            multiplier = 2.0 },
}
local EmdTGrades = {
    [0] = { label = 'EMT',              multiplier = 1.0 },
    [1] = { label = 'Senior EMT',       multiplier = 1.15 },
    [2] = { label = 'Paramedic',        multiplier = 1.3 },
    [3] = { label = 'Shift Supervisor', multiplier = 1.5 },
    [4] = { label = 'EMS Chief',        multiplier = 1.8 },
}

Job('lspd',       'Los Santos Police Dept.', 'government', 1500, PoliceGrades, {
    whitelisted = true, faction = 'police', offDuty = true,
    vehicles = { 'police', 'police2', 'police3', 'policeb' },
    weapons  = { 'weapon_pistol', 'weapon_microsmg', 'weapon_stungun', 'weapon_pumpshotgun' },
    outfit   = 'lspd_standard',
})
Job('sahp',       'San Andreas Highway Patrol', 'government', 1450, PoliceGrades, {
    whitelisted = true, faction = 'police',
    vehicles = { 'police', 'police2', 'polyice', 'sheriff' },
    weapons  = { 'weapon_pistol', 'weapon_microsmg' },
    outfit   = 'sahp_standard',
})
Job('fib',        'Federal Investigation Bureau', 'government', 2200, PoliceGrades, {
    whitelisted = true, faction = 'federal',
    vehicles = { 'fbi', 'fbi2', 'riot' },
    weapons  = { 'weapon_pistol', 'weapon_carbinerifle', 'weapon_microsmg' },
    outfit   = 'fib_standard',
})
Job('ambulance',  'Paramedic',           'emergency', 1200, EmdTGrades, {
    whitelisted = true, faction = 'ems',
    vehicles = { 'ambulance', 'ride' },
    outfit   = 'ems_standard',
})
Job('paramedic',  'EMS Responder',       'emergency', 1050, EmdTGrades, {
    faction = 'ems', vehicles = { 'ambulance' },
})
Job('doctors',    'Hospital Staff',      'emergency', 1600, EmdTGrades, { faction = 'ems' })
Job('judge',      'Municipal Judge',     'government', 1800, {
    [0] = { label = 'Judge', multiplier = 1.0 },
    [1] = { label = 'Chief Justice', multiplier = 1.4 },
}, { whitelisted = true })
Job('lawyer',     'Defense Attorney',    'legal', 1400, {
    [0] = { label = 'Associate', multiplier = 1.0 },
    [1] = { label = 'Partner', multiplier = 1.4 },
}, { whitelisted = true })
Job('mechanicgov','City Works',          'legal', 700)
Job('armsdeal',   'Licenced Gunsmith',   'legal', 900, nil, { whitelisted = true })

-- ─── Illegal / gangs ─────────────────────────────────────────
local GangGrades = {
    [0] = { label = 'Associate',  multiplier = 1.0 },
    [1] = { label = 'Shot',         multiplier = 1.15 },
    [2] = { label = 'Full Gang',    multiplier = 1.3 },
    [3] = { label = 'OG',           multiplier = 1.5 },
    [4] = { label = 'Capo',         multiplier = 1.7 },
    [5] = { label = 'Leader',       multiplier = 2.0 },
}

Job('ballas',     'The Ballas',          'illegal', 0, GangGrades, {
    gang = true, faction = 'ballas',
    weapons = { 'weapon_pistol', 'weapon_microsmg' },
})
Job('vagos',      'Vagos Riders',        'illegal', 0, GangGrades, {
    gang = true, faction = 'vagos',
    vehicles = { 'essii', 'bati2' },
})
Job('lostmc',     'The Lost MC',         'illegal', 0, GangGrades, {
    gang = true, faction = 'lost',
    vehicles = { 'hexer', 'bati' },
})
Job('marabunta',  'Marabunta Grande',    'illegal', 0, GangGrades, { gang = true, faction = 'marabunta' })
Job('hood',       'Grove Street Families','illegal', 0, GangGrades, { gang = true, faction = 'grove' })
Job('cartel',     'Cartel Enforcer',     'illegal', 0, GangGrades, { gang = true, faction = 'cartel' })
Job('drugdealer', 'Drug Dealer',         'illegal', 0, {
    [0] = { label = 'Runner', multiplier = 1.0 },
    [1] = { label = 'Dealer', multiplier = 1.3 },
    [2] = { label = 'Chef',   multiplier = 1.6 },
}, { gang = true })
Job('weapondealer','Arms Trafficker',    'illegal', 0, {
    [0] = { label = 'Courier', multiplier = 1.0 },
    [1] = { label = 'Broker',  multiplier = 1.4 },
}, { gang = true })

-- ─── Lookup indexes (built once at load, safe because config runs shared) ───
Config.JobIndex = {}
for i = 1, #Config.Jobs do
    Config.JobIndex[Config.Jobs[i].name] = Config.Jobs[i]
end

-- ─── Progression / EXP ───────────────────────────────────────
Config.Progress = {
    MaxLevel          = 100,
    ExpInterval       = 900,      -- seconds of activity per EXP point
    AFKTimeout        = 180,      -- idle longer than this and EXP stops accruing
    ActivityInterval  = 30,       -- seconds between client activity heartbeats
    -- EXP needed to climb FROM a level. Gentle quadratic grind.
    ExpCurve          = function(level)
        return 100 + (level * 25) + (level * level * 2)
    end,
}

--- EXP required to advance from `level` to `level + 1`.
---@param level number
---@return number
function Config.ExpForLevel(level)
    local curve = Config.Progress.ExpCurve
    local need = type(curve) == 'function' and curve(level) or tonumber(curve) or 100
    return math.max(1, Util.Floor(need))
end

-- ─── Notifications ───────────────────────────────────────────────
Config.Notifications = {
    LevelUp   = 'You reached level %s!',
    Salary    = 'Salary deposited: $%s',
    Interest  = 'Bank interest earned: $%s',
    Deposit   = 'Deposited $%s',
    Withdraw  = 'Withdrew $%s',
    Death     = 'You were downed',
    Hospital  = 'Hospital bill: $%s',
    Seatbelt  = 'Seatbelt %s',
    DutyOn    = 'You are now on duty',
    DutyOff   = 'You are now off duty',
}

--- Hourly supplement for a job name, or the default.
---@param jobName string
---@return number
function Config.GetJobPay(jobName)
    local job = Config.JobIndex[jobName]
    if job and job.pay and job.pay > 0 then return job.pay end
    return Config.Salary.DefaultJobPay
end
