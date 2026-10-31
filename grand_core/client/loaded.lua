-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/client/loaded.lua
--  First‑tick player loaded event `grand_core:client:PlayerLoaded`,
--  sets `CurrentUser` global table for other resources,
--  exports `CurrentUser()`.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()
local Log = Util.Log

-- ─── Global state ────────────────────────────────────────────────
--   CurrentUser = {
--       source      = source,
--       citizenid   = 'ABC12345',
--       firstname   = 'John',
--       lastname    = 'Doe',
--       job         = 'unemployed',
--       jobGrade    = 0,
--       familyId    = 0,
--       familyRank  = 0,
--       money       = { cash, bank, crypto },
--       license     = 'license:xxxx',
--       loadedAt    = os.time(),
--   }
-- ─────────────────────────────────────────────────────────────

CurrentUser = nil
local Loaded = false

-- ─── Loading flow ────────────────────────────────────────────────

--- Request the server to send us our character data.
local function RequestLoad()
    local start = GetGameTimer()

    lib.callback('grand_core:server:GetCharacterData', 10000, function(data)
        if not data then
            Log('error', 'Failed to load character data')
            return
        end

        -- Build global state
        local identifiers = GetPlayerIdentifiers(PlayerId())
        CurrentUser = {
            source     = GetPlayerServerId(PlayerId()),
            citizenid  = data.citizenid,
            firstname  = data.firstname,
            lastname   = data.lastname,
            job        = data.job,
            jobGrade    = tonumber(data.job_grade) or 0,
            familyId    = tonumber(data.family_id) or 0,
            familyRank  = tonumber(data.family_rank) or 0,
            money       = Util.ParseMoney(data.money),
            license     = Util.GetLicenseIdentifier(identifiers) or '',
            loadedAt    = os.time(),
        }

        Loaded = true

        -- Fire the loaded event
        TriggerEvent('grand_core:client:PlayerLoaded',
            CurrentUser.citizenid,
            CurrentUser.firstname,
            CurrentUser.lastname,
            CurrentUser.job,
            CurrentUser.money
        )

        -- Notify other resources
        TriggerEvent('grand_core:client:CurrentUserReady', CurrentUser)

        Log('info', ('Loaded %s %s (%s) in %d ms'):format(
            CurrentUser.firstname,
            CurrentUser.lastname,
            CurrentUser.citizenid,
            GetGameTimer() - start
        ))
    end, GetPlayerServerId(PlayerId()))
end

--- Wait for the player to be ready, then load.
Citizen.CreateThread(function()
    while true do
        Wait(1000)

        if NetworkIsPlayerActive(PlayerId()) and not Loaded then
            -- Wait a tick for other resources
            Wait(500)

            RequestLoad()
            break
        end
    end
end)

-- ─── Exports ─────────────────────────────────────────────────────

--- Returns the CurrentUser table.
---@return table|nil
function GetCurrentUser()
    return CurrentUser
end

--- Whether the player is fully loaded.
---@return boolean
function IsPlayerLoaded()
    return Loaded == true
end

--- Get the player's citizenid.
---@return string|nil
function GetCitizenId()
    return CurrentUser and CurrentUser.citizenid
end

--- Get the player's job.
---@return string|nil
function GetJob()
    return CurrentUser and CurrentUser.job
end

--- Get the player's money bucket.
---@param kind string
---@return number
function GetMoney(kind)
    if not CurrentUser or not CurrentUser.money then return 0 end
    return Util.Floor(CurrentUser.money[kind])
end

exports('CurrentUser', GetCurrentUser)
exports('GetCurrentUser', GetCurrentUser)
exports('IsPlayerLoaded', IsPlayerLoaded)
exports('GetCitizenId', GetCitizenId)
exports('GetJob', GetJob)
exports('GetMoney', GetMoney)

-- ─── Events ──────────────────────────────────────────────────────

--- Re‑request data from server (used after character creation).
RegisterNetEvent('grand_core:client:CharacterCreated', function(citizenid, firstname, lastname)
    Loaded = false
    CurrentUser = nil
    Wait(1000)
    RequestLoad()
end)

--- Refresh money.
---@param wallet table
RegisterNetEvent('grand_core:client:MoneyUpdated', function(wallet)
    if CurrentUser then
        CurrentUser.money = wallet
    end
end)

--- Refresh job.
---@param job string
---@param grade number
RegisterNetEvent('grand_core:client:JobChanged', function(job, grade)
    if CurrentUser then
        CurrentUser.job = job
        CurrentUser.jobGrade = grade
    end
end)

--- Refresh vitals (called by HUD).
---@param hunger number
---@param thirst number
---@param stress number
RegisterNetEvent('grand_core:client:SetVitals', function(hunger, thirst, stress)
    if CurrentUser then
        CurrentUser.hunger = hunger
        CurrentUser.thirst = thirst
        CurrentUser.stress = stress
    end
end)

--- Server‑initiated reload (admin).
RegisterNetEvent('grand_core:client:ReloadUser', function()
    Loaded = false
    CurrentUser = nil
    Wait(500)
    RequestLoad()
end)