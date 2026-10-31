-- resources/[grand_systems]/grand_admin/server/main.lua
-- Authority for every privileged action. Nothing here trusts the client.
-- Player data comes from server/bridge.lua (Grand RP schema), not a framework.

local RESOURCE = GetCurrentResourceName()

--- @see server/bridge.lua
local Bridge = _G.GrandBridge

local PlayerStates = {}

local IS_STAFF_MENU = Config.Permissions.AceIdentifiers
local IS_STAFF_FULL = Config.Permissions.AceFull

local function RequireBridge()
    if Bridge then return true end

    print(('^1[%s]^7 server/bridge.lua did not load - check the manifest load order^7'):format(RESOURCE))
    return false
end

-- ---------------------------------------------------------------------------
-- Permissions
-- ---------------------------------------------------------------------------

--- @return boolean canMenu, boolean canFull
local function HasPermission(source)
    if not RequireBridge() then return false, false end
    if source == 0 then return true, true end

    local hasMenuAce = IsPlayerAceAllowed(tostring(source), IS_STAFF_MENU)
    local hasFullAce = IsPlayerAceAllowed(tostring(source), IS_STAFF_FULL)

    if Config.Permissions.RequireAce then
        if not hasMenuAce and not hasFullAce then
            return false, false
        end
    elseif hasMenuAce or hasFullAce then
        return true, hasFullAce
    end

    -- Configured staff identifiers are always allowed.
    local identifiers = GetPlayerIdentifiers(source) or {}
    for _, allowed in ipairs(Config.Permissions.Identifiers or {}) do
        for _, identifier in ipairs(identifiers) do
            if identifier == allowed then
                return true, true
            end
        end
    end

    -- Group-based access, e.g. add_principal identifier.fivem:1 group.admin
    if Bridge.InGroup(source, Config.Permissions.Groups) then
        return true, IsPlayerAceAllowed(tostring(source), 'group.' .. (Config.Permissions.FullGroup or 'superadmin'))
    end

    return false, false
end

--- Permission gate shared by every callback below.
local function Guard(source, targetId)
    local canMenu = HasPermission(source)
    if not canMenu then
        return false, 'Insufficient permission'
    end

    if source ~= 0 and not PlayerStates[source] then
        PlayerStates[source] = { godmode = false, noclip = false, spectating = nil }
    end

    if targetId ~= nil then
        local resolved = Bridge.ResolveTarget(targetId)
        if not resolved then
            return false, 'Target player is not online'
        end
        if resolved == source then
            return false, 'You cannot target yourself'
        end
        return true, nil, resolved
    end

    return true
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

