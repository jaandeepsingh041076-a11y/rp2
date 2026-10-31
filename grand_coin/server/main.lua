-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_coin/server/main.lua
--  Commands, net events, exports and the housekeeping threads.
--  Loads last: Config, Util, Database and Coins are global.
-- ─────────────────────────────────────────────────────────────

GrandCoin = GrandCoin or {}
local G = GrandCoin

local RESOURCE = GetCurrentResourceName()

-- ─── Small helpers ───────────────────────────────────────────
local function respond(src, message, kind)
    if src == 0 then
        print(('[grand_coin] %s'):format(tostring(message)))
    else
        Util.Notify(src, message, kind)
    end
end

local function isAdmin(src)
    if src == 0 then return true end
    if IsPlayerAceAllowed(src, Config.Permissions.admin) then return true end
    if Config.Permissions.grant and IsPlayerAceAllowed(src, Config.Permissions.grant) then return true end
    for _, group in ipairs(Config.Permissions.aceGroups or {}) do
        if IsPlayerAceAllowed(src, group) then return true end
    end
    return false
end

local function online(source)
    return source ~= nil and source > 0 and GetPlayerName(source) ~= nil
end

local function pushBalance(src)
    if not online(src) then return end
    local balance = Coins.Balance(src)
    TriggerClientEvent('grand_coin:client:Balance', src, balance)
    return balance
end

-- ─── Boot ────────────────────────────────────────────────────
function G.Start()
    Database.Bootstrap()

    -- Integrity sweep: online players only, every `integrityInterval`.
    CreateThread(function()
        while true do
            Wait(math.max(60, Util.Int(Config.Ledger.integrityInterval) or 300) * 1000)
            local checked, drift = 0, 0
            for _, srcText in ipairs(GetPlayers()) do
                local src = tonumber(srcText)
                local cid = Util.GetCitizenId(src)
                if cid then
                    local result = Database.CheckLedger(cid)
                    checked = checked + 1
                    if not result.consistent then
                        drift = drift + 1
                        Util.Log('warn', ('ledger drift %s: balance=%d ledger=%d'):format(
                            cid, result.balance, result.ledger))
                    end
                end
            end
            if checked > 0 and Config.Debug then
                Util.Debug('integrity sweep: %d checked, %d drifted', checked, drift)
            end
        end
    end)

    -- Daily rollover + cleanup, checked once a minute.
    CreateThread(function()
        local lastCleanup = 0
        while true do
            Wait(60000)
            Database.RollPool()
            local now = os.time()
            if now - lastCleanup > 86400 then
                lastCleanup = now
                Database.Cleanup()
                Util.PruneCooldowns()
                Util.Debug('daily coin housekeeping done')
            end
        end
    end)

    Util.Log('info', 'Grand Coins online')
end

-- ─── Net events (all re-quote server side) ───────────────────
RegisterNetEvent('grand_coin:server:Ready', function()
    local src = source
    if not online(src) then return end
    if not Util.RateLimit('ready:' .. src, 5) then return end
    pushBalance(src)
    TriggerClientEvent('grand_coin:client:Shop', src, Config.Shop)
end)

RegisterNetEvent('grand_coin:server:GetBalance', function()
    local src = source
    if not online(src) then return end
    if not Util.RateLimit('balance:' .. src, 2) then return end
    pushBalance(src)
end)

RegisterNetEvent('grand_coin:server:GetQuote', function(amount, direction)
    local src = source
    if not online(src) then return end
    if not Util.RateLimit('quote:' .. src, 1) then return end

    local quote = Coins.Quote(amount, direction)
    TriggerClientEvent('grand_coin:client:Quote', src, quote, direction)
end)

RegisterNetEvent('grand_coin:server:GetShop', function()
    local src = source
    if not online(src) then return end
    if not Util.RateLimit('shopview:' .. src, 3) then return end
    TriggerClientEvent('grand_coin:client:Shop', src, Config.Shop)
end)

RegisterNetEvent('grand_coin:server:Purchase', function(slug, quantity)
    local src = source
    if not online(src) then return end

    local ok, detail, extra = Coins.PurchaseItem(src, slug, quantity)
    if ok then
        TriggerClientEvent('grand_coin:client:Purchased', src, slug, quantity, detail, extra)
    else
        Util.Notify(src, tostring(detail or 'purchase failed'), 'error')
    end
    pushBalance(src)
end)

