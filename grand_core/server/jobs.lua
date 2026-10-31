-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/server/jobs.lua
--  set job, grade promotion, on‑duty toggles, job list accessor exports,
--  salary lookup.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()

GrandJobs = {}

local JobState = {}
local GangState = {}
local OutfitState = {}

-- ─── Helpers ────────────────────────────────────────────────

---@param jobName string
---@return table|nil
local function GetJobDef(jobName)
    return Config.JobIndex[jobName or 'unemployed'] or nil
end

---@param jobName string
---@param grade number
---@return boolean
local function GradeExists(jobName, grade)
    local job = GetJobDef(jobName)
    if not job or not job.grades then return false end
    return job.grades[tostring(grade)] ~= nil
end

---@param jobName string
---@return number
local function DefaultGrade(jobName)
    local job = GetJobDef(jobName)
    if not job or not job.grades then return 0 end

    local lowest = math.huge
    for key in pairs(job.grades) do
        local num = tonumber(key)
        if num and num < lowest then lowest = num end
    end
    return lowest == math.huge and 0 or lowest
end

---@param jobName string
---@return boolean
local function CanBeOffDuty(jobName)
    local job = GetJobDef(jobName)
    return job and job.canBeOffDuty ~= false
end

---@param jobName string
---@return boolean
local function IsWhitelisted(jobName)
    local job = GetJobDef(jobName)
    return job and job.whitelisted == true
end

---@param jobName string
---@return boolean
local function IsGang(jobName)
    local job = GetJobDef(jobName)
    return job and job.gang == true
end

---@param source number
---@param jobName string
---@return boolean
local function MayTakeJob(source, jobName)
    if not IsWhitelisted(jobName) then return true end

    local allowed = false

    if Config.Whitelist.JobWhitelist.Enabled then
        local identifiers = GetPlayerIdentifiers(source)
        if not identifiers then return false end
        allowed = Util.IsWhitelisted(Util.GetLicenseIdentifier(identifiers), jobName)
    else
        allowed = IsPlayerAceAllowed(tostring(source), 'job.' .. jobName)
    end

    return allowed
end

-- ─── Set / get job ──────────────────────────────────────────

--- Sets a player's job and grade (updates session, database, broadcasts).
---@param source number
---@param jobName string
---@param grade? number
---@param silent? boolean
---@return boolean success, string error
function GrandJobs.SetJob(source, jobName, grade, silent)
    local session = GrandPlayer.Get(source)
    if not session then return false, 'no session' end

    if not GetJobDef(jobName) then
        return false, 'job does not exist'
    end

    if IsWhitelisted(jobName) and not MayTakeJob(source, jobName) then
        return false, 'not whitelisted for this job'
    end

    grade = grade or DefaultGrade(jobName)
    if not GradeExists(jobName, grade) then
        return false, 'invalid grade'
    end

    local oldJob   = session.job
    local oldGrade = session.jobGrade

    session.job     = jobName
    session.jobGrade = grade
    session.dirty   = true

    GrandPlayer.SaveJob(source, jobName, grade)

    JobState[source] = {
        job         = jobName,
        grade       = grade,
        onDuty      = JobState[source] and JobState[source].onDuty or false,
        lastChanged = os.time(),
    }

    local job = GetJobDef(jobName)
    if job and job.gang then
        GangState[source] = job.faction
    else
        GangState[source] = nil
    end

    if not silent then
        local label = job and job.label or Util.Humanize(jobName)
        TriggerClientEvent('grand_core:client:Notify', source,
            ('You are now a %s (Grade %d)'):format(label, grade), 'success')
    end

    TriggerClientEvent('grand_core:client:JobChanged', source, jobName, grade)
    TriggerEvent('grand_core:server:JobChanged', source, oldJob, oldGrade, jobName, grade)

    return true, ''
end

--- Changes grade inside the current job.
---@param source number
---@param newGrade number
---@param silent? boolean
---@return boolean success, string error
function GrandJobs.SetGrade(source, newGrade, silent)
    local session = GrandPlayer.Get(source)
    if not session then return false, 'no session' end

    local jobName = session.job
    if not GradeExists(jobName, newGrade) then
        return false, 'invalid grade'
    end

    local oldGrade = session.jobGrade
    session.jobGrade = newGrade
    session.dirty = true

    GrandPlayer.SaveJob(source, jobName, newGrade)

    if JobState[source] then
        JobState[source].grade = newGrade
        JobState[source].lastChanged = os.time()
    end

    if not silent then
        TriggerClientEvent('grand_core:client:Notify', source,
            ('Promoted to grade %d'):format(newGrade), 'success')
    end

    TriggerClientEvent('grand_core:client:GradeChanged', source, newGrade)
    TriggerEvent('grand_core:server:GradeChanged', source, oldGrade, newGrade)

    return true, ''
end

--- Toggles on‑duty status for jobs that allow it.
---@param source number
---@param force? boolean
---@return boolean success, boolean newState, string error
function GrandJobs.ToggleDuty(source, force)
    local session = GrandPlayer.Get(source)
    if not session then return false, false, 'no session' end

    local jobName = session.job
    if not CanBeOffDuty(jobName) then
        return false, false, 'job cannot be off duty'
    end

    local state = JobState[source] or { job = jobName, grade = session.jobGrade, onDuty = false }
    local newState = force
    if newState == nil then newState = not state.onDuty end

    state.onDuty = newState
    JobState[source] = state
    session.onDuty = newState
    session.dirty = true

    if newState then
        TriggerClientEvent('grand_core:client:Notify', source,
            Config.Notifications.DutyOn, 'success')
    else
        TriggerClientEvent('grand_core:client:Notify', source,
            Config.Notifications.DutyOff, 'info')
    end

    TriggerClientEvent('grand_core:client:DutyChanged', source, newState)
    TriggerEvent('grand_core:server:DutyChanged', source, newState)

    return true, newState, ''
