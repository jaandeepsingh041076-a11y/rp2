-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/server/income.lua
--  Payday + interest + turf/property bonuses; runs as a rescheduling
--  `while true` loop, NOT a one-shot SetTimeout that dies forever.
-- ─────────────────────────────────────────────────────────────

-- Globals inside this resource: shared/util.lua runs first in every
-- context, then these modules attach to the same table.
Income = {}
Families = Families or {}
Families.Income = Income

local RESOURCE = GetCurrentResourceName()

function Income.Log(level, message)
    if (Income.LEVELS[level] or 2) < (Income.LEVELS[Config.LogLevel] or 2) then return end
    local colour = ({ error = '^1', warn = '^3', info = '^7', debug = '^8' })[level] or '^7'
    print(('%s[%s][income] %s^7'):format(colour, RESOURCE, tostring(message)))
end

Income.LEVELS = { debug = 3, info = 2, warn = 1, error = 0 }

-- ─── Interest (bank balance grows) ─────────────────────────────
function Income.RunInterest()
    local start = os.time()
    Income.Log('debug', 'interest tick started')

    local families = DB.ListFamilies(0)
    local processed, skipped, errored = 0, 0, 0
    local rate = Config.Income.interestRate or 0.001   -- plain fraction, 0.001 = 0.1%

    for _, family in ipairs(families) do
        local id = family.id
        local balance = tonumber(family.balance) or 0

        if balance <= 0 then
            skipped = skipped + 1
            goto continue
        end

        local interest = math.floor(balance * rate)
        if interest < 1 then
            skipped = skipped + 1
            goto continue
        end

        local newBalance, before, delta = DB.MoveVault(id, interest, 'interest', 'system', 'daily interest')
        if newBalance then
            processed = processed + 1
        else
            errored = errored + 1
        end

        ::continue::
    end

    Income.Log('info', ('interest: %d processed, %d zero, %d errored (%.2fs)'):format(
        processed, skipped, errored, os.time() - start))
end

-- ─── Turf / property bonuses ───────────────────────────────────
function Income.RunPayouts()
    local start = os.time()
    Income.Log('debug', 'payout tick started')

    -- All active properties (solar panels + oil wells)
    local properties = DB.AllActiveProperties()
    local propPaid = 0
    local propSkipped = 0

    for _, prop in ipairs(properties) do
        local familyId = prop.family_id
        local now = os.time()
        local last = Util.SqlToEpoch(prop.last_payout)
        local elapsed = now - last

        if elapsed >= Config.Income.payoutSeconds then
            local yield = 0
            if prop.property_type == 'solar_panel' then
                yield = Config.Income.solarYield or 1500
            elseif prop.property_type == 'oil_well' then
                yield = Config.Income.oilYield or 5000
            end

            local newBalance, before, delta = DB.MoveVault(
                familyId, yield, 'property', 'system',
                ('%s income'):format(prop.property_type)
            )
            if newBalance then
                DB.TouchPropertyPayout(prop.id)
                propPaid = propPaid + 1
            else
                propSkipped = propSkipped + 1
            end
        end
    end

    -- Turf bonuses (tier‑scaled)
    local turfs = DB.AllOwnedTurfs()
    local turfPaid = 0
    local turfSkipped = 0

    for _, turf in ipairs(turfs) do
        local familyId = turf.family_id
        local now = os.time()
        local last = Util.SqlToEpoch(turf.last_bonus_payout)
        local elapsed = now - last

        if elapsed >= Config.Income.payoutSeconds then
            local tier = tonumber(turf.tier) or 1
            local base = Config.TurfWar.hourlyBase or 10000
            local bonus = math.floor(base * tier)

            local newBalance, before, delta = DB.MoveVault(
                familyId, bonus, 'turf', 'system',
                ('%s turf income'):format(turf.turf_name)
            )
            if newBalance then
                DB.TouchTurfPayout(turf.id)
                turfPaid = turfPaid + 1
            else
                turfSkipped = turfSkipped + 1
            end
        end
    end

    Income.Log('info', ('payouts: %d props, %d turfs (%.2fs)'):format(
        propPaid, turfPaid, os.time() - start))
end

-- ─── Offline accrual ──────────────────────────────────────────
function Income.CatchupOnBoot()
    if not Config.Income.offlineAccrual then
        Income.Log('info', 'offline accrual disabled')
        return
    end

    local start = os.time()
    Income.Log('debug', 'catchup started')

    -- Properties
    local properties = DB.AllActiveProperties()
    for _, prop in ipairs(properties) do
        local now = os.time()
        local last = Util.SqlToEpoch(prop.last_payout)
        local elapsed = now - last
        local periods = math.floor(elapsed / Config.Income.payoutSeconds)

        if periods > 0 then
            local yield = 0
            if prop.property_type == 'solar_panel' then
                yield = Config.Income.solarYield or 1500
            elseif prop.property_type == 'oil_well' then
                yield = Config.Income.oilYield or 5000
            end

            local total = yield * periods
            DB.MoveVault(
                prop.family_id, total, 'property_catchup', 'system',
                ('%dx %s catchup'):format(periods, prop.property_type)
            )
            DB.TouchPropertyPayout(prop.id)
        end
    end

    -- Turfs
    local turfs = DB.AllOwnedTurfs()
    for _, turf in ipairs(turfs) do
        local now = os.time()
        local last = Util.SqlToEpoch(turf.last_bonus_payout)
        local elapsed = now - last
        local periods = math.floor(elapsed / Config.Income.payoutSeconds)

        if periods > 0 then
            local tier = tonumber(turf.tier) or 1
            local base = Config.TurfWar.hourlyBase or 10000
            local total = math.floor(base * tier) * periods

            DB.MoveVault(
                turf.family_id, total, 'turf_catchup', 'system',
                ('%dx %s catchup'):format(periods, turf.turf_name)
            )
            DB.TouchTurfPayout(turf.id)
        end
    end

    Income.Log('info', ('catchup done (%.2fs)'):format(os.time() - start))
end

-- ─── Thread loops ─────────────────────────────────────────────
Income.Running = false

function Income.StartLoops()
    if Income.Running then return end
    Income.Running = true

    -- Interest, daily
    CreateThread(function()
        while Income.Running do
            Wait((Config.Income.interestSeconds or 86400) * 1000)
            if Income.Running then Income.RunInterest() end
        end
    end)

    -- Payouts, hourly
    CreateThread(function()
        Wait(30000)  -- let the server settle
        if not Income.Running then return end
        Income.CatchupOnBoot()
        while Income.Running do
            Income.RunPayouts()
            Wait((Config.Income.payoutSeconds or 3600) * 1000)
        end
    end)
end

function Income.Stop()
    Income.Running = false
    Income.Log('info', 'income loops stopped')
end

return Income