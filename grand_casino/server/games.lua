-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_casino/server/games.lua
--  Game logic implementations: slots, blackjack, roulette, etc.
-- ─────────────────────────────────────────────────────────────

local Config = require 'config'
local Util = require 'shared.util'
local RNG = require 'server.rng'
local Database = require 'server.database'

local Games = {}

-- Slots game
function Games.PlaySlots(source, betAmount)
    local citizenId = Util.GetCitizenId(source)
    if not citizenId then
        Util.Notify(source, 'Unable to verify your identity.', 'error')
        return false
    end
    
    -- Check player exclusion
    if Database.IsPlayerExcluded(citizenId) then
        Util.Notify(source, 'You are excluded from casino games.', 'error')
        return false
    end
    
    -- Validate bet amount
    betAmount = Util.ValidateNumber(betAmount, Config.Slots.minBet, Config.Slots.maxBet, Config.Slots.minBet)
    
    -- Check player balance
    local balance = Util.GetCoinBalance(source)
    if balance < betAmount then
        Util.Notify(source, 'Insufficient Grand Coins.', 'error')
        return false
    end
    
    -- Check rate limit
    if not Util.CheckRateLimit(source, 'slots', Config.Limits.coolingOffPeriod) then
        Util.Notify(source, 'Please wait before playing again.', 'warning')
        return false
    end
    
    -- Check loss limits
    local hourlyLoss = Database.GetPlayerHourlyLoss(citizenId)
    if hourlyLoss >= Config.Limits.maxHourlyLoss then
        Util.Notify(source, 'You have reached your hourly loss limit.', 'warning')
        return false
    end
    
    local dailyLoss = Database.GetPlayerDailyLoss(citizenId)
    if dailyLoss >= Config.Limits.maxDailyLoss then
        Util.Notify(source, 'You have reached your daily loss limit.', 'warning')
        return false
    end
    
    -- Generate round ID and seed
    local roundId = Util.GenerateRoundId()
    local seed = RNG.GenerateSeed(roundId)
    
    -- Generate symbols
    local symbols = RNG.GenerateSlotSymbols(seed, Config.Slots.symbols, Config.Slots.reels)
    
    -- Calculate payout
    local payout = 0
    local winMultiplier = 1
    
    -- Check for jackpot (three sevens)
    local jackpot = true
    for _, symbol in ipairs(symbols) do
        if symbol.name ~= 'seven' then
            jackpot = false
            break
        end
    end
    
    if jackpot then
        winMultiplier = Config.Slots.jackpotMultiplier
        payout = betAmount * winMultiplier
    else
        -- Calculate line payout (simplified: all reels same symbol)
        local firstSymbol = symbols[1].name
        local sameSymbol = true
        for i = 2, #symbols do
            if symbols[i].name ~= firstSymbol then
                sameSymbol = false
                break
            end
        end
        
        if sameSymbol then
            for _, symbol in ipairs(Config.Slots.symbols) do
                if symbol.name == firstSymbol then
                    winMultiplier = symbol.payout
                    payout = betAmount * winMultiplier
                    break
                end
            end
        end
    end
    
    -- Apply house edge
    if payout > 0 and not jackpot then
        payout = math.floor(payout * (1 - Config.Slots.houseEdge))
    end
    
    -- Record round
    Database.RecordRound(roundId, 'slots', citizenId, betAmount, 'coins', seed, {
        symbols = symbols,
        winMultiplier = winMultiplier,
        jackpot = jackpot
    }, payout)
    
    -- Handle currency
    local success = false
    if payout > 0 then
        -- Player won
        success = Util.CreditCoins(source, payout - betAmount, 'Slots win: ' .. roundId)
        if success then
            Util.Notify(source, ('You won %s!'):format(Util.FormatCoins(payout)), 'success')
        end
    else
        -- Player lost
        success = Util.DebitCoins(source, betAmount, 'Slots loss: ' .. roundId)
        if success then
            Util.Notify(source, ('You lost %s.'):format(Util.FormatCoins(betAmount)), 'error')
        end
    end
    
    -- Record bet
    if success then
        Database.RecordBet(roundId, citizenId, 'slots', betAmount, {
            symbols = symbols,
            winMultiplier = winMultiplier,
            jackpot = jackpot
        })
        
        -- Update session
        local session = Database.GetActiveSession(citizenId)
        if session then
            Database.EndSession(session.id, session.total_bet + betAmount, 
                session.total_won + math.max(0, payout - betAmount),
                session.net_result + (payout - betAmount))
        else
            Database.StartSession(citizenId)
            Database.EndSession(1, betAmount, math.max(0, payout - betAmount), payout - betAmount)
        end
    end
    
    return success, {
        roundId = roundId,
        symbols = symbols,
        bet = betAmount,
        payout = payout,
        winMultiplier = winMultiplier,
        jackpot = jackpot,
        seed = seed
    }
