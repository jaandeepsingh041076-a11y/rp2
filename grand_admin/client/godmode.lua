-- resources/[grand_systems]/grand_admin/client/godmode.lua
-- Godmode: invincibility, infinite ammo, ragdoll lock and self-heal loop.

local GodModeActive = false
local GodThread = nil
local OriginalMaxHealth = nil

function SetGodMode(state)
    state = state and true or false
    if state == GodModeActive then return end

    local ped = PlayerPedId()
    GodModeActive = state

    if state then
        OriginalMaxHealth = GetEntityMaxHealth(ped)

        SetEntityInvincible(ped, true)
        SetPlayerInvincible(PlayerId(), true)
        SetPedCanRagdoll(ped, not Config.GodMode.DisableRagdoll)
        SetEntityProofs(ped, true, true, true, true, true, true, true, true)

        if Config.GodMode.InfiniteAmmo then
            SetPedInfiniteAmmo(ped, true, 0)
            SetPedInfiniteAmmoClip(ped, true)
        end

        Citizen.CreateThread(function()
            while GodModeActive do
                local currentPed = PlayerPedId()

                if currentPed and currentPed ~= 0 then
                    SetEntityInvincible(currentPed, true)

                    if Config.GodMode.KeepArmour then
                        local armour = GetPedArmour(currentPed)
                        if armour < Config.GodMode.ArmourValue then
                            SetPedArmour(currentPed, Config.GodMode.ArmourValue)
                        end
                    end

                    local health = GetEntityHealth(currentPed)
                    local maxHealth = GetEntityMaxHealth(currentPed)
                    if health < maxHealth then
                        SetEntityHealth(currentPed, maxHealth)
                    end
                end

                Wait(Config.GodMode.HealIntervalMs)
            end
        end)

        if AdminState then AdminState.godmode = true end
        Notify('Godmode enabled', 'success')
    else
        local currentPed = PlayerPedId()

        if currentPed and currentPed ~= 0 then
            SetEntityInvincible(currentPed, false)
            SetPlayerInvincible(PlayerId(), false)
            SetPedCanRagdoll(currentPed, true)
            SetEntityProofs(currentPed, false, false, false, false, false, false, false, false)
            SetPedInfiniteAmmo(currentPed, false, 0)
            SetPedInfiniteAmmoClip(currentPed, false)

            if OriginalMaxHealth then
                SetEntityMaxHealth(currentPed, OriginalMaxHealth)
                OriginalMaxHealth = nil
            end
        end

        if AdminState then AdminState.godmode = false end
        Notify('Godmode disabled', 'info')
    end
end

RegisterNetEvent('grand_admin:client:SetGodMode', function(state)
    SetGodMode(state)
end)

exports('SetGodMode', SetGodMode)
exports('IsGodModeActive', function() return GodModeActive end)
