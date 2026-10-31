-- resources/[grand_systems]/grand_admin/client/noclip.lua
-- Smooth, FPS-independent noclip driven by camera-relative vector math.

local NoClipActive = false
local NoClipCoords = nil
local NoClipSpeedMult = 3.0 -- adjustable from the NUI slider
local WasFreezed = false

--- Movement follows the camera, not the frozen ped, so looking around while
--- flying behaves exactly like an editor camera.
---@return vector3 forward, vector3 right, vector3 up, number yaw
local function GetCameraBasis()
    local rot = GetGameplayCamRot(2)
    local rollDeg, pitchDeg, yawDeg = rot.x, rot.y, rot.z

    local roll  = math.rad(rollDeg)
    local pitch = math.rad(pitchDeg)
    local yaw   = math.rad(yawDeg)

    -- Standard GTA camera basis (Y axis is north, angles in radians).
    local forward = vector3(
        -math.sin(yaw) * math.abs(math.cos(pitch)),
        math.cos(yaw) * math.abs(math.cos(pitch)),
        math.sin(pitch)
    )

    local right = vector3(
        math.cos(yaw),
        math.sin(yaw),
        0.0
    )

    local up = vector3(0.0, 0.0, 1.0)

    return forward, right, up, yawDeg
end

--- Scales base speed by frame time so the admin flies the same distance per
--- second at 30fps as at 300fps.
---@param multiplier number
---@return number
local function GetSmoothSpeed(multiplier)
    local frameTime = GetFrameTime()
    if type(frameTime) ~= 'number' or frameTime <= 0.0 or frameTime > 1.0 then
        frameTime = 1 / 60
    end

    local factor = frameTime * 60.0
    local speed = Config.Noclip.BaseSpeed * multiplier * factor

    return math.max(Config.Noclip.MinSpeed, math.min(speed, Config.Noclip.MaxSpeed))
end

function SetNoclip(state)
    state = state and true or false
    if state == NoClipActive then return end

    local ped = PlayerPedId()
    NoClipActive = state

    if state then
        if Config.Noclip.ClearSurroundingsOnToggle then
            local coords = GetEntityCoords(ped)
            ClearArea(coords, Config.Noclip.ClearRadius, false, true, true, true, false)
        end

        NoClipCoords = GetEntityCoords(ped)
        SetEntityVisible(ped, false, false)
        SetEntityInvincible(ped, true)
        SetEntityCollision(ped, false, false)
        WasFreezed = false

        if AdminState then AdminState.noclip = true end

        Citizen.CreateThread(function()
            while NoClipActive do
                DisableAllControlActions(0)

                -- Re-enable the controls noclip itself needs.
                EnableControlAction(0, 1, true)   -- look left/right
                EnableControlAction(0, 2, true)   -- look up/down
                EnableControlAction(0, 17, true)  -- noclip toggle
                EnableControlAction(0, 245, true) -- interact
                EnableControlAction(0, 322, true) -- quick menu

                local pedHandle = PlayerPedId()

                local fwdInput   = GetDisabledControlNormal(0, 32)  -- W
                local backInput  = GetDisabledControlNormal(0, 33)  -- S
                local leftInput  = GetDisabledControlNormal(0, 34)  -- A
                local rightInput = GetDisabledControlNormal(0, 35)  -- D
                local upInput    = GetDisabledControlNormal(0, 44)  -- SPACE
                local downInput  = GetDisabledControlNormal(0, 38)  -- LEFT SHIFT

                local multiplier = NoClipSpeedMult
                if IsControlPressed(0, 21) then -- sprint
                    multiplier = multiplier * Config.Noclip.SprintMultiplier
                end

                local forward, right, up = GetCameraBasis()

                local delta = (forward * (fwdInput - backInput))
                    + (right * (rightInput - leftInput))
                    + (up * (upInput - downInput))

                local magnitude = #delta

                if magnitude > 0.001 then
                    -- Normalise then scale: diagonal movement is not faster than straight.
                    local speed = GetSmoothSpeed(multiplier)
                    local step = (delta / magnitude) * math.min(magnitude, 1.0) * speed

                    NoClipCoords = NoClipCoords + step
                    SetEntityCoordsNoOffset(pedHandle, NoClipCoords.x, NoClipCoords.y, NoClipCoords.z, false, false, false)

                    if WasFreezed then
                        FreezeEntityPosition(pedHandle, false)
                        WasFreezed = false
                    end
                elseif Config.Noclip.FreezeWhileIdle and not WasFreezed then
                    FreezeEntityPosition(pedHandle, true)
                    WasFreezed = true
                end

                Wait(0)
            end
        end)

        TriggerEvent('chat:addMessage', {
            color = { 255, 188, 0 },
            multiline = true,
            args = { 'Admin', 'Noclip enabled (WASD + Space/Shift)' }
        })
    else
        NoClipCoords = nil

        local currentPed = PlayerPedId()
        SetEntityVisible(currentPed, true, false)
        SetEntityCollision(currentPed, true, true)
        SetEntityInvincible(currentPed, AdminState and AdminState.godmode or false)

        if WasFreezed then
            FreezeEntityPosition(currentPed, false)
            WasFreezed = false
        end

        if AdminState then AdminState.noclip = false end

        TriggerEvent('chat:addMessage', {
            color = { 255, 188, 0 },
            multiline = true,
            args = { 'Admin', 'Noclip disabled' }
        })
    end
end

RegisterNetEvent('grand_admin:client:SetNoClip', function(state)
    SetNoclip(state)
end)

RegisterCommand('noclip', function()
    SetNoclip(not NoClipActive)
end, false)

exports('SetNoclip', SetNoclip)
exports('IsNoclipActive', function() return NoClipActive end)
exports('GetNoclipSpeed', function() return NoClipSpeedMult end)
exports('SetNoclipSpeedMultiplier', function(value)
    local v = tonumber(value)
    if not v then return end
    NoClipSpeedMult = math.max(1.0, math.min(v, 10.0))
end)
