-- resources/[grand_systems]/grand_admin/client/spectate.lua
-- Ghost-cam spectate: hides the admin, locks camera onto the target's ped,
-- and travels to them automatically when they get too far away.

local SpectatingTarget = 0
local SpectateActive = false
local OriginalCoords = nil
local CamHandle = nil
local SpectateThread = nil

-- --------------------------------------------------------------------------
-- Camera handling
-- --------------------------------------------------------------------------

local function CreateSpectateCam()
    local cam = CreateCamWithParams(
        'DEFAULT_SCRIPTED_CAMERA',
        0.0, 0.0, 0.0,
        0.0, 0.0, 0.0,
        45.0,
        false,
        2
    )
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 800, true, false)
    return cam
end

local function DestroySpectateCam()
    if CamHandle then
        RenderScriptCams(false, true, 800, true, false)
        SetCamActive(CamHandle, false)
        DestroyCam(CamHandle, false)
        CamHandle = nil
    end
end

-- --------------------------------------------------------------------------
-- Core
-- --------------------------------------------------------------------------

local function CleanupSpectate()
    SpectateActive = false
    SpectatingTarget = 0

    DestroySpectateCam()

    if SpectateThread then
        SpectateThread = false
    end

    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    ClearPedTasksImmediately(ped)

    SetPlayerInvincible(PlayerId(), false)

    if AdminState then AdminState.spectating = nil end
end

function SetSpectating(target)
    if not target then
        CleanupSpectate()
        return
    end

    local targetPed = GetPlayerPed(target)
    if not targetPed or targetPed == 0 then
        Notify('Target player not found', 'error')
        return
    end

    if SpectateActive then
        -- Switching targets: drop the old camera first.
        DestroySpectateCam()
    end

    local myPed = PlayerPedId()
    OriginalCoords = GetEntityCoords(myPed)

    SpectatingTarget = target
    SpectateActive = true
    if AdminState then AdminState.spectating = target end

    -- Become a non-interfering observer.
    SetEntityVisible(myPed, false, false)
    SetEntityInvincible(myPed, true)
    FreezeEntityPosition(myPed, true)
    SetEntityCollision(myPed, false, false)
    TriggerEvent('illuminated:client:toggleVis', true) -- no-op if ILP missing

    CamHandle = CamHandle or CreateSpectateCam()

    Citizen.CreateThread(function()
        while SpectateActive do
            local ped = GetPlayerPed(SpectatingTarget)

            if not ped or ped == 0 or DoesEntityExist(ped) == false then
                Notify('That player is no longer online', 'error')
                break
            end

            local targetCoords = GetEntityCoords(ped)
            local adminCoords = GetEntityCoords(PlayerPedId())
            local distance = #(adminCoords - targetCoords)

            -- Follow at a comfortable offset behind/above the target.
            local targetHeading = GetEntityHeading(ped)
            local offset = GetOffsetFromEntityInWorldCoords(ped, 0.0, -Config.Spectate.MinDistance * 0.6, 2.5)

            if Config.Spectate.CollisionAware then
                local hit, endPos = GetShapeTestResult(
                    StartShapeTestLOS(adminCoords.x, adminCoords.y, adminCoords.z,
                        targetCoords.x, targetCoords.y, targetCoords.z + 1.0, 1, myPed)
                )
                if hit == 1 then
                    offset = targetCoords + vector3(0.0, 0.0, 2.0)
                end
            end

            SetEntityCoordsNoOffset(myPed, offset.x, offset.y, offset.z, false, false, false)
            SetEntityHeading(myPed, targetHeading)

            -- Frame the target from the camera.
            local camPos = GetEntityCoords(myPed)
            local lookAt = targetCoords + vector3(0.0, 0.0, 1.0)

            SetCamCoord(CamHandle, camPos.x, camPos.y, camPos.z)
            PointCamAtCoord(CamHandle, lookAt.x, lookAt.y, lookAt.z)

            -- Keep the world loaded around who we are watching.
            if Config.Spectate.AutoTravel and distance > Config.Spectate.AutoTravelDistance then
                SetEntityCoordsNoOffset(myPed, targetCoords.x, targetCoords.y, targetCoords.z, false, false, false)
            end

            Wait(Config.Spectate.UpdateIntervalMs)
        end

        CleanupSpectate()
    end)

    Notify(('Now spectating %s'):format(GetPlayerName(target) or tostring(target)), 'info')
end

RegisterNetEvent('grand_admin:client:SpectatePlayer', function(target)
    SetSpectating(target)
end)

RegisterNetEvent('grand_admin:client:StopSpectating', function()
    if AdminState then AdminState.spectating = nil end
    CleanupSpectate()
end)

-- If the target disconnects we are told to stop.
RegisterNetEvent('grand_admin:client:SpectateTargetLeft', function()
    if AdminState then AdminState.spectating = nil end
    CleanupSpectate()
end)

exports('SetSpectating', SetSpectating)
exports('IsSpectating', function() return SpectateActive end)