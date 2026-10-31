-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_coin/shared/util.lua
--  Shared helpers for Grand Coins. Loaded before every server
--  and client script; defines the global `Util` table.
--  Framework-agnostic: guarded grand_core exports only.
-- ─────────────────────────────────────────────────────────────

Util = Util or {}
local U = Util

U.Server = IsDuplicityVersion and IsDuplicityVersion() or false
U.Cooldowns = {}
U.Locks = {}
U.TxCounter = 0

-- ─── Guarded exports ─────────────────────────────────────────
--- Calls exports[res][name](...) only when the resource is
--- started. Never throws, returns nil on any failure.
function U.TryExport(res, name, ...)
    if type(res) ~= 'string' or type(name) ~= 'string' then return nil end
    if GetResourceState(res) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[res][name](table.unpack(args, 1, args.n))
    end)
    return ok and result or nil
end

-- ─── Logging ─────────────────────────────────────────────────
local levels = { debug = 1, info = 2, warn = 3, error = 4 }
local currentLevel = 2

function U.SetLogLevel(level)
    currentLevel = levels[tostring(level):lower()] or 2
end

function U.Log(level, message, ...)
    local lvl = tostring(level or 'info'):lower()
    if (levels[lvl] or 2) < currentLevel then return end
    local text = select('#', ...) > 0 and string.format(tostring(message), ...) or tostring(message)
    print(('^3[grand_coin]^7 %s'):format(text))
end

function U.Debug(...)
    if Config and Config.Debug then U.Log('debug', ...) end
end

-- ─── Identity ────────────────────────────────────────────────
function U.GetIdentifier(src)
    src = tonumber(src)
    if not src then return nil end
    local id = U.TryExport('grand_core', 'GetIdentifier', src)
    if type(id) == 'string' and id ~= '' then return id end
    return GetPlayerIdentifierByType(src, 'license')
end

function U.GetCitizenId(src)
    src = tonumber(src)
    if not src then return nil end
    local cid = U.TryExport('grand_core', 'GetCitizenId', src)
    if type(cid) == 'string' and cid ~= '' then return cid end
    return nil
end

--- Accepts either a server source (number) or a citizenid string
--- and always returns a citizenid (or nil).
function U.ResolveCitizenId(srcOrCid)
    if type(srcOrCid) == 'number' then return U.GetCitizenId(srcOrCid) end
    if type(srcOrCid) == 'string' and srcOrCid ~= '' then
        if srcOrCid:find('^![0-9]+$') then return nil end
        return srcOrCid
    end
    return nil
end

function U.GetSession(src)
    return U.TryExport('grand_core', 'GetSession', tonumber(src) or src)
end

-- ─── Notifications ───────────────────────────────────────────
--- Server: tries grand_core, then the client event.
--- Client: lib.notify when available, chat otherwise.
function U.Notify(target, message, kind)
    message = tostring(message or '')
    kind = kind or 'info'

    if U.Server then
        local src = tonumber(target)
        if not src then return end
        local sent = U.TryExport('grand_core', 'Notify', src, message, kind)
        if sent == nil then
            TriggerClientEvent('grand_coin:client:Notify', src, message, kind)
        end
        return
    end

    if GetResourceState('ox_lib') == 'started' then
        local ok = pcall(function()
            lib.notify({ description = message, type = kind })
        end)
        if ok then return end
    end

    local colours = {
        error = { 244, 67, 54 }, success = { 76, 175, 80 },
        warning = { 255, 193, 7 }, info = { 200, 210, 255 },
    }
    TriggerEvent('chat:addMessage', {
        color = colours[kind] or colours.info,
        multiline = true,
        args = { 'Grand Coins', message },
    })
end

-- ─── Number helpers ──────────────────────────────────────────
function U.Int(value)
    local n = tonumber(value)
    if not n or n ~= n or n == math.huge or n == -math.huge then return nil end
    return math.floor(n)
end

function U.Clamp(value, lo, hi)
    if lo and value < lo then value = lo end
    if hi and value > hi then value = hi end
    return value
end

--- Accepts "1500", "1.5k", "2m". Returns an integer or nil.
function U.ParseAmount(raw)
    if type(raw) == 'number' then return U.Int(raw) end
    if type(raw) ~= 'string' then return nil end
    local text = raw:lower():gsub('[$%s,]', '')
    local numberPart, suffix = text:match('^(%d+%.?%d*)([km]?)$')
    if not numberPart then return nil end
    local value = tonumber(numberPart)
    if not value then return nil end
    if suffix == 'k' then value = value * 1000 end
    if suffix == 'm' then value = value * 1000000 end
    return U.Int(value)
end

function U.Comma(amount)
    local formatted = tostring(math.floor(tonumber(amount) or 0))
    local sign = ''
    if formatted:sub(1, 1) == '-' then
        sign = '-'
        formatted = formatted:sub(2)
    end
    while true do
        local replaced, count = formatted:gsub('^(%d+)(%d%d%d)', '%1,%2')
        formatted = replaced
        if count == 0 then break end
    end
    return sign .. formatted
end

function U.Cash(amount)
    return '$' .. U.Comma(amount)
end

function U.Coins(amount)
    return U.Comma(amount) .. ' GC'
end

-- ─── Rate limits ─────────────────────────────────────────────
--- Returns true when the action is allowed and records it.
function U.RateLimit(key, seconds)
    local now = os.time()
    local until_ = U.Cooldowns[key]
    if until_ and now < until_ then return false, until_ - now end
    U.Cooldowns[key] = now + math.max(0, math.floor(tonumber(seconds) or 1))
    return true
end

function U.RateLimitLeft(key)
    local until_ = U.Cooldowns[key]
    if not until_ then return 0 end
    return math.max(0, until_ - os.time())
end

function U.ClearRateLimit(key)
    U.Cooldowns[key] = nil
end

function U.PruneCooldowns()
    local now = os.time()
    for key, until_ in pairs(U.Cooldowns) do
        if until_ <= now then U.Cooldowns[key] = nil end
    end
    for key, locked in pairs(U.Locks) do
        if locked == false then U.Locks[key] = nil end
    end
end

-- ─── Per-key mutex (single resource, single thread of logic) ──
--- Returns an unlock function, or nil when the key is busy.
function U.Lock(key)
    if U.Locks[key] then return nil end
    U.Locks[key] = true
    return function()
        U.Locks[key] = nil
    end
end

-- ─── Misc ────────────────────────────────────────────────────
function U.TxnId()
    U.TxCounter = (U.TxCounter + 1) % 100000
    return ('GC-%d-%06d'):format(os.time(), U.TxCounter)
end

function U.SanitizeText(raw, maxLen)
    if type(raw) ~= 'string' then return '' end
    local text = raw:gsub('[%c]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    return text:sub(1, maxLen or 190)
end

function U.SanitizeSlug(raw)
    if type(raw) ~= 'string' then return '' end
    return (raw:lower():gsub('[^%w_%-]', '')):sub(1, 64)
end

function U.IsOnline(src)
    src = tonumber(src)
    return src ~= nil and src > 0 and GetPlayerName(src) ~= nil
end

--- Looks a shop entry up by slug. Exposed for commands.
function U.FindShopItem(slug)
    slug = U.SanitizeSlug(slug)
    if slug == '' or not Config or not Config.Shop then return nil end
    for _, item in ipairs(Config.Shop.items or {}) do
        if item.slug == slug then return item end
    end
    return nil
end

return U