end

-- Blackjack game
function Games.PlayBlackjack(source, betAmount, action, handIndex)
    local citizenId = Util.GetCitizenId(source)
    if not citizenId then
        Util.Notify(source, 'Unable to verify your identity.', 'error')
        return false
    end
    
    -- Check player exclusion
    if Database.IsPlayerExcluded(citizenId) then
        Util.Notify(source, 'You are excluded from casino games.', 'error')
        return false
    end
    
    -- Validate bet amount
    betAmount = Util.ValidateNumber(betAmount, Config.Blackjack.minBet, Config.Blackjack.maxBet, Config.Blackjack.minBet)
    
    -- Check player balance
    local balance = Util.GetCoinBalance(source)
    if balance < betAmount then
        Util.Notify(source, 'Insufficient Grand Coins.', 'error')
        return false
    end
    
    -- Check rate limit
    if not Util.CheckRateLimit(source, 'blackjack', Config.Limits.coolingOffPeriod) then
        Util.Notify(source, 'Please wait before playing again.', 'warning')
        return false
    end
    
    -- Check loss limits
    local hourlyLoss = Database.GetPlayerHourlyLoss(citizenId)
    if hourlyLoss >= Config.Limits.maxHourlyLoss then
        Util.Notify(source, 'You have reached your hourly loss limit.', 'warning')
        return false
    end
    
    -- Generate round ID and seed
    local roundId = Util.GenerateRoundId()
    local seed = RNG.GenerateSeed(roundId)
    
    -- Generate deck
    local deck = RNG.GenerateDeck(seed, Config.Blackjack.decks)
    
    -- Initial deal
    local playerHand = { table.remove(deck), table.remove(deck) }
    local dealerHand = { table.remove(deck), table.remove(deck) }
    
    -- Calculate hand value
    local function CalculateHandValue(hand)
        local value = 0
        local aces = 0
        
        for _, card in ipairs(hand) do
            value = value + card.points
            if card.value == 'A' then
                aces = aces + 1
            end
        end
        
        -- Adjust aces from 11 to 1 if needed
        while value > 21 and aces > 0 do
            value = value - 10
            aces = aces - 1
        end
        
        return value
    end
    
    -- Game state
    local gameState = {
        deck = deck,
        playerHand = playerHand,
        dealerHand = dealerHand,
        playerValue = CalculateHandValue(playerHand),
        dealerValue = CalculateHandValue(dealerHand),
        playerBusted = false,
        dealerBusted = false,
        playerBlackjack = false,
        dealerBlackjack = false,
        action = action or 'deal',
        handIndex = handIndex or 1
    }
    
    -- Check for blackjack
    if gameState.playerValue == 21 and #playerHand == 2 then
        gameState.playerBlackjack = true
    end
    if gameState.dealerValue == 21 and #dealerHand == 2 then
        gameState.dealerBlackjack = true
    end
    
    -- Handle actions
    if action == 'hit' then
        local newCard = table.remove(deck)
        table.insert(playerHand, newCard)
        gameState.playerValue = CalculateHandValue(playerHand)
        gameState.playerBusted = gameState.playerValue > 21
        
    elseif action == 'stand' then
        -- Dealer plays
        while gameState.dealerValue < 17 do
            local newCard = table.remove(deck)
            table.insert(dealerHand, newCard)
            gameState.dealerValue = CalculateHandValue(dealerHand)
        end
        gameState.dealerBusted = gameState.dealerValue > 21
        
    elseif action == 'double' and Config.Blackjack.doubleAllowed then
        betAmount = betAmount * 2
        local newCard = table.remove(deck)
        table.insert(playerHand, newCard)
        gameState.playerValue = CalculateHandValue(playerHand)
        gameState.playerBusted = gameState.playerValue > 21
        
        if not gameState.playerBusted then
            -- Dealer plays
            while gameState.dealerValue < 17 do
                local newCard = table.remove(deck)
                table.insert(dealerHand, newCard)
                gameState.dealerValue = CalculateHandValue(dealerHand)
            end
            gameState.dealerBusted = gameState.dealerValue > 21
        end
        
    elseif action == 'split' and Config.Blackjack.splitAllowed then
        -- Simplified split logic (one split only)
        if #playerHand == 2 and playerHand[1].value == playerHand[2].value then
            gameState.splitHands = {
                { playerHand[1], table.remove(deck) },
                { playerHand[2], table.remove(deck) }
            }
            gameState.currentSplit = 1
        end
    end
    
    -- Determine outcome
    local payout = 0
    local winType = 'loss'
    
    if gameState.playerBusted then
        payout = 0
        winType = 'bust'
    elseif gameState.dealerBusted then
        payout = betAmount * 2  -- Even money
        winType = 'dealer_bust'
    elseif gameState.playerBlackjack and not gameState.dealerBlackjack then
        payout = math.floor(betAmount * Config.Blackjack.blackjackPayout)
        winType = 'blackjack'
    elseif gameState.playerValue > gameState.dealerValue then
        payout = betAmount * 2  -- Even money
        winType = 'win'
    elseif gameState.playerValue == gameState.dealerValue then
        payout = betAmount  -- Push
        winType = 'push'
    else
        payout = 0
        winType = 'loss'
    end
    
    -- Apply house edge (except on blackjack)
    if winType ~= 'blackjack' and payout > betAmount then
        payout = math.floor(payout * (1 - Config.Blackjack.houseEdge))
    end
    
    -- Record round
    Database.RecordRound(roundId, 'blackjack', citizenId, betAmount, 'coins', seed, {
        playerHand = playerHand,
        dealerHand = dealerHand,
        playerValue = gameState.playerValue,
        dealerValue = gameState.dealerValue,
        playerBusted = gameState.playerBusted,
        dealerBusted = gameState.dealerBusted,
        playerBlackjack = gameState.playerBlackjack,
        dealerBlackjack = gameState.dealerBlackjack,
        winType = winType
    }, payout)
    
    -- Handle currency
    local success = false
    if payout > betAmount then
        -- Player won
        local winAmount = payout - betAmount
        success = Util.CreditCoins(source, winAmount, 'Blackjack ' .. winType .. ': ' .. roundId)
        if success then
            Util.Notify(source, ('You won %s!'):format(Util.FormatCoins(winAmount)), 'success')
        end
    elseif payout == betAmount then
        -- Push, return bet
        success = true
        Util.Notify(source, 'Push - bet returned.', 'info')
    else
        -- Player lost
        success = Util.DebitCoins(source, betAmount, 'Blackjack ' .. winType .. ': ' .. roundId)
        if success then
            Util.Notify(source, ('You lost %s.'):format(Util.FormatCoins(betAmount)), 'error')
        end
    end
    
    -- Record bet
    if success then
        Database.RecordBet(roundId, citizenId, 'blackjack', betAmount, {
            action = action,
            winType = winType,
            playerHand = playerHand,
            dealerHand = dealerHand
        })
        
        -- Update session
        local session = Database.GetActiveSession(citizenId)
        if session then
            Database.EndSession(session.id, session.total_bet + betAmount, 
                session.total_won + math.max(0, payout - betAmount),
                session.net_result + (payout - betAmount))
        else
            Database.StartSession(citizenId)
            Database.EndSession(1, betAmount, math.max(0, payout - betAmount), payout - betAmount)
        end
    end
    
    return success, {
        roundId = roundId,
        playerHand = playerHand,
        dealerHand = dealerHand,
        playerValue = gameState.playerValue,
        dealerValue = gameState.dealerValue,
        playerBusted = gameState.playerBusted,
        dealerBusted = gameState.dealerBusted,
        playerBlackjack = gameState.playerBlackjack,
        dealerBlackjack = gameState.dealerBlackjack,
        winType = winType,
        bet = betAmount,
        payout = payout,
        seed = seed
    }