RegisterNetEvent('grand_coin:server:ConvertToCoins', function(cashAmount)
    local src = source
    if not online(src) then return end

    local ok, value = Coins.ConvertToCoins(src, cashAmount)
    if not ok then Util.Notify(src, tostring(value or 'exchange failed'), 'error') end
    pushBalance(src)
end)

RegisterNetEvent('grand_coin:server:ConvertToCash', function(coinAmount)
    local src = source
    if not online(src) then return end

    local ok, value = Coins.ConvertToCash(src, coinAmount)
    if not ok then Util.Notify(src, tostring(value or 'exchange failed'), 'error') end
    pushBalance(src)
end)

RegisterNetEvent('grand_coin:server:Transfer', function(targetSource, amount, reason)
    local src = source
    if not online(src) then return end

    local ok, value = Coins.Transfer(src, tonumber(targetSource), amount, reason)
    if not ok then Util.Notify(src, tostring(value or 'transfer failed'), 'error') end
    pushBalance(src)
end)

RegisterNetEvent('grand_coin:server:History', function(limit)
    local src = source
    if not online(src) then return end
    if not Util.RateLimit('history:' .. src, 2) then return end

    local rows = Coins.History(src, limit or 15, 0)
    TriggerClientEvent('grand_coin:client:History', src, rows)
end)

RegisterNetEvent('grand_coin:server:Purchases', function(limit)
    local src = source
    if not online(src) then return end
    if not Util.RateLimit('purchases:' .. src, 2) then return end

    local rows = Coins.Purchases(src, limit or 10)
    TriggerClientEvent('grand_coin:client:Purchases', src, rows)
end)

-- ─── Player commands ─────────────────────────────────────────
RegisterCommand(Config.Commands.balance, function(src)
    if src == 0 then return end
    local balance = pushBalance(src) or 0
    local stats = Coins.Stats(src, 30) or {}
    respond(src, ('Balance: %s | 30d in %s, out %s'):format(
        Util.Coins(balance),
        Util.Coins(stats.total_incoming or 0),
        Util.Coins(stats.total_outgoing or 0)), 'info')
end, false)

