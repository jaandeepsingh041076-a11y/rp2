-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/client/main.lua
--  Spawn / respawn, the notification shim every other client script
--  uses, screen fades, hospital positioning and the death trigger.
--  No framework object is read anywhere — state lives in CurrentUser
--  (client/loaded.lua) and the core state bag.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()

GrandCore = GrandCore or {}

-- ─── Notification shim ─────────────────────────────────────
-- Mirrors resources/[grand_systems]/grand_admin/client/notify.lua so the
-- two resources behave identically, but routes through ox_lib / chat only.

local frontend

local function DetectFrontend()
    if frontend then return frontend end

    if GetResourceState('ox_lib') == 'started' then
        frontend = 'oxlib'
    elseif GetResourceState('grand_admin') == 'started' then
        frontend = 'panel'
    else
        frontend = 'chat'
    end

    return frontend
end

-- Grand RP Section 01 palette, RGB so chat colours match the UI
local Colours = {
    success = { 0, 255, 136 },   -- emerald cash
    error   = { 255, 30, 56 },   -- crimson
    warning = { 255, 145, 0 },   -- vitals orange
    primary = { 255, 188, 0 },   -- grand gold
    info    = { 0, 176, 255 }    -- sapphire bank
}

---@param message string
---@param kind? string 'success' | 'error' | 'warning' | 'info' | 'primary'
function Notify(message, kind)
    if message == nil then return end

    kind = kind or 'info'
    local text = tostring(message)

    if DetectFrontend() == 'oxlib' then
        local ok = pcall(lib.notify, {
            title       = 'Grand RP',
            description = text,
            type        = kind == 'primary' and 'inform' or kind,
            duration    = 4500,
        })
        if ok then return end
    end

    TriggerEvent('chat:addMessage', {
        color     = Colours[kind] or Colours.info,
        multiline = true,
        args      = { 'Grand RP', text },
    })
end

exports('Notify', Notify)

RegisterNetEvent('grand_core:client:Notify', function(message, kind)
    Notify(message, kind)
end)

-- ─── Screen fade helpers ───────────────────────────────────

---@param ms number
function GrandCore.FadeOut(ms)
    DoScreenFadeOut(math.max(100, ms))

    local deadline = GetGameTimer() + ms + 2500
    while not IsScreenFadedOut() and GetGameTimer() < deadline do
        Wait(0)
    end
end

---@param ms number
function GrandCore.FadeIn(ms)
    DoScreenFadeIn(math.max(100, ms))

    local deadline = GetGameTimer() + ms + 2500
    while not IsScreenFadedIn() and GetGameTimer() < deadline do
        Wait(0)
    end
end

-- ─── Positioning ───────────────────────────────────────────

---@param position table
---@param heading? number
local function PlacePed(position, heading)
    local ped = PlayerPedId()
    local x, y, z = position.x, position.y, position.z
    local h = tonumber(heading or position.heading) or 0.0

    RequestCollisionAtCoord(x, y, z)

    local deadline = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        Wait(10)
    end

    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    SetEntityHeading(ped, h)
    ClearPedTasksImmediately(ped)

    if IsEntityDead(ped) then
        NetworkResurrectLocalPlayer(x, y, z, h, true, false)
        SetEntityHealth(ped, GetEntityMaxHealth(ped))
    end
end

--- Nearest configured spawn point to where the ped already stands.
---@param list table
---@return table
local function PickPoint(list)
    if type(list) ~= 'table' or #list == 0 then
        return { x = -1037.0, y = -2737.0, z = 20.16, heading = 335.0 }
    end

    if #list == 1 then return list[1] end

    local nearest = Util.Nearest(GetEntityCoords(PlayerPedId()), list)
    return nearest or list[1]
end

-- ─── Spawn ──────────────────────────────────────────────────

