-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/client/hud_bridge.lua
--  Every ~1s pushes a state bag / NUI message with health, armour,
--  hunger, thirst, stress, speed, seatbelt, money, job so HUD/phone
--  can render it; must not error when those resources are absent
--  (check `GetResourceState`).
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()
local Log = Util.Log

-- ─── State ──────────────────────────────────────────────────────

local HudState = {
    health    = 200,
    armour    = 0,
    hunger    = 100,
    thirst    = 100,
    stress    = 0,
    speed     = 0,
    seatbelt  = false,
    money     = { cash = 0, bank = 0, crypto = 0 },
    job       = 'unemployed',
    jobGrade   = 0,
    jobLabel   = 'Unemployed',
    faction   = nil,
    gang      = false,
    onDuty    = false,
    wanted    = 0,
    street    = '',
    zone      = '',
    time      = '00:00',
    date      = '01/01/1970',
    voice     = 0,
    radio     = false,
    talking   = false,
}

local PushThread = nil
local SeatbeltOn = false
local LastVehicle = 0
local LastStreet = ''
local LastZone = ''

-- ─── Helpers ────────────────────────────────────────────────────

--- Get current street and zone.
---@return string street, string zone
local function GetLocation()
    local ped = PlayerPedId()
    local coords = GetEntityCoords(ped)

    local streetHash, crossingHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local street = GetStreetNameFromHashKey(streetHash)
    local crossing = GetStreetNameFromHashKey(crossingHash)

    local zone = GetLabelText(GetNameOfZone(coords.x, coords.y, coords.z))
    if zone == 'NULL' then zone = '' end

    if crossing and crossing ~= '' then
        street = street .. ' / ' .. crossing
    end

    return street, zone
end

--- Get current vehicle speed.
---@return number kmh
local function GetSpeed()
    local ped = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return 0 end

    local speed = GetEntitySpeed(vehicle)
    return math.floor(speed * 3.6)  -- m/s → km/h
end

--- Get voice level (pma‑voice or saltychat).
---@return number 0‑3
local function GetVoiceLevel()
    if GetResourceState('pma‑voice') == 'started' then
        local level = exports['pma‑voice'].getVoiceLevel()
        return tonumber(level) or 0
    end

    if GetResourceState('saltychat') == 'started' then
        -- SaltyChat doesn't expose a level; assume 2 when talking.
        return IsPlayerTalking(PlayerId()) and 2 or 0
    end

    return 0
end

--- Whether radio is active (pma‑voice).
---@return boolean
local function IsRadioActive()
    if GetResourceState('pma‑voice') == 'started' then
        return exports['pma‑voice'].isRadioActive()
    end
    return false
end

--- Whether player is currently talking.
---@return boolean
local function IsTalking()
    return IsPlayerTalking(PlayerId())
end

--- Get current game time.
---@return string time, string date
local function GetGameTime()
    local hour = GetClockHours()
    local minute = GetClockMinutes()
    local day = GetClockDayOfWeek()
    local month = GetClockMonth()
    local year = GetClockYear()

    local time = ('%02d:%02d'):format(hour, minute)
    local date = ('%02d/%02d/%04d'):format(day, month, year)

    return time, date
end

-- ─── State bag (global) ──────────────────────────────────────────

--- Update the global state bag `grand_hud`.
local function UpdateStateBag()
    local bag = 'grand_hud'
    LocalPlayer.state:set(bag, HudState, true)
end

-- ─── NUI push ────────────────────────────────────────────────────

--- Send HudState to every NUI consumer listed in Config.Hud.Consumers.
local function PushNui()
    for _, consumer in ipairs(Config.Hud.Consumers) do
        if GetResourceState(consumer) == 'started' then
            SendNUIMessage({
                action = Config.Hud.NuiMessageAction or 'grand:hud',
                data = HudState,
            })
        end
    end
end

-- ─── Update loop ────────────────────────────────────────────────

