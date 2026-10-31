-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/client/casino.lua
--  Client-side casino interactions and UI
-- ─────────────────────────────────────────────────────────────

local Config = require 'config'
local Util = require 'shared.util'

local Casino = {
    blips = {},
    markers = {},
    inCasino = false,
    currentGame = nil,
    balance = 0
}

-- Initialize client
function Casino.Initialize()
    -- Add casino blip
    Casino.blips.casino = Util.AddBlip({
        coords = Config.Casino.coords,
        sprite = Config.Blip.sprite,
        colour = Config.Blip.colour,
        scale = Config.Blip.scale,
        label = Config.Blip.label,
        range = Config.Blip.range,
        hidden = Config.Blip.hidden
    })
    
    -- Set up markers for game tables
    Casino.SetupMarkers()
    
    -- Start interaction thread
    Casino.StartInteractionThread()
    
    -- Start balance update thread
    Casino.StartBalanceThread()
    
    print('[grand_casino] Client initialized')
end

-- Set up markers for casino games
function Casino.SetupMarkers()
    -- Slot machines
    for i, coords in ipairs(Config.Casino.slotFloor) do
        Casino.markers['slot_' .. i] = {
            coords = coords,
            type = 'slots',
            label = 'Slot Machine',
            range = Config.Interaction.slotRange
        }
    end
    
    -- Blackjack tables
    for i, coords in ipairs(Config.Casino.tables.blackjack) do
        Casino.markers['bj_' .. i] = {
            coords = coords,
            type = 'blackjack',
            label = 'Blackjack Table',
            range = Config.Interaction.tableRange
        }
    end
    
    -- Roulette table
    Casino.markers.roulette = {
        coords = Config.Casino.tables.roulette[1],
        type = 'roulette',
        label = 'Roulette Table',
        range = Config.Interaction.tableRange
    }
    
    -- Coin flip area
    Casino.markers.coinflip = {
        coords = Config.Casino.tables.coinflip[1],
        type = 'coinflip',
        label = 'Coin Flip Challenge',
        range = Config.Interaction.tableRange
    }
    
    -- Wheel of Fortune
    Casino.markers.wheel = {
        coords = Config.Casino.wheel,
        type = 'wheel',
        label = 'Wheel of Fortune',
        range = Config.Interaction.wheelRange
    }
end

-- Main interaction thread
function Casino.StartInteractionThread()
    CreateThread(function()
        while true do
            local sleep = 1000
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            local inRange = false
            
            -- Check each marker
            for id, marker in pairs(Casino.markers) do
                local distance = Util.GetDistance(pos, marker.coords)
                
                if distance <= marker.range then
                    sleep = 0
                    inRange = true
                    
                    -- Draw marker
                    DrawMarker(1, marker.coords.x, marker.coords.y, marker.coords.z - 1.0,
                        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        1.5, 1.5, 0.5,
                        255, 30, 56, 100,
                        false, false, 2, false, nil, nil, false)
                    
                    -- Draw interaction text
                    Casino.DrawText3D(marker.coords.x, marker.coords.y, marker.coords.z + 0.5,
                        ('~%s~%s~n~~w~Press ~g~E~w~ to play'):format(
                            Casino.currentGame == marker.type and 'r' or 'g',
                            marker.label
                        ))
                    
                    -- Check for interaction
                    if IsControlJustReleased(0, 38) then -- E key
                        Casino.HandleInteraction(marker.type)
                    end
                end
            end
            
            -- Update casino state
            local casinoDistance = Util.GetDistance(pos, Config.Casino.coords)
            Casino.inCasino = casinoDistance <= 100.0
            
            Wait(sleep)
        end
    end)
end

-- Handle game interaction
function Casino.HandleInteraction(gameType)
    if Casino.currentGame == gameType then
        Casino.currentGame = nil
        return
    end
    
    Casino.currentGame = gameType
    
    if gameType == 'slots' then
        Casino.OpenSlotsMenu()
    elseif gameType == 'blackjack' then
        Casino.OpenBlackjackMenu()
    elseif gameType == 'roulette' then
        Casino.OpenRouletteMenu()
    elseif gameType == 'coinflip' then
        Casino.OpenCoinflipMenu()
    elseif gameType == 'wheel' then
        Casino.OpenWheelMenu()
    end
