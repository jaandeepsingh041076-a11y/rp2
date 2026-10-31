-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/server/characters.lua
--  create/claim/delete character, citizenid generation,
--  first/last name validation, skin/outfit JSON persistence,
--  inventory JSON column persistence.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()
local Log = Util.Log

--- Create a brand new character row for a license.
---@param source number
---@param identifier string
---@param firstname string
---@param lastname string
---@return string|nil citizenid, string|nil error
function CreateCharacterForPlayer(source, identifier, firstname, lastname)
    source = tonumber(source)
    if not source or source == 0 then return nil, 'invalid source' end
    if not identifier or identifier == '' then return nil, 'no identifier' end

    local max = (Config.Logins and Config.Logins.MaxCharacters) or 4
    if GrandPlayer.CountFor(identifier) >= max then
        return nil, 'max characters reached'
    end

    local citizenid
    for _ = 1, 25 do
        local candidate = Util.GenerateCitizenId()
        local ok, count = pcall(function()
            return MySQL.scalar.await('SELECT COUNT(*) FROM characters WHERE citizenid = ?', { candidate })
        end)
        if ok and (tonumber(count) or 0) == 0 then
            citizenid = candidate
            break
        end
    end
    if not citizenid then return nil, 'could not generate a unique citizenid' end

    local starting = (Config.Money and Config.Money.Starting) or { cash = 5000, bank = 25000, crypto = 0 }
    local money = {
        cash   = starting.cash or 5000,
        bank   = starting.bank or 25000,
        crypto = starting.crypto or 0,
    }

    local ok, err = pcall(function()
        MySQL.insert.await([[
            INSERT INTO characters
            (citizenid, identifier, firstname, lastname, level, exp, money, job, job_grade,
             family_id, family_rank, position, inventory, skin, gender, phone_number, created_at, last_seen)
            VALUES (?, ?, ?, ?, 1, 0, ?, 'unemployed', 0, NULL, 0, '{}', '[]', '{}', 'm', '', NOW(), NOW())
        ]], { citizenid, identifier, firstname, lastname, Util.SerializeMoney(money) })
    end)

    if not ok then
        Log('error', ('CreateCharacterForPlayer failed: %s'):format(tostring(err)))
        return nil, 'database error'
    end

    return citizenid, nil
end
-- ─── Character creation ──────────────────────────────────────────

--- Create a new character and load it.
---@param source number
---@param identifier string
---@param firstname string
---@param lastname string
---@return boolean success, string citizenid, string error
local function CreateAndLoad(source, identifier, firstname, lastname)
    local citizenid, err = CreateCharacterForPlayer(source, identifier, firstname, lastname)
    if not citizenid then return false, '', err end

    -- Now that the row exists, load it
    local session, loadErr = GrandPlayer.Load(source)
    if not session then
        Log('error', ('Created but could not load %s: %s'):format(citizenid, tostring(loadErr)))
        return false, '', 'Load failed: ' .. tostring(loadErr)
    end

    -- Ensure the session has the right citizenid
    session.citizenid = citizenid

    return true, citizenid, ''
end

--- Event for UI character creation.
---@param firstname string
---@param lastname string
RegisterNetEvent('grand_core:server:CreateCharacter', function(firstname, lastname)
    local source = tonumber(source)
    if not source then return end

    -- Cooldown guard (global throttle)
    local now = os.time()
    local lastAttempt = GetPlayerLastCreateAttempt(source) or 0
    if now - lastAttempt < Config.Logins.CreateCooldown then
        TriggerClientEvent('grand_core:client:Notify', source, 'Please wait before creating another character', 'error')
        return
    end

    SetPlayerLastCreateAttempt(source, now)

    -- Get identifier
    local identifiers = GetPlayerIdentifiers(source)
    if not identifiers then
        TriggerClientEvent('grand_core:client:Notify', source, 'Could not identify your account', 'error')
        return
    end

    local identifier = Util.GetLicenseIdentifier(identifiers)
    if not identifier then
        TriggerClientEvent('grand_core:client:Notify', source, 'Could not retrieve your license', 'error')
        return
    end

    -- Already have a session?
    if GrandPlayer.Get(source) then
        TriggerClientEvent('grand_core:client:Notify', source, 'You already have a character loaded', 'error')
        return
    end

    -- Validate names
    local ok, reason, cleaned = Util.ValidateName(firstname)
    if not ok then
        TriggerClientEvent('grand_core:client:Notify', source, 'Invalid first name: ' .. reason, 'error')
        return
    end
    firstname = cleaned

    ok, reason, cleaned = Util.ValidateName(lastname)
    if not ok then
        TriggerClientEvent('grand_core:client:Notify', source, 'Invalid last name: ' .. reason, 'error')
        return
    end
    lastname = cleaned

    -- Create
    local success, citizenid, err = CreateAndLoad(source, identifier, firstname, lastname)
    if not success then
        TriggerClientEvent('grand_core:client:Notify', source, 'Failed to create character: ' .. err, 'error')
        return
    end

    -- Notify
    TriggerClientEvent('grand_core:client:Notify', source, 'Character created successfully', 'success')
    TriggerClientEvent('grand_core:client:CharacterCreated', source, citizenid, firstname, lastname)

    -- Broadcast to other resources
    TriggerEvent('grand_core:server:CharacterCreated', source, citizenid, firstname, lastname)

    Log('info', ('%s created character %s (%s %s)'):format(identifier, citizenid, firstname, lastname))
end)

