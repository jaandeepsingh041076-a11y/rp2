fx_version 'cerulean'
game 'gta5'

author 'Grand RP Development'
description 'Grand Casino - Games of Chance'
version '1.0.0'

lua54 'yes'

shared_scripts {
    'config.lua',
    'shared/util.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/rng.lua',
    'server/games.lua',
    'server/main.lua'
}

client_scripts {
    'client/casino.lua'
}

dependencies {
    'grand_core',
    'grand_mechanic'
}