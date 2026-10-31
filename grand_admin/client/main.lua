-- resources/[grand_systems]/grand_admin/client/main.lua
-- Entry point for NUI (HTML) admin panel.

local RESOURCE = GetCurrentResourceName()
local IsMenuOpen = false

local function NoclipSpeed()
    local ok, speed = pcall(function()
        return exports[RESOURCE]:GetNoclipSpeed()
    end)
    if ok and tonumber(speed) then return tonumber(speed) end
    return 3
end

-- --------------------------------------------------------------------------
-- NUI message handlers
-- --------------------------------------------------------------------------

local function SendState()
    local state = AdminState or {}
    SendNUIMessage({
        action = 'state',
        godmode = state.godmode,
        noclip = state.noclip,
        invisible = false,
        spectating = state.spectating,
        name = GetPlayerName(PlayerId()) or 'Staff',
        noclipSpeed = NoclipSpeed()
    })
end

RegisterNUICallback('getPlayers', function(_, cb)
    lib.callback('grand_admin:server:GetPlayers', false, function(players)
        SendNUIMessage({ action = 'players', data = players or {} })
        cb({ data = players or {}, error = nil })
    end)
end)

RegisterNUICallback('getVehicleCategories', function(_, cb)
    lib.callback('grand_admin:server:GetVehicleCategories', false, function(categories)
        SendNUIMessage({ action = 'vehicles', data = categories or {} })
        cb({ data = categories or {}, error = nil })
    end)
end)

RegisterNUICallback('getState', function(_, cb)
    local state = AdminState or {}
    cb({ data = {
        godmode = state.godmode,
        noclip = state.noclip,
        spectating = state.spectating
    }})
end)

RegisterNUICallback('getServerInfo', function(_, cb)
    lib.callback('grand_admin:server:GetServerInfo', false, function(info)
        cb({ data = info or {} })
    end)
end)

RegisterNUICallback('kickPlayer', function(data, cb)
    lib.callback('grand_admin:server:KickPlayer', false, function(success, message)
        cb({ success = success, message = message })
    end, data and data.target, data and data.reason)
end)

RegisterNUICallback('banPlayer', function(data, cb)
    lib.callback('grand_admin:server:BanPlayer', false, function(success, message)
        cb({ success = success, message = message })
    end, data and data.target, data and data.duration, data and data.reason)
end)

RegisterNUICallback('bringPlayer', function(data, cb)
    lib.callback('grand_admin:server:BringPlayer', false, function(success, message)
        cb({ success = success, message = message })
    end, data and data.target)
end)

RegisterNUICallback('spawnVehicle', function(data, cb)
    if not data or not data.model then
        cb({ success = false, message = 'No model selected' })
        return
    end

    lib.callback('grand_admin:server:SpawnVehicle', false, function(success, message)
        cb({ success = success, message = message })
    end, data.model)
end)

RegisterNUICallback('toggleGodmode', function(_, cb)
    lib.callback('grand_admin:server:ToggleGodMode', false, function(success, message)
        if success then RefreshAdminState() end
        cb({ success = success, message = message })
    end)
end)

RegisterNUICallback('toggleNoclip', function(_, cb)
    lib.callback('grand_admin:server:ToggleNoClip', false, function(success, message)
        if success then RefreshAdminState() end
        cb({ success = success, message = message })
    end)
end)

RegisterNUICallback('spectatePlayer', function(data, cb)
    lib.callback('grand_admin:server:StartSpectating', false, function(success, message)
        if success then RefreshAdminState() end
        cb({ success = success, message = message })
    end, data and data.target)
end)

RegisterNUICallback('stopSpectating', function(_, cb)
    lib.callback('grand_admin:server:StopSpectating', false, function(success, message)
        if success then RefreshAdminState() end
        cb({ success = success, message = message })
    end)
end)

-- teleportToCoords, teleportToWaypoint, teleportToPlayer, bringPlayer,
-- setInvisible, healSelf are already handled by client/teleport.lua

RegisterNUICallback('setNoclipSpeed', function(data, cb)
    local value = tonumber(data and data.value)
    if not value then
        cb({ success = false, message = 'Invalid value' })
        return
    end

    local ok = pcall(function()
        return exports[RESOURCE]:SetNoclipSpeedMultiplier(value)
    end)
    if not ok then
        return cb({ success = false, message = 'Noclip module not loaded' })
    end
    cb({ success = true, message = 'Speed updated' })
end)

RegisterNUICallback('deleteCurrentVehicle', function(_, cb)
    local ok, success, message = pcall(function()
        return exports[RESOURCE]:DeleteLastVehicle()
    end)

    if not ok then
        cb({ success = false, message = 'Vehicle module not available' })
        return
    end

    cb({ success = success, message = message })
end)

RegisterNUICallback('closeMenu', function(_, cb)
    CloseMenu()
    cb('ok')
end)

RegisterNUICallback('notify', function(data, cb)
    local type = data and data.type or 'info'
    SendNUIMessage({ action = 'notify', message = data.message, type = type })
    cb('ok')
end)

-- --------------------------------------------------------------------------
-- Menu open / close
-- --------------------------------------------------------------------------

function OpenMenu()
    if IsMenuOpen then return end

    lib.callback('grand_admin:server:CanOpenMenu', false, function(canMenu)
        if not canMenu then
            SendNUIMessage({ action = 'notify', message = 'No permission', type = 'error' })
            return
        end

        IsMenuOpen = true
        SetNuiFocus(true, true)

        SendNUIMessage({
            action = 'open',
            name = GetPlayerName(PlayerId()) or 'Staff',
            full = IsPlayerAceAllowed('grand_admin.full') == 1
        })

        SendState()
    end)
end

function CloseMenu()
    if not IsMenuOpen then return end

    IsMenuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

function ToggleMenu()
    if IsMenuOpen then
        CloseMenu()
    else
        OpenMenu()
    end
end

-- --------------------------------------------------------------------------
-- Commands and events
-- --------------------------------------------------------------------------

RegisterCommand('adminmenu', function()
    ToggleMenu()
end, false)

RegisterKeyMapping('adminmenu', 'Open Grand RP Admin Panel', 'keyboard', 'f10')

RegisterNetEvent('grand_admin:client:OpenMenu', function()
    ToggleMenu()
end)

-- --------------------------------------------------------------------------
-- State sync
-- --------------------------------------------------------------------------

RegisterNetEvent('grand_admin:client:SpectateTargetLeft', function()
    SendNUIMessage({ action = 'spectateStopped' })
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == RESOURCE then
        CloseMenu()
        SetNuiFocus(false, false)
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == RESOURCE then
        print('^2[grand_admin] HTML/NUI admin panel ready^7')
    end
end)

-- --------------------------------------------------------------------------
-- Exports (for external control)
-- --------------------------------------------------------------------------

exports('OpenMenu', OpenMenu)
exports('CloseMenu', CloseMenu)
exports('ToggleMenu', ToggleMenu)
exports('IsMenuOpen', function() return IsMenuOpen end)