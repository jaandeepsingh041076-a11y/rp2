-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/config.lua
--  Every tunable for the turf / territory / PvP layer.
--  16 Los Santos & San Andreas turfs, 6 gang families, war rules,
--  income rules, red-zone PvP rules, blip rules, permissions.
--  Keys are ASCII only; never name a column `until`, `end` or `then`.
-- ─────────────────────────────────────────────────────────────

Config = {}

Config.Debug = false
Config.Prefix = 'grand_gangs'

-- ─── Hourly income per turf tier ─────────────────────────────
-- tier 1 = 10000/hr, tier 2 = 15000/hr, tier 3 = 22000/hr.
-- The design base is exactly 10000, and most zones are tier 1.
Config.TierIncome = {
    [1] = 10000,
    [2] = 15000,
    [3] = 22000,
}

-- ─── Turf zones ──────────────────────────────────────────────
-- ghetto = true  -> red zone: open PvP, no police response, no weapon permit needed.
-- blip.colour is the *neutral* colour; an owned zone is recoloured
-- to the owning gang's blipColour at runtime.
Config.Zones = {
    {
        id = 'davis', name = 'Davis', tier = 1, ghetto = true,
        coords = vector3(-1020.3, -967.2, 11.6), radius = 190.0,
        blip = { sprite = 84, colour = 1 },
        marker = { colour = { 255, 30, 56, 120 }, scale = 190.0 },
    },
    {
        id = 'grove', name = 'Grove Street', tier = 1, ghetto = false,
        coords = vector3(-124.9, -1586.8, 33.5), radius = 150.0,
        blip = { sprite = 84, colour = 2 },
        marker = { colour = { 0, 255, 136, 120 }, scale = 150.0 },
    },
    {
        id = 'rundown', name = 'The RunDown', tier = 1, ghetto = true,
        coords = vector3(-1187.0, -1121.0, 4.7), radius = 200.0,
        blip = { sprite = 84, colour = 1 },
        marker = { colour = { 255, 30, 56, 120 }, scale = 200.0 },
    },
    {
        id = 'seoul', name = 'Little Seoul', tier = 1, ghetto = true,
        coords = vector3(20.5, -1461.2, 29.3), radius = 165.0,
        blip = { sprite = 84, colour = 1 },
        marker = { colour = { 255, 30, 56, 120 }, scale = 165.0 },
    },
    {
        id = 'vimmo', name = "Vimmo's Corner", tier = 1, ghetto = false,
        coords = vector3(271.5, -1494.4, 29.3), radius = 120.0,
        blip = { sprite = 84, colour = 4 },
        marker = { colour = { 255, 188, 0, 120 }, scale = 120.0 },
    },
    {
        id = 'strawberry', name = 'Strawberry', tier = 1, ghetto = true,
        coords = vector3(-45.0, -1622.0, 28.6), radius = 175.0,
        blip = { sprite = 84, colour = 1 },
        marker = { colour = { 255, 30, 56, 120 }, scale = 175.0 },
    },
    {
        id = 'citadel', name = 'Citadel Flats', tier = 1, ghetto = true,
        coords = vector3(398.0, -1621.0, 28.7), radius = 185.0,
        blip = { sprite = 84, colour = 1 },
        marker = { colour = { 255, 30, 56, 120 }, scale = 185.0 },
    },
    {
        id = 'lamesa', name = 'La Mesa', tier = 1, ghetto = false,
        coords = vector3(133.0, -1282.0, 29.2), radius = 155.0,
        blip = { sprite = 56, colour = 26 },
        marker = { colour = { 150, 150, 150, 110 }, scale = 155.0 },
    },
    {
        id = 'mirrorpark', name = 'Mirror Park', tier = 2, ghetto = false,
        coords = vector3(-557.0, -120.0, 36.0), radius = 170.0,
        blip = { sprite = 56, colour = 26 },
        marker = { colour = { 150, 150, 150, 110 }, scale = 170.0 },
    },
    {
        id = 'rockford', name = 'Rockford Hills', tier = 3, ghetto = false,
        coords = vector3(-1102.0, -407.0, 13.0), radius = 210.0,
        blip = { sprite = 56, colour = 4 },
        marker = { colour = { 255, 188, 0, 120 }, scale = 210.0 },
    },
    {
        id = 'vespucci', name = 'Vespucci Beach', tier = 2, ghetto = false,
        coords = vector3(-1223.0, -1453.0, 4.3), radius = 200.0,
        blip = { sprite = 56, colour = 52 },
        marker = { colour = { 0, 176, 255, 110 }, scale = 200.0 },
    },
    {
        id = 'delperro', name = 'Del Perro', tier = 2, ghetto = false,
        coords = vector3(-1836.0, -1234.0, 13.0), radius = 220.0,
        blip = { sprite = 56, colour = 52 },
        marker = { colour = { 0, 176, 255, 110 }, scale = 220.0 },
    },
    {
        id = 'sandy', name = 'Sandy Shores', tier = 1, ghetto = true,
        coords = vector3(1740.0, 3780.0, 34.2), radius = 240.0,
        blip = { sprite = 84, colour = 1 },
        marker = { colour = { 255, 30, 56, 120 }, scale = 240.0 },
    },
    {
        id = 'paleto', name = 'Paleto Bay', tier = 2, ghetto = false,
        coords = vector3(-245.0, 6630.0, 7.5), radius = 230.0,
        blip = { sprite = 56, colour = 52 },
        marker = { colour = { 0, 176, 255, 110 }, scale = 230.0 },
    },
    {
        id = 'airport', name = 'Los Santos International', tier = 3, ghetto = false,
        coords = vector3(-1037.0, -2735.0, 20.1), radius = 260.0,
        blip = { sprite = 48, colour = 4 },
        marker = { colour = { 255, 188, 0, 120 }, scale = 260.0 },
    },
    {
        id = 'vinewood', name = 'Vinewood Blvd', tier = 2, ghetto = false,
        coords = vector3(-1188.0, -1418.0, 4.6), radius = 240.0,
        blip = { sprite = 56, colour = 66 },
        marker = { colour = { 120, 20, 120, 110 }, scale = 240.0 },
    },
}

