fx_version 'cerulean'
game 'gta5'

author 'Grand RP Development'
description 'Grand Coins Currency System'
version '1.0.0'

lua54 'yes'

shared_scripts {
    'config.lua',
    'shared/util.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/database.lua',
    'server/coins.lua',
    'server/main.lua'
}

client_scripts {
    'client/coins.lua'
}

dependencies {
    'grand_core',
    'grand_mechanic'
}