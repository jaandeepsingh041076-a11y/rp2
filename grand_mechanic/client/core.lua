-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/client/core.lua
--  Session cache, the marker/interaction engine every branch uses,
--  vehicle state snapshots (damage -> faults), keybinds, prompts.
--  No NUI: everything is in-world text + ox_lib notifications.
-- ─────────────────────────────────────────────────────────────

local Shared = Mechanic.Shared

local Mx = {}
Mechanic.Client = Mx

-- ─── Cached session ───────────────────────────────────────────
Mx.Session = { cid = nil, job = nil, xp = 0, level = 0, active = nil, outstanding = 0 }
Mx.Board = {}
Mx.Invoices = {}
Mx.HoardList = {}
Mx.TowList = {}

local interactables = {}   -- [handle] = { coords, radius, label, key, action, once }
local promptQueue = nil
local nearest = nil
local nearestDist = 0.0

-- ─── Notify (guarded ox_lib, then core, then print) ───────────
function Mx.Notify(msg, kind)
    kind = kind or 'inform'
    if lib and lib.notify then
        lib.notify({ title = 'Workforce', description = tostring(msg), type = kind, position = 'top', duration = 5000 })
        return
    end
    TriggerServerEvent('grand_core:server:Notify', msg, kind)
    print('[grand_mechanic] ' .. tostring(msg))
end

RegisterNetEvent('grand_core:client:Notify', function(message, k)
    if k == 'info' or k == 'inform' then k = 'inform' end
    if lib and lib.notify then
        lib.notify({ title = 'Grand RP', description = tostring(message), type = k, position = 'top' })
    end
end)

-- ─── Interaction registry ────────────────────────────────────
--- key: 'E' by default. action runs when the bind is pressed in range.
function Mx.Add(coords, radius, label, action, opts)
    opts = opts or {}
    local handle = #interactables + 1
    interactables[handle] = {
        coords = coords,
        radius = radius or 2.5,
        label = label,
        action = action,
        key = opts.key or 'E',
        icon = opts.icon,
        hidden = opts.hidden,
        job = opts.job,             -- require this job (or on the whitelist)
        repeatable = opts.repeatable ~= false,
        data = opts.data,
    }
    return handle
end

function Mx.Remove(handle)
    if interactables[handle] then interactables[handle].dead = true end
end

function Mx.Clear()
    for i in ipairs(interactables) do interactables[i].dead = true end
    interactables = {}
    nearest = nil
end

Mx.Interactables = interactables

-- ─── Job gate ─────────────────────────────────────────────────
function Mx.IsOnDuty(kind)
    local list = Config.Jobs[kind]
    if not list then return false end
    local job = Mx.Session.job
    if not job then return false end
    for _, j in ipairs(list) do
        if j == job then return true end
    end
    return false
end

Mx.CanWork = Mx.IsOnDuty

-- ─── Native guard ─────────────────────────────────────────────
-- Damage-model natives differ between game builds; anything missing
-- degrades to a sane default instead of throwing every frame.
local nativeCache = {}
local function Native(name, fallback, ...)
    local fn = nativeCache[name]
    if fn == nil then
        fn = (load('return ' .. name) or function() return nil end)()
        nativeCache[name] = fn or false
    end
    if fn == false then return fallback end
    local ok, result = pcall(fn, ...)
    if not ok or result == nil then return fallback end
    return result
end
Mx.Native = Native

function Mx.NetId(veh)
    local id = Native('VehToNet', 0, veh)
    return tonumber(id) or 0
end