local function LogAction(source, action, targetId, details)
    local admin = Bridge and Bridge.GetDisplayName(source) or 'Console'
    local adminCitizen = source ~= 0 and Bridge.GetCitizenId(source) or 'console'
    local target = targetId and (Bridge.GetDisplayName(targetId) .. ' (#' .. tostring(targetId) .. ')') or '-'

    print(('^3[%s]^7 %s (%s) -> %s | %s %s'):format(
        RESOURCE, admin, adminCitizen, target, action, details or ''))

    if Config.Moderation.LogToDatabase then
        pcall(function()
            MySQL.insert.await([[
                INSERT INTO grand_admin_logs (admin, admin_citizenid, action, target, details)
                VALUES (?, ?, ?, ?, ?)
            ]], { admin, adminCitizen, action, tostring(targetId), details or '' })
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Callbacks
-- ---------------------------------------------------------------------------

lib.callback.register('grand_admin:server:CanOpenMenu', function(source)
    return HasPermission(source)
end)

lib.callback.register('grand_admin:server:GetPlayers', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return {} end
    if not RequireBridge() then return {} end

    return Bridge.GetRoster()
end)

lib.callback.register('grand_admin:server:GetPlayerState', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return nil end

    local state = PlayerStates[source]
    if not state then
        state = { godmode = false, noclip = false, spectating = nil }
        PlayerStates[source] = state
    end

    return state
end)

lib.callback.register('grand_admin:server:KickPlayer', function(source, targetId, reason)
    local ok, err, target = Guard(source, targetId)
    if not ok then return false, err end

    reason = reason and tostring(reason):sub(1, Config.Moderation.ReasonMaxLength) or nil

    local message = Config.Moderation.KickMessage
    if reason and #reason > 0 then
        message = message .. '\nReason: ' .. reason
    end

    DropPlayer(target, message)

    LogAction(source, 'kick', target, reason or '(no reason given)')
    return true, ('Kicked %s'):format(Bridge.GetDisplayName(target))
end)

lib.callback.register('grand_admin:server:BanPlayer', function(source, targetId, duration, reason)
    local ok, err, target = Guard(source, targetId)
    if not ok then return false, err end

    duration = math.max(0, math.floor(tonumber(duration) or Config.Moderation.DefaultBanDuration))
    reason = reason and tostring(reason):sub(1, Config.Moderation.ReasonMaxLength) or 'No reason given'

    local licence, discord = '', ''
    for _, identifier in ipairs(GetPlayerIdentifiers(target) or {}) do
        if identifier:find('license:') == 1 and licence == '' then
            licence = identifier
        elseif identifier:find('discord:') == 1 then
            discord = identifier
        end
    end

    local now = os.time()
    local expires = duration > 0 and (now + duration * 60) or 0
    local ip = (GetPlayerEndpoint(target) or '')

    local written = pcall(function()
        MySQL.insert.await([[
            INSERT INTO grand_admin_bans
                (license, discord, ip, name, citizenid, reason, banned_by, expires, timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ]], {
            licence,
            discord,
            ip,
            Bridge.GetDisplayName(target),
            Bridge.GetCitizenId(target),
            reason,
            Bridge.GetDisplayName(source),
            expires,
            now
        })
    end)

    if not written then
        return false, 'Could not record the ban (database error)'
    end

    if Config.Moderation.BanIdentifiers and licence ~= '' then
        ExecuteCommand('banid ' .. licence)
    end

    local message = Config.Moderation.BanMessage
    if duration > 0 then
        message = ('%s Duration: %d minutes'):format(message, duration)
    else
        message = message .. ' (Permanent)'
    end
    message = ('%s\nReason: %s'):format(message, reason)

    DropPlayer(target, message)

    LogAction(source, 'ban', target, ('%dm %s'):format(duration, reason))
    return true, ('Banned %s'):format(Bridge.GetDisplayName(target))
end)

lib.callback.register('grand_admin:server:BringPlayer', function(source, targetId)
    local ok, err, target = Guard(source, targetId)
    if not ok then return false, err end

    local adminPed = GetPlayerPed(source)
    if not adminPed or adminPed == 0 then return false, 'You are not fully loaded' end

    local coords = GetEntityCoords(adminPed)
    TriggerClientEvent('grand_admin:client:TeleportToCoords', target, coords.x, coords.y, coords.z + 1.0)

    LogAction(source, 'bring', target, '')
    return true, ('Brought %s to you'):format(Bridge.GetDisplayName(target))
end)

lib.callback.register('grand_admin:server:GetVehicleCategories', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return {} end
    return Config.VehicleCategories
end)

lib.callback.register('grand_admin:server:SpawnVehicle', function(source, model)
    local canMenu = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    model = tostring(model or ''):lower():gsub('%s+', ''):gsub('[^a-z0-9_]', '')
    if #model == 0 or #model > 40 then
        return false, 'Invalid vehicle model'
    end

    -- Model validity is a client native, so the client re-validates before spawning.
    for _, blocked in ipairs(Config.VehicleSpawner.BlockedModels) do
        if model == blocked:lower() then
            return false, 'That vehicle is blocked from spawning'
        end
    end

    local plate = GeneratePlate()
    if not plate then
        return false, 'Could not generate a valid plate'
    end

    TriggerClientEvent('grand_admin:client:SpawnVehicle', source, model, plate)
    LogAction(source, 'spawn', nil, ('%s [%s]'):format(model, plate))
    return true, ('Spawning %s [%s]'):format(model:upper(), plate)
end)

--- Collision-avoiding plate generator, checked against the Grand RP garage.
function GeneratePlate()
    if not RequireBridge() then return false end

    local prefix = (Config.VehicleSpawner.PlatePrefix or ''):upper():sub(1, 4)
    local length = math.max(1, math.min(8 - #prefix, tonumber(Config.VehicleSpawner.PlateLength) or 8))
    local chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'

    for _ = 1, 30 do
        local suffix = {}
        for _ = 1, length do
            local index = math.random(1, #chars)
            suffix[#suffix + 1] = chars:sub(index, index)
        end

        local plate = (prefix .. table.concat(suffix)):upper():sub(1, 8)

        if not Config.VehicleSpawner.UniquePlates or not Bridge.IsPlateTaken(plate) then
            return plate
        end
    end

    return false
end

RegisterNetEvent('grand_admin:server:RecordVehicle', function(model, plate)
    local source = tonumber(source)
    local canMenu = HasPermission(source)
    if not canMenu then return end

    local citizenid = Bridge.GetCitizenId(source)
    if Bridge.RecordVehicle(citizenid, tostring(model), tostring(plate)) then
        print(('^2[%s]^7 Stored %s [%s] for %s'):format(RESOURCE, model, plate, citizenid))
    end
end)

-- ---------------------------------------------------------------------------
-- Self actions
-- ---------------------------------------------------------------------------

lib.callback.register('grand_admin:server:ToggleGodMode', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    local state = PlayerStates[source]
    if not state then return false, 'Open the menu first' end

    state.godmode = not state.godmode
    TriggerClientEvent('grand_admin:client:SetGodMode', source, state.godmode)

    local status = state.godmode and 'enabled' or 'disabled'
    LogAction(source, 'godmode', nil, status)
    return true, 'Godmode ' .. status
end)

lib.callback.register('grand_admin:server:ToggleNoClip', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    local state = PlayerStates[source]
    if not state then return false, 'Open the menu first' end

    if state.spectating then
        return false, 'Stop spectating before using noclip'
    end

    state.noclip = not state.noclip
    TriggerClientEvent('grand_admin:client:SetNoClip', source, state.noclip)

    local status = state.noclip and 'enabled' or 'disabled'
    LogAction(source, 'noclip', nil, status)
    return true, 'Noclip ' .. status
end)

lib.callback.register('grand_admin:server:StartSpectating', function(source, targetId)
    local canMenu, canFull = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    if source == 0 then return false, 'Spectating is not available from the console' end

    local target = Bridge.ResolveTarget(targetId)
    if not target then return false, 'Target player is not online' end

    local state = PlayerStates[source]
    if not state then return false, 'Open the menu first' end

    if state.noclip then
        state.noclip = false
        TriggerClientEvent('grand_admin:client:SetNoClip', source, false)
    end

    state.spectating = target
    TriggerClientEvent('grand_admin:client:SpectatePlayer', source, target)

    LogAction(source, 'spectate', target, canFull and 'full staff' or '')
    return true, ('Now spectating %s'):format(Bridge.GetDisplayName(target))
end)

lib.callback.register('grand_admin:server:StopSpectating', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    local state = PlayerStates[source]
    if not state then return false, 'Open the menu first' end

    if not state.spectating then
        return false, 'You are not spectating anyone'
    end

    local previous = state.spectating
    state.spectating = nil
    TriggerClientEvent('grand_admin:client:StopSpectating', source)

    LogAction(source, 'spectate-stop', previous, '')
    return true, 'Stopped spectating'
end)

-- ---------------------------------------------------------------------------
-- Teleport
-- ---------------------------------------------------------------------------

lib.callback.register('grand_admin:server:TeleportToPlayer', function(source, targetId)
    local canMenu = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    local target = Bridge.ResolveTarget(targetId)
    if not target then return false, 'Target player is not online' end

    local ped = GetPlayerPed(target)
    if not ped or ped == 0 then return false, 'That player is still loading' end

    local coords = GetEntityCoords(ped)
    TriggerClientEvent('grand_admin:client:TeleportToCoords', source, coords.x, coords.y, coords.z)

    LogAction(source, 'teleport', target, 'to player')
    return true, ('Teleported to %s'):format(Bridge.GetDisplayName(target))
end)

lib.callback.register('grand_admin:server:TeleportToLocation', function(source, x, y, z)
    local canMenu = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if not x or not y or not z then return false, 'Invalid coordinates' end
    if math.abs(x) > 20000 or math.abs(y) > 20000 or z < -1000 or z > 2000 then
        return false, 'Coordinates are out of bounds'
    end

    TriggerClientEvent('grand_admin:client:TeleportToCoords', source, x, y, z)

    LogAction(source, 'teleport', nil, ('%.2f, %.2f, %.2f'):format(x, y, z))
    return true, 'Teleported'
end)

lib.callback.register('grand_admin:server:TeleportToWaypoint', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return false, 'Insufficient permission' end

    TriggerClientEvent('grand_admin:client:TeleportToWaypoint', source)

    LogAction(source, 'teleport', nil, 'to waypoint')
    return true, 'Teleported to waypoint'
end)

--- Uptime in whole seconds since the resource started. The panel formats it,
--- because GetGameTimer is a client-only native.
local ResourceStartedAt = os.time()

function GetServerUptimeSeconds()
    return math.max(0, os.time() - ResourceStartedAt)
end

function GetServerUptime()
    local seconds = GetServerUptimeSeconds()
    return ('%02d:%02d:%02d'):format(
        math.floor(seconds / 3600),
        math.floor((seconds % 3600) / 60),
        seconds % 60
    )
end

lib.callback.register('grand_admin:server:GetServerInfo', function(source)
    local canMenu = HasPermission(source)
    if not canMenu then return nil end

    return {
        uptime = GetServerUptimeSeconds(),
        uptimeText = GetServerUptime(),
        players = Bridge and #Bridge.GetRoster() or #GetPlayers(),
        maxPlayers = GetConvarInt('sv_maxclients', 32),
        name = GetConvar('sv_hostname', 'Grand RP')
    }
end)

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

AddEventHandler('playerDropped', function()
    local source = tonumber(source)
    PlayerStates[source] = nil

    for admin, state in pairs(PlayerStates) do
        if state.spectating == source then
            state.spectating = nil
            TriggerClientEvent('grand_admin:client:StopSpectating', admin)
            TriggerClientEvent('grand_admin:client:SpectateTargetLeft', admin)
        end
    end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end

    if not MySQL then
        print(('^1[%s]^7 oxmysql is not loaded - the panel will run without persistence^7'):format(RESOURCE))
        return
    end

    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `grand_admin_bans` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `license` VARCHAR(128) NOT NULL DEFAULT '',
                `discord` VARCHAR(128) NOT NULL DEFAULT '',
                `ip` VARCHAR(64) NOT NULL DEFAULT '',
                `name` VARCHAR(128) NOT NULL DEFAULT '',
                `citizenid` VARCHAR(64) NOT NULL DEFAULT '',
                `reason` TEXT,
                `banned_by` VARCHAR(128) NOT NULL DEFAULT '',
                `expires` BIGINT NOT NULL DEFAULT 0,
                `timestamp` BIGINT NOT NULL DEFAULT 0,
                `unbanned` TINYINT(1) DEFAULT 0,
                `unbanned_at` BIGINT DEFAULT 0,
                `unbanned_by` VARCHAR(128) DEFAULT '',
                KEY `idx_license` (`license`),
                KEY `idx_citizenid` (`citizenid`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]])
    end)

    pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS `grand_admin_logs` (
                `id` INT AUTO_INCREMENT PRIMARY KEY,
                `admin` VARCHAR(128) NOT NULL DEFAULT '',
                `admin_citizenid` VARCHAR(64) NOT NULL DEFAULT '',
                `action` VARCHAR(64) NOT NULL DEFAULT '',
                `target` VARCHAR(32) DEFAULT '',
                `details` TEXT,
                `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                KEY `idx_action` (`action`)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]])
    end)

    print(('^2[%s]^7 Ready - admin actions verified against the Grand RP schema^7'):format(RESOURCE))
end)

exports('HasPermission', HasPermission)
exports('GetRoster', function()
    return Bridge and Bridge.GetRoster() or {}
end)
