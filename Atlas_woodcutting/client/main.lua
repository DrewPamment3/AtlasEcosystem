local isBusy = false
local GroveRegistry = {}   -- {forestId, treeIndex, coords, entity (tree or stump), isStump}
local RenderedForests = {} -- Forests currently being rendered
local TreeStumpMap = {}    -- Map of treeIndex -> stump entity for quick lookup

-- Enhanced Animation System Variables
local currentAnimationScenario = nil
local animationEffectsActive = false
local soundHandle = nil

-- Enhanced Animation System Functions

-- Try to start the best available chopping animation
local function StartChoppingAnimation(playerPed)
    if not playerPed or playerPed == 0 then
        return false, nil
    end
    
    -- Clear any existing tasks
    ClearPedTasks(playerPed)
    
    -- Try each animation scenario in order of preference
    for i, scenario in ipairs(AtlasWoodConfig.Animations.scenarios) do
        -- Test if scenario is valid by trying to start it
        local success = pcall(function()
            TaskStartScenarioInPlace(playerPed, scenario, -1, true)
        end)
        
        if success then
            -- Wait a frame to see if the animation actually started
            Citizen.Wait(100)
            
            -- Check if the ped is actually using this scenario
            if IsPedUsingScenario(playerPed, scenario) then
                currentAnimationScenario = scenario
                if AtlasWoodConfig.DebugLogging then
                    print("^2[ANIMATION]^7 Successfully started scenario: " .. scenario)
                end
                return true, scenario
            else
                if AtlasWoodConfig.DebugLogging then
                    print("^3[ANIMATION]^7 Scenario " .. scenario .. " started but not active, trying next...")
                end
            end
        else
            if AtlasWoodConfig.DebugLogging then
                print("^1[ANIMATION]^7 Failed to start scenario: " .. scenario)
            end
        end
    end
    
    -- If all scenarios failed, log error but continue (animation is optional)
    print("^1[ANIMATION]^7 All animation scenarios failed - continuing without animation")
    return false, nil
end

