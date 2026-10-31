-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/server/main.lua
--  Main server module - event handlers and commands
-- ─────────────────────────────────────────────────────────────

local Config = require 'config'
local Util = require 'shared.util'
local Database = require 'server.database'
local Games = require 'server.games'

local Casino = {}

-- Initialize resource
function Casino.Initialize()
    Database.Initialize()
    
    -- Set up cleanup thread
    CreateThread(function()
        while true do
            Wait(3600000)  -- Every hour
            Database.CleanupOldData()
        end
    end)
    
    print('[grand_casino] Resource initialized')
end

-- Event handlers
RegisterNetEvent('grand_casino:server:PlaySlots', function(betAmount)
    local source = source
    local success, result = Games.PlaySlots(source, betAmount)
    
    if success then
        TriggerClientEvent('grand_casino:client:SlotsResult', source, result)
    end
end)

RegisterNetEvent('grand_casino:server:PlayBlackjack', function(betAmount, action, handIndex)
    local source = source
    local success, result = Games.PlayBlackjack(source, betAmount, action, handIndex)
    
    if success then
        TriggerClientEvent('grand_casino:client:BlackjackResult', source, result)
    end
end)

RegisterNetEvent('grand_casino:server:PlayRoulette', function(betAmount, betType, betDetails)
    local source = source
    local success, result = Games.PlayRoulette(source, betAmount, betType, betDetails)
    
    if success then
        TriggerClientEvent('grand_casino:client:RouletteResult', source, result)
    end
end)

RegisterNetEvent('grand_casino:server:PlayCoinflip', function(betAmount, targetSource, call)
    local source = source
    local success, result = Games.PlayCoinflip(source, betAmount, targetSource, call)
    
    if success then
        TriggerClientEvent('grand_casino:client:CoinflipResult', source, result)
        if targetSource and result.winnerSource then
            TriggerClientEvent('grand_casino:client:CoinflipResult', targetSource, result)
        end
    end
end)

RegisterNetEvent('grand_casino:server:PlayWheel', function(betAmount)
    local source = source
    local success, result = Games.PlayWheel(source, betAmount)
    
    if success then
        TriggerClientEvent('grand_casino:client:WheelResult', source, result)
    end
end)

-- Player self-exclusion
RegisterNetEvent('grand_casino:server:SelfExclude', function(hours, reason)
    local source = source
    local citizenId = Util.GetCitizenId(source)
    
    if not citizenId then
        Util.Notify(source, 'Unable to verify your identity.', 'error')
        return
    end
    
    -- Validate hours (0 = permanent)
    hours = tonumber(hours) or 0
    local valid = false
    for _, period in ipairs(Config.Limits.selfExclusionDuration) do
        if period.hours == hours then
            valid = true
            break
        end
    end
    
    if not valid then
        Util.Notify(source, 'Invalid exclusion period.', 'error')
        return
    end
    
    -- Add exclusion
    local success = Database.AddExclusion(citizenId, 'self', hours, reason or 'Self-excluded', nil)
    
    if success then
        if hours == 0 then
            Util.Notify(source, 'You have permanently excluded yourself from casino games.', 'warning')
        else
            Util.Notify(source, ('You have excluded yourself from casino games for %d hours.'):format(hours), 'warning')
        end
    else
        Util.Notify(source, 'Failed to process exclusion request.', 'error')
    end
end)

-- Get player stats
RegisterNetEvent('grand_casino:server:GetStats', function()
    local source = source
    local citizenId = Util.GetCitizenId(source)
    
    if not citizenId then
        Util.Notify(source, 'Unable to verify your identity.', 'error')
        return
    end
    
    local stats = Database.GetPlayerStats(citizenId, 30)
    TriggerClientEvent('grand_casino:client:ReceiveStats', source, stats)
end)

-- Get jackpot info
RegisterNetEvent('grand_casino:server:GetJackpot', function()
    local source = source
    local jackpot = Database.GetJackpot('wheel')
    
    if jackpot then
        TriggerClientEvent('grand_casino:client:ReceiveJackpot', source, jackpot)
    else
        Util.Notify(source, 'Jackpot information unavailable.', 'error')
    end
end)

-- Verify round (for auditing)
RegisterNetEvent('grand_casino:server:VerifyRound', function(roundId)
    local source = source
    local round = Database.GetRound(roundId)
    
    if round then
        TriggerClientEvent('grand_casino:client:ReceiveRoundVerification', source, round)
    else
        Util.Notify(source, 'Round not found.', 'error')
    end
end)

-- Admin commands
RegisterNetEvent('grand_casino:server:AdminExclude', function(targetCitizenId, hours, reason)
    local source = source
    
    -- Check admin permissions (simplified - would need integration with admin system)
    local session = Util.GetSession(source)
    if not session or not session.job or session.job ~= 'admin' then
        Util.Notify(source, 'Insufficient permissions.', 'error')
        return
    end
    
    local success = Database.AddExclusion(targetCitizenId, 'admin', hours, reason, session.citizenid)
    
    if success then
        Util.Notify(source, ('Player %s excluded for %d hours.'):format(targetCitizenId, hours), 'success')
    else
        Util.Notify(source, 'Failed to exclude player.', 'error')
    end
end)

