local isBusy = false
local GroveRegistry = {}   -- {forestId, treeIndex, coords, entity (tree or stump), isStump}
local RenderedForests = {} -- Forests currently being rendered
local TreeStumpMap = {}    -- Map of treeIndex -> stump entity for quick lookup

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

    -- Progress text
    SetTextScale(0.4, 0.4)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextFontForCurrentCommand(1)
    local progressText = "Chopping... " .. math.floor(progress * 100) .. "%"
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
                    print("^2[INTERACTION DEBUG]^7 Forest: " ..
                    matchedNode.forestId .. " | Tree: " .. matchedNode.treeIndex)
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

-- [[ ANIMATION DISCOVERY COMMAND ]]
-- Tests LOTS of potential RDR2 animation dicts & scenarios to find working ones
RegisterCommand('findanims', function(source, args, rawCommand)
    local ped = PlayerPedId()
    print("^2[ANIM FIND]^7 ========================================")
    print("^2[ANIM FIND]^7 Searching for working animations...")
    print("^2[ANIM FIND]^7 ========================================")

    -- === PART 1: Test animation dictionaries (TaskPlayAnim) ===
    local animDictsToTest = {
        -- RDR2 melee dicts
        {"melee@hatchet@streamed_core", "attack_high_left"},
        {"melee@hatchet@streamed", "attack_high_left"},
        {"melee@knife@streamed_core", "attack_high_left"},
        {"melee@unarmed@streamed_core", "heavyattack_forward_b"},
        {"melee_hatchet", "attack_high_left_slash"},
        {"melee_knife@", "slash_right"},
        -- GTA V style
        {"melee@hatchet@streamed_core", "attack_high_left_slash"},
        {"melee@large_wpn@streamed_core", "attack_high_left_slash"},
        -- RDR2 ambient/tool
        {"amb_custom@world_human_tree_chop@male_a@base", "chop_loop"},
        {"amb_custom@world_human_tree_chop@male_a@base", "chop"},
        {"amb_custom@world_human_tree_chop@male_a", "chop"},
        {"amb_work@world_human_tree_chop@male_a@base", "chop_loop"},
        {"amb_work@world_human_tree_chop@male_a@idle_a", "chop_loop"},
        {"amb_work@world_human_hammer@male_a@base", "hammer_loop"},
        -- script_mechanics
        {"script_mechanics@axe@", "chop"},
        {"script_mechanics@axe", "chop"},
        -- Generic RDR2 dicts  
        {"script_common@jail_break@", "chop_wood"},
    }

    local foundDicts = {}
    for _, entry in ipairs(animDictsToTest) do
        local dict = entry[1]
        local anim = entry[2]
        
        if not HasAnimDictLoaded(dict) then
            RequestAnimDict(dict)
            local timeout = GetGameTimer() + 2000
            while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
                Citizen.Wait(5)
            end
        end
        
        if HasAnimDictLoaded(dict) and not foundDicts[dict] then
            foundDicts[dict] = true
            print("^2[ANIM FIND]^7 ✓ Dict EXISTS: " .. dict)
            
            -- Now test if the specific animation exists within it
            ClearPedTasks(ped)
            Citizen.Wait(50)
            pcall(function()
                TaskPlayAnim(ped, dict, anim, 2.0, -2.0, 3000, 49, 0, false, false, false)
            end)
            Citizen.Wait(300)
            local playing = IsEntityPlayingAnim(ped, dict, anim, 3)
            if playing then
                print("^2[ANIM FIND]^7   ✓ Anim WORKS: " .. anim .. " (visible!)")
            else
                print("^3[ANIM FIND]^7   ~ Anim '" .. anim .. "' not found in dict (dict loads but anim name may differ)")
            end
            ClearPedTasks(ped)
        end
        
        RemoveAnimDict(dict)
        Citizen.Wait(50)
    end

    -- === PART 2: Test scenarios (TaskStartScenarioInPlace) ===
    print("^2[ANIM FIND]^7 --- Testing scenarios ---")
    local scenariosToTest = {
        "WORLD_HUMAN_TREE_CHOP",
        "WORLD_HUMAN_CHOP_WOOD",
        "PROP_HUMAN_TREE_CHOP",
        "WORLD_HUMAN_HAMMER",
        "WORLD_HUMAN_GARDENER_PLANT",
        "WORLD_HUMAN_CROUCH_INSPECT",
        "WORLD_HUMAN_STAND_IMPATIENT",
        "WORLD_HUMAN_DRINKING",
        "WORLD_HUMAN_SMOKING",
        "WORLD_HUMAN_GUARD_STAND",
        "PROP_HUMAN_SEAT_CHAIR",
        "WORLD_HUMAN_LEANING",
        "WORLD_HUMAN_BROOM",
        "WORLD_HUMAN_SHOVEL",
        "WORLD_HUMAN_PICKAXE",
        "WORLD_HUMAN_AXE",
    }

    for _, scenario in ipairs(scenariosToTest) do
        ClearPedTasks(ped)
        Citizen.Wait(50)
        pcall(function()
            TaskStartScenarioInPlace(ped, GetHashKey(scenario), 2000, true, false, false, false)
        end)
        Citizen.Wait(300)
        local active = pcall(function() return IsPedActiveInScenario(ped) end)
        local still = IsPedStill(ped)
        if active then
            print("^2[ANIM FIND]^7 ✓ Scenario ACTIVE: " .. scenario .. " | IsPedStill=" .. tostring(still))
        end
        ClearPedTasks(ped)
        Citizen.Wait(50)
    end

    -- === PART 3: Brute-force anim names in the 2 confirmed dicts ===
    print("^2[ANIM FIND]^7 --- Brute-forcing anim names in confirmed dicts ---")
    local dictsWithNames = {
        {"amb_work@world_human_tree_chop@male_a@base", 
            {"base", "idle", "idle_a", "idle_b", "idle_c", "work", "action", "chop", "chop_loop", "chop_a", "chop_b", 
             "chop_idle", "chop_tree", "tree_chop", "loop", "male", "chop_wood", "chop_axe", "swing_axe", "hit_tree",
             "worker_a", "base_chop", "base_loop", "idle_loop", "work_loop", "action_a", "action_b"}},
        {"amb_work@world_human_tree_chop@male_a@idle_a",
            {"idle_a", "idle", "idle_b", "base", "chop", "work", "loop", "action", "idle_loop", "chop_idle", "idle_chop"}},
    }
    
    for _, dictData in ipairs(dictsWithNames) do
        local dict = dictData[1]
        local names = dictData[2]
        
        if not HasAnimDictLoaded(dict) then
            RequestAnimDict(dict)
            local timeout = GetGameTimer() + 2000
            while not HasAnimDictLoaded(dict) and GetGameTimer() < timeout do
                Citizen.Wait(5)
            end
        end
        
        if HasAnimDictLoaded(dict) then
            print("^2[ANIM FIND]^7 Testing names in: " .. dict)
            for _, name in ipairs(names) do
                ClearPedTasks(ped)
                Citizen.Wait(30)
                -- Try with different flags: 1=loop, 49=upperbody+hold
                local success = pcall(function()
                    TaskPlayAnim(ped, dict, name, 1.0, -1.0, 3000, 1, 0, false, false, false)
                end)
                Citizen.Wait(200)
                local playing = IsEntityPlayingAnim(ped, dict, name, 3)
                if playing then
                    print("^2[ANIM FIND]^7   ✓✓ WORKS: '" .. name .. "' — THIS ONE PLAYS!")
                end
                ClearPedTasks(ped)
            end
        end
    end
    
    -- Also try DoesAnimDictExist on a broader set
    print("^2[ANIM FIND]^7 --- Broad DoesAnimDictExist check ---")
    local broadDicts = {
        "amb_work@world_human_tree_chop@male_a@base",
        "amb_work@world_human_tree_chop@male_a@idle_a",
        "amb_work@world_human_tree_chop@male_a",
        "amb_work@world_human_axe@male_a@base",
        "amb_work@world_human_axe@male_a",
        "amb_work@world_human_pickaxe@male_a@base",
        "amb_work@world_human_hammer@male_a@base",
        "amb_work@world_human_hammer@male_a",
        "amb_work@world_human_shovel@male_a@base",
        "melee@hatchet@streamed_core",
        "melee@knife@streamed_core",
        "melee@unarmed@streamed_core",
        "script_mechanics@axe@",
    }
    for _, d in ipairs(broadDicts) do
        local exists = DoesAnimDictExist(d)
        if exists then
            print("^2[ANIM FIND]^7 ✓ Dict: " .. d)
        end
    end

    print("^2[ANIM FIND]^7 ========================================")
    print("^2[ANIM FIND]^7 Search complete. Look for ✓✓ above.")
    print("^2[ANIM FIND]^7 ========================================")
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





RegisterNetEvent('atlas_woodcutting:client:beginMinigame')
AddEventHandler('atlas_woodcutting:client:beginMinigame', function(token)
    print("^2[CHOP FLOW]^7 beginMinigame [CLIENT] - Token: " .. token)
    print("^2[CHOP FLOW]^7 Setting isBusy = true")
    isBusy = true
    isChopping = true
    choppingProgress = 0.0

    local playerPed = PlayerPedId()
    local startCoords = GetEntityCoords(playerPed)
    local startTime = GetGameTimer()
    local duration = AtlasWoodConfig.ChopAnimationTime
    local interrupted = false

    -- Store ped handle locally for the progress thread
    local playerPedLocal = playerPed
    local startCoordsLocal = startCoords

    -- Use TaskPlayAnim with a known-working animation dict (standard approach, NOT scenario)
    -- melee_hatchet or melee_knife@ are reliable across RedM builds
    print("^2[CHOP FLOW]^7 Starting chopping animation via TaskPlayAnim...")
    
    local animDict = nil
    local animName = nil
    local primaryDict = "melee_hatchet"
    local primaryAnim = "attack_high_left_slash"
    local fallbackDict = "melee_knife@"
    local fallbackAnim = "slash_right"
    
    -- Try primary dict first, fall back to secondary
    if not HasAnimDictLoaded(primaryDict) then
        RequestAnimDict(primaryDict)
        local timeout = GetGameTimer() + 3000
        while not HasAnimDictLoaded(primaryDict) and GetGameTimer() < timeout do
            Citizen.Wait(10)
        end
    end
    
    if HasAnimDictLoaded(primaryDict) then
        animDict = primaryDict
        animName = primaryAnim
        ClearPedTasks(playerPedLocal)
        Citizen.Wait(50)
        TaskPlayAnim(playerPedLocal, animDict, animName, 4.0, -4.0, duration, 49, 0, false, false, false)
        print("^2[CHOP FLOW]^7 ✓ Animation started (" .. animDict .. "/" .. animName .. ")")
    elseif not HasAnimDictLoaded(fallbackDict) then
        RequestAnimDict(fallbackDict)
        local timeout = GetGameTimer() + 3000
        while not HasAnimDictLoaded(fallbackDict) and GetGameTimer() < timeout do
            Citizen.Wait(10)
        end
    end
    
    if not animDict and HasAnimDictLoaded(fallbackDict) then
        animDict = fallbackDict
        animName = fallbackAnim
        ClearPedTasks(playerPedLocal)
        Citizen.Wait(50)
        TaskPlayAnim(playerPedLocal, animDict, animName, 3.0, -3.0, duration, 49, 0, false, false, false)
        print("^2[CHOP FLOW]^7 ✓ Animation started (fallback: " .. animDict .. "/" .. animName .. ")")
    end
    
    if not animDict then
        print("^1[CHOP FLOW]^7 ⚠ No animation dicts available, proceeding without animation")
    end

    -- Progress thread
    Citizen.CreateThread(function()
        print("^2[CHOP FLOW]^7 Starting progress thread - Duration: " .. duration .. "ms")

        local lastScenarioCheck = GetGameTimer()
        while GetGameTimer() - startTime < duration and not interrupted do
            local currentTime = GetGameTimer()
            local elapsed = currentTime - startTime
            choppingProgress = math.min(elapsed / duration, 1.0)

            -- Debug: Print progress every second
            if elapsed % 1000 < 100 then
                print("^3[PROGRESS DEBUG]^7 " ..
                math.floor(choppingProgress * 100) .. "% (" .. math.floor(elapsed) .. "ms / " .. duration .. "ms)")
            end

            -- Re-apply scenario every 2 seconds if it dropped (RedM scenario fragility workaround)
            if currentTime - lastScenarioCheck > 2000 then
                local stillActive = pcall(function() return IsPedActiveInScenario(playerPedLocal) end)
                if not stillActive and not interrupted then
                    print("^3[CHOP FLOW]^7 Scenario dropped, re-applying...")
                    TaskStartScenarioInPlace(playerPedLocal, GetHashKey("WORLD_HUMAN_TREE_CHOP"), duration - elapsed, false)
                end
                lastScenarioCheck = currentTime
            end

            -- Check for movement interruption
            local currentCoords = GetEntityCoords(playerPedLocal)
            local distance = #(startCoordsLocal - currentCoords)

            if distance > 2.0 then
                print("^1[CHOP FLOW]^7 Interrupted - Player moved too far (" .. string.format("%.1f", distance) .. "m)")
                interrupted = true
                break
            end

            Citizen.Wait(100)
        end

        -- Cleanup
        isChopping = false
        choppingProgress = 0.0
        print("^2[CHOP FLOW]^7 Progress complete - Interrupted: " .. tostring(interrupted))
        if animDict then
            StopAnimTask(playerPedLocal, animDict, animName, 1.0)
        end
        ClearPedTasks(playerPedLocal)

        if interrupted then
            print("^1[CHOP FLOW]^7 Chopping interrupted!")
            isBusy = false
        else
            print("^2[CHOP FLOW]^7 Sending finishChop to server")
            isBusy = false
            TriggerServerEvent('atlas_woodcutting:server:finishChop', token)
        end
    end)
end)
