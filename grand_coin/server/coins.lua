-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_coin/server/coins.lua
--  Every coin movement in one place. Public API (global Coins):
--    Balance, Credit, Debit, Transfer, Grant, Quote,
--    ConvertToCoins, ConvertToCash, PurchaseItem,
--    AwardJobCompletion, AwardEventParticipation, History
--
--  Rules:
--    * balance lives in users.grand_coins, resolved via characters
--    * every mutation writes grand_coin_ledger
--    * cash moves through grand_core with a characters.money fallback
--    * nothing trusts the client with an amount it did not re-quote
-- ─────────────────────────────────────────────────────────────

Coins = Coins or {}
local C = Coins

local MAX_QTY = 5

-- ─── Money bridge ────────────────────────────────────────────
local function moneyRow(citizenid)
    local row = Database.Single('SELECT money FROM characters WHERE citizenid = ? LIMIT 1',
        { citizenid })
    if not row then return nil end
    local ok, decoded = pcall(json.decode, tostring(row.money or '{}'))
    if ok and type(decoded) == 'table' then return decoded end
    return { cash = 0, bank = 0, crypto = 0 }
end

local function saveMoney(citizenid, money)
    return Database.Update('UPDATE characters SET money = ? WHERE citizenid = ?', {
        json.encode(money), citizenid,
    }) > 0
end

local function takeCash(src, citizenid, amount, reason)
    local result = Util.TryExport('grand_core', 'RemoveMoney', src, 'cash', amount, reason)
    if result ~= nil then return result == true end

    local money = moneyRow(citizenid)
    if not money or (tonumber(money.cash) or 0) < amount then return false end
    money.cash = math.floor((tonumber(money.cash) or 0) - amount)
    return saveMoney(citizenid, money)
end

local function giveCash(src, citizenid, amount, reason)
    local result = Util.TryExport('grand_core', 'AddMoney', src, 'cash', amount, reason)
    if result ~= nil then return result == true end

    local money = moneyRow(citizenid)
    if not money then return false end
    money.cash = math.max(0, math.floor((tonumber(money.cash) or 0) + amount))
    if money.cash > 50000 then money.cash = 50000 end
    return saveMoney(citizenid, money)
end

local function notifyTarget(target, message, kind)
    if type(target) == 'number' and target > 0 then
        Util.Notify(target, message, kind)
    end
end

-- ─── Balance ─────────────────────────────────────────────────
function C.Balance(target)
    local citizenid = Util.ResolveCitizenId(target)
    if not citizenid then return 0 end
    return Database.GetBalance(citizenid)
end

-- ─── Credit / debit ──────────────────────────────────────────
function C.Credit(target, amount, reason, kind, meta)
    local citizenid = Util.ResolveCitizenId(target)
    if not citizenid then return false, 'no citizen' end

    amount = Util.Int(amount)
    if not amount or amount <= 0 then return false, 'invalid amount' end

    local maxBalance = Util.Int(Config.Limits.maxBalance) or 1000000
    local after, before = Database.AdjustBalance(citizenid, amount, maxBalance)
    if not after then
        notifyTarget(target, ('Could not credit coins: %s'):format(tostring(before or 'error')), 'error')
        return false, before
    end

    local txn = Util.TxnId()
    Database.Ledger(txn, citizenid, amount, kind or 'credit',
        reason or 'Coin credit', before, after, meta)

    notifyTarget(target, ('+%s - %s'):format(Util.Coins(amount), tostring(reason or 'credit')), 'success')
    return true, txn, after
end

function C.Debit(target, amount, reason, kind, meta)
    local citizenid = Util.ResolveCitizenId(target)
    if not citizenid then return false, 'no citizen' end

    amount = Util.Int(amount)
    if not amount or amount <= 0 then return false, 'invalid amount' end

    local after, before = Database.AdjustBalance(citizenid, -amount, nil)
    if not after then
        if before == 'insufficient balance' then
            notifyTarget(target, ('Not enough Grand Coins. Need %s.'):format(Util.Coins(amount)), 'error')
        else
            notifyTarget(target, ('Could not debit coins: %s'):format(tostring(before or 'error')), 'error')
        end
        return false, before
    end

    local txn = Util.TxnId()
    Database.Ledger(txn, citizenid, -amount, kind or 'debit',
        reason or 'Coin debit', before, after, meta)

    notifyTarget(target, ('-%s - %s'):format(Util.Coins(amount), tostring(reason or 'debit')), 'info')
    return true, txn, after
end