RegisterNetEvent('grand_casino:server:AdminRemoveExclusion', function(targetCitizenId)
    local source = source
    
    -- Check admin permissions
    local session = Util.GetSession(source)
    if not session or not session.job or session.job ~= 'admin' then
        Util.Notify(source, 'Insufficient permissions.', 'error')
        return
    end
    
    local success = Database.RemoveExclusion(targetCitizenId)
    
    if success then
        Util.Notify(source, ('Exclusion removed for player %s.'):format(targetCitizenId), 'success')
    else
        Util.Notify(source, 'Failed to remove exclusion.', 'error')
    end
end)

-- Console commands
RegisterCommand('casino_stats', function(source, args)
    if source == 0 then
        -- Console command
        local days = tonumber(args[1]) or 7
        print(('Casino statistics for last %d days:'):format(days))
        
        -- Would implement actual stats query here
        print('Stats command placeholder')
    end
end, true)

RegisterCommand('casino_cleanup', function(source, args)
    if source == 0 then
        Database.CleanupOldData()
        print('[grand_casino] Cleanup completed')
    end
end, true)

RegisterCommand('casino_jackpot', function(source, args)
    if source == 0 then
        local jackpot = Database.GetJackpot('wheel')
        if jackpot then
            print(('Wheel jackpot: $%d'):format(jackpot.current_amount))
            if jackpot.last_winner then
                print(('Last winner: %s ($%d)'):format(jackpot.last_winner, jackpot.last_win_amount))
            end
        end
    end
end, true)

-- Player commands (chat-based)
RegisterCommand('casino', function(source, args)
    local message = [[
        ^1CASINO GAMES^7
        ^3/slots [bet]^7 - Play slots (bet: 10-1000 GC)
        ^3/bj [bet]^7 - Play blackjack
        ^3/hit^7 / ^3/stand^7 / ^3/double^7 - Blackjack actions
        ^3/roulette [bet] [type] [pick]^7 - Play roulette
        ^3/coinflip [bet] [playerid] [heads/tails]^7 - Challenge player
        ^3/wheel [bet]^7 - Spin Wheel of Fortune
        ^3/selfexclude [hours]^7 - Self-exclude from casino
        ^3/jackpot^7 - Check jackpot amount
        ^3/casinostats^7 - Your casino statistics
    ]]
    
    TriggerEvent('chat:addMessage', source, {
        color = {255, 30, 56},
        multiline = true,
        args = {'Casino', message}
    })
end, false)

RegisterCommand('slots', function(source, args)
    local betAmount = tonumber(args[1]) or Config.Slots.minBet
    TriggerEvent('grand_casino:server:PlaySlots', betAmount)
end, false)

RegisterCommand('bj', function(source, args)
    local betAmount = tonumber(args[1]) or Config.Blackjack.minBet
    TriggerEvent('grand_casino:server:PlayBlackjack', betAmount, 'deal')
end, false)

RegisterCommand('hit', function(source, args)
    TriggerEvent('grand_casino:server:PlayBlackjack', nil, 'hit')
end, false)

RegisterCommand('stand', function(source, args)
    TriggerEvent('grand_casino:server:PlayBlackjack', nil, 'stand')
end, false)

RegisterCommand('double', function(source, args)
    TriggerEvent('grand_casino:server:PlayBlackjack', nil, 'double')
end, false)

RegisterCommand('roulette', function(source, args)
    if #args < 2 then
        Util.Notify(source, 'Usage: /roulette [bet] [type] [pick]', 'error')
        return
    end
    
    local betAmount = tonumber(args[1]) or Config.Roulette.minBet
    local betType = args[2]
    local betDetails = args[3]
    
    TriggerEvent('grand_casino:server:PlayRoulette', betAmount, betType, betDetails)
end, false)

RegisterCommand('coinflip', function(source, args)
    if #args < 3 then
        Util.Notify(source, 'Usage: /coinflip [bet] [playerid] [heads/tails]', 'error')
        return
    end
    
    local betAmount = tonumber(args[1]) or Config.Coinflip.minBet
    local targetSource = tonumber(args[2])
    local call = args[3]
    
    TriggerEvent('grand_casino:server:PlayCoinflip', betAmount, targetSource, call)
end, false)

RegisterCommand('wheel', function(source, args)
    local betAmount = tonumber(args[1]) or Config.WheelOfFortune.minBet
    TriggerEvent('grand_casino:server:PlayWheel', betAmount)
end, false)

RegisterCommand('selfexclude', function(source, args)
    local hours = tonumber(args[1]) or 24
    local reason = args[2] or 'Self-exclusion'
    
    TriggerEvent('grand_casino:server:SelfExclude', hours, reason)
end, false)

RegisterCommand('jackpot', function(source, args)
    TriggerEvent('grand_casino:server:GetJackpot')
end, false)

RegisterCommand('casinostats', function(source, args)
    TriggerEvent('grand_casino:server:GetStats')
end, false)

-- Initialize on resource start
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Casino.Initialize()
    end
end)

-- Export functions for other resources
exports('GetPlayerExcluded', function(citizenId)
    return Database.IsPlayerExcluded(citizenId)
end)

exports('GetPlayerStats', function(citizenId, days)
    return Database.GetPlayerStats(citizenId, days)
end)

exports('GetJackpotAmount', function(jackpotType)
    local jackpot = Database.GetJackpot(jackpotType or 'wheel')
    return jackpot and jackpot.current_amount or 0
end)

return Casino