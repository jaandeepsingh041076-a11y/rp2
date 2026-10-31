-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/civic.lua
--  Centralised civic POIs: courthouse, hospitals, prison.
--  Reuses the GrandBlips engine with a raw fallback.
-- ─────────────────────────────────────────────────────────────

local PREFIX = 'civic_'

local function engine(name, ...)
    if _G.GrandBlips and type(_G.GrandBlips[name]) == 'function' then
        local args = table.pack(...)
        local ok, result = pcall(_G.GrandBlips[name], table.unpack(args, 1, args.n))
        if ok then return result end
    end
    if GetResourceState('grand_mechanic') == 'started' then
        local args = table.pack(...)
        local ok, result = pcall(function()
            return exports['grand_mechanic'][name](table.unpack(args, 1, args.n))
        end)
        if ok then return result end
    end
    return nil
end

local civicBlips = {
    { id = PREFIX .. 'courthouse', coords = vector3(237.0, -413.0, 48.0), sprite = 498, colour = 46, scale = 0.8, label = 'Courthouse' },
    { id = PREFIX .. 'hospital_pillbox', coords = vector3(306.0, -586.4, 43.3), sprite = 80, colour = 1, scale = 0.85, label = 'Pillbox Hospital' },
    { id = PREFIX .. 'hospital_sandy', coords = vector3(1839.9, 3672.9, 34.3), sprite = 80, colour = 1, scale = 0.8, label = 'Sandy Shores Medical' },
    { id = PREFIX .. 'prison', coords = vector3(1641.1, 2567.8, 45.5), sprite = 237, colour = 40, scale = 0.85, label = 'Bolingbroke Penitentiary' },
    { id = PREFIX .. 'airport', coords = vector3(-1037.0, -2738.0, 20.2), sprite = 90, colour = 3, scale = 0.8, label = 'Los Santos International' },
}

local handles = {}

local function add(record)
    local id = engine('AddBlip', {
        id = record.id,
        coords = record.coords,
        sprite = record.sprite,
        colour = record.colour,
        scale = record.scale,
        label = record.label,
        range = 2000.0,
    })
    if id then
        handles[record.id] = { engine = true, id = id }
        return
    end
    local handle = AddBlipForCoord(record.coords.x, record.coords.y, record.coords.z)
    SetBlipSprite(handle, record.sprite)
    SetBlipColour(handle, record.colour)
    SetBlipScale(handle, record.scale)
    SetBlipAsShortRange(handle, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(record.label)
    EndTextCommandSetBlipName(handle)
    handles[record.id] = { engine = false, handle = handle }
end

CreateThread(function()
    Wait(4000)
    for _, record in ipairs(civicBlips) do
        add(record)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for key, entry in pairs(handles) do
        if entry.engine then
            engine('RemoveBlip', entry.id)
        elseif entry.handle then
            RemoveBlip(entry.handle)
        end
    end
end)