--- First spawn after the character is loaded.
---@param position? table  saved position from the session
function GrandCore.Spawn(position)
    local target = type(position) == 'table' and tonumber(position.x) and position
        or PickPoint(Config.Positions.Spawn)

    GrandCore.FadeOut(Config.Death.FadeOutMs)

    PlacePed(target, target.heading)

    SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
    SetPedArmour(PlayerPedId(), 0)
    ClearPlayerWantedLevel(PlayerId())
    SetPlayerInvincible(PlayerId(), false)

    TriggerServerEvent('grand_core:server:PlayerReady', {
        x = target.x, y = target.y, z = target.z, heading = target.heading or 0.0,
    })

    GrandCore.FadeIn(Config.Death.FadeInMs)
    GrandCore.spawned = true
end

--- Respawn the player at a hospital and have the server bill them.
function GrandCore.Respawn()
    if GrandCore.respawnPending then return end
    GrandCore.respawnPending = true

    GrandCore.FadeOut(Config.Death.FadeOutMs)
    TriggerServerEvent('grand_core:server:RequestRespawn')

    GrandCore.respawnPending = false
end

exports('Spawn',   GrandCore.Spawn)
exports('Respawn', GrandCore.Respawn)

-- ─── Server-driven respawn ─────────────────────────────────

RegisterNetEvent('grand_core:client:DoRespawn', function(position, bill)
    local target = type(position) == 'table' and tonumber(position.x) and position
        or PickPoint(Config.Positions.Hospital)

    if GrandDeath then GrandDeath.ExitDeath() end

    PlacePed(target, target.heading)

    SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
    ClearPlayerWantedLevel(PlayerId())
    SetPedArmour(PlayerPedId(), 0)

    TriggerEvent('grand_core:client:SetVitals', 100.0, 100.0, 0.0)

    GrandCore.FadeIn(Config.Death.FadeInMs)

    if bill and bill > 0 then
        Notify(Config.Notifications.Hospital:format(Util.FormatMoney(bill)), 'warning')
    else
        Notify('You have been treated at ' .. (target.name or 'the hospital'), 'info')
    end
end)

-- ─── Death trigger ─────────────────────────────────────────

--- Any script that kills a player cleanly calls this.
RegisterNetEvent('grand_core:client:OnPlayerDied', function(killer, reason)
    if GrandDeath and GrandDeath.IsDead and GrandDeath.IsDead() then return end

    local ped = PlayerPedId()
    SetPedToRagdoll(ped, 5000, 5000, 0, true, true, false)
    SetPlayerInvincible(PlayerId(), true)

    TriggerServerEvent('grand_core:server:WentDown', {
        x = GetEntityCoords(ped).x,
        y = GetEntityCoords(ped).y,
        z = GetEntityCoords(ped).z,
    })

    if killer and killer ~= 0 and killer ~= PlayerId() then
        Notify('You were attacked', 'error')
    else
        Notify(Config.Notifications.Death .. (reason and (' (%s)'):format(reason) or ''), 'error')
    end
end)

-- ─── Vitals sync ───────────────────────────────────────────

local vitals = { hunger = 100.0, thirst = 100.0, stress = 0.0 }

--- Other resources (food, drink, stress events) call this event.
RegisterNetEvent('grand_core:client:SetVitals', function(hunger, thirst, stress)
    vitals.hunger = Util.Clamp(hunger, 0, 100)
    vitals.thirst = Util.Clamp(thirst, 0, 100)
    vitals.stress = Util.Clamp(stress, 0, 100)

    if CurrentUser then
        CurrentUser.hunger = vitals.hunger
        CurrentUser.thirst = vitals.thirst
        CurrentUser.stress = vitals.stress
    end
end)

exports('GetVitals', function() return Util.Copy(vitals) end)

