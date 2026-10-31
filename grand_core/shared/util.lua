-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/shared/util.lua
--  Pure helpers shared by client + server. No natives, no DB,
--  no framework calls — everything here is deterministic and
--  side-effect free so it can be unit-reasoned about.
-- ─────────────────────────────────────────────────────────────

Util = {}

-- ─── Numbers ─────────────────────────────────────────────────

--- Numeric clamp that also kills NaN before it reaches the database.
---@param value number|string
---@param lower number
---@param upper number
---@return number
function Util.Clamp(value, lower, upper)
    value = tonumber(value)
    if not value or value ~= value then return lower end
    if value < lower then return lower end
    if value > upper then return upper end
    return value
end

--- Integer round (Lua's // and math.floor disagree on negatives).
---@param value number|string
---@return number
function Util.Round(value)
    value = tonumber(value)
    if not value or value ~= value then return 0 end
    return math.floor(value + 0.5)
end

--- Floor toward zero, used for money so we never mint a fraction.
---@param value number|string
---@return number
function Util.Floor(value)
    value = tonumber(value)
    if not value or value ~= value then return 0 end
    if value >= 0 then return math.floor(value) end
    return math.ceil(value)
end

--- Safe division: never returns inf or NaN.
---@param numerator number
---@param denominator number
---@param fallback? number
---@return number
function Util.Divide(numerator, denominator, fallback)
    numerator = tonumber(numerator) or 0
    denominator = tonumber(denominator) or 0
    if denominator == 0 then return fallback or 0 end
    return numerator / denominator
end

-- ─── Tables ──────────────────────────────────────────────────

--- Count the entries of a hash or array table.
---@param input table|nil
---@return number
function Util.Count(input)
    if type(input) ~= 'table' then return 0 end

    local count = 0
    for _ in pairs(input) do count = count + 1 end
    return count
end

--- First value in a table matching a predicate.
---@param input table
---@param predicate fun(value: any, key: any): boolean
---@return any|nil
function Util.Find(input, predicate)
    if type(input) ~= 'table' then return nil end
    for key, value in pairs(input) do
        if predicate(value, key) then return value, key end
    end
    return nil
end

--- Shallow copy that leaves functions and metatables behind.
---@param input table|nil
---@return table
function Util.Copy(input)
    local copy = {}
    if type(input) ~= 'table' then return copy end
    for key, value in pairs(input) do
        if type(value) == 'table' then
            copy[key] = Util.Copy(value)
        else
            copy[key] = value
        end
    end
    return copy
end

--- Merge b into a (b wins), non-destructive.
---@param a table
---@param b table|nil
---@return table
function Util.Merge(a, b)
    local result = Util.Copy(a or {})
    if type(b) == 'table' then
        for key, value in pairs(b) do
            if type(value) == 'table' and type(result[key]) == 'table' then
                result[key] = Util.Merge(result[key], value)
            else
                result[key] = value
            end
        end
    end
    return result
end

--- Whether a value sits in an array table.
---@param input table
---@param value any
---@return boolean
function Util.InTable(input, value)
    if type(input) ~= 'table' then return false end
    for _, entry in pairs(input) do
        if entry == value then return true end
    end
    return false
end

--- Keys of a table sorted deterministically.
---@param input table
---@return table
function Util.Keys(input)
    local keys = {}
    for key in pairs(input or {}) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) then return tostring(a) < tostring(b) end
        return tostring(a) < tostring(b)
    end)
    return keys
end

-- ─── Strings ─────────────────────────────────────────────────

--- Trim leading/trailing whitespace.
---@param value any
---@return string
function Util.Trim(value)
    return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

--- Lower-case a string with no locale surprises.
---@param value any
---@return string
function Util.Lower(value)
    return Util.Trim(value):lower()
end

--- True when every character is alphabetic (names, plates).
---@param value string
---@return boolean
function Util.IsAlpha(value)
    return type(value) == 'string' and value:match('^%a+$') ~= nil
end

--- True when the string is alphanumeric only.
---@param value string
---@return boolean
function Util.IsAlphanumeric(value)
    return type(value) == 'string' and value:match('^%w+$') ~= nil
end

--- Strip anything that is not a letter, digit, space or apostrophe.
---@param value string
---@return string
function Util.SanitizeName(value)
    value = Util.Trim(value)
    value = value:gsub("[^%a%s'‘’%-]", '')
    value = value:gsub('%s+', ' ')
    return value
end

-- ─── Money JSON ──────────────────────────────────────────────
-- Shape stored on characters.money:
--   { "cash": 0, "bank": 0, "crypto": 0 }

local MONEY_KINDS = { 'cash', 'bank', 'crypto' }