--- Delete a character (admin action).
---@param citizenid string
---@param reason string
RegisterNetEvent('grand_core:server:DeleteCharacter', function(citizenid, reason)
    local source = tonumber(source)
    if not source then return end

    -- Permission check (caller must have admin rights or own the character)
    local session = GrandPlayer.Get(source)
    local isOwner = session and session.citizenid == citizenid
    local isAdmin = false  -- TODO: bridge to grand_admin

    if not isOwner and not isAdmin then
        TriggerClientEvent('grand_core:client:Notify', source, 'You cannot delete this character', 'error')
        return
    end

    local ok = DeletePlayerCharacter(source, citizenid, reason or 'player deleted')
    if ok then
        TriggerClientEvent('grand_core:client:Notify', source, 'Character deleted', 'success')
        Log('info', ('%s deleted character %s (%s)'):format(
            session and session.citizenid or 'unknown', citizenid, reason or ''))
    else
        TriggerClientEvent('grand_core:client:Notify', source, 'Failed to delete character', 'error')
    end
end)

--- Claim a character slot (select existing).
---@param citizenid string
RegisterNetEvent('grand_core:server:ClaimCharacter', function(citizenid)
    local source = tonumber(source)
    if not source then return end

    -- Already loaded?
    if GrandPlayer.Get(source) then
        TriggerClientEvent('grand_core:client:Notify', source, 'You already have a character loaded', 'error')
        return
    end

    -- Get identifier
    local identifiers = GetPlayerIdentifiers(source)
    if not identifiers then
        TriggerClientEvent('grand_core:client:Notify', source, 'Could not identify your account', 'error')
        return
    end

    local identifier = Util.GetLicenseIdentifier(identifiers)
    if not identifier then
        TriggerClientEvent('grand_core:client:Notify', source, 'Could not retrieve your license', 'error')
        return
    end

    -- Check ownership
    local ok, row = pcall(function()
        return MySQL.single.await(
            'SELECT identifier FROM characters WHERE citizenid = ? LIMIT 1',
            { citizenid }
        )
    end)

    if not ok or not row or not Util.IdentifierMatches(row.identifier, identifier) then
        TriggerClientEvent('grand_core:client:Notify', source, 'You do not own that character', 'error')
        return
    end

    -- Already in use?
    if GrandPlayer.GetSourceByCitizenId(citizenid) ~= nil then
        TriggerClientEvent('grand_core:client:Notify', source, 'Character is already in use', 'error')
        return
    end

    -- Load
    local session, err = GrandPlayer.Load(source)
    if not session then
        TriggerClientEvent('grand_core:client:Notify', source, 'Failed to load character: ' .. err, 'error')
        return
    end

    -- Success
    TriggerClientEvent('grand_core:client:Notify', source, 'Character loaded', 'success')
    TriggerClientEvent('grand_core:client:CharacterClaimed', source, citizenid)

    Log('info', ('%s claimed character %s'):format(identifier, citizenid))
end)

-- ─── Skin / outfit ──────────────────────────────────────────────

--- Save skin JSON.
---@param skin table
RegisterNetEvent('grand_core:server:SaveSkin', function(skin)
    local source = tonumber(source)
    local session = GrandPlayer.Get(source)
    if not session then return end

    session.skin = skin
    GrandPlayer.Touch(source)

    pcall(function()
        MySQL.update.await('UPDATE characters SET skin = ? WHERE citizenid = ?', {
            Util.EncodeJson(skin), session.citizenid
        })
    end)

    Log('debug', ('Skin saved for %s'):format(session.citizenid))
end)

--- Load skin JSON.
---@param citizenid string
---@return table|nil
local function LoadSkin(citizenid)
    local ok, row = pcall(function()
        return MySQL.single.await('SELECT skin FROM characters WHERE citizenid = ? LIMIT 1', { citizenid })
    end)
    if not ok or not row then return {} end
    return Util.ParseJson(row.skin, {})
end