-- ─── Gang definitions ───────────────────────────────────────
-- Keys MUST match grand_core Config.Jobs illegal gang jobs.
-- colour = brand hex (UI/chat), blipColour = FiveM radmap index.
Config.Gangs = {
    ballas = {
        label = 'The Ballas', colour = '#8E24AA', blipColour = 27,
        homeTurf = 'davis', allies = { 'cartel' }, rivals = { 'hood', 'vagos' },
    },
    vagos = {
        label = 'Vagos Riders', colour = '#1E88E5', blipColour = 2,
        homeTurf = 'rundown', allies = { 'marabunta' }, rivals = { 'lostmc', 'hood' },
    },
    lostmc = {
        label = 'The Lost MC', colour = '#FDD835', blipColour = 30,
        homeTurf = 'lamesa', allies = { 'vagos' }, rivals = { 'marabunta', 'cartel' },
    },
    marabunta = {
        label = 'Marabunta Grande', colour = '#FB8C00', blipColour = 41,
        homeTurf = 'seoul', allies = { 'hood' }, rivals = { 'lostmc', 'ballas' },
    },
    hood = {
        label = 'Grove Street Families', colour = '#43A047', blipColour = 34,
        homeTurf = 'grove', allies = { 'marabunta' }, rivals = { 'ballas', 'vagos' },
    },
    cartel = {
        label = 'Cartel Enforcer', colour = '#D81B60', blipColour = 29,
        homeTurf = 'airport', allies = { 'ballas' }, rivals = { 'lostmc' },
    },
}

-- Ranks from grand_core GangGrades; at/above MinAttackRank may call an attack.
Config.Ranks = {
    MinAttackRank = 1,     -- Shot or above
    LeaderRank = 5,        -- Leader
    OfficerRanks = { [3] = true, [4] = true, [5] = true },
}

-- ─── Turf war engine ─────────────────────────────────────────
Config.War = {
    captureSeconds = 900,      -- 15 minutes of net favourable presence
    tickSeconds = 30,          -- presence tick
    minAttackers = 3,          -- family members physically in the zone
    minDefenders = 1,
    contestRadius = 110.0,     -- fallback; per-zone radius wins
    idleDecay = true,          -- unfavourable presence bleeds progress
    decayPerTick = 2,          -- ticks of progress lost while losing
    forfeitAfterSeconds = 120, -- all attackers gone this long -> forfeit
    cooldownSeconds = 1800,    -- family re-attack cooldown after a war ends
    maxConcurrentWars = 3,     -- per family
    maxTotalWars = 6,          -- server-wide
    neutralCap = true,         -- unowned turfs can be claimed
    commandRateMs = 5000,      -- one war action per source per 5s
    maxWarSeconds = 5400,      -- hard cap: an unfinished war is aborted
}

-- ─── Income ──────────────────────────────────────────────────
Config.Income = {
    payoutSeconds = 3600,      -- real-time payout loop
    offlineAccrual = true,     -- settle owed hours on boot
    capPerFamily = 90000,      -- vault ceiling per settle pass
    taxToCity = 0.0,
    maxTransaction = 48000,    -- split larger payouts into chunks
    minOwnerCount = 1,         -- family must have >=1 online member to pay
}

-- ─── PvP / red zones ─────────────────────────────────────────
Config.PvP = {
    ghettoOnly = true,         -- sanctioned hostile fire only in ghetto turfs
    friendlyFire = false,
    respawnLockSeconds = 12,   -- killer lockout after a turf kill
    weaponCooldownSeconds = 8, -- per-shooter fire rate limit
    bountyPerKill = 750,
    bountyDecay = 0.9,         -- bounty bleeds off per hour
    maxBounty = 25000,
    allyPenalty = 1500,        -- friend-fire bounty forfeiture
    allyLockSeconds = 45,      -- temp weapon lock after friend fire
    permitJobs = { 'armsdeal', 'security', 'lspd', 'sahp', 'fib' },
    requirePermitOutsideGhetto = true,
    killLogHours = 6,          -- look-back window for the re-verify check
    maxDistanceToVictim = 90.0,
    policeFactions = { police = true, ems = true, federal = true },
}

