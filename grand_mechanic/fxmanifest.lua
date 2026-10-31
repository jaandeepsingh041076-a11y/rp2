-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_mechanic/fxmanifest.lua
--  SECTION 06 — MECHANIC / TOW / TAXI WORKFORCE
--  Framework-agnostic: oxmysql + ox_lib + grand_core exports only.
-- ─────────────────────────────────────────────────────────────

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'grand_mechanic'
author 'Grand RP'
description 'Full mechanic, tow and taxi workforce: hoarding, parts, diagnostics, jacking, impounds'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/*.lua',
}

client_scripts {
    'client/core.lua',
    'client/diagnostic.lua',
    'client/hoarding.lua',
    'client/tow.lua',
    'client/jack.lua',
    'client/taxi.lua',
    'client/blips.lua',
    'client/civic.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/jobs.lua',
    'server/tools.lua',
    'server/hoarding.lua',
    'server/tow.lua',
    'server/jack.lua',
    'server/taxi.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'grand_core',
    'grand_inventory',
}