end

-- Roulette game
function Games.PlayRoulette(source, betAmount, betType, betDetails)
    local citizenId = Util.GetCitizenId(source)
    if not citizenId then
        Util.Notify(source, 'Unable to verify your identity.', 'error')
        return false
    end
    
    -- Check player exclusion
    if Database.IsPlayerExcluded(citizenId) then
        Util.Notify(source, 'You are excluded from casino games.', 'error')
        return false
    end
    
    -- Validate bet amount
    betAmount = Util.ValidateNumber(betAmount, Config.Roulette.minBet, Config.Roulette.maxBet, Config.Roulette.minBet)
    
    -- Check player balance
    local balance = Util.GetCoinBalance(source)
    if balance < betAmount then
        Util.Notify(source, 'Insufficient Grand Coins.', 'error')
        return false
    end
    
    -- Check rate limit
    if not Util.CheckRateLimit(source, 'roulette', Config.Limits.coolingOffPeriod) then
        Util.Notify(source, 'Please wait before playing again.', 'warning')
        return false
    end
    
    -- Check loss limits
    local hourlyLoss = Database.GetPlayerHourlyLoss(citizenId)
    if hourlyLoss >= Config.Limits.maxHourlyLoss then
        Util.Notify(source, 'You have reached your hourly loss limit.', 'warning')
        return false
    end
    
    -- Validate bet type
    if not Config.Roulette.bets[betType] then
        Util.Notify(source, 'Invalid bet type.', 'error')
        return false
    end
    
    -- Generate round ID and seed
    local roundId = Util.GenerateRoundId()
    local seed = RNG.GenerateSeed(roundId)
    
    -- Generate roulette number (0-36)
    local winningNumber = RNG.GenerateRouletteNumber(seed)
    
    -- Determine if bet wins
    local wins = false
    local payoutMultiplier = Config.Roulette.bets[betType].payout
    
    if betType == 'straight' then
        wins = (tonumber(betDetails) == winningNumber)
    elseif betType == 'split' then
        local numbers = betDetails or {}
        wins = (numbers[1] == winningNumber or numbers[2] == winningNumber)
    elseif betType == 'street' then
        local row = betDetails or 1
        local start = (row - 1) * 3 + 1
        wins = (winningNumber >= start and winningNumber <= start + 2)
    elseif betType == 'corner' then
        local corners = betDetails or {}
        for _, num in ipairs(corners) do
            if num == winningNumber then
                wins = true
                break
            end
        end
    elseif betType == 'line' then
        local rows = betDetails or {1, 2}
        local start1 = (rows[1] - 1) * 3 + 1
        local start2 = (rows[2] - 1) * 3 + 1
        wins = (winningNumber >= start1 and winningNumber <= start1 + 2) or
               (winningNumber >= start2 and winningNumber <= start2 + 2)
    elseif betType == 'dozen' then
        local dozen = betDetails or 1
        wins = (winningNumber >= (dozen - 1) * 12 + 1 and winningNumber <= dozen * 12)
    elseif betType == 'column' then
        local column = betDetails or 1
        local columnNumbers = {}
        for i = column, 36, 3 do
            table.insert(columnNumbers, i)
        end
        wins = (winningNumber == 0 and false) or (table.contains(columnNumbers, winningNumber))
    elseif betType == 'red' then
        local redNumbers = {1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36}
        wins = table.contains(redNumbers, winningNumber)
    elseif betType == 'black' then
        local blackNumbers = {2, 4, 6, 8, 10, 11, 13, 15, 17, 20, 22, 24, 26, 28, 29, 31, 33, 35}
        wins = table.contains(blackNumbers, winningNumber)
    elseif betType == 'odd' then
        wins = (winningNumber ~= 0 and winningNumber % 2 == 1)
    elseif betType == 'even' then
        wins = (winningNumber ~= 0 and winningNumber % 2 == 0)
    elseif betType == 'low' then
        wins = (winningNumber >= 1 and winningNumber <= 18)
    elseif betType == 'high' then
        wins = (winningNumber >= 19 and winningNumber <= 36)
    end
    
    -- Calculate payout
    local payout = 0
    if wins then
        payout = math.floor(betAmount * (payoutMultiplier + 1))
        
        -- Apply house edge
        payout = math.floor(payout * (1 - Config.Roulette.houseEdge))
    end
    
    -- Record round
    Database.RecordRound(roundId, 'roulette', citizenId, betAmount, 'coins', seed, {
        winningNumber = winningNumber,
        betType = betType,
        betDetails = betDetails,
        wins = wins,
        payoutMultiplier = payoutMultiplier
    }, payout)
    
    -- Handle currency
    local success = false
    if payout > 0 then
        -- Player won
        success = Util.CreditCoins(source, payout - betAmount, 'Roulette win: ' .. roundId)
        if success then
            Util.Notify(source, ('You won %s!'):format(Util.FormatCoins(payout)), 'success')
        end
    else
        -- Player lost
        success = Util.DebitCoins(source, betAmount, 'Roulette loss: ' .. roundId)
        if success then
            Util.Notify(source, ('You lost %s.'):format(Util.FormatCoins(betAmount)), 'error')
        end
    end
    
    -- Record bet
    if success then
        Database.RecordBet(roundId, citizenId, 'roulette', betAmount, {
            betType = betType,
            betDetails = betDetails,
            winningNumber = winningNumber,
            wins = wins
        })
        
        -- Update session
        local session = Database.GetActiveSession(citizenId)
        if session then
            Database.EndSession(session.id, session.total_bet + betAmount, 
                session.total_won + math.max(0, payout - betAmount),
                session.net_result + (payout - betAmount))
        else
            Database.StartSession(citizenId)
            Database.EndSession(1, betAmount, math.max(0, payout - betAmount), payout - betAmount)
        end
    end
    
    return success, {
        roundId = roundId,
        winningNumber = winningNumber,
        betType = betType,
        betDetails = betDetails,
        wins = wins,
        bet = betAmount,
        payout = payout,
        seed = seed
    }
end

-- Coin flip game (peer-to-peer)
function Games.PlayCoinflip(source, betAmount, targetSource, call)
    local citizenId = Util.GetCitizenId(source)
    if not citizenId then
        Util.Notify(source, 'Unable to verify your identity.', 'error')
        return false
    end
    
    -- Check player exclusion
    if Database.IsPlayerExcluded(citizenId) then
        Util.Notify(source, 'You are excluded from casino games.', 'error')
        return false
    end
    
    -- Validate bet amount
    betAmount = Util.ValidateNumber(betAmount, Config.Coinflip.minBet, Config.Coinflip.maxBet, Config.Coinflip.minBet)
    
    -- Check player balance
    local balance = Util.GetCoinBalance(source)
    if balance < betAmount then
        Util.Notify(source, 'Insufficient Grand Coins.', 'error')
        return false
    end
    
    -- Check target player
    if not targetSource or targetSource == source then
        Util.Notify(source, 'Invalid target player.', 'error')
        return false
    end
    
    local targetCitizenId = Util.GetCitizenId(targetSource)
    if not targetCitizenId then
        Util.Notify(source, 'Target player not found.', 'error')
        return false
    end
    
    -- Check target balance
    local targetBalance = Util.GetCoinBalance(targetSource)
    if targetBalance < betAmount then
        Util.Notify(source, 'Target player has insufficient Grand Coins.', 'error')
        return false
    end
    
    -- Validate call (heads/tails)
    call = call and call:lower() or 'heads'
    if call ~= 'heads' and call ~= 'tails' then
        Util.Notify(source, 'Call must be "heads" or "tails".', 'error')
        return false
    end
    
    -- Generate round ID and seed
    local roundId = Util.GenerateRoundId()
    local seed = RNG.GenerateSeed(roundId)
    
    -- Generate coin flip
    local result = RNG.GenerateCoinFlip(seed)
    local resultText = result and 'heads' or 'tails'
    
    -- Determine winner
    local winnerSource = nil
    local loserSource = nil
    
    if (call == 'heads' and result) or (call == 'tails' and not result) then
        winnerSource = source
        loserSource = targetSource
    else
        winnerSource = targetSource
        loserSource = source
    end
    
    -- Calculate payout (minus house rake)
    local rake = math.floor(betAmount * Config.Coinflip.houseRake)
    local payout = (betAmount * 2) - rake
    
    -- Record round (from challenger's perspective)
    Database.RecordRound(roundId, 'coinflip', citizenId, betAmount, 'coins', seed, {
        call = call,
        result = resultText,
        winner = (winnerSource == source),
        opponent = targetCitizenId,
        rake = rake
    }, (winnerSource == source) and (payout - betAmount) or 0)
    
    -- Handle currency transfers
    local success = false
    
    -- Debit both players
    local debit1 = Util.DebitCoins(source, betAmount, 'Coinflip bet: ' .. roundId)
    local debit2 = Util.DebitCoins(targetSource, betAmount, 'Coinflip bet: ' .. roundId)
    
    if debit1 and debit2 then
        -- Credit winner (net amount after rake)
        local winAmount = payout - betAmount
        success = Util.CreditCoins(winnerSource, winAmount, 'Coinflip win: ' .. roundId)
        
        if success then
            Util.Notify(source, ('Coin flip: %s! You %s.'):format(resultText, 
                winnerSource == source and 'won' or 'lost'), 
                winnerSource == source and 'success' or 'error')
            Util.Notify(targetSource, ('Coin flip: %s! You %s.'):format(resultText,
                winnerSource == targetSource and 'won' or 'lost'),
                winnerSource == targetSource and 'success' or 'error')
        end
    end
    
    -- Record bet
    if success then
        Database.RecordBet(roundId, citizenId, 'coinflip', betAmount, {
            call = call,
            result = resultText,
            winner = (winnerSource == source),
            opponent = targetCitizenId,
            rake = rake
        })
        
        -- Update sessions for both players
        local session1 = Database.GetActiveSession(citizenId)
        if session1 then
            Database.EndSession(session1.id, session1.total_bet + betAmount, 
                session1.total_won + (winnerSource == source and winAmount or 0),
                session1.net_result + (winnerSource == source and winAmount or -betAmount))
        else
            Database.StartSession(citizenId)
            Database.EndSession(1, betAmount, winnerSource == source and winAmount or 0, 
                winnerSource == source and winAmount or -betAmount)
        end
        
        local session2 = Database.GetActiveSession(targetCitizenId)
        if session2 then
            Database.EndSession(session2.id, session2.total_bet + betAmount, 
                session2.total_won + (winnerSource == targetSource and winAmount or 0),
                session2.net_result + (winnerSource == targetSource and winAmount or -betAmount))
        else
            Database.StartSession(targetCitizenId)
            Database.EndSession(1, betAmount, winnerSource == targetSource and winAmount or 0, 
                winnerSource == targetSource and winAmount or -betAmount)
        end
    else
        -- Refund if something went wrong
        if debit1 then Util.CreditCoins(source, betAmount, 'Coinflip refund') end
        if debit2 then Util.CreditCoins(targetSource, betAmount, 'Coinflip refund') end
    end
    
    return success, {
        roundId = roundId,
        call = call,
        result = resultText,
        winnerSource = winnerSource,
        bet = betAmount,
        payout = payout,
        rake = rake,
        seed = seed
    }
end

-- Wheel of Fortune
function Games.PlayWheel(source, betAmount)
    local citizenId = Util.GetCitizenId(source)
    if not citizenId then
        Util.Notify(source, 'Unable to verify your identity.', 'error')
        return false
    end
    
    -- Check player exclusion
    if Database.IsPlayerExcluded(citizenId) then
        Util.Notify(source, 'You are excluded from casino games.', 'error')
        return false
    end
    
    -- Validate bet amount
    betAmount = Util.ValidateNumber(betAmount, Config.WheelOfFortune.minBet, Config.WheelOfFortune.maxBet, Config.WheelOfFortune.minBet)
    
    -- Check player balance
    local balance = Util.GetCoinBalance(source)
    if balance < betAmount then
        Util.Notify(source, 'Insufficient Grand Coins.', 'error')
        return false
    end
    
    -- Check rate limit
    if not Util.CheckRateLimit(source, 'wheel', Config.Limits.coolingOffPeriod) then
        Util.Notify(source, 'Please wait before playing again.', 'warning')
        return false
    end
    
    -- Check loss limits
    local hourlyLoss = Database.GetPlayerHourlyLoss(citizenId)
    if hourlyLoss >= Config.Limits.maxHourlyLoss then
        Util.Notify(source, 'You have reached your hourly loss limit.', 'warning')
        return false
    end
    
    -- Generate round ID and seed
    local roundId = Util.GenerateRoundId()
    local seed = RNG.GenerateSeed(roundId)
    
    -- Get current jackpot
    local jackpot = Database.GetJackpot('wheel')
    if not jackpot then
        Util.Notify(source, 'Jackpot system unavailable.', 'error')
        return false
    end
    
    -- Generate wheel segment
    local segment = RNG.GenerateWheelSegment(seed, Config.WheelOfFortune.segments)
    
    -- Calculate payout
    local payout = 0
    local winMultiplier = segment.multiplier
    
    if winMultiplier > 0 then
        payout = math.floor(betAmount * winMultiplier)
        
        -- Apply house edge
        payout = math.floor(payout * (1 - Config.WheelOfFortune.houseEdge))
        
        -- Check for jackpot segment
        if segment.label == 'JACKPOT' then
            payout = payout + jackpot.current_amount
            Database.WinJackpot('wheel', citizenId, jackpot.current_amount)
        end
    end
    
    -- Update jackpot (contribute portion of bet)
    local jackpotContribution = math.floor(betAmount * 0.01)  -- 1% to jackpot
    Database.UpdateJackpot('wheel', jackpotContribution)
    
    -- Record round
    Database.RecordRound(roundId, 'wheel', citizenId, betAmount, 'coins', seed, {
        segment = segment,
        winMultiplier = winMultiplier,
        jackpotContribution = jackpotContribution,
        jackpotWon = (segment.label == 'JACKPOT')
    }, payout)
    
    -- Handle currency
    local success = false
    if payout > 0 then
        -- Player won
        success = Util.CreditCoins(source, payout - betAmount, 'Wheel win: ' .. roundId)
        if success then
            Util.Notify(source, ('You won %s!'):format(Util.FormatCoins(payout)), 'success')
        end
    else
        -- Player lost
        success = Util.DebitCoins(source, betAmount, 'Wheel loss: ' .. roundId)
        if success then
            Util.Notify(source, ('You lost %s.'):format(Util.FormatCoins(betAmount)), 'error')
        end
    end
    
    -- Record bet
    if success then
        Database.RecordBet(roundId, citizenId, 'wheel', betAmount, {
            segment = segment,
            winMultiplier = winMultiplier,
            jackpotContribution = jackpotContribution,
            jackpotWon = (segment.label == 'JACKPOT')
        })
        
        -- Update session
        local session = Database.GetActiveSession(citizenId)
        if session then
            Database.EndSession(session.id, session.total_bet + betAmount, 
                session.total_won + math.max(0, payout - betAmount),
                session.net_result + (payout - betAmount))
        else
            Database.StartSession(citizenId)
            Database.EndSession(1, betAmount, math.max(0, payout - betAmount), payout - betAmount)
        end
    end
    
    return success, {
        roundId = roundId,
        segment = segment,
        winMultiplier = winMultiplier,
        bet = betAmount,
        payout = payout,
        jackpotContribution = jackpotContribution,
        jackpotWon = (segment.label == 'JACKPOT'),
        seed = seed
    }
end

-- Helper function for table.contains (missing in Lua)
function table.contains(table, element)
    for _, value in pairs(table) do
        if value == element then
            return true
        end
    end
    return false
end

return Games