-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/server/jobs.lua
--  Session registry + the job board (create / claim / abandon /
--  complete) that every branch — mechanic, tow, taxi, jack — runs on.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local DB = Mechanic.DB

local Jobs = {}
Mechanic.Jobs = Jobs

Jobs.Sessions = {}   -- [source] = session

-- ─── Bridge helpers ───────────────────────────────────────────
local function TryExport(res, name, ...)
    if GetResourceState(res) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[res][name](table.unpack(args, 1, args.n))
    end)
    if not ok then
        DB.Log('warn', ('%s:%s failed: %s'):format(res, name, tostring(result)))
        return nil
    end
    return result
end
Jobs.TryExport = TryExport

local function CitizenId(source)
    local cid = TryExport('grand_core', 'GetCitizenId', source)
    if cid and type(cid) == 'string' then return cid end
    local s = Jobs.Sessions[source]
    return s and s.cid or nil
end
Jobs.CitizenId = CitizenId

local function JobName(source)
    local data = TryExport('grand_core', 'GetJob', source)
    if type(data) == 'table' then return data.name or data.job end
    if type(data) == 'string' then return data end
    local s = Jobs.Sessions[source]
    if s and s.job then return s.job end
    local cid = CitizenId(source)
    if not cid then return nil end
    local row = DB.Character(cid)
    return row and row.job or nil
end
Jobs.JobName = JobName

local function Money(source, kind)
    local wallet = TryExport('grand_core', 'GetMoney', source)
    if type(wallet) ~= 'table' then return 0 end
    return math.floor(tonumber(wallet[kind]) or 0)
end
Jobs.Money = Money

