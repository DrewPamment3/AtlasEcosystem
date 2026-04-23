fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
lua54 'yes'

author 'DrewPamment3'
description 'Atlas Skilling System - Core XP Manager'

shared_scripts {
    'shared/config.lua'
}

client_script 'client/main.lua'
server_script 'server/main.lua'

dependencies {
    'vorp_core',
    'oxmysql'
}

exports {
    'AddSkillXP',
    'GetSkillLevel',
    'GetSkillLevelSync'
}

version '1.0'