end

-- Open slots menu
function Casino.OpenSlotsMenu()
    local input = lib.inputDialog('Slot Machine', {
        {type = 'number', label = 'Bet Amount (GC)', required = true, 
         default = Config.Slots.minBet, min = Config.Slots.minBet, max = Config.Slots.maxBet},
        {type = 'number', label = 'Number of Spins', required = true, 
         default = 1, min = 1, max = 10}
    })
    
    if not input then return end
    
    local betAmount = input[1]
    local numSpins = input[2]
    
    if betAmount > Casino.balance then
        Util.Notify('Insufficient Grand Coins.', 'error')
        return
    end
    
    for i = 1, numSpins do
        TriggerServerEvent('grand_casino:server:PlaySlots', betAmount)
        Wait(1000) -- Small delay between spins
    end
end

-- Open blackjack menu
function Casino.OpenBlackjackMenu()
    local input = lib.inputDialog('Blackjack Table', {
        {type = 'number', label = 'Bet Amount (GC)', required = true,
         default = Config.Blackjack.minBet, min = Config.Blackjack.minBet, max = Config.Blackjack.maxBet}
    })
    
    if not input then return end
    
    local betAmount = input[1]
    
    if betAmount > Casino.balance then
        Util.Notify('Insufficient Grand Coins.', 'error')
        return
    end
    
    TriggerServerEvent('grand_casino:server:PlayBlackjack', betAmount, 'deal')
end

-- Open roulette menu
function Casino.OpenRouletteMenu()
    -- Simplified roulette UI - would be more complex in reality
    local betTypes = {
        {label = 'Straight (35:1)', value = 'straight'},
        {label = 'Split (17:1)', value = 'split'},
        {label = 'Street (11:1)', value = 'street'},
        {label = 'Corner (8:1)', value = 'corner'},
        {label = 'Line (5:1)', value = 'line'},
        {label = 'Dozen (2:1)', value = 'dozen'},
        {label = 'Column (2:1)', value = 'column'},
        {label = 'Red (1:1)', value = 'red'},
        {label = 'Black (1:1)', value = 'black'},
        {label = 'Odd (1:1)', value = 'odd'},
        {label = 'Even (1:1)', value = 'even'},
        {label = 'Low (1:1)', value = 'low'},
        {label = 'High (1:1)', value = 'high'}
    }
    
    local input = lib.inputDialog('Roulette', {
        {type = 'number', label = 'Bet Amount (GC)', required = true,
         default = Config.Roulette.minBet, min = Config.Roulette.minBet, max = Config.Roulette.maxBet},
        {type = 'select', label = 'Bet Type', required = true, options = betTypes},
        {type = 'input', label = 'Bet Details (number(s))', required = false,
         placeholder = 'e.g., 17 or "17,20" for split'}
    })
    
    if not input then return end
    
    local betAmount = input[1]
    local betType = input[2]
    local betDetails = input[3]
    
    if betAmount > Casino.balance then
        Util.Notify('Insufficient Grand Coins.', 'error')
        return
    end
    
    -- Parse bet details
    local details = nil
    if betDetails then
        if betType == 'straight' then
            details = tonumber(betDetails)
        elseif betType == 'split' or betType == 'corner' then
            details = {}
            for num in betDetails:gmatch('%d+') do
                table.insert(details, tonumber(num))
            end
        elseif betType == 'street' or betType == 'line' or betType == 'dozen' or betType == 'column' then
            details = tonumber(betDetails)
        end
    end
    
    TriggerServerEvent('grand_casino:server:PlayRoulette', betAmount, betType, details)
end