-- Start visual and audio effects for wood chopping
local function StartWoodChoppingEffects(playerPed)
    if not AtlasWoodConfig.Animations.effects.particlesEnabled and not AtlasWoodConfig.Animations.sounds.enabled then
        return
    end
    
    animationEffectsActive = true
    
    Citizen.CreateThread(function()
        while animationEffectsActive do
            -- Particle effects (wood chips)
            if AtlasWoodConfig.Animations.effects.particlesEnabled then
                local pedCoords = GetEntityCoords(playerPed)
                local heading = GetEntityHeading(playerPed)
                
                -- Calculate position in front of player (where they're chopping)
                local forwardX = math.sin(math.rad(heading))
                local forwardY = -math.cos(math.rad(heading))
                local effectX = pedCoords.x + (forwardX * 1.0)
                local effectY = pedCoords.y + (forwardY * 1.0)
                local effectZ = pedCoords.z + 1.0
                
                -- Trigger wood chip particle effect (simplified for RedM compatibility)
                -- Note: Many GTA V particle effects don't exist in RedM
                local success = pcall(function()
                    SetPtfxAssetNextCall("scr_bike_dirtbike")
                    StartParticleFxLoopedAtCoord("scr_bike_rear_wheels", effectX, effectY, effectZ, 0.0, 0.0, 0.0, 
                        AtlasWoodConfig.Animations.effects.particleScale, false, false, false, false)
                end)
                
                if not success and AtlasWoodConfig.DebugLogging then
                    print("^3[ANIMATION]^7 Particle effect failed - continuing without particles")
                end
            end
            
            Citizen.Wait(AtlasWoodConfig.Animations.effects.particleFrequency)
        end
    end)
end

-- Play chopping sound effects
local function PlayChoppingSound(soundType)
    if not AtlasWoodConfig.Animations.sounds.enabled then
        return
    end
    
    local soundName = nil
    
    if soundType == "chop" then
        soundName = AtlasWoodConfig.Animations.sounds.choppingLoop
    elseif soundType == "completion" then
        soundName = AtlasWoodConfig.Animations.sounds.completionSound
    elseif soundType == "interruption" then
        soundName = AtlasWoodConfig.Animations.sounds.interruptionSound
    end
    
    if soundName then
        -- Play sound with error handling for RedM compatibility
        local success = pcall(function()
            PlaySoundFromEntity(-1, soundName, PlayerPedId(), "", 0, 0)
        end)
        
        if not success and AtlasWoodConfig.DebugLogging then
            print("^3[ANIMATION]^7 Sound effect '" .. soundName .. "' failed - continuing without sound")
        end
    end
end

-- Stop all chopping effects
local function StopWoodChoppingEffects()
    animationEffectsActive = false
    
    if soundHandle then
        StopSound(soundHandle)
        soundHandle = nil
    end
    
    -- Clear particle effects with error handling
    pcall(function()
        RemoveParticleFxInRange(GetEntityCoords(PlayerPedId()), 5.0)
    end)
end

-- Check for animation interruption conditions
local function CheckAnimationInterruption(playerPed, startCoords, startHealth)
    local config = AtlasWoodConfig.Animations.interruption
    
    -- Movement check
    local currentCoords = GetEntityCoords(playerPed)
    local distance = #(startCoords - currentCoords)
    if distance > config.maxMovementDistance then
        if AtlasWoodConfig.DebugLogging then
            print("^1[ANIMATION]^7 Interrupted - Player moved " .. string.format("%.2f", distance) .. "m (max: " .. config.maxMovementDistance .. "m)")
        end
        return true, "movement"
    end
    
    -- Health check (if enabled)
    if config.healthCheckEnabled then
        local currentHealth = GetEntityHealth(playerPed)
        if currentHealth < startHealth then
            if AtlasWoodConfig.DebugLogging then
                print("^1[ANIMATION]^7 Interrupted - Player took damage (health: " .. currentHealth .. " -> " .. startHealth .. ")")
            end
            return true, "damage"
        end
    end
    
    -- Combat check (if enabled)
    if config.combatCheckEnabled then
        if IsPedInCombat(playerPed, 0) then
            if AtlasWoodConfig.DebugLogging then
                print("^1[ANIMATION]^7 Interrupted - Player entered combat")
            end
            return true, "combat"
        end
    end
    
    -- Check if player is still using the animation scenario
    if currentAnimationScenario and not IsPedUsingScenario(playerPed, currentAnimationScenario) then
        if AtlasWoodConfig.DebugLogging then
            print("^1[ANIMATION]^7 Interrupted - Animation scenario stopped")
        end
        return true, "animation_stopped"
    end
    
    return false, nil
end

-- Progress bar drawing function (define first)
local function DrawProgressBar(progress)
    -- Only draw if progress is valid
    if not progress or progress < 0 or progress > 1 then
        return
    end
    
    local barWidth = 0.25
    local barHeight = 0.025
    local x = 0.5
    local y = 0.8
    
    -- Background (dark)
    DrawRect(x, y, barWidth, barHeight, 0, 0, 0, 180)
    
    -- Progress fill (brown/wood color)
    if progress > 0 then
        local fillWidth = barWidth * progress
        local fillX = x - (barWidth / 2) + (fillWidth / 2)
        DrawRect(fillX, y, fillWidth, barHeight - 0.004, 139, 94, 60, 255) -- Brown wood color
    end
    
    -- Border frame
    DrawRect(x, y - (barHeight / 2) + 0.001, barWidth, 0.002, 255, 255, 255, 255) -- Top
    DrawRect(x, y + (barHeight / 2) - 0.001, barWidth, 0.002, 255, 255, 255, 255) -- Bottom
    DrawRect(x - (barWidth / 2) + 0.001, y, 0.002, barHeight, 255, 255, 255, 255) -- Left  
    DrawRect(x + (barWidth / 2) - 0.001, y, 0.002, barHeight, 255, 255, 255, 255) -- Right
    
    -- Progress text with animation status
    SetTextScale(0.4, 0.4)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextFontForCurrentCommand(1)
    local progressText = "Chopping... " .. math.floor(progress * 100) .. "%"
    
    -- Add animation status indicator
    if currentAnimationScenario then
        progressText = progressText .. " ✓"
    else
        progressText = progressText .. " ⚠"
    end
    
    DisplayText(CreateVarString(10, "LITERAL_STRING", progressText), x, y + 0.04)
end

-- Progress bar state
local isChopping = false
local choppingProgress = 0.0

-- Render thread for smooth progress bar
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        
        if isChopping then
            DrawProgressBar(choppingProgress)
        end
    end
end)

