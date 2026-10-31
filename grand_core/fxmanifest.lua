-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_core/fxmanifest.lua
--  Framework-agnostic core / character / economy engine.
--  No qb-core, no qbx, no esx — oxmysql + ox_lib only.
-- ─────────────────────────────────────────────────────────────
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Grand RP - Core'
version '2.0.0'
author 'Grand RP Development Team'
description 'Character persistence, money economy, jobs and spawn/respawn logic'

-- ─── Shared ──────────────────────────────────────────────────
shared_scripts {
    '@ox_lib/init.lua',
    'shared/util.lua',
    'config.lua'
}

-- ─── Client (notify shim is part of main.lua, loaded first) ──
client_scripts {
    'client/main.lua',
    'client/loaded.lua',
    'client/hud_bridge.lua',
    'client/death.lua'
}

-- ─── Server (boot order matters: main defines the helpers) ───
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/player.lua',
    'server/characters.lua',
    'server/jobs.lua',
    'server/economy.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql'
}