--- Empty wallet using the configured starting balances.
---@return table
function Util.EmptyMoney()
    local starting = (Config and Config.Money and Config.Money.Starting) or {}
    return {
        cash   = Util.Floor(starting.cash or 0),
        bank   = Util.Floor(starting.bank or 0),
        crypto = Util.Floor(starting.crypto or 0),
    }
end

--- Read one wallet bucket, falling back to the starting balance only
--- when the column genuinely does not carry the key.
---@param source table|nil
---@param kind string
---@param defaults table
---@return number
local function ReadBucket(source, kind, defaults)
    if type(source) ~= 'table' then return Util.Floor(defaults[kind]) end
    if source[kind] == nil then return Util.Floor(defaults[kind]) end
    return Util.Floor(source[kind])
end

--- Parse the money column. Never throws: a corrupt row becomes a
--- starting wallet instead of taking down the save routine.
---@param raw string|table|nil
---@return table money {cash, bank, crypto}
function Util.ParseMoney(raw)
    local defaults = (Config and Config.Money and Config.Money.Starting) or {}
    local decoded = raw

    if type(raw) == 'string' then
        if raw == '' then decoded = {} else
            local ok, result = pcall(json.decode, raw)
            decoded = (ok and type(result) == 'table') and result or {}
        end
    elseif type(raw) ~= 'table' then
        decoded = {}
    end

    return {
        cash   = ReadBucket(decoded, 'cash', defaults),
        bank   = ReadBucket(decoded, 'bank', defaults),
        crypto = ReadBucket(decoded, 'crypto', defaults),
    }
end

--- Serialise a wallet back to the JSON column shape.
---@param money table|nil
---@return string
function Util.SerializeMoney(money)
    money = money or {}
    local payload = {
        cash   = Util.Floor(money.cash),
        bank   = Util.Floor(money.bank),
        crypto = Util.Floor(money.crypto),
    }

    local ok, encoded = pcall(json.encode, payload)
    if not ok or type(encoded) ~= 'string' then
        return '{"cash":0,"bank":0,"crypto":0}'
    end
    return encoded
end

--- Total of every wallet bucket (used by the cap checks).
---@param money table|nil
---@return number
function Util.TotalMoney(money)
    money = money or {}
    return Util.Floor(money.cash) + Util.Floor(money.bank) + Util.Floor(money.crypto)
end

--- The valid money kinds, exported so other resources stop guessing.
---@return table
function Util.MoneyKinds()
    local copy = {}
    for i = 1, #MONEY_KINDS do copy[i] = MONEY_KINDS[i] end
    return copy
end

--- Whether a string is an accepted money bucket.
---@param kind any
---@return boolean
function Util.IsMoneyKind(kind)
    return Util.InTable(MONEY_KINDS, tostring(kind))
end

-- ─── JSON helpers ────────────────────────────────────────────

--- Decode a JSON column with a table fallback.
---@param raw string|table|nil
---@param fallback? any
---@return any
function Util.ParseJson(raw, fallback)
    if type(raw) == 'table' then return raw end
    if type(raw) ~= 'string' or raw == '' then return fallback or {} end

    local ok, decoded = pcall(json.decode, raw)
    if not ok then return fallback or {} end
    return decoded
end

--- Encode with a stable fallback string.
---@param value any
---@param fallback? string
---@return string
function Util.EncodeJson(value, fallback)
    local ok, encoded = pcall(json.encode, value)
    if ok and type(encoded) == 'string' then return encoded end
    return fallback or '{}'
end

-- ─── Vectors / distance ──────────────────────────────────────

--- Coerce anything coordinate-ish into {x,y,z}.
---@param pos any
---@return table
function Util.ToVector(pos)
    if type(pos) ~= 'table' then
        return { x = 0.0, y = 0.0, z = 0.0 }
    end
    return {
        x = tonumber(pos.x or pos[1]) or 0.0,
        y = tonumber(pos.y or pos[2]) or 0.0,
        z = tonumber(pos.z or pos[3]) or 0.0,
    }
end

--- 3D distance between two tables or vector3 values.
---@param a any
---@param b any
---@return number
function Util.Distance(a, b)
    local pa, pb = Util.ToVector(a), Util.ToVector(b)
    local dx, dy, dz = pa.x - pb.x, pa.y - pb.y, pa.z - pb.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Flat 2D distance (Z drift in hills makes 3D useless for zones).
---@param a any
---@param b any
---@return number
function Util.Distance2D(a, b)
    local pa, pb = Util.ToVector(a), Util.ToVector(b)
    local dx, dy = pa.x - pb.x, pa.y - pb.y
    return math.sqrt(dx * dx + dy * dy)
end

--- Nearest entry from a Config.Positions-style list.
---@param point any
---@param list table|nil
---@return table|nil, number
function Util.Nearest(point, list)
    local best, bestDistance = nil, math.huge
    for _, entry in ipairs(list or {}) do
        local distance = Util.Distance(point, entry)
        if distance < bestDistance then
            best, bestDistance = entry, distance
        end
    end
    return best, bestDistance == math.huge and 0.0 or bestDistance
