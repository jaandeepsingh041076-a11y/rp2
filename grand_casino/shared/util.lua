-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/shared/util.lua
--  Shared utilities and guarded cross-resource calls
-- ─────────────────────────────────────────────────────────────

local Util = {}

-- Guarded export helper from BUILDCONTRACT.md
function Util.TryExport(res, name, ...)
    if GetResourceState(res) ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports[res][name](table.unpack(args, 1, args.n))
    end)
    return ok and result or nil
end

-- Get player identifier from source (server-side)
function Util.GetIdentifier(source)
    if source == nil then return nil end
    local result = Util.TryExport('grand_core', 'GetIdentifier', source)
    if result then return result end
    
    -- Fallback: try to get from characters table
    local player = GetPlayerName(source)
    if player then
        return GetPlayerIdentifierByType(source, 'license')
    end
    return nil
end

-- Get citizenid from source (server-side)
function Util.GetCitizenId(source)
    local result = Util.TryExport('grand_core', 'GetCitizenId', source)
    if result then return result end
    
    -- Fallback: extract from identifier
    local identifier = Util.GetIdentifier(source)
    if identifier then
        -- Convert license:license:xxxx to citizenid format
        return identifier:gsub('license:', ''):sub(1, 10)
    end
    return nil
end

-- Get player session (server-side)
function Util.GetSession(source)
    return Util.TryExport('grand_core', 'GetSession', source)
end

-- Get player money
function Util.GetMoney(source)
    local result = Util.TryExport('grand_core', 'GetMoney', source)
    if result then return result end
    
    -- Fallback: return empty money table
    return {cash = 0, bank = 0, crypto = 0}
end

-- Add money to player
function Util.AddMoney(source, kind, amount, reason)
    local result = Util.TryExport('grand_core', 'AddMoney', source, kind, amount, reason)
    if result then return result end
    
    -- Fallback: direct DB update would go here, but we should avoid
    return false
end

-- Remove money from player
function Util.RemoveMoney(source, kind, amount, reason)
    local result = Util.TryExport('grand_core', 'RemoveMoney', source, kind, amount, reason)
    if result then return result end
    
    -- Fallback: direct DB update would go here
    return false
end

-- Notify player
function Util.Notify(source, message, type)
    local result = Util.TryExport('grand_core', 'Notify', source, message, type)
    if result then return result end
    
    -- Fallback: trigger client event
    TriggerClientEvent('grand_casino:client:Notify', source, message, type)
end

-- Get player's grand coin balance via grand_coin export
function Util.GetCoinBalance(source)
    local result = Util.TryExport('grand_coin', 'Balance', source)
    if result then return tonumber(result) or 0 end
    return 0
end

-- Debit grand coins from player
function Util.DebitCoins(source, amount, reason)
    local result = Util.TryExport('grand_coin', 'Debit', source, amount, reason)
    if result then return result end
    return false
end

-- Credit grand coins to player
function Util.CreditCoins(source, amount, reason)
    local result = Util.TryExport('grand_coin', 'Credit', source, amount, reason)
    if result then return result end
    return false
end

-- Add blip via grand_mechanic
function Util.AddBlip(record)
    local result = Util.TryExport('grand_mechanic', 'AddBlip', record)
    if result then return result end
    
    -- Fallback: raw FiveM API
    local x, y, z = record.coords.x, record.coords.y, record.coords.z
    local blip = AddBlipForCoord(x, y, z)
    SetBlipSprite(blip, record.sprite or 1)
    SetBlipColour(blip, record.colour or 1)
    SetBlipScale(blip, record.scale or 0.8)
    SetBlipAsShortRange(blip, true)
    if record.label then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(record.label)
        EndTextCommandSetBlipName(blip)
    end
    return blip
end

-- Remove blip via grand_mechanic
function Util.RemoveBlip(id)
    local result = Util.TryExport('grand_mechanic', 'RemoveBlip', id)
    if result then return result end
    
    -- Fallback: we can't remove by ID without grand_mechanic
    -- This would require tracking blip handles
    return false
end

-- Clear blips with prefix via grand_mechanic
function Util.ClearBlips(prefix)
    local result = Util.TryExport('grand_mechanic', 'ClearBlips', prefix)
    if result then return result end
    return false
end

-- Distance calculation helper
function Util.GetDistance(coords1, coords2)
    if not coords1 or not coords2 then return 9999.0 end
    return #(vector3(coords1.x or coords1[1], coords1.y or coords1[2], coords1.z or coords1[3]) 
            - vector3(coords2.x or coords2[1], coords2.y or coords2[2], coords2.z or coords2[3]))
end

-- Table deep copy
function Util.DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[Util.DeepCopy(orig_key)] = Util.DeepCopy(orig_value)
        end
        setmetatable(copy, Util.DeepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    return copy
end

-- Validate number is within range
function Util.ValidateNumber(value, min, max, default)
    local num = tonumber(value)
    if not num then return default end
    if min and num < min then return min end
    if max and num > max then return max end
    return num
end

-- Format currency with commas
function Util.FormatCurrency(amount)
    if not amount then return '$0' end
    local formatted = tostring(math.floor(amount))
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return '$' .. formatted
end

-- Format grand coins
function Util.FormatCoins(amount)
    if not amount then return '0 GC' end
    local formatted = tostring(math.floor(amount))
    while true do
        formatted, k = string.gsub(formatted, '^(-?%d+)(%d%d%d)', '%1,%2')
        if k == 0 then break end
    end
    return formatted .. ' GC'
end

-- Generate unique round ID
function Util.GenerateRoundId()
    local time = os.time()
    local random = math.random(1000, 9999)
    return ('RND-%d-%d'):format(time, random)
end

-- Rate limiting helper
Util.RateLimits = {}
function Util.CheckRateLimit(source, key, limitSeconds)
    local identifier = Util.GetIdentifier(source)
    if not identifier then return false end
    
    local now = os.time()
    local cacheKey = identifier .. ':' .. key
    
    if not Util.RateLimits[cacheKey] or (now - Util.RateLimits[cacheKey]) > limitSeconds then
        Util.RateLimits[cacheKey] = now
        return true
    end
    return false
end

return Util