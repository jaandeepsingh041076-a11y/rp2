-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/config.lua
--  Casino configuration – every tunable parameter lives here
-- ─────────────────────────────────────────────────────────────

local Config = {}

-- Casino location – The Diamond Casino & Resort
-- Main entrance: vector3(1130.0, -1530.0, 30.0) (GTA Plaza)
Config.Casino = {
    coords = vector3(1130.0, -1530.0, 30.0),
    lobby = vector3(1130.0, -1530.0, 30.5),  -- interior offset
    slotFloor = {
        vector3(1132.5, -1535.0, 30.5),
        vector3(1135.0, -1535.0, 30.5),
        vector3(1137.5, -1535.0, 30.5),
        vector3(1140.0, -1535.0, 30.5),
    },
    tables = {
        blackjack = {
            vector3(1145.0, -1525.0, 30.5),
            vector3(1147.0, -1525.0, 30.5),
        },
        roulette = {
            vector3(1150.0, -1520.0, 30.5),
        },
        coinflip = {
            vector3(1125.0, -1530.0, 30.5),
        }
    },
    wheel = vector3(1130.0, -1520.0, 31.0),  -- Wheel of Fortune location
}

-- Blip configuration
Config.Blip = {
    sprite = 245,      -- Casino chip sprite
    colour = 'gold',   -- Gold colour (from grand_mechanic palette)
    scale = 0.9,
    label = 'The Diamond Casino',
    hidden = false,
    range = 300.0,
}

-- Game configurations
Config.Slots = {
    minBet = 10,
    maxBet = 1000,
    houseEdge = 0.05,  -- 5% house edge
    symbols = {
        { name = 'seven', weight = 1, payout = 20 },
        { name = 'bar', weight = 2, payout = 10 },
        { name = 'bell', weight = 3, payout = 5 },
        { name = 'cherry', weight = 4, payout = 3 },
        { name = 'lemon', weight = 5, payout = 2 },
        { name = 'orange', weight = 6, payout = 1 },
    },
    reels = 3,
    jackpotTriggers = { 'seven', 'seven', 'seven' },
    jackpotMultiplier = 100,
}

Config.Blackjack = {
    minBet = 50,
    maxBet = 5000,
    houseEdge = 0.02,  -- 2% house edge (better for players)
    decks = 6,
    shoePenetration = 0.75,  -- Reshuffle when 75% of cards used
    blackjackPayout = 1.5,   -- 3:2 payout
    doubleAllowed = true,
    splitAllowed = true,
    surrenderAllowed = false,
    dealerHitsSoft17 = true,
}

Config.Roulette = {
    minBet = 10,
    maxBet = 2000,
    houseEdge = 0.027,  -- 2.7% for single-zero European
    wheelType = 'european',  -- single-zero
    bets = {
        straight = { payout = 35, odds = 1/37 },
        split = { payout = 17, odds = 2/37 },
        street = { payout = 11, odds = 3/37 },
        corner = { payout = 8, odds = 4/37 },
        line = { payout = 5, odds = 6/37 },
        dozen = { payout = 2, odds = 12/37 },
        column = { payout = 2, odds = 12/37 },
        red = { payout = 1, odds = 18/37 },
        black = { payout = 1, odds = 18/37 },
        odd = { payout = 1, odds = 18/37 },
        even = { payout = 1, odds = 18/37 },
        low = { payout = 1, odds = 18/37 },
        high = { payout = 1, odds = 18/37 },
    }
}

Config.Coinflip = {
    minBet = 10,
    maxBet = 10000,
    houseRake = 0.03,  -- 3% house take
    timeoutSeconds = 60,  -- Time to accept challenge
}

Config.WheelOfFortune = {
    minBet = 100,
    maxBet = 5000,
    houseEdge = 0.08,  -- 8% house edge
    segments = {
        { label = 'JACKPOT', multiplier = 10, weight = 1 },
        { label = '5x', multiplier = 5, weight = 2 },
        { label = '3x', multiplier = 3, weight = 3 },
        { label = '2x', multiplier = 2, weight = 4 },
        { label = 'BREAK EVEN', multiplier = 1, weight = 5 },
        { label = 'LOSE HALF', multiplier = 0.5, weight = 6 },
        { label = 'LOSE ALL', multiplier = 0, weight = 7 },
    },
    jackpotSeed = 10000,  -- Starting jackpot amount
}

-- Player limits and responsible gambling
Config.Limits = {
    maxHourlyLoss = 50000,       -- Max coins a player can lose per hour
    maxDailyLoss = 200000,       -- Max coins a player can lose per day
    selfExclusionDuration = {    -- Self-exclusion periods
        { label = '24 hours', hours = 24 },
        { label = '7 days', hours = 168 },
        { label = '30 days', hours = 720 },
        { label = 'Permanent', hours = 0 },  -- 0 = permanent
    },
    coolingOffPeriod = 300,       -- 5 minutes between large bets
}

-- Currency configuration
Config.Currency = {
    primary = 'grand_coins',    -- Use grand_coins from users table
    allowCashChips = false,      -- Allow buying chips with cash
    cashToChipRatio = 100,       -- $100 = 1 chip
    chipPurchaseMin = 100,
    chipPurchaseMax = 10000,
}

-- RNG configuration
Config.RNG = {
    algorithm = 'xorshift128',  -- xorshift128 for fast, good randomness
    seedSource = 'combined',     -- Combine round id + server secret + os.clock()
    serverSecret = 'grand_casino_server_secret_' .. os.date('%Y%m%d'),
    saltLength = 16,
}

-- Interaction ranges and UI
Config.Interaction = {
    tableRange = 2.5,           -- Distance to interact with tables
    slotRange = 1.5,            -- Distance to interact with slots
    wheelRange = 3.0,           -- Distance to interact with wheel
    drawTextScale = 0.5,
    drawTextFont = 4,
    drawTextColour = {255, 255, 255, 255},
    notificationDuration = 5000, -- ms
}

-- Database configuration
Config.Database = {
    roundRetentionDays = 30,     -- Keep round records for 30 days
    sessionCleanupHours = 24,    -- Clean up old sessions every 24 hours
}

-- Debug/testing (set to false for production)
Config.Debug = {
    enableLogging = false,
    skipRNGVerification = false,
    forceWin = false,
    forceLose = false,
}

return Config