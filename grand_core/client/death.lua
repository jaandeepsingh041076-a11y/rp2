-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/client/death.lua
--  Ragdoll, bleed-out timer, hospital transport, respawn cost.
--  Detection uses the `IsEntityDead` native only — no framework.
--
--  Threads here are stopped cooperatively: FiveM cannot cancel a
--  thread from outside, so every loop checks a live flag it owns.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()

GrandDeath = {}

local dead            = false
local downed          = false
local deathStamp      = 0
local deathPosition   = nil
local ragdollActive   = false
local bleedRunning    = false
local monitorRunning  = false

-- ─── Ragdoll ────────────────────────────────────────────────

--- Pins the ped to the ground and strips every control.
local function RagdollLoop()
    if ragdollActive then return end
    ragdollActive = true

    Citizen.CreateThread(function()
        local ped = PlayerPedId()
        SetPedToRagdoll(ped, 3000, 5000, 0, true, true, false)

        while ragdollActive do
            ped = PlayerPedId()

            -- Attack / aim / weapon wheel / cover / reload / melee
            local blocked = { 24, 25, 37, 44, 45, 69, 140, 141, 142, 257, 263, 264 }
            for i = 1, #blocked do
                DisableControlAction(0, blocked[i], true)
            end

            -- Movement + sprint + jump + crouch
            local movement = { 21, 22, 30, 31, 290, 310, 215, 1 }
            for i = 1, #movement do
                DisableControlAction(0, movement[i], true)
            end

            if not IsPedRagdoll(ped) and not IsPedFalling(ped) then
                SetPedToRagdoll(ped, 1500, 3000, 0, true, true, false)
            end

            Wait(0)
        end
    end)
end

function GrandDeath.StopRagdoll()
    ragdollActive = false

    local ped = PlayerPedId()
    NetworkResurrectLocalPlayer(GetEntityCoords(ped).x, GetEntityCoords(ped).y, GetEntityCoords(ped).z,
        GetEntityHeading(ped), true, false)
    ClearPedTasksImmediately(ped)
    SetEntityInvincible(ped, false)
end

-- ─── HUD text ───────────────────────────────────────────────

---@param text string
---@param r? number
---@param g? number
---@param b? number
local function DrawCentre(text, r, g, b)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextScale(0.0, 0.55)
    SetTextColour(r or 255, g or 30, b or 56, 215)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(2, 0, 0, 0, 150)
    SetTextDropShadow()
    SetTextOutline()
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    DrawText(0.5, 0.9)
end

-- ─── Bleed-out timer ────────────────────────────────────────

--- The downed state: the player can still cancel into a respawn.
function GrandDeath.StartBleedOut()
    if bleedRunning then return end
    bleedRunning = true

    Citizen.CreateThread(function()
        local total    = math.max(5, Config.Death.BleedOutSeconds)
        local deadline = GetGameTimer() + (total * 1000)

        while bleedRunning do
            local remaining = math.ceil((deadline - GetGameTimer()) / 1000)

            if remaining <= 0 then
                bleedRunning = false
                GrandDeath.Kill()
                break
            end

            DrawCentre(('BLEEDING OUT — %ss'):format(remaining))
            DrawCentre(('Hold ~r~BACKSPACE~w~ to call an ambulance for %s'):format(
                Util.FormatMoney(GrandDeath.GetBill())), 0, 176, 255)

            if IsControlPressed(0, Config.Keys.CancelDowned) then
                bleedRunning = false
                GrandDeath.RequestHospital()
                break
            end

            Wait(0)
        end

        bleedRunning = false
    end)
end

function GrandDeath.StopBleedOut()
    bleedRunning = false
end

-- ─── Death ──────────────────────────────────────────────────

--- Hard death: screen fades, then a hospital transport happens.
function GrandDeath.Kill()
    if not dead then return end

    bleedRunning = false
    GrandDeath.StopRagdoll()

    DoScreenFadeOut(Config.Death.FadeOutMs)
    while not IsScreenFadedOut() do Wait(0) end

    local bill = GrandDeath.RequestHospital()
    if not bill then return end

    Wait(400)
    DoScreenFadeIn(Config.Death.FadeInMs)
end

--- The hospital transport + billing the spec asks for.
---@return boolean
function GrandDeath.RequestHospital()
    local coords = Config.Positions.Hospital[1]
    local ped    = PlayerPedId()

    if deathPosition then
        local nearest = Util.Nearest(deathPosition, Config.Positions.Hospital)
        if nearest then coords = nearest end
    end

    -- Bill is only charged from the server (money lives there), so the client
    -- asks the server to settle up and respawn it.
    TriggerServerEvent('grand_core:server:Respawn', Util.Round(GetPlayerServerId(PlayerId())))

    SetEntityCoords(ped, coords.x, coords.y, coords.z, false, false, false, false)
    NetworkResurrectLocalPlayer(coords.x, coords.y, coords.z, coords.heading or 0.0, true, false)
    ClearPedTasksImmediately(ped)
    SetEntityHealth(ped, GetEntityMaxHealth(ped))

    if Config.Wanted.ClearOnRespawn then
        ClearPlayerWantedLevel(PlayerId())
    end

    dead = false
    downed = false
    bleedRunning = false
    ragdollActive = false
    deathPosition = nil

    TriggerEvent('grand_core:client:SetVitals', 100.0, 100.0,
        math.min(100, (CurrentUser and CurrentUser.stress or 0) + Config.Vitals.StressPerDeath))

    DoScreenFadeIn(Config.Death.FadeInMs)
    return true