-- ─── Transfer ────────────────────────────────────────────────
function C.Transfer(source, targetSource, amount, reason)
    source = tonumber(source)
    targetSource = tonumber(targetSource)
    if not Util.IsOnline(source) then return false, 'invalid source' end
    if not Util.IsOnline(targetSource) then return false, 'target is not online' end
    if source == targetSource then return false, 'you cannot send coins to yourself' end

    amount = Util.Int(amount)
    if not amount or amount <= 0 then return false, 'invalid amount' end
    if amount > (Config.Limits.maxGiftAmount or 10000) then
        return false, ('maximum transfer is %s'):format(Util.Coins(Config.Limits.maxGiftAmount))
    end

    local allowed, wait = Util.RateLimit('transfer:' .. source, Config.Limits.giftCooldown or 3600)
    if not allowed then
        return false, ('wait %d seconds before transferring again'):format(wait or 0)
    end

    local sourceCid = Util.GetCitizenId(source)
    local targetCid = Util.GetCitizenId(targetSource)
    if not sourceCid or not targetCid then return false, 'player not loaded' end

    local debitOk, debitTxn = C.Debit(source, amount, ('Transfer to %s'):format(targetCid),
        'transfer_out', { target = targetCid })
    if not debitOk then return false, 'not enough Grand Coins' end

    local creditOk, creditTxn = C.Credit(targetSource, amount,
        ('Transfer from %s'):format(sourceCid), 'transfer_in', { source = sourceCid })
    if not creditOk then
        C.Credit(source, amount, 'Transfer refund', 'refund', { target = targetCid })
        return false, 'target could not receive the coins'
    end

    Util.Notify(source, ('Sent %s to %s'):format(Util.Coins(amount),
        GetPlayerName(targetSource) or targetCid), 'success')

    return true, { debit = debitTxn, credit = creditTxn }
end

-- ─── Admin grant ─────────────────────────────────────────────
local function isAdmin(src)
    if src == 0 then return true end
    if not src or src <= 0 then return false end
    if IsPlayerAceAllowed(src, Config.Permissions.admin) then return true end
    if Config.Permissions.grant and IsPlayerAceAllowed(src, Config.Permissions.grant) then return true end
    for _, group in ipairs(Config.Permissions.aceGroups or {}) do
        if IsPlayerAceAllowed(src, group) then return true end
    end
    return false
end

function C.Grant(adminSource, targetSource, amount, reason)
    adminSource = tonumber(adminSource) or 0
    if not isAdmin(adminSource) then return false, 'not authorised' end

    targetSource = tonumber(targetSource)
    if not Util.IsOnline(targetSource) then return false, 'target is not online' end

    amount = Util.Int(amount)
    local cfg = Config.EarningSources.adminGrants
    if not amount or amount < cfg.minAmount or amount > cfg.maxAmount then
        return false, ('amount must be between %d and %d'):format(cfg.minAmount, cfg.maxAmount)
    end

    reason = Util.SanitizeText(reason or '', 190)
    if cfg.requireReason and reason == '' then return false, 'a reason is required' end

    local adminName = adminSource > 0 and (GetPlayerName(adminSource) or tostring(adminSource)) or 'console'
    local ok, txn = C.Credit(targetSource, amount,
        ('Admin grant by %s: %s'):format(adminName, reason), 'admin_grant',
        { admin = adminName })
    if not ok then return false, 'grant failed' end

    if adminSource > 0 then
        Util.Notify(adminSource, ('Granted %s to %s'):format(Util.Coins(amount),
            GetPlayerName(targetSource) or tostring(targetSource)), 'success')
    end
    Util.Log('info', ('grant: %s -> %s (%d) "%s"'):format(adminName, tostring(targetSource), amount, reason))
    return true, txn
end

-- ─── Quotes ──────────────────────────────────────────────────
function C.Quote(amount, direction)
    direction = direction or 'coins_to_cash'
    if direction == 'in' then direction = 'cash_to_coins' end
    if direction == 'out' then direction = 'coins_to_cash' end
    return Config.Exchange.Quote(tonumber(amount) or 0, direction)
end

