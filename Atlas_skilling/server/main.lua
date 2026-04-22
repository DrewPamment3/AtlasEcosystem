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

-- 2. THE XP MANAGER (Global function for manifest export)
function AddSkillXP(source, skill, amount, personalMult)
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
            local character = User.getUsedCharacter
            userGroup = character and character.group or "user"
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
                -- Calling the global function directly
                AddSkillXP(targetID, skillName, amount)
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
        local denyMsg = "Access Denied. Group: [" .. userGroup .. "]. Required: admin."
        if _source ~= 0 then VORPcore.NotifyRightTip(_source, denyMsg, 6000) end
        print("^1[Atlas Admin Auth]^7 " .. denyMsg)
    end
end, false)

-- Returns the player's level for a specific skill
-- Calculation: floor(sqrt(currentXP / Divisor)) + 1
function GetSkillLevel(source, skill)
    local User = VORPcore.getUser(source)
    if not User then return 1 end

    local Character = User.getUsedCharacter
    if not Character then return 1 end

    local charidentifier = Character.charIdentifier
    local skillColumn = string.lower(skill) .. "_xp"

    -- Using await for a synchronous return to the calling script
    local currentXP = exports.oxmysql:scalar_await(
        'SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?', { charidentifier })

    if currentXP then
        return math.floor(math.sqrt(currentXP / Config.XPFormulaDivisor)) + 1
    end

    return 1
end

-- Explicitly register exports (FiveM/RedM sometimes needs this)
exports('AddSkillXP', AddSkillXP)
exports('GetSkillLevel', GetSkillLevel)

-- Alternative server event method for XP awarding (backup method)
RegisterServerEvent('atlas_skilling:awardXP')
AddEventHandler('atlas_skilling:awardXP', function(skill, amount, personalMult)
    local _source = source
    AddSkillXP(_source, skill, amount, personalMult)
end)

-- Server event method for getting skill level
RegisterServerEvent('atlas_skilling:getLevel')
AddEventHandler('atlas_skilling:getLevel', function(skill, callback)
    local _source = source
    local level = GetSkillLevel(_source, skill)
    if callback then
        TriggerEvent(callback, level)
    end
end)

-- Debug command to test exports are working
RegisterCommand('testskillexports', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Skilling Debug]^7 Testing exports from console...")
        print("^2[Atlas Skilling Debug]^7 AddSkillXP function exists: " .. tostring(AddSkillXP ~= nil))
        print("^2[Atlas Skilling Debug]^7 GetSkillLevel function exists: " .. tostring(GetSkillLevel ~= nil))
        return
    end

    local User = VORPcore.getUser(_source)
    if not User then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local Character = User.getUsedCharacter
    if not Character then
        VORPcore.NotifyRightTip(_source, "~r~No character selected", 4000)
        return
    end

    -- Test the functions directly
    print("^3[Atlas Skilling Debug]^7 Testing exports for player " .. _source)
    print("^2[Atlas Skilling Debug]^7 AddSkillXP function exists: " .. tostring(AddSkillXP ~= nil))
    print("^2[Atlas Skilling Debug]^7 GetSkillLevel function exists: " .. tostring(GetSkillLevel ~= nil))
    
    -- Test GetSkillLevel
    local currentLevel = GetSkillLevel(_source, 'woodcutting')
    print("^2[Atlas Skilling Debug]^7 Current woodcutting level: " .. tostring(currentLevel))
    
    -- Test AddSkillXP with small amount
    AddSkillXP(_source, 'woodcutting', 1)
    print("^2[Atlas Skilling Debug]^7 Added 1 XP to woodcutting")
    
    VORPcore.NotifyRightTip(_source, "~g~Export test completed - check console", 4000)
end)
