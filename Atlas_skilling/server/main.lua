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
function GetSkillLevel(source, skill, callback)
    local User = VORPcore.getUser(source)
    if not User then 
        if callback then callback(1) end
        return 1 
    end

    local Character = User.getUsedCharacter
    if not Character then 
        if callback then callback(1) end
        return 1 
    end

    local charidentifier = Character.charIdentifier
    local skillColumn = string.lower(skill) .. "_xp"

    -- Use regular scalar with callback - scalar_await doesn't exist
    exports.oxmysql:scalar('SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?', 
        { charidentifier }, function(currentXP)
            local level = 1
            if currentXP then
                level = math.floor(math.sqrt(currentXP / Config.XPFormulaDivisor)) + 1
            end
            
            if callback then
                callback(level)
            end
        end)
    
    -- Return default level immediately for backward compatibility
    return 1
end

-- Synchronous version - using a blocking wait approach since scalar_sync doesn't exist
function GetSkillLevelSync(source, skill)
    print("^3[GetSkillLevelSync DEBUG]^7 === FUNCTION CALLED ===")
    print("^3[GetSkillLevelSync DEBUG]^7 Source: " .. tostring(source))
    print("^3[GetSkillLevelSync DEBUG]^7 Skill: " .. tostring(skill))
    
    local User = VORPcore.getUser(source)
    if not User then 
        print("^1[GetSkillLevelSync]^7 No user found for source " .. source)
        return 1 
    end
    
    print("^3[GetSkillLevelSync DEBUG]^7 User found: " .. tostring(User))

    local Character = User.getUsedCharacter
    if not Character then 
        print("^1[GetSkillLevelSync]^7 No character found for source " .. source)
        return 1 
    end
    
    print("^3[GetSkillLevelSync DEBUG]^7 Character found")

    -- Debug character info
    print("^3[GetSkillLevelSync DEBUG]^7 Character object keys:")
    for k, v in pairs(Character) do
        print("^3[GetSkillLevelSync DEBUG]^7   " .. k .. " = " .. tostring(v))
    end
    
    local charidentifier = Character.charIdentifier
    local skillColumn = string.lower(skill) .. "_xp"
    
    print("^3[GetSkillLevelSync DEBUG]^7 Checking " .. skillColumn .. " for charID " .. tostring(charidentifier))
    print("^3[GetSkillLevelSync DEBUG]^7 === STARTING DATABASE QUERY ===")
    
    -- Use a promise-based approach since scalar_sync doesn't exist
    local currentXP = nil
    local completed = false
    
    exports.oxmysql:scalar('SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?', 
        { charidentifier }, function(result)
            currentXP = result
            completed = true
            print("^3[GetSkillLevelSync DEBUG]^7 Async callback received XP: " .. tostring(result))
        end)
    
    -- Wait for the callback (with timeout)
    local timeout = 0
    while not completed and timeout < 100 do -- 1 second timeout
        Citizen.Wait(10)
        timeout = timeout + 1
    end
    
    if not completed then
        print("^1[GetSkillLevelSync]^7 Database query timed out after 1 second")
        return 1
    end
    
    print("^3[GetSkillLevelSync DEBUG]^7 Final retrieved XP: " .. tostring(currentXP))
    
    if currentXP and currentXP > 0 then
        local level = math.floor(math.sqrt(currentXP / Config.XPFormulaDivisor)) + 1
        print("^2[GetSkillLevelSync DEBUG]^7 Calculated level: " .. level .. " (from " .. currentXP .. " XP)")
        return level
    end

    print("^1[GetSkillLevelSync]^7 No XP found or XP is 0, returning level 1")
    return 1
end

-- Properly register the exports for other resources to use
exports('AddSkillXP', AddSkillXP)
exports('GetSkillLevel', GetSkillLevel)
exports('GetSkillLevelSync', GetSkillLevelSync)

-- Debug: Print export registration
print("^2[Atlas Skilling]^7 Exports registered successfully:")
print("^2[Atlas Skilling]^7 - AddSkillXP")
print("^2[Atlas Skilling]^7 - GetSkillLevel (async with callback)")
print("^2[Atlas Skilling]^7 - GetSkillLevelSync (synchronous)")
