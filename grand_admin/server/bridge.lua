-- resources/[grand_systems]/grand_admin/server/bridge.lua
-- Framework bridge.
--
-- This server has no qb-core/qbx installation, so the admin panel reads its
-- player data from the Grand RP schema (users + characters) plus FiveM natives.
-- Every accessor is nil-safe and cached for the lifetime of a session so the
-- panel can poll without hammering the database.

local Bridge = {}

--- source -> cached character row
local CharacterCache = {}

local RESOURCE = GetCurrentResourceName()

local function Warn(msg)
    print(('^3[%s]^7 %s'):format(RESOURCE, msg))
end

local function Query(label, fn)
    local ok, result = pcall(fn)
    if not ok then
        Warn(('[%s] %s'):format(label, tostring(result)))
        return nil
    end
    return result
end

-- --------------------------------------------------------------------------
-- Identity
-- --------------------------------------------------------------------------

--- The stable identifier we key characters on.
---@param source number
---@return string|nil
function Bridge.GetIdentifier(source)
    if source == 0 then return nil end

    if GetPlayerIdentifierByType then
        return Query('GetPlayerIdentifierByType', function()
            return GetPlayerIdentifierByType(source, 'license')
        end)
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(source) or {}) do
        if identifier:find('license:') == 1 then
            return identifier
        end
    end

    return nil
end

---@param source number
---@return string
function Bridge.GetName(source)
    if source == 0 then return 'Console' end
    return GetPlayerName(source) or ('Player ' .. tostring(source))
end

-- --------------------------------------------------------------------------
-- Characters
-- --------------------------------------------------------------------------

--- Loads (and caches) the character row for a connected player.
---@param source number
---@return table|nil
function Bridge.GetCharacter(source)
    if CharacterCache[source] then
        return CharacterCache[source]
    end

    local identifier = Bridge.GetIdentifier(source)
    if not identifier then return nil end

    local row = Query('GetCharacter', function()
        return MySQL.single.await([[
            SELECT citizenid, identifier, firstname, lastname, level, exp,
                   job, job_grade, family_id, family_rank, money
            FROM characters
            WHERE identifier = ?
            LIMIT 1
        ]], { identifier })
    end)

    if row then
        CharacterCache[source] = row
    end

    return row
end

function Bridge.ClearCache(source)
    CharacterCache[source] = nil
end

---@param source number
---@return string
function Bridge.GetDisplayName(source)
    local character = Bridge.GetCharacter(source)
    if character and character.firstname and character.lastname then
        return ('%s %s'):format(character.firstname, character.lastname)
    end
    return Bridge.GetName(source)
end

---@param source number
---@return string citizenid or ''
function Bridge.GetCitizenId(source)
    local character = Bridge.GetCharacter(source)
    return character and character.citizenid or ''
end

---@param source number
---@return string job name
function Bridge.GetJob(source)
    local character = Bridge.GetCharacter(source)
    return (character and character.job) or 'unemployed'
end

---@param source number
---@return number level
function Bridge.GetLevel(source)
    local character = Bridge.GetCharacter(source)
    return math.max(1, math.floor(tonumber(character and character.level) or 1))
end

---@param source number
---@return number cash, number bank
function Bridge.GetMoney(source)
    local character = Bridge.GetCharacter(source)
    if not character or not character.money then return 0, 0 end

    local decoded = Query('DecodeMoney', function()
        return json.decode(character.money)
    end)

    if type(decoded) ~= 'table' then return 0, 0 end
    return math.floor(tonumber(decoded.cash) or 0), math.floor(tonumber(decoded.bank) or 0)
end

-- --------------------------------------------------------------------------
-- Ranks / permissions
-- --------------------------------------------------------------------------

--- Groups configured in server.cfg, e.g. add_principal identifier.fivem:1 group.admin
---@param source number
---@param groups table<string>
---@return boolean
function Bridge.InGroup(source, groups)
    if source == 0 then return true end

    for _, group in ipairs(groups or {}) do
        if IsPlayerAceAllowed(tostring(source), 'group.' .. group) then
            return true
        end
    end

    return false
end

--- Whether a source is online right now.
---@param target number|string
---@return number|nil resolved source
function Bridge.ResolveTarget(target)
    local id = tonumber(target)
    if not id then return nil end
    if not GetPlayerPed(id) or GetPlayerPed(id) == 0 then return nil end
    return id
end

-- --------------------------------------------------------------------------
-- Listing
-- --------------------------------------------------------------------------

--- Full roster for the player-management table.
---@return table
function Bridge.GetRoster()
    local roster = {}

    for _, rawId in ipairs(GetPlayers()) do
        local id = tonumber(rawId)
        if id then
            local cash, bank = Bridge.GetMoney(id)
            local character = Bridge.GetCharacter(id)

            roster[#roster + 1] = {
                source    = id,
                name      = Bridge.GetDisplayName(id),
                account   = Bridge.GetName(id),
                citizenid = character and character.citizenid or '',
                job       = Bridge.GetJob(id),
                grade     = tonumber(character and character.job_grade) or 0,
                level     = Bridge.GetLevel(id),
                cash      = cash,
                bank      = bank,
                ping      = GetPlayerPing(id) or 0,
                ip        = (GetPlayerEndpoint(id) or ''):match('^(.-):') or GetPlayerEndpoint(id) or '',
                identifiers = GetPlayerIdentifiers(id) or {},
                family    = tonumber(character and character.family_id) or 0,
                familyRank = tonumber(character and character.family_rank) or 0,
            }
        end
    end

    table.sort(roster, function(a, b) return a.source < b.source end)
    return roster
end

-- --------------------------------------------------------------------------
-- Persistence helpers used by moderation + spawning
-- --------------------------------------------------------------------------

--- Writes a spawned vehicle into the Grand RP garage table.
---@param citizenid string
---@param model string
---@param plate string
---@return boolean
function Bridge.RecordVehicle(citizenid, model, plate)
    if not citizenid or citizenid == '' then return false end

    local ok = Query('RecordVehicle', function()
        MySQL.insert.await([[
            INSERT INTO grand_vehicles (citizenid, plate, model, props, garage, state, fuel)
            VALUES (?, ?, ?, '{}', 'Legion_Square', 0, 100)
            ON DUPLICATE KEY UPDATE model = VALUES(model), state = 0
        ]], { citizenid, plate, model })
    end)

    return ok ~= nil
end

--- Whether a plate is already taken in the garage.
---@param plate string
---@return boolean
function Bridge.IsPlateTaken(plate)
    local row = Query('IsPlateTaken', function()
        return MySQL.single.await('SELECT id FROM grand_vehicles WHERE plate = ? LIMIT 1', { plate })
    end)
    return row ~= nil and row ~= false
end

-- --------------------------------------------------------------------------
-- Session lifecycle
-- --------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    Bridge.ClearCache(tonumber(source))
end)

AddEventHandler('playerJoined', function()
    -- A relog must not reuse a stale character row.
    Bridge.ClearCache(tonumber(source))
end)

_G.GrandBridge = Bridge
