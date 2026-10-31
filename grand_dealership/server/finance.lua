-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_dealership/server/finance.lua
--  Weekly instalments, late fees, early settlement and default /
--  repossession. One scheduler tick handles every active deal.
-- ─────────────────────────────────────────────────────────────

DealerFinance = DealerFinance or {}
local F = DealerFinance

F.Booted = false
F.LastTick = 0

-- ─── Helpers ─────────────────────────────────────────────────
local function online(src)
    src = tonumber(src)
    return src ~= nil and src > 0 and GetPlayerName(src) ~= nil
end

local function sourceFor(citizenid)
    local src = DealerShared.TryExport('grand_core', 'GetSourceByCitizenId', citizenid)
    src = tonumber(src)
    if src and online(src) then return src end
    return nil
end

local function lateFeeFor(weekly)
    return math.ceil((tonumber(weekly) or 0) * (Config.Finance.lateFeePercent or 0.12))
end

function F.Remaining(row)
    local term = tonumber(row.term_weeks) or 0
    local paid = tonumber(row.weeks_paid) or 0
    local weekly = tonumber(row.weekly_payment) or 0
    return math.max(0, (term - paid) * weekly + (tonumber(row.late_fees) or 0))
end

function F.Summary(row)
    if not row then return nil end
    return {
        id = tonumber(row.id),
        plate = row.plate,
        model = row.model,
        status = row.status,
        weekly = tonumber(row.weekly_payment) or 0,
        lateFees = tonumber(row.late_fees) or 0,
        weeksPaid = tonumber(row.weeks_paid) or 0,
        termWeeks = tonumber(row.term_weeks) or 0,
        missedWeeks = tonumber(row.missed_weeks) or 0,
        financed = tonumber(row.financed) or 0,
        remaining = F.Remaining(row),
        nextDue = row.next_due_at,
    }
end

function F.ForCitizen(citizenid)
    local rows = DB.ActiveFinanceFor(citizenid)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = F.Summary(row) end
    return out
end

function F.Find(citizenid, key)
    key = tostring(key or '')
    if key == '' then return nil end

    local id = DealerShared.Int(key)
    if id then
        local row = DB.FinanceById(id)
        if row and row.citizenid == citizenid and row.status == 'active' then return row end
        return nil
    end

    return DB.ActiveFinanceFor(citizenid, DealerShared.SanitizePlate(key))
end

-- ─── Payments ────────────────────────────────────────────────
local function applyPayment(row, weeks, source)
    weeks = math.max(1, DealerShared.Int(weeks) or 1)
    local weekly = tonumber(row.weekly_payment) or 0
    local late = tonumber(row.late_fees) or 0
    local amount = weekly * weeks + late

    if amount <= 0 then return false, 'nothing to pay' end

    local src = source or sourceFor(row.citizenid)
    if not src then return false, 'the account holder must be online to pay' end

    local paid, reason = DealerShared.TakePayment(src, amount,
        ('Vehicle finance #%d'):format(tonumber(row.id) or 0))
    if not paid then return false, reason or 'payment failed' end

    local interestPerWeek = math.floor((tonumber(row.financed) or 0) * (tonumber(row.apr) or 0) / 52)
    local principalPart = math.max(0, weekly - interestPerWeek) * weeks
    local interestPart = math.max(0, amount - principalPart - late)

    local weeksPaid = (tonumber(row.weeks_paid) or 0) + weeks
    local term = tonumber(row.term_weeks) or 0
    local nextDue = tonumber(row.next_due_at) or os.time()
    nextDue = math.max(os.time(), nextDue) + (Config.Finance.weekSeconds or 604800)

    DB.RecordPayment({
        finance_id = row.id,
        citizenid = row.citizenid,
        amount = amount,
        principal_part = principalPart,
        interest_part = math.max(0, interestPart),
        late_fee = late,
        weeks = weeks,
        source = 'bank',
    })

    if weeksPaid >= term then
        DB.SetFinanceStatus(row.id, 'paid')
        DB.UpdateFinanceAfterPayment(row.id, term, nextDue, 0)
        DealerShared.Notify(src, ('Finance #%d is fully paid. The %s is yours outright.'):format(
            tonumber(row.id) or 0, tostring(row.model)), 'success')
    else
        DB.UpdateFinanceAfterPayment(row.id, weeksPaid, nextDue, 0)
        DealerShared.Notify(src, ('Finance #%d paid: %s. %d of %d weeks remaining.'):format(
            tonumber(row.id) or 0, DealerShared.Money(amount),
            math.max(0, term - weeksPaid), term), 'success')
    end

    DealerShared.Log('info', ('finance #%s payment %s by %s'):format(
        tostring(row.id), tostring(amount), tostring(row.citizenid)))
    return true, amount
end