end

--- Whether a player is on duty.
---@param source number
---@return boolean
function GrandJobs.IsOnDuty(source)
    local state = JobState[source]
    return state and state.onDuty == true
end

--- Full job info for a player.
---@param source number
---@return table|nil
function GrandJobs.GetJob(source)
    local session = GrandPlayer.Get(source)
    if not session then return nil end

    local jobName = session.job or 'unemployed'
    local job = GetJobDef(jobName) or {}
    local state = JobState[source] or { onDuty = false }

    return {
        job     = jobName,
        grade   = session.jobGrade,
        onDuty  = state.onDuty,
        label   = job.label or Util.Humanize(jobName),
        type    = job.type or 'legal',
        pay     = job.pay or Config.Salary.DefaultJobPay,
        gang    = job.gang or false,
        faction = job.faction,
        whitelisted = job.whitelisted or false,
        canBeOffDuty = job.canBeOffDuty ~= false,
    }
end

--- Get the job's faction (police, ems, ballas, etc.).
---@param source number
---@return string|nil
function GrandJobs.GetFaction(source)
    local job = GrandJobs.GetJob(source)
    return job and job.faction
end

--- Whether a player is in a gang.
---@param source number
---@return boolean
function GrandJobs.IsGangMember(source)
    local job = GrandJobs.GetJob(source)
    return job and job.gang == true
end

--- Salary lookup (exported).
---@param jobName string
---@param grade? number
---@return number
function GrandJobs.GetSalary(jobName, grade)
    grade = grade or 0
    local job = GetJobDef(jobName)
    if not job then return Config.Salary.DefaultJobPay end

    local pay = job.pay or Config.Salary.DefaultJobPay
    local gradeData = job.grades and job.grades[tostring(grade)]
    if gradeData and gradeData.multiplier then
        pay = math.floor(pay * gradeData.multiplier)
    end

    return pay
end

--- Full job list (exported).
---@return table
function GrandJobs.GetJobList()
    return Util.Copy(Config.Jobs)
end

--- Job definition.
---@param jobName string
---@return table|nil
function GrandJobs.GetJobDefinition(jobName)
    return Util.Copy(Config.JobIndex[jobName])
end

--- Grades for a job.
---@param jobName string
---@return table
function GrandJobs.GetJobGrades(jobName)
    local job = GetJobDef(jobName)
    if not job or not job.grades then return {} end

    local grades = {}
    for grade, data in pairs(job.grades) do
        grades[tonumber(grade) or 0] = Util.Copy(data)
    end
    return grades
end

-- ─── Net events ──────────────────────────────────────────────

RegisterNetEvent('grand_core:server:SetJob', function(jobName, grade)
    GrandJobs.SetJob(source, jobName, grade)
end)

RegisterNetEvent('grand_core:server:SetGrade', function(newGrade)
    GrandJobs.SetGrade(source, newGrade)
end)

RegisterNetEvent('grand_core:server:ToggleDuty', function(force)
    GrandJobs.ToggleDuty(source, force)
end)

-- ─── Admin command ──────────────────────────────────────────

RegisterCommand('setjob', function(executor, args)
    if not IsPlayerAceAllowed(tostring(executor), 'grand_core.admin') then
        TriggerClientEvent('grand_core:client:Notify', executor, 'Not allowed', 'error')
        return
    end

    if #args < 2 then
        TriggerClientEvent('grand_core:client:Notify', executor,
            'Usage: /setjob <target> <job> [grade]', 'error')
        return
    end

    local target = tonumber(args[1])
    local job = args[2]
    local grade = tonumber(args[3]) or 0

    if not target or not job then
        TriggerClientEvent('grand_core:client:Notify', executor, 'Invalid arguments', 'error')
        return
    end

    local ok, err = GrandJobs.SetJob(target, job, grade, true)
    if ok then
        TriggerClientEvent('grand_core:client:Notify', executor,
            ('Job set to %s grade %d'):format(job, grade), 'success')
    else
        TriggerClientEvent('grand_core:client:Notify', executor, 'Error: ' .. err, 'error')
    end
end, true)

-- ─── Exports ────────────────────────────────────────────────

exports('SetJob',               GrandJobs.SetJob)
exports('SetGrade',             GrandJobs.SetGrade)
exports('ToggleDuty',           GrandJobs.ToggleDuty)
exports('IsOnDuty',             GrandJobs.IsOnDuty)
exports('GetJob',               GrandJobs.GetJob)
exports('GetFaction',           GrandJobs.GetFaction)
exports('IsGangMember',         GrandJobs.IsGangMember)
exports('GetSalary',            GrandJobs.GetSalary)
exports('GetJobList',           GrandJobs.GetJobList)
exports('GetJobDefinition',     GrandJobs.GetJobDefinition)
exports('GetJobGrades',         GrandJobs.GetJobGrades)

-- ─── Callbacks ──────────────────────────────────────────────

lib.callback.register('grand_core:server:GetJobInfo', function(source)
    return GrandJobs.GetJob(source)
end)

lib.callback.register('grand_core:server:GetJobList', function()
    return GrandJobs.GetJobList()
end)

lib.callback.register('grand_core:server:GetJobGrades', function(_, jobName)
    return GrandJobs.GetJobGrades(jobName)
end)

_G.GrandJobs = GrandJobs