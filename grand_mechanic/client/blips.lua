-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/blips.lua
--  THE MAP LAYER. A data-driven blip + zone engine: every resource
--  hands it records and it owns the radmap, the distance culling,
--  the duty gating and the chevrons on the ground.
--
--  Public API (also usable from other resources via exports):
--    Blips.Add({ id, coords, sprite, colour, scale, label,
--                hidden, duty, range, alpha, heading, route,
--                short, secondary, flash })
--    Blips.Remove(id)
--    Blips.Show(id, bool)
--    Blips.SetDuty(kind | false)      -- reveal only for that job
--    Blips.Zone({ id, coords, radius, colour, label })   -- turf / hoard area
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared
local Mx = Mechanic.Client

local Blips = {}
Mechanic.Blips = Blips

local registry = {}     -- [id] = record
local zones = {}        -- [id] = zone record
local blipHandle = {}   -- [id] = handle
local spriteHandle = {} -- [id] = handle (rotating sprite for zones)

-- ─── Colour table: name -> radmap index ──────────────────────
local COLOURS = {
    crimson = 1, green = 2, blue = 3, gold = 4, orange = 9, red = 1,
    purple = 5, teal = 6, pink = 8, yellow = 66, sky = 52, emerald = 25,
    grey = 26, white = 0, black = 29, sapphire = 52,
    -- gang palette
    ballas = 27, vagos = 2, lost = 30, marabunta = 41, cartel = 29, hood = 34,
    police = 52, ems = 5, cab = 5, tow = 17, wrench = 28,
}

local function ColourOf(value)
    if type(value) == 'number' then return value end
    if type(value) == 'string' then return COLOURS[value:lower()] or 29 end
    return 29
end

Blips.COLOURS = COLOURS

