-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/server/economy.lua
--  GetMoney / AddMoney / RemoveMoney exports + net events, the
--  cash / bank / crypto wallet, the `grand_money_logs` audit trail,
--  an anti-duplication guard, the salary pay loop and the bank
--  interest tick.
--
--  Wallets live on the session table (server/player.lua) and are
--  mirrored to `characters.money` on save so a crash cannot mint cash.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()

GrandEconomy = {}

local DB = GrandPlayer.DB

-- ─── Wallet helpers ─────────────────────────────────────────

--- Caps applied to a wallet after every mutation.
---@param wallet table
---@return table
function GrandEconomy.ApplyCaps(wallet)
    local caps = Config.Money.Caps or {}
    return {
        cash   = Util.Clamp(wallet.cash,   0, caps.cash   or 50000),
        bank   = Util.Clamp(wallet.bank,   0, caps.bank   or 2500000),
        crypto = Util.Clamp(wallet.crypto, 0, caps.crypto or 1000000),
    }
end

--- GetMoney(source) -> {cash, bank, crypto}
---@param source any
---@return table
function GrandEconomy.GetMoney(source)
    local session = GrandPlayer.Get(source)
    if session and session.money then
        local wallet = session.money
        return { cash = wallet.cash, bank = wallet.bank, crypto = wallet.crypto }
    end

    -- Offline fallback: read the row straight from the database.
    local citizenid = type(source) == 'string' and source or nil
    if citizenid then
        local row = GrandPlayer.GetRowByCitizenId(citizenid)
        if row then return Util.ParseMoney(row.money) end
    end

    return Util.EmptyMoney()
end

--- One bucket only (used by the ATM / banking UIs).
---@param source number
---@param kind string
---@return number
function GrandEconomy.GetMoneyBucket(source, kind)
    if not Util.IsMoneyKind(kind) then return 0 end
    return Util.Floor(GrandEconomy.GetMoney(source)[kind])
end

-- ─── Audit log ────────────────────────────────────────────

