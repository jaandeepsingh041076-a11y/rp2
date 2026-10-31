-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/server/player.lua
--  Session table keyed by `source`. Loads a character from the DB on
--  connect, saves on drop + on an interval autosave, and is offline
--  safe: every accessor returns nil / false instead of throwing.
--
--  All schema access goes through the DB facade below, which only uses
--  MySQL.single.fetch / MySQL.scalar / MySQL.inStatement / MySQL.insert /
--  MySQL.update (`.await` variants) with `?` placeholders. User input is
--  never concatenated into SQL.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()

GrandPlayer = {}

--- source -> session table
---@type table<number, table>
local Sessions = {}

--- source -> { key = string, tick = number }  (anti double-spend)
---@type table<number, table>
local DuplicateGuard = {}

--- license identifier -> source
---@type table<string, number>
local ActiveByLicense = {}

-- ─── DB facade ────────────────────────────────────────────

local DB = {}

--- SELECT one row (nil when missing or on error).
---@param label string
---@param query string
---@param params? table
---@return table|nil
function DB.Row(label, query, params)
    local ok, result = pcall(MySQL.single.fetch.await, query, params or {})
    if not ok then
        Util.Log('error', ('[%s] %s'):format(label, tostring(result)))
        return nil
    end
    if type(result) ~= 'table' then return nil end
    return result
end

