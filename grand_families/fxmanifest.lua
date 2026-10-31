-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/fxmanifest.lua
--  Family vault, ranks, properties, turf ownership.
--  Framework-agnostic: oxmysql + ox_lib only, no NUI.
-- ─────────────────────────────────────────────────────────────
fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Grand RP - Families'
version '2.0.0'
author 'Grand RP Development Team'
description 'Families, vault, ranks, properties, turf ownership and income'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/util.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/bridge.lua',
    'server/income.lua',
    'server/main.lua'
}

dependencies {
    'oxmysql',
    'ox_lib'
}

provides { 'grand_families' }
