local VORPcore = exports.vorp_core:GetCore()

-- 1. INITIALIZATION: Create the row when a character is selected
RegisterNetEvent('vorp:SelectedCharacter')
AddEventHandler('vorp:SelectedCharacter', function(source, character)
    local charidentifier = character.charIdentifier

    exports.oxmysql:execute('SELECT 1 FROM character_skills WHERE charidentifier = ?', { charidentifier },
        function(result)
            if not result or #result == 0 then
                exports.oxmysql:insert('INSERT INTO character_skills (charidentifier) VALUES (?)', { charidentifier })
                print('^2[Atlas Skilling]^7 Created new skill profile for CharID: ' .. charidentifier)
            end
        end)
end)

-- Callback for grabbing skill information from client
RegisterServerEvent('atlas_skilling:getSkills')
AddEventHandler('atlas_skilling:getSkills', function()
    local _source = source
    local Character = VORPcore.getUser(_source).getUsedCharacter
    local charidentifier = Character.charIdentifier

    exports.oxmysql:execute('SELECT * FROM character_skills WHERE charidentifier = ?', { charidentifier },
        function(result)
            if result and result[1] then
                local skillData = result[1]
                TriggerClientEvent('atlas_skilling:openMenu', _source, skillData)
            end
        end)
end)

-- 2. THE XP MANAGER
exports('AddSkillXP', function(source, skill, amount, personalMult)
    local Character = VORPcore.getUser(source).getUsedCharacter
    if not Character then return end

    local charidentifier = Character.charIdentifier
    local skillColumn = string.lower(skill) .. "_xp"
    local pMult = personalMult or 1.0

    -- REFERENCING CONFIG: Using Config.GlobalXPMultiplier from shared/config.lua
    local finalAmount = math.floor(amount * Config.GlobalXPMultiplier * pMult)

    exports.oxmysql:scalar('SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?',
        { charidentifier }, function(currentXP)
            if currentXP ~= nil then
                local newXP = currentXP + finalAmount

                -- REFERENCING CONFIG: Using Config.MaxXP
                if newXP > Config.MaxXP then newXP = Config.MaxXP end

                exports.oxmysql:execute('UPDATE character_skills SET ' .. skillColumn .. ' = ? WHERE charidentifier = ?',
                    { newXP, charidentifier })

                TriggerClientEvent('atlas_skilling:xpNotification', source, skill, finalAmount, newXP)
                CheckForLevelUp(source, currentXP, newXP)
            end
        end)
end)

-- 3. LEVEL LOGIC (Synced with Config)
function GetLevelFromXP(xp)
    -- REFERENCING CONFIG: Using Config.XPFormulaDivisor
    return math.floor(math.sqrt(xp / Config.XPFormulaDivisor)) + 1
end

function CheckForLevelUp(source, oldXP, newXP)
    local oldLevel = GetLevelFromXP(oldXP)
    local newLevel = GetLevelFromXP(newXP)

    if newLevel > oldLevel then
        TriggerClientEvent('atlas_skilling:levelUp', source, newLevel)
        print("^3[Atlas Skilling]^7 Player " .. source .. " has leveled up to " .. newLevel)
    end
end