-- [[ UI ]]
local function DrawWoodcuttingPrompt()
    local x, y = 0.5, 0.92
    DrawRect(x, y, 0.12, 0.045, 0, 0, 0, 180)
    SetTextScale(0.38, 0.38)
    SetTextColor(0, 0, 0, 255)
    SetTextCentre(true)
    local gText = CreateVarString(10, "LITERAL_STRING", "G")
    DrawRect(x - 0.035, y, 0.022, 0.032, 255, 255, 255, 255)
    DisplayText(gText, x - 0.035, y - 0.016)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(false)
    SetTextFontForCurrentCommand(1)
    DisplayText(CreateVarString(10, "LITERAL_STRING", "CHOP TREE"), x - 0.018, y - 0.016)
end

-- [[ SPAWNING ]]
local function SpawnLocalTree(node, forestId, treeIndex, isStump)
    isStump = isStump or false
    local modelName = isStump and "p_stump" or node.model_name
    local modelHash = GetHashKey(modelName)

    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = GetGameTimer() + AtlasWoodConfig.ModelLoadTimeout
        while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
            Citizen.Wait(1)
        end

        if not HasModelLoaded(modelHash) then
            print("^1[Atlas Woodcutting]^7 Failed to load model " .. modelName .. " within timeout")
            return
        end
    end

    local _, groundZ = GetGroundZFor_3dCoord(node.x, node.y, 1000.0, 0)
    local zOffset = AtlasWoodConfig.GetTreeZOffset(modelName)
    local tree = CreateObject(modelHash, node.x, node.y, groundZ - zOffset, false, false, false)

    if tree == 0 then
        print("^1[Atlas Woodcutting]^7 ERROR: CreateObject failed for " .. modelName)
        return
    end

    SetEntityRotation(tree, 0.0, 0.0, math.random(0, 360) + 0.0, 2, true)
    FreezeEntityPosition(tree, true)
    SetEntityAsMissionEntity(tree, true, true)

    table.insert(GroveRegistry, {
        forestId = forestId,
        treeIndex = treeIndex,
        coords = vec3(node.x, node.y, node.z),
        entity = tree,
        isStump = isStump
    })

    if isStump then
        TreeStumpMap[treeIndex] = tree
    end

    SetModelAsNoLongerNeeded(modelHash)
    return tree
end

-- [[ INTERACTION LOOP ]]
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        -- UPDATED: Start at 0.9 (waist) and pull distance to 1.3m
        local start = pCoords + vec3(0, 0, 0.9)
        local target = pCoords + (pForward * 1.3) + vec3(0, 0, 0.9)

        DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 255, playerPed, 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        if hit == 1 and entityHit ~= 0 then
            local entCoords = GetEntityCoords(entityHit)
            local matchedNode = nil
            for _, node in ipairs(GroveRegistry) do
                if #(entCoords - node.coords) < 1.5 and not node.isStump then
                    matchedNode = node
                    break
                end
            end

            if matchedNode then
                DrawWoodcuttingPrompt()
                if IsControlJustPressed(0, AtlasWoodConfig.InteractionKey) and not isBusy then
                    print("^2[INTERACTION DEBUG]^7 G key pressed! Starting chop request")
                    print("^2[INTERACTION DEBUG]^7 Forest: " .. matchedNode.forestId .. " | Tree: " .. matchedNode.treeIndex)
                    print("^2[INTERACTION DEBUG]^7 isBusy: " .. tostring(isBusy))
                    print("^2[INTERACTION DEBUG]^7 Sending requestStart event to server...")
                    
                    TriggerServerEvent('atlas_woodcutting:server:requestStart', entCoords, matchedNode.forestId,
                        matchedNode.treeIndex, {
                            x = matchedNode.coords.x,
                            y = matchedNode.coords.y,
                            z = matchedNode.coords.z
                        })
                    
                    print("^2[INTERACTION DEBUG]^7 requestStart event sent!")
                end
            end
        end
    end