---@param session table
---@param kind string
---@param delta number
---@param reason string
---@param before table
---@param after table
local function WriteLog(session, kind, delta, reason, before, after)
    if not Config.Money.LogTransactions then return end

    DB.Insert('WriteMoneyLog', [[
        INSERT INTO grand_money_logs
            (citizenid, identifier, kind, amount, reason, balance_before, balance_after, total_before, total_after)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        session.citizenid,
        session.license,
        kind,
        Util.Floor(delta),
        Util.Trim(reason):sub(1, 120),
        Util.Floor(before[kind]),
        Util.Floor(after[kind]),
        Util.TotalMoney(before),
        Util.TotalMoney(after),
    })
end

-- ─── Broadcast ────────────────────────────────────────────

---@param session table
---@param kind string
---@param delta number
---@param reason string
local function Publish(session, kind, delta, reason)
    TriggerClientEvent('grand_core:client:MoneyUpdated', session.source, session.money)

    TriggerEvent('grand_core:server:MoneyChanged', {
        source    = session.source,
        citizenid = session.citizenid,
        kind      = kind,
        amount    = delta,
        reason    = reason,
        wallet    = GrandEconomy.GetMoney(session.source),
    })
end

-- ─── AddMoney ─────────────────────────────────────────────

--- AddMoney(source, kind, amount) -> boolean
---@param source any
---@param kind string
---@param amount any
---@param reason? string
---@return boolean
function GrandEconomy.AddMoney(source, kind, amount, reason)
    local session = GrandPlayer.Get(source)
    if not session then
        Util.Log('warn', ('AddMoney: no session for %s'):format(tostring(source)))
        return false
    end

    if not Util.IsMoneyKind(kind) then
        Util.Log('error', ('AddMoney: unknown money kind "%s"'):format(tostring(kind)))
        return false
    end

    amount = Util.Floor(amount)
    if amount <= 0 then
        Util.Log('warn', ('AddMoney: rejected amount %s for %s'):format(tostring(amount), session.citizenid))
        return false
    end

    if amount > Config.Money.MaxTransaction then
        Util.Log('warn', ('AddMoney: %s exceeds the transaction ceiling for %s'):format(amount, session.citizenid))
        return false
    end

    reason = reason or 'add'

    -- Anti-duplication: the same amount + reason twice inside the window
    -- is treated as a double-firing UI button, not a second payment.
    local key = ('%s:%s:%d'):format(kind, reason, amount)
    if GrandPlayer.IsDuplicate(session.source, key, Config.Money.DuplicateWindowSeconds) then
        Util.Log('warn', ('AddMoney blocked duplicate %s for %s'):format(key, session.citizenid))
        return false
    end
    GrandPlayer.MarkTransaction(session.source, key)

    local before = Util.Copy(session.money)
    local wallet = GrandEconomy.ApplyCaps({
        cash   = before.cash   + (kind == 'cash'   and amount or 0),
        bank   = before.bank   + (kind == 'bank'   and amount or 0),
        crypto = before.crypto + (kind == 'crypto' and amount or 0),
    })

    if wallet[kind] == before[kind] then
        Util.Log('warn', ('AddMoney: %s is at its cap (%s)'):format(kind, session.citizenid))
        return false
    end

    local delta = wallet[kind] - before[kind]
    session.money = wallet
    session.dirty = true

    WriteLog(session, kind, delta, reason, before, wallet)
    GrandEconomy.FlushWallet(session.source)
    Publish(session, kind, delta, reason)

    return true
end

-- ─── RemoveMoney ──────────────────────────────────────────

--- RemoveMoney(source, kind, amount) -> boolean
---@param source any
---@param kind string
---@param amount any
---@param reason? string
---@return boolean
function GrandEconomy.RemoveMoney(source, kind, amount, reason)
    local session = GrandPlayer.Get(source)
    if not session then
        Util.Log('warn', ('RemoveMoney: no session for %s'):format(tostring(source)))
        return false
    end

    if not Util.IsMoneyKind(kind) then
        Util.Log('error', ('RemoveMoney: unknown money kind "%s"'):format(tostring(kind)))
        return false
    end

    amount = Util.Floor(amount)
    if amount <= 0 then
        Util.Log('warn', ('RemoveMoney: rejected amount %s for %s'):format(tostring(amount), session.citizenid))
        return false
    end

    if amount > Config.Money.MaxTransaction then
        Util.Log('warn', ('RemoveMoney: %s exceeds the transaction ceiling for %s'):format(amount, session.citizenid))
        return false
    end

    reason = reason or 'remove'

    local key = ('%s:%s:%d'):format(kind, reason, amount)
    if GrandPlayer.IsDuplicate(session.source, key, Config.Money.DuplicateWindowSeconds) then
        Util.Log('warn', ('RemoveMoney blocked duplicate %s for %s'):format(key, session.citizenid))
        return false
    end
    GrandPlayer.MarkTransaction(session.source, key)

    local before = Util.Copy(session.money)
    if before[kind] < amount then
        return false
    end

    session.money = {
        cash   = before.cash   - (kind == 'cash'   and amount or 0),
        bank   = before.bank   - (kind == 'bank'   and amount or 0),
        crypto = before.crypto - (kind == 'crypto' and amount or 0),
    }
    session.dirty = true

    WriteLog(session, kind, -amount, reason, before, session.money)
    GrandEconomy.FlushWallet(session.source)
    Publish(session, kind, -amount, reason)

    return true
end

--- Moves money between two buckets of the same wallet.
---@param source any
---@param from string
---@param to string
---@param amount any
---@param reason? string
---@return boolean
function GrandEconomy.TransferBucket(source, from, to, amount, reason)
    if from == to then return true end
    if not Util.IsMoneyKind(from) or not Util.IsMoneyKind(to) then return false end

    amount = Util.Floor(amount)
    if amount <= 0 then return false end

    if not GrandEconomy.RemoveMoney(source, from, amount, reason or 'withdraw') then
        return false
    end

    if not GrandEconomy.AddMoney(source, to, amount, reason or 'deposit') then
        -- Roll the removal back so a failed deposit is not money lost.
        GrandEconomy.AddMoney(source, from, amount, 'transfer-rollback')
        return false
    end

    return true
end

--- Wallet-to-wallet payment between two connected players. Money leaves
--- the sender first and is only credited once the debit succeeded.
---@param sender number
---@param receiver number
---@param amount any
---@param kind? string
---@param reason? string
---@return boolean
function GrandEconomy.PayPlayer(sender, receiver, amount, kind, reason)
    sender, receiver = tonumber(sender), tonumber(receiver)
    kind = kind or 'cash'
    amount = Util.Floor(amount)

    if not sender or not receiver or sender == receiver then return false end
    if amount <= 0 then return false end
    if not GrandPlayer.Get(receiver) then return false end

    local target = GrandPlayer.Get(receiver)
    local caps = Config.Money.Caps or {}
    local incoming = GrandEconomy.GetMoney(target.source)

    if kind == 'cash' and incoming.cash + amount > (caps.cash or 50000) then
        TriggerClientEvent('grand_core:client:Notify', sender, 'That player cannot carry any more cash', 'error')
        return false
    end

    if not GrandEconomy.RemoveMoney(sender, kind, amount, reason or 'payment') then
        TriggerClientEvent('grand_core:client:Notify', sender, 'You do not have enough money', 'error')
        return false
    end

    if not GrandEconomy.AddMoney(receiver, kind, amount, reason or 'payment') then
        GrandEconomy.AddMoney(sender, kind, amount, 'payment-rollback')
        return false
    end

    TriggerClientEvent('grand_core:client:Notify', receiver,
        ('You received %s'):format(Util.FormatMoney(amount)), 'success')
    return true
end

--- Immediate narrow write of the money column.
---@param source number
function GrandEconomy.FlushWallet(source)
    if not Config.Money.FlushOnEveryChange then return end
    GrandPlayer.SaveWallet(source)
end

-- ─── Tax ──────────────────────────────────────────────────

--- Splits a price into (net to vendor, tax to the state ledger).
---@param amount any
---@return number net, number tax
function GrandEconomy.SplitTax(amount)
    amount = math.max(0, Util.Floor(amount))
    local rate = Config.Money.TaxRate or 0
    local tax = math.floor(amount * rate + 0.5)
    return amount - tax, tax
end

-- ─── Salary loop ──────────────────────────────────────────

---@param session table
---@return number
function GrandEconomy.CalculateSalary(session)
    local jobName = session.job or 'unemployed'

    if Config.Salary.RequireOnDuty and not session.onDuty then
        local job = Config.JobIndex[jobName]
        if job and job.onDutyOnly then return 0 end
        if job and not job.canBeOffDuty then return 0 end
        if job and job.type == 'government' then return 0 end
    end

    local jobPay = Config.GetJobPay(jobName)
    local grade  = Config.JobIndex[jobName] and Config.JobIndex[jobName].grades
        and Config.JobIndex[jobName].grades[session.jobGrade] or nil

    if grade and grade.multiplier then
        jobPay = math.floor(jobPay * grade.multiplier)
    end

    local total = Config.Salary.BasePay
        + (session.level * Config.Salary.LevelMultiplier)
        + jobPay

    if Config.Salary.RequireOnDuty and not session.onDuty then
        total = math.floor(total * Config.Salary.OffDutyMultiplier)
    end

    return math.max(0, Util.Floor(total))
end

--- Pays every online character once and returns a summary.
---@return number paid, number skipped
function GrandEconomy.RunPayday()
    if not Config.Salary.Enabled then return 0, 0 end

    local paid, skipped = 0, 0

    for _, session in pairs(GrandPlayer.OnlineSessions()) do
        local salary = GrandEconomy.CalculateSalary(session)

        if salary <= 0 then
            skipped = skipped + 1
        elseif GrandEconomy.AddMoney(session.source, Config.Salary.DebitTo, salary, 'salary') then
            paid = paid + 1
            TriggerClientEvent('grand_core:client:Notify', session.source,
                Config.Notifications.Salary:format(Util.FormatMoney(salary)), 'primary')
        else
            skipped = skipped + 1
        end
    end

    Util.Log('info', ('Payday complete: %d paid, %d skipped'):format(paid, skipped))
    return paid, skipped
end

-- ─── Bank interest tick ───────────────────────────────────

---@param balance number
---@return number
function GrandEconomy.CalculateInterest(balance)
    balance = Util.Floor(balance)
    if balance < Config.Bank.MinBalance then return 0 end

    local interest = math.floor(balance * Config.Bank.InterestRate)
    return math.max(0, math.min(interest, Config.Bank.MaxInterest))
end

--- Credits interest to every connected bank account.
---@return number paid
function GrandEconomy.RunInterest()
    if not Config.Bank.Enabled then return 0 end

    local paid = 0

    for _, session in pairs(GrandPlayer.OnlineSessions()) do
        local interest = GrandEconomy.CalculateInterest(session.money.bank)

        if interest > 0 and GrandEconomy.AddMoney(session.source, 'bank', interest, 'bank interest') then
            paid = paid + 1
            TriggerClientEvent('grand_core:client:Notify', session.source,
                Config.Notifications.Interest:format(Util.FormatMoney(interest)), 'info')
        end
    end

    if Config.Debug then Util.Debug(('Interest tick: %d accounts credited'):format(paid)) end
    return paid
end

-- ─── Loops ────────────────────────────────────────────────

local loopsStarted = false

function GrandEconomy.StartLoops()
    if loopsStarted then return end
    loopsStarted = true

    Citizen.CreateThread(function()
        -- Let everyone settle in before the first payout.
        Wait(math.max(15, Config.Salary.FirstPayoutDelay) * 1000)

        while true do
            GrandEconomy.RunPayday()
            Wait(math.max(300, Config.Salary.PayoutInterval) * 1000)
        end
    end)

    Citizen.CreateThread(function()
        Wait(math.max(60, Config.Bank.InterestTick) * 1000)

        while true do
            GrandEconomy.RunInterest()
            Wait(math.max(60, Config.Bank.InterestTick) * 1000)
        end
    end)

    Util.Log('info', ('Economy loops armed (payday %s, interest %s)'):format(
        Util.FormatDuration(Config.Salary.PayoutInterval),
        Util.FormatDuration(Config.Bank.InterestTick)))
end

-- ─── Net events ───────────────────────────────────────────

RegisterNetEvent('grand_core:server:Deposit', function(amount)
    local session = GrandPlayer.Get(source)
    if not session then return end

    amount = Util.Floor(amount)
    if amount <= 0 then return end

    -- Large deposits are taxed (Config.Money.TaxRate) once they clear the
    -- tax-free threshold, which is how the ledger flags suspicious cash-in.
    local net, tax = amount, 0
    if amount > Config.Money.TaxFreeDeposit then
        net, tax = GrandEconomy.SplitTax(amount)
    end

    if session.money.cash < (net + tax) then
        TriggerClientEvent('grand_core:client:Notify', session.source, 'You do not have that much cash', 'error')
        return
    end

    if not GrandEconomy.RemoveMoney(session.source, 'cash', net + tax, 'bank deposit') then return end

    if GrandEconomy.AddMoney(session.source, 'bank', net, 'bank deposit') then
        TriggerClientEvent('grand_core:client:Notify', session.source,
            Config.Notifications.Deposit:format(Util.FormatMoney(net)), 'success')
    else
        GrandEconomy.AddMoney(session.source, 'cash', net + tax, 'deposit-rollback')
    end
end)

RegisterNetEvent('grand_core:server:Withdraw', function(amount)
    local session = GrandPlayer.Get(source)
    if not session then return end

    amount = Util.Floor(amount)
    if amount <= 0 then return end

    local caps = Config.Money.Caps or {}
    if session.money.cash + amount > (caps.cash or 50000) then
        TriggerClientEvent('grand_core:client:Notify', session.source, 'Your pockets are full', 'error')
        return
    end

    if not GrandEconomy.RemoveMoney(session.source, 'bank', amount, 'bank withdraw') then
        TriggerClientEvent('grand_core:client:Notify', session.source, 'Insufficient bank balance', 'error')
        return
    end

    if GrandEconomy.AddMoney(session.source, 'cash', amount, 'bank withdraw') then
        TriggerClientEvent('grand_core:client:Notify', session.source,
            Config.Notifications.Withdraw:format(Util.FormatMoney(amount)), 'success')
    else
        GrandEconomy.AddMoney(session.source, 'bank', amount, 'withdraw-rollback')
    end
end)

RegisterNetEvent('grand_core:server:PayPlayer', function(target, amount)
    local session = GrandPlayer.Get(source)
    if not session then return end

    GrandEconomy.PayPlayer(session.source, tonumber(target), amount, 'cash', 'player payment')
end)

RegisterNetEvent('grand_core:server:ChargeTax', function(amount)
    local session = GrandPlayer.Get(source)
    if not session then return end

    local _, tax = GrandEconomy.SplitTax(amount)
    if tax <= 0 then return end

    GrandEconomy.RemoveMoney(session.source, 'cash', tax, 'sales tax')
end)

-- ─── Admin / console ──────────────────────────────────────

RegisterCommand('grandpayday', function(executor)
    if tonumber(executor) and not IsPlayerAceAllowed(tostring(executor), 'grand_core.payday') then
        TriggerClientEvent('grand_core:client:Notify', executor, 'Not allowed', 'error')
        return
    end

    local paid = GrandEconomy.RunPayday()
    print(('[grand_core] Manual payday paid %d players'):format(paid))
end, true)

RegisterCommand('grandinterest', function(executor)
    if tonumber(executor) and not IsPlayerAceAllowed(tostring(executor), 'grand_core.payday') then
        TriggerClientEvent('grand_core:client:Notify', executor, 'Not allowed', 'error')
        return
    end

    local paid = GrandEconomy.RunInterest()
    print(('[grand_core] Manual interest tick credited %d accounts'):format(paid))
end, true)

-- ─── Exports ──────────────────────────────────────────────

exports('GetMoney',        GrandEconomy.GetMoney)
exports('AddMoney',        GrandEconomy.AddMoney)
exports('RemoveMoney',     GrandEconomy.RemoveMoney)
exports('TransferBucket',  GrandEconomy.TransferBucket)
exports('PayPlayer',       GrandEconomy.PayPlayer)
exports('SplitTax',        GrandEconomy.SplitTax)
exports('CalculateSalary', GrandEconomy.CalculateSalary)
exports('RunPayday',       GrandEconomy.RunPayday)
exports('RunInterest',     GrandEconomy.RunInterest)

_G.GrandEconomy = GrandEconomy
