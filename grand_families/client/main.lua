-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/client/main.lua
--  Headless client: no NUI, no lib.context menus. Family state is
--  pushed by the server; this file only renders markers, 3D text
--  and chat feedback, and exposes the local cache to other
--  client scripts.
--
--  The full turf map (blips + rings) belongs to grand_gangs.
--  Here we only mark the turfs YOUR family holds.
-- ─────────────────────────────────────────────────────────────

local Families = {}

local CurrentFamily = nil
local OwnTurfs = {}          -- [zoneId] = { id, name, tier, radius, coords }
local LastVault = 0

local function notify(message, kind)
    if GetResourceState('ox_lib') == 'started' then
        local ok = pcall(function()
            lib.notify({ description = tostring(message), type = kind or 'inform' })
        end)
        if ok then return end
    end

    local colour = ({ error = { 244, 67, 54 }, success = { 76, 175, 80 },
                      warning = { 255, 193, 7 } })[kind] or { 255, 255, 255 }
    TriggerEvent('chat:addMessage', {
        color = colour, multiline = true,
        args = { 'Families', tostring(message) },
    })
end

local function vecFrom(payload)
    if not payload then return nil end
    if payload.x then return vector3(payload.x, payload.y, payload.z) end
    return nil
end

-- ─── State events ────────────────────────────────────────────
RegisterNetEvent('grand_families:client:FamilyUpdated', function(family)
    CurrentFamily = family
    if not family then
        OwnTurfs = {}
        LastVault = 0
        notify('You are not in a family any more', 'info')
        return
    end

    LastVault = tonumber(family.vault) or 0
    notify(('%s [%s] - rank %s'):format(
        tostring(family.name), tostring(family.tag or '----'),
        tostring(family.rankTitle or family.rank or 1)), 'success')
end)

RegisterNetEvent('grand_families:client:TurfSnapshot', function(turfs)
    OwnTurfs = {}
    for _, turf in ipairs(turfs or {}) do
        local id = turf.id or turf.name
        if id then
            OwnTurfs[id] = {
                id = id,
                name = turf.name or id,
                tier = tonumber(turf.tier) or 1,
                radius = tonumber(turf.radius) or 150.0,
                coords = vecFrom(turf.coords),
            }
        end
    end
end)

RegisterNetEvent('grand_families:client:VaultChanged', function(balance)
    local before = LastVault
    LastVault = tonumber(balance) or 0
    if CurrentFamily then CurrentFamily.vault = LastVault end

    local delta = LastVault - before
    if delta ~= 0 and math.abs(delta) >= 1000 then
        notify(('Vault %s: %s'):format(delta > 0 and 'up' or 'down',
            tostring(math.floor(math.abs(delta)))), delta > 0 and 'success' or 'warning')
    end
end)

RegisterNetEvent('grand_families:client:InvitationReceived',
    function(familyId, familyName, tag, inviter)
        notify(('%s [%s] invited you. /acceptinvite %s')
            :format(tostring(familyName), tostring(tag or '----'), tostring(familyId)), 'success')
        TriggerEvent('chat:addMessage', {
            color = { 255, 220, 120 }, multiline = true,
            args = { 'Invitation', ('%s wants you in %s. Run /acceptinvite %s'):format(
                tostring(inviter or 'Someone'), tostring(familyName), tostring(familyId)) },
        })
    end)

RegisterNetEvent('grand_families:client:TurfGained', function(turfName)
    notify(('Your family now holds %s'):format(tostring(turfName)), 'success')
    TriggerServerEvent('grand_families:server:Refresh')
end)

RegisterNetEvent('grand_families:client:TurfLost', function(turfName)
    notify(('Your family lost %s'):format(tostring(turfName)), 'error')
    TriggerServerEvent('grand_families:server:Refresh')
end)

RegisterNetEvent('grand_families:client:FamilyMessage', function(message, kind)
    notify(message, kind)
end)

