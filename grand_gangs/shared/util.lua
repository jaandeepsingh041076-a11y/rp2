-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/shared/util.lua
--  Pure-Lua helpers shared by client + server. No NUI, no DB.
--  Owns: guarded cross-resource calls, zone/distance maths,
--  plate + citizenid sanitising, the colour palette, logging,
--  money formatting and the generic cooldown store.
-- ─────────────────────────────────────────────────────────────

GangsShared = GangsShared or {}
local Shared = GangsShared

Shared.Name = 'grand_gangs'

-- ─── Guarded cross-resource export call ──────────────────────
-- `...` is NOT visible inside a nested function, so pack first.
function Shared.TryExport(res, name, ...)
    if GetResourceState(res) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[res][name](table.unpack(args, 1, args.n))
    end)
    return ok and result or nil
end

--- Same, but returns nil instead of throwing when the resource is missing.
function Shared.TryEvent(eventName, ...)
    local args = table.pack(...)
    local ok = pcall(function()
        TriggerEvent(eventName, table.unpack(args, 1, args.n))
    end)
    return ok
end

--- Like TryExport, but tells the caller whether the call itself landed,
--- so money paths never double-credit when an export returns nothing.
function Shared.TryExportOk(res, name, ...)
    if GetResourceState(res) ~= 'started' then return false, nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[res][name](table.unpack(args, 1, args.n))
    end)
    if not ok then return false, nil end
    return true, result
end

-- ─── Maths ───────────────────────────────────────────────────
function Shared.Clamp(value, lo, hi)
    if type(value) ~= 'number' then return lo end
    if value < lo then return lo end
    if value > hi then return hi end
    return value
end

function Shared.Round(value, places)
    local m = 10 ^ (places or 0)
    return math.floor((value * m) + 0.5) / m
end

function Shared.Money(value)
    return Shared.Round(Shared.Clamp(tonumber(value) or 0, -999999999, 999999999))
end

--- Pretty money: 1234567 -> $1,234,567
function Shared.FormatMoney(value)
    local n = Shared.Money(math.abs(value or 0))
    local s = tostring(math.floor(n))
    local out = ''
    while #s > 3 do
        out = ',' .. s:sub(-3) .. out
        s = s:sub(1, -4)
    end
    out = s .. out
    return ('%s$%s'):format((value or 0) < 0 and '-' or '', out)
end

--- Human duration: 5400 -> 1h 30m
function Shared.Duration(seconds)
    local s = math.max(0, math.floor(tonumber(seconds) or 0))
    local h = math.floor(s / 3600)
    local m = math.floor((s % 3600) / 60)
    if h > 0 then return ('%dh %02dm'):format(h, m) end
    return ('%dm %02ds'):format(m, s % 60)
end

-- ─── Vector helpers (accepts vector3 / {x,y,z} / {1,2,3}) ────
function Shared.AsVec(v)
    if not v then return nil end
    local x = v.x or v[1] or 0
    local y = v.y or v[2] or 0
    local z = v.z or v[3] or 0
    return vector3(tonumber(x) + 0.0, tonumber(y) + 0.0, tonumber(z) + 0.0)
end

function Shared.Distance2D(a, b)
    local va, vb = Shared.AsVec(a), Shared.AsVec(b)
    if not va or not vb then return math.huge end
    local dx, dy = va.x - vb.x, va.y - vb.y
    return math.sqrt(dx * dx + dy * dy)
end

function Shared.Distance3D(a, b)
    local va, vb = Shared.AsVec(a), Shared.AsVec(b)
    if not va or not vb then return math.huge end
    return #(va - vb)
end

--- Flattens whatever coords shape came out of the DB JSON into {x,y,z}.
function Shared.ParseCoords(raw)
    if type(raw) == 'string' then
        local ok, decoded = pcall(json.decode, raw)
        if not ok or type(decoded) ~= 'table' then
            local x, y, z = raw:match('([%d%.%-]+)[,%s]+([%d%.%-]+)[,%s]+([%d%.%-]+)')
            if not x then return nil end
            return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
        end
        raw = decoded
    end
    return Shared.AsVec(raw)
