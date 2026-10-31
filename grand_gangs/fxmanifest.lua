-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_gangs/fxmanifest.lua
--  TURFS / TERRITORY / PVP LAYER for Grand RP.
--  Framework-agnostic: oxmysql + grand_core + grand_families
--  exports only. Reuses grand_mechanic's GrandBlips map engine.
--  No NUI, no qb-core, no ESX.
-- ─────────────────────────────────────────────────────────────

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'grand_gangs'
author 'Grand RP'
description 'Turf territories, /attackturf capture wars, red-zone PvP, bounties and family income'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/util.lua',
}

client_scripts {
    'client/zones.lua',
    'client/pvp.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/turfs.lua',
    'server/wars.lua',
    'server/pvp.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'grand_core',
}