--- SELECT a list of rows without leaving the documented accessor set.
--- The character roster is bounded by Config.Identity.MaxCharacters, so we
--- read the id list in one scalar pass and fetch each row individually.
---@param label string
---@param ids string        query returning one comma-separated id list
---@param perRow string     query taking one id and returning one row
---@param params table
---@return table
function DB.Rows(label, ids, perRow, params)
    local idList = DB.Scalar(label .. ':ids', ids, params)
    if type(idList) ~= 'string' or idList == '' then return {} end

    local list = {}
    for token in idList:gmatch('%d+') do
        local row = DB.Row(label .. ':row', perRow, { tonumber(token) })
        if row then list[#list + 1] = row end
    end
    return list
end

--- SELECT a single value.
---@param label string
---@param query string
---@param params? table
---@return any
function DB.Scalar(label, query, params)
    local ok, result = pcall(MySQL.scalar.await, query, params or {})
    if not ok then
        Util.Log('error', ('[%s] %s'):format(label, tostring(result)))
        return nil
    end
    return result
end

--- INSERT, returns the insert id (0 on failure).
---@param label string
---@param query string
---@param params? table
---@return number
function DB.Insert(label, query, params)
    local ok, result = pcall(MySQL.insert.await, query, params or {})
    if not ok then
        Util.Log('error', ('[%s] %s'):format(label, tostring(result)))
        return 0
    end
    return tonumber(result) or 0
end

--- INSERT with one parameter set per row (job history / audit bursts).
---@param label string
---@param query string
---@param paramSets table
---@return boolean
function DB.InStatement(label, query, paramSets)
    if type(paramSets) ~= 'table' or #paramSets == 0 then return true end

    local ok, result = pcall(MySQL.inStatement.await, query, paramSets)
    if not ok then
        Util.Log('error', ('[%s] %s'):format(label, tostring(result)))
        return false
    end
    return result ~= false
end

--- UPDATE / DELETE / DDL, returns affected rows (-1 on failure).
---@param label string
---@param query string
---@param params? table
---@return number
function DB.Update(label, query, params)
    local ok, result = pcall(MySQL.update.await, query, params or {})
    if not ok then
        Util.Log('error', ('[%s] %s'):format(label, tostring(result)))
        return -1
    end
    return tonumber(result) or 0
end

GrandPlayer.DB = DB

-- ─── Queries ──────────────────────────────────────────────

local SELECT_BY_IDENTIFIER_IDS = [[
    SELECT GROUP_CONCAT(id ORDER BY id ASC) FROM characters WHERE identifier = ?
]]

local SELECT_BY_ID = [[
    SELECT citizenid, identifier, firstname, lastname, level, exp, money,
           job, job_grade, family_id, family_rank, position, inventory,
           skin, gender, phone_number, created_at, last_seen
      FROM characters
     WHERE id = ?
     LIMIT 1
]]

local SELECT_BY_CITIZENID = [[
    SELECT citizenid, identifier, firstname, lastname, level, exp, money,
           job, job_grade, family_id, family_rank, position, inventory,
           skin, gender, phone_number, created_at, last_seen
      FROM characters
     WHERE citizenid = ?
     LIMIT 1
]]

-- ─── Identity ─────────────────────────────────────────────

--- The stable identifier characters are keyed on.
---@param source number
---@return string|nil
function GrandPlayer.GetIdentifier(source)
    source = tonumber(source)
    if not source or source == 0 then return nil end

    if GetPlayerIdentifierByType then
        local ok, license = pcall(GetPlayerIdentifierByType, source, 'license')
        if ok and license then return license end
    end

    local ok, identifiers = pcall(GetPlayerIdentifiers, source)
    if not ok or type(identifiers) ~= 'table' then return nil end

    return Util.GetLicenseIdentifier(identifiers)
end

-- ─── Session shape ────────────────────────────────────────

---@param raw string|table|nil
---@return table
local function NormaliseWallet(raw)
    local caps = Config.Money.Caps or {}
    local wallet = Util.ParseMoney(raw)

    return {
        cash   = Util.Clamp(wallet.cash,   0, caps.cash   or 50000),
        bank   = Util.Clamp(wallet.bank,   0, caps.bank   or 2500000),
        crypto = Util.Clamp(wallet.crypto, 0, caps.crypto or 1000000),
    }
end

---@param raw string|table|nil
---@return table
local function NormalisePosition(raw)
    local parsed = Util.ParseJson(raw, {})

    if type(parsed) ~= 'table' or tonumber(parsed.x) == nil then
        local spawn = Config.Positions and Config.Positions.Spawn and Config.Positions.Spawn[1]
        return { x = spawn and spawn.x or -1037.0, y = spawn and spawn.y or -2737.0, z = spawn and spawn.z or 20.16, heading = spawn and spawn.heading or 335.0 }
    end

    return {
        x       = tonumber(parsed.x) or 0.0,
        y       = tonumber(parsed.y) or 0.0,
        z       = tonumber(parsed.z) or 0.0,
        heading = tonumber(parsed.heading) or 0.0,
    }
end

---@param raw string|table|nil
---@return table
local function NormaliseList(raw)
    local parsed = Util.ParseJson(raw, {})
    if type(parsed) ~= 'table' then return {} end
    return parsed
end

--- Builds the live session table from a DB row.
---@param source number
---@param row table
---@return table
local function BuildSession(source, row)
    return {
        source       = source,
        license      = row.identifier,
        citizenid    = row.citizenid,
        firstname    = row.firstname or 'Unknown',
        lastname     = row.lastname or 'Citizen',
        fullname     = ('%s %s'):format(row.firstname or 'Unknown', row.lastname or 'Citizen'),
        gender       = (row.gender == nil) and 'm' or tostring(row.gender),
        phone        = row.phone_number or '',
        level        = Util.Clamp(row.level, 1, Config.Progress.MaxLevel),
        exp          = Util.Floor(row.exp),
        money        = NormaliseWallet(row.money),
        job          = (row.job and row.job ~= '') and row.job or 'unemployed',
        jobGrade     = Util.Clamp(row.job_grade, 0, 20),
        onDuty       = false,
        familyId     = Util.Floor(row.family_id),
        familyRank   = Util.Floor(row.family_rank),
        position     = NormalisePosition(row.position),
        inventory    = NormaliseList(row.inventory),
        skin         = NormaliseList(row.skin),
        outfit       = nil,
        vitals       = { hunger = 100.0, thirst = 100.0, stress = 0.0 },
        ped          = 0,
        createdAt    = row.created_at,
        loadTime     = os.time(),
        lastSaved    = os.time(),
        lastActivity = os.time(),
        dirty        = true,
        saving       = false,
    }
end

-- ─── Lookup ───────────────────────────────────────────────

--- Every character owned by an identifier (roster screen).
---@param identifier string
---@return table
function GrandPlayer.GetRows(identifier)
    if not identifier then return {} end

    local rows = DB.Rows('GetRows', SELECT_BY_IDENTIFIER_IDS, SELECT_BY_ID, { identifier })
    local list = {}

    for i = 1, #rows do
        local row = rows[i]
        row.wallet = NormaliseWallet(row.money)
        list[#list + 1] = row
    end

    return list
end

--- How many characters a license owns.
---@param identifier string
---@return number
function GrandPlayer.CountFor(identifier)
    if not identifier then return 0 end

    local count = DB.Scalar('CountFor',
        'SELECT COUNT(*) FROM characters WHERE identifier = ?', { identifier })
    return math.max(0, Util.Floor(count))
end

---@param citizenid string
---@return table|nil
function GrandPlayer.GetRowByCitizenId(citizenid)
    if not citizenid or citizenid == '' then return nil end
    return DB.Row('GetRowByCitizenId', SELECT_BY_CITIZENID, { citizenid })
end

-- ─── Load / unload ────────────────────────────────────────

--- Loads (or re-attaches) a character for a connected source.
---@param source number
---@param citizenid? string  nil = first character owned by the license
---@return table|nil session, string error
function GrandPlayer.Load(source, citizenid)
    source = tonumber(source)
    if not source or source == 0 then return nil, 'invalid source' end

    if Sessions[source] then return Sessions[source], '' end

    local identifier = GrandPlayer.GetIdentifier(source)
    if not identifier then
        return nil, 'could not resolve a license identifier'
    end

    if not Util.IsWhitelisted(identifier) then
        return nil, Config.Logins.KickWhitelist
    end

    local row
    if citizenid and citizenid ~= '' then
        row = GrandPlayer.GetRowByCitizenId(citizenid)

        if row and not Util.IdentifierMatches(row.identifier, identifier) then
            Util.Log('warn', ('%s tried to load foreign character %s'):format(identifier, tostring(citizenid)))
            return nil, 'that character is not yours'
        end
    else
        local rows = GrandPlayer.GetRows(identifier)
        row = rows[1]
    end

    if type(row) ~= 'table' or not row.citizenid then
        return nil, 'no character'
    end

    -- One citizenid, one session — never two.
    local holder = GrandPlayer.GetSourceByCitizenId(row.citizenid)
    if holder and holder ~= source then
        return nil, Config.Logins.KickDuplicate
    end

    local session = BuildSession(source, row)
    Sessions[source] = session
    ActiveByLicense[session.license] = source

    GrandPlayer.OpenSessionLog(source)
    GrandPlayer.Touch(source)

    Util.Log('info', ('%s <%s> session opened'):format(session.fullname, session.citizenid))
    return session, ''
end

--- Drops a session without saving (used by the relog guard).
---@param source number
function GrandPlayer.Unload(source)
    source = tonumber(source)
    if not source then return end

    local session = Sessions[source]
    if session and session.license then
        ActiveByLicense[session.license] = nil
    end

    Sessions[source] = nil
    DuplicateGuard[source] = nil
end

-- ─── Accessors ────────────────────────────────────────────

---@param source any
---@return table|nil
function GrandPlayer.Get(source)
    return Sessions[tonumber(source) or source]
end

---@param citizenid string
---@return number|nil
function GrandPlayer.GetSourceByCitizenId(citizenid)
    if not citizenid then return nil end

    for source, session in pairs(Sessions) do
        if session.citizenid == citizenid then return source end
    end
    return nil
end

---@param identifier string
---@return number|nil
function GrandPlayer.GetSourceByIdentifier(identifier)
    if not identifier or identifier == '' then return nil end
    return ActiveByLicense[identifier]
end

--- Offline-safe character read: live session first, DB second.
---@param citizenid string
---@return table|nil
function GrandPlayer.GetCharacter(citizenid)
    if not citizenid then return nil end

    local source = GrandPlayer.GetSourceByCitizenId(citizenid)
    if source then
        local data = GrandPlayer.ExportCharacter(Sessions[source])
        data.online = true
        return data
    end

    local row = GrandPlayer.GetRowByCitizenId(citizenid)
    if not row then return nil end

    row.wallet = NormaliseWallet(row.money)
    row.money = Util.ParseMoney(row.money)
    row.online = false
    return row
end

--- Flat copy for exports / NUI / other resources.
---@param session table|nil
---@return table|nil
function GrandPlayer.ExportCharacter(session)
    if not session then return nil end

    local wallet = session.money or Util.EmptyMoney()
    return {
        source      = session.source,
        citizenid   = session.citizenid,
        identifier  = session.license,
        firstname   = session.firstname,
        lastname    = session.lastname,
        fullname    = session.fullname,
        gender      = session.gender,
        phone       = session.phone,
        level       = session.level,
        exp         = session.exp,
        cash        = wallet.cash,
        bank        = wallet.bank,
        crypto      = wallet.crypto,
        money       = { cash = wallet.cash, bank = wallet.bank, crypto = wallet.crypto },
        job         = session.job,
        job_grade   = session.jobGrade,
        onDuty      = session.onDuty == true,
        family_id   = session.familyId,
        family_rank = session.familyRank,
        position    = session.position,
        inventory   = session.inventory,
        skin        = session.skin,
        outfit      = session.outfit,
        vitals      = session.vitals,
    }
end

---@param source any
---@return table|nil
function GrandPlayer.GetCharacterData(source)
    return GrandPlayer.ExportCharacter(GrandPlayer.Get(source))
end

---@return number
function GrandPlayer.OnlineCount()
    local count = 0
    for _ in pairs(Sessions) do count = count + 1 end
    return count
end

---@return table
function GrandPlayer.OnlineSessions()
    return Sessions
end

-- ─── Mutators ─────────────────────────────────────────────

---@param source number
---@param wallet table
---@return boolean
function GrandPlayer.SetWallet(source, wallet)
    local session = GrandPlayer.Get(source)
    if not session or type(wallet) ~= 'table' then return false end

    session.money = NormaliseWallet(wallet)
    session.dirty = true
    return true
end

---@param source number
---@param position table
---@return boolean
function GrandPlayer.SetPosition(source, position)
    local session = GrandPlayer.Get(source)
    if not session or type(position) ~= 'table' then return false end

    session.position = {
        x       = tonumber(position.x) or session.position.x,
        y       = tonumber(position.y) or session.position.y,
        z       = tonumber(position.z) or session.position.z,
        heading = tonumber(position.heading) or session.position.heading,
    }
    session.dirty = true
    return true
end

---@param source number
---@param vitals table
---@return boolean
function GrandPlayer.SetVitals(source, vitals)
    local session = GrandPlayer.Get(source)
    if not session or type(vitals) ~= 'table' then return false end

    session.vitals = {
        hunger = Util.Clamp(vitals.hunger, 0, 100),
        thirst = Util.Clamp(vitals.thirst, 0, 100),
        stress = Util.Clamp(vitals.stress, 0, 100),
    }
    session.dirty = true
    return true
end

---@param source number
---@param level number
---@param exp number
---@return boolean
function GrandPlayer.SetProgress(source, level, exp)
    local session = GrandPlayer.Get(source)
    if not session then return false end

    session.level = Util.Clamp(level, 1, Config.Progress.MaxLevel)
    session.exp = math.max(0, Util.Floor(exp))
    session.dirty = true
    return true
end

--- Marks the session active and caches the ped handle.
---@param source number
function GrandPlayer.Touch(source)
    local session = GrandPlayer.Get(source)
    if not session then return end

    session.lastActivity = os.time()

    local ok, ped = pcall(GetPlayerPed, source)
    if ok and ped and ped > 0 then session.ped = ped end
end

--- Snapshot a session's current ped transform (used on drop / autosave).
---@param session table
---@return boolean
function GrandPlayer.CapturePed(session)
    if not session then return false end

    local ok, ped = pcall(GetPlayerPed, session.source)
    if not ok or not ped or ped == 0 then return false end

    local okCoords, coords = pcall(GetEntityCoords, ped)
    if not okCoords or type(coords) ~= 'table' then return false end

    local okHeading, heading = pcall(GetEntityHeading, ped)
    session.position = {
        x       = coords.x,
        y       = coords.y,
        z       = coords.z,
        heading = (okHeading and tonumber(heading)) or session.position.heading,
    }
    session.ped = ped
    return true
end

-- ─── Duplicate-transaction guard ──────────────────────────

---@param source number
---@param key string
---@param windowSeconds number
---@return boolean blocked
function GrandPlayer.IsDuplicate(source, key, windowSeconds)
    local entry = DuplicateGuard[source]
    if not entry then return false end
    if entry.key ~= key then return false end

    return (GetGameTimer() - entry.tick) < math.max(0, windowSeconds * 1000)
end

---@param source number
---@param key string
function GrandPlayer.MarkTransaction(source, key)
    DuplicateGuard[source] = { key = key, tick = GetGameTimer() }
end

---@param source number
function GrandPlayer.ClearTransaction(source)
    DuplicateGuard[source] = nil
end

-- ─── Persistence ──────────────────────────────────────────

--- Writes every core-owned column for one session.
---@param source number
---@param reason? string
---@return boolean
function GrandPlayer.Save(source, reason)
    local session = GrandPlayer.Get(source)
    if not session then return false end
    if session.saving then return false end

    session.saving = true

    local affected = DB.Update('SaveCharacter', [[
        UPDATE characters
           SET money = ?, job = ?, job_grade = ?, position = ?,
               inventory = ?, skin = ?, level = ?, exp = ?, last_seen = NOW()
         WHERE citizenid = ?
    ]], {
        Util.SerializeMoney(session.money),
        session.job or 'unemployed',
        Util.Floor(session.jobGrade),
        Util.EncodeJson(session.position),
        Util.EncodeJson(session.inventory or {}),
        Util.EncodeJson(session.skin or {}),
        Util.Floor(session.level),
        Util.Floor(session.exp),
        session.citizenid,
    })

    session.saving = false

    if affected < 0 then
        Util.Log('error', ('Save failed for %s'):format(session.citizenid))
        return false
    end

    session.dirty = false
    session.lastSaved = os.time()
    GrandPlayer.CloseSessionLog(session)

    if reason then Util.Debug(('%s saved (%s)'):format(session.citizenid, reason)) end
    return true
end

--- Narrow money write, called right after a wallet change so a crash
--- between autosaves cannot duplicate or lose cash.
---@param source number
---@return boolean
function GrandPlayer.SaveWallet(source)
    local session = GrandPlayer.Get(source)
    if not session then return false end

    local affected = DB.Update('SaveWallet',
        'UPDATE characters SET money = ? WHERE citizenid = ?',
        { Util.SerializeMoney(session.money), session.citizenid })

    return affected >= 0
end

---@param source number
---@return boolean
function GrandPlayer.SavePosition(source)
    local session = GrandPlayer.Get(source)
    if not session then return false end

    local affected = DB.Update('SavePosition',
        'UPDATE characters SET position = ? WHERE citizenid = ?',
        { Util.EncodeJson(session.position), session.citizenid })

    return affected >= 0
end

---@param source number
---@param job string
---@param grade number
---@return boolean
function GrandPlayer.SaveJob(source, job, grade)
    local session = GrandPlayer.Get(source)
    if not session then return false end

    session.job = job
    session.jobGrade = Util.Floor(grade)
    session.dirty = true

    local affected = DB.Update('SaveJob',
        'UPDATE characters SET job = ?, job_grade = ? WHERE citizenid = ?',
        { job, Util.Floor(grade), session.citizenid })

    return affected >= 0
end

---@param source number
---@param skin table
---@return boolean
function GrandPlayer.SaveSkin(source, skin)
    local session = GrandPlayer.Get(source)
    if not session or type(skin) ~= 'table' then return false end

    session.skin = skin
    session.dirty = true

    local affected = DB.Update('SaveSkin',
        'UPDATE characters SET skin = ? WHERE citizenid = ?',
        { Util.EncodeJson(skin), session.citizenid })

    return affected >= 0
end

---@param source number
---@param inventory table
---@return boolean
function GrandPlayer.SaveInventory(source, inventory)
    local session = GrandPlayer.Get(source)
    if not session then return false end

    session.inventory = type(inventory) == 'table' and inventory or {}
    session.dirty = true

    local affected = DB.Update('SaveInventory',
        'UPDATE characters SET inventory = ? WHERE citizenid = ?',
        { Util.EncodeJson(session.inventory), session.citizenid })

    return affected >= 0
end

-- ─── grand_sessions bookkeeping ───────────────────────────

---@param source number
function GrandPlayer.OpenSessionLog(source)
    local session = GrandPlayer.Get(source)
    if not session then return end

    DB.Insert('OpenSessionLog', [[
        INSERT INTO grand_sessions (citizenid, identifier, started_at, last_seen)
        VALUES (?, ?, NOW(), NOW())
    ]], { session.citizenid, session.license })
end

---@param session table
function GrandPlayer.CloseSessionLog(session)
    if not session then return end

    DB.Update('CloseSessionLog', [[
        UPDATE grand_sessions
           SET last_seen = NOW(), ended_at = NOW()
         WHERE citizenid = ? AND ended_at IS NULL
    ]], { session.citizenid })
end

-- ─── Flush ────────────────────────────────────────────────

---@param onlyDirty boolean
---@return number, number
function GrandPlayer.Flush(onlyDirty)
    local saved, failed = 0, 0

    for source, session in pairs(Sessions) do
        if not onlyDirty or session.dirty then
            GrandPlayer.CapturePed(session)

            if GrandPlayer.Save(source, onlyDirty and 'autosave' or 'flush') then
                saved = saved + 1
            else
                failed = failed + 1
            end
        end
    end

    return saved, failed
end

-- ─── Loops ────────────────────────────────────────────────

local loopsStarted = false

function GrandPlayer.StartLoops()
    if loopsStarted then return end
    loopsStarted = true

    -- Interval autosave of dirty sessions.
    Citizen.CreateThread(function()
        while true do
            Wait(math.max(30, Config.Persistence.AutosaveInterval) * 1000)

            local saved, failed = GrandPlayer.Flush(true)
            if Config.Debug and (saved > 0 or failed > 0) then
                Util.Debug(('Autosave flushed %d, failed %d'):format(saved, failed))
            end
        end
    end)

    -- Passive position capture so a crash still leaves a sane spawn.
    Citizen.CreateThread(function()
        while true do
            Wait(math.max(15, Config.Persistence.PositionInterval) * 1000)

            for _, session in pairs(Sessions) do
                if GrandPlayer.CapturePed(session) then
                    session.dirty = true
                end
            end
        end
    end)

    -- A session that never produced a ped after the load timeout is
    -- reported once so operators can spot a stuck client.
    Citizen.CreateThread(function()
        local warned = {}

        while true do
            Wait(30000)

            for source, session in pairs(Sessions) do
                if session.ped == 0 and not warned[source] then
                    if Util.SecondsSince(session.loadTime) > Config.Logins.LoadTimeout then
                        warned[source] = true
                        Util.Log('warn', ('Source %s never finished loading a ped'):format(tostring(source)))
                    end
                elseif session.ped > 0 then
                    warned[source] = nil
                end
            end
        end
    end)
end

-- ─── Lifecycle ────────────────────────────────────────────

AddEventHandler('playerDropped', function()
    local source = tonumber(source)
    if not source then return end

    local session = Sessions[source]
    if not session then
        GrandPlayer.Unload(source)
        return
    end

    if Config.Persistence.SaveOnDrop then
        GrandPlayer.CapturePed(session)
        GrandPlayer.Save(source, 'playerDropped')
    else
        GrandPlayer.CloseSessionLog(session)
    end

    Util.Log('info', ('%s dropped'):format(session.citizenid))
    GrandPlayer.Unload(source)
end)

-- ─── Events ───────────────────────────────────────────────

RegisterNetEvent('grand_core:server:PlayerReady', function(position)
    local source = tonumber(source)
    if not Sessions[source] then return end

    if type(position) == 'table' then
        GrandPlayer.SetPosition(source, position)
    end

    GrandPlayer.Touch(source)
end)

RegisterNetEvent('grand_core:server:Activity', function()
    local source = tonumber(source)
    if not Sessions[source] then return end
    GrandPlayer.Touch(source)
end)

RegisterNetEvent('grand_core:server:SyncVitals', function(hunger, thirst, stress)
    local source = tonumber(source)
    if not Sessions[source] then return end
    GrandPlayer.SetVitals(source, { hunger = hunger, thirst = thirst, stress = stress })
end)

RegisterNetEvent('grand_core:server:SyncPosition', function(position)
    local source = tonumber(source)
    if not Sessions[source] then return end

    if type(position) == 'table' then
        GrandPlayer.SetPosition(source, position)
        GrandPlayer.SavePosition(source)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end
    GrandPlayer.StartLoops()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    if Config.Persistence.SaveOnShutdown then
        local saved, failed = GrandPlayer.Flush(false)
        Util.Log('info', ('Shutdown flush: %d saved, %d failed'):format(saved, failed))
    end
end)

-- ─── Exports ──────────────────────────────────────────────

exports('GetSession',            GrandPlayer.Get)
exports('GetCharacter',          GrandPlayer.GetCharacter)
exports('GetCharacterData',      GrandPlayer.GetCharacterData)
exports('GetCharacterRows',      GrandPlayer.GetRows)
exports('CountFor',              GrandPlayer.CountFor)
exports('GetIdentifier',         GrandPlayer.GetIdentifier)
exports('GetSourceByIdentifier', GrandPlayer.GetSourceByIdentifier)
exports('GetSourceByCitizenId',  GrandPlayer.GetSourceByCitizenId)
exports('LoadPlayer',            GrandPlayer.Load)
exports('SaveCharacter',         GrandPlayer.Save)
exports('SaveWallet',            GrandPlayer.SaveWallet)
exports('SetPosition',           GrandPlayer.SetPosition)
exports('SetVitals',             GrandPlayer.SetVitals)
exports('SetWallet',             GrandPlayer.SetWallet)
exports('OnlineCount',           GrandPlayer.OnlineCount)

_G.GrandPlayer = GrandPlayer