end

--- Interpolate between two numbers (used for HUD fades).
---@param a number
---@param b number
---@param t number 0..1
---@return number
function Util.Lerp(a, b, t)
    return a + (b - a) * Util.Clamp(t, 0, 1)
end

-- ─── Plates ──────────────────────────────────────────────────

--- Generates a `GRxxxx` plate, or feeds back a supplied random string
--- so callers can retry without a closure.
---@param randomSource? fun(max:number):number  returns 0..max-1
---@return string
function Util.GeneratePlate(randomSource)
    local prefix  = (Config and Config.Identity and Config.Identity.PlatePrefix) or 'GR'
    local digits  = (Config and Config.Identity and Config.Identity.PlateDigits) or 4

    local rng = randomSource or math.random
    local body = ''
    for _ = 1, digits do
        local pick = rng(10)
        pick = math.floor(tonumber(pick) or 0)
        if pick < 0 then pick = 0 end
        body = body .. tostring(pick % 10)
    end

    return ('%s%s'):format(prefix:sub(1, 8 - digits), body)
end

--- Normalise a plate the way the database stores it.
---@param plate any
---@return string
function Util.NormalizePlate(plate)
    local value = Util.Trim(plate):upper():gsub('[^%w]', '')
    return value:sub(1, 8)
end

-- ─── Citizen IDs ─────────────────────────────────────────────

