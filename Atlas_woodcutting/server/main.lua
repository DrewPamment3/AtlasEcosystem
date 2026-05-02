local VORPcore = exports.vorp_core:GetCore()
local Config = AtlasWoodConfig -- Reference shared config
local ActiveTasks = {}
local GlobalNodes = {}
local GlobalForests = {}
local ForestClients = {}    -- Track which players see which forests: {forestId = {playerId1, playerId2, ...}}
local ForestTreeStates = {} -- Track dead trees: {forestId = {treeIndex = chopTime, ...}}
local RespawnTimers = {}    -- Track respawn timers: {forestId_treeIndex = timerId}

-- Helper: Refresh GlobalForests from database
local function RefreshGlobalForests(callback)
    if Config.DebugLogging then
        print("^3[FOREST REFRESH]^7 Refreshing GlobalForests from database...")
    end
    
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_forests', {}, function(forests)
        if forests then
            GlobalForests = forests
            if Config.DebugLogging then
                print("^2[FOREST REFRESH]^7 Updated GlobalForests - now contains " .. #forests .. " forests")
                for _, forest in ipairs(forests) do
                    print(string.format("^2[FOREST REFRESH]^7   Forest ID %d: '%s' at (%.1f, %.1f, %.1f)", 
                        forest.id, forest.name, forest.x, forest.y, forest.z))
                end
            end
            
            if callback then callback() end
        else
            if Config.DebugLogging then
                print("^1[FOREST REFRESH]^7 ERROR: Failed to load forests from database")
            end
        end
    end)
end

