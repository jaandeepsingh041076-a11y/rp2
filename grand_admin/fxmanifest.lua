fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Grand RP - Admin Panel'
version '1.0.0'
author 'Grand RP Development Team'
description 'HTML/NUI admin panel: noclip, godmode, vehicle spawner, spectate, moderation'

-- ----------------------------------------------------------------------
-- Dependencies (framework-free: oxmysql + ox_lib only)
-- ----------------------------------------------------------------------
dependencies {
    'oxmysql',
    'ox_lib'
}

-- ----------------------------------------------------------------------
-- Client entry point and web UI (Sections 01, 11)
-- ----------------------------------------------------------------------
ui_page 'web/index.html'
files {
    'web/index.html',
    'web/style.css',
    'web/tokens.css',
    'web/app.js'
}

-- ----------------------------------------------------------------------
-- Shared configuration
-- ----------------------------------------------------------------------
shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

-- ----------------------------------------------------------------------
-- Client scripts (notify must load first)
-- ----------------------------------------------------------------------
client_scripts {
    'client/notify.lua',          -- global Notify() shim (Section 01 palette)
    'client/state.lua',           -- admin state (loaded first)
    'client/teleport.lua',        -- teleport handlers
    'client/noclip.lua',          -- smooth noclip
    'client/godmode.lua',         -- invincibility
    'client/vehicle.lua',         -- vehicle spawner
    'client/spectate.lua',        -- spectate camera
    'client/main.lua'             -- NUI entry point (F10)
}

-- ----------------------------------------------------------------------
-- Server scripts
-- ----------------------------------------------------------------------
server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/bridge.lua',
    'server/main.lua'
}