-- ─── Exchange ────────────────────────────────────────────────
function C.ConvertToCoins(source, cashAmount)
    source = tonumber(source)
    if not Util.IsOnline(source) then return false, 'invalid player' end

    cashAmount = Util.Int(cashAmount)
    if not cashAmount or cashAmount <= 0 then return false, 'invalid amount' end

    local quote = Config.Exchange.Quote(cashAmount, 'cash_to_coins')
    if not quote.valid or quote.coins <= 0 then
        return false, quote.reason or 'amount outside the exchange limits'
    end

    local citizenid = Util.GetCitizenId(source)
    if not citizenid then return false, 'player not loaded' end

    local allowed, wait = Util.RateLimit('exchange:' .. source, Config.Limits.transactionCooldown or 8)
    if not allowed then
        return false, ('wait %d seconds before exchanging again'):format(wait or 0)
    end

    if not takeCash(source, citizenid, cashAmount, 'Grand Coins purchase') then
        return false, 'not enough cash'
    end

    local ok, txn = C.Credit(source, quote.coins,
        ('Exchange: %s -> %s'):format(Util.Cash(cashAmount), Util.Coins(quote.coins)),
        'exchange_in', { cash = cashAmount, fee = quote.fee })
    if not ok then
        giveCash(source, citizenid, cashAmount, 'Grand Coins purchase refund')
        return false, 'coin credit failed'
    end

    Database.RecordExchange(citizenid, 'cash_in', quote.coins, cashAmount, quote.fee)
    Database.AddPool(cashAmount)
    Util.Notify(source, ('Bought %s for %s (fee %s)'):format(
        Util.Coins(quote.coins), Util.Cash(cashAmount), Util.Coins(quote.fee)), 'success')
    return true, txn
end

function C.ConvertToCash(source, coinAmount)
    source = tonumber(source)
    if not Util.IsOnline(source) then return false, 'invalid player' end

    coinAmount = Util.Int(coinAmount)
    if not coinAmount or coinAmount <= 0 then return false, 'invalid amount' end

    local quote = Config.Exchange.Quote(coinAmount, 'coins_to_cash')
    if not quote.valid or quote.cash <= 0 then
        return false, quote.reason or 'amount outside the exchange limits'
    end

    local citizenid = Util.GetCitizenId(source)
    if not citizenid then return false, 'player not loaded' end

    local allowed, wait = Util.RateLimit('exchange:' .. source, Config.Limits.transactionCooldown or 8)
    if not allowed then
        return false, ('wait %d seconds before exchanging again'):format(wait or 0)
    end

    local totals = Database.ExchangeTotals(citizenid, 1)
    local limit = Config.Exchange.hourlyCashOutLimit or 50000
    if (tonumber(totals.cash_out_coins) or 0) + coinAmount > limit then
        return false, ('hourly cash-out limit is %s'):format(Util.Coins(limit))
    end

    if not Database.SpendPool(quote.cash) then
        return false, 'the daily cash-out pool is empty, try tomorrow'
    end

    local ok, txn = C.Debit(source, coinAmount,
        ('Cash-out: %s -> %s'):format(Util.Coins(coinAmount), Util.Cash(quote.cash)),
        'exchange_out', { cash = quote.cash, fee = quote.fee })
    if not ok then
        Database.ReturnPool(quote.cash)
        return false, 'not enough Grand Coins'
    end

    if not giveCash(source, citizenid, quote.cash, 'Grand Coins cash-out') then
        C.Credit(source, coinAmount, 'Cash-out refund', 'refund')
        Database.ReturnPool(quote.cash)
        return false, 'cash delivery failed, coins refunded'
    end

    Database.RecordExchange(citizenid, 'cash_out', coinAmount, quote.cash, quote.fee)
    Util.Notify(source, ('Cashed out %s for %s (fee %s)'):format(
        Util.Coins(coinAmount), Util.Cash(quote.cash), Util.Cash(quote.fee)), 'success')
    return true, txn
end

-- ─── Shop ────────────────────────────────────────────────────
function C.PurchaseItem(source, slug, quantity)
    source = tonumber(source)
    if not Util.IsOnline(source) then return false, 'invalid player' end

    local item = Util.FindShopItem(slug)
    if not item then return false, 'unknown item' end

    quantity = Util.Int(quantity) or 1
    if quantity < 1 or quantity > MAX_QTY then
        return false, ('quantity must be 1-%d'):format(MAX_QTY)
    end

    local total = (tonumber(item.price) or 0) * quantity
    if total <= 0 then return false, 'item is not for sale' end

    local citizenid = Util.GetCitizenId(source)
    if not citizenid then return false, 'player not loaded' end

    local allowed, wait = Util.RateLimit('shop:' .. source, Config.Limits.transactionCooldown or 8)
    if not allowed then
        return false, ('wait %d seconds before buying again'):format(wait or 0)
    end

    local balance = Database.GetBalance(citizenid)
    if balance < total then
        return false, ('not enough Grand Coins (need %s)'):format(Util.Coins(total))
    end

    local debitOk, txn = C.Debit(source, total, ('Purchase: %dx %s'):format(quantity, item.name),
        'purchase', { item = item.slug, quantity = quantity })
    if not debitOk then return false, 'purchase failed' end

    Database.RecordPurchase(txn, citizenid, item, quantity, total)
    local delivered, detail = C.Deliver(source, citizenid, item, quantity)

    if not delivered then
        C.Credit(source, total, ('Refund: %s'):format(item.name), 'refund', { item = item.slug })
        Database.PurchaseStatus(txn, 'refunded', { error = tostring(detail or 'delivery failed') })
        return false, ('delivery failed: %s'):format(tostring(detail or 'unknown'))
    end

    Database.PurchaseStatus(txn, 'delivered', {
        delivered_at = os.time(), detail = detail,
    })
    Util.Notify(source, ('Bought %dx %s for %s'):format(quantity, item.name,
        Util.Coins(total)), 'success')
    return true, txn, detail