-- ─── Vehicle state snapshot (the same shape the server prices) ──
---@param veh number
function Mx.Snapshot(veh)
    if not veh or veh == 0 or not DoesEntityExist(veh) then return nil end

    local doors = {}
    for i = 0, 5 do
        doors[i] = Native('IsVehicleDoorBroken', false, veh, i) and 0 or 1
    end

    -- tyres: burst + grip loss per corner
    local grip = 0
    local corners = { 'FL', 'FR', 'RL', 'RR' }
    local burstByIndex = { [0] = true, [1] = true, [2] = true, [3] = true,
                           [4] = true, [5] = true, [6] = true, [7] = true,
                           [8] = true, [9] = true, [10] = true, [11] = true, [12] = true }
    for index = 0, 12 do
        if burstByIndex[index] then
            if Native('IsVehicleTyreBurst', false, veh, index, false) then
                grip = grip + 0.55
            else
                local wear = Native('GetVehicleTyreVariable', 1.0, veh, index, 21)
                if type(wear) == 'number' and wear < 1.0 then grip = grip + (1.0 - wear) end
            end
        end
    end
    local tires = Shared.Clamp(100.0 - (grip / 4.0 * 100.0), 0.0, 100.0)

    local engine = tonumber(GetVehicleEngineHealth(veh)) or 1000.0
    local body   = tonumber(GetVehicleBodyHealth(veh)) or 1000.0
    local petrol = tonumber(GetVehiclePetrolTankHealth(veh)) or 1000.0

    -- no per-component brake/suspension health native: read them off the
    -- damage model, so a rear-end shunt shows up as suspension work.
    local rearDamage, frontDamage = 0.0, 0.0
    for i = 0, 5 do
        local d = Native('GetVehicleDoorRatioDamage', 0, veh, i) or 0
        if type(d) == 'number' and d > 1 then
            if i == 4 or i == 5 then rearDamage = rearDamage + d else frontDamage = frontDamage + d end
        end
    end

    local brokenWindows = 0
    for s = 0, 7 do
        if Native('IsVehicleWindowOff', false, veh, s, false) then brokenWindows = brokenWindows + 1 end
    end

    return {
        handle = veh,
        netId = Mx.NetId(veh),
        model = GetEntityModel(veh),
        modelName = Shared.ModelLabel(GetDisplayNameFromVehicleModel(GetEntityModel(veh))),
        plate = Shared.NormalisePlate(GetVehicleNumberPlateText(veh)),
        class = GetVehicleClass(veh),
        engineHealth = Shared.Clamp(engine, 0.0, 1000.0),
        bodyHealth = Shared.Clamp(body, 0.0, 1000.0),
        petrolTankHealth = Shared.Clamp(petrol, 0.0, 1000.0),
        brakes = Shared.Clamp(100.0 - (frontDamage * 9.0) - ((1000.0 - engine) / 250.0), 0.0, 100.0),
        suspension = Shared.Clamp(100.0 - (rearDamage * 8.0) - ((100.0 - tires) * 0.35), 0.0, 100.0),
        tires = tires,
        electricHealth = tonumber(Native('GetVehicleElectricEngineHealth', engine, veh)) or engine,
        glass = Shared.Clamp(100.0 - (brokenWindows * 14.0), 0.0, 100.0),
        doors = doors,
        fuelLevel = Shared.Clamp(petrol / 1000.0, 0.0, 1.0),
        locked = GetVehicleDoorLockStatus(veh) >= 2,
        alarm = Native('GetVehicleAlarmState', false, veh) and true or false,
        seatCount = 4,
        coords = GetEntityCoords(veh),
        heading = GetEntityHeading(veh),
        driver = GetPedInVehicleSeat(veh, -1),
    }
end

--- The faults a snapshot implies, priced for the local player's rank.
function Mx.Assess(veh, kind)
    local snap = type(veh) == 'table' and veh or Mx.Snapshot(veh)
    if not snap then return nil, nil end
    local faults = Shared.DeriveFaults(snap)
    local quote = Shared.Quote(faults, snap, Mx.Session.level or 0, kind or 'mechanic')
    return faults, quote, snap
end

-- ─── Prompt renderer + proximity loop ─────────────────────────
local KEYMAPS = {
    ['E'] = 38, ['F'] = 23, ['G'] = 47, ['H'] = 74, ['R'] = 45,
    ['T'] = 21, ['Y'] = 22, ['U'] = 30, ['V'] = 49, ['B'] = 8,
}

local keyLatch = {}
local function EdgePressed(key)
    local code = KEYMAPS[key] or 38
    local down = IsControlPressed(0, code)
    if down and not keyLatch[key] then
        keyLatch[key] = true
        return true
    elseif not down then
        keyLatch[key] = false
    end
    return false
