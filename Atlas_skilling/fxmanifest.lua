fx_version 'adamant' -- Changed to adamant (common stable standard for RDR3)
game 'rdr3'
lua54 'yes'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'
description 'Atlas Skilling System'
author 'DrewPamment3'

-- In modern manifests, we list dependencies like this:
dependency 'vorp_core'
dependency 'oxmysql'

shared_script 'shared/config.lua'

client_script 'client/main.lua'

server_script 'server/main.lua'

-- Use exports instead of server_export for better compatibility
exports {
    'AddSkillXP'
}
