-- -------------------------------------------------------------
--  resources/[grand_systems]/grand_dealership/fxmanifest.lua
--  SECTION 07 - VEHICLE DEALERSHIP: forecourt sales, finance,
--  test drives, owned-vehicle garage. Headless: NO NUI.
--  Framework-agnostic: oxmysql + ox_lib + grand_core exports only.
-- -------------------------------------------------------------

fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'grand_dealership'
author 'Grand RP'
description 'Car dealership network: catalogue sales, cash or financed, test drives, weekly instalments and vehicle garage'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/util.lua',
}

client_scripts {
    'client/garage.lua',
    'client/sales.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/sales.lua',
    'server/finance.lua',
    'server/testdrive.lua',
    'server/garage.lua',
    'server/main.lua',
}

dependencies {
    'ox_lib',
    'oxmysql',
    'grand_core',
}
