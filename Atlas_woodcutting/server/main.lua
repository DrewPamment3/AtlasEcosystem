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
    -- Just update subscriptions, don't send full loadForests event
    local closestForests = SubscribePlayerToForests(_source, playerCoords)
    if Config.DebugLogging then
        print("^3[SUBSCRIPTIONS]^7 Updated player " ..
        _source .. " subscriptions - " .. #closestForests .. " forests in range")
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

RegisterServerEvent('atlas_woodcutting:server:requestStart')
AddEventHandler('atlas_woodcutting:server:requestStart', function(coords, forestId, treeIndex, nodeData)
    local _source = source
    print("^2[CHOP FLOW]^7 requestStart [SERVER] - Player " ..
    _source .. " | Forest " .. forestId .. " | Tree " .. treeIndex)

    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = {
        token = token,
        startTime = os.time(),
        forestId = forestId,
        treeIndex = treeIndex,
        nodeData = nodeData
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

    -- Award XP using Atlas_skilling - try export method first, then fallback to server event
    local success, result = pcall(function()
        return exports['Atlas_skilling']:AddSkillXP(_source, 'woodcutting', Config.ChopXPReward)
    end)

    if not success then
        if Config.DebugLogging then
            print("^3[XP AWARD]^7 Export method failed, trying server event method...")
            print("^3[XP AWARD]^7 Export error: " .. tostring(result))
        end
        
        -- Fallback: Try direct function call via resource export
        local success2, result2 = pcall(function()
            -- Try calling the global function directly via another export method
            if Config.DebugLogging then
                print("^3[XP AWARD]^7 Attempting direct function call for player " .. _source)
            end
            
            local skillsResource = exports['Atlas_skilling']
            if skillsResource then
                return skillsResource:AddSkillXP(_source, 'woodcutting', Config.ChopXPReward)
            else
                error("Atlas_skilling resource not available")
            end
        end)
        
        if success2 then
            if Config.DebugLogging then
                print("^2[XP AWARD]^7 Successfully awarded " .. Config.ChopXPReward .. " woodcutting XP via server event to player " .. _source)
            end
        else
            print("^1[Atlas Woodcutting]^7 Both export and server event methods failed for player " .. _source)
            print("^1[Atlas Woodcutting]^7 Export error: " .. tostring(result))
            print("^1[Atlas Woodcutting]^7 Event error: " .. tostring(result2))
            print("^1[Atlas Woodcutting]^7 Make sure Atlas_skilling resource is started and loaded properly")
        end
    else
        if Config.DebugLogging then
            print("^2[XP AWARD]^7 Successfully awarded " .. Config.ChopXPReward .. " woodcutting XP via export to player " .. _source)
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
    local forest = GetForestById(forestId)
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
