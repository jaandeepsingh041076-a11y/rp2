-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/shared/util.lua
--  Pure helpers. Shared between the client and the server, so it
--  must not touch the DB, exports or natives beyond vector3/Wait.
-- ─────────────────────────────────────────────────────────────

-- Global within this resource only (server/*.lua and client/*.lua both
-- see it, because shared_scripts run first in every script context).
Util = {}
Families = Families or {}
Families.Util = Util

-- ─── Strings ──────────────────────────────────────────────────
function Util.Trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function Util.Lower(value)
    return tostring(value or ''):lower()
end

--- ASCII-only, no control characters, no long strings. Every name the
--- family layer accepts goes through this before it reaches SQL.
function Util.Clean(value, maxLength)
    local out = Util.Trim(value):gsub('[^%g]', ''):gsub('[%"\'\\%-%-]', '')
    local cap = math.floor(tonumber(maxLength) or 50)
    if #out > cap then out = out:sub(1, cap) end
    return out
end

function Util.IsBlank(value)
    return Util.Trim(value) == ''
end

function Util.TitleCase(value)
    return tostring(value or ''):gsub('%W', function(word)
        return word:sub(1, 1):upper() .. word:sub(2):lower()
    end)
end

-- ─── Numbers ──────────────────────────────────────────────────
function Util.Int(value, fallback)
    local number = tonumber(value)
    if not number then return math.floor(tonumber(fallback) or 0) end
    return math.floor(number + 0.5)
end

function Util.Clamp(value, low, high)
    value = tonumber(value) or low
    if value < low then return low end
    if value > high then return high end
    return value
end

function Util.Round(value, places)
    local mult = 10 ^ (math.floor(tonumber(places) or 2))
    return math.floor((tonumber(value) or 0) * mult + 0.5) / mult
end

--- $1,234,567 with thousands separators.
function Util.Money(value)
    local amount = tostring(math.floor(math.abs(tonumber(value) or 0)))
    local formatted = amount
    while true do
        local swap
        swap, formatted = formatted:match('^(-?%d+)(%d%d%d)')
        if not swap then break end
        formatted = swap .. ',' .. formatted:match('(.*)')
    end
    return ('%s$%s'):format((tonumber(value) or 0) < 0 and '-' or '', formatted)
end

-- ─── JSON ─────────────────────────────────────────────────────
function Util.Decode(value, fallback)
    if type(value) == 'table' then return value end
    if value == nil or value == '' then return fallback or {} end
    local ok, decoded = pcall(json.decode, tostring(value))
    if ok and type(decoded) == 'table' then return decoded end
    return fallback or {}
end

function Util.Encode(value)
    if type(value) == 'string' then return value end
    local ok, encoded = pcall(json.encode, value or {})
    return ok and encoded or '{}'
end

-- ─── Identity ─────────────────────────────────────────────────
-- A citizenid is 6 letters + 5 digits in this server (grand_core
-- Config.Identity). Anything else is a client trying to lie.
function Util.ValidCitizenId(value)
    value = tostring(value or '')
    if #value < 6 or #value > 16 then return false end
    return value:match('^%u+%d+$') ~= nil or value:match('^%w+$') ~= nil
end

function Util.ValidFamilyName(value)
    value = Util.Trim(value)
    local rules = (Config and Config.Families) or {}
    if #value < (rules.MinNameLength or 3) then return false, 'Name too short' end
    if #value > (rules.MaxNameLength or 20) then return false, 'Name too long' end
    if not value:match("^[%a%s'%.%-]+$") then return false, 'Name contains invalid characters' end
    for _, blocked in ipairs(rules.BlockedNames or {}) do
        if Util.Lower(value):find(Util.Lower(blocked), 1, true) then
            return false, 'Name is not permitted'
        end
    end
    return true
end

function Util.ValidTag(value)
    value = Util.Trim(value):upper()
    if value == '' then return true, '' end
    if #value > (Config.Families.MaxTagLength or 5) then return false, 'Tag too long' end
    if not value:match('^%u%d*$') then return false, 'Tag must be letters and digits only' end
    return true, value
end

function Util.ValidHexColour(value)
    value = Util.Trim(value)
    if value == '' then return false end
    return value:match('^#%x%x%x%x%x%x$') ~= nil
end

-- ─── Ranks ────────────────────────────────────────────────────
function Util.Rank(rank)
    return Util.Clamp(math.floor(tonumber(rank) or 1), 1, Config.Families.MaxRank)
end

function Util.RankTitle(rank)
    local titles = Config.RankTitles or {}
    return titles[Util.Rank(rank)] or ('Rank %d'):format(Util.Rank(rank))
end

--- Permissions ladder downward: rank 8 inherits everything rank 5 has.
function Util.Permissions(rank)
    local r = Util.Rank(rank)
    local merged = {}
    local table_ = Config.RankPermissions or {}
    for level, perms in pairs(table_) do
        if level <= r then
            for key, value in pairs(perms) do
                if value then merged[key] = true end
            end
        end
    end
    local exact = table_[r]
    if exact then
        for key, value in pairs(exact) do merged[key] = value end
    end
    return merged
end

function Util.Can(rank, permission)
    local perms = Util.Permissions(rank)
    return perms[permission] == true
end

--- A member may only change the rank of someone strictly below them,
--- and may never touch the leader unless they are the leader.
function Util.CanManageRank(actorRank, targetRank, isLeader)
    actorRank, targetRank = Util.Rank(actorRank), Util.Rank(targetRank)
    if not Util.Can(actorRank, 'canPromote') then return false, 'No promotion rights' end
    if targetRank >= actorRank and not isLeader then return false, 'Cannot manage a superior' end
    if isLeader and actorRank < Config.Families.MaxRank then return false, 'Only the Godfather can do that' end
    return true
end

-- ─── Time ─────────────────────────────────────────────────────
function Util.Hour()
    return 3600
end

function Util.Since(timestamp)
    local stamp = tonumber(timestamp)
    if not stamp then return 0 end
    return math.max(0, os.time() - stamp)
end

--- MySQL TIMESTAMP values come back as 'YYYY-MM-DD HH:MM:SS'. Converting
--- with os.time on the server clock is good enough for accrual maths.
function Util.SqlToEpoch(value)
    if type(value) == 'number' then return value end
    local y, m, d, h, min, s = tostring(value or ''):match('^(%d+)-(%d+)-(%d+)[ T]?(%d+):(%d+):?(%d*)')
    if not y then return os.time() end
    return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d),
        hour = tonumber(h) or 0, min = tonumber(min) or 0, sec = tonumber(s) or 0 })
end

function Util.Duration(seconds)
    seconds = math.max(0, Util.Int(seconds))
    local h, m = math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)
    if h > 0 then return ('%dh %dm'):format(h, m) end
    return ('%dm %ds'):format(m, seconds % 60)
end

-- ─── Geometry (zones, turf presence) ──────────────────────────
function Util.FlatDistance(a, b)
    if not a or not b then return math.huge end
    return math.sqrt(((a.x or a[1] or 0) - (b.x or b[1] or 0)) ^ 2
        + ((a.y or a[2] or 0) - (b.y or b[2] or 0)) ^ 2)
end

function Util.InZone(coords, zone)
    if not coords or not zone then return false end
    local radius = tonumber(zone.radius) or 150.0
    return Util.FlatDistance(coords, zone.coords) <= radius
end

--- Z-level tolerance: a turf is a cylinder, but players in the garage
--- under Davis must still count, so we compare height separately.
function Util.HeightOk(coords, zone, tolerance)
    if not coords or not zone then return false end
    local limit = tonumber(tolerance) or (Config.TurfWar and Config.TurfWar.heightTolerance) or 60.0
    local z1 = coords.z or coords[3] or 0.0
    local z2 = (zone.coords and (zone.coords.z or zone.coords[3])) or 0.0
    return math.abs(z1 - z2) <= limit
end

function Util.InZone3D(coords, zone)
    return Util.InZone(coords, zone) and Util.HeightOk(coords, zone)
end

-- ─── Tables ───────────────────────────────────────────────────
function Util.Copy(input)
    if type(input) ~= 'table' then return {} end
    local out = {}
    for k, v in pairs(input) do
        out[k] = type(v) == 'table' and Util.Copy(v) or v
    end
    return out
end

function Util.Count(table_)
    local n = 0
    for _ in pairs(table_ or {}) do n = n + 1 end
    return n
end

function Util.Keys(table_)
    local out = {}
    for k in pairs(table_ or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function Util.Sum(rows, key)
    local total = 0
    for _, row in ipairs(rows or {}) do
        total = total + (tonumber(type(row) == 'table' and row[key] or row) or 0)
    end
    return total
end

--- Dedupes and type-checks a citizenid list coming from a client.
function Util.CleanIds(input, limit)
    local seen, out = {}, {}
    for _, value in ipairs(type(input) == 'table' and input or {}) do
        local cid = Util.Clean(value, 16)
        if Util.ValidCitizenId(cid) and not seen[cid] then
            seen[cid] = true
            out[#out + 1] = cid
            if #out >= (math.floor(tonumber(limit) or 20)) then break end
        end
    end
    return out
end

-- ─── Rate limiting ────────────────────────────────────────────
local buckets = {}

--- Guarded cross-resource export call. `...` is not visible inside a
--- nested function, so everything goes through table.pack first.
function Util.TryExport(res, name, ...)
    if GetResourceState(res) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[res][name](table.unpack(args, 1, args.n))
    end)
    if not ok then
        if Config and Config.Debug then
            print(('^3[util] %s:%s failed: %s^7'):format(res, name, tostring(result)))
        end
        return nil
    end
    return result
end

Util.TRY = Util.TryExport

--- Returns true when the actor is within budget, consuming one token.
function Util.Throttle(key, maxPerWindow, windowSeconds)
    local now = os.time()
    local entry = buckets[key]
    if not entry or now - entry.started > windowSeconds then
        buckets[key] = { started = now, hits = 1 }
        return true
    end
    entry.hits = entry.hits + 1
    return entry.hits <= maxPerWindow
end

function Util.Cooldown(key, seconds)
    local now = os.time()
    local until_ = buckets['cd:' .. key]
    if until_ and now < until_ then return until_ - now end
    buckets['cd:' .. key] = now + math.floor(tonumber(seconds) or 0)
    return 0
end

CreateThread(function()
    while true do
        Wait(120000)
        local now = os.time()
        for key, entry in pairs(buckets) do
            if type(entry) == 'number' then
                if now > entry + 3600 then buckets[key] = nil end
            elseif now - entry.started > 600 then
                buckets[key] = nil
            end
        end
    end
end)

return Util