end

-- ─── Bill preview (mirrors server/economy's maths) ──────────

---@return number
function GrandDeath.GetBill()
    local cost = Config.Death.RespawnCost
    local stars = GetPlayerWantedLevel(PlayerId())
    local penalty = Config.Wanted.Penalties and Config.Wanted.Penalties[stars]

    if penalty and penalty.cost then
        cost = cost + penalty.cost
    elseif stars > 0 then
        cost = cost + (stars * Config.Death.RespawnCostPerStar)
    end

    return math.min(cost, Config.Death.MaxRespawnCost)
end

---@return boolean
function GrandDeath.IsDead()
    return dead
end

---@return boolean
function GrandDeath.IsDowned()
    return downed
end

---@return table|nil
function GrandDeath.GetDeathPosition()
    return deathPosition
end

-- ─── Entering the downed state ──────────────────────────────

local function EnterDeath()
    if dead then return end

    dead = true
    downed = true
    deathStamp = GetGameTimer()
    deathPosition = GetEntityCoords(PlayerPedId())

    TriggerServerEvent('grand_core:server:WentDown', deathPosition)
    Notify(Config.Notifications.Death, 'error')

    RagdollLoop()
    GrandDeath.StartBleedOut()
end

function GrandDeath.ExitDeath()
    dead = false
    downed = false
    GrandDeath.StopBleedOut()
    GrandDeath.StopRagdoll()
    deathPosition = nil
end

-- ─── Monitor ────────────────────────────────────────────────

function GrandDeath.StartMonitor()
    if monitorRunning then return end
    monitorRunning = true

    Citizen.CreateThread(function()
        while monitorRunning do
            Wait(500)

            if CurrentUser and CurrentUser.citizenid then
                local ped = PlayerPedId()

                if DoesEntityExist(ped) and ped ~= 0 then
                    if IsEntityDead(ped) and not dead then
                        EnterDeath()
                    elseif not IsEntityDead(ped) and dead and not downed then
                        -- Revived by something external (EMS, admin, script).
                        GrandDeath.ExitDeath()
                    end
                end
            end
        end

        monitorRunning = false
    end)
end

function GrandDeath.StopMonitor()
    monitorRunning = false
end

-- ─── Revive window (EMS can revive free) ────────────────────

Citizen.CreateThread(function()
    while true do
        Wait(1000)

        if dead and deathStamp > 0 then
            local within = (GetGameTimer() - deathStamp) / 1000 < Config.Death.ReviveWindow
            if within then
                DrawCentre(('A paramedic can revive you free for %ds'):format(
                    math.ceil(Config.Death.ReviveWindow - (GetGameTimer() - deathStamp) / 1000)),
                    0, 255, 136)
            end
        end
    end
end)

-- ─── Events ─────────────────────────────────────────────────

RegisterNetEvent('grand_core:client:Revive', function(position, heal)
    GrandDeath.ExitDeath()

    if type(position) == 'table' then
        DoScreenFadeOut(800)
        while not IsScreenFadedOut() do Wait(0) end

        SetEntityCoords(PlayerPedId(), position.x, position.y, position.z, false, false, false, false)
        NetworkResurrectLocalPlayer(position.x, position.y, position.z, position.heading or 0.0, true, false)
        ClearPedTasksImmediately(PlayerPedId())
        DoScreenFadeIn(1000)
    end

    if heal ~= false then
        SetEntityHealth(PlayerPedId(), GetEntityMaxHealth(PlayerPedId()))
    end

    SetEntityInvincible(PlayerPedId(), false)
    Notify('You have been revived', 'success')
end)

RegisterNetEvent('grand_core:client:Killed', function()
    if not dead then
        dead = true
        EnterDeath()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end

    GrandDeath.StopMonitor()
    GrandDeath.StopBleedOut()
    ragdollActive = false
end)

-- ─── Exports ────────────────────────────────────────────────

exports('IsDead',              GrandDeath.IsDead)
exports('IsDowned',            GrandDeath.IsDowned)
exports('GetDeathPosition',    GrandDeath.GetDeathPosition)
exports('RespawnAtHospital',   GrandDeath.RequestHospital)
exports('GetRespawnBill',      GrandDeath.GetBill)
exports('ForceDown',           EnterDeath)

_G.GrandDeath = GrandDeath