-- Open coin flip menu
function Casino.OpenCoinflipMenu()
    local input = lib.inputDialog('Coin Flip Challenge', {
        {type = 'number', label = 'Bet Amount (GC)', required = true,
         default = Config.Coinflip.minBet, min = Config.Coinflip.minBet, max = Config.Coinflip.maxBet},
        {type = 'number', label = 'Target Player ID', required = true, min = 1},
        {type = 'select', label = 'Your Call', required = true, options = {
            {label = 'Heads', value = 'heads'},
            {label = 'Tails', value = 'tails'}
        }}
    })
    
    if not input then return end
    
    local betAmount = input[1]
    local targetSource = input[2]
    local call = input[3]
    
    if betAmount > Casino.balance then
        Util.Notify('Insufficient Grand Coins.', 'error')
        return
    end
    
    TriggerServerEvent('grand_casino:server:PlayCoinflip', betAmount, targetSource, call)
end

-- Open wheel menu
function Casino.OpenWheelMenu()
    local input = lib.inputDialog('Wheel of Fortune', {
        {type = 'number', label = 'Bet Amount (GC)', required = true,
         default = Config.WheelOfFortune.minBet, min = Config.WheelOfFortune.minBet, 
         max = Config.WheelOfFortune.maxBet}
    })
    
    if not input then return end
    
    local betAmount = input[1]
    
    if betAmount > Casino.balance then
        Util.Notify('Insufficient Grand Coins.', 'error')
        return
    end
    
    TriggerServerEvent('grand_casino:server:PlayWheel', betAmount)
end

-- Draw 3D text
function Casino.DrawText3D(x, y, z, text)
    local onScreen, _x, _y = World3dToScreen2d(x, y, z)
    if onScreen then
        SetTextScale(Config.Interaction.drawTextScale)
        SetTextFont(Config.Interaction.drawTextFont)
        SetTextProportional(true)
        SetTextColour(table.unpack(Config.Interaction.drawTextColour))
        SetTextOutline()
        SetTextEntry('STRING')
        SetTextCentre(true)
        AddTextComponentString(text)
        DrawText(_x, _y)
    end
end

-- Update balance thread
function Casino.StartBalanceThread()
    CreateThread(function()
        while true do
            Casino.UpdateBalance()
            Wait(30000) -- Update every 30 seconds
        end
    end)
end

-- Update coin balance
function Casino.UpdateBalance()
    local newBalance = Util.GetCoinBalance(source)
    if newBalance ~= Casino.balance then
        Casino.balance = newBalance
        -- Could trigger HUD update here if HUD was allowed
    end
end

-- Event handlers for game results
RegisterNetEvent('grand_casino:client:SlotsResult', function(result)
    local message = ('Slot Machine: %s'):format(
        result.payout > result.bet and ('Won %s!'):format(Util.FormatCoins(result.payout - result.bet)) or
        ('Lost %s'):format(Util.FormatCoins(result.bet))
    )
    
    if result.jackpot then
        message = '🎰 JACKPOT! ' .. message
    end
    
    Util.Notify(message, result.payout > result.bet and 'success' or 'error')
    
    -- Show symbols
    local symbolText = ''
    for _, symbol in ipairs(result.symbols) do
        symbolText = symbolText .. symbol.name:upper() .. ' '
    end
    
    TriggerEvent('chat:addMessage', {
        color = {255, 30, 56},
        args = {'Slots', symbolText}
    })
end)

RegisterNetEvent('grand_casino:client:BlackjackResult', function(result)
    local message = ('Blackjack: %s'):format(
        result.payout > result.bet and ('Won %s!'):format(Util.FormatCoins(result.payout - result.bet)) or
        result.payout == result.bet and 'Push - bet returned' or
        ('Lost %s'):format(Util.FormatCoins(result.bet))
    )
    
    if result.playerBlackjack then
        message = '♠️ BLACKJACK! ' .. message
    end
    
    Util.Notify(message, result.payout > result.bet and 'success' or 
                result.payout == result.bet and 'info' or 'error')
    
    -- Show hands
    local playerHand = ''
    for _, card in ipairs(result.playerHand) do
        playerHand = playerHand .. card.code .. ' '
    end
    
    local dealerHand = ''
    for _, card in ipairs(result.dealerHand) do
        dealerHand = dealerHand .. card.code .. ' '
    end
    
    TriggerEvent('chat:addMessage', {
        color = {255, 30, 56},
        multiline = true,
        args = {'Blackjack', ('Your hand: %s (%d)\nDealer hand: %s (%d)'):format(
            playerHand, result.playerValue, dealerHand, result.dealerValue)}
    })
end)

