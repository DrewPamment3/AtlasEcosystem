print("^5======================================^7")
print("^5  ATLAS MINING SERVER BOOTING^7")
print("^5======================================^7")

local VORPcore = exports.vorp_core:GetCore()
print("^2[ATLAS MINING]^7 VORP core loaded")

local Config = AtlasMiningConfig -- Reference shared config
print("^2[ATLAS MINING]^7 Config loaded. Rocks configured: " .. #Config.Rocks)

local ActiveTasks = {}
local GlobalCamps = {}
local GlobalNodes = {}
local CampClients = {}    -- Track which players see which camps: {campId = {playerId1, playerId2, ...}}
local CampRockStates = {} -- Track depleted rocks: {campId = {rockIndex = mineTime, ...}}
local RespawnTimers = {}  -- Track respawn timers: {campId_rockIndex = timerId}

-- =============================================
-- DATABASE INITIALIZATION
-- =============================================
Citizen.CreateThread(function()
    Citizen.Wait(500)

    -- Create camps table
    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS atlas_mining_camps (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL DEFAULT 'Unnamed_Camp',
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            radius DOUBLE NOT NULL DEFAULT 20.0,
            rock_count INT NOT NULL DEFAULT 10,
            tier INT NOT NULL DEFAULT 1,
            model_name VARCHAR(100) NOT NULL DEFAULT 'p_rock_basalt_01'
        )
    ]])

    -- Create nodes table
    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS atlas_mining_nodes (
            id INT AUTO_INCREMENT PRIMARY KEY,
            camp_id INT NOT NULL,
            x DOUBLE NOT NULL,
            y DOUBLE NOT NULL,
            z DOUBLE NOT NULL,
            model_name VARCHAR(100) NOT NULL DEFAULT 'p_rock_basalt_01',
            FOREIGN KEY (camp_id) REFERENCES atlas_mining_camps(id) ON DELETE CASCADE
        )
    ]])

    print("^2[Atlas Mining]^7 Database tables ensured")
end)