end)

-- [[ UTILITY ]]
RegisterCommand('debugtrees', function()
    print("^3[Atlas Debug]^7 Total in Registry: " .. #GroveRegistry)
    for i, node in ipairs(GroveRegistry) do
        print(string.format("Node %s: Forest %s | Tree %s | Entity %s | IsStump %s", i, node.forestId, node.treeIndex,
            tostring(node.entity), tostring(node.isStump)))
    end
end)

--- List all available tree models
RegisterCommand('listtrees', function()
    print("^2[Atlas Woodcutting]^7 Available Tree Models:")
    print("^3================================================^7")
    for modelName, _ in pairs(AtlasWoodConfig.TreeModelZOffsets) do
        print("^2 - ^7" .. modelName)
    end
    print("^3================================================^7")
    print("^3Usage:^7 /createforest [radius] [count] [tier] [model] [name]")
end)

--- DEBUG: Spawn tree model in front of player with custom Z offset
RegisterCommand('spawntree', function(source, args, rawCommand)
    -- Client-side: source is always 0, args is a TABLE directly
    if not args[1] then
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = { "Debug", "Usage: /spawntree [model] [zOffset]" }
        })
        return
    end

    local modelName = args[1]
    local zOffset = args[2] and tonumber(args[2]) or 0.2

    if not zOffset or zOffset < 0 then
        zOffset = 0.2
    end

    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local forwardX = math.sin(math.rad(heading))
    local forwardY = -math.cos(math.rad(heading))

    -- Spawn 3 meters in front of player
    local spawnX = pCoords.x + (forwardX * 3)
    local spawnY = pCoords.y + (forwardY * 3)
    local spawnZ = pCoords.z

    -- Get ground Z
    local found, groundZ = GetGroundZFor_3dCoord(spawnX, spawnY, 1000.0, 0)
    if found then
        spawnZ = groundZ - zOffset
    end

    -- Load and spawn model
    local modelHash = GetHashKey(modelName)
    if not IsModelValid(modelHash) then
        print("^1[Atlas Debug]^7 Invalid model: " .. modelName)
        return
    end

    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = GetGameTimer() + 5000
        while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
            Citizen.Wait(1)
        end

        if not HasModelLoaded(modelHash) then
            print("^1[Atlas Debug]^7 Failed to load model " .. modelName .. " within timeout")
            return
        end
    end

    local tree = CreateObject(modelHash, spawnX, spawnY, spawnZ, false, false, false)
    SetEntityRotation(tree, 0.0, 0.0, 0.0, 2, true)
    FreezeEntityPosition(tree, true)
    SetEntityAsMissionEntity(tree, true, true)
    SetModelAsNoLongerNeeded(modelHash)

    print("^2[Atlas Debug]^7 Spawned " .. modelName .. " with Z offset: " .. zOffset)
    print("^2[Atlas Debug]^7 Position: (" .. spawnX .. ", " .. spawnY .. ", " .. spawnZ .. ")")
end)

