-- resources/[grand_systems]/grand_admin/client/state.lua
-- Shared state loaded first so other client modules can rely on it.

AdminState = {
    godmode = false,
    noclip = false,
    spectating = nil
}

local RESOURCE = GetCurrentResourceName()

function RefreshAdminState()
    lib.callback('grand_admin:server:GetPlayerState', false, function(state)
        if not state then
            AdminState.godmode = false
            AdminState.noclip = false
            AdminState.spectating = nil
            return
        end

        AdminState.godmode = state.godmode and true or false
        AdminState.noclip = state.noclip and true or false
        AdminState.spectating = state.spectating
    end)
end

RegisterNetEvent('grand_core:client:PlayerLoaded', function()
    RefreshAdminState()
end)

RegisterNetEvent('grand_core:client:CurrentUserReady', function()
    RefreshAdminState()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName == RESOURCE then
        RefreshAdminState()
    end
end)

-- Clean shutdown: never leave noclip/godmode/spectate active after a restart.
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    local ok

    if AdminState.noclip then
        ok = pcall(function() exports[RESOURCE]:SetNoclip(false) end)
        if not ok then SetNoclip(false) end
    end

    if AdminState.godmode then
        ok = pcall(function() exports[RESOURCE]:SetGodMode(false) end)
        if not ok and SetGodMode then SetGodMode(false) end
    end

    if AdminState.spectating then
        ok = pcall(function() exports[RESOURCE]:SetSpectating(false) end)
        if not ok and SetSpectating then SetSpectating(false) end
    end

    SetNuiFocus(false, false)
end)

exports('GetAdminState', function()
    return AdminState
end)