RegisterCommand(Config.Commands.shop, function(src)
    if src == 0 then
        for _, item in ipairs(Config.Shop.items or {}) do
            print(('[shop] %-16s %8d GC  %s'):format(item.slug, item.price, item.name))
        end
        return
    end
    if not online(src) then return end
    if not Util.RateLimit('shopcmd:' .. src, 3) then return end

    TriggerClientEvent('grand_coin:client:Shop', src, Config.Shop)
    respond(src, ('%d items for sale. /%s <slug> [qty]'):format(
        #(Config.Shop.items or {}), Config.Commands.buy), 'info')
end, false)

RegisterCommand(Config.Commands.buy, function(src, args)
    if src == 0 then
        respond(src, 'players only', 'error')
        return
    end
    if not online(src) then return end

    local slug = args[1]
    if not slug then
        respond(src, ('usage: /%s <item> [qty]'):format(Config.Commands.buy), 'info')
        return
    end

    local ok, detail, extra = Coins.PurchaseItem(src, slug, tonumber(args[2]) or 1)
    if ok then
        respond(src, ('Purchased %s%s'):format(tostring(slug),
            extra and (' (' .. tostring(extra) .. ')') or ''), 'success')
        TriggerClientEvent('grand_coin:client:Purchased', src, slug, tonumber(args[2]) or 1, detail, extra)
    else
        respond(src, tostring(detail or 'purchase failed'), 'error')
    end
    pushBalance(src)
end, false)

RegisterCommand(Config.Commands.convert, function(src, args)
    if src == 0 then return end
    if not online(src) then return end

    local cash = Util.ParseAmount(args[1])
    if not cash or cash <= 0 then
        respond(src, ('usage: /%s <cash> - e.g. /%s 5000'):format(
            Config.Commands.convert, Config.Commands.convert), 'info')
        return
    end

    local ok, value = Coins.ConvertToCoins(src, cash)
    if not ok then respond(src, tostring(value or 'exchange failed'), 'error') end
    pushBalance(src)
end, false)

RegisterCommand(Config.Commands.cashout, function(src, args)
    if src == 0 then return end
    if not online(src) then return end

    local coins = Util.ParseAmount(args[1])
    if not coins or coins <= 0 then
        respond(src, ('usage: /%s <coins>'):format(Config.Commands.cashout), 'info')
        return
    end

    local ok, value = Coins.ConvertToCash(src, coins)
    if not ok then respond(src, tostring(value or 'exchange failed'), 'error') end
    pushBalance(src)
end, false)

RegisterCommand(Config.Commands.give, function(src, args)
    if src == 0 then return end
    if not online(src) then return end

    local target = tonumber(args[1])
    local amount = Util.ParseAmount(args[2])
    if not target or not amount or amount <= 0 then
        respond(src, ('usage: /%s <player_id> <amount> [reason]'):format(Config.Commands.give), 'info')
        return
    end

    local reason = table.concat(args, ' ', 3)
    local ok, value = Coins.Transfer(src, target, amount, reason ~= '' and reason or 'Gift')
    if not ok then respond(src, tostring(value or 'transfer failed'), 'error') end
    pushBalance(src)
end, false)

RegisterCommand('coinhistory', function(src, args)
    if src == 0 then return end
    if not online(src) then return end

    local rows = Coins.History(src, tonumber(args[1]) or 15, 0)
    if #rows == 0 then
        respond(src, 'No coin transactions yet', 'info')
        return
    end

    for _, row in ipairs(rows) do
        respond(src, ('%s %s %s - %s'):format(
            tostring(row.created_at), (tonumber(row.change_amount) or 0) >= 0 and '+' or '',
            Util.Coins(row.change_amount), tostring(row.reason or row.transaction_type)), 'info')
    end
end, false)

RegisterCommand('coinquote', function(src, args)
    if src == 0 then return end
    if not online(src) then return end

    local amount = Util.ParseAmount(args[1])
    if not amount then
        respond(src, 'usage: /coinquote <amount> [in|out]', 'info')
        return
    end

    local direction = (args[2] or 'out'):lower()
    local quote = Coins.Quote(amount, direction)
    if not quote.valid then
        respond(src, ('Quote unavailable: %s'):format(tostring(quote.reason or 'invalid')), 'warning')
        return
    end

    respond(src, ('%s %s -> %s (fee %s), rate 1:%d'):format(
        direction == 'in' and 'Buy' or 'Sell', Util.Coins(quote.coins),
        Util.Cash(quote.cash), Util.Coins(quote.fee), quote.rate), 'info')
end, false)

RegisterCommand('coinpurchases', function(src)
    if src == 0 then return end
    if not online(src) then return end

    local rows = Coins.Purchases(src, 10)
    if #rows == 0 then
        respond(src, 'No shop purchases yet', 'info')
        return
    end
    for _, row in ipairs(rows) do
        respond(src, ('%s %dx %s - %s (%s)'):format(
            tostring(row.created_at), tonumber(row.quantity) or 1, tostring(row.item_name),
            Util.Coins(row.total_cost), tostring(row.delivery_status)), 'info')
    end
end, false)

-- ─── Admin command ───────────────────────────────────────────
RegisterCommand(Config.Commands.admin, function(src, args)
    if not isAdmin(src) then
        respond(src, 'Not authorised', 'error')
        return
    end

    local sub = tostring(args[1] or 'help'):lower()

    if sub == 'grant' then
        local target = tonumber(args[2])
        local amount = Util.ParseAmount(args[3])
        if not target or not amount then
            respond(src, 'usage: /coinadmin grant <player_id> <amount> <reason>', 'info')
            return
        end
        local reason = table.concat(args, ' ', 4)
        local ok, value = Coins.Grant(src, target, amount, reason)
        respond(src, ok and ('Granted %s'):format(Util.Coins(amount)) or tostring(value), ok and 'success' or 'error')

    elseif sub == 'balance' then
        local target = tonumber(args[2])
        if not target then
            respond(src, 'usage: /coinadmin balance <player_id>', 'info')
            return
        end
        respond(src, ('%s holds %s'):format(
            GetPlayerName(target) or tostring(target), Util.Coins(Coins.Balance(target))), 'info')

    elseif sub == 'fix' then
        local cid = tostring(args[2] or '')
        local delta = Util.Int(args[3])
        if cid == '' or not delta or delta == 0 then
            respond(src, 'usage: /coinadmin fix <citizenid> <delta> <reason>', 'info')
            return
        end
        local reason = table.concat(args, ' ', 4)
        local txn, after = Database.Correct(cid, delta, reason ~= '' and reason or 'admin fix')
        if txn then
            respond(src, ('Corrected %s. New balance %s (%s)'):format(cid, Util.Coins(after), txn), 'success')
        else
            respond(src, 'Correction failed - check the citizenid', 'error')
        end

    elseif sub == 'pool' then
        local pool = Database.Pool()
        if pool then
            respond(src, ('Pool %s: %s / %s, out %s, in %s'):format(
                tostring(pool.pool_date), Util.Cash(pool.remaining_pool), Util.Cash(pool.total_pool),
                Util.Cash(pool.cash_outs), Util.Cash(pool.cash_ins)), 'info')
        else
            respond(src, 'No pool row for today', 'warning')
        end

    elseif sub == 'cleanup' then
        Database.Cleanup()
        respond(src, 'Coin ledger cleanup complete', 'success')

    else
        respond(src, 'Usage: /coinadmin grant|balance|fix|pool|cleanup', 'info')
    end
end, false)

-- ─── Console commands ────────────────────────────────────────
RegisterCommand('coin_stats', function(src, args)
    if src ~= 0 then return end
    local days = tonumber(args[1]) or 7
    local row = Database.Single([[
        SELECT COUNT(*) AS total_transactions,
               COALESCE(SUM(CASE WHEN change_amount > 0 THEN change_amount ELSE 0 END), 0) AS total_incoming,
               COALESCE(SUM(CASE WHEN change_amount < 0 THEN -change_amount ELSE 0 END), 0) AS total_outgoing,
               COUNT(DISTINCT player_citizenid) AS active_players
          FROM `grand_coin_ledger`
         WHERE created_at > DATE_SUB(NOW(), INTERVAL ? DAY)
    ]], { days })

    if row then
        print(('[grand_coin] last %d days: %d txns, in %d, out %d, %d players'):format(
            days, tonumber(row.total_transactions) or 0, tonumber(row.total_incoming) or 0,
            tonumber(row.total_outgoing) or 0, tonumber(row.active_players) or 0))
    end

    local pool = Database.Pool()
    if pool then
        print(('[grand_coin] pool %s: %d / %d'):format(
            tostring(pool.pool_date), tonumber(pool.remaining_pool) or 0,
            tonumber(pool.total_pool) or 0))
    end
end, true)

RegisterCommand('coin_cleanup', function(src)
    if src ~= 0 then return end
    Database.Cleanup()
    print('[grand_coin] cleanup complete')
end, true)

-- ─── Exports ─────────────────────────────────────────────────
exports('Balance', function(target) return Coins.Balance(target) end)
exports('Debit', function(target, amount, reason, kind, meta)
    return Coins.Debit(target, amount, reason, kind, meta)
end)
exports('Credit', function(target, amount, reason, kind, meta)
    return Coins.Credit(target, amount, reason, kind, meta)
end)
exports('Transfer', function(source, targetSource, amount, reason)
    return Coins.Transfer(source, targetSource, amount, reason)
end)
exports('Grant', function(adminSource, targetSource, amount, reason)
    return Coins.Grant(adminSource, targetSource, amount, reason)
end)
exports('Quote', function(amount, direction) return Coins.Quote(amount, direction) end)
exports('ConvertToCoins', function(source, cash) return Coins.ConvertToCoins(source, cash) end)
exports('ConvertToCash', function(source, coins) return Coins.ConvertToCash(source, coins) end)
exports('PurchaseItem', function(source, slug, qty) return Coins.PurchaseItem(source, slug, qty) end)
exports('AwardJobCompletion', function(source, job) return Coins.AwardJobCompletion(source, job) end)
exports('AwardEventParticipation', function(source, event) return Coins.AwardEventParticipation(source, event) end)
exports('History', function(target, limit, offset) return Coins.History(target, limit, offset) end)
exports('Purchases', function(target, limit) return Coins.Purchases(target, limit) end)
exports('Stats', function(target, days) return Coins.Stats(target, days) end)
exports('Shop', function() return Config.Shop end)
exports('IsAdmin', function(src) return isAdmin(src) end)

-- ─── Lifecycle ───────────────────────────────────────────────
AddEventHandler('onResourceStart', function(resource)
    if resource ~= RESOURCE then return end
    CreateThread(function()
        Wait(1000)
        G.Start()
    end)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    Util.Log('info', 'Grand Coins stopped')
end)

return G
