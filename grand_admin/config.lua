-- resources/[grand_systems]/grand_admin/config.lua
Config = {}

-- Who can open the menu. Checked server side on every privileged action,
-- never trusted from the client.
Config.Permissions = {
    -- Ace permissions (add_ace / add_principal in server.cfg)
    AceIdentifiers = 'grand_admin.menu',
    AceFull        = 'grand_admin.full',

    -- Staff identifiers always allowed (license:xxxx, discord:xxxx, ip:xxxx)
    Identifiers = {
        -- 'license:abcdef1234567890',
    },

    -- Server groups from server.cfg, e.g. add_principal identifier.fivem:1 group.admin
    Groups = { 'admin', 'superadmin', 'god', 'moderator' },

    -- The single group that unlocks destructive/fully privileged actions
    FullGroup = 'superadmin',

    -- Require BOTH the ace and a group/identifier match
    RequireAce = false,
}

Config.Menu = {
    ToggleKey = 289, -- F10
    NoclipSpeedKey = 17,
}

Config.Noclip = {
    -- Speed is scaled by current client frame time so movement feels identical
    -- regardless of FPS. Units are world units per frame at 60fps.
    BaseSpeed = 0.35,
    SprintMultiplier = 3.0,
    TargetFPS = 60.0,
    MinSpeed = 0.05,
    MaxSpeed = 6.0,

    -- Collision handling
    FreezeWhileIdle = true,
    IdleThreshold = 0.01,

    -- Clear the area of traffic/peds so you do not get stuck inside props
    ClearSurroundingsOnToggle = true,
    ClearRadius = 15.0,
}

Config.VehicleSpawner = {
    -- Plate settings
    PlatePrefix = 'GRAND',
    PlateLength = 8,
    UniquePlates = true,
    DefaultNumberPlateStyle = 0,

    -- Spawn behaviour
    SpawnDistance = 8.0,
    GroundOffset = 0.3,
    SeatPosition = 'driver',

    MaxSpawnDistance = 25.0,

    -- Safety: never spawn these
    BlockedModels = {
        'rhino', 'bomber', 'hydra', 'lazer', 'savage', 'akula', 'oppressor2'
    },

    -- Quick spawn list shown in the menu
    Categories = {
        'Cars',
        'SUVs',
        'Motorcycles',
    }
}

Config.VehicleCategories = {
    ['Cars'] = {
        'adder', 'emerus', 'feveter', 'negasi', 'raiden', 'swift2', 'comet6', 'zentorno',
    },
    ['SUVs'] = {
        'baller7', 'conturia', 'novice', 'granger', 'toros', 'rebla', 'issi4',
    },
    ['Motorcycles'] = {
        'bati2', 'neron', 'akuma', 'carbonrs', 'rprotota', 'maneter',
    }
}

Config.Spectate = {
    MinDistance = 15.0,
    MaxDistance = 35.0,
    UpdateIntervalMs = 200,

    -- Keep the camera from clipping into terrain
    CollisionAware = true,

    -- Teleport the admin to the target if they are too far away
    AutoTravel = true,
    AutoTravelDistance = 350.0,
}

Config.Moderation = {
    -- Minutes; 0 = permanent
    DefaultBanDuration = 0,
    ReasonMaxLength = 512,
    KickMessage = 'You were removed from the server by staff.',
    BanMessage  = 'You have been banned from Grand RP.',

    -- Write every privileged action into grand_admin_logs
    LogToDatabase = true,

    -- Also run the native `banid` command so FiveM itself blocks the licence
    BanIdentifiers = true,

    -- Our own ban table
    BanTable = 'grand_admin_bans',
}

Config.GodMode = {
    InfiniteAmmo = true,
    KeepArmour = true,
    ArmourValue = 200,
    DisableRagdoll = true,
    HealIntervalMs = 1000,
}
