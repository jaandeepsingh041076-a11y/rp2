-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_coin/client/coins.lua
--  Headless client: balances, shop lists, quotes and exchange
--  points on the map. NO NUI - chat, markers and GrandBlips.
-- ─────────────────────────────────────────────────────────────

GrandCoinClient = GrandCoinClient or {}
local C = GrandCoinClient

C.Balance = 0
C.Shop = Config.Shop
C.Blips = {}
C.UsingEngine = false
C.Ready = false

local PREFIX = (Config.Blips and Config.Blips.prefix) or 'coin_'

-- ─── Blip engine ─────────────────────────────────────────────
local function engine(name, ...)
    if GetResourceState('grand_mechanic') ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports['grand_mechanic'][name](table.unpack(args, 1, args.n))
    end)
    return ok and result or nil
end

local function addExchangeBlips()
    if not Config.Blips.enabled then return end

    for _, point in ipairs(Config.Blips.locations or {}) do
        local id = PREFIX .. point.id
        local coords = point.coords

        local engineId = engine('AddBlip', {
            id = id,
            coords = coords,
            sprite = point.sprite or 277,
            colour = point.colour or 'gold',
            scale = 0.72,
            label = point.label or 'Grand Coins',
            range = Config.Blips.distanceCull or 1200.0,
            short = false,
        })

        if engineId then
            C.UsingEngine = true
            C.Blips[point.id] = { engine = true, id = engineId }
        else
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, point.sprite or 277)
            SetBlipColour(blip, 46) -- gold
            SetBlipScale(blip, 0.72)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(tostring(point.label or 'Grand Coins'))
            EndTextCommandSetBlipName(blip)
            C.Blips[point.id] = blip
        end
    end
end

local function clearBlips()
    for _, handle in pairs(C.Blips) do
        if type(handle) == 'table' and handle.engine then
            engine('RemoveBlip', handle.id)
        elseif type(handle) == 'number' then
            RemoveBlip(handle)
        end
    end
    C.Blips = {}
end

-- ─── State events ────────────────────────────────────────────
RegisterNetEvent('grand_coin:client:Balance', function(balance)
    C.Balance = tonumber(balance) or 0
end)

RegisterNetEvent('grand_coin:client:Shop', function(shop)
    C.Shop = shop or Config.Shop
    if not shop then return end

    TriggerEvent('chat:addMessage', {
        color = { 255, 200, 60 },
        multiline = true,
        args = { 'Grand Coin Shop', ('%d items. /coinbuy <slug> [qty] | /coins for balance')
            :format(#(shop.items or {})) },
    })
end)

RegisterNetEvent('grand_coin:client:Quote', function(quote, direction)
    if not quote then return end
    local text = quote.valid
        and ('%s -> %s; fee %s'):format(Util.Coins(quote.coins), Util.Cash(quote.cash), Util.Coins(quote.fee))
        or ('Unavailable: %s'):format(tostring(quote.reason or 'invalid amount'))
    TriggerEvent('chat:addMessage', {
        color = { 200, 220, 255 }, multiline = false,
        args = { 'Quote', text },
    })
end)

RegisterNetEvent('grand_coin:client:Purchased', function(slug, quantity, txn, detail)
    TriggerEvent('chat:addMessage', {
        color = { 120, 220, 140 }, multiline = true,
        args = { 'Purchase', ('%dx %s delivered (%s)'):format(
            tonumber(quantity) or 1, tostring(slug), tostring(detail or txn or 'ok')) },
    })
    TriggerServerEvent('grand_coin:server:GetBalance')
end)

RegisterNetEvent('grand_coin:client:History', function(rows)
    if not rows or #rows == 0 then
        Util.Notify('No coin transactions yet', 'info')
        return
    end
    for _, row in ipairs(rows) do
        local amount = tonumber(row.change_amount) or 0
        TriggerEvent('chat:addMessage', {
            color = amount >= 0 and { 120, 220, 140 } or { 255, 160, 120 },
            args = { tostring(row.created_at), ('%s%s - %s'):format(
                amount >= 0 and '+' or '', Util.Coins(amount),
                tostring(row.reason or row.transaction_type)) },
        })
    end
end)

RegisterNetEvent('grand_coin:client:Purchases', function(rows)
    if not rows or #rows == 0 then
        Util.Notify('No shop purchases yet', 'info')
        return
    end
    for _, row in ipairs(rows) do
        TriggerEvent('chat:addMessage', {
            color = { 200, 210, 255 },
            args = { tostring(row.created_at), ('%dx %s - %s (%s)'):format(
                tonumber(row.quantity) or 1, tostring(row.item_name),
                Util.Coins(row.total_cost), tostring(row.delivery_status)) },
        })
    end
end)

RegisterNetEvent('grand_coin:client:Notify', function(message, kind)
    Util.Notify(message, kind)
end)

-- ─── Exchange point markers ──────────────────────────────────
CreateThread(function()
    addExchangeBlips()

    while true do
        local sleep = 700
        if Config.Blips.enabled then
            local coords = GetEntityCoords(PlayerPedId())
            for _, point in ipairs(Config.Blips.locations or {}) do
                local p = point.coords
                local flat = #(vector2(coords.x, coords.y) - vector2(p.x, p.y))
                if flat <= 22.0 then
                    sleep = 0
                    DrawMarker(1, p.x, p.y, p.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                        2.2, 2.2, 1.0, 255, 200, 60, 130, false, true, 2, false, nil, nil, false)

                    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(p.x, p.y, p.z + 0.6)
                    if onScreen then
                        SetTextScale(0.33, 0.33)
                        SetTextFont(4)
                        SetTextProportional(1)
                        SetTextColour(255, 210, 80, 235)
                        SetTextOutline()
                        SetTextEntry('STRING')
                        AddTextComponentString(('%s - /coins'):format(tostring(point.label)))
                        DrawText(sx, sy)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ─── Player commands (client mirrors for quick help) ─────────
RegisterCommand('coinhelp', function()
    TriggerEvent('chat:addMessage', {
        color = { 255, 200, 60 }, multiline = true,
        args = { 'Grand Coins', table.concat({
            ('/%s - balance'):format(Config.Commands.balance),
            ('/%s - item list'):format(Config.Commands.shop),
            ('/%s <slug> [qty] - buy'):format(Config.Commands.buy),
            ('/%s <cash> - buy coins'):format(Config.Commands.convert),
            ('/%s <coins> - cash out'):format(Config.Commands.cashout),
            ('/%s <id> <amount> - send'):format(Config.Commands.give),
            '/coinhistory [limit]',
            '/coinquote <amount> [in|out]',
        }, '\n') },
    })
end, false)

-- ─── Lifecycle ───────────────────────────────────────────────
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    CreateThread(function()
        Wait(2000)
        C.Ready = true
        TriggerServerEvent('grand_coin:server:Ready')
    end)
end)

AddEventHandler('onClientResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    clearBlips()
    engine('ClearBlips', PREFIX)
end)

-- ─── Client exports ──────────────────────────────────────────
exports('GetBalance', function() return C.Balance end)
exports('GetShop', function() return C.Shop end)

return C
