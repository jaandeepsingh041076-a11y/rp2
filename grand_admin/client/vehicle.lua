-- resources/[grand_systems]/grand_admin/client/vehicle.lua
-- Vehicle spawner: model validation, plate assignment, clean spawn placement.

local SpawnedVehicles = {}
local LastSpawnedVehicle = nil

-- --------------------------------------------------------------------------
-- Placement
-- --------------------------------------------------------------------------

--- Finds a safe spawn position: in front of the camera, ground-snapped,
--- and cleared of any blocking traffic.
---@param distance number
---@return vector3, number heading
local function GetSpawnLocation(distance)
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)
    local camRot = GetGameplayCamRot(2)
    local heading = GetEntityHeading(ped)

    local forward = vector3(
        -math.sin(math.rad(camRot.z)),
        math.cos(math.rad(camRot.z)),
        0.0
    )

    local target = coords + (forward * distance)

    -- Snap to the ground so cars do not spawn inside the road or in the air.
    local found, groundZ = GetGroundZFor_3dCoord(target.x, target.y, target.z + 2.0, false)
    if found then
        target = vector3(target.x, target.y, groundZ + Config.VehicleSpawner.GroundOffset)
    end

    -- Push the point onto a drivable road if one is close by.
    local nodeOk, nodePos = GetClosestVehicleNode(target.x, target.y, target.z, 1, 50.0, 0)
    if nodeOk and #(nodePos - target) < Config.VehicleSpawner.MaxSpawnDistance then
        heading = GetVehicleNodeHeading(nodePos) or heading
    end

    return target, heading
end

--- Requests the model and waits for it to stream, with a hard timeout so a bad
--- model name can never hang a thread forever.
---@param model string
---@return number|nil hash
local function RequestModelSafe(model)
    local hash = joaat(model)

    if not IsModelInCdimage(hash) or IsModelAVehicle(hash) == false then
        return nil
    end

    RequestModel(hash)

    local deadline = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do
        Wait(50)
    end

    if not HasModelLoaded(hash) then
        SetModelAsNoLongerNeeded(hash)
        return nil
    end

    return hash
end

-- --------------------------------------------------------------------------
-- Spawn
-- --------------------------------------------------------------------------

local function SpawnVehicle(model, plate)
    if not model then return end

    local hash = RequestModelSafe(model)
    if not hash then
        Notify(('Model "%s" is invalid or could not load'):format(model), 'error')
        return
    end

    local position, heading = GetSpawnLocation(Config.VehicleSpawner.SpawnDistance)

    -- Make sure nothing is parked where we are about to spawn.
    ClearAreaOfVehicles(position.x, position.y, position.z, 10.0, false, false, false, false, false)
    ClearAreaOfPeds(position.x, position.y, position.z, 8.0, 0)
    Wait(150)

    local vehicle = CreateVehicle(hash, position.x, position.y, position.z, heading, true, false)

    if not vehicle or vehicle == 0 then
        Notify('Failed to create vehicle', 'error')
        SetModelAsNoLongerNeeded(hash)
        return
    end

    -- Plate assignment: uppercase, trimmed to the engine's 8-char limit.
    local finalPlate = (plate or GenerateClientPlate()):upper():gsub('%s', ''):sub(1, 8)
    SetVehicleNumberPlateText(vehicle, finalPlate)

    if Config.VehicleSpawner.DefaultNumberPlateStyle then
        SetVehicleNumberPlateTextIndex(vehicle, Config.VehicleSpawner.DefaultNumberPlateStyle)
    end

    SetVehicleEngineOn(vehicle, true, true, false)
    SetVehicleDirtLevel(vehicle, 0.0)
    SetVehiclePetrolTankHealth(vehicle, 4000.0)
    SetVehicleTyresCanBurst(vehicle, false)

    SetModelAsNoLongerNeeded(hash)

    local ped = PlayerPedId()
    local seat = Config.VehicleSpawner.SeatPosition == 'driver' and -1 or 0
    TaskWarpPedIntoVehicle(ped, vehicle, seat)

    SpawnedVehicles[#SpawnedVehicles + 1] = vehicle
    LastSpawnedVehicle = vehicle

    -- Persist ownership so the car survives a relog if the garage resource reads it.
    TriggerServerEvent('grand_admin:server:RecordVehicle', model, finalPlate)

    Notify(('%s spawned [%s]'):format(model:upper(), finalPlate), 'success')
end

RegisterNetEvent('grand_admin:client:SpawnVehicle', function(model, plate)
    SpawnVehicle(model, plate)
end)

--- Fallback plate generator, used when the server did not supply one.
function GenerateClientPlate()
    local prefix = (Config.VehicleSpawner.PlatePrefix or ''):upper()
    local length = math.max(1, math.min(8 - #prefix, Config.VehicleSpawner.PlateLength or 8))
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local out = {}

    for _ = 1, length do
        local i = math.random(1, #chars)
        out[#out + 1] = chars:sub(i, i)
    end

    return (prefix .. table.concat(out)):sub(1, 8)
end

-- --------------------------------------------------------------------------
-- Delete
-- --------------------------------------------------------------------------

local function DeleteVehicleHandle(vehicle)
    if not vehicle or vehicle == 0 or DoesEntityExist(vehicle) == false then return false end

    local ped = PlayerPedId()
    if IsPedInVehicle(ped, vehicle, false) then
        TaskLeaveVehicle(ped, vehicle, 16)
        Wait(500)
    end

    SetEntityAsMissionEntity(vehicle, true, true)
    DeleteVehicle(vehicle)
    DeleteEntity(vehicle)

    return true
end

--- Deletes the most recently spawned vehicle. Owned by this file; the NUI
--- endpoint in client/main.lua forwards here through the export.
local function DeleteLastVehicle()
    if not LastSpawnedVehicle then
        return false, 'No vehicle spawned this session'
    end

    local removed = DeleteVehicleHandle(LastSpawnedVehicle)

    if removed then
        for i = #SpawnedVehicles, 1, -1 do
            if SpawnedVehicles[i] == LastSpawnedVehicle then
                table.remove(SpawnedVehicles, i)
            end
        end
        LastSpawnedVehicle = nil
        Notify('Vehicle deleted', 'success')
        return true, 'Vehicle deleted'
    end

    LastSpawnedVehicle = nil
    return false, 'Vehicle no longer exists'
end

-- `spawnVehicle` / `deleteCurrentVehicle` NUI endpoints live in client/main.lua.
-- Do not register them here.

exports('DeleteLastVehicle', DeleteLastVehicle)

exports('GetSpawnedVehicles', function()
    return SpawnedVehicles
end)

exports('GetLastSpawnedVehicle', function()
    return LastSpawnedVehicle
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for _, vehicle in ipairs(SpawnedVehicles) do
        if DoesEntityExist(vehicle) then
            SetEntityAsMissionEntity(vehicle, true, true)
            DeleteEntity(vehicle)
        end
    end
end)