--- Passive decay + push to the server so the values persist.
Citizen.CreateThread(function()
    local lastPush = 0

    while true do
        Wait(10000)

        if CurrentUser and CurrentUser.citizenid and not (GrandDeath and GrandDeath.IsDead()) then
            local minutes = 10 / 60

            vitals.hunger = math.max(0.0, vitals.hunger - Config.Vitals.HungerDecayPerMinute * minutes)
            vitals.thirst = math.max(0.0, vitals.thirst - Config.Vitals.ThirstDecayPerMinute * minutes)
            vitals.stress = math.max(Config.Vitals.MinStress,
                math.min(Config.Vitals.MaxStress, vitals.stress - Config.Vitals.StressDecayPerMinute * minutes))

            if CurrentUser then
                CurrentUser.hunger = vitals.hunger
                CurrentUser.thirst = vitals.thirst
                CurrentUser.stress = vitals.stress
            end

            if GetGameTimer() - lastPush > 60000 then
                lastPush = GetGameTimer()
                TriggerServerEvent('grand_core:server:SyncVitals', vitals.hunger, vitals.thirst, vitals.stress)
            end

            -- Starvation: cross zero and the ped starts taking damage.
            if Config.Vitals.OverflowDamage and (vitals.hunger <= 0 or vitals.thirst <= 0) then
                local ped = PlayerPedId()
                local health = GetEntityHealth(ped)
                if health > 105 then
                    SetEntityHealth(ped, health - 1)
                end
            end
        end
    end
end)

-- ─── Activity heartbeat ────────────────────────────────────
-- Keeps the server's AFK counter at zero and refreshes the ped handle.

local lastPosition, lastWeapon, lastHealth, lastVehicle

local function HasActed()
    local ped = PlayerPedId()
    if ped == 0 then return false end

    local position = GetEntityCoords(ped)
    local moved = lastPosition and #(position - lastPosition) > 0.35
    lastPosition = position

    local weapon  = GetSelectedPedWeapon(ped)
    local health  = GetEntityHealth(ped)
    local vehicle = GetVehiclePedIsIn(ped, false)

    local changed = (lastWeapon ~= weapon) or (lastHealth ~= health) or (lastVehicle ~= vehicle)
    lastWeapon, lastHealth, lastVehicle = weapon, health, vehicle

    return moved or changed or IsPlayerFreeAiming(PlayerId())
end

Citizen.CreateThread(function()
    while true do
        Wait(Config.Progress.ActivityInterval * 1000)

        if CurrentUser and CurrentUser.citizenid and not IsPauseMenuActive() then
            if HasActed() then
                TriggerServerEvent('grand_core:server:Activity')
            end
        end
    end
end)

-- ─── Position writer ───────────────────────────────────────

Citizen.CreateThread(function()
    while true do
        Wait(Config.Persistence.PositionInterval * 1000)

        if GrandCore.spawned and CurrentUser and CurrentUser.citizenid then
            local ped = PlayerPedId()
            if ped ~= 0 and not IsEntityDead(ped) then
                local coords = GetEntityCoords(ped)
                TriggerServerEvent('grand_core:server:SyncPosition', {
                    x = coords.x, y = coords.y, z = coords.z,
                    heading = GetEntityHeading(ped),
                })
            end
        end
    end
end)

-- ─── Boot ──────────────────────────────────────────────────

RegisterNetEvent('grand_core:client:PlayerLoaded', function(citizenid, firstname, lastname, job, money)
    if GrandCore.spawned then return end

    Wait(250)
    GrandCore.Spawn(CurrentUser and CurrentUser.position)

    Notify(('Welcome back, %s %s'):format(firstname or '', lastname or ''), 'primary')

    TriggerEvent('grand_core:client:HudRefresh')
    if GrandDeath then GrandDeath.StartMonitor() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    if GrandDeath then
        GrandDeath.StopMonitor()
        GrandDeath.StopBleedOut()
    end

    SetPlayerInvincible(PlayerId(), false)
    DoScreenFadeIn(500)
end)

-- ─── Commands ──────────────────────────────────────────────

RegisterCommand('grandrespawn', function()
    if GrandDeath and GrandDeath.IsDead() then
        GrandCore.Respawn()
    else
        Notify('You are not down', 'error')
    end
end, false)

RegisterCommand('grandhud', function()
    TriggerEvent('grand_core:client:HudRefresh')
    Notify('HUD state re-pushed', 'info')
end, false)

exports('IsSpawned', function() return GrandCore.spawned == true end)

_G.GrandCore = GrandCore