-- [[ EVENTS ]]
RegisterNetEvent('atlas_woodcutting:client:loadForests')
AddEventHandler('atlas_woodcutting:client:loadForests', function(forests, nodes, forestTreeStates)
    -- Clear existing registry
    for _, node in ipairs(GroveRegistry) do
        if DoesEntityExist(node.entity) then
            DeleteEntity(node.entity)
        end
    end
    GroveRegistry = {}
    TreeStumpMap = {}
    RenderedForests = {}

    -- Load forests in range
    for _, forest in ipairs(forests) do
        RenderedForests[forest.id] = forest

        -- Find and spawn all trees for this forest
        local treeIndex = 0
        for _, node in ipairs(nodes) do
            if node.forest_id == forest.id then
                treeIndex = treeIndex + 1
                local isDead = forestTreeStates[forest.id] and forestTreeStates[forest.id][treeIndex]

                if isDead then
                    -- Spawn stump
                    SpawnLocalTree(node, forest.id, treeIndex, true)
                else
                    -- Spawn tree
                    SpawnLocalTree(node, forest.id, treeIndex, false)
                end
            end
        end
    end

    print("^2[Atlas Woodcutting]^7 Loaded " .. #forests .. " forests in render range")
end)

RegisterNetEvent('atlas_woodcutting:client:treeChopDeath')
AddEventHandler('atlas_woodcutting:client:treeChopDeath', function(forestId, treeIndex, nodeData)
    print("^2[CHOP FLOW]^7 treeChopDeath [CLIENT] received - Forest " .. forestId .. " | Tree " .. treeIndex)
    print("^2[CHOP FLOW]^7 GroveRegistry size: " .. #GroveRegistry)

    -- Find and delete the tree entity
    local found = false
    for i = #GroveRegistry, 1, -1 do
        local node = GroveRegistry[i]
        if node.forestId == forestId and node.treeIndex == treeIndex and not node.isStump then
            print("^2[CHOP FLOW]^7 Found matching tree at index " .. i .. ", deleting entity " .. tostring(node.entity))
            if DoesEntityExist(node.entity) then
                DeleteEntity(node.entity)
                found = true
            end
            table.remove(GroveRegistry, i)
            break
        end
    end

    if not found then
        print("^1[CHOP FLOW]^7 ERROR: No matching tree found in registry!")
    end

    -- Spawn stump
    SpawnLocalTree(nodeData, forestId, treeIndex, true)
    print("^3[Atlas Woodcutting]^7 Tree " .. treeIndex .. " in forest " .. forestId .. " chopped, stump spawned")
end)

RegisterNetEvent('atlas_woodcutting:client:treeRespawn')
AddEventHandler('atlas_woodcutting:client:treeRespawn', function(forestId, treeIndex, nodeData)
    -- Find and delete the stump entity
    for i = #GroveRegistry, 1, -1 do
        if GroveRegistry[i].forestId == forestId and GroveRegistry[i].treeIndex == treeIndex and GroveRegistry[i].isStump then
            if DoesEntityExist(GroveRegistry[i].entity) then
                DeleteEntity(GroveRegistry[i].entity)
            end
            table.remove(GroveRegistry, i)
            break
        end
    end

    TreeStumpMap[treeIndex] = nil

    -- Respawn tree
    SpawnLocalTree(nodeData, forestId, treeIndex, false)
    print("^3[Atlas Woodcutting]^7 Tree " .. treeIndex .. " in forest " .. forestId .. " respawned")
end)

RegisterNetEvent('atlas_woodcutting:client:wipeSpecificForest')
AddEventHandler('atlas_woodcutting:client:wipeSpecificForest', function(forestId)
    for i = #GroveRegistry, 1, -1 do
        if GroveRegistry[i].forestId == forestId then
            if DoesEntityExist(GroveRegistry[i].entity) then DeleteEntity(GroveRegistry[i].entity) end
            table.remove(GroveRegistry, i)
        end
    end
end)

RegisterNetEvent('atlas_woodcutting:client:wipeAllForests')
AddEventHandler('atlas_woodcutting:client:wipeAllForests', function()
    for i = #GroveRegistry, 1, -1 do
        if DoesEntityExist(GroveRegistry[i].entity) then DeleteEntity(GroveRegistry[i].entity) end
        table.remove(GroveRegistry, i)
    end
    GroveRegistry = {}
    TreeStumpMap = {}
    RenderedForests = {}
end)

RegisterNetEvent('atlas_woodcutting:client:spawnSingleNode')
AddEventHandler('atlas_woodcutting:client:spawnSingleNode', function(node, forestId)
    -- Spawn a single new tree when a node is added to a forest
    -- (doesn't matter if we're currently rendering the forest - loadForests will handle state)

    -- Count existing trees for this forest to get the new index
    local treeIndex = 0
    for _, registryNode in ipairs(GroveRegistry) do
        if registryNode.forestId == forestId and not registryNode.isStump then
            treeIndex = treeIndex + 1
        end
    end
    treeIndex = treeIndex + 1

    SpawnLocalTree(node, forestId, treeIndex, false)
end)

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('atlas_woodcutting:server:playerLoaded')
end)

-- Periodic subscription update: refresh every 15 seconds (without clearing entities)
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(15000) -- Update subscriptions every 15 seconds
        TriggerServerEvent('atlas_woodcutting:server:updateSubscriptions')
    end
end)

