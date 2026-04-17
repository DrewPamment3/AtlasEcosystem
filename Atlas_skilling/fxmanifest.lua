fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

description 'Atlas Skilling System - Core XP Manager'
author 'DrewPamment3'

-- Dependencies: This script won't load if these aren't running
dependencies {
    'vorp_core',
    'oxmysql'
}

-- Shared scripts (accessible by both client and server)
shared_scripts {
    'shared/config.lua'
}

-- Client-side scripts (code that runs on the player's PC)
client_scripts {
    'client/main.lua'
}

-- Server-side scripts (code that runs on the host/database)
server_scripts {
    'server/main.lua'
}

-- Export the function so other resources can call it
server_export 'AddSkillXP'
