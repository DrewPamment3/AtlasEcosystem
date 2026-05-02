fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
-- lua54 'yes'

author 'DrewPamment3'
description 'Atlas Woodcutting - RPG Gathering Module'
version '1.0'

shared_scripts {
    'shared/config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    'server/tool_validation.lua',
    'server/main.lua'
}

dependencies {
    'vorp_core',
    'vorp_inventory',
    'oxmysql',
    'Atlas_skilling' -- Essential: Allows use of AddSkillXP and GetSkillLevel
}