end

--- Delivers one shop item. Returns success, detail.
function C.Deliver(source, citizenid, item, quantity)
    quantity = quantity or 1

    if item.type == 'cash' then
        local cash = (tonumber(item.amount) or 0) * quantity
        if giveCash(source, citizenid, cash, item.name) then return true, cash end
        return false, 'cash payout failed'

    elseif item.type == 'vehicle' then
        if not item.vehicle then return false, 'no model configured' end
        local plate = Database.AddVehicle(citizenid, item.vehicle, 'Legion_Square')
        if not plate then return false, 'garage insert failed' end
        return true, plate

    elseif item.type == 'vip_time' then
        if not Database.SetVip(citizenid, (tonumber(item.duration) or 0) * quantity) then
            return false, 'VIP update failed'
        end
        return true, item.duration

    elseif item.type == 'garage_slot' then
        -- No column in the root schema yet; the purchase ledger is the
        -- source of truth and the property resource reads it later.
        return true, 'garage_slot'

    elseif item.type == 'outfit' then
        return true, item.outfitTag or 'premium_outfit'
    end

    return false, ('unknown delivery type %s'):format(tostring(item.type))
end

-- ─── Gameplay rewards ────────────────────────────────────────
local function canEarn(citizenid, amount)
    local earned = Database.EarnedToday(citizenid)
    local cap = Config.Limits.dailyEarningCap or 10000
    return earned + amount <= cap, earned
end

function C.AwardJobCompletion(source, jobName)
    source = tonumber(source)
    if not Util.IsOnline(source) then return false end

    local cfg = Config.EarningSources.jobCompletion
    if not cfg or not cfg.enabled then return false end

    jobName = tostring(jobName or ''):lower()
    local range = (cfg.amounts or {})[jobName]
    if not range then return false end

    local citizenid = Util.GetCitizenId(source)
    if not citizenid then return false end

    local allowed = Util.RateLimit('job:' .. citizenid .. ':' .. jobName, cfg.cooldownSeconds or 600)
    if not allowed then return false, 'job reward cooling down' end

    local amount = math.random(tonumber(range.min) or 1, tonumber(range.max) or 1)
    local underCap = canEarn(citizenid, amount)
    if not underCap then return false, 'daily earning cap reached' end

    local ok, txn = C.Credit(source, amount, ('Job reward: %s'):format(jobName),
        'job_reward', { job = jobName })
    return ok, amount, txn
end

function C.AwardEventParticipation(source, eventName)
    source = tonumber(source)
    if not Util.IsOnline(source) then return false end

    local cfg = Config.EarningSources.events
    if not cfg or not cfg.enabled then return false end

    eventName = tostring(eventName or ''):lower()
    local amount = (cfg.amounts or {})[eventName]
    if not amount then return false end

    local citizenid = Util.GetCitizenId(source)
    if not citizenid then return false end

    local underCap = canEarn(citizenid, amount)
    if not underCap then return false, 'daily earning cap reached' end

    local ok, txn = C.Credit(source, amount, ('Event: %s'):format(eventName),
        'event_reward', { event = eventName })
    return ok, amount, txn
end

-- ─── Read helpers ────────────────────────────────────────────
function C.History(target, limit, offset)
    local citizenid = Util.ResolveCitizenId(target)
    if not citizenid then return {} end
    return Database.History(citizenid, limit, offset)
end

function C.Purchases(target, limit)
    local citizenid = Util.ResolveCitizenId(target)
    if not citizenid then return {} end
    return Database.Purchases(citizenid, limit)
end

function C.Stats(target, days)
    local citizenid = Util.ResolveCitizenId(target)
    if not citizenid then return nil end
    return Database.Stats(citizenid, days)
end

return C
