-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/config.lua
--  Every tunable the family layer reads. Nothing is hardcoded in
--  the server or client scripts. Framework-agnostic: no qb, no esx.
--
--  Column contract: root database.sql owns `grand_families.balance`
--  (the vault). Anything extra is added additively at boot through
--  Config.Database.Columns and can never conflict with it.
-- ─────────────────────────────────────────────────────────────

Config = {}

-- error | warn | info | debug
Config.LogLevel = 'info'

-- ─── Families ─────────────────────────────────────────────────
Config.Families = {
    MaxMembers        = 50,
    MaxRank           = 10,
    CreationCost      = 50000,     -- $50k, paid from cash into the vault
    MinNameLength     = 3,
    MaxNameLength     = 20,
    MaxTagLength      = 5,
    MinVaultDeposit   = 100,       -- matches grand_phone Config.FamilyHub.vaultMinDeposit
    DefaultVaultCap   = 2500000,   -- 0 = uncapped
    StartingVault     = 0,

    BlockedNames = {
        'police', 'lspd', 'government', 'state', 'ems', 'ambulance',
        'admin', 'staff', 'moderator', 'fbi', 'fib', 'aos',
    },
}

-- ─── Ranks ────────────────────────────────────────────────────
-- Titles line up with grand_phone Config.FamilyHub.rankTitles so the
-- phone hub renders the same ladder without a translation table.
Config.RankTitles = {
    [1]  = 'Affiliate',
    [2]  = 'Prospect',
    [3]  = 'Recruit',
    [4]  = 'Associate',
    [5]  = 'Soldier',
    [6]  = 'Made Man',
    [7]  = 'Capo',
    [8]  = 'Consigliere',
    [9]  = 'Underboss',
    [10] = 'Godfather',
}

-- Permissions ladder downward: a rank inherits every lower rung.
Config.RankPermissions = {
    [1] = { -- Affiliate
        canInvite = false, canKick = false, canPromote = false,
        canDeposit = false, canWithdraw = false,
        canManageTurf = false, canManageProperties = false,
        canSeeVault = true,
    },
    [4] = { -- Associate
        canInvite = true, canKick = false, canPromote = false,
        canDeposit = true, canWithdraw = false,
        canManageTurf = false, canManageProperties = false,
        canSeeVault = true,
    },
    [5] = { -- Soldier
        canInvite = true, canKick = true, canPromote = false,
        canDeposit = true, canWithdraw = false,
        canManageTurf = true, canManageProperties = false,
        canSeeVault = true,
    },
    [7] = { -- Capo
        canInvite = true, canKick = true, canPromote = true,
        canDeposit = true, canWithdraw = true,
        canManageTurf = true, canManageProperties = true,
        canSeeVault = true,
    },
    [10] = { -- Godfather
        canInvite = true, canKick = true, canPromote = true,
        canDeposit = true, canWithdraw = true,
        canManageTurf = true, canManageProperties = true,
        canSeeVault = true,
        canDissolveFamily = true, canSetTaxRate = true, canSetVaultCap = true,
    },
}

-- ─── Income ───────────────────────────────────────────────────
-- All intervals are in SECONDS (the old millisecond values were fed
-- straight to Wait() in one place and to a reschedule in another).
Config.Income = {
    payoutSeconds     = 3600,      -- hourly tick for properties + turfs
    interestSeconds   = 86400,     -- daily interest pass
    interestRate      = 0.001,     -- 0.1% of vault per pass
    solarYield        = 1500,      -- per panel per hour (phone hub mirrors this)
    oilYield          = 5000,      -- per well per hour
    maxSolarPanels    = 5,
    maxOilWells       = 3,
    solarCost         = 75000,
    oilCost           = 200000,
    offlineAccrual    = true,      -- settle owed hours since last_payout on boot
    maxCatchupHours   = 48,        -- never pay more than two days back
    capPerFamily      = 250000,    -- vault income ceiling per payout pass
}

-- ─── Invitations ──────────────────────────────────────────────
Config.Invites = {
    ttlSeconds   = 300,            -- an invite expires after 5 minutes
    maxPerFamily = 5,
    pruneSeconds = 600,
}