RegisterNetEvent('atlas_woodcutting:client:generateForestNodes')
AddEventHandler('atlas_woodcutting:client:generateForestNodes', function(fId, center, radius, count, model)
    for i = 1, count do
        local angle, r = math.random() * 2 * math.pi, radius * math.sqrt(math.random())
        local x = center.x + r * math.cos(angle)
        local y = center.y + r * math.sin(angle)
        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)
        if foundGround then
            TriggerServerEvent('atlas_woodcutting:server:saveNode', fId, vec3(x, y, groundZ), model)
        end
        Citizen.Wait(300)
    end
end)

-- Handle admin animation tests triggered from server
RegisterNetEvent('atlas_woodcutting:client:adminAnimTest')
AddEventHandler('atlas_woodcutting:client:adminAnimTest', function(duration)
    if isBusy then
        print("^1[ADMIN ANIM TEST]^7 Player is busy - cannot run animation test")
        return
    end
    
    print("^2[ADMIN ANIM TEST]^7 Running admin-triggered animation test for " .. duration .. "ms")
    
    local playerPed = PlayerPedId()
    local startCoords = GetEntityCoords(playerPed)
    
    -- Start animation test
    local animationStarted, usedScenario = StartChoppingAnimation(playerPed)
    StartWoodChoppingEffects(playerPed)
    PlayChoppingSound("chop")
    
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 0 },
        args = { "Admin Test", "Animation test started for " .. duration .. "ms" }
    })
    
    -- Run for specified duration
    Citizen.CreateThread(function()
        local startTime = GetGameTimer()
        local lastProgressUpdate = 0
        
        while GetGameTimer() - startTime < duration do
            local progress = (GetGameTimer() - startTime) / duration
            local progressPercent = math.floor(progress * 100)
            
            -- Show progress in chat every 25%
            if progressPercent >= lastProgressUpdate + 25 and progressPercent <= 100 and progressPercent > 0 then
                lastProgressUpdate = progressPercent
                TriggerEvent('chat:addMessage', {
                    color = { 0, 255, 0 },
                    args = { "Animation Test", progressPercent .. "% complete" }
                })
            end
            
            Citizen.Wait(100)
        end
        
        -- Cleanup
        ClearPedTasks(playerPed)
        StopWoodChoppingEffects()
        PlayChoppingSound("completion")
        
        TriggerEvent('chat:addMessage', {
            color = { 0, 255, 0 },
            args = { "Animation Test", "Test completed! Animation: " .. (usedScenario or "NONE") }
        })
        
        print("^2[ADMIN ANIM TEST]^7 Animation test completed - Used: " .. (usedScenario or "FALLBACK"))
    end)
end)

-- Handle real-time config updates from server
RegisterNetEvent('atlas_woodcutting:client:updateConfig')
AddEventHandler('atlas_woodcutting:client:updateConfig', function(configKey, newValue)
    print("^2[CONFIG UPDATE]^7 " .. configKey .. " = " .. tostring(newValue))
    
    if configKey == 'ChopAnimationTime' then
        AtlasWoodConfig.ChopAnimationTime = newValue
    elseif configKey == 'maxMovementDistance' then
        AtlasWoodConfig.Animations.interruption.maxMovementDistance = newValue
    elseif configKey == 'checkInterval' then
        AtlasWoodConfig.Animations.interruption.checkInterval = newValue
    end
    
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 0 },
        args = { "Config Update", configKey .. " updated to " .. tostring(newValue) }
    })
end)