-- ─── Core add ────────────────────────────────────────────────
function Blips.Add(record)
    if not record or not record.coords then return nil end
    local id = record.id or ('blip-%d'):format(#registry + 1)
    record.id = id
    record.sprite = tonumber(record.sprite) or 1
    record.colour = ColourOf(record.colour or record.blip and record.blip.colour)
    record.scale = tonumber(record.scale) or 0.8
    record.range = tonumber(record.range) or (Config.Blips and Config.Blips.distanceCull or 1200.0)
    record.hidden = record.hidden == true
    registry[id] = record
    Blips.Refresh(id)
    return id
end

--- Convenience: add from a config `blip = { ... }` sub-record.
function Blips.FromConfig(coords, blip, extra)
    if type(blip) ~= 'table' then return nil end
    local record = {
        coords = coords, sprite = blip.sprite, colour = blip.colour, scale = blip.scale,
        label = blip.label, hidden = blip.hidden,
    }
    if extra then
        for k, v in pairs(extra) do record[k] = v end
    end
    return Blips.Add(record)
end

function Blips.Remove(id)
    local handle = blipHandle[id]
    if handle then
        RemoveBlip(handle)
        blipHandle[id] = nil
    end
    registry[id] = nil
end

function Blips.Clear(prefix)
    for id in pairs(registry) do
        if not prefix or id:sub(1, #prefix) == prefix then
            Blips.Remove(id)
        end
    end
end

function Blips.Show(id, visible)
    local record = registry[id]
    if not record then return end
    record.hidden = not visible
    Blips.Refresh(id)
end

--- Only reveal it when the local player holds this job (or kind).
function Blips.SetDuty(id, kind)
    local record = registry[id]
    if not record then return end
    record.duty = kind
    Blips.Refresh(id)
end

function Blips.Exists(id)
    return registry[id] ~= nil
end

-- ─── (Re)materialise one blip honouring duty + hidden rules ──
function Blips.Refresh(id)
    local record = registry[id]
    if not record then return end

    local existing = blipHandle[id]
    if existing then
        RemoveBlip(existing)
        blipHandle[id] = nil
    end

    if record.hidden then return end
    if record.duty and not Mx.IsOnDuty(record.duty) then return end
    if Config.Blips and Config.Blips.onlyOnDuty and not record.duty then
        -- master switch: keep public POIs visible, gate the rest
    end

    local c = record.coords
    local x, y, z = c.x or c[1] or 0.0, c.y or c[2] or 0.0, c.z or c[3] or 0.0

    local handle
    if record.route then
        handle = AddBlipForRoute(x, y, z)
    else
        handle = AddBlipForCoord(x, y, z)
    end

    SetBlipSprite(handle, record.sprite)
    SetBlipColour(handle, record.colour)
    SetBlipScale(handle, record.scale)
    SetBlipAsShortRange(handle, record.short ~= false)
    SetBlipFlashes(handle, record.flash or false)
    SetBlipFlashTimer(handle, record.flashTimer or 1000)

    if record.heading then
        SetBlipSprite(handle, 8)
        SetBlipRotation(handle, math.floor((record.heading or 0.0) - 90.0))
    end

    if record.alpha then SetBlipAlpha(handle, record.alpha) end
    if record.range then SetBlipFadeDistance(handle, record.range, 2) end

    if record.label then
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(record.label)
        EndTextCommandSetBlipName(handle)
    end

    blipHandle[id] = handle
end

-- ─── Ground zones (turf, hoarding areas, no-fly) ─────────────
function Blips.Zone(record)
    if not record or not record.coords then return nil end
    local id = record.id or ('zone-%d'):format(#zones + 1)
    record.id = id
    record.radius = tonumber(record.radius) or 40.0
    record.colour = ColourOf(record.colour or 'crimson')
    record.tick = record.tick ~= false
    zones[id] = record
    return id
end

function Blips.RemoveZone(id)
    local h = spriteHandle[id]
    if h then RemoveBlip(h) spriteHandle[id] = nil end
    zones[id] = nil
end

function Blips.Zones()
    local out = {}
    for _, z in pairs(zones) do out[#out + 1] = z end
    return out
end

function Blips.InZone(name, coords)
    coords = coords or GetEntityCoords(PlayerPedId())
    for _, z in pairs(zones) do
        if (not name or z.id == name or z.group == name) then
            local c = z.coords
            local d = #(coords - vector3(c.x or c[1] or 0, c.y or c[2] or 0, c.z or c[3] or 0))
            if d <= (z.radius or 40.0) then return z, d end
        end
    end
    return nil
end

function Blips.ZoneAt(coords)
    return Blips.InZone(nil, coords)
end

-- ─── Renderer for the zone rings + chevrons ──────────────────
CreateThread(function()
    while true do
        local sleep = 800
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)

        for id, z in pairs(zones) do
            local c = z.coords
            local cx, cy, cz = c.x or c[1] or 0.0, c.y or c[2] or 0.0, c.z or c[3] or 0.0
            local d = #(pos - vector3(cx, cy, cz))

            if d <= (z.radius or 40.0) + 90.0 then
                sleep = 0
                local r, g, b = BandToRGB(z.colour)
                local inside = d <= (z.radius or 40.0)
                local alpha = inside and 120 or 60

                -- ring on the ground
                DrawMarker(1, cx, cy, cz - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    (z.radius or 40.0) * 2.0, (z.radius or 40.0) * 2.0, 3.0,
                    r, g, b, alpha, false, false, 2, false, nil, nil, false)

                -- pulsing pillar at the centre
                local pulse = 0.5 + (math.sin(GetGameTimer() / 320.0) * 0.35)
                DrawMarker(28, cx, cy, cz - 0.9, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                    2.6, 2.6, 1.2, r, g, b, math.floor(60 + pulse * 110), false, false, 2, false, nil, nil, false)

                if z.label and d <= (z.radius or 40.0) + 35.0 then
                    BeginTextCommandDisplayText('STRING')
                    AddTextComponentSubstringPlayerName(('^%s%s'):format(inside and '1' or '3', z.label))
                    EndTextCommandDisplayText(0.5, 0.135)
                end
            end
        end

        Wait(sleep)
    end
end)

--- Radmap colour index -> RGBA for markers.
function BandToRGB(index)
    local map = {
        [0] = { 220, 220, 220 }, [1] = { 255, 30, 56 }, [2] = { 16, 200, 110 },
        [3] = { 107, 50, 126 }, [4] = { 56, 110, 255 }, [5] = { 0, 178, 180 },
        [6] = { 220, 255, 20 }, [7] = { 255, 188, 0 }, [8] = { 255, 30, 56 },
        [9] = { 240, 160, 0 }, [25] = { 0, 255, 136 }, [26] = { 150, 150, 150 },
        [27] = { 105, 20, 170 }, [28] = { 0, 178, 180 }, [29] = { 255, 255, 255 },
        [30] = { 255, 30, 56 }, [34] = { 100, 60, 40 }, [41] = { 80, 170, 60 },
        [47] = { 60, 90, 140 }, [52] = { 0, 176, 255 }, [66] = { 120, 20, 120 },
    }
    local c = map[index] or { 255, 30, 56 }
    return c[1], c[2], c[3]
end

-- ─── Distance cull loop ──────────────────────────────────────
CreateThread(function()
    Wait(3000)
    local cull = (Config.Blips and Config.Blips.distanceCull) or 1200.0
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for id, record in pairs(registry) do
            if not record.hidden and not record.persistent then
                local c = record.coords
                local d = #(pos - vector3(c.x or c[1] or 0, c.y or c[2] or 0, c.z or c[3] or 0))
                local visible = d <= (record.range or cull)
                local has = blipHandle[id] ~= nil
                if visible and not has then
                    Blips.Refresh(id)
                elseif not visible and has then
                    RemoveBlip(blipHandle[id])
                    blipHandle[id] = nil
                end
            end
        end
        Wait(4000)
    end
end)

-- ─── Map: install every workforce icon from config ───────────
function Blips.InstallWorkforce()
    Blips.Clear('mx-')

    for _, site in ipairs(Config.Locations) do
        local duty = site.kind == 'towing' and 'tow'
            or site.kind == 'taxi' and 'taxi'
            or site.kind == 'hoarding' and 'mechanic' or false

        Blips.Add({
            id = 'mx-' .. site.id,
            coords = site.coords,
            sprite = site.blip and site.blip.sprite or 478,
            colour = site.blip and site.blip.colour or 28,
            scale = site.blip and site.blip.scale or 0.8,
            label = site.blip and site.blip.label or site.name,
            hidden = site.blip and site.blip.hidden or false,
            duty = duty,
            heading = site.heading,
        })

        -- the physical yard footprint
        if site.radius and site.kind ~= 'taxi' then
            Blips.Zone({
                id = 'mxz-' .. site.id,
                group = 'workforce',
                coords = site.coords,
                radius = site.radius,
                colour = site.kind == 'illegal' and 'crimson' or 'gold',
                label = site.kind == 'illegal' and 'UNLISTED WORKSHOP' or site.name,
            })
        end
    end

    for _, lot in ipairs(Config.Impound) do
        Blips.Add({
            id = 'mx-imp-' .. lot.id,
            coords = lot.coords,
            sprite = lot.blip and lot.blip.sprite or 345,
            colour = lot.blip and lot.blip.colour or 47,
            scale = lot.blip and lot.blip.scale or 0.75,
            label = lot.blip and lot.blip.label or lot.name,
        })
        Blips.Zone({
            id = 'mxz-imp-' .. lot.id, group = 'impound', coords = lot.coords,
            radius = 22.0, colour = 'sapphire', label = lot.name,
        })
    end

    for _, pub in ipairs(Config.PublicServices) do
        Blips.Add({
            id = 'mx-pub-' .. pub.id,
            coords = pub.coords,
            sprite = pub.blip and pub.blip.sprite or 360,
            colour = pub.blip and pub.blip.colour or 5,
            scale = pub.blip and pub.blip.scale or 0.75,
            label = pub.blip and pub.blip.label or pub.name,
        })
    end

    -- fleet spawns get their own small icon so crews can find the trucks
    for model, spawn in pairs(Config.FleetSpawn or {}) do
        Blips.Add({
            id = 'mx-fleet-' .. model,
            coords = vector3(spawn.x or spawn[1], spawn.y or spawn[2], spawn.z or spawn[3]),
            sprite = 481, colour = 26, scale = 0.55,
            label = ('Crew pool: %s'):format(model:upper()),
            duty = (model == 'taxi' or model == 'taxi2') and 'taxi' or 'tow',
            hidden = true,
        })
    end

    -- taxi rank route arrows
    for _, route in ipairs(Config.TaxiRoutes or {}) do
        Blips.Add({
            id = 'mx-route-' .. route.id,
            coords = route.to,
            sprite = 476, colour = 5, scale = 0.5,
            label = ('%s ($%s)'):format(route.name, Shared.Money(route.fare)),
            duty = 'taxi', hidden = true,
        })
    end
end

-- ─── Live job markers ────────────────────────────────────────
function Blips.InstallBoardMarkers(board)
    Blips.Clear('job-')
    for _, job in ipairs(board or {}) do
        if job.status == 'open' or job.worker == Mx.Session.cid then
            Blips.Add({
                id = 'job-' .. job.ref,
                coords = vector3(job.x or 0, job.y or 0, job.z or 0),
                sprite = job.kind == 'tow' and 481 or job.kind == 'taxi' and 476 or 478,
                colour = job.worker and 2 or 1,
                scale = 0.6,
                label = ('%s — %s $%s'):format(job.kind:upper(), job.plate or '—', Shared.Money(job.estimate or 0)),
                range = 700.0,
            })
        end
    end
end

RegisterNetEvent('grand_mechanic:client:SessionReady', function()
    Blips.InstallWorkforce()
end)

RegisterNetEvent('grand_mechanic:client:BoardChanged', function(board)
    Blips.InstallBoardMarkers(board)
end)

-- ─── Commands to drive the map ───────────────────────────────
RegisterCommand('mapicons', function(_, args)
    local sub = tostring(args[1] or 'list'):lower()
    if sub == 'reload' then
        Blips.InstallWorkforce()
        Mx.Notify('Map icons rebuilt', 'success')
    elseif sub == 'off' then
        Config.Blips.enable = false
        Blips.Clear()
        Mx.Notify('All workforce icons cleared', 'info')
    elseif sub == 'on' then
        Config.Blips.enable = true
        Blips.InstallWorkforce()
    elseif sub == 'reveal' then
        local id = args[2] or ''
        Blips.Show('mx-' .. id, true)
        Mx.Notify(('Icon %s revealed'):format(id), 'info')
    elseif sub == 'list' then
        local lines = { '^1▚ MAP ICONS' }
        local n = 0
        for id, record in pairs(registry) do
            n = n + 1
            if not record.hidden then
                lines[#lines + 1] = ('  ^3%s ^7%s'):format(id, record.label or '')
            end
        end
        lines[#lines + 1] = ('^7%d registered, %d shown'):format(n, #lines - 2)
        TriggerEvent('chat:addMessage', { multiline = true, args = lines })
    end
end, false, { help = 'Map icons: list | reload | on | off | reveal <site>' })

CreateThread(function()
    Wait(2000)
    if Config.Blips.enable == false then return end
    Blips.InstallWorkforce()
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        Blips.Clear()
        for id in pairs(zones) do Blips.RemoveZone(id) end
    end
end)

-- ─── Exports so gangs / police / anything can use the map ────
exports('AddBlip', Blips.Add)
exports('RemoveBlip', Blips.Remove)
exports('ClearBlips', Blips.Clear)
exports('ShowBlip', Blips.Show)
exports('SetBlipDuty', Blips.SetDuty)
exports('AddZone', Blips.Zone)
exports('RemoveZone', Blips.RemoveZone)
exports('Zones', Blips.Zones)
exports('InZone', Blips.InZone)
exports('ZoneAt', Blips.ZoneAt)
exports('Colour', ColourOf)
exports('Refresh', Blips.Refresh)

_G.GrandBlips = Blips
return Blips