RegisterNetEvent('grand_families:client:ShowTurfs', function()
    if not CurrentFamily then
        notify('You are not in a family', 'error')
        return
    end
    local count = 0
    for _, turf in pairs(OwnTurfs) do count = count + 1 end
    if count == 0 then
        notify('Your family holds no turf', 'info')
        return
    end
    for _, turf in pairs(OwnTurfs) do
        TriggerEvent('chat:addMessage', {
            color = { 200, 220, 255 }, multiline = false,
            args = { '', ('%s - tier %d'):format(turf.name, turf.tier) },
        })
    end
end)

-- ─── Marker loop: your own turfs only ────────────────────────
CreateThread(function()
    while true do
        local sleep = 800
        local has = next(OwnTurfs)
        if has and CurrentFamily then
            local coords = GetEntityCoords(PlayerPedId())
            local drawn = 0

            for _, turf in pairs(OwnTurfs) do
                local centre = turf.coords
                if centre then
                    local flat = #(vector2(coords.x, coords.y) - vector2(centre.x, centre.y))
                    if flat <= (turf.radius + 250.0) then
                        drawn = drawn + 1
                        DrawMarker(1, centre.x, centre.y, centre.z - 1.0,
                            0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                            6.0, 6.0, 2.0, 60, 200, 120, 180,
                            false, false, 2, false, nil, nil, false)

                        local onScreen, sx, sy = GetScreenCoordFromWorldCoord(
                            centre.x, centre.y, centre.z + 1.5)
                        if onScreen and flat <= 120.0 then
                            SetTextScale(0.30, 0.30)
                            SetTextFont(4)
                            SetTextProportional(1)
                            SetTextColour(120, 230, 160, 235)
                            SetTextOutline()
                            SetTextEntry('STRING')
                            AddTextComponentString(('%s - YOUR TURF'):format(turf.name))
                            DrawText(sx, sy)
                        end
                    end
                end
            end

            if drawn > 0 then sleep = 0 end
        end
        Wait(sleep)
    end
end)

-- ─── Lifecycle ───────────────────────────────────────────────
AddEventHandler('onClientResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- Ask the server for the current state once grand_core has spawned us.
    CreateThread(function()
        Wait(2500)
        TriggerServerEvent('grand_families:server:PlayerLoaded')
    end)
end)

-- ─── Local commands (never shadow the server ones) ───────────
RegisterCommand('fam', function()
    if not CurrentFamily then
        notify('You are not in a family', 'info')
        return
    end

    local count = 0
    for _ in pairs(OwnTurfs) do count = count + 1 end

    TriggerEvent('chat:addMessage', {
        color = { 200, 220, 255 }, multiline = true,
        args = { 'Family', ('%s [%s]\nRank: %s\nVault: $%s\nTurfs: %d'):format(
            tostring(CurrentFamily.name), tostring(CurrentFamily.tag or '----'),
            tostring(CurrentFamily.rankTitle or CurrentFamily.rank or 1),
            tostring(math.floor(LastVault)), count) },
    })
end, false)

-- ─── Client exports ──────────────────────────────────────────
exports('GetCurrentFamily', function()
    return CurrentFamily
end)

exports('GetFamilyId', function()
    return CurrentFamily and CurrentFamily.id or nil
end)

exports('IsInFamily', function()
    return CurrentFamily ~= nil
end)

exports('GetOwnTurfs', function()
    return OwnTurfs
end)

exports('IsInOwnTurf', function()
    if not CurrentFamily then return false end
    local coords = GetEntityCoords(PlayerPedId())
    for _, turf in pairs(OwnTurfs) do
        local centre = turf.coords
        if centre then
            local flat = #(vector2(coords.x, coords.y) - vector2(centre.x, centre.y))
            if flat <= turf.radius then return true, turf.id end
        end
    end
    return false
end)

exports('Notify', notify)

return Families