end

function Mx.Marker(coords, radius, r, g, b)
    local pulse = 0.35 + (math.sin(GetGameFrameTime() * 0.0025) * 0.12)
    DrawMarker(28, coords.x, coords.y, coords.z + 0.02, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        (radius or 2.0) * 2.0, (radius or 2.0) * 2.0, 0.9,
        r or 255, g or 30, b or 56, math.floor(pulse * 180), false, false, 2, false, nil, nil, false)
end

local function PromptLabel(text)
    SetTextFont(4)
    SetTextScale(0.0, 0.30)
    SetTextColour(255, 188, 0, 235)
    SetTextCentre(true)
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(0.5, 0.80)
end

CreateThread(function()
    while true do
        local sleep = 450
        local pos = GetEntityCoords(PlayerPedId())

        nearest, nearestDist = nil, 0.0
        local candidate, candidateDist
        for handle, point in ipairs(interactables) do
            if not point.dead then
                local show = true
                if point.hidden then show = false end
                if point.job and not Mx.IsOnDuty(point.job) then show = false end
                if show then
                    local d = #(pos - point.coords)
                    if d <= point.radius and (not candidateDist or d < candidateDist) then
                        candidate, candidateDist, sleep = handle, d, 0
                    end
                end
            end
        end

        if candidate then
            local point = interactables[candidate]
            nearest, nearestDist = candidate, candidateDist
            Mx.Marker(point.coords, math.min(point.radius, 3.0))
            PromptLabel(('[%s]  %s'):format(point.key, point.label or 'Interact'))

            if EdgePressed(point.key) then
                local ok, err = pcall(point.action, point.data, point)
                if not ok then
                    Mx.Notify(('Interaction failed: %s'):format(tostring(err)), 'error')
                    print('[grand_mechanic] interaction error: ' .. tostring(err))
                end
                if point.once then Mx.Remove(candidate) end
                candidate = nil
            end
        end

        Wait(sleep)
    end
end)

function Mx.Nearest()
    if not nearest then return nil end
    return interactables[nearest]
end

-- ─── Progress bars (ox_lib when present, native fallback) ────
function Mx.Progress(label, seconds, anim)
    seconds = math.max(1, math.floor(seconds or 4))
    if lib and lib.progressBar then
        return lib.progressBar({
            duration = seconds * 1000,
            label = label or 'Working',
            useWhileDead = false,
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = anim,
        })
    end

    local ped = PlayerPedId()
    if anim and anim.dict then
        RequestAnimDict(anim.dict)
        local tries = 0
        while not HasAnimDictLoaded(anim.dict) and tries < 60 do tries = tries + 1 Wait(50) end
        TaskPlayAnim(ped, anim.dict, anim.clip or 'prop_hurt_armR_lo_a', 3.0, 3.0, -1, 49, 0, false, false, false)
    end

    local width = 0.24
    local finish = GetGameTimer() + (seconds * 1000)
    while GetGameTimer() < finish do
        local pct = Shared.Clamp((1.0 - ((finish - GetGameTimer()) / (seconds * 1000))), 0.0, 1.0)
        DrawRect(0.5, 0.86, width, 0.014, 10, 11, 14, 210)
        DrawRect(0.5 - (width / 2) + (width * pct / 2), 0.86, width * pct, 0.014, 255, 30, 56, 235)
        SetTextFont(4)
        SetTextScale(0.0, 0.30)
        SetTextColour(255, 255, 255, 240)
        SetTextCentre(true)
        SetTextOutline()
        BeginTextCommandDisplayText('STRING')
        AddTextComponentSubstringPlayerName(('%s  %ds'):format(label or 'WORKING',
            math.ceil((finish - GetGameTimer()) / 1000)))
        EndTextCommandDisplayText(0.5, 0.842)
        Wait(0)
    end

    ClearPedTasks(ped)
    return true
end