local function StartPushLoop()
    PushThread = Citizen.CreateThread(function()
        while true do
            Wait(Config.Hud.Interval)

            -- Player must be loaded
            if not CurrentUser or not IsPlayerLoaded() then goto continue end

            local ped = PlayerPedId()

            -- Health / armour
            HudState.health = GetEntityHealth(ped) - 100  -- GTA offset
            HudState.armour = GetPedArmour(ped)

            -- Vitals (from CurrentUser or fallback)
            HudState.hunger = CurrentUser.hunger or 100
            HudState.thirst = CurrentUser.thirst or 100
            HudState.stress = CurrentUser.stress or 0

            -- Money
            HudState.money = CurrentUser.money or { cash = 0, bank = 0, crypto = 0 }

            -- Job
            HudState.job = CurrentUser.job or 'unemployed'
            HudState.jobGrade = CurrentUser.jobGrade or 0

            local jobDef = Config.JobIndex[HudState.job] or {}
            HudState.jobLabel = jobDef.label or Util.Humanize(HudState.job)
            HudState.faction = jobDef.faction
            HudState.gang = jobDef.gang or false
            HudState.onDuty = false -- server tracks duty; updated via grand_core:client:DutyChanged if needed

            -- Vehicle
            HudState.speed = GetSpeed()

            -- Seatbelt
            if IsPedInAnyVehicle(ped, false) then
                local vehicle = GetVehiclePedIsIn(ped, false)
                if vehicle ~= LastVehicle then
                    SeatbeltOn = false
                    LastVehicle = vehicle
                end
            else
                SeatbeltOn = false
                LastVehicle = 0
            end
            HudState.seatbelt = SeatbeltOn

            -- Wanted
            HudState.wanted = GetPlayerWantedLevel(PlayerId())

            -- Location
            local street, zone = GetLocation()
            if street ~= '' then LastStreet = street end
            if zone ~= '' then LastZone = zone end
            HudState.street = LastStreet
            HudState.zone = LastZone

            -- Time / date
            HudState.time, HudState.date = GetGameTime()

            -- Voice
            HudState.voice = GetVoiceLevel()
            HudState.radio = IsRadioActive()
            HudState.talking = IsTalking()

            -- Push
            UpdateStateBag()
            PushNui()

            ::continue::
        end
    end)
end

-- ─── Seatbelt toggle ────────────────────────────────────────────

--- Toggle seatbelt with a key press.
local function SeatbeltToggle()
    if not IsPedInAnyVehicle(PlayerPedId(), false) then return end
    SeatbeltOn = not SeatbeltOn

    if SeatbeltOn then
        Notify('Seatbelt fastened', 'success')
    else
        Notify('Seatbelt unfastened', 'warning')
    end
end

RegisterCommand('grandseatbelt', SeatbeltToggle, false)
RegisterKeyMapping('grandseatbelt', 'Toggle Seatbelt', 'keyboard', Config.Keys.SeatbeltToggle)

-- ─── Events ─────────────────────────────────────────────────────

--- Refresh HUD (called by other resources).
RegisterNetEvent('grand_core:client:HudRefresh', function()
    -- Force an immediate update
    if PushThread then
        -- loop will pick it up next tick
    end
end)

--- Money updated.
---@param wallet table
RegisterNetEvent('grand_core:client:MoneyUpdated', function(wallet)
    HudState.money = wallet
end)

--- Job changed.
---@param job string
---@param grade number
RegisterNetEvent('grand_core:client:JobChanged', function(job, grade)
    HudState.job = job
    HudState.jobGrade = grade
end)

--- Vitals updated.
---@param hunger number
---@param thirst number
---@param stress number
RegisterNetEvent('grand_core:client:SetVitals', function(hunger, thirst, stress)
    HudState.hunger = hunger
    HudState.thirst = thirst
    HudState.stress = stress
end)

--- Duty changed.
---@param onDuty boolean
RegisterNetEvent('grand_core:client:DutyChanged', function(onDuty)
    HudState.onDuty = onDuty
end)

--- Player loaded.
RegisterNetEvent('grand_core:client:PlayerLoaded', function()
    -- Wait for CurrentUser to populate
    Citizen.Wait(500)

    if not PushThread then
        StartPushLoop()
        Log('debug', 'HUD bridge loop started')
    end
end)

-- ─── Resource start ──────────────────────────────────────────────

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end

    -- Wait for player to load
    Citizen.SetTimeout(2000, function()
        if IsPlayerLoaded() and not PushThread then
            StartPushLoop()
        end
    end)
end)

-- ─── Exports ─────────────────────────────────────────────────────

--- Get current HUD state.
---@return table
exports('GetHudState', function()
    return Util.Copy(HudState)
end)

--- Set vitals (for external resources).
---@param hunger number
---@param thirst number
---@param stress number
exports('SetVitals', function(hunger, thirst, stress)
    HudState.hunger = Util.Clamp(hunger, 0, 100)
    HudState.thirst = Util.Clamp(thirst, 0, 100)
    HudState.stress = Util.Clamp(stress, 0, 100)
end)