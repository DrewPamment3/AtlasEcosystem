local VORPcore = exports.vorp_core:GetCore()

-- 1. INITIALIZATION
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

RegisterServerEvent('atlas_skilling:getSkills')
AddEventHandler('atlas_skilling:getSkills', function()
    local _source = source
    local User = VORPcore.getUser(_source)
    if not User then return end

    local Character = User.getUsedCharacter
    if not Character then return end

    local charidentifier = Character.charIdentifier

    exports.oxmysql:execute('SELECT * FROM character_skills WHERE charidentifier = ?', { charidentifier },
        function(result)
            if result and result[1] then
                TriggerClientEvent('atlas_skilling:openMenu', _source, result[1])
            end
        end)
end)

-- 2. THE XP MANAGER LOGIC
local function AddSkillXP_Internal(source, skill, amount, personalMult)
    local User = VORPcore.getUser(source)
    if not User then return end

    local Character = User.getUsedCharacter
    if not Character then return end

    local charidentifier = Character.charIdentifier
    local skillColumn = string.lower(skill) .. "_xp"
    local pMult = personalMult or 1.0
    local finalAmount = math.floor(amount * Config.GlobalXPMultiplier * pMult)

    exports.oxmysql:scalar('SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?',
        { charidentifier }, function(currentXP)
            if currentXP ~= nil then
                local newXP = currentXP + finalAmount
                if newXP > Config.MaxXP then newXP = Config.MaxXP end

                exports.oxmysql:execute('UPDATE character_skills SET ' .. skillColumn .. ' = ? WHERE charidentifier = ?',
                    { newXP, charidentifier })

                TriggerClientEvent('atlas_skilling:xpNotification', source, skill, finalAmount, newXP)

                local oldLevel = math.floor(math.sqrt(currentXP / Config.XPFormulaDivisor)) + 1
                local newLevel = math.floor(math.sqrt(newXP / Config.XPFormulaDivisor)) + 1

                if newLevel > oldLevel then
                    TriggerClientEvent('atlas_skilling:levelUp', source, newLevel)
                    print("^3[Atlas Skilling]^7 Player " .. source .. " leveled up to " .. newLevel)
                end
            end
        end)
end

exports('AddSkillXP', AddSkillXP_Internal)

-- 3. ADMIN COMMAND
RegisterCommand('givexp', function(source, args)
    local _source = source
    local canExecute = false
    local userGroup = "none"

    if _source == 0 then
        canExecute = true
        userGroup = "console"
    else
        local User = VORPcore.getUser(_source)
        if User then
            userGroup = User.group or "user"
            if userGroup == 'admin' or userGroup == 'superadmin' then
                canExecute = true
            end
        else
            userGroup = "invalid_session"
        end
    end

    if canExecute then
        local targetID = tonumber(args[1])
        local skillName = args[2] and tostring(args[2]):lower() or nil
        local amount = tonumber(args[3])

        if targetID and skillName and amount then
            local Target = VORPcore.getUser(targetID)
            if Target and Target.getUsedCharacter then
                AddSkillXP_Internal(targetID, skillName, amount)
                if _source ~= 0 then
                    VORPcore.NotifyRightTip(_source, "Granted " .. amount .. " XP to ID " .. targetID, 4000)
                end
                print('^2[Atlas Admin]^7 Granted ' .. amount .. ' XP in ' .. skillName .. ' to ID: ' .. targetID)
            else
                print('^1[Atlas Admin Error]^7 Target ID ' .. targetID .. ' not found.')
            end
        else
            print('^1[Atlas Admin Error]^7 Usage: /givexp [id] [skill] [amount]')
        end
    else
        local denyMsg = "Access Denied. Your group is [" .. userGroup .. "]. Required: admin."
        if _source ~= 0 then VORPcore.NotifyRightTip(_source, denyMsg, 6000) end
        print("^1[Atlas Admin Auth]^7 " .. denyMsg)
    end
end, false)