local function Pay(source, kind, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    local ok = TryExport('grand_core', 'AddMoney', source, kind, amount, reason or 'mechanic')
    if ok == false or ok == nil then
        -- no core: fall back to the wallet column directly
        local cid = CitizenId(source)
        if not cid then return false end
        local row = DB.Character(cid)
        if not row then return false end
        local wallet = DB.Decode(row.money, { cash = 0, bank = 0, crypto = 0 })
        wallet[kind] = math.floor((tonumber(wallet[kind]) or 0) + amount)
        MySQL.update.await('UPDATE characters SET money = ? WHERE citizenid = ?',
            { json.encode(wallet), cid })
    end
    TryExport('grand_core', 'MarkDirty', source)
    return true
end
Jobs.Pay = Pay

local function Take(source, kind, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return true end
    local ok = TryExport('grand_core', 'RemoveMoney', source, kind, amount, reason or 'mechanic')
    if ok == false or ok == nil then
        if Money(source, kind) < amount then return false end
        local cid = CitizenId(source)
        if not cid then return false end
        local row = DB.Character(cid)
        if not row then return false end
        local wallet = DB.Decode(row.money, { cash = 0, bank = 0, crypto = 0 })
        wallet[kind] = math.floor((tonumber(wallet[kind]) or 0) - amount)
        MySQL.update.await('UPDATE characters SET money = ? WHERE citizenid = ?',
            { json.encode(wallet), cid })
    end
    TryExport('grand_core', 'MarkDirty', source)
    return true
end
Jobs.Take = Take

local function Notify(source, message, kind)
    TriggerClientEvent('grand_core:client:Notify', source, message, kind or 'info')
end
Jobs.Notify = Notify

-- ─── Progression ──────────────────────────────────────────────
local function LevelFromXp(xp)
    local levels = Config.Progression.levels
    local level = 0
    for i = 1, #levels do
        if (xp or 0) >= levels[i] then level = i - 1 end
    end
    return level
end
Jobs.LevelFromXp = LevelFromXp

function Jobs.XpFor(kind)
    local p = Config.Progression
    if kind == 'tow' then return p.xpPerTow end
    if kind == 'jack' then return p.xpPerJack end
    if kind == 'taxi' then return p.xpPerTaxi end
    return p.xpPerJob
end

function Jobs.RegisterAction(source, kind, payout)
    local session = Jobs.Sessions[source]
    if not session then return end

    local fieldMap = { mechanic = 'repairs', tow = 'tows', jack = 'jacks', taxi = 'fares' }
    local field = fieldMap[kind] or 'repairs'
    local xp = Jobs.XpFor(kind)

    local row = DB.AddXp(session.cid, xp, field, payout or 0)
    if row then
        session.xp = row.xp or 0
        session.level = LevelFromXp(session.xp)
        if session.level ~= session.reportedLevel then
            session.reportedLevel = session.level
            Notify(source, ('RANK UP — LEVEL %d (%s)'):format(
                session.level + 1,
                Shared.InList({ 'mechanic', 'tow', 'taxi' }, kind) and 'bonus pay unlocked' or 'better resale'), 'primary')
            DB.SetLevel(session.cid, session.level)
        end
    end
end

-- ─── Session lifecycle ────────────────────────────────────────
function Jobs.Attach(source)
    local cid = CitizenId(source)
    if not cid then return nil end

    DB.EnsureStats(cid)
    local stats = DB.Stats(cid) or { xp = 0, level = 0 }

    Jobs.Sessions[source] = {
        cid = cid,
        job = JobName(source),
        xp = stats.xp or 0,
        level = LevelFromXp(stats.xp or 0),
        reportedLevel = LevelFromXp(stats.xp or 0),
        active = nil,          -- job_ref
        working = nil,         -- timer end
        busted = 0,
        lastCall = {},         -- anti-spam
        lastJob = 0,
    }

    local existing = DB.ActiveJobForWorker(cid)
    if existing then Jobs.Sessions[source].active = existing.job_ref end

    return Jobs.Sessions[source]
end

function Jobs.Detach(source)
    local session = Jobs.Sessions[source]
    if not session then return end
    if session.active then
        DB.ReleaseJob(session.active)
        TriggerClientEvent('grand_mechanic:client:JobCancelled', -1, session.active)
    end
    Jobs.Sessions[source] = nil
end

function Jobs.Session(source) return Jobs.Sessions[source] end
function Jobs.Get(source) return Jobs.Sessions[source] end

function Jobs.CanWork(jobName, kind)
    local allowed = Config.Jobs[kind]
    if not allowed then return false end
    for _, j in ipairs(allowed) do
        if j == jobName then return true end
    end
    return false
end

local function Throttle(source, key, seconds)
    local session = Jobs.Sessions[source]
    if not session then return true end
    local now = math.floor(os.time())
    local last = session.lastCall[key] or 0
    if now - last < (seconds or 2) then return false end
    session.lastCall[key] = now
    return true
end
Jobs.Throttle = Throttle

-- ─── Job board ────────────────────────────────────────────────
---@class MechanicJob
---@field ref string
---@field kind 'mechanic'|'tow'|'taxi'|'jack'
---@field status string
---@field vehicle string
---@field plate string
---@field model string
---@field coords vector3
---@field site string
---@field worker string|nil
---@field customer string|nil
---@field faults table

local Board = {}     -- [ref] = job
Jobs.Board = Board

function Jobs.Publish(job)
    Board[job.ref] = job
    DB.CreateJob(job)
    TriggerClientEvent('grand_mechanic:client:JobSync', -1, Jobs.Snapshot())
    return job
end

function Jobs.Remove(ref, status)
    local job = Board[ref]
    if not job then return false end
    Board[ref] = nil
    if status then DB.FailJob(ref, status) end
    TriggerClientEvent('grand_mechanic:client:JobSync', -1, Jobs.Snapshot())
    return true
end

function Jobs.Get(ref) return Board[ref] end

function Jobs.Snapshot()
    local out = {}
    for _, job in pairs(Board) do
        out[#out + 1] = {
            ref = job.ref, kind = job.kind, status = job.status, plate = job.plate,
            model = job.model, site = job.site, worker = job.worker, customer = job.customer,
            estimate = job.estimate, x = job.coords and job.coords.x or 0,
            y = job.coords and job.coords.y or 0, z = job.coords and job.coords.z or 0,
            created = job.created, faults = #job.faults,
        }
    end
    return out
end

function Jobs.ForKind(kind)
    local out = {}
    for _, job in pairs(Board) do
        if job.kind == kind then out[#out + 1] = job end
    end
    table.sort(out, function(a, b) return a.created > b.created end)
    return out
end

function Jobs.Create(source, kind, opts)
    local session = Jobs.Sessions[source]
    if not session then return nil, 'no-session' end
    if not Jobs.Throttle(source, 'create', 1) then return nil, 'slow-down' end

    opts = opts or {}
    local plate = Shared.NormalisePlate(opts.plate)
    if plate == '' then return nil, 'no-plate' end

    local job = {
        ref = Shared.Id(kind .. 'j'),
        kind = kind,
        status = 'open',
        vehicle = plate,
        plate = plate,
        model = opts.model or '',
        coords = opts.coords or GetEntityCoords(GetPlayerPed(source)),
        site = opts.site or '',
        worker = kind == 'jack' and session.cid or nil,
        customer = opts.customer or (kind == 'jack' and session.cid or nil),
        faults = opts.faults or {},
        estimate = math.floor(opts.estimate or 0),
        created = math.floor(os.time()),
        meta = opts.meta or {},
    }

    Jobs.Publish(job)
    return job
end

function Jobs.Claim(source, ref)
    local session = Jobs.Sessions[source]
    if not session then return false, 'no-session' end
    local job = Board[ref]
    if not job then return false, 'gone' end
    if job.status ~= 'open' then return false, 'taken' end

    if not Jobs.CanWork(session.job, job.kind) and job.kind ~= 'jack' then
        return false, 'not-your-job'
    end
    if session.active then return false, 'already-working' end

    if not DB.ClaimJob(ref, session.cid) then return false, 'lost-race' end

    session.active = ref
    job.status = 'active'
    job.worker = session.cid
    TriggerClientEvent('grand_mechanic:client:JobSync', -1, Jobs.Snapshot())
    TriggerClientEvent('grand_mechanic:client:Claimed', source, job)
    return true, job
end

function Jobs.Abandon(source)
    local session = Jobs.Sessions[source]
    if not session or not session.active then return false end
    local job = Board[session.active]
    DB.ReleaseJob(session.active)
    session.active = nil
    if job then
        job.status = 'open'
        job.worker = nil
        TriggerClientEvent('grand_mechanic:client:JobSync', -1, Jobs.Snapshot())
    end
    return true
end

--- Completion. `paid` decides whether the worker is owed anything.
function Jobs.Complete(source, ref, opts)
    opts = opts or {}
    local session = Jobs.Sessions[source]
    if not session then return false, 'no-session' end
    local job = Board[ref] or Board[session.active]
    if not job then return false, 'gone' end

    local payout = math.floor(opts.payout or job.estimate or 0)
    local split = Config.PaySplit[job.kind] or 0.75
    local crew = math.floor(payout * split)

    if crew > 0 then
        Pay(source, opts.wallet or 'cash', crew, job.kind .. ':' .. job.ref)
    end
    if opts.tip and opts.tip > 0 then
        Pay(source, 'cash', math.floor(opts.tip), 'tip')
    end

    Jobs.RegisterAction(source, job.kind, crew)

    Board[ref] = nil
    Board[job.ref] = nil
    DB.FinishJob(job.ref, payout)
    session.active = nil
    session.lastJob = math.floor(os.time())

    TriggerClientEvent('grand_mechanic:client:JobSync', -1, Jobs.Snapshot())
    TriggerClientEvent('grand_mechanic:client:Completed', source, {
        ref = job.ref, payout = crew, gross = payout, kind = job.kind, level = session.level,
    })

    return true, { crew = crew, gross = payout }
end

-- ─── NUI-less RPC used by the client layer ─────────────────────
RegisterNetEvent('grand_mechanic:server:Attach', function()
    local source = tonumber(source)
    if not source then return end
    local session = Jobs.Attach(source)
    if not session then return end
    TriggerClientEvent('grand_mechanic:client:Session', source, {
        cid = session.cid, job = session.job, xp = session.xp, level = session.level,
        active = session.active, outstanding = math.floor(DB.OutstandingTotal(session.cid)),
    })
    TriggerClientEvent('grand_mechanic:client:JobSync', source, Jobs.Snapshot())
end)

RegisterNetEvent('grand_mechanic:server:CreateJob', function(kind, payload)
    local source = tonumber(source)
    if not source then return end
    kind = tostring(kind or ''):lower()
    if not Shared.InList({ 'mechanic', 'tow', 'taxi', 'jack' }, kind) then return end

    if kind ~= 'jack' then
        local session = Jobs.Sessions[source]
        if not session then
            Jobs.Attach(source)
            session = Jobs.Sessions[source]
        end
        if not session or not Jobs.CanWork(session.job, kind) then
            return Notify(source, 'You are not on the clock for that work', 'error')
        end
    end

    local job, err = Jobs.Create(source, kind, payload)
    if not job then
        return Notify(source, ('Could not post the work order (%s)'):format(err or 'unknown'), 'error')
    end
    Notify(source, ('Work order %s posted'):format(job.ref:upper()), 'success')
end)

RegisterNetEvent('grand_mechanic:server:Claim', function(ref)
    local source = tonumber(source)
    if not source then return end
    local ok, result = Jobs.Claim(source, tostring(ref or ''))
    if not ok then Notify(source, ('Cannot take that job: %s'):format(result), 'error') end
end)

RegisterNetEvent('grand_mechanic:server:Abandon', function()
    local source = tonumber(source)
    if not source then return end
    if Jobs.Abandon(source) then Notify(source, 'Work order released', 'warning') end
end)

RegisterNetEvent('grand_mechanic:server:Complete', function(ref, opts)
    local source = tonumber(source)
    if not source then return end
    if not Jobs.Throttle(source, 'complete', 4) then return end
    Jobs.Complete(source, tostring(ref or ''), type(opts) == 'table' and opts or {})
end)

AddEventHandler('playerDropped', function()
    local source = tonumber(source)
    if source then Jobs.Detach(source) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Jobs.Sessions) do Jobs.Detach(src) end
end)

-- ─── Maintenance loop ─────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(60000)
        DB.SweepStaleJobs(1800)
        for _, job in pairs(Board) do
            if job.created < (math.floor(os.time() - 1800)) then Jobs.Remove(job.ref, 'expired') end
        end
        DB.ExpireInvoices()
    end
end)

exports('GetSession', function(source) return Jobs.Sessions[tonumber(source)] end)
exports('Snapshot', function() return Jobs.Snapshot() end)
exports('Claim', function(source, ref, kind) return Jobs.Claim(source, ref, kind) end)
exports('Complete', function(source, ref, opts) return Jobs.Complete(source, ref, opts) end)
exports('Pay', Pay)
exports('Take', Take)
exports('Notify', Notify)
exports('CitizenId', CitizenId)
exports('CanWork', Jobs.CanWork)
exports('Board', function(kind) return Jobs.ForKind(kind) end)

return Jobs