-- Admin command to test animations directly
RegisterCommand('testchopanimation', function(source, args, rawCommand)
    if isBusy then
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 100 },
            args = { "Animation Test", "You are currently busy!" }
        })
        return
    end
    
    local duration = tonumber(args[1]) or 5000
    
    if duration < 1000 or duration > 30000 then
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 100 },
            args = { "Animation Test", "Duration must be between 1000ms and 30000ms" }
        })
        return
    end
    
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 0 },
        args = { "Animation Test", "Testing chopping animation for " .. duration .. "ms" }
    })
    
    local playerPed = PlayerPedId()
    
    -- Start animation test
    local animationStarted, usedScenario = StartChoppingAnimation(playerPed)
    StartWoodChoppingEffects(playerPed)
    PlayChoppingSound("chop")
    
    -- Run for specified duration
    Citizen.CreateThread(function()
        local startTime = GetGameTimer()
        local lastProgressUpdate = 0
        
        while GetGameTimer() - startTime < duration do
            local progress = (GetGameTimer() - startTime) / duration
            local progressPercent = math.floor(progress * 100)
            
            -- Show progress in chat every 25%
            if progressPercent >= lastProgressUpdate + 25 and progressPercent <= 100 then
                lastProgressUpdate = progressPercent
                TriggerEvent('chat:addMessage', {
                    color = { 0, 255, 0 },
                    args = { "Animation Test", progressPercent .. "% complete" }
                })
            end
            
            Citizen.Wait(100)
        end
        
        -- Cleanup
        ClearPedTasks(playerPed)
        StopWoodChoppingEffects()
        PlayChoppingSound("completion")
        
        TriggerEvent('chat:addMessage', {
            color = { 0, 255, 0 },
            args = { "Animation Test", "Test completed! Animation: " .. (usedScenario or "NONE") }
        })
    end)
end)

-- Admin command to test specific animation scenarios
RegisterCommand('testscenario', function(source, args, rawCommand)
    if not args[1] then
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 100 },
            args = { "Scenario Test", "Usage: /testscenario [scenario_name] [duration_ms]" }
        })
        return
    end
    
    local scenario = args[1]
    local duration = tonumber(args[2]) or 5000
    local playerPed = PlayerPedId()
    
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 255 },
        args = { "Scenario Test", "Testing scenario: " .. scenario }
    })
    
    -- Clear existing tasks
    ClearPedTasks(playerPed)
    
    -- Try to start the scenario
    local success = pcall(function()
        TaskStartScenarioInPlace(playerPed, scenario, -1, true)
    end)
    
    if success then
        Citizen.Wait(500) -- Wait to see if it actually starts
        
        if IsPedUsingScenario(playerPed, scenario) then
            TriggerEvent('chat:addMessage', {
                color = { 0, 255, 0 },
                args = { "Scenario Test", "✓ Scenario started successfully!" }
            })
            
            -- Run for duration then clean up
            Citizen.CreateThread(function()
                Citizen.Wait(duration)
                ClearPedTasks(playerPed)
                TriggerEvent('chat:addMessage', {
                    color = { 0, 255, 0 },
                    args = { "Scenario Test", "Test completed" }
                })
            end)
        else
            TriggerEvent('chat:addMessage', {
                color = { 255, 100, 100 },
                args = { "Scenario Test", "✗ Scenario failed to start (not active)" }
            })
        end
    else
        TriggerEvent('chat:addMessage', {
            color = { 255, 100, 100 },
            args = { "Scenario Test", "✗ Scenario failed to start (invalid)" }
        })
    end
end)

-- List available animation scenarios
RegisterCommand('listscenarios', function(source, args, rawCommand)
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 255 },
        args = { "Available Scenarios", "Chopping animation fallbacks:" }
    })
    
    for i, scenario in ipairs(AtlasWoodConfig.Animations.scenarios) do
        TriggerEvent('chat:addMessage', {
            color = { 255, 255, 255 },
            args = { "Scenario " .. i, scenario }
        })
    end
    
    TriggerEvent('chat:addMessage', {
        color = { 255, 255, 0 },
        args = { "Usage", "/testscenario [scenario_name] [duration_ms]" }
    })
end)