-- Helper: Refresh GlobalCamps from database
local function RefreshGlobalCamps(callback)
    if Config.DebugLogging then
        print("^3[CAMP REFRESH]^7 Refreshing GlobalCamps from database...")
    end

    exports.oxmysql:execute('SELECT * FROM atlas_mining_camps', {}, function(camps)
        if camps then
            GlobalCamps = camps
            if Config.DebugLogging then
                print("^2[CAMP REFRESH]^7 Updated GlobalCamps - now contains " .. #camps .. " camps")
                for _, camp in ipairs(camps) do
                    print(string.format("^2[CAMP REFRESH]^7   Camp ID %d: '%s' at (%.1f, %.1f, %.1f)",
                        camp.id, camp.name, camp.x, camp.y, camp.z))
                end
            end

            if callback then callback() end
        else
            if Config.DebugLogging then
                print("^1[CAMP REFRESH]^7 ERROR: Failed to load camps from database")
            end
        end
    end)
end

-- Helper: Refresh GlobalNodes from database
local function RefreshGlobalNodes(callback)
    if Config.DebugLogging then
        print("^3[NODE REFRESH]^7 Refreshing GlobalNodes from database...")
    end

    exports.oxmysql:execute('SELECT x, y, z, model_name, camp_id FROM atlas_mining_nodes', {}, function(nodes)
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
    Citizen.Wait(1500)

    -- Validate loot system configuration first
    print("^3[Atlas Mining]^7 Validating loot system configuration...")
    local isValid = AtlasMiningConfig.ValidateLootSystem()

    if not isValid then
        print("^1[Atlas Mining]^7 ❌ CRITICAL: Loot system configuration is invalid!")
        print("^1[Atlas Mining]^7 Please fix configuration errors before using mining")
        return
    else
        print("^2[Atlas Mining]^7 ✓ Loot system configuration validated")
    end

    -- Load camps first, then nodes
    RefreshGlobalCamps(function()
        print("^2[Atlas Mining]^7 Initial load: " .. #GlobalCamps .. " camps loaded from database")

        Citizen.Wait(500)
        RefreshGlobalNodes(function()
            print("^2[Atlas Mining]^7 Initial load: " .. #GlobalNodes .. " nodes loaded from database")

            -- Test Atlas_skilling connection after resource is fully loaded
            Citizen.Wait(2000)
            print("^3[Atlas Mining]^7 Testing Atlas_skilling connection...")

            local skillResourceState = GetResourceState('Atlas_skilling')
            print("^3[Atlas Mining]^7 Atlas_skilling resource state: " .. tostring(skillResourceState))

            if skillResourceState == 'started' then
                local success, result = pcall(function()
                    return exports['Atlas_skilling']['AddSkillXP']
                end)

                if success and result then
                    print("^2[Atlas Mining]^7 ✅ Atlas_skilling export connection successful!")
                else
                    print("^1[Atlas Mining]^7 ❌ Atlas_skilling export not accessible: " .. tostring(result))
                    print("^1[Atlas Mining]^7 Will attempt to use server event fallback method")
                end
            else
                print("^1[Atlas Mining]^7 ❌ Atlas_skilling resource not started - current state: " .. tostring(skillResourceState))
                print("^1[Atlas Mining]^7 Please ensure Atlas_skilling is started before Atlas_mining")
            end
        end)
    end)
end)

-- Helper: Calculate respawn time in seconds based on camp tier
local function GetRespawnSeconds(campTier)
    local baseMinutes = Config.RespawnMinutesPerTier
    local multiplier = 2 ^ (campTier - 1) -- Tier 1 = 1x, Tier 2 = 2x, Tier 3 = 4x, Tier 4 = 8x
    return (baseMinutes * multiplier) * 60
end

-- Helper: Get camp info by ID
local function GetCampById(campId)
    for _, camp in ipairs(GlobalCamps) do
        if camp.id == campId then
            return camp
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

-- Helper: Get player's pickaxe tier from inventory
local function GetPlayerPickaxeTier(source)
    -- Check player's inventory for pickaxes, return the highest tier they have
    local pickaxeTier = 1 -- Default to crude pickaxe

    for pickName, pickData in pairs(Config.Pickaxes) do
        local success, hasPick = pcall(function()
            local item = exports.vorp_inventory:getItem(source, pickName)
            return item and item.count and item.count > 0
        end)

        if success and hasPick then
            pickaxeTier = math.max(pickaxeTier, pickData.tier)
        end
    end

    return pickaxeTier
end

-- Helper: Award loot to player
local function AwardLoot(source, oreType, quantity, isBonus)
    local user = VORPcore.getUser(source)
    if not user then
        print("^1[LOOT AWARD]^7 No user found for player " .. source)
        return false
    end

    local character = user.getUsedCharacter
    if not character then
        print("^1[LOOT AWARD]^7 No character found for player " .. source)
        return false
    end

    if Config.DebugLogging then
        print("^3[LOOT DEBUG]^7 Attempting to award " .. quantity .. "x " .. oreType .. " to player " .. source)
    end

    local success, result = pcall(function()
        -- Use VORP core inventory system
        character.addItem(oreType, quantity)
        return true
    end)

    if success and result then
        -- Get display name for notification
        local displayName = oreType:gsub("iron_ore_", ""):gsub("_", " ")
        displayName = displayName:sub(1,1):upper() .. displayName:sub(2) .. " Iron Ore"

        local bonusText = isBonus and " (Bonus)" or ""
        local quantityText = quantity > 1 and (" x" .. quantity) or ""

        VORPcore.NotifyRightTip(source, "~g~Received: " .. displayName .. quantityText .. bonusText, 3000)

        if Config.DebugLogging then
            print("^2[LOOT AWARD]^7 SUCCESS: Player " .. source .. " received " .. quantity .. "x " .. oreType .. bonusText)
        end

        return true
    else
        if Config.DebugLogging then
            print("^1[LOOT AWARD]^7 FAILED to award " .. oreType .. " to player " .. source .. ": " .. tostring(result))
        end

        VORPcore.NotifyRightTip(source, "~r~Failed to receive items - check your inventory", 4000)
        return false
    end
end

-- Main loot calculation and award function
local function ProcessMiningLoot(source, campTier)
    -- Get player's mining level
    local success, playerLevel = pcall(function()
        return exports['Atlas_skilling']:GetSkillLevel(source, 'mining')
    end)

    if not success then
        print("^1[Atlas Mining]^7 Error getting player level for loot: " .. tostring(playerLevel))
        return false -- Return false to indicate no bonus loot
    end

    -- Get player's pickaxe tier
    local pickaxeTier = GetPlayerPickaxeTier(source)

    if Config.DebugLogging then
        print("^3[LOOT DEBUG]^7 Player " .. source .. " - Level: " .. playerLevel .. " - Camp Tier: " .. campTier .. " - Pickaxe Tier: " .. pickaxeTier)
    end

    -- Calculate primary loot weights
    local weights, totalWeight = AtlasMiningConfig.CalculateLootWeights(playerLevel, campTier, pickaxeTier, false)

    -- Check if player can access this camp
    if not weights then
        local requiredLevel = totalWeight -- totalWeight contains required level when weights is nil
        VORPcore.NotifyRightTip(source, "~r~Come back when you improve (Level Required: " .. requiredLevel .. ")", 4000)
        return false
    end

    if totalWeight <= 0 then
        print("^1[LOOT DEBUG]^7 No valid loot weights calculated for player " .. source)
        return false
    end

    -- Roll for primary loot
    local primaryLoot = AtlasMiningConfig.RollForLoot(weights, totalWeight)
    if primaryLoot then
        AwardLoot(source, primaryLoot, 1, false)
    end

    -- Calculate bonus loot chance
    local bonusChance = AtlasMiningConfig.CalculateBonusChance(playerLevel, pickaxeTier)
    local bonusRoll = math.random() * 100

    if Config.DebugLogging then
        print("^3[LOOT DEBUG]^7 Bonus chance: " .. string.format("%.1f%%", bonusChance) .. " - Roll: " .. string.format("%.1f", bonusRoll))
    end

    -- Roll for bonus loot
    local hasBonusLoot = false
    if bonusRoll <= bonusChance then
        local bonusWeights, bonusTotalWeight = AtlasMiningConfig.CalculateLootWeights(playerLevel, campTier, pickaxeTier, true)

        if bonusWeights and bonusTotalWeight > 0 then
            local bonusLoot = AtlasMiningConfig.RollForLoot(bonusWeights, bonusTotalWeight)
            if bonusLoot then
                AwardLoot(source, bonusLoot, 1, true)
                hasBonusLoot = true
            end
        end
    end

    -- Return whether bonus loot was awarded (for XP calculation)
    return hasBonusLoot
end

-- Helper: Subscribe player to nearby camps
local function SubscribePlayerToCamps(playerId, playerCoords)
    if Config.DebugLogging then
        print(string.format("^3[SUBSCRIBE DEBUG]^7 SubscribePlayerToCamps called - Player %d at (%.1f, %.1f, %.1f)",
            playerId, playerCoords.x, playerCoords.y, playerCoords.z))
        print("^3[SUBSCRIBE DEBUG]^7 GlobalCamps has " .. #GlobalCamps .. " camps")
    end

    local closestCamps = {}

    for _, camp in ipairs(GlobalCamps) do
        local distance = GetDistance(playerCoords.x, playerCoords.y, playerCoords.z, camp.x, camp.y, camp.z)
        if Config.DebugLogging then
            print(string.format("^3[SUBSCRIBE DEBUG]^7 Camp %d at (%.1f, %.1f, %.1f) - distance: %.1f meters", camp.id,
                camp.x, camp.y, camp.z, distance))
        end

        if distance <= Config.RenderDistance then
            if Config.DebugLogging then
                print("^2[SUBSCRIBE DEBUG]^7 Camp " .. camp.id .. " IS IN RANGE")
            end
            table.insert(closestCamps, {
                id = camp.id,
                x = camp.x,
                y = camp.y,
                z = camp.z,
                distance = distance,
                tier = camp.tier
            })
        else
            if Config.DebugLogging then
                print("^3[SUBSCRIBE DEBUG]^7 Camp " .. camp.id .. " is out of range")
            end
        end
    end

    if Config.DebugLogging then
        print("^3[SUBSCRIBE DEBUG]^7 Player will be subscribed to " .. #closestCamps .. " camps")
    end

    -- Update CampClients tracking - REMOVE from dead camps
    if Config.DebugLogging then
        print("^3[SUBSCRIBE DEBUG]^7 Checking existing subscriptions...")
    end

    for campId, _ in pairs(CampClients) do
        local stillInRange = false
        for _, camp in ipairs(closestCamps) do
            if camp.id == campId then
                stillInRange = true
                break
            end
        end

        if not stillInRange and CampClients[campId] then
            if Config.DebugLogging then
                print("^1[SUBSCRIBE DEBUG]^7 Removing player " ..
                playerId .. " from camp " .. campId .. " (out of range)")
            end
            CampClients[campId][playerId] = nil
        end
    end

    -- ADD to new camps
    if Config.DebugLogging then
        print("^3[SUBSCRIBE DEBUG]^7 Adding to new camps...")
    end

    for _, camp in ipairs(closestCamps) do
        if not CampClients[camp.id] then
            if Config.DebugLogging then
                print("^2[SUBSCRIBE DEBUG]^7 Creating CampClients[" .. camp.id .. "]")
            end
            CampClients[camp.id] = {}
        end
        if Config.DebugLogging then
            print("^2[SUBSCRIBE DEBUG]^7 Adding player " .. playerId .. " to camp " .. camp.id)
        end
        CampClients[camp.id][playerId] = true
    end

    if Config.DebugLogging then
        print("^2[SUBSCRIBE DEBUG]^7 Final CampClients state:")
        for cId, clients in pairs(CampClients) do
            print("  Camp " .. cId .. ": " .. CountTable(clients) .. " clients")
        end
    end

    return closestCamps
end

-- =============================================
-- EVENTS
-- =============================================

RegisterServerEvent('atlas_mining:server:playerLoaded')
AddEventHandler('atlas_mining:server:playerLoaded', function()
    local _source = source
    print("^2[PLAYER LOADED]^7 Server received playerLoaded from player " .. _source)

    local user = VORPcore.getUser(_source)
    if not user then
        print("^1[PLAYER LOADED]^7 No user object for player " .. _source)
        return
    end

    local character = user.getUsedCharacter
    if not character then
        print("^1[PLAYER LOADED]^7 No character for player " .. _source)
        return
    end

    -- Get player position from player ped (standard RedM approach)
    local ped = GetPlayerPed(_source)
    if ped == 0 then
        print("^1[PLAYER LOADED]^7 No ped for player " .. _source)
        return
    end

    local playerCoords = GetEntityCoords(ped)
    print("^2[PLAYER LOADED]^7 Player " .. _source .. " at (" .. string.format("%.1f", playerCoords.x) .. ", " .. string.format("%.1f", playerCoords.y) .. ", " .. string.format("%.1f", playerCoords.z) .. ")")
    print("^2[PLAYER LOADED]^7 GlobalCamps count: " .. #GlobalCamps .. " GlobalNodes count: " .. #GlobalNodes)

    local closestCamps = SubscribePlayerToCamps(_source, playerCoords)

    -- Send initial camp state to client (full load with all rocks)
    print("^2[PLAYER LOADED]^7 Sending loadCamps to player " .. _source .. " with " .. #closestCamps .. " camps and " .. #GlobalNodes .. " nodes")
    TriggerClientEvent('atlas_mining:client:loadCamps', _source, closestCamps, GlobalNodes, CampRockStates)
end)

-- Periodic subscription update (WITHOUT reloading all rocks)
RegisterServerEvent('atlas_mining:server:updateSubscriptions')
AddEventHandler('atlas_mining:server:updateSubscriptions', function()
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user then return end

    local character = user.getUsedCharacter
    if not character then return end

    -- Get player position from player ped
    local ped = GetPlayerPed(_source)
    if ped == 0 then return end

    local playerCoords = GetEntityCoords(ped)
    -- Just update subscriptions, don't send full loadCamps event
    local closestCamps = SubscribePlayerToCamps(_source, playerCoords)
    if Config.DebugLogging then
        print("^3[SUBSCRIPTIONS]^7 Updated player " ..
        _source .. " subscriptions - " .. #closestCamps .. " camps in range")
    end
end)

RegisterServerEvent('atlas_mining:server:saveNode')
AddEventHandler('atlas_mining:server:saveNode', function(campId, coords, modelName)
    -- Server picks the model if not specified or empty (ensures all players see the same rock)
    if not modelName or modelName == "" then
        local rocks = Config.Rocks
        modelName = rocks[math.random(1, #rocks)]
    end

    exports.oxmysql:insert('INSERT INTO atlas_mining_nodes (camp_id, x, y, z, model_name) VALUES (?, ?, ?, ?, ?)',
        { campId, coords.x, coords.y, coords.z, modelName }, function(id)
            if id then
                local node = { x = coords.x, y = coords.y, z = coords.z, model_name = modelName, camp_id = campId }
                table.insert(GlobalNodes, node)

                -- Broadcast to all clients (they'll spawn if they're tracking this camp)
                TriggerClientEvent('atlas_mining:client:spawnSingleNode', -1, node, campId)
            else
                print("^1[Atlas Mining]^7 Failed to save node for camp " .. campId)
            end
        end)
end)

RegisterServerEvent('atlas_mining:server:requestStart')
AddEventHandler('atlas_mining:server:requestStart', function(coords, campId, rockIndex, nodeData)
    local _source = source
    print("^2[MINE FLOW]^7 requestStart [SERVER] - Player " ..
    _source .. " | Camp " .. campId .. " | Rock " .. rockIndex)

    -- Generate random number of hits required (like woodcutting)
    local hitsRequired = math.random(Config.MinHitsRequired, Config.MaxHitsRequired)
    
    local token = "MINE_" .. math.random(1000, 9999)
    ActiveTasks[_source] = {
        token = token,
        startTime = os.time(),
        campId = campId,
        rockIndex = rockIndex,
        nodeData = nodeData,
        hitsRequired = hitsRequired
    }
    print("^2[MINE FLOW]^7 Token created: " .. token .. " | Hits required: " .. hitsRequired)
    print("^2[MINE FLOW]^7 Sending beginMining to client " .. _source)
    TriggerClientEvent('atlas_mining:client:beginMining', _source, token, hitsRequired)
end)

RegisterServerEvent('atlas_mining:server:finishMine')
AddEventHandler('atlas_mining:server:finishMine', function(token)
    local _source = source
    print("^2[MINE FLOW]^7 finishMine [SERVER] - Player " .. _source .. " | Token: " .. token)

    local task = ActiveTasks[_source]
    if not task or task.token ~= token then
        if not task then
            print("^1[MINE FLOW]^7 ERROR: No active task for player " .. _source)
        else
            print("^1[MINE FLOW]^7 ERROR: Token mismatch!")
        end
        return
    end

    local campId = task.campId
    local rockIndex = task.rockIndex
    local nodeData = task.nodeData
    print("^2[MINE FLOW]^7 Marking rock depleted - Camp " .. campId .. " | Rock " .. rockIndex)

    -- Get camp info for loot and XP calculation
    local camp = GetCampById(campId)
    local campTier = camp and camp.tier or 1

    -- Process loot rewards and get bonus loot status for XP calculation
    local hasBonusLoot = ProcessMiningLoot(_source, campTier)

    -- Get player's pickaxe tier for XP calculation
    local pickaxeTier = GetPlayerPickaxeTier(_source)

    -- Calculate XP reward based on camp tier, pickaxe tier, and bonus loot
    local xpReward = AtlasMiningConfig.CalculateXPReward(campTier, pickaxeTier, hasBonusLoot)

    -- Award XP using Atlas_skilling export
    local success, result = pcall(function()
        return exports['Atlas_skilling']:AddSkillXP(_source, 'mining', xpReward)
    end)

    if not success then
        print("^1[Atlas Mining]^7 Error awarding XP to player " .. _source .. ": " .. tostring(result))
        print("^1[Atlas Mining]^7 Make sure Atlas_skilling resource is started and loaded properly")
    else
        if Config.DebugLogging then
            local bonusText = hasBonusLoot and " (BONUS XP for double loot!)" or ""
            print("^2[MINE FLOW]^7 Successfully awarded " .. xpReward .. " mining XP to player " .. _source .. bonusText)
        end
        
        -- Send XP notification to client
        local bonusText = hasBonusLoot and " (Bonus XP!)" or ""
        VORPcore.NotifyRightTip(_source, "~b~+" .. xpReward .. " Mining XP" .. bonusText, 4000)
    end

    -- Mark rock as depleted
    if not CampRockStates[campId] then
        CampRockStates[campId] = {}
    end

    local mineTime = os.time()
    CampRockStates[campId][rockIndex] = mineTime
    print("^2[MINE FLOW]^7 CampRockStates updated, checking subscriptions...")

    -- Notify all clients tracking this camp about the depleted rock
    print("^2[MINE FLOW]^7 Looking for CampClients[" .. campId .. "]")
    if CampClients[campId] then
        local clientCount = CountTable(CampClients[campId])
        print("^2[MINE FLOW]^7 Found " .. clientCount .. " subscribed clients for camp " .. campId)
        for clientId, _ in pairs(CampClients[campId]) do
            print("^2[MINE FLOW]^7 Sending rockMinedDeath to client " .. clientId)
            TriggerClientEvent('atlas_mining:client:rockMinedDeath', clientId, campId, rockIndex, nodeData)
        end
    else
        print("^1[MINE FLOW]^7 ERROR: NO SUBSCRIBED CLIENTS for camp " .. campId)
    end

    -- Schedule respawn timer
    if camp then
        local respawnSeconds = GetRespawnSeconds(camp.tier)
        local timerKey = campId .. "_" .. rockIndex

        RespawnTimers[timerKey] = SetTimeout(respawnSeconds * 1000, function()
            -- Rock respawns
            CampRockStates[campId][rockIndex] = nil

            -- Notify all clients tracking this camp about the respawn
            if CampClients[campId] then
                for clientId, _ in pairs(CampClients[campId]) do
                    TriggerClientEvent('atlas_mining:client:rockRespawn', clientId, campId, rockIndex, nodeData)
                end
            end

            RespawnTimers[timerKey] = nil
            print("^2[Atlas Mining]^7 Rock " .. rockIndex .. " respawned in camp " .. campId)
        end)
    end

    ActiveTasks[_source] = nil
end)

-- =============================================
-- ADMIN COMMANDS
-- =============================================

RegisterCommand('createcamp', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 /createcamp is for in-game players only")
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
    local model = args[4] or nil  -- nil = random mixture from Config.Rocks
    local name = args[5] or "Unnamed_Camp"

    -- Validate parameters against config ranges
    if radius < Config.RadiusRange.min or radius > Config.RadiusRange.max then
        VORPcore.NotifyRightTip(_source, "~r~Radius must be " .. Config.RadiusRange.min .. "-" .. Config.RadiusRange.max,
            4000)
        return
    end
    if count < Config.RockCountRange.min or count > Config.RockCountRange.max then
        VORPcore.NotifyRightTip(_source,
            "~r~Rock count must be " .. Config.RockCountRange.min .. "-" .. Config.RockCountRange.max, 4000)
        return
    end
    if tier < Config.TierRange.min or tier > Config.TierRange.max then
        VORPcore.NotifyRightTip(_source, "~r~Tier must be " .. Config.TierRange.min .. "-" .. Config.TierRange.max, 4000)
        return
    end

    local dbModel = model or "mixed"  -- "mixed" = random rocks from Config.Rocks
    exports.oxmysql:insert(
        'INSERT INTO atlas_mining_camps (x, y, z, radius, rock_count, tier, model_name, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier, dbModel, name }, function(cId)
            if cId then
                -- Success: Update GlobalCamps immediately
                RefreshGlobalCamps(function()
                    if Config.DebugLogging then
                        print("^2[CREATE CAMP]^7 GlobalCamps refreshed after creating camp ID " .. cId)
                    end
                end)

                VORPcore.NotifyRightTip(_source, "~g~Camp '" .. name .. "' created with " .. count .. " rocks", 4000)
                TriggerClientEvent('atlas_mining:client:generateCampNodes', _source, cId, pCoords, radius, count,
                    model)
                print("^2[Atlas Mining Admin]^7 Camp '" .. name .. "' (ID: " .. cId .. ") created by player " .. _source)
            else
                VORPcore.NotifyRightTip(_source, "~r~Failed to create camp in database", 4000)
                print("^1[Atlas Mining]^7 Failed to insert camp for admin " .. _source)
            end
        end)
end)

RegisterCommand('wipecamp', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 /wipecamp is for in-game players only")
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
        VORPcore.NotifyRightTip(_source, "~r~Usage: /wipecamp [id|all]", 4000)
        return
    end

    if targetId == 'all' then
        -- Wipe all camps
        exports.oxmysql:execute('DELETE FROM atlas_mining_nodes')
        exports.oxmysql:execute('DELETE FROM atlas_mining_camps', {}, function()
            -- Update both GlobalCamps and GlobalNodes after successful deletion
            GlobalCamps = {}
            GlobalNodes = {}
            CampClients = {}  -- Clear all subscriptions
            CampRockStates = {} -- Clear all rock states

            if Config.DebugLogging then
                print("^2[WIPE ALL]^7 Cleared all GlobalCamps, GlobalNodes, CampClients, and CampRockStates")
            end

            TriggerClientEvent('atlas_mining:client:wipeAllCamps', -1)
            VORPcore.NotifyRightTip(_source, "~g~All camps wiped successfully", 4000)
            print("^2[Atlas Mining Admin]^7 All camps wiped by player " .. _source)
        end)
    else
        -- Wipe specific camp by ID
        local cId = tonumber(targetId)
        if not cId then
            VORPcore.NotifyRightTip(_source, "~r~Camp ID must be a number", 4000)
            return
        end

        exports.oxmysql:execute('SELECT id FROM atlas_mining_camps WHERE id = ?', { cId }, function(result)
            if result and result[1] then
                exports.oxmysql:execute('DELETE FROM atlas_mining_nodes WHERE camp_id = ?', { cId })
                exports.oxmysql:execute('DELETE FROM atlas_mining_camps WHERE id = ?', { cId }, function()
                    -- Update GlobalCamps and GlobalNodes after successful deletion
                    RefreshGlobalCamps(function()
                        RefreshGlobalNodes(function()
                            -- Clean up related data structures
                            CampClients[cId] = nil
                            CampRockStates[cId] = nil

                            -- Clear any respawn timers for this camp
                            for timerKey, timerId in pairs(RespawnTimers) do
                                if timerKey:match("^" .. cId .. "_") then
                                    RemoveTimeout(timerId)
                                    RespawnTimers[timerKey] = nil
                                end
                            end

                            if Config.DebugLogging then
                                print("^2[WIPE CAMP]^7 Cleaned up all data for camp ID " .. cId)
                            end

                            TriggerClientEvent('atlas_mining:client:wipeSpecificCamp', -1, cId)
                            VORPcore.NotifyRightTip(_source, "~g~Camp ID " .. cId .. " wiped successfully", 4000)
                            print("^2[Atlas Mining Admin]^7 Camp ID " .. cId .. " wiped by player " .. _source)
                        end)
                    end)
                end)
            else
                VORPcore.NotifyRightTip(_source, "~r~Camp ID " .. cId .. " not found", 4000)
            end
        end)
    end
end)

RegisterCommand('listcamps', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 /listcamps is for in-game players only")
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
        'SELECT id, name, radius, rock_count, tier, x, y, z FROM atlas_mining_camps ORDER BY name ASC', {},
        function(result)
            if not result or #result == 0 then
                print("^3[Atlas Mining]^7 No camps found in database.")
                return
            end

            local itemsPerPage = 10
            local totalCamps = #result
            local totalPages = math.ceil(totalCamps / itemsPerPage)

            if page > totalPages then page = totalPages end

            local startIdx = (page - 1) * itemsPerPage + 1
            local endIdx = math.min(page * itemsPerPage, totalCamps)

            -- Print header
            print("^2================================================^7")
            print(string.format("^2 ATLAS MINING CAMPS - PAGE %d/%d^7", page, totalPages))
            print("^2================================================^7")
            print(string.format("^3%-4s^7 | ^3%-18s^7 | ^3%-7s^7 | ^3%-5s^7 | ^3%-4s^7 | ^3%-8s^7 | ^3%-8s^7 | ^3%-8s^7",
                "ID", "Name", "Radius", "Rocks", "Tier", "X", "Y", "Z"))
            print("^2----|--------------------|---------|---------|---------|-----------|-----------|-----------^7")

            -- Print camp entries
            for i = startIdx, endIdx do
                local camp = result[i]
                print(string.format(
                    "^7%-4d^7 | ^6%-18s^7 | ^5%-7.1f^7 | ^4%-5d^7 | ^3%-4d^7 | ^2%-8.2f^7 | ^2%-8.2f^7 | ^2%-8.2f^7",
                    camp.id,
                    camp.name:sub(1, 18),
                    camp.radius,
                    camp.rock_count,
                    camp.tier,
                    camp.x,
                    camp.y,
                    camp.z
                ))
            end

            print("^2================================================^7")
            print(string.format("^3Total: %d camps | Showing %d-%d^7", totalCamps, startIdx, endIdx))
            print("^2================================================^7")
        end)
end)

-- Debug command to manually refresh camp data
RegisterCommand('refreshcamps', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 /refreshcamps is for in-game players only")
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

    RefreshGlobalCamps(function()
        RefreshGlobalNodes(function()
            VORPcore.NotifyRightTip(_source, "~g~Camp data refreshed successfully", 4000)
            print("^2[Atlas Mining Admin]^7 Camp data manually refreshed by player " .. _source)
            print("^2[Atlas Mining Admin]^7 Now tracking " .. #GlobalCamps .. " camps and " .. #GlobalNodes .. " nodes")
        end)
    end)
end)

-- Debug command to test loot calculations
RegisterCommand('testmineloot', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 Use this command in-game")
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
    local campTier = tonumber(args[2]) or 1
    local pickaxeTier = tonumber(args[3]) or 1

    print("^2[LOOT TEST]^7 Testing loot calculation:")
    print("^3  Player Level:^7 " .. playerLevel)
    print("^3  Camp Tier:^7 " .. campTier)
    print("^3  Pickaxe Tier:^7 " .. pickaxeTier)

    -- Calculate weights
    local weights, totalWeight = AtlasMiningConfig.CalculateLootWeights(playerLevel, campTier, pickaxeTier, false)

    if not weights then
        local requiredLevel = totalWeight
        print("^1[LOOT TEST]^7 Player cannot access tier " .. campTier .. " camp (requires level " .. requiredLevel .. ")")
        return
    end

    -- Display probabilities
    print("^2[LOOT TEST]^7 Primary Loot Probabilities:")
    for oreType, weight in pairs(weights) do
        local percentage = (weight / totalWeight) * 100
        print("^3  " .. oreType .. ":^7 " .. string.format("%.2f%% (weight: %.2f)", percentage, weight))
    end

    -- Calculate bonus chance
    local bonusChance = AtlasMiningConfig.CalculateBonusChance(playerLevel, pickaxeTier)
    print("^2[LOOT TEST]^7 Bonus Loot Chance: " .. string.format("%.1f%%", bonusChance))

    -- Calculate XP rewards
    local baseXP = AtlasMiningConfig.CalculateXPReward(campTier, pickaxeTier, false)
    local bonusXP = AtlasMiningConfig.CalculateXPReward(campTier, pickaxeTier, true)
    print("^2[XP TEST]^7 XP Rewards:")
    print("^3  Base XP (no bonus loot):^7 " .. baseXP)
    print("^3  Bonus XP (with bonus loot):^7 " .. bonusXP .. " (+" .. (bonusXP - baseXP) .. " bonus)")

    -- Test multiple rolls
    print("^2[LOOT TEST]^7 Sample rolls (10x):")
    for i = 1, 10 do
        local result = AtlasMiningConfig.RollForLoot(weights, totalWeight)
        local bonusRoll = math.random() * 100
        local bonusResult = ""
        local xpAmount = baseXP

        if bonusRoll <= bonusChance then
            local bonusWeights, bonusTotalWeight = AtlasMiningConfig.CalculateLootWeights(playerLevel, campTier, pickaxeTier, true)
            if bonusWeights and bonusTotalWeight > 0 then
                local bonusLoot = AtlasMiningConfig.RollForLoot(bonusWeights, bonusTotalWeight)
                bonusResult = " + " .. (bonusLoot or "NONE") .. " (bonus)"
                xpAmount = bonusXP
            end
        end

        print("^3  Roll " .. i .. ":^7 " .. (result or "NONE") .. bonusResult .. " | XP: " .. xpAmount)
    end

    VORPcore.NotifyRightTip(_source, "~g~Loot & XP test complete - check console", 3000)
end)

-- Debug command to check player's pickaxe tier
RegisterCommand('checkpickaxe', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 Use this command in-game")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local pickaxeTier = GetPlayerPickaxeTier(_source)
    print("^2[PICKAXE CHECK]^7 Player " .. _source .. " has pickaxe tier: " .. pickaxeTier)

    -- Show which pickaxes they have
    print("^2[PICKAXE CHECK]^7 Player's pickaxes:")
    for pickName, pickData in pairs(Config.Pickaxes) do
        local success, hasPick = pcall(function()
            local item = exports.vorp_inventory:getItem(_source, pickName)
            return item and item.count and item.count > 0
        end)

        if success and hasPick then
            print("^3  " .. pickName .. ":^7 Tier " .. pickData.tier .. " ✓")
        else
            print("^1  " .. pickName .. ":^7 Tier " .. pickData.tier .. " ✗")
        end
    end

    VORPcore.NotifyRightTip(_source, "~g~Pickaxe tier: " .. pickaxeTier .. " - Check console for details", 3000)
end)

-- Command to validate loot system configuration
RegisterCommand('validatemineloot', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 /validatemineloot is for in-game players only")
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

    local isValid = AtlasMiningConfig.ValidateLootSystem()

    if isValid then
        print("^2[LOOT VALIDATION]^7 ✓ Loot system configuration is valid")
        VORPcore.NotifyRightTip(_source, "~g~Loot system configuration is valid", 3000)
    else
        print("^1[LOOT VALIDATION]^7 ✗ Loot system configuration has errors")
        VORPcore.NotifyRightTip(_source, "~r~Loot system has configuration errors - check console", 4000)
    end
end)

-- Command to test XP scaling across all tiers
RegisterCommand('testminexp', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 Use this command in-game")
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

    print("^2[XP TEST]^7 XP Scaling by Camp Tier and Pickaxe Tier:")
    print("^2================================================================^7")

    -- Test XP scaling across all combinations
    for campTier = 1, 5 do
        print("^3Camp Tier " .. campTier .. ":^7")
        for pickaxeTier = 1, 5 do
            local baseXP = AtlasMiningConfig.CalculateXPReward(campTier, pickaxeTier, false)
            local bonusXP = AtlasMiningConfig.CalculateXPReward(campTier, pickaxeTier, true)
            local pickName = ""

            -- Get pickaxe name for display
            for name, data in pairs(Config.Pickaxes) do
                if data.tier == pickaxeTier then
                    pickName = name:gsub("_", " "):gsub("(%a)([%a%d]*)", function(a, b) return a:upper()..b end)
                    break
                end
            end

            print(string.format("^7  %s (Tier %d): ^2%d XP^7 base | ^6%d XP^7 with bonus (+%d)",
                pickName, pickaxeTier, baseXP, bonusXP, (bonusXP - baseXP)))
        end
        print("")
    end

    print("^2================================================================^7")
    print("^3Summary:^7")
    print("^7• Camp tiers double base XP each level (150 → 300 → 600 → 1200 → 2400)")
    print("^7• Pickaxe tiers provide scaling multipliers (1.0x → 1.1x → 1.2x → 1.3x → 1.5x)")
    print("^7• Bonus loot awards double XP (2.0x multiplier)")
    print("^2================================================================^7")

    VORPcore.NotifyRightTip(_source, "~g~XP scaling test complete - check console", 3000)
end)

-- Simulate loot command
RegisterCommand('simulatemineloot', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Mining]^7 Use this command in-game")
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

    local campTier = tonumber(args[1]) or 1

    print("^2[LOOT SIMULATE]^7 Simulating complete mining experience for player " .. _source .. " in tier " .. campTier .. " camp")

    -- Process loot and get bonus status
    local hasBonusLoot = ProcessMiningLoot(_source, campTier)

    -- Get player's pickaxe tier and calculate XP
    local pickaxeTier = GetPlayerPickaxeTier(_source)
    local xpReward = AtlasMiningConfig.CalculateXPReward(campTier, pickaxeTier, hasBonusLoot)

    -- Simulate XP award
    local bonusText = hasBonusLoot and " (DOUBLE XP for bonus loot!)" or ""
    print("^2[LOOT SIMULATE]^7 Would award " .. xpReward .. " XP" .. bonusText)

    VORPcore.NotifyRightTip(_source, "~g~Simulation complete: " .. xpReward .. " XP" .. (hasBonusLoot and " (BONUS!)" or ""), 4000)
end)

-- =============================================
-- PLAYER DISCONNECT CLEANUP
-- =============================================

AddEventHandler('playerDropped', function(reason)
    local _source = source
    if ActiveTasks[_source] then
        ActiveTasks[_source] = nil
        print("^2[Atlas Mining]^7 Cleaned up active task for disconnected player " .. _source)
    end

    -- Remove from CampClients tracking
    for campId, clients in pairs(CampClients) do
        if clients[_source] then
            clients[_source] = nil
            print("^2[Atlas Mining]^7 Unsubscribed player " .. _source .. " from camp " .. campId)
        end
    end
end)