-- ─── Server sync ──────────────────────────────────────────────
RegisterNetEvent('grand_mechanic:client:Session', function(data)
    if type(data) ~= 'table' then return end
    Mx.Session.cid = data.cid
    Mx.Session.job = data.job
    Mx.Session.xp = data.xp or 0
    Mx.Session.level = data.level or 0
    Mx.Session.active = data.active
    Mx.Session.outstanding = data.outstanding or 0
    TriggerEvent('grand_mechanic:client:SessionReady', data)
end)

RegisterNetEvent('grand_mechanic:client:JobSync', function(rows)
    Mx.Board = type(rows) == 'table' and rows or {}
    TriggerEvent('grand_mechanic:client:BoardChanged', Mx.Board)
end)

RegisterNetEvent('grand_mechanic:client:JobCancelled', function(ref)
    for i, job in ipairs(Mx.Board) do
        if job.ref == ref then table.remove(Mx.Board, i) break end
    end
end)

RegisterNetEvent('grand_mechanic:client:Claimed', function(job)
    Mx.Session.active = job and job.ref
    Mx.Notify(('Claimed %s — %s'):format(job and job.ref or '', (job and job.model) or 'vehicle'), 'success')
end)

RegisterNetEvent('grand_mechanic:client:Completed', function(data)
    Mx.Session.active = nil
    Mx.Notify(('$%s banked — level %d'):format(Shared.Money(data.payout or 0), (data.level or 0) + 1), 'success')
end)

RegisterNetEvent('grand_mechanic:client:InvoiceList', function(rows, total)
    Mx.Invoices = rows or {}
    Mx.Session.outstanding = total or 0
end)

RegisterNetEvent('grand_mechanic:client:HoardList', function(rows)
    Mx.HoardList = rows or {}
end)

RegisterNetEvent('grand_mechanic:client:TowMeter', function(rows)
    Mx.TowList = rows or {}
end)

-- ─── Board print (chat, no NUI) ───────────────────────────────
RegisterNetEvent('grand_mechanic:client:OpenBoard', function(rows)
    Mx.Board = rows or {}
    local lines = { '^1≡ WORKFORCE BOARD' }
    if #Mx.Board == 0 then lines[#lines + 1] = '^7  nothing open — keep driving' end
    for _, job in ipairs(Mx.Board) do
        lines[#lines + 1] = ('^3%s  ^7%s  %s  $%s  %s%s'):format(
            job.ref, (job.kind or ''):upper(), job.plate or '----',
            Shared.Money(job.estimate or 0), job.status or '',
            job.worker and (' (' .. job.worker:sub(1, 6) .. ')') or '')
    end
    TriggerEvent('chat:addMessage', { multiline = true, args = lines })
end)

-- ─── Keybinds ─────────────────────────────────────────────────
RegisterCommand('work', function()
    TriggerServerEvent('grand_mechanic:server:RequestSession')
    TriggerEvent('grand_mechanic:client:OpenBoard', Mx.Board)
end, false)
RegisterKeyMapping('work', 'Grand RP: workforce board', 'keyboard', 'F6')

RegisterCommand('workscan', function()
    TriggerEvent('grand_mechanic:client:RunScan')
end, false)
RegisterKeyMapping('workscan', 'Grand RP: OBD scan nearest vehicle', 'keyboard', 'F7')

RegisterCommand('workclaim', function(_, args)
    TriggerServerEvent('grand_mechanic:server:Claim', args[1] or '')
end, false)

RegisterCommand('workabandon', function()
    TriggerServerEvent('grand_mechanic:server:Abandon')
end, false)

-- ─── Boot handshake ───────────────────────────────────────────
CreateThread(function()
    Wait(1200)
    TriggerServerEvent('grand_mechanic:server:RequestSession')
    Wait(2500)
    TriggerServerEvent('grand_mechanic:server:MyInvoices')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    Mx.Clear()
end)

exports('Session', function() return Mx.Session end)
exports('Snapshot', Mx.Snapshot)
exports('Assess', Mx.Assess)
exports('Notify', Mx.Notify)
exports('Progress', Mx.Progress)
exports('AddInteraction', Mx.Add)
exports('IsOnDuty', Mx.IsOnDuty)

_G.Mechanic = Mechanic
if not _G.lib and GetResourceState('ox_lib') == 'started' then
    lib = exports['ox_lib']
end