--- Save outfit slug.
---@param outfit string
RegisterNetEvent('grand_core:server:SaveOutfit', function(outfit)
    local source = tonumber(source)
    local session = GrandPlayer.Get(source)
    if not session then return end

    session.outfit = outfit
    GrandPlayer.Touch(source)

    pcall(function()
        MySQL.insert.await([[
            INSERT INTO grand_outfits (citizenid, slug, display, components, props)
            VALUES (?, ?, ?, '[]', '[]')
            ON DUPLICATE KEY UPDATE slug = VALUES(slug)
        ]], { session.citizenid, outfit, outfit })
    end)

    Log('debug', ('Outfit %s saved for %s'):format(outfit, session.citizenid))
end)

--- Load outfit.
---@param citizenid string
---@param slug string
---@return table|nil
local function LoadOutfit(citizenid, slug)
    local ok, row = pcall(function()
        return MySQL.single.await(
            'SELECT slug, display, components, props FROM grand_outfits WHERE citizenid = ? AND slug = ? LIMIT 1',
            { citizenid, slug }
        )
    end)
    if not ok or not row then return nil end
    return row
end

-- ─── Inventory ──────────────────────────────────────────────────

--- Save inventory JSON (array of item slugs).
---@param inventory table
RegisterNetEvent('grand_core:server:SaveInventory', function(inventory)
    local source = tonumber(source)
    local session = GrandPlayer.Get(source)
    if not session then return end

    session.inventory = inventory
    GrandPlayer.Touch(source)

    pcall(function()
        MySQL.update.await('UPDATE characters SET inventory = ? WHERE citizenid = ?', {
            Util.EncodeJson(inventory), session.citizenid
        })
    end)

    Log('debug', ('Inventory saved for %s (%d items)'):format(session.citizenid, #inventory))
end)

--- Load inventory.
---@param citizenid string
---@return table
local function LoadInventory(citizenid)
    local ok, row = pcall(function()
        return MySQL.single.await('SELECT inventory FROM characters WHERE citizenid = ? LIMIT 1', { citizenid })
    end)
    if not ok or not row then return {} end
    return Util.ParseJson(row.inventory, {})
end

-- ─── Exports ────────────────────────────────────────────────────

--- Get a character by citizenid (from any session).
---@param citizenid string
---@return table|nil character data
function GetCharacter(citizenid)
    local ok, row = pcall(function()
        return MySQL.single.await([[
            SELECT citizenid, identifier, firstname, lastname, level, exp,
                   money, job, job_grade, family_id, family_rank,
                   position, inventory, skin, created_at
              FROM characters
             WHERE citizenid = ?
             LIMIT 1
        ]], { citizenid })
    end)

    if not ok or not row then return nil end

    -- Add live money if the player is online
    for _, session in pairs(GrandPlayer.OnlineSessions()) do
        if session.citizenid == citizenid then
            row.money = Util.SerializeMoney(session.money)
            break
        end
    end

    return row
end

--- Get all characters owned by an identifier.
---@param identifier string
---@return table
function GetCharacters(identifier)
    local ok, rows = pcall(function()
        return MySQL.query.await([[
            SELECT citizenid, firstname, lastname, level, job, job_grade,
                   money, created_at
              FROM characters
             WHERE identifier = ?
             ORDER BY created_at DESC
        ]], { identifier })
    end)

    if not ok or not rows then return {} end

    for _, row in ipairs(rows) do
        row.money = Util.ParseMoney(row.money)
    end

    return rows
end

--- Whether a character exists.
---@param citizenid string
---@return boolean
function CharacterExists(citizenid)
    local ok, count = pcall(function()
        return MySQL.scalar.await('SELECT COUNT(*) FROM characters WHERE citizenid = ?', { citizenid }) or 0
    end)
    return ok and count > 0
end

-- ─── Cooldown tracking (global) ─────────────────────────────────

local CreateAttempts = {}

function GetPlayerLastCreateAttempt(source)
    return CreateAttempts[source]
end

function SetPlayerLastCreateAttempt(source, timestamp)
    CreateAttempts[source] = timestamp
end

-- ─── Module exports ─────────────────────────────────────────────

exports('GetCharacter', GetCharacter)
exports('GetCharacters', GetCharacters)
exports('CharacterExists', CharacterExists)

-- ─── Event‑based callbacks ──────────────────────────────────────

lib.callback.register('grand_core:server:GetCharacterList', function(source)
    local identifiers = GetPlayerIdentifiers(source)
    local identifier = identifiers and Util.GetLicenseIdentifier(identifiers)
    if not identifier then return {} end

    return GetCharacters(identifier)
end)

lib.callback.register('grand_core:server:CreateCharacter', function(source, firstname, lastname)
    local identifiers = GetPlayerIdentifiers(source)
    local identifier = identifiers and Util.GetLicenseIdentifier(identifiers)
    if not identifier then return false, 'No identifier' end

    local ok, citizenid, err = CreateAndLoad(source, identifier, firstname, lastname)
    return ok, ok and citizenid or err
end)