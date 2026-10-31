-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/server/main.lua
--  Boot order, resource restart protection, console banner,
--  the exports listed in the spec (`GetCharacter`, `GetMoney`,
--  `AddMoney`, `RemoveMoney`, `Notify`), `grand_core:client:Notify`
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()
local Log = Util.Log

-- ─── Banner ──────────────────────────────────────────────────────

local function PrintBanner()
    print([[
^1╔══════════════════════════════════════════════════════════════════════╗
^1║ ^7Grand RP Core v2.0.0 – Framework‑agnostic character / economy     ^1║
^1║ ^7No qb‑core, no qbx, no esx. Running on oxmysql + ox_lib.           ^1║
^1╚══════════════════════════════════════════════════════════════════════╝
]])
end

-- ─── Schema bootstrap ────────────────────────────────────────────

local function LoadSchema()
    if not Config.Persistence.AutoCreateSchema then return true end

    local ok, schema = pcall(LoadResourceFile, RESOURCE, 'sql/schema.sql')
    if not ok or not schema then
        Log('warn', 'sql/schema.sql not found – run it manually against your database')
        return false
    end

    -- Split by statement
    for statement in (schema .. ';'):gmatch('([^;]-)%;') do
        if statement:find('CREATE') then
            local stmtOk = pcall(function()
                MySQL.query.await(statement)
            end)
            if not stmtOk then
                Log('error', ('Schema statement failed: %s'):format(statement:sub(1, 80)))
            end
        end
    end

    Log('info', 'Database schema verified')
    return true
end

-- ─── Notification shim (bridge to grand_admin) ────────────────────

local NotifyBridge = nil

--- Send a notification to a player.
---@param source number|string
---@param message string
---@param type? string  'success' | 'error' | 'warning' | 'info' | 'primary'
function Notify(source, message, type)
    if type(NotifyBridge) == 'function' then
        NotifyBridge(source, message, type)
        return
    end

    -- Fallback: direct client event
    TriggerClientEvent('grand_core:client:Notify', tonumber(source) or source, message, type or 'info')
end

--- Bridge to grand_admin's Notify function.
---@param bridge function
function SetNotifyBridge(bridge)
    NotifyBridge = bridge
end

-- ─── Player connection lifecycle ──────────────────────────────────

--- When a player connects, we wait for them to pick a character.
--- The actual session loading is triggered by grand_core:server:ClaimCharacter.
AddEventHandler('playerConnecting', function(name, _, deferrals)
    local source = tonumber(source)
    deferrals.defer()

    -- Give them time to load the UI
    Wait(1000)

    deferrals.done()
end)

--- When they drop, the session cleanup is handled in server/player.lua.
--- This handler just ensures the console logs something.
AddEventHandler('playerDropped', function()
    local source = tonumber(source)
    Log('debug', ('Player %d dropped'):format(source))
end)

--- Heartbeat from client to keep session alive.
RegisterNetEvent('grand_core:server:Heartbeat', function()
    local source = tonumber(source)
    -- No‑op; just a keepalive
end)

-- ─── Exports (spec‑mandated) ─────────────────────────────────────

--- GetCharacter(citizenid) -> table|nil
---@param citizenid string
---@return table|nil
function GetCharacter(citizenid)
    return GrandPlayer.GetCharacter(citizenid)
end

--- GetMoney(source) -> {cash,bank,crypto}
---@param source number|string
---@return table
function GetMoney(source)
    return GrandEconomy.GetMoney(source)
end

--- AddMoney(source, kind, amount) -> boolean
---@param source number|string
---@param kind string
---@param amount number|string
---@param reason? string
---@return boolean
function AddMoney(source, kind, amount, reason)
    return GrandEconomy.AddMoney(source, kind, amount, reason)
end

--- RemoveMoney(source, kind, amount) -> boolean
---@param source number|string
---@param kind string
---@param amount number|string
---@param reason? string
---@return boolean
function RemoveMoney(source, kind, amount, reason)
    return GrandEconomy.RemoveMoney(source, kind, amount, reason)
end

--- Notify(source, msg, type)
---@param source number|string
---@param message string
---@param type? string
function Notify(source, message, type)
    if type(NotifyBridge) == 'function' then
        NotifyBridge(source, message, type)
        return
    end
    TriggerClientEvent('grand_core:client:Notify', tonumber(source) or source, message, type or 'info')
end

--- Export the Notify bridge so grand_admin can hook it.
exports('Notify', Notify)

-- ─── Shorthand exports ──────────────────────────────────────────

exports('GetCharacter', GetCharacter)
exports('GetCharacters', function(identifier) return GrandPlayer.GetRows(identifier) end)
exports('CharacterExists', function(citizenid)
    local row = GrandPlayer.GetRowByCitizenId(citizenid)
    return row ~= nil
end)

exports('GetCharacterData', function(source) return GrandPlayer.GetCharacterData(source) end)
exports('GetSession', function(source) return GrandPlayer.Get(source) end)
exports('GetCitizenId', function(source)
    local session = GrandPlayer.Get(source)
    return session and session.citizenid or nil
end)
exports('MarkDirty', function(source) return GrandPlayer.Touch(source) end)

exports('SetJob', function(source, job, grade) return GrandJobs.SetJob(source, job, grade) end)
exports('SetGrade', function(source, grade) return GrandJobs.SetGrade(source, grade) end)
exports('ToggleDuty', function(source, force) return GrandJobs.ToggleDuty(source, force) end)
exports('IsOnDuty', function(source) return GrandJobs.IsOnDuty(source) end)
exports('GetJob', function(source) return GrandJobs.GetJob(source) end)
exports('GetSalary', function(jobName, grade) return GrandJobs.GetSalary(jobName, grade) end)
exports('GetJobList', function() return GrandJobs.GetJobList() end)
exports('GetJobDefinition', function(jobName) return GrandJobs.GetJobDefinition(jobName) end)
exports('GetJobGrades', function(jobName) return GrandJobs.GetJobGrades(jobName) end)
exports('GetFaction', function(source) return GrandJobs.GetFaction(source) end)
exports('IsGangMember', function(source) return GrandJobs.IsGangMember(source) end)

exports('GetMoney', GetMoney)
exports('AddMoney', AddMoney)
exports('RemoveMoney', RemoveMoney)
exports('TransferMoney', function(source, from, to, amount, reason)
    return GrandEconomy.TransferBucket(source, from, to, amount, reason)
end)
exports('PayPlayer', function(sender, receiver, amount, kind, reason)
    return GrandEconomy.PayPlayer(sender, receiver, amount, kind, reason)
end)
exports('SplitTax', function(amount) return GrandEconomy.SplitTax(amount) end)
exports('CalculateSalary', function(session) return GrandEconomy.CalculateSalary(session) end)

exports('LoadPlayer', function(source, citizenid) return GrandPlayer.Load(source, citizenid) end)
exports('SaveCharacter', function(source, reason) return GrandPlayer.Save(source, reason) end)
exports('SaveWallet', function(source) return GrandPlayer.SaveWallet(source) end)
exports('SetPosition', function(source, position) return GrandPlayer.SetPosition(source, position) end)
exports('SetVitals', function(source, vitals) return GrandPlayer.SetVitals(source, vitals) end)
exports('SetWallet', function(source, wallet) return GrandPlayer.SetWallet(source, wallet) end)
exports('UnloadPlayer', function(source) return GrandPlayer.Unload(source) end)
exports('OnlineCount', function() return GrandPlayer.OnlineCount() end)
exports('OnlineSessions', function() return GrandPlayer.OnlineSessions() end)
exports('GetSourceByCitizenId', function(citizenid) return GrandPlayer.GetSourceByCitizenId(citizenid) end)
exports('GetSourceByIdentifier', function(identifier) return GrandPlayer.GetSourceByIdentifier(identifier) end)
exports('GetIdentifier', function(source) return GrandPlayer.GetIdentifier(source) end)

exports('Notify', Notify)
exports('SetNotifyBridge', SetNotifyBridge)

-- ─── Resource start ──────────────────────────────────────────────

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end

    PrintBanner()

    -- Load database
    LoadSchema()

    -- Start autosave loops (player.lua)
    if true then
        -- loops are started inside player.lua
    end

    -- Start salary/interest loops (economy.lua)
    pcall(GrandEconomy.StartLoops)
    -- Start autosave loops (player.lua)
    pcall(GrandPlayer.StartLoops)

    -- Bridge to grand_admin's Notify (if available)
    if GetResourceState('grand_admin') == 'started' then
        local adminNotify = exports['grand_admin'].Notify
        if type(adminNotify) == 'function' then
            SetNotifyBridge(adminNotify)
            Log('info', 'Notification bridge connected to grand_admin')
        end
    end

    Log('info', 'Grand Core initialised')
end)

-- ─── Resource stop ───────────────────────────────────────────────

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    if Config.Persistence.SaveOnShutdown then
        local saved = 0
        for src, session in pairs(GrandPlayer.OnlineSessions()) do
            if session.dirty then
                local ok = pcall(GrandPlayer.Save, src, 'shutdown')
                if ok then saved = saved + 1 end
            end
        end
        Log('info', ('Shutdown: %d sessions saved'):format(saved))
    end

    Log('info', 'Grand Core stopped')
end)
