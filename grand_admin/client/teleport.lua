-- resources/[grand_systems]/grand_admin/client/teleport.lua
-- Teleport handlers for the web panel. This project has no qb-core, so all
-- feedback goes through the global Notify() from client/notify.lua.

--- Teleports the player to a ground-snapped location with a short fade.
---@param x number
---@param y number
---@param z number
local function TeleportToCoords(x, y, z)
    local ped = PlayerPedId()

    DoScreenFadeOut(400)
    Wait(450)

    local found, groundZ = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 4.0, false)
    local target = found and vector3(x, y, groundZ + 1.0) or vector3(x, y, z)

    RequestCollisionAtCoord(target.x, target.y, target.z)

    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle ~= 0 then
        SetEntityCoords(vehicle, target.x, target.y, target.z, false, false, false, false)
    else
        SetEntityCoordsNoOffset(ped, target.x, target.y, target.z, false, false, false)
    end

    ClearPedTasksImmediately(ped)
    SetEntityAlpha(ped, 0, false)

    Wait(500)
    DoScreenFadeIn(600)

    local deadline = GetGameTimer() + 2500
    while not HaveCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        Wait(25)
    end

    SetEntityAlpha(ped, 255, false)

    Notify(('Teleported to %.1f, %.1f, %.1f'):format(target.x, target.y, target.z), 'success')
end

--- Teleports the player to their map waypoint marker.
local function TeleportToWaypoint()
    if not IsWaypointActive() then
        Notify('No waypoint set on the map', 'error')
        return
    end

    local coords = GetBlipInfoIdCoord(GetFirstBlipInfoId(8)) -- 8 = waypoint blip
    if not coords then
        Notify('Could not read waypoint', 'error')
        return
    end

    local found, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, 1000.0, false)
    TeleportToCoords(coords.x, coords.y, found and groundZ or coords.z)
end

--- Teleports the admin onto another player's position.
---@param target number server id
local function TeleportToPlayer(target)
    target = tonumber(target)
    if not target or GetPlayerPed(target) == 0 then
        Notify('Target player not found', 'error')
        return
    end

    local ped = GetPlayerPed(target)
    local coords = GetEntityCoords(ped)
    TeleportToCoords(coords.x, coords.y, coords.z)
end

-- ---------------------------------------------------------------------------
-- Network events (fired by server/main.lua)
-- ---------------------------------------------------------------------------

RegisterNetEvent('grand_admin:client:TeleportToCoords', TeleportToCoords)
RegisterNetEvent('grand_admin:client:TeleportToWaypoint', TeleportToWaypoint)
RegisterNetEvent('grand_admin:client:TeleportToPlayer', TeleportToPlayer)

-- ---------------------------------------------------------------------------
-- NUI callbacks (only the ones owned by this file)
-- ---------------------------------------------------------------------------

RegisterNUICallback('teleportToCoords', function(data, cb)
    local x = tonumber(data and data.x)
    local y = tonumber(data and data.y)
    local z = tonumber(data and data.z)

    if not x or not y or not z then
        cb({ success = false, message = 'Invalid coordinates' })
        return
    end

    TeleportToCoords(x, y, z)
    cb({ success = true, message = 'Teleported' })
end)

RegisterNUICallback('teleportToWaypoint', function(_, cb)
    TeleportToWaypoint()
    cb({ success = true, message = 'Teleported to waypoint' })
end)

RegisterNUICallback('teleportToPlayer', function(data, cb)
    local target = tonumber(data and data.target)
    if not target then
        cb({ success = false, message = 'No target specified' })
        return
    end

    TeleportToPlayer(target)
    cb({ success = true, message = 'Teleported' })
end)

RegisterNUICallback('setInvisible', function(data, cb)
    local state = data and data.state == true
    local ped = PlayerPedId()

    SetEntityVisible(ped, not state, false)
    SetEntityNoCollisionEntity(ped, ped, state)
    Notify(state and 'You are now invisible' or 'You are visible again', 'info')
    cb({ success = true, message = state and 'Invisible' or 'Visible' })
end)

RegisterNUICallback('healSelf', function(data, cb)
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))

    if data and data.armor == true then
        SetPedArmour(ped, 100)
    end

    Notify('Restored health' .. ((data and data.armor) and ' and armour' or ''), 'success')
    cb({ success = true, message = 'Healed' })
end)

-- ---------------------------------------------------------------------------
-- Exports
-- ---------------------------------------------------------------------------

exports('TeleportToCoords', TeleportToCoords)
exports('TeleportToWaypoint', TeleportToWaypoint)
exports('TeleportToPlayer', TeleportToPlayer)
