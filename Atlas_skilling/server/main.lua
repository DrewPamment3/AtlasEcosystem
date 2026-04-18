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

-- 2. THE XP MANAGER LOGIC
-- Internal function so the script can call itself without using exports
local function AddSkillXP_Internal(source, skill, amount, personalMult)
    local Character = VORPcore.getUser(source).getUsedCharacter
    if not Character then return end

    local charidentifier = Character.charIdentifier
    local skillColumn = string.lower(skill) .. "_xp"
    local pMult = personalMult or 1.0

    -- Using Config from shared/config.lua
    local finalAmount = math.floor(amount * Config.GlobalXPMultiplier * pMult)

    exports.oxmysql:scalar('SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?',
        { charidentifier }, function(currentXP)
            if currentXP ~= nil then
                local newXP = currentXP + finalAmount

                if newXP > Config.MaxXP then newXP = Config.MaxXP end

                exports.oxmysql:execute('UPDATE character_skills SET ' .. skillColumn .. ' = ? WHERE charidentifier = ?',
                    { newXP, charidentifier })

                TriggerClientEvent('atlas_skilling:xpNotification', source, skill, finalAmount, newXP)
                CheckForLevelUp(source, currentXP, newXP)
            end
        end)
end

-- Register the internal function as an export for OTHER resources
exports('AddSkillXP', AddSkillXP_Internal)

-- 3. LEVEL LOGIC
function GetLevelFromXP(xp)
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

-- 4. ADMIN COMMAND: Grant XP
-- Usage: /givexp [ID] [SKILL] [AMOUNT]
RegisterCommand('givexp', function(source, args)
    local _source = source
    local canExecute = false
    local userGroup = "none"

    -- 1. Console (source 0) or Admin/Superadmin groups
    if _source == 0 then
        canExecute = true
    else
        local User = VORPcore.getUser(_source)
        if User then
            userGroup = User.group or "user" -- Fallback to 'user' string if nil
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
                -- Direct call to the internal function
                AddSkillXP_Internal(targetID, skillName, amount)

                if _source ~= 0 then
                    VORPcore.NotifyRightTip(_source, "Granted " .. amount .. " XP to ID " .. targetID, 4000)
                end
                print('^2[Atlas Admin]^7 Granted ' .. amount .. ' XP in ' .. skillName .. ' to ID: ' .. targetID)
            else
                local errorMsg = "^1[Atlas Admin Error]^7 Target ID " ..
                    targetID .. " not found or character not loaded."
                if _source ~= 0 then VORPcore.NotifyRightTip(_source, "Target not found.", 4000) end
                print(errorMsg)
            end
        else
            local usageMsg = "^1[Atlas Admin Error]^7 Usage: /givexp [id] [skill] [amount]"
            if _source ~= 0 then VORPcore.NotifyRightTip(_source, "Invalid Arguments.", 4000) end
            print(usageMsg)
        end
    else
        -- VERBOSE DEBUGGING
        local denyMsg = "Access Denied. Your group is [" .. userGroup .. "]. Required: [admin] or [superadmin]."
        VORPcore.NotifyRightTip(_source, denyMsg, 6000)
        print("^1[Atlas Admin Auth]^7 " .. denyMsg .. " (Source: " .. _source .. ")")
    end
end, false)
