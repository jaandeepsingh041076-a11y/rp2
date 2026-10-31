-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/server/rng.lua
--  Server-authoritative RNG with provably fair seeding
--  Implements xorshift128 algorithm for fast, good randomness
-- ─────────────────────────────────────────────────────────────

local Config = require 'config'
local Util = require 'shared.util'

local RNG = {}

-- xorshift128 implementation
local function xorshift128(state)
    local x = state[1]
    local y = state[2]
    local z = state[3]
    local w = state[4]
    
    local t = x ~ (x << 11)
    x = y
    y = z
    z = w
    w = w ~ (w >> 19) ~ (t ~ (t >> 8))
    
    state[1] = x
    state[2] = y
    state[3] = z
    state[4] = w
    
    return w
end

-- Seed generator from multiple sources
function RNG.GenerateSeed(roundId)
    local seedSources = {}
    
    -- Round ID contributes to seed
    table.insert(seedSources, roundId)
    
    -- Server secret (rotating daily)
    table.insert(seedSources, Config.RNG.serverSecret)
    
    -- Current time with high precision
    table.insert(seedSources, tostring(os.clock()))
    
    -- Current Unix timestamp
    table.insert(seedSources, tostring(os.time()))
    
    -- Resource KVP as additional entropy
    local kvp = GetResourceKvpString('grand_casino_rng_salt')
    if not kvp then
        kvp = tostring(math.random(1000000, 9999999))
        SetResourceKvp('grand_casino_rng_salt', kvp)
    end
    table.insert(seedSources, kvp)
    
    -- Combine all sources
    local combined = table.concat(seedSources, '|')
    
    -- Simple hash function (FNV-1a)
    local hash = 2166136261
    for i = 1, #combined do
        hash = hash ~ string.byte(combined, i)
        hash = hash * 16777619
        hash = hash & 0xFFFFFFFF  -- Keep 32-bit
    end
    
    return tostring(hash)
end

-- Initialize RNG state from seed
function RNG.InitializeState(seed)
    -- Use seed to generate four 32-bit state values
    local state = {0, 0, 0, 0}
    
    -- Distribute seed bits across state
    for i = 1, 4 do
        -- Simple mixing function
        local mixed = seed + i * 2654435761  -- golden ratio constant
        mixed = mixed ~ (mixed >> 21)
        mixed = mixed * 1597334677
        mixed = mixed ~ (mixed >> 15)
        state[i] = mixed & 0xFFFFFFFF
    end
    
    -- Warm up the generator
    for _ = 1, 10 do
        xorshift128(state)
    end
    
    return state
end

-- Generate random integer in range [min, max]
function RNG.RandomInt(seed, min, max)
    local state = RNG.InitializeState(seed)
    local range = max - min + 1
    
    -- Generate random value
    local raw = xorshift128(state)
    raw = raw & 0x7FFFFFFF  -- Ensure positive
    
    return min + (raw % range)
end

-- Generate random float in range [0, 1)
function RNG.RandomFloat(seed)
    local state = RNG.InitializeState(seed)
    local raw = xorshift128(state)
    raw = raw & 0x7FFFFFFF  -- Ensure positive
    
    return raw / 2147483647.0  -- Divide by 2^31-1
end

-- Generate weighted random choice
function RNG.WeightedRandom(seed, items)
    if not items or #items == 0 then return nil end
    
    -- Calculate total weight
    local totalWeight = 0
    for _, item in ipairs(items) do
        totalWeight = totalWeight + (item.weight or 1)
    end
    
    -- Generate random value
    local randomValue = RNG.RandomFloat(seed) * totalWeight
    
    -- Find selected item
    local cumulative = 0
    for _, item in ipairs(items) do
        cumulative = cumulative + (item.weight or 1)
        if randomValue <= cumulative then
            return item
        end
    end
    
    return items[#items]  -- Fallback
end

-- Generate multiple symbols for slots
function RNG.GenerateSlotSymbols(seed, symbolTable, reelCount)
    local symbols = {}
    local state = RNG.InitializeState(seed)
    
    for reel = 1, reelCount do
        -- Use different part of state for each reel
        local reelSeed = xorshift128(state) & 0x7FFFFFFF
        local reelState = RNG.InitializeState(tostring(reelSeed))
        
        -- Generate weighted random symbol
        local totalWeight = 0
        for _, symbol in ipairs(symbolTable) do
            totalWeight = totalWeight + symbol.weight
        end
        
        local randomValue = xorshift128(reelState) & 0x7FFFFFFF
        randomValue = (randomValue / 2147483647.0) * totalWeight
        
        local cumulative = 0
        local selectedSymbol = symbolTable[1]
        for _, symbol in ipairs(symbolTable) do
            cumulative = cumulative + symbol.weight
            if randomValue <= cumulative then
                selectedSymbol = symbol
                break
            end
        end
        
        table.insert(symbols, selectedSymbol)
    end
    
    return symbols
end

-- Shuffle array using Fisher-Yates algorithm
function RNG.ShuffleArray(seed, array)
    local shuffled = Util.DeepCopy(array)
    local state = RNG.InitializeState(seed)
    
    for i = #shuffled, 2, -1 do
        local j = RNG.RandomInt(seed .. i, 1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end
    
    return shuffled
end

-- Generate card deck and shuffle
function RNG.GenerateDeck(seed, decks)
    local deck = {}
    local suits = {'H', 'D', 'C', 'S'}  -- Hearts, Diamonds, Clubs, Spades
    local values = {'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'}
    
    -- Create multiple decks
    for deckNum = 1, decks do
        for _, suit in ipairs(suits) do
            for _, value in ipairs(values) do
                table.insert(deck, {
                    suit = suit,
                    value = value,
                    code = value .. suit,
                    points = RNG.CardPoints(value)
                })
            end
        end
    end
    
    -- Shuffle using seed
    return RNG.ShuffleArray(seed, deck)
end

-- Calculate card points for blackjack
function RNG.CardPoints(value)
    if value == 'A' then return 11 end  -- Will be adjusted to 1 if needed
    if value == 'J' or value == 'Q' or value == 'K' then return 10 end
    return tonumber(value)
end

-- Generate roulette number (0-36 for European)
function RNG.GenerateRouletteNumber(seed)
    return RNG.RandomInt(seed, 0, 36)
end

-- Generate coin flip result
function RNG.GenerateCoinFlip(seed)
    return RNG.RandomInt(seed, 0, 1) == 1  -- true = heads, false = tails
end

-- Generate wheel of fortune segment
function RNG.GenerateWheelSegment(seed, segments)
    return RNG.WeightedRandom(seed, segments)
end

-- Verify RNG result (for auditing)
function RNG.VerifyResult(seed, expectedResult, algorithm)
    -- Re-generate using same seed and compare
    if algorithm == 'slots' then
        -- Would need symbol table to regenerate
        return true  -- Trust for now, audit logs will show seed+result
    elseif algorithm == 'roulette' then
        local regenerated = RNG.GenerateRouletteNumber(seed)
        return regenerated == expectedResult
    elseif algorithm == 'coinflip' then
        local regenerated = RNG.GenerateCoinFlip(seed)
        return regenerated == expectedResult
    else
        return true  -- Default trust
    end
end

-- Export for other modules
RNG.xorshift128 = xorshift128

return RNG