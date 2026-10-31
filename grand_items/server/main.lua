-- ─────────────────────────────────────────────────────────────
--  grand_items: server/main.lua
--  Consumables are carried by grand_inventory; this resource owns
--  the food/drink metadata and the HUD vitals bridge. There is no
--  framework dependency and no external inventory export.
-- ─────────────────────────────────────────────────────────────

--- Metadata lookup for other resources.
---@param name string
---@return table|nil
function GrandItems.Get(name)
    if type(name) ~= 'string' then return nil end
    return GrandItems[name]
end

--- Every registered consumable, copied so callers cannot mutate it.
function GrandItems.All()
    local copy = {}
    for name, data in pairs(GrandItems) do
        if type(data) == 'table' then copy[name] = data end
    end
    return copy
end

exports('GetItem', function(name) return GrandItems[name] end)
exports('GetAll', function() return GrandItems.All() end)

-- ─── Vitals bridge ───────────────────────────────────────────
RegisterNetEvent('grand_items:applyVitals', function(hunger, thirst)
    local src = source
    if not src or src <= 0 then return end

    hunger = math.max(0, math.min(100, tonumber(hunger) or 0))
    thirst = math.max(0, math.min(100, tonumber(thirst) or 0))

    TriggerClientEvent('grand_hud:receiveStats', src, {
        hungerBoost = hunger,
        thirstBoost = thirst,
    })
end)
