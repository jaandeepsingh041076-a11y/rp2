-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/server/tools.lua
--  Inventory authority: part consumption, tool validation, toolbox
--  purchasing, hoarding stock, and the "did the fitting succeed" roll.
--  Talks to grand_inventory's exports; falls back to the JSON column.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local DB = Mechanic.DB
local Jobs = Mechanic.Jobs

local Tools = {}
Mechanic.Tools = Tools

local Notify = Jobs.Notify
local CitizenId = Jobs.CitizenId

local function TryExportMarkDirty(source)
    pcall(function()
        if GetResourceState('grand_core') == 'started' then exports['grand_core'].MarkDirty(source) end
    end)
end
Tools.MarkDirty = TryExportMarkDirty

-- ─── Inventory bridge ─────────────────────────────────────────
local function Inv(name, ...)
    if GetResourceState('grand_inventory') ~= 'started' then return nil end
    local args = table.pack(...)
    local ok, result = pcall(function()
        return exports['grand_inventory'][name](table.unpack(args, 1, args.n))
    end)
    if not ok then
        DB.Log('warn', ('grand_inventory:%s -> %s'):format(name, tostring(result)))
        return nil
    end
    return result
end
Tools.Inv = Inv

local function HasItem(source, item, count)
    count = count or 1
    local n = Inv('CountItem', source, item)
    if type(n) == 'number' then return n >= count end

    -- fallback: read characters.inventory directly
    local cid = Jobs.CitizenId(source)
    if not cid then return false end
    local row = DB.Character(cid)
    if not row then return false end
    local list = Shared.DB.Decode(row.inventory, {})
    local total = 0
    for _, slot in pairs(list) do
        if type(slot) == 'table' and slot.name == item then
            total = total + (tonumber(slot.count) or 1)
        end
    end
    return total >= count
end
Tools.HasItem = HasItem

local function RemoveItem(source, item, count)
    count = count or 1
    local removed = Inv('RemoveItem', source, item, count, 'mechanic')
    if removed ~= nil then return removed ~= false end

    local cid = Jobs.CitizenId(source)
    if not cid then return false end
    local row = DB.Character(cid)
    if not row then return false end
    local list = Shared.DB.Decode(row.inventory, {})
    local left = count
    for _, slot in pairs(list) do
        if type(slot) == 'table' and slot.name == item and left > 0 then
            local have = tonumber(slot.count) or 1
            local take = math.min(have, left)
            slot.count = have - take
            left = left - take
            if slot.count <= 0 then slot.count = nil slot.name = nil end
        end
    end
    if left > 0 then return false end
    MySQL.update.await('UPDATE characters SET inventory = ? WHERE citizenid = ?',
        { json.encode(list), cid })
    TryExportMarkDirty(source)
    return true
end
Tools.RemoveItem = RemoveItem

local function AddItem(source, item, count, meta)
    count = count or 1
    local ok = Inv('AddItem', source, item, count, meta, 'mechanic')
    if ok ~= nil then return ok ~= false end

    local cid = Jobs.CitizenId(source)
    if not cid then return false end
    local row = DB.Character(cid)
    if not row then return false end
    local list = Shared.DB.Decode(row.inventory, {})
    for i = 1, 60 do
        if not list[i] or not list[i].name then
            list[i] = { slot = i, name = item, count = count, durability = 100, meta = meta }
            MySQL.update.await('UPDATE characters SET inventory = ? WHERE citizenid = ?',
                { json.encode(list), cid })
            return true
        end
    end
    return false
end
Tools.AddItem = AddItem

local function TryExportMarkDirty(source)
    pcall(function()
        if GetResourceState('grand_core') == 'started' then exports['grand_core'].MarkDirty(source) end
    end)
end
Tools.MarkDirty = TryExportMarkDirty

-- ─── Part stock held at a site ────────────────────────────────
local Stock = {}   -- ['hoarding:grille_benny'] = { part = qty }
Tools.Stock = Stock

local function StockKey(siteId)
    for _, site in ipairs(Config.Locations) do
        if site.id == siteId then return site.storage end
    end
    return 'hoarding:' .. tostring(siteId)
end

function Tools.GetStock(siteId)
    local key = StockKey(siteId)
    if not Stock[key] then Stock[key] = {} end
    return Stock[key]
end

function Tools.Restock(siteId, part, qty)
    local def = Config.Parts[part]
    if not def then return false end
    local stock = Tools.GetStock(siteId)
    stock[part] = (stock[part] or 0) + math.max(0, math.floor(qty or 0))
    return stock[part]
end

function Tools.TakeStock(siteId, part, qty)
    local stock = Tools.GetStock(siteId)
    qty = math.max(1, math.floor(qty or 1))
    if (stock[part] or 0) < qty then return false end
    stock[part] = stock[part] - qty
    return true
end

CreateThread(function()
    -- default bench stock so a fresh server is immediately usable
    for _, site in ipairs(Config.Locations) do
        if site.kind == 'hoarding' or site.kind == 'towing' then
            local stock = Tools.GetStock(site.id)
            stock.battery, stock.tires_set, stock.glass = 6, 5, 4
            stock.radiators, stock.brakes, stock.suspension = 3, 3, 2
            stock.panel_front, stock.panel_rear = 2, 2
            if site.kind == 'towing' then stock.winch = 4 end
        end
    end
end)

-- ─── Purchase a part from a site's catalogue ─────────────────
function Tools.BuyPart(source, siteId, part)
    local def = Config.Parts[part]
    if not def then return false, 'unknown-part' end
    if def.sell == 0 then return false, 'not-for-sale' end

    local price = math.floor(def.sell)
    if Jobs.Money(source, 'cash') < price then return false, 'no-cash' end

    if not Jobs.Take(source, 'cash', price, 'part:' .. part) then return false, 'payment-failed' end

    if not AddItem(source, def.item, 1, { site = siteId }) then
        Jobs.Pay(source, 'cash', price, 'refund')
        return false, 'no-space'
    end

    DB.LogTampering(Jobs.CitizenId(source), 'PART-' .. part:upper(), 'purchase', siteId, false)
    return true, { price = price, part = part }
end

function Tools.BuyTool(source, toolKey)
    local def = Config.Tools[toolKey]
    if not def then return false, 'unknown-tool' end
    if HasItem(source, def.item, 1) then return false, 'already-owned' end

    local price = math.floor((def.price or ({ toolbox = 620, wrench = 240, diag_tablet = 1450,
        jack_stand = 380, welder = 890, lockpick_set = 540 })[toolKey] or 400))
    if Jobs.Money(source, 'cash') < price then return false, 'no-cash' end
    if not Jobs.Take(source, 'cash', price, 'tool:' .. toolKey) then return false, 'payment-failed' end
    if not AddItem(source, def.item, 1) then
        Jobs.Pay(source, 'cash', price, 'refund')
        return false, 'no-space'
    end
    return true, { price = price }
end

-- ─── Work authority ──────────────────────────────────────────
--- Decide whether a repair request is legitimate and bill the customer.
---@param source number the worker
---@param payload table { plate, netId, faults, quote, site, partsUsed }
function Tools.AuthoriseRepair(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    if not Jobs.CanWork(session.job, 'mechanic') then return false, 'off-duty' end
    if not Jobs.Throttle(source, 'repair', 6) then return false, 'slow-down' end

    payload = type(payload) == 'table' and payload or {}
    local plate = Shared.NormalisePlate(payload.plate)
    if plate == '' then return false, 'no-plate' end

    local faults = payload.faults or {}
    if #faults == 0 then return false, 'nothing-wrong' end

    local quote = payload.quote or Shared.Quote(faults, payload.snap, session.level, 'mechanic')
    if quote.total <= 0 then return false, 'zero-quote' end

    -- tools of the trade
    for _, toolKey in ipairs({ 'toolbox', 'diag_tablet' }) do
        local def = Config.Tools[toolKey]
        if def and not HasItem(source, def.item, 1) then
            return false, 'missing-tool:' .. def.label
        end
    end

    -- parts must be in the worker's pack or on the bench
    local usedParts = {}
    for _, line in ipairs(quote.lines or {}) do
        if line.part then
            local def = Config.Parts[line.part]
            if def then
                if HasItem(source, def.item, 1) then
                    usedParts[#usedParts + 1] = { item = def.item, from = 'pack' }
                elseif Tools.TakeStock(payload.site, line.part, 1) then
                    usedParts[#usedParts + 1] = { item = def.item, from = 'bench' }
                else
                    return false, 'missing-part:' .. def.label
                end
            end
        end
    end

    for _, u in ipairs(usedParts) do
        if u.from == 'pack' then RemoveItem(source, u.item, 1, 'fitted') end
    end

    -- who pays? the customer if there is one, otherwise the crew fronts it
    local payer = payload.customer and tonumber(payload.customer) or nil
    if payer and payer ~= source then
        if Jobs.Money(payer, 'cash') >= quote.total then
            if not Jobs.Take(payer, 'cash', quote.total, 'invoice:' .. plate) then
                -- roll the parts back onto the bench / into the pack
                for _, u in ipairs(usedParts) do
                    if u.from == 'pack' then
                        AddItem(source, u.item, 1)
                    else
                        for key, def in pairs(Config.Parts) do
                            if def.item == u.item then Tools.Restock(payload.site, key, 1) break end
                        end
                    end
                end
                return false, 'customer-cant-pay'
            end
            Jobs.Pay(source, 'cash', math.floor(quote.total * (Config.PaySplit.mechanic or 0.72)), 'repair')
        else
            DB.CreateInvoice({
                ref = Shared.Id('inv'), kind = 'mechanic', customer = Jobs.CitizenId(payer),
                worker = session.cid, plate = plate, lines = quote.lines,
                labour = quote.labour, parts = quote.parts, tax = quote.tax, total = quote.total,
            })
            Notify(payer, ('Unpaid invoice %s — $%s for work on %s'):format(
                plate, Shared.Money(quote.total), plate), 'warning')
            Jobs.Pay(source, 'cash', math.floor(quote.total * ((Config.PaySplit.mechanic or 0.72) * 0.45)),
                'repair-partial')
        end
    else
        Jobs.Pay(source, 'cash', math.floor(quote.total * (Config.PaySplit.mechanic or 0.72)), 'repair')
    end

    Jobs.RegisterAction(source, 'mechanic', quote.total)
    return true, { quote = quote, parts = usedParts }
end

--- A bench job (no customer present): the crew buys the parts and books the labour.
function Tools.BenchJob(source, payload)
    local session = Jobs.Get(source)
    if not session then return false, 'no-session' end
    payload = payload or {}

    local quote = Shared.Quote(payload.faults or {}, payload.snap, session.level, 'mechanic')
    local partsCost = quote.parts
    if Jobs.Money(source, 'cash') < partsCost then return false, 'no-cash' end

    if partsCost > 0 and not Jobs.Take(source, 'cash', partsCost, 'bench-parts') then
        return false, 'payment-failed'
    end
    Jobs.Pay(source, 'cash', math.floor(quote.labour * (Config.PaySplit.mechanic or 0.72)), 'bench-labour')
    Jobs.RegisterAction(source, 'mechanic', quote.labour)
    return true, quote
end

-- ─── Worn part / fitting failure roll ────────────────────────
function Tools.FitRoll(source, toolKey)
    local def = Config.Tools[toolKey or 'toolbox']
    if not def then return true end
    local chance = Config.Failure.partFitFailChance + (def.breakChance or 0) * 0.25
    local roll = math.random()
    if roll < chance then
        -- the tool takes damage or disappears
        if math.random() < 0.35 then
            RemoveItem(source, def.item, 1, 'broken')
            return false, 'tool-broke'
        end
        return false, 'part-refused'
    end
    return true
end

-- ─── RPC ──────────────────────────────────────────────────────
RegisterNetEvent('grand_mechanic:server:Repair', function(payload)
    local source = tonumber(source)
    if not source then return end
    local ok, result = Tools.AuthoriseRepair(source, payload)
    if not ok then
        Notify(source, ('Repair refused: %s'):format(tostring(result)), 'error')
        TriggerClientEvent('grand_mechanic:client:RepairDenied', source, tostring(result))
    else
        TriggerClientEvent('grand_mechanic:client:RepairDone', source, {
            plate = Shared.NormalisePlate((payload or {}).plate),
            quote = result.quote,
        })
    end
end)

RegisterNetEvent('grand_mechanic:server:BuyPart', function(siteId, part)
    local source = tonumber(source)
    if not source then return end
    local ok, result = Tools.BuyPart(source, tostring(siteId or ''), tostring(part or ''))
    if ok then
        Notify(source, ('Bought %s for $%s'):format(Config.Parts[result.part].label, Shared.Money(result.price)), 'success')
    else
        Notify(source, ('Cannot buy that part: %s'):format(tostring(result)), 'error')
    end
end)

RegisterNetEvent('grand_mechanic:server:BuyTool', function(toolKey)
    local source = tonumber(source)
    if not source then return end
    local ok, result = Tools.BuyTool(source, tostring(toolKey or ''))
    if ok then Notify(source, ('Tool acquired — $%s'):format(Shared.Money(result.price)), 'success') end
end)

RegisterNetEvent('grand_mechanic:server:Stock', function(siteId)
    local source = tonumber(source)
    if not source then return end
    TriggerClientEvent('grand_mechanic:client:StockSync', source, Tools.GetStock(tostring(siteId or '')))
end)

RegisterNetEvent('grand_mechanic:server:Restock', function(siteId, part, qty)
    local source = tonumber(source)
    if not source then return end
    if not IsPlayerAceAllowed(source, 'grand.mechanic.restock') then
        return Notify(source, 'Not authorised', 'error')
    end
    local total = Tools.Restock(tostring(siteId or ''), tostring(part or ''), tonumber(qty) or 0)
    if total then TriggerClientEvent('grand_mechanic:client:StockSync', -1, Tools.GetStock(siteId)) end
end)

RegisterNetEvent('grand_mechanic:server:Bench', function(payload)
    local source = tonumber(source)
    if not source then return end
    Tools.BenchJob(source, payload)
end)

exports('HasItem', HasItem)
exports('AddItem', AddItem)
exports('RemoveItem', RemoveItem)
exports('Stock', Tools.GetStock)
exports('FitRoll', Tools.FitRoll)

return Tools