end

-- ─── Zone registry access (config-driven, shared) ────────────
Shared.ZoneIndex = nil

function Shared.Zones()
    local list = (Config and Config.Zones) or {}
    if Shared.ZoneIndex == nil then
        local idx = {}
        for i = 1, #list do
            local zone = list[i]
            if zone and type(zone.id) == 'string' then
                idx[zone.id:lower()] = zone
            end
        end
        Shared.ZoneIndex = idx
    end
    return list, Shared.ZoneIndex
end

function Shared.ZoneById(id)
    if type(id) ~= 'string' then return nil end
    local _, idx = Shared.Zones()
    return idx[id:lower():gsub('%s', '')] or idx[id:lower()]
end

--- The turf whose radius contains `coords` (nearest wins on overlap).
function Shared.ZoneAt(coords)
    local pos = Shared.AsVec(coords)
    if not pos then return nil end
    local list = Shared.Zones()
    local best, bestDist
    for i = 1, #list do
        local zone = list[i]
        local centre = Shared.AsVec(zone.coords)
        if centre then
            local d = #(pos - centre)
            local r = tonumber(zone.radius) or 120.0
            if d <= r and (not bestDist or d < bestDist) then
                best, bestDist = zone, d
            end
        end
    end
    return best, bestDist
end

function Shared.InZone(zoneId, coords)
    local zone = Shared.ZoneById(zoneId)
    if not zone then return false, math.huge end
    local d = Shared.Distance3D(coords, zone.coords)
    return d <= (tonumber(zone.radius) or 120.0), d
end

function Shared.ContestRadius(zone)
    local fallback = (Config and Config.War and Config.War.contestRadius) or 110.0
    if type(zone) ~= 'table' then return fallback end
    local r = tonumber(zone.contestRadius) or tonumber(zone.radius) or fallback
    return Shared.Clamp(r, 40.0, 400.0)
end

function Shared.IsGhetto(zone)
    return type(zone) == 'table' and zone.ghetto == true
end

function Shared.TierIncome(zone)
    local tier = Shared.Clamp((type(zone) == 'table' and tonumber(zone.tier)) or 1, 1, 3)
    return (Config and Config.TierIncome and Config.TierIncome[tier]) or 10000
end

-- ─── Gang helpers ────────────────────────────────────────────
function Shared.Gang(key)
    if type(key) ~= 'string' then return nil end
    return Config and Config.Gangs and Config.Gangs[key:lower()]
end

function Shared.GangKeys()
    local out = {}
    for k in pairs((Config and Config.Gangs) or {}) do out[#out + 1] = k end
    table.sort(out)
    return out
end

function Shared.IsRival(a, b)
    local ga, gb = Shared.Gang(a), Shared.Gang(b)
    if not ga or not gb or a == b then return false end
    for _, r in ipairs(ga.rivals or {}) do
        if r == b then return true end
    end
    return false
end

function Shared.IsAlly(a, b)
    if type(a) ~= 'string' or type(b) ~= 'string' then return false end
    if a == b then return true end
    local ga = Shared.Gang(a)
    if not ga then return false end
    for _, al in ipairs(ga.allies or {}) do
        if al == b then return true end
    end
    return false
end

function Shared.HomeTurfOf(gangKey)
    local g = Shared.Gang(gangKey)
    return g and g.homeTurf or nil
end

-- ─── Colour table ────────────────────────────────────────────
-- name -> FiveM radmap index (mirrors grand_mechanic's palette).
Shared.ColourNames = {
    white = 0, crimson = 1, red = 1, green = 2, blue = 3, gold = 4,
    purple = 5, teal = 6, pink = 8, orange = 9, emerald = 25, grey = 26,
    ballas = 27, wrench = 28, black = 29, lost = 30, vagos = 2,
    hood = 34, marabunta = 41, sky = 52, sapphire = 52, yellow = 66,
    neutral = 26, contested = 1, owned = 4,
}

--- Radmap index -> RGBA (same bands grand_mechanic draws with).
Shared.ColourRGB = {
    [0] = { 220, 220, 220 }, [1] = { 255, 30, 56 }, [2] = { 16, 200, 110 },
    [3] = { 107, 50, 126 }, [4] = { 56, 110, 255 }, [5] = { 0, 178, 180 },
    [6] = { 220, 255, 20 }, [7] = { 255, 188, 0 }, [8] = { 255, 30, 56 },
    [9] = { 240, 160, 0 }, [25] = { 0, 255, 136 }, [26] = { 150, 150, 150 },
    [27] = { 142, 36, 170 }, [28] = { 0, 178, 180 }, [29] = { 255, 255, 255 },
    [30] = { 253, 216, 53 }, [34] = { 67, 160, 71 }, [41] = { 251, 140, 0 },
    [47] = { 60, 90, 140 }, [52] = { 0, 176, 255 }, [66] = { 216, 27, 96 },
}

function Shared.ColourOf(value, fallback)
    if type(value) == 'number' then return Shared.Clamp(math.floor(value), 0, 84) end
    if type(value) == 'string' then
        return Shared.ColourNames[value:lower()] or (Shared.ColourNames[fallback or 'grey']) or 26
    end
    return Shared.ColourNames[fallback or 'grey'] or 26
end

function Shared.RGBOf(index, alpha)
    local c = Shared.ColourRGB[tonumber(index) or 1] or { 255, 30, 56 }
    return c[1], c[2], c[3], math.floor(Shared.Clamp(alpha or 140, 0, 255))
end

--- #RRGGBB -> r,g,b (0..255)
function Shared.HexToRgb(hex)
    if type(hex) ~= 'string' then return 255, 30, 56 end
    local h = hex:gsub('^#', ''):gsub('%s', '')
    if #h ~= 6 then return 255, 30, 56 end
    return tonumber(h:sub(1, 2), 16) or 255, tonumber(h:sub(3, 4), 16) or 30, tonumber(h:sub(5, 6), 16) or 56
end

--- FiveM colour index -> chat code (^1 .. ^9) approximation.
function Shared.ChatCode(index)
    local map = { [0] = '^7', [1] = '^1', [2] = '^2', [3] = '^4', [4] = '^4', [5] = '^8',
        [6] = '^2', [7] = '^3', [8] = '^1', [9] = '^3', [25] = '^2', [26] = '^7',
        [27] = '^5', [29] = '^7', [30] = '^3', [34] = '^2', [41] = '^3', [52] = '^4', [66] = '^5' }
    return map[tonumber(index) or 1] or '^7'
end

function Shared.GangChatColour(gangKey)
    local g = Shared.Gang(gangKey)
    if not g then return '^7' end
    return Shared.ChatCode(g.blipColour)
end

-- ─── Identity / input sanitising ─────────────────────────────
function Shared.SanitizeCid(cid)
    if type(cid) ~= 'string' then return nil end
    local out = cid:gsub('%s', ''):gsub('[^%w]', '')
    if #out < 3 or #out > 20 then return nil end
    return out:upper()
end

function Shared.SanitizePlate(plate)
    if type(plate) ~= 'string' then return nil end
    local out = (plate:upper():gsub('%s', ''):gsub('[^%w]', '')):sub(1, 12)
    if #out < 2 then return nil end
    return out
end

function Shared.IsPlate(plate)
    local p = Shared.SanitizePlate(plate)
    if not p then return false end
    return p:match('^%w?%w?%d?%d?%d?%d?%w?%w?$') ~= nil
end

--- Free text -> safe single-line ASCII label of bounded length.
function Shared.SanitizeText(raw, maxLen)
    if type(raw) ~= 'string' then return nil end
    local out = raw:gsub('[\1-\31]', ''):gsub('[%^%[%]%{~}', ''):gsub('%s+', ' ')
    out = out:gsub('[^%g]', '')
    local limit = Shared.Clamp(maxLen or 48, 4, 96)
    if #out > limit then out = out:sub(1, limit) end
    if #out == 0 then return nil end
    return out
end

function Shared.SanitizeKey(raw)
    if type(raw) ~= 'string' then return nil end
    local out = raw:lower():gsub('[^%w]', '_'):sub(1, 32)
    if #out == 0 then return nil end
    return out
end

function Shared.ValidSource(src)
    return type(src) == 'number' and src > 0 and src < 65536
end

function Shared.ValidInt(value, lo, hi)
    local n = tonumber(value)
    if not n then return nil end
    n = math.floor(n)
    if n < lo or n > hi then return nil end
    return n
end

-- ─── Cooldown store ─────────────────────────────────────────
-- Keyed by any string; expiries tracked in ms of GetGameTimer so it
-- behaves the same on client and server and survives a paused tick.
local cooldowns = {}

local function now()
    return GetGameTimer and GetGameTimer() or 0
end

function Shared.Cooldown(key, durationSeconds)
    if type(key) ~= 'string' then return false end
    local entry = cooldowns[key]
    local t = now()
    if entry and entry.expires > t then
        return false, math.ceil((entry.expires - t) / 1000)
    end
    cooldowns[key] = { expires = t + (math.max(1, tonumber(durationSeconds) or 1) * 1000), set = t }
    return true
end

function Shared.CooldownLeft(key)
    local entry = cooldowns[type(key) == 'string' and key or '']
    if not entry then return 0 end
    local left = entry.expires - now()
    if left <= 0 then
        cooldowns[key] = nil
        return 0
    end
    return math.ceil(left / 1000)
end

--- Prepaid cooldown: set an expiry without a readiness check.
function Shared.SetCooldown(key, durationSeconds)
    if type(key) ~= 'string' then return end
    cooldowns[key] = { expires = now() + (math.max(1, tonumber(durationSeconds) or 1) * 1000), set = now() }
end

function Shared.ClearCooldown(key)
    if type(key) == 'string' then cooldowns[key] = nil end
end

function Shared.PruneCooldowns()
    local t = now()
    local removed = 0
    for k, v in pairs(cooldowns) do
        if not v or not v.expires or v.expires <= t then
            cooldowns[k] = nil
            removed = removed + 1
        end
    end
    return removed
end

-- ─── Logging ─────────────────────────────────────────────────
local TAG = ('[%s]'):format(Shared.Name)

function Shared.Log(...)
    local args = table.pack(...)
    local parts = {}
    for i = 1, args.n do parts[#parts + 1] = tostring(args[i]) end
    print(('%s %s'):format(TAG, table.concat(parts, ' ')))
end

function Shared.Warn(...)
    local args = table.pack(...)
    local parts = {}
    for i = 1, args.n do parts[#parts + 1] = tostring(args[i]) end
    print(('^3%s %s^7'):format(TAG, table.concat(parts, ' ')))
end

function Shared.Error(...)
    local args = table.pack(...)
    local parts = {}
    for i = 1, args.n do parts[#parts + 1] = tostring(args[i]) end
    print(('^1%s %s^7'):format(TAG, table.concat(parts, ' ')))
end

function Shared.Debug(...)
    if not (Config and Config.Debug) then return end
    Shared.Log('^2DBG^7', ...)
end

-- ─── Misc ────────────────────────────────────────────────────
function Shared.InList(list, value)
    for _, v in ipairs(list or {}) do
        if v == value then return true end
    end
    return false
end

function Shared.Keys(t)
    local out = {}
    for k in pairs(t or {}) do out[#out + 1] = k end
    table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
    return out
end

function Shared.DeepCopy(t)
    if type(t) ~= 'table' then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Shared.DeepCopy(v) end
    return out
end

function Shared.TableSize(t)
    local n = 0
    for _ in pairs(t or {}) do n = n + 1 end
    return n
end

return Shared