RegisterNetEvent('grand_casino:client:RouletteResult', function(result)
    local message = ('Roulette: %s landed on %d - %s'):format(
        result.betType, result.winningNumber,
        result.wins and ('Won %s!'):format(Util.FormatCoins(result.payout - result.bet)) or
        ('Lost %s'):format(Util.FormatCoins(result.bet))
    )
    
    Util.Notify(message, result.wins and 'success' or 'error')
end)

RegisterNetEvent('grand_casino:client:CoinflipResult', function(result)
    local message = ('Coin Flip: %s called %s, result was %s - %s'):format(
        result.call == 'heads' and 'Heads' or 'Tails',
        result.call,
        result.result,
        result.winnerSource == source and ('Won %s!'):format(Util.FormatCoins(result.payout - result.bet)) or
        ('Lost %s'):format(Util.FormatCoins(result.bet))
    )
    
    Util.Notify(message, result.winnerSource == source and 'success' or 'error')
end)

RegisterNetEvent('grand_casino:client:WheelResult', function(result)
    local message = ('Wheel of Fortune: %s - %s'):format(
        result.segment.label,
        result.payout > result.bet and ('Won %s!'):format(Util.FormatCoins(result.payout - result.bet)) or
        ('Lost %s'):format(Util.FormatCoins(result.bet))
    )
    
    if result.jackpotWon then
        message = '🎯 JACKPOT! ' .. message
    end
    
    Util.Notify(message, result.payout > result.bet and 'success' or 'error')
end)

RegisterNetEvent('grand_casino:client:ReceiveStats', function(stats)
    local message = string.format([[
        ^1CASINO STATISTICS (30 days)^7
        ^3Total Rounds: ^7%d
        ^3Total Bet: ^7%s
        ^3Total Won: ^7%s
        ^3Net Result: ^7%s
        ^3Last Played: ^7%s
    ]], stats.total_rounds, Util.FormatCoins(stats.total_bet),
       Util.FormatCoins(stats.total_won), Util.FormatCoins(stats.net_result),
       stats.last_played or 'Never')
    
    TriggerEvent('chat:addMessage', {
        color = {255, 30, 56},
        multiline = true,
        args = {'Casino Stats', message}
    })
end)

RegisterNetEvent('grand_casino:client:ReceiveJackpot', function(jackpot)
    local message = string.format([[
        ^1WHEEL OF FORTUNE JACKPOT^7
        ^3Current Amount: ^7%s
        ^3Last Winner: ^7%s
        ^3Last Win Amount: ^7%s
        ^3Last Win Time: ^7%s
    ]], Util.FormatCoins(jackpot.current_amount),
       jackpot.last_winner or 'None',
       jackpot.last_winner and Util.FormatCoins(jackpot.last_win_amount) or '—',
       jackpot.last_win_time or 'Never')
    
    TriggerEvent('chat:addMessage', {
        color = {255, 30, 56},
        multiline = true,
        args = {'Jackpot', message}
    })
end)

RegisterNetEvent('grand_casino:client:ReceiveRoundVerification', function(round)
    local result = json.decode(round.result)
    local message = string.format([[
        ^1ROUND VERIFICATION^7
        ^3Round ID: ^7%s
        ^3Game: ^7%s
        ^3Bet: ^7%s
        ^3Payout: ^7%s
        ^3Seed: ^7%s
        ^3Time: ^7%s
    ]], round.round_id, round.game_type, Util.FormatCoins(round.bet_amount),
       Util.FormatCoins(round.payout), round.seed,
       round.created_at)
    
    TriggerEvent('chat:addMessage', {
        color = {255, 30, 56},
        multiline = true,
        args = {'Round Verification', message}
    })
end)

RegisterNetEvent('grand_casino:client:Notify', function(message, type)
    Util.Notify(source, message, type)
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        -- Clear blips
        Util.ClearBlips('casino_')
        
        -- Clear any active game state
        Casino.currentGame = nil
    end
end)

-- Initialize when resource starts
AddEventHandler('onClientResourceStart', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        Casino.Initialize()
    end
end)