-- Helper: Refresh GlobalNodes from database  
local function RefreshGlobalNodes(callback)
    if Config.DebugLogging then
        print("^3[NODE REFRESH]^7 Refreshing GlobalNodes from database...")
    end
    
    exports.oxmysql:execute('SELECT x, y, z, model_name, forest_id FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            GlobalNodes = nodes
            if Config.DebugLogging then
                print("^2[NODE REFRESH]^7 Updated GlobalNodes - now contains " .. #nodes .. " nodes")
            end
            
            if callback then callback() end
        else
            if Config.DebugLogging then
                print("^1[NODE REFRESH]^7 ERROR: Failed to load nodes from database")
            end
        end
    end)
end

-- Initial data load on resource start
Citizen.CreateThread(function()
    Citizen.Wait(1000)
    
    -- Validate loot system configuration first
    print("^3[Atlas Woodcutting]^7 Validating loot system configuration...")
    local isValid = AtlasWoodConfig.ValidateLootSystem()
    
    if not isValid then
        print("^1[Atlas Woodcutting]^7 ❌ CRITICAL: Loot system configuration is invalid!")
        print("^1[Atlas Woodcutting]^7 Please fix configuration errors before using woodcutting")
        return
    else
        print("^2[Atlas Woodcutting]^7 ✓ Loot system configuration validated")
    end
    
    -- Load forests first, then nodes
    RefreshGlobalForests(function()
        print("^2[Atlas Woodcutting]^7 Initial load: " .. #GlobalForests .. " forests loaded from database")
        
        Citizen.Wait(500)
        RefreshGlobalNodes(function()
            print("^2[Atlas Woodcutting]^7 Initial load: " .. #GlobalNodes .. " nodes loaded from database")
            
            -- Test Atlas_skilling connection after resource is fully loaded
            Citizen.Wait(2000) -- Give extra time for Atlas_skilling to load
            print("^3[Atlas Woodcutting]^7 Testing Atlas_skilling connection...")
            
            local skillResourceState = GetResourceState('Atlas_skilling')
            print("^3[Atlas Woodcutting]^7 Atlas_skilling resource state: " .. tostring(skillResourceState))
            
            if skillResourceState == 'started' then
                local success, result = pcall(function()
                    return exports['Atlas_skilling']['AddSkillXP']
                end)
                
                if success and result then
                    print("^2[Atlas Woodcutting]^7 ✅ Atlas_skilling export connection successful!")
                else
                    print("^1[Atlas Woodcutting]^7 ❌ Atlas_skilling export not accessible: " .. tostring(result))
                    print("^1[Atlas Woodcutting]^7 Will attempt to use server event fallback method")
                end
            else
                print("^1[Atlas Woodcutting]^7 ❌ Atlas_skilling resource not started - current state: " .. tostring(skillResourceState))
                print("^1[Atlas Woodcutting]^7 Please ensure Atlas_skilling is started before Atlas_woodcutting")
            end
        end)
    end)
end)

-- Helper: Calculate respawn time in seconds based on forest tier
local function GetRespawnSeconds(forestTier)
    local baseMinutes = Config.RespawnMinutesPerTier
    local multiplier = 2 ^ (forestTier - 1) -- Tier 1 = 1x, Tier 2 = 2x, Tier 3 = 4x, Tier 4 = 8x
    return (baseMinutes * multiplier) * 60
end

-- Helper: Get forest info by ID
local function GetForestById(forestId)
    for _, forest in ipairs(GlobalForests) do
        if forest.id == forestId then
            return forest
        end
    end
    return nil
end

-- Helper: Get distance between two 3D points
local function GetDistance(x1, y1, z1, x2, y2, z2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2 + (z2 - z1) ^ 2)
end

-- Helper: Count table entries
local function CountTable(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Helper: Get player's axe tier from inventory
local function GetPlayerAxeTier(source)
    -- Check player's inventory for axes, return the highest tier they have
    local axeTier = 1 -- Default to crude axe
    
    for axeName, axeData in pairs(Config.Axes) do
        local success, hasAxe = pcall(function()
            local item = exports.vorp_inventory:getItem(source, axeName)
            return item and item.count and item.count > 0
        end)
        
        if success and hasAxe then
            axeTier = math.max(axeTier, axeData.tier)
        end
    end
    
    return axeTier
end

-- Helper: Award loot to player
local function AwardLoot(source, woodType, quantity, isBonus)
    local success, result = pcall(function()
        return exports.vorp_inventory:addItem(source, woodType, quantity)
    end)
    
    if success then
        -- Clean display name (remove wood_ prefix and clean up)
        local displayName = woodType:gsub("wood_", ""):gsub("_", " ")
        displayName = displayName:sub(1,1):upper() .. displayName:sub(2) .. " Wood"
        
        -- Simple, clean notification format
        if isBonus then
            VORPcore.NotifyRightTip(source, "+" .. quantity .. " " .. displayName .. " (Bonus)", 3000)
        else
            VORPcore.NotifyRightTip(source, "+" .. quantity .. " " .. displayName, 3000)
        end
        
        if Config.DebugLogging then
            local bonusText = isBonus and " (Bonus)" or ""
            print("^2[LOOT AWARD]^7 Player " .. source .. " received " .. quantity .. "x " .. woodType .. bonusText)
        end
        
        return true
    else
        if Config.DebugLogging then
            print("^1[LOOT AWARD]^7 Failed to award " .. woodType .. " to player " .. source .. ": " .. tostring(result))
        end
        
        -- Check if it's an inventory full error
        if tostring(result):find("full") or tostring(result):find("space") then
            VORPcore.NotifyRightTip(source, "~r~Your inventory is too full to harvest", 4000)
        end
        
        return false
    end
end

-- Main loot calculation and award function
local function ProcessWoodcuttingLoot(source, groveTier, axeTier)
    print("^3[ProcessWoodcuttingLoot DEBUG]^7 === FUNCTION CALLED ===")
    print("^3[ProcessWoodcuttingLoot DEBUG]^7 Source: " .. tostring(source))
    print("^3[ProcessWoodcuttingLoot DEBUG]^7 Grove Tier: " .. tostring(groveTier))
    print("^3[ProcessWoodcuttingLoot DEBUG]^7 Axe Tier: " .. tostring(axeTier or "nil"))
    
    -- Get player's woodcutting level using synchronous version
    local success, playerLevel = pcall(function()
        return exports['Atlas_skilling']:GetSkillLevelSync(source, 'woodcutting')
    end)
    
    if not success then
        print("^1[Atlas Woodcutting]^7 Error getting player level for loot: " .. tostring(playerLevel))
        return false -- Return false to indicate no bonus loot
    end
    
    -- Use provided axe tier or fallback to old method
    axeTier = axeTier or GetPlayerAxeTier(source)
    
    if Config.DebugLogging then
        print("^3[LOOT DEBUG]^7 Player " .. source .. " - Level: " .. playerLevel .. " - Grove Tier: " .. groveTier .. " - Axe Tier: " .. axeTier)
    end
    
    -- Calculate primary loot weights
    local weights, totalWeight = AtlasWoodConfig.CalculateLootWeights(playerLevel, groveTier, axeTier, false)
    
    -- Check if player can access this grove
    if not weights then
        local requiredLevel = totalWeight -- totalWeight contains required level when weights is nil
        VORPcore.NotifyRightTip(source, "~r~Come back when you improve (Level Required: " .. requiredLevel .. ")", 4000)
        return false -- Return false to indicate no bonus loot
    end
    
    if totalWeight <= 0 then
        print("^1[LOOT DEBUG]^7 No valid loot weights calculated for player " .. source)
        return false -- Return false to indicate no bonus loot
    end
    
    -- Roll for primary loot
    local primaryLoot = AtlasWoodConfig.RollForLoot(weights, totalWeight)
    if primaryLoot then
        AwardLoot(source, primaryLoot, 1, false)
    end
    
    -- Calculate bonus loot chance
    local bonusChance = AtlasWoodConfig.CalculateBonusChance(playerLevel, axeTier)
    local bonusRoll = math.random() * 100
    
    if Config.DebugLogging then
        print("^3[LOOT DEBUG]^7 Bonus chance: " .. string.format("%.1f%%", bonusChance) .. " - Roll: " .. string.format("%.1f", bonusRoll))
    end
    
    -- Roll for bonus loot
    local hasBonusLoot = false
    if bonusRoll <= bonusChance then
        local bonusWeights, bonusTotalWeight = AtlasWoodConfig.CalculateLootWeights(playerLevel, groveTier, axeTier, true)
        
        if bonusWeights and bonusTotalWeight > 0 then
            local bonusLoot = AtlasWoodConfig.RollForLoot(bonusWeights, bonusTotalWeight)
            if bonusLoot then
                AwardLoot(source, bonusLoot, 1, true)
                hasBonusLoot = true
            end
        end
    end
    
    -- Return whether bonus loot was awarded (for XP calculation)
    return hasBonusLoot
end

-- Helper: Subscribe player to nearby forests
local function SubscribePlayerToForests(playerId, playerCoords)
    if Config.DebugLogging then
        print(string.format("^3[SUBSCRIBE DEBUG]^7 SubscribePlayerToForests called - Player %d at (%.1f, %.1f, %.1f)",
            playerId, playerCoords.x, playerCoords.y, playerCoords.z))
        print("^3[SUBSCRIBE DEBUG]^7 GlobalForests has " .. #GlobalForests .. " forests")
    end

    local closestForests = {}

    for _, forest in ipairs(GlobalForests) do
        local distance = GetDistance(playerCoords.x, playerCoords.y, playerCoords.z, forest.x, forest.y, forest.z)
        if Config.DebugLogging then
            print(string.format("^3[SUBSCRIBE DEBUG]^7 Forest %d at (%.1f, %.1f, %.1f) - distance: %.1f meters", forest.id,
                forest.x, forest.y, forest.z, distance))
        end
        
        if distance <= Config.RenderDistance then
            if Config.DebugLogging then
                print("^2[SUBSCRIBE DEBUG]^7 Forest " .. forest.id .. " IS IN RANGE")
            end
            table.insert(closestForests, {
                id = forest.id,
                x = forest.x,
                y = forest.y,
                z = forest.z,
                distance = distance,
                tier = forest.tier
            })
        else
            if Config.DebugLogging then
                print("^3[SUBSCRIBE DEBUG]^7 Forest " .. forest.id .. " is out of range")
            end
        end
    end

    if Config.DebugLogging then
        print("^3[SUBSCRIBE DEBUG]^7 Player will be subscribed to " .. #closestForests .. " forests")
    end

    -- Update ForestClients tracking - REMOVE from dead forests
    if Config.DebugLogging then
        print("^3[SUBSCRIBE DEBUG]^7 Checking existing subscriptions...")
    end
    
    for forestId, _ in pairs(ForestClients) do
        local stillInRange = false
        for _, forest in ipairs(closestForests) do
            if forest.id == forestId then
                stillInRange = true
                break
            end
        end

        if not stillInRange and ForestClients[forestId] then
            if Config.DebugLogging then
                print("^1[SUBSCRIBE DEBUG]^7 Removing player " ..
                playerId .. " from forest " .. forestId .. " (out of range)")
            end
            ForestClients[forestId][playerId] = nil
        end
    end

    -- ADD to new forests
    if Config.DebugLogging then
        print("^3[SUBSCRIBE DEBUG]^7 Adding to new forests...")
    end
    
    for _, forest in ipairs(closestForests) do
        if not ForestClients[forest.id] then
            if Config.DebugLogging then
                print("^2[SUBSCRIBE DEBUG]^7 Creating ForestClients[" .. forest.id .. "]")
            end
            ForestClients[forest.id] = {}
        end
        if Config.DebugLogging then
            print("^2[SUBSCRIBE DEBUG]^7 Adding player " .. playerId .. " to forest " .. forest.id)
        end
        ForestClients[forest.id][playerId] = true
    end

    if Config.DebugLogging then
        print("^2[SUBSCRIBE DEBUG]^7 Final ForestClients state:")
        for fId, clients in pairs(ForestClients) do
            print("  Forest " .. fId .. ": " .. CountTable(clients) .. " clients")
        end
    end

    return closestForests
end

-- Notify all players within range when a new forest is created
local function NotifyPlayersOfNewForest(forestId, forestCoords, radius, tier, name)
    if Config.DebugLogging then
        print("^2[NEW FOREST NOTIFY]^7 Checking all players for proximity to new forest " .. forestId)
    end
    
    -- Get all connected players
    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local playerSource = tonumber(playerId)
        if playerSource then
            local user = VORPcore.getUser(playerSource)
            if user and user.getUsedCharacter then
                local ped = GetPlayerPed(playerSource)
                if ped ~= 0 then
                    local playerCoords = GetEntityCoords(ped)
                    local distance = GetDistance(playerCoords.x, playerCoords.y, playerCoords.z, 
                                               forestCoords.x, forestCoords.y, forestCoords.z)
                    
                    if distance <= Config.RenderDistance then
                        if Config.DebugLogging then
                            print("^2[NEW FOREST NOTIFY]^7 Player " .. playerSource .. " is within range (" .. 
                                  math.floor(distance) .. "m) - triggering subscription update")
                        end
                        
                        -- Trigger immediate subscription update for this player
                        -- Force an immediate subscription check for new forests
                        local closestForests = SubscribePlayerToForests(playerSource, playerCoords)
                        TriggerClientEvent('atlas_woodcutting:client:loadForests', playerSource, closestForests, GlobalNodes, ForestTreeStates)
                        
                        -- Also notify them about the new forest
                        VORPcore.NotifyRightTip(playerSource, "~b~New forest discovered: " .. name, 3000)
                    end
                end
            end
        end
    end
end

RegisterServerEvent('atlas_woodcutting:server:playerLoaded')
AddEventHandler('atlas_woodcutting:server:playerLoaded', function()
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then return end

    local character = user.getUsedCharacter
    if not character then return end

    -- Get player position from player ped (standard RedM approach)
    local ped = GetPlayerPed(_source)
    if ped == 0 then return end

    local playerCoords = GetEntityCoords(ped)
    local closestForests = SubscribePlayerToForests(_source, playerCoords)

    -- Send initial forest state to client (full load with all trees)
    TriggerClientEvent('atlas_woodcutting:client:loadForests', _source, closestForests, GlobalNodes, ForestTreeStates)
end)

-- Periodic subscription update (WITHOUT reloading all trees)
RegisterServerEvent('atlas_woodcutting:server:updateSubscriptions')
AddEventHandler('atlas_woodcutting:server:updateSubscriptions', function()
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then return end

    local character = user.getUsedCharacter
    if not character then return end

    -- Get player position from player ped
    local ped = GetPlayerPed(_source)
    if ped == 0 then return end

    local playerCoords = GetEntityCoords(ped)
    
    -- Track current subscriptions BEFORE update
    local currentSubscriptions = {}
    for forestId, clients in pairs(ForestClients) do
        if clients[_source] then
            currentSubscriptions[forestId] = true
        end
    end
    
    -- Update subscriptions and get new forest list
    local closestForests = SubscribePlayerToForests(_source, playerCoords)
    
    -- Check if any NEW forests were added to subscription
    local newForests = {}
    for _, forest in ipairs(closestForests) do
        if not currentSubscriptions[forest.id] then
            table.insert(newForests, forest)
            if Config.DebugLogging then
                print("^2[SUBSCRIPTIONS]^7 Player " .. _source .. " discovered NEW forest: " .. forest.id)
            end
        end
    end
    
    -- If new forests discovered, send them the full forest data
    if #newForests > 0 then
        TriggerClientEvent('atlas_woodcutting:client:loadForests', _source, closestForests, GlobalNodes, ForestTreeStates)
        if Config.DebugLogging then
            print("^2[SUBSCRIPTIONS]^7 Sent loadForests to player " .. _source .. " for " .. #newForests .. " new forests")
        end
    end
    
    if Config.DebugLogging then
        print("^3[SUBSCRIPTIONS]^7 Updated player " .. _source .. " subscriptions - " .. #closestForests .. " forests in range")
    end
end)

RegisterServerEvent('atlas_woodcutting:server:saveNode')
AddEventHandler('atlas_woodcutting:server:saveNode', function(forestId, coords, modelName)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_name) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelName }, function(id)
            if id then
                local node = { x = coords.x, y = coords.y, z = coords.z, model_name = modelName, forest_id = forestId }
                table.insert(GlobalNodes, node)

                -- Broadcast to all clients (they'll spawn if they're tracking this forest)
                TriggerClientEvent('atlas_woodcutting:client:spawnSingleNode', -1, node, forestId)
            else
                print("^1[Atlas Woodcutting]^7 Failed to save node for forest " .. forestId)
            end
        end)
end)

-- Advanced debug command to check player group from multiple sources
RegisterCommand('checkgroup', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        print("^1[Debug]^7 User object is nil!")
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local groupStatus = user.group or "user"
    local charGroup = character and character.group or "unknown"
    local userIdentifier = user.identifier or "unknown"

    -- Query database directly to verify
    exports.oxmysql:execute('SELECT `group` FROM characters WHERE charidentifier = ?',
        { character and character.charIdentifier or "unknown" },
        function(result)
            local dbCharGroup = (result and result[1] and result[1].group) or "NOT FOUND"

            -- Also check users table
            exports.oxmysql:execute('SELECT `group` FROM users WHERE identifier = ?',
                { userIdentifier },
                function(userResult)
                    local dbUserGroup = (userResult and userResult[1] and userResult[1].group) or "NOT FOUND"

                    print("^2================================================^7")
                    print(string.format("^3Advanced Group Check for ID %d^7", _source))
                    print("^2================================================^7")
                    print("^3FROM VORPCORE OBJECT:^7")
                    print(string.format("  ^7user.group: ^6%s^7", groupStatus))
                    print(string.format("  ^7character.group: ^6%s^7", charGroup))
                    print("^3FROM DATABASE (DIRECT QUERY):^7")
                    print(string.format("  ^7characters table: ^6%s^7", dbCharGroup))
                    print(string.format("  ^7users table: ^6%s^7", dbUserGroup))
                    print("^3IDENTIFIERS:^7")
                    print(string.format("  ^7User: ^6%s^7", userIdentifier))
                    print(string.format("  ^7Character ID: ^6%s^7", character and character.charIdentifier or "unknown"))
                    print("^2================================================^7")

                    if dbCharGroup ~= groupStatus then
                        print("^1⚠️  MISMATCH!^7 Database shows '" ..
                            dbCharGroup .. "' but VORP shows '" .. groupStatus .. "'")
                    end
                    if dbUserGroup ~= groupStatus then
                        print("^1⚠️  MISMATCH!^7 Users table shows '" ..
                            dbUserGroup .. "' but VORP shows '" .. groupStatus .. "'")
                    end
                    print("^2================================================^7")
                end)
        end)

    VORPcore.NotifyRightTip(_source, "^3Checking group from database...", 4000)
end)

RegisterCommand('createforest', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /createforest is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end
    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius, count, tier = tonumber(args[1]) or 15.0, tonumber(args[2]) or 10, tonumber(args[3]) or 1
    local model, name = args[4] or "p_tree_pine01x", args[5] or "Unnamed_Grove"

    -- Validate parameters against config ranges
    if radius < Config.RadiusRange.min or radius > Config.RadiusRange.max then
        VORPcore.NotifyRightTip(_source, "~r~Radius must be " .. Config.RadiusRange.min .. "-" .. Config.RadiusRange.max,
            4000)
        return
    end
    if count < Config.TreeCountRange.min or count > Config.TreeCountRange.max then
        VORPcore.NotifyRightTip(_source,
            "~r~Count must be " .. Config.TreeCountRange.min .. "-" .. Config.TreeCountRange.max, 4000)
        return
    end
    if tier < Config.TierRange.min or tier > Config.TierRange.max then
        VORPcore.NotifyRightTip(_source, "~r~Tier must be " .. Config.TierRange.min .. "-" .. Config.TierRange.max, 4000)
        return
    end
    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier, model_name, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier, model, name }, function(fId)
            if fId then
                -- Success: Update GlobalForests immediately
                RefreshGlobalForests(function()
                    if Config.DebugLogging then
                        print("^2[CREATE FOREST]^7 GlobalForests refreshed after creating forest ID " .. fId)
                    end
                    
                    -- Notify all existing players about the new forest
                    NotifyPlayersOfNewForest(fId, pCoords, radius, tier, name)
                end)
                
                VORPcore.NotifyRightTip(_source, "~g~Forest '" .. name .. "' created with " .. count .. " trees", 4000)
                TriggerClientEvent('atlas_woodcutting:client:generateForestNodes', _source, fId, pCoords, radius, count,
                    model)
                print("^2[Atlas Woodcutting Admin]^7 Forest '" .. name .. "' (ID: " .. fId .. ") created by player " .. _source)
            else
                VORPcore.NotifyRightTip(_source, "~r~Failed to create forest in database", 4000)
                print("^1[Atlas Woodcutting]^7 Failed to insert forest for admin " .. _source)
            end
        end)
end)

RegisterCommand('wipeforest', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /wipeforest is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    local targetId = args[1] and tostring(args[1]):lower() or nil
    if not targetId then
        VORPcore.NotifyRightTip(_source, "~r~Usage: /wipeforest [id|all]", 4000)
        return
    end

    if targetId == 'all' then
        -- Wipe all forests
        exports.oxmysql:execute('DELETE FROM atlas_woodcutting_nodes')
        exports.oxmysql:execute('DELETE FROM atlas_woodcutting_forests', {}, function()
            -- Update both GlobalForests and GlobalNodes after successful deletion
            GlobalForests = {}
            GlobalNodes = {}
            ForestClients = {}  -- Clear all subscriptions
            ForestTreeStates = {} -- Clear all tree states
            
            if Config.DebugLogging then
                print("^2[WIPE ALL]^7 Cleared all GlobalForests, GlobalNodes, ForestClients, and ForestTreeStates")
            end
            
            TriggerClientEvent('atlas_woodcutting:client:wipeAllForests', -1)
            VORPcore.NotifyRightTip(_source, "~g~All forests wiped successfully", 4000)
            print("^2[Atlas Woodcutting Admin]^7 All forests wiped by player " .. _source)
        end)
    else
        -- Wipe specific forest by ID
        local fId = tonumber(targetId)
        if not fId then
            VORPcore.NotifyRightTip(_source, "~r~Forest ID must be a number", 4000)
            return
        end

        exports.oxmysql:execute('SELECT id FROM atlas_woodcutting_forests WHERE id = ?', { fId }, function(result)
            if result and result[1] then
                exports.oxmysql:execute('DELETE FROM atlas_woodcutting_nodes WHERE forest_id = ?', { fId })
                exports.oxmysql:execute('DELETE FROM atlas_woodcutting_forests WHERE id = ?', { fId }, function()
                    -- Update GlobalForests and GlobalNodes after successful deletion
                    RefreshGlobalForests(function()
                        RefreshGlobalNodes(function()
                            -- Clean up related data structures
                            ForestClients[fId] = nil
                            ForestTreeStates[fId] = nil
                            
                            -- Clear any respawn timers for this forest
                            for timerKey, timerId in pairs(RespawnTimers) do
                                if timerKey:match("^" .. fId .. "_") then
                                    RemoveTimeout(timerId)
                                    RespawnTimers[timerKey] = nil
                                end
                            end
                            
                            if Config.DebugLogging then
                                print("^2[WIPE FOREST]^7 Cleaned up all data for forest ID " .. fId)
                            end
                            
                            TriggerClientEvent('atlas_woodcutting:client:wipeSpecificForest', -1, fId)
                            VORPcore.NotifyRightTip(_source, "~g~Forest ID " .. fId .. " wiped successfully", 4000)
                            print("^2[Atlas Woodcutting Admin]^7 Forest ID " .. fId .. " wiped by player " .. _source)
                        end)
                    end)
                end)
            else
                VORPcore.NotifyRightTip(_source, "~r~Forest ID " .. fId .. " not found", 4000)
            end
        end)
    end
end)

-- Debug command to test Atlas_skilling connection
RegisterCommand('testatlasconnection', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting Debug]^7 Testing Atlas_skilling connection from console...")
        
        -- Test if resource exists
        local skillResource = GetResourceState('Atlas_skilling')
        print("^3[Atlas Woodcutting Debug]^7 Atlas_skilling resource state: " .. tostring(skillResource))
        
        -- Test export availability
        local success1, result1 = pcall(function()
            return exports['Atlas_skilling']
        end)
        print("^3[Atlas Woodcutting Debug]^7 Atlas_skilling exports accessible: " .. tostring(success1))
        if not success1 then
            print("^1[Atlas Woodcutting Debug]^7 Export access error: " .. tostring(result1))
        end
        
        -- Test specific export
        local success2, result2 = pcall(function()
            return exports['Atlas_skilling']['AddSkillXP']
        end)
        print("^3[Atlas Woodcutting Debug]^7 AddSkillXP export exists: " .. tostring(success2))
        if not success2 then
            print("^1[Atlas Woodcutting Debug]^7 AddSkillXP error: " .. tostring(result2))
        else
            print("^2[Atlas Woodcutting Debug]^7 AddSkillXP function type: " .. tostring(type(result2)))
        end
        
        return
    end
    
    print("^3[Atlas Woodcutting Debug]^7 Use this command from server console for full debug info")
    VORPcore.NotifyRightTip(_source, "~y~Check server console for connection test results", 4000)
end)

-- Debug command to manually refresh forest data
RegisterCommand('refreshforests', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /refreshforests is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    RefreshGlobalForests(function()
        RefreshGlobalNodes(function()
            VORPcore.NotifyRightTip(_source, "~g~Forest data refreshed successfully", 4000)
            print("^2[Atlas Woodcutting Admin]^7 Forest data manually refreshed by player " .. _source)
            print("^2[Atlas Woodcutting Admin]^7 Now tracking " .. #GlobalForests .. " forests and " .. #GlobalNodes .. " nodes")
        end)
    end)
end)

-- Debug command to test loot calculations
RegisterCommand('testloot', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    local playerLevel = tonumber(args[1]) or 1
    local groveTier = tonumber(args[2]) or 1
    local axeTier = tonumber(args[3]) or 1

    print("^2[LOOT TEST]^7 Testing loot calculation:")
    print("^3  Player Level:^7 " .. playerLevel)
    print("^3  Grove Tier:^7 " .. groveTier)  
    print("^3  Axe Tier:^7 " .. axeTier)

    -- Calculate weights
    local weights, totalWeight = AtlasWoodConfig.CalculateLootWeights(playerLevel, groveTier, axeTier, false)
    
    if not weights then
        local requiredLevel = totalWeight
        print("^1[LOOT TEST]^7 Player cannot access tier " .. groveTier .. " grove (requires level " .. requiredLevel .. ")")
        return
    end

    -- Display probabilities
    print("^2[LOOT TEST]^7 Primary Loot Probabilities:")
    for woodType, weight in pairs(weights) do
        local percentage = (weight / totalWeight) * 100
        print("^3  " .. woodType .. ":^7 " .. string.format("%.2f%% (weight: %.2f)", percentage, weight))
    end

    -- Calculate bonus chance
    local bonusChance = AtlasWoodConfig.CalculateBonusChance(playerLevel, axeTier)
    print("^2[LOOT TEST]^7 Bonus Loot Chance: " .. string.format("%.1f%%", bonusChance))

    -- Calculate XP rewards
    local baseXP = AtlasWoodConfig.CalculateXPReward(groveTier, axeTier, false)
    local bonusXP = AtlasWoodConfig.CalculateXPReward(groveTier, axeTier, true)
    print("^2[XP TEST]^7 XP Rewards:")
    print("^3  Base XP (no bonus loot):^7 " .. baseXP)
    print("^3  Bonus XP (with bonus loot):^7 " .. bonusXP .. " (+" .. (bonusXP - baseXP) .. " bonus)")

    -- Test multiple rolls
    print("^2[LOOT TEST]^7 Sample rolls (10x):")
    for i = 1, 10 do
        local result = AtlasWoodConfig.RollForLoot(weights, totalWeight)
        local bonusRoll = math.random() * 100
        local bonusResult = ""
        local xpAmount = baseXP
        
        if bonusRoll <= bonusChance then
            local bonusWeights, bonusTotalWeight = AtlasWoodConfig.CalculateLootWeights(playerLevel, groveTier, axeTier, true)
            if bonusWeights and bonusTotalWeight > 0 then
                local bonusLoot = AtlasWoodConfig.RollForLoot(bonusWeights, bonusTotalWeight)
                bonusResult = " + " .. (bonusLoot or "NONE") .. " (bonus)"
                xpAmount = bonusXP
            end
        end
        
        print("^3  Roll " .. i .. ":^7 " .. (result or "NONE") .. bonusResult .. " | XP: " .. xpAmount)
    end

    VORPcore.NotifyRightTip(_source, "~g~Loot & XP test complete - check console", 3000)
end)

-- Debug command to simulate giving loot for testing
RegisterCommand('simulateloot', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    local groveTier = tonumber(args[1]) or 1
    
    print("^2[LOOT SIMULATE]^7 Simulating complete woodcutting experience for player " .. _source .. " in tier " .. groveTier .. " grove")
    
    -- Process loot and get bonus status
    local hasBonusLoot = ProcessWoodcuttingLoot(_source, groveTier, 1) -- Default to tier 1 for this call
    
    -- Get player's axe tier and calculate XP
    local axeTier = GetPlayerAxeTier(_source)
    local xpReward = AtlasWoodConfig.CalculateXPReward(groveTier, axeTier, hasBonusLoot)
    
    -- Simulate XP award (but don't actually give it to avoid exploits)
    local bonusText = hasBonusLoot and " (DOUBLE XP for bonus loot!)" or ""
    print("^2[LOOT SIMULATE]^7 Would award " .. xpReward .. " XP" .. bonusText)
    
    VORPcore.NotifyRightTip(_source, "~g~Simulation complete: " .. xpReward .. " XP" .. (hasBonusLoot and " (BONUS!)" or ""), 4000)
end)

-- Debug command to check player's axe tier
RegisterCommand('checkaxe', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local axeTier = GetPlayerAxeTier(_source)
    print("^2[AXE CHECK]^7 Player " .. _source .. " has axe tier: " .. axeTier)
    
    -- Show which axes they have
    print("^2[AXE CHECK]^7 Player's axes:")
    for axeName, axeData in pairs(Config.Axes) do
        local success, hasAxe = pcall(function()
            local item = exports.vorp_inventory:getItem(_source, axeName)
            return item and item.count and item.count > 0
        end)
        
        if success and hasAxe then
            print("^3  " .. axeName .. ":^7 Tier " .. axeData.tier .. " ✓")
        else
            print("^1  " .. axeName .. ":^7 Tier " .. axeData.tier .. " ✗")
        end
    end
    
    VORPcore.NotifyRightTip(_source, "~g~Axe tier: " .. axeTier .. " - Check console for details", 3000)
end)

-- Command to validate loot system configuration
RegisterCommand('validateloot', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /validateloot is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    print("^2[LOOT VALIDATION]^7 Validating loot system configuration...")
    
    local isValid = AtlasWoodConfig.ValidateLootSystem()
    
    if isValid then
        print("^2[LOOT VALIDATION]^7 ✓ Loot system configuration is valid")
        VORPcore.NotifyRightTip(_source, "~g~Loot system configuration is valid", 3000)
    else
        print("^1[LOOT VALIDATION]^7 ✗ Loot system configuration has errors")
        VORPcore.NotifyRightTip(_source, "~r~Loot system has configuration errors - check console", 4000)
    end
end)

-- Command to test XP scaling across all tiers
RegisterCommand('testxp', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    print("^2[XP TEST]^7 XP Scaling by Grove Tier and Axe Tier:")
    print("^2================================================================^7")
    
    -- Test XP scaling across all combinations
    for groveTier = 1, 5 do
        print("^3Grove Tier " .. groveTier .. ":^7")
        for axeTier = 1, 5 do
            local baseXP = AtlasWoodConfig.CalculateXPReward(groveTier, axeTier, false)
            local bonusXP = AtlasWoodConfig.CalculateXPReward(groveTier, axeTier, true)
            local axeName = ""
            
            -- Get axe name for display
            for name, data in pairs(Config.Axes) do
                if data.tier == axeTier then
                    axeName = name:gsub("_", " "):gsub("(%a)([%a%d]*)", function(a, b) return a:upper()..b end)
                    break
                end
            end
            
            print(string.format("^7  %s (Tier %d): ^2%d XP^7 base | ^6%d XP^7 with bonus (+%d)", 
                axeName, axeTier, baseXP, bonusXP, (bonusXP - baseXP)))
        end
        print("")
    end
    
    print("^2================================================================^7")
    print("^3Summary:^7")
    print("^7• Grove tiers double base XP each level (150 → 300 → 600 → 1200 → 2400)")
    print("^7• Axe tiers provide scaling multipliers (1.0x → 1.1x → 1.2x → 1.3x → 1.5x)")
    print("^7• Bonus loot awards double XP (2.0x multiplier)")
    print("^2================================================================^7")
    
    VORPcore.NotifyRightTip(_source, "~g~XP scaling test complete - check console", 3000)
end)

-- Admin command to test player animations remotely
RegisterCommand('testplayeranimation', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    local targetId = tonumber(args[1]) or _source
    local duration = tonumber(args[2]) or 5000
    
    -- Validate target player
    local targetUser = VORPcore.getUser(targetId)
    if not targetUser then
        VORPcore.NotifyRightTip(_source, "~r~Player " .. targetId .. " not found", 4000)
        return
    end
    
    if duration < 1000 or duration > 30000 then
        VORPcore.NotifyRightTip(_source, "~r~Duration must be between 1000ms and 30000ms", 4000)
        return
    end
    
    -- Trigger animation test on target client
    TriggerClientEvent('atlas_woodcutting:client:adminAnimTest', targetId, duration)
    
    VORPcore.NotifyRightTip(_source, "~g~Animation test sent to player " .. targetId .. " for " .. duration .. "ms", 4000)
    print("^2[ADMIN ANIMATION TEST]^7 Admin " .. _source .. " triggered animation test on player " .. targetId .. " for " .. duration .. "ms")
end)

-- Admin command to update animation configuration in real-time
RegisterCommand('updateanimconfig', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    local configKey = args[1]
    local newValue = tonumber(args[2])
    
    if not configKey or not newValue then
        VORPcore.NotifyRightTip(_source, "~r~Usage: /updateanimconfig [key] [value]", 4000)
        print("^3[ADMIN CONFIG]^7 Available keys:")
        print("^7• ChopAnimationTime (1000-30000)")
        print("^7• maxMovementDistance (1.0-10.0)")
        print("^7• checkInterval (50-500)")
        return
    end
    
    -- Update local config
    if configKey == 'ChopAnimationTime' then
        if newValue >= 1000 and newValue <= 30000 then
            AtlasWoodConfig.ChopAnimationTime = newValue
        else
            VORPcore.NotifyRightTip(_source, "~r~ChopAnimationTime must be between 1000-30000", 4000)
            return
        end
    elseif configKey == 'maxMovementDistance' then
        if newValue >= 1.0 and newValue <= 10.0 then
            AtlasWoodConfig.Animations.interruption.maxMovementDistance = newValue
        else
            VORPcore.NotifyRightTip(_source, "~r~maxMovementDistance must be between 1.0-10.0", 4000)
            return
        end
    elseif configKey == 'checkInterval' then
        if newValue >= 50 and newValue <= 500 then
            AtlasWoodConfig.Animations.interruption.checkInterval = newValue
        else
            VORPcore.NotifyRightTip(_source, "~r~checkInterval must be between 50-500", 4000)
            return
        end
    else
        VORPcore.NotifyRightTip(_source, "~r~Invalid config key", 4000)
        return
    end
    
    -- Broadcast update to all clients
    TriggerClientEvent('atlas_woodcutting:client:updateConfig', -1, configKey, newValue)
    
    VORPcore.NotifyRightTip(_source, "~g~Updated " .. configKey .. " = " .. newValue, 4000)
    print("^2[ADMIN CONFIG]^7 Admin " .. _source .. " updated " .. configKey .. " to " .. newValue)
end)

-- Admin command to get current animation system status
RegisterCommand('animationstatus', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    print("^2[ANIMATION STATUS]^7 Current Animation System Configuration:")
    print("^2=======================================================^7")
    print("^3Animation Settings:^7")
    print("^7• ChopAnimationTime: " .. AtlasWoodConfig.ChopAnimationTime .. "ms")
    print("^7• Available Scenarios: " .. #AtlasWoodConfig.Animations.scenarios)
    for i, scenario in ipairs(AtlasWoodConfig.Animations.scenarios) do
        print("^7  " .. i .. ". " .. scenario)
    end
    
    print("^3Interruption Settings:^7")
    print("^7• Max Movement Distance: " .. AtlasWoodConfig.Animations.interruption.maxMovementDistance .. "m")
    print("^7• Check Interval: " .. AtlasWoodConfig.Animations.interruption.checkInterval .. "ms")
    print("^7• Health Check: " .. tostring(AtlasWoodConfig.Animations.interruption.healthCheckEnabled))
    print("^7• Combat Check: " .. tostring(AtlasWoodConfig.Animations.interruption.combatCheckEnabled))
    
    print("^3Effects Settings:^7")
    print("^7• Sounds Enabled: " .. tostring(AtlasWoodConfig.Animations.sounds.enabled))
    print("^7• Particles Enabled: " .. tostring(AtlasWoodConfig.Animations.effects.particlesEnabled))
    print("^7• Sound Volume: " .. AtlasWoodConfig.Animations.sounds.volume)
    print("^7• Particle Scale: " .. AtlasWoodConfig.Animations.effects.particleScale)
    
    print("^2=======================================================^7")
    
    VORPcore.NotifyRightTip(_source, "~g~Animation status logged to console", 3000)
end)

RegisterCommand('listforests', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /listforests is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        print("^1[Debug]^7 User object is nil!")
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        if _source ~= 0 then
            VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        end
        return
    end

    local page = tonumber(args[1]) or 1
    if page < 1 then page = 1 end

    exports.oxmysql:execute(
        'SELECT id, name, radius, tree_count, tier, x, y, z FROM atlas_woodcutting_forests ORDER BY name ASC', {},
        function(result)
            if not result or #result == 0 then
                print("^3[Atlas Woodcutting]^7 No forests found in database.")
                return
            end

            local itemsPerPage = 10
            local totalForests = #result
            local totalPages = math.ceil(totalForests / itemsPerPage)

            if page > totalPages then page = totalPages end

            local startIdx = (page - 1) * itemsPerPage + 1
            local endIdx = math.min(page * itemsPerPage, totalForests)

            -- Print header
            print("^2================================================^7")
            print(string.format("^2 ATLAS WOODCUTTING FORESTS - PAGE %d/%d^7", page, totalPages))
            print("^2================================================^7")
            print(string.format("^3%-4s^7 | ^3%-18s^7 | ^3%-7s^7 | ^3%-5s^7 | ^3%-4s^7 | ^3%-8s^7 | ^3%-8s^7 | ^3%-8s^7",
                "ID", "Name", "Radius", "Trees", "Tier", "X", "Y", "Z"))
            print("^2----|--------------------|---------|---------|---------|-----------|-----------|-----------^7")

            -- Print forest entries
            for i = startIdx, endIdx do
                local forest = result[i]
                print(string.format(
                    "^7%-4d^7 | ^6%-18s^7 | ^5%-7.1f^7 | ^4%-5d^7 | ^3%-4d^7 | ^2%-8.2f^7 | ^2%-8.2f^7 | ^2%-8.2f^7",
                    forest.id,
                    forest.name:sub(1, 18),
                    forest.radius,
                    forest.tree_count,
                    forest.tier,
                    forest.x,
                    forest.y,
                    forest.z
                ))
            end

            print("^2================================================^7")
            print(string.format("^3Total: %d forests | Showing %d-%d^7", totalForests, startIdx, endIdx))
            print("^2================================================^7")
        end)
end)

-- Handle validation requests from client
RegisterServerEvent('atlas_woodcutting:server:requestValidation')
AddEventHandler('atlas_woodcutting:server:requestValidation', function(forestId)
    local _source = source
    
    -- Get forest info for validation
    local forest = GetForestById(forestId)
    if not forest then
        -- Send error response
        TriggerClientEvent('atlas_woodcutting:client:validationResult', _source, forestId, "CHOP TREE (Error)", true)
        return
    end
    
    -- Validate tools and level for this forest tier
    local validation = ValidateWoodcuttingTools(_source, forest.tier)
    local promptText, isDisabled = GetWoodcuttingPromptText(validation)
    
    -- Send validation result to client
    TriggerClientEvent('atlas_woodcutting:client:validationResult', _source, forestId, promptText, isDisabled)
    
    if Config.DebugLogging then
        print("^3[VALIDATION]^7 Player " .. _source .. " - Forest " .. forestId .. " (Tier " .. forest.tier .. ") - " .. promptText .. " (disabled: " .. tostring(isDisabled) .. ")")
    end
end)

RegisterServerEvent('atlas_woodcutting:server:requestStart')
AddEventHandler('atlas_woodcutting:server:requestStart', function(coords, forestId, treeIndex, nodeData)
    local _source = source
    print("^2[CHOP FLOW]^7 requestStart [SERVER] - Player " ..
    _source .. " | Forest " .. forestId .. " | Tree " .. treeIndex)

    -- Get forest info for validation
    local forest = GetForestById(forestId)
    if not forest then
        print("^1[CHOP FLOW]^7 ERROR: Forest " .. forestId .. " not found")
        return
    end
    
    local groveTier = forest.tier
    
    -- NEW: Comprehensive tool and level validation
    local validation = ValidateWoodcuttingTools(_source, groveTier)
    
    if not validation.hasValidTool or not validation.levelValid then
        print("^3[CHOP FLOW]^7 Player " .. _source .. " validation failed: " .. (validation.errorMessage or "Unknown error"))
        VORPcore.NotifyRightTip(_source, "~r~" .. (validation.errorMessage or "Cannot chop this tree"), 4000)
        return
    end
    
    print("^2[CHOP FLOW]^7 Validation passed - Player has " .. validation.bestTool.name .. " (tier " .. validation.bestTool.tier .. ", durability " .. validation.bestTool.durability .. ")")
    if validation.willBreak then
        print("^3[CHOP FLOW]^7 WARNING: Tool will break after this action!")
    end

    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = {
        token = token,
        startTime = os.time(),
        forestId = forestId,
        treeIndex = treeIndex,
        nodeData = nodeData,
        toolData = validation.bestTool -- Store tool info for durability handling
    }
    print("^2[CHOP FLOW]^7 Token created: " .. token)
    print("^2[CHOP FLOW]^7 Sending beginMinigame to client " .. _source)
    TriggerClientEvent('atlas_woodcutting:client:beginMinigame', _source, token)
end)

RegisterServerEvent('atlas_woodcutting:server:finishChop')
AddEventHandler('atlas_woodcutting:server:finishChop', function(token)
    local _source = source
    print("^2[CHOP FLOW]^7 finishChop [SERVER] - Player " .. _source .. " | Token: " .. token)

    local task = ActiveTasks[_source]
    if not task or task.token ~= token then
        if not task then
            print("^1[CHOP FLOW]^7 ERROR: No active task for player " .. _source)
        else
            print("^1[CHOP FLOW]^7 ERROR: Token mismatch!")
        end
        return
    end

    local forestId = task.forestId
    local treeIndex = task.treeIndex
    local nodeData = task.nodeData
    print("^2[CHOP FLOW]^7 Marking tree dead - Forest " .. forestId .. " | Tree " .. treeIndex)

    -- Get forest info for loot and XP calculation
    local forest = GetForestById(forestId)
    local groveTier = forest and forest.tier or 1

    -- NEW: Handle tool durability first
    local toolData = task.toolData
    if toolData then
        local durabilitySuccess = HandleAxeDurability(_source, toolData)
        if not durabilitySuccess then
            print("^1[CHOP FLOW]^7 ERROR: Failed to handle tool durability")
        end
    end
    
    -- Process loot rewards and get bonus loot status for XP calculation
    local axeTier = toolData and toolData.tier or 1
    local hasBonusLoot = ProcessWoodcuttingLoot(_source, groveTier, axeTier)
    
    -- Calculate XP reward based on grove tier, axe tier, and bonus loot
    local xpReward = AtlasWoodConfig.CalculateXPReward(groveTier, axeTier, hasBonusLoot)

    -- Award XP using Atlas_skilling export
    local success, result = pcall(function()
        return exports['Atlas_skilling']:AddSkillXP(_source, 'woodcutting', xpReward)
    end)

    if not success then
        print("^1[Atlas Woodcutting]^7 Error awarding XP to player " .. _source .. ": " .. tostring(result))
        print("^1[Atlas Woodcutting]^7 Make sure Atlas_skilling resource is started and loaded properly")
    else
        if Config.DebugLogging then
            local bonusText = hasBonusLoot and " (BONUS XP for double loot!)" or ""
            print("^2[CHOP FLOW]^7 Successfully awarded " .. xpReward .. " woodcutting XP to player " .. _source .. bonusText)
        end
    end

    -- Mark tree as dead
    if not ForestTreeStates[forestId] then
        ForestTreeStates[forestId] = {}
    end

    local chopTime = os.time()
    ForestTreeStates[forestId][treeIndex] = chopTime
    print("^2[CHOP FLOW]^7 ForestTreeStates updated, checking subscriptions...")

    -- Notify all clients tracking this forest about the dead tree
    print("^2[CHOP FLOW]^7 Looking for ForestClients[" .. forestId .. "]")
    if ForestClients[forestId] then
        local clientCount = CountTable(ForestClients[forestId])
        print("^2[CHOP FLOW]^7 Found " .. clientCount .. " subscribed clients for forest " .. forestId)
        for clientId, _ in pairs(ForestClients[forestId]) do
            print("^2[CHOP FLOW]^7 Sending treeChopDeath to client " .. clientId)
            TriggerClientEvent('atlas_woodcutting:client:treeChopDeath', clientId, forestId, treeIndex, nodeData)
        end
    else
        print("^1[CHOP FLOW]^7 ERROR: NO SUBSCRIBED CLIENTS for forest " .. forestId)
    end

    -- Schedule respawn timer
    if forest then
        local respawnSeconds = GetRespawnSeconds(forest.tier)
        local timerKey = forestId .. "_" .. treeIndex

        RespawnTimers[timerKey] = SetTimeout(respawnSeconds * 1000, function()
            -- Tree respawns
            ForestTreeStates[forestId][treeIndex] = nil

            -- Notify all clients tracking this forest about the respawn
            if ForestClients[forestId] then
                for clientId, _ in pairs(ForestClients[forestId]) do
                    TriggerClientEvent('atlas_woodcutting:client:treeRespawn', clientId, forestId, treeIndex, nodeData)
                end
            end

            RespawnTimers[timerKey] = nil
            print("^2[Atlas Woodcutting]^7 Tree " .. treeIndex .. " respawned in forest " .. forestId)
        end)
    end

    ActiveTasks[_source] = nil
end)

-- Player Disconnect Cleanup
AddEventHandler('playerDropped', function(reason)
    local _source = source
    if ActiveTasks[_source] then
        ActiveTasks[_source] = nil
        print("^2[Atlas Woodcutting]^7 Cleaned up active task for disconnected player " .. _source)
    end

    -- Remove from ForestClients tracking
    for forestId, clients in pairs(ForestClients) do
        if clients[_source] then
            clients[_source] = nil
            print("^2[Atlas Woodcutting]^7 Unsubscribed player " .. _source .. " from forest " .. forestId)
        end
    end
end)
