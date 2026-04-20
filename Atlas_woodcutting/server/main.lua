local VORPcore = exports.vorp_core:GetCore()
local Config = AtlasWoodConfig -- Reference shared config
local ActiveTasks = {}
local GlobalNodes = {}
local GlobalForests = {}
local ForestClients = {}    -- Track which players see which forests: {forestId = {playerId1, playerId2, ...}}
local ForestTreeStates = {} -- Track dead trees: {forestId = {treeIndex = chopTime, ...}}
local RespawnTimers = {}    -- Track respawn timers: {forestId_treeIndex = timerId}

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_forests', {}, function(forests)
        if forests then
            GlobalForests = forests
            print("^2[Atlas]^7 Server loaded " .. #forests .. " forests from DB.")
        end
    end)

    Citizen.Wait(500)
    exports.oxmysql:execute('SELECT x, y, z, model_name, forest_id FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            GlobalNodes = nodes
            print("^2[Atlas]^7 Server loaded " .. #nodes .. " nodes from DB.")
        end
    end)
end)

-- Helper: Calculate respawn time in seconds based on forest tier
local function GetRespawnSeconds(forestTier)
    local baseMinutes = Config.RespawnMinutesPerTier
    local multiplier = math.pow(2, forestTier - 1) -- Tier 1 = 1x, Tier 2 = 2x, Tier 3 = 4x, Tier 4 = 8x
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

-- Helper: Subscribe player to nearby forests
local function SubscribePlayerToForests(playerId, playerCoords)
    local closestForests = {}

    for _, forest in ipairs(GlobalForests) do
        local distance = GetDistance(playerCoords.x, playerCoords.y, playerCoords.z, forest.x, forest.y, forest.z)
        if distance <= Config.RenderDistance then
            table.insert(closestForests, {
                id = forest.id,
                x = forest.x,
                y = forest.y,
                z = forest.z,
                distance = distance,
                tier = forest.tier
            })
        end
    end

    -- Update ForestClients tracking
    for forestId, _ in pairs(ForestClients) do
        local stillInRange = false
        for _, forest in ipairs(closestForests) do
            if forest.id == forestId then
                stillInRange = true
                break
            end
        end

        if not stillInRange and ForestClients[forestId] then
            ForestClients[forestId][playerId] = nil
        end
    end

    for _, forest in ipairs(closestForests) do
        if not ForestClients[forest.id] then
            ForestClients[forest.id] = {}
        end
        ForestClients[forest.id][playerId] = true
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

    -- Send initial forest state to client
    TriggerClientEvent('atlas_woodcutting:client:loadForests', _source, closestForests, GlobalNodes, ForestTreeStates)
end)

RegisterServerEvent('atlas_woodcutting:server:saveNode')
AddEventHandler('atlas_woodcutting:server:saveNode', function(forestId, coords, modelName)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_name) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelName }, function(id)
            if id then
                local node = { x = coords.x, y = coords.y, z = coords.z, model_name = modelName, forest_id = forestId }
                table.insert(GlobalNodes, node)

                -- Broadcast to all clients tracking this forest
                if ForestClients[forestId] then
                    for clientId, _ in pairs(ForestClients[forestId]) do
                        TriggerClientEvent('atlas_woodcutting:client:spawnSingleNode', clientId, node, forestId)
                    end
                end
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
                VORPcore.NotifyRightTip(_source, "~g~Forest '" .. name .. "' created with " .. count .. " trees", 4000)
                TriggerClientEvent('atlas_woodcutting:client:generateForestNodes', _source, fId, pCoords, radius, count,
                    model)
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
        exports.oxmysql:execute('DELETE FROM atlas_woodcutting_forests')
        GlobalNodes = {}
        TriggerClientEvent('atlas_woodcutting:client:wipeAllForests', -1)
        VORPcore.NotifyRightTip(_source, "~g~All forests wiped successfully", 4000)
        print("^2[Atlas Woodcutting Admin]^7 All forests wiped by " .. _source)
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
                exports.oxmysql:execute('DELETE FROM atlas_woodcutting_forests WHERE id = ?', { fId })
                for i = #GlobalNodes, 1, -1 do
                    if GlobalNodes[i].forest_id == fId then table.remove(GlobalNodes, i) end
                end
                TriggerClientEvent('atlas_woodcutting:client:wipeSpecificForest', -1, fId)
                VORPcore.NotifyRightTip(_source, "~g~Forest ID " .. fId .. " wiped successfully", 4000)
                print("^2[Atlas Woodcutting Admin]^7 Forest ID " .. fId .. " wiped by " .. _source)
            else
                VORPcore.NotifyRightTip(_source, "~r~Forest ID " .. fId .. " not found", 4000)
            end
        end)
    end
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
    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = {
        token = token,
        startTime = os.time(),
        forestId = forestId,
        treeIndex = treeIndex,
        nodeData = nodeData
    }
    TriggerClientEvent('atlas_woodcutting:client:beginMinigame', _source, token)
end)

RegisterServerEvent('atlas_woodcutting:server:finishChop')
AddEventHandler('atlas_woodcutting:server:finishChop', function(token)
    local _source = source
    local task = ActiveTasks[_source]
    if not task or task.token ~= token then return end

    local forestId = task.forestId
    local treeIndex = task.treeIndex
    local nodeData = task.nodeData

    local success, result = pcall(function()
        return exports.Atlas_skilling:AddSkillXP(_source, 'woodcutting', Config.ChopXPReward)
    end)

    if not success then
        print("^1[Atlas Woodcutting]^7 Error awarding XP to player " .. _source .. ": " .. tostring(result))
    end

    -- Mark tree as dead
    if not ForestTreeStates[forestId] then
        ForestTreeStates[forestId] = {}
    end

    local chopTime = os.time()
    ForestTreeStates[forestId][treeIndex] = chopTime

    -- Notify all clients tracking this forest about the dead tree
    if ForestClients[forestId] then
        for clientId, _ in pairs(ForestClients[forestId]) do
            TriggerClientEvent('atlas_woodcutting:client:treeChopDeath', clientId, forestId, treeIndex, nodeData)
        end
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