--- Builds a citizenid like `ABJKLM12345`.
---@param randomSource? fun(max:number):number
---@return string
function Util.GenerateCitizenId(randomSource)
    local letters = (Config and Config.Identity and Config.Identity.Letters) or 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local letterLen = (Config and Config.Identity and Config.Identity.LetterLength) or 6
    local numberLen = (Config and Config.Identity and Config.Identity.NumberLength) or 5
    local prefix    = (Config and Config.Identity and Config.Identity.Prefix) or ''

    local rng = randomSource or math.random
    local chars = {}
    for _ = 1, letterLen do
        local index = math.floor(tonumber(rng(#letters)) or 1)
        if index < 1 then index = 1 elseif index > #letters then index = #letters end
        chars[#chars + 1] = letters:sub(index, index)
    end

    local numbers = ''
    for _ = 1, numberLen do
        local digit = math.floor(tonumber(rng(10)) or 0)
        numbers = numbers .. tostring(digit % 10)
    end

    return ('%s%s%s'):format(prefix, table.concat(chars), numbers)
end

-- ─── Identifiers ─────────────────────────────────────────────

--- Pull one identifier type out of a GetPlayerIdentifiers() list.
---@param identifiers table
---@param kind string  'license' | 'fivem' | 'steam' | 'discord' | 'xbl' | 'ip'
---@return string|nil
function Util.GetIdentifierByType(identifiers, kind)
    if type(identifiers) ~= 'table' then return nil end

    local needle = kind .. ':'
    for _, raw in ipairs(identifiers) do
        local value = tostring(raw)
        if value:sub(1, #needle) == needle then
            return value
        end
    end
    return nil
end

--- Best stable identifier for a character row, honouring the
--- database.sql convention of storing the raw `license:xxxx` string.
---@param identifiers table
---@return string|nil
function Util.GetLicenseIdentifier(identifiers)
    local license = Util.GetIdentifierByType(identifiers, 'license')
    if license then return license end

    -- legal / discord-only servers still have something unique
    for _, kind in ipairs({ 'fivem', 'steam', 'xbl', 'live', 'discord', 'ip' }) do
        local found = Util.GetIdentifierByType(identifiers, kind)
        if found then return found end
    end
    return nil
end

--- Strip the `type:` prefix, e.g. license:abc -> abc
---@param identifier string
---@return string
function Util.StripIdentifier(identifier)
    local value = tostring(identifier or '')
    return (value:gsub('^%w+:', ''))
end

--- Whether a stored identifier column matches the raw value we have.
---@param stored string|nil
---@param wanted string|nil
---@return boolean
function Util.IdentifierMatches(stored, wanted)
    if not stored or not wanted then return false end
    if stored == wanted then return true end
    return Util.StripIdentifier(stored) == Util.StripIdentifier(wanted)
end

-- ─── Time ────────────────────────────────────────────────────

--- Seconds -> `1h 05m 30s`, dropping empty leading units.
---@param seconds number|string
---@param compact? boolean  drop the 'h/m/s' words
---@return string
function Util.FormatTime(seconds, compact)
    local total = math.max(0, Util.Floor(seconds))
    local hours   = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    local secs    = total % 60

    if compact then
        if hours > 0 then return ('%d:%02d:%02d'):format(hours, minutes, secs) end
        return ('%02d:%02d'):format(minutes, secs)
    end

    if hours > 0 then return ('%dh %02dm %02ds'):format(hours, minutes, secs) end
    if minutes > 0 then return ('%dm %02ds'):format(minutes, secs) end
    return ('%ds'):format(secs)
end

--- Human duration for logs, e.g. `4h`.
---@param seconds number
---@return string
function Util.FormatDuration(seconds)
    local total = math.max(0, Util.Floor(seconds))
    if total < 60 then return ('%ds'):format(total) end
    if total < 3600 then return ('%dm'):format(math.floor(total / 60)) end
    return ('%dh'):format(math.floor(total / 3600))
end

--- Format an os.time() stamp as `YYYY-MM-DD HH:MM:SS`.
---@param stamp number|nil
---@param utcOnly? boolean
---@return string
function Util.FormatDate(stamp, utcOnly)
    local time = tonumber(stamp) or os.time()
    local pattern = utcOnly and '!%Y-%m-%d %H:%M:%S' or '%Y-%m-%d %H:%M:%S'

    local ok, result = pcall(os.date, pattern, time)
    if ok and type(result) == 'string' then return result end
    return '1970-01-01 00:00:00'
end

--- Milliseconds since a past os.time() stamp.
---@param since number
---@return number
function Util.SecondsSince(since)
    return math.max(0, os.time() - (tonumber(since) or os.time()))
end

-- ─── Formatting ──────────────────────────────────────────────

--- $1,234,567 currency string (Section 01: numbers are tabular).
---@param amount number|string
---@return string
function Util.FormatMoney(amount)
    local value = Util.Floor(amount)
    local negative = value < 0
    value = math.abs(value)

    local text = tostring(value)
    local grouped = text:reverse():gsub('(%d%d%d)', '%1,'):reverse()
    grouped = grouped:gsub('^,', '')

    return ('%s$%s'):format(negative and '-' or '', grouped)
end

--- Title-case a job key (`lspd` -> `Lspd`, `car_dealer` -> `Car Dealer`).
---@param key string
---@return string
function Util.Humanize(key)
    local value = Util.Trim(key):gsub('[_%-]', ' ')
    return (value:gsub('%f[%w]%a', function(first) return first:upper() end))
end

-- ─── Validation ──────────────────────────────────────────────

--- Checks a first/last name against Config.Identity rules.
---@param name any
---@return boolean ok, string reason, string cleaned
function Util.ValidateName(name)
    local rules = (Config and Config.Identity) or {}
    local cleaned = Util.SanitizeName(name)
    local lower = cleaned:lower()

    if #cleaned < (rules.MinNameLength or 2) then
        return false, 'Name is too short', cleaned
    end
    if #cleaned > (rules.MaxNameLength or 20) then
        return false, 'Name is too long', cleaned
    end
    if not cleaned:match("^%a[%a%s'‘’%-]*$") then
        return false, 'Name contains invalid characters', cleaned
    end

    for _, blocked in ipairs(rules.BlockedNames or {}) do
        if lower:find(tostring(blocked):lower(), 1, true) then
            return false, 'Name is not allowed', cleaned
        end
    end
    for _, blocked in ipairs(rules.BlockedExact or {}) do
        if lower == tostring(blocked):lower() then
            return false, 'Name is not allowed', cleaned
        end
    end

    return true, '', cleaned
end

--- Whitelist gate used by join handlers.
---@param identifier string|nil
---@return boolean
function Util.IsWhitelisted(identifier)
    local rules = (Config and Config.Whitelist) or {}
    if not rules.Enabled then return true end
    if not identifier then return false end

    for _, allowed in ipairs(rules.Identifiers or {}) do
        if allowed == '*' then return true end
        if Util.IdentifierMatches(identifier, tostring(allowed)) then return true end
    end
    return false
end

--- Whether a job requires the whitelist gate in Config.Whitelist.JobWhitelist.
---@param jobName string|nil
---@return boolean
function Util.IsGatedJob(jobName)
    local rules = (Config and Config.Whitelist and Config.Whitelist.JobWhitelist) or {}
    if not rules.Enabled then return false end
    return Util.InTable(rules.Jobs or {}, tostring(jobName))
end

-- ─── Logging ─────────────────────────────────────────────────

--- Structured console line, Section-01 coloured.
---@param level string 'info' | 'warn' | 'error'
---@param message string
function Util.Log(level, message)
    local colour = ({
        info  = '^2',
        warn  = '^3',
        error = '^1',
        debug = '^7',
    })[level] or '^7'

    print(('%s[grand_core]^7 %s'):format(colour, tostring(message)))
end

--- Only logs when Config.Debug is on.
---@param message string
function Util.Debug(message)
    if Config and Config.Debug then Util.Log('debug', message) end
end