-- ─── Map layer (grand_mechanic GrandBlips) ───────────────────
Config.Blips = {
    enabled = true,
    distanceCull = 1400.0,
    showOwnerColours = true,
    prefix = 'gang_',
    zoneSprite = 84,
    contestedSprite = 56,
    labelScale = 0.82,
    ringHeight = 30.0,
    notifyOnZoneChange = true,
    drawDistance = 420.0,
    promptDistance = 260.0,
}

-- ─── Tags / logos / graffiti (data only, no NUI) ────────────
Config.Logos = {
    ballas = { tag = 'BAL', graffiti = 'prop_sign_road_5_22', colour = '#8E24AA' },
    vagos = { tag = 'VG', graffiti = 'prop_sign_road_3_4', colour = '#1E88E5' },
    lostmc = { tag = 'LOST', graffiti = 'prop_wallpaper_01', colour = '#FDD835' },
    marabunta = { tag = 'MG', graffiti = 'prop_sign_road_5_26', colour = '#FB8C00' },
    hood = { tag = 'GSF', graffiti = 'prop_beachflag_le', colour = '#43A047' },
    cartel = { tag = 'CART', graffiti = 'prop_sign_road_3_3', colour = '#D81B60' },
}

Config.Graffiti = {
    allowedSprites = {
        'prop_sign_road_5_22', 'prop_sign_road_3_4', 'prop_wallpaper_01',
        'prop_sign_road_5_26', 'prop_beachflag_le', 'prop_sign_road_3_3',
        'prop_miling_bomb_01', 'prop_wallpaper_02',
    },
    -- tagging a spot earns a small vault bump and marks the turf hot
    spots = {
        { id = 'davis_walk', zone = 'davis', coords = vector3(-1015.0, -975.0, 12.0), prop = 'prop_sign_road_5_22' },
        { id = 'grove_wall', zone = 'grove', coords = vector3(-120.0, -1592.0, 33.5), prop = 'prop_wallpaper_01' },
        { id = 'rundown_arch', zone = 'rundown', coords = vector3(-1192.0, -1114.0, 5.0), prop = 'prop_sign_road_3_4' },
        { id = 'seoul_lane', zone = 'seoul', coords = vector3(26.0, -1455.0, 29.4), prop = 'prop_sign_road_5_26' },
        { id = 'straw_wall', zone = 'strawberry', coords = vector3(-38.0, -1628.0, 28.8), prop = 'prop_wallpaper_02' },
        { id = 'citadel_stair', zone = 'citadel', coords = vector3(404.0, -1614.0, 28.9), prop = 'prop_beachflag_le' },
        { id = 'sandy_diner', zone = 'sandy', coords = vector3(1747.0, 3772.0, 34.4), prop = 'prop_sign_road_3_3' },
        { id = 'vimmo_corner', zone = 'vimmo', coords = vector3(264.0, -1500.0, 29.3), prop = 'prop_miling_bomb_01' },
    },
    reward = 250,             -- vault bump per fresh tag (capped per hour)
    perHourCap = 8,
    cooldownSeconds = 900,
    range = 18.0,
    propScale = 0.9,
    tagRateMs = 4000,
}

-- ─── Commands ────────────────────────────────────────────────
Config.Commands = {
    attack = 'attackturf',
    yield = 'turf',          -- /turf yield | status | list
    stats = 'turfstats',
    admin = 'gangadmin',
    map = 'turfmap',
}

-- ─── Permissions (ace) ───────────────────────────────────────
Config.Permissions = {
    attack = 'grand_gangs.attack',
    yield = 'grand_gangs.yield',
    stats = 'grand_gangs.stats',
    admin = 'grand_gangs.admin',
    force = 'grand_gangs.force',
    reset = 'grand_gangs.reset',
    adminGroups = { 'admin', 'superadmin', 'god', 'owner' },
    -- group-based fallbacks if ace is not granted
    aceGroups = { 'group.admin', 'group.god' },
}

-- ─── Notification text (chat strings, ASCII only) ───────────
Config.Text = {
    warStart = 'TURF WAR: %s is attacking %s!',
    warMine = 'Your family is attacking %s. Hold the ground.',
    warDefend = '%s is attacking YOUR turf %s. Defend it!',
    captured = 'TURF LOST: %s now belongs to %s.',
    gained = 'TURF CLAIMED: %s is yours.',
    forfeit = 'The attack on %s was abandoned.',
    income = 'Turf income %s paid to the family vault.',
    entered = 'You are standing in %s',
    owned = 'Turf: %s - owned by %s',
    neutral = 'Turf: %s - unclaimed',
    contested = 'TURF WAR LIVE in %s',
    denied = 'You cannot attack %s: %s',
    bounty = 'Bounty collected: %s',
    friendFire = 'Friendly fire in your own turf. Penalty: %s',
    noZone = 'No turf at those coordinates.',
    needFamily = 'You are not in a family.',
    needGang = 'You must be an on-duty gang member.',
    notEnough = 'Need %d of your family inside the turf.',
    rateLimited = 'Slow down: one turf action every %d seconds.',
}