RegisterNetEvent('atlas_woodcutting:client:beginMinigame')
AddEventHandler('atlas_woodcutting:client:beginMinigame', function(token)
    print("^2[CHOP FLOW]^7 beginMinigame [CLIENT] - Token: " .. token)
    print("^2[CHOP FLOW]^7 Setting isBusy = true")
    isBusy = true
    isChopping = true
    choppingProgress = 0.0

    local playerPed = PlayerPedId()
    local startCoords = GetEntityCoords(playerPed)
    local startHealth = GetEntityHealth(playerPed)
    local startTime = GetGameTimer()
    local duration = AtlasWoodConfig.ChopAnimationTime
    local interrupted = false
    local interruptReason = nil

    -- Enhanced Animation System - Start animation with fallbacks
    print("^2[CHOP FLOW]^7 Starting enhanced chopping animation...")
    local animationStarted, usedScenario = StartChoppingAnimation(playerPed)
    
    if animationStarted then
        print("^2[CHOP FLOW]^7 Animation started successfully: " .. usedScenario)
    else
        print("^3[CHOP FLOW]^7 Animation failed to start - continuing without animation")
    end
    
    -- Start visual and audio effects
    StartWoodChoppingEffects(playerPed)
    PlayChoppingSound("chop")

    -- Enhanced Progress thread with comprehensive interruption checking
    Citizen.CreateThread(function()
        print("^2[CHOP FLOW]^7 Starting enhanced progress thread - Duration: " .. duration .. "ms")
        
        while GetGameTimer() - startTime < duration and not interrupted do
            local currentTime = GetGameTimer()
            choppingProgress = math.min((currentTime - startTime) / duration, 1.0)
            
            -- Debug: Print progress every second
            local elapsedTime = currentTime - startTime
            if elapsedTime % 1000 < 100 then -- Every ~1 second
                print("^3[PROGRESS DEBUG]^7 " .. math.floor(choppingProgress * 100) .. "% (" .. math.floor(elapsedTime) .. "ms / " .. duration .. "ms)")
                print("^3[PROGRESS DEBUG]^7 Animation: " .. (currentAnimationScenario or "NONE") .. " | Effects: " .. tostring(animationEffectsActive))
            end
            
            -- Enhanced interruption checking
            local isInterrupted, reason = CheckAnimationInterruption(playerPed, startCoords, startHealth)
            if isInterrupted then
                interrupted = true
                interruptReason = reason
                break
            end
            
            Citizen.Wait(AtlasWoodConfig.Animations.interruption.checkInterval) -- Configurable check interval
        end
        
        -- Enhanced Cleanup
        isChopping = false
        choppingProgress = 0.0
        currentAnimationScenario = nil
        
        -- Stop all effects
        StopWoodChoppingEffects()
        ClearPedTasks(playerPed)
        
        print("^2[CHOP FLOW]^7 Progress complete - Interrupted: " .. tostring(interrupted))
        if interrupted and interruptReason then
            print("^1[CHOP FLOW]^7 Interruption reason: " .. interruptReason)
        end
        
        if interrupted then
            print("^1[CHOP FLOW]^7 Chopping interrupted!")
            PlayChoppingSound("interruption")
            isBusy = false
            
            -- Provide user feedback based on interruption reason
            if interruptReason == "movement" then
                TriggerEvent('chat:addMessage', {
                    color = { 255, 100, 100 },
                    args = { "Woodcutting", "You moved too far from the tree!" }
                })
            elseif interruptReason == "damage" then
                TriggerEvent('chat:addMessage', {
                    color = { 255, 100, 100 },
                    args = { "Woodcutting", "You were injured and stopped chopping!" }
                })
            elseif interruptReason == "combat" then
                TriggerEvent('chat:addMessage', {
                    color = { 255, 100, 100 },
                    args = { "Woodcutting", "Combat interrupted your work!" }
                })
            end
        else
            print("^2[CHOP FLOW]^7 Sending finishChop to server")
            PlayChoppingSound("completion")
            isBusy = false
            TriggerServerEvent('atlas_woodcutting:server:finishChop', token)
        end
    end)
end)