function F.Pay(src, key)
    src = tonumber(src)
    if not online(src) then return false, 'invalid player' end

    local citizenid = DealerShared.GetCitizenId(src)
    if not citizenid then return false, 'character not loaded' end

    local row = F.Find(citizenid, key)
    if not row then return false, 'no active finance agreement matched that' end
    if not DealerShared.Cooldown('finance:' .. src, 5) then return false, 'slow down' end

    return applyPayment(row, 1, src)
end

function F.Settle(src, key)
    src = tonumber(src)
    if not online(src) then return false, 'invalid player' end

    local citizenid = DealerShared.GetCitizenId(src)
    if not citizenid then return false, 'character not loaded' end

    local row = F.Find(citizenid, key)
    if not row then return false, 'no active finance agreement matched that' end

    local term = tonumber(row.term_weeks) or 0
    local paid = tonumber(row.weeks_paid) or 0
    local weeksLeft = math.max(0, term - paid)
    if weeksLeft <= 0 then
        DB.SetFinanceStatus(row.id, 'paid')
        return true, 0
    end

    return applyPayment(row, weeksLeft, src)
end

-- ─── Scheduler ───────────────────────────────────────────────
local function repossess(row, reason)
    DB.SetFinanceStatus(row.id, 'defaulted')
    DB.RecordRepossession({
        finance_id = row.id,
        citizenid = row.citizenid,
        plate = row.plate,
        model = row.model,
        reason = reason,
    })

    local vehicle = DB.VehicleByPlate(row.plate)
    if vehicle then
        DB.SetVehicleState(row.plate, 2, 'Repossessed')
    end

    local src = sourceFor(row.citizenid)
    if src then
        DealerShared.Notify(src, ('REPOSSESSION: finance #%d defaulted. The %s was collected.'):format(
            tonumber(row.id) or 0, tostring(row.model)), 'error')
    end

    DealerShared.Log('warn', ('repossessed %s (%s) for %s'):format(
        tostring(row.plate), tostring(row.model), tostring(row.citizenid)))
end

function F.Tick()
    for _, row in ipairs(DB.DueFinance()) do
        local src = sourceFor(row.citizenid)
        local weekly = tonumber(row.weekly_payment) or 0
        local lateFees = tonumber(row.late_fees) or 0
        local missed = tonumber(row.missed_weeks) or 0

        local amount = weekly + lateFees
        local paid = false

        if src and amount > 0 then
            paid = DealerShared.TakePayment(src, amount,
                ('Vehicle finance #%d instalment'):format(tonumber(row.id) or 0))
            if paid then
                DB.RecordPayment({
                    finance_id = row.id,
                    citizenid = row.citizenid,
                    amount = amount,
                    principal_part = weekly,
                    interest_part = 0,
                    late_fee = lateFees,
                    weeks = 1,
                    source = 'bank',
                })
            end
        end

        local nextDue = tonumber(row.next_due_at) or os.time()
        nextDue = math.max(os.time(), nextDue) + (Config.Finance.weekSeconds or 604800)

        if paid then
            local weeksPaid = (tonumber(row.weeks_paid) or 0) + 1
            local term = tonumber(row.term_weeks) or 0
            if weeksPaid >= term then
                DB.SetFinanceStatus(row.id, 'paid')
                DB.UpdateFinanceAfterPayment(row.id, term, nextDue, 0)
                if src then
                    DealerShared.Notify(src, ('Finance #%d is fully paid.'):format(
                        tonumber(row.id) or 0), 'success')
                end
            else
                DB.UpdateFinanceAfterPayment(row.id, weeksPaid, nextDue, 0)
                if src then
                    DealerShared.Notify(src, ('Finance #%d charged %s (%d/%d weeks).'):format(
                        tonumber(row.id) or 0, DealerShared.Money(amount), weeksPaid, term), 'info')
                end
            end
        else
            missed = missed + 1
            local newLate = lateFees
            if missed > (Config.Finance.graceWeeks or 1) and lateFees == 0 then
                newLate = lateFeeFor(weekly)
            end

            if missed > (Config.Finance.defaultAfterWeeks or 3) then
                repossess(row, ('missed %d instalments'):format(missed))
            else
                DB.SetFinanceDue(row.id, nextDue, missed, newLate)
                if src then
                    DealerShared.Notify(src, ('Finance #%d missed a payment (%d/%d grace).'):format(
                        tonumber(row.id) or 0, missed, Config.Finance.defaultAfterWeeks or 3), 'warning')
                end
            end
        end
    end
end

function F.Boot()
    if F.Booted then return end
    F.Booted = true

    CreateThread(function()
        Wait(10000)
        while true do
            Wait(math.max(30, DealerShared.Int(Config.Timing.financeTickMs or 60000) // 1000) * 1000)

            local ok, err = pcall(F.Tick)
            if not ok then
                DealerShared.Log('error', ('finance tick failed: %s'):format(tostring(err)))
            end

            DB.ExpireTestDrives()
            DealerShared.PruneCooldowns()
        end
    end)
end

return F