-- ─── Turf ownership (the war engine itself lives in grand_gangs) ──
Config.TurfWar = {
    hourlyBase     = 10000,        -- tier 1 = $10k/hr, tier 2 = $15k, tier 3 = $22k
    tierMultiplier = { [1] = 1.0, [2] = 1.5, [3] = 2.2 },
    heightTolerance = 60.0,        -- Z window that still counts as "inside" a turf
    maxTurfsPerFamily = 6,
    captureSeconds = 900,          -- 15 minutes of net favourable presence
    maxConcurrentWars = 3,

    -- Keyed by zone id so grand_gangs can look one up in O(1).
    -- Ids and coordinates MUST match grand_gangs/config.lua.
    TurfLocations = {
        davis        = { id = 'davis',      name = 'Davis',                  tier = 1, ghetto = true,
                         coords = vector3(-1020.3, -967.2, 11.6), radius = 190.0 },
        grove        = { id = 'grove',      name = 'Grove Street',           tier = 1, ghetto = false,
                         coords = vector3(-124.9, -1586.8, 33.5), radius = 150.0 },
        rundown      = { id = 'rundown',    name = 'The RunDown',            tier = 1, ghetto = true,
                         coords = vector3(-1187.0, -1121.0, 4.7),  radius = 200.0 },
        seoul        = { id = 'seoul',      name = 'Little Seoul',           tier = 1, ghetto = true,
                         coords = vector3(20.5, -1461.2, 29.3),    radius = 165.0 },
        vimmo        = { id = 'vimmo',      name = "Vimmo's Corner",         tier = 1, ghetto = false,
                         coords = vector3(271.5, -1494.4, 29.3),   radius = 120.0 },
        strawberry   = { id = 'strawberry', name = 'Strawberry',             tier = 1, ghetto = true,
                         coords = vector3(-45.0, -1622.0, 28.6),   radius = 175.0 },
        citadel      = { id = 'citadel',    name = 'Citadel Flats',          tier = 1, ghetto = true,
                         coords = vector3(398.0, -1621.0, 28.7),   radius = 185.0 },
        lamesa       = { id = 'lamesa',     name = 'La Mesa',                tier = 1, ghetto = false,
                         coords = vector3(133.0, -1282.0, 29.2),   radius = 155.0 },
        mirrorpark   = { id = 'mirrorpark', name = 'Mirror Park',            tier = 2, ghetto = false,
                         coords = vector3(-557.0, -120.0, 36.0),   radius = 170.0 },
        rockford     = { id = 'rockford',   name = 'Rockford Hills',         tier = 3, ghetto = false,
                         coords = vector3(-1102.0, -407.0, 13.0),  radius = 210.0 },
        vespucci     = { id = 'vespucci',   name = 'Vespucci Beach',         tier = 2, ghetto = false,
                         coords = vector3(-1223.0, -1453.0, 4.3),  radius = 200.0 },
        delperro     = { id = 'delperro',   name = 'Del Perro',              tier = 2, ghetto = false,
                         coords = vector3(-1836.0, -1234.0, 13.0), radius = 220.0 },
        sandy        = { id = 'sandy',      name = 'Sandy Shores',           tier = 1, ghetto = true,
                         coords = vector3(1740.0, 3780.0, 34.2),   radius = 240.0 },
        paleto       = { id = 'paleto',     name = 'Paleto Bay',             tier = 2, ghetto = false,
                         coords = vector3(-245.0, 6630.0, 7.5),    radius = 230.0 },
        airport      = { id = 'airport',    name = 'Los Santos International', tier = 3, ghetto = false,
                         coords = vector3(-1037.0, -2735.0, 20.1), radius = 260.0 },
        vinewood     = { id = 'vinewood',   name = 'Vinewood Blvd',          tier = 2, ghetto = false,
                         coords = vector3(-1188.0, -1418.0, 4.6),  radius = 240.0 },
    },
}

-- ─── Progression / stats ──────────────────────────────────────
Config.Progress = {
    turfPoints  = 50,    -- family points gained per capture
    ratingLoss  = 25,    -- rating lost per turf lost
    maxLevel    = 25,
}

-- ─── Database ─────────────────────────────────────────────────
Config.Database = {
    AutoCreate = true,

    -- Additive only. Anything root database.sql already created is
    -- detected through information_schema and skipped.
    Columns = {
        grand_families = {
            { name = 'tag',             definition = "VARCHAR(5) NULL UNIQUE" },
            { name = 'color',           definition = "VARCHAR(7) NOT NULL DEFAULT '#FFFFFF'" },
            { name = 'tax_rate',        definition = "DECIMAL(5,2) NOT NULL DEFAULT 0.00" },
            { name = 'active_members',  definition = "INT NOT NULL DEFAULT 1" },
            { name = 'total_properties',definition = "INT NOT NULL DEFAULT 0" },
            { name = 'total_turfs',     definition = "INT NOT NULL DEFAULT 0" },
            { name = 'description',     definition = "TEXT NULL" },
            { name = 'deleted',         definition = "TINYINT(1) NOT NULL DEFAULT 0" },
            { name = 'vault_cap',       definition = "BIGINT NOT NULL DEFAULT 0" },
            { name = 'last_income_at',  definition = "TIMESTAMP NULL DEFAULT NULL" },
        },
        grand_family_members = {
            { name = 'total_deposits',     definition = "BIGINT NOT NULL DEFAULT 0" },
            { name = 'total_withdrawals',  definition = "BIGINT NOT NULL DEFAULT 0" },
            { name = 'kills_in_turf',      definition = "INT NOT NULL DEFAULT 0" },
            { name = 'captures_assisted',  definition = "INT NOT NULL DEFAULT 0" },
        },
    },
}

-- ─── Chat commands ────────────────────────────────────────────
Config.Commands = {
    CreateFamily = 'createfamily',
    Family       = 'family',
    Accept       = 'acceptinvite',
    Deposit      = 'deposit',
    Withdraw     = 'withdraw',
    Dissolve     = 'dissolve',
    Turfs        = 'turfs',
    Admin        = 'familyadmin',
}
