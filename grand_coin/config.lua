-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_coin/config.lua
--  Grand Coins: the premium currency. `users.grand_coins` is the
--  single balance column (INT, root database.sql owns it).
--  Every movement writes a row to `grand_coin_ledger`.
-- ─────────────────────────────────────────────────────────────

Config = {}

Config.Debug = false
Config.LogLevel = 'info'

-- ─── Exchange ────────────────────────────────────────────────
Config.Exchange = {
    cashToCoinRate   = 100,      -- $100 buys 1 coin
    coinToCashRate   = 100,      -- 1 coin is worth $100 on cash-out
    cashInFee        = 0.05,     -- 5% burned when buying coins with cash
    cashOutFee       = 0.12,     -- 12% burned when cashing out
    minTransaction   = 10,       -- minimum coins per exchange
    maxTransaction   = 10000,    -- maximum coins per exchange
    hourlyCashOutLimit = 50000,  -- coins per player per hour
    dailyLiquidityPool = 1000000,-- server-wide cash-out pool in dollars
    allowNegative    = false,
}

--- Pure quote helper, no side effects. direction:
---   'cash_to_coins' | 'coins_to_cash'
function Config.Exchange.Quote(amount, direction)
    amount = tonumber(amount) or 0
    if amount <= 0 then
        return { coins = 0, cash = 0, fee = 0, rate = 1, valid = false, reason = 'invalid amount' }
    end

    local ex = Config.Exchange
    if direction == 'cash_to_coins' then
        if amount < ex.minTransaction * ex.cashToCoinRate then
            return { coins = 0, cash = amount, fee = 0, rate = ex.cashToCoinRate,
                     valid = false, reason = 'below minimum' }
        end
        local coins = amount / ex.cashToCoinRate
        local fee = math.floor(coins * ex.cashInFee)
        return {
            coins = math.max(math.floor(coins) - fee, 0),
            cash = math.floor(amount),
            fee = fee,
            rate = ex.cashToCoinRate,
            valid = true,
        }
    end

    local cashGross = amount * ex.coinToCashRate
    local fee = math.floor(cashGross * ex.cashOutFee)
    return {
        coins = math.floor(amount),
        cash = math.max(math.floor(cashGross - fee), 0),
        fee = fee,
        rate = ex.coinToCashRate,
        valid = amount >= ex.minTransaction,
        reason = amount < ex.minTransaction and 'below minimum' or nil,
    }
end

-- ─── Earning sources (never client-driven) ───────────────────
Config.EarningSources = {
    jobCompletion = {
        enabled = true,
        cooldownSeconds = 600,
        amounts = {
            mechanic = { min = 5, max = 20 },
            taxi     = { min = 2, max = 10 },
            tow      = { min = 5, max = 15 },
            lspd     = { min = 10, max = 50 },
            sahp     = { min = 10, max = 50 },
            fib      = { min = 10, max = 50 },
            ambulance = { min = 10, max = 50 },
        },
    },
    events = {
        enabled = true,
        amounts = {
            daily_login       = 10,
            weekly_streak     = 50,
            event_participation = 25,
            achievement       = 100,
        },
    },
    adminGrants = {
        enabled = true,
        minAmount = 1,
        maxAmount = 10000,
        requireReason = true,
    },
}

-- ─── Shop ────────────────────────────────────────────────────
Config.Shop = {
    items = {
        { slug = 'basic_car',   name = 'Blista',           price = 5000,  type = 'vehicle',
          vehicle = 'blista',     category = 'transport',
          description = 'A dependable compact car delivered to Legion Square.' },
        { slug = 'premium_car', name = 'Comet',            price = 25000, type = 'vehicle',
          vehicle = 'comet2',     category = 'transport',
          description = 'A premium sports coupe.' },
        { slug = 'garage_slot', name = 'Garage Slot',      price = 1000,  type = 'garage_slot',
          category = 'property', description = 'One extra parking space.' },
        { slug = 'vip_1day',    name = 'VIP (1 Day)',      price = 100,   type = 'vip_time',
          duration = 24,          category = 'premium', description = 'VIP status for 24 hours.' },
        { slug = 'vip_7days',   name = 'VIP (7 Days)',     price = 600,   type = 'vip_time',
          duration = 168,         category = 'premium', description = 'VIP status for one week.' },
        { slug = 'vip_30days',  name = 'VIP (30 Days)',    price = 2500,  type = 'vip_time',
          duration = 720,         category = 'premium', description = 'VIP status for a month.' },
        { slug = 'outfit_premium', name = 'Premium Outfit', price = 500,  type = 'outfit',
          outfitTag = 'premium_001', category = 'cosmetic', description = 'An exclusive outfit token.' },
        { slug = 'cash_1000',   name = '$1,000 Cash',      price = 10,    type = 'cash',
          amount = 1000,          category = 'currency', description = 'Instant cash payout.' },
        { slug = 'cash_10000',  name = '$10,000 Cash',     price = 90,    type = 'cash',
          amount = 10000,         category = 'currency', description = 'Bulk cash payout.' },
        { slug = 'cash_50000',  name = '$50,000 Cash',     price = 400,   type = 'cash',
          amount = 50000,         category = 'currency', description = 'Bulk cash payout, best value.' },
    },
    categories = {
        transport = { label = 'Transport' },
        property  = { label = 'Property' },
        premium   = { label = 'Premium' },
        cosmetic  = { label = 'Cosmetic' },
        currency  = { label = 'Currency' },
    },
}

-- ─── Ledger / limits ─────────────────────────────────────────
Config.Ledger = {
    retentionDays        = 90,
    integrityInterval    = 300,   -- seconds
    maxDriftAllowed      = 100,
    notifyAdminsOnDrift  = true,
}

Config.Limits = {
    maxBalance           = 1000000,
    dailyEarningCap      = 10000,
    transactionCooldown  = 8,     -- seconds, per source
    maxGiftAmount        = 10000,
    giftCooldown         = 3600,
    maxTransactionsHour  = 100,
    unusualActivity      = 50000,
}

-- ─── Map / presentation ──────────────────────────────────────
Config.Blips = {
    enabled    = true,
    prefix     = 'coin_',
    distanceCull = 1200.0,
    locations = {
        { id = 'casino_cage', label = 'Grand Coins Exchange', sprite = 277,
          colour = 'gold', coords = vector3(1120.0, 219.0, -49.0) },
        { id = 'airport_kiosk', label = 'Grand Coins Kiosk', sprite = 277,
          colour = 'gold', coords = vector3(-1042.0, -2745.0, 21.0) },
    },
}

Config.UI = {
    updateInterval = 30000,
    drawScale = 0.42,
    drawFont = 4,
    showOnScreen = false,   -- HUD is a frozen resource; chat is the default
}

Config.Commands = {
    balance  = 'coins',
    shop     = 'coinshop',
    buy      = 'coinbuy',
    convert  = 'convert',
    cashout  = 'cashout',
    give     = 'givecoins',
    admin    = 'coinadmin',
}

Config.Permissions = {
    admin = 'grand.coin.admin',
    grant = 'grand.coin.grant',
    aceGroups = { 'group.admin' },
}

Config.Tables = {
    ledger    = 'grand_coin_ledger',
    purchases = 'grand_coin_purchases',
    pools     = 'grand_coin_pools',
    earnings  = 'grand_coin_earnings',
}
