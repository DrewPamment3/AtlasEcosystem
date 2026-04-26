local isBusy = false
local GroveRegistry = {}   -- {forestId, treeIndex, coords, entity (tree or stump), isStump}
local RenderedForests = {} -- Forests currently being rendered
local TreeStumpMap = {}    -- Map of treeIndex -> stump entity for quick lookup

-- VORP Lumberjack-style animation variables
local tool, hastool = nil, false
local swing = 0
local active = false
local UsePrompt, PropPrompt

-- Progress bar state
local isChopping = false
local choppingProgress = 0.0

-- Enhanced progress bar with animation status (from ANIMATION_SYSTEM.md)
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

    -- Enhanced progress text with animation status indicator
    SetTextScale(0.4, 0.4)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextFontForCurrentCommand(1)
    
    -- Animation status indicator (like ANIMATION_SYSTEM.md)
    local animationIndicator = "✓" -- Assume animation is working
    if not hastool then
        animationIndicator = "⚠" -- Warning if no tool equipped
    end
    
    local progressText = animationIndicator .. " Chopping... " .. math.floor(progress * 100) .. "%"
    if swing > 0 then
        progressText = animationIndicator .. " Swing " .. swing .. " - " .. math.floor(progress * 100) .. "%"
    end
    
    DisplayText(CreateVarString(10, "LITERAL_STRING", progressText), x, y + 0.04)
end

-- Render thread for smooth progress bar
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        if isChopping then
            DrawProgressBar(choppingProgress)
        end
    end
end)

-- VORP Lumberjack-style Animation Functions (copied from VORP lumberjack)
local function Anim(actor, dict, body, duration, flags, introtiming, exittiming)
    CreateThread(function()
        RequestAnimDict(dict)
        local dur = duration or -1
        local flag = flags or 1
        local intro = tonumber(introtiming) or 1.0
        local exit = tonumber(exittiming) or 1.0
        local timeout = 5
        while (not HasAnimDictLoaded(dict) and timeout > 0) do
            timeout = timeout - 1
            if timeout == 0 then
                print("Animation Failed to Load")
            end
            Wait(300)
        end
        TaskPlayAnim(actor, dict, body, intro, exit, dur, flag, 1, false, 0, false, "", true)
    end)
end

local function releasePlayer()
    if PropPrompt then
        -- UiPromptSetEnabled(PropPrompt, false)
        -- UiPromptSetVisible(PropPrompt, false)
    end

    if UsePrompt then
        -- UiPromptSetEnabled(UsePrompt, false)
        -- UiPromptSetVisible(UsePrompt, false)
    end

    FreezeEntityPosition(PlayerPedId(), false)
end

local function removeToolFromPlayer()
    hastool = false

    if not tool then
        return
    end
    local ped = PlayerPedId()
    Citizen.InvokeNative(0xED00D72F81CF7278, tool, 1, 1)
    DeleteObject(tool)
    Citizen.InvokeNative(0x58F7DB5BD8FA2288, ped) -- Cancel Walk Style
    
    -- Add safety checks for these natives
    local success1 = pcall(function()
        ClearPedDesiredLocoForModel(ped)
    end)
    
    local success2 = pcall(function()
        ClearPedDesiredLocoMotionType(ped)
    end)
    
    if not success1 or not success2 then
        print("^3[Atlas Woodcutting]^7 Some loco natives failed (expected in some RedM builds)")
    end

    tool = nil
end

local function EquipTool(toolhash)
    hastool = false
    -- Citizen.InvokeNative(0x6A2F820452017EA2) -- Clear Prompts from Screen
    if tool then
        DeleteEntity(tool)
    end
    Wait(500)
    
    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0)
    tool = CreateObject(toolhash, coords.x, coords.y, coords.z, true, false, false, false)
    AttachEntityToEntity(tool, ped, GetPedBoneIndex(ped, 7966), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, false, false, false, false,
        2, true, false, false)
    Citizen.InvokeNative(0x923583741DC87BCE, ped, 'arthur_healthy')
    Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, "carry_pitchfork")
    Citizen.InvokeNative(0x2208438012482A1A, ped, true, true)
    ForceEntityAiAndAnimationUpdate(tool, true)
    Citizen.InvokeNative(0x3A50753042B6891B, ped, "PITCH_FORKS")

    Wait(500)
    hastool = true
end

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

-- List available animation scenarios (like VORP lumberjack system)
RegisterCommand('listscenarios', function()
    print("^2[Atlas Woodcutting]^7 Available Animation Scenarios (Priority Order):")
    print("^3================================================^7")
    for i, scenario in ipairs(AtlasWoodConfig.Animations.scenarios) do
        print("^2 " .. i .. ". ^7" .. scenario)
    end
    print("^3================================================^7")
    print("^3Usage:^7 /testanim scenario [name] [duration]")
end)

-- Test specific scenario directly (like VORP lumberjack system) 
RegisterCommand('testscenario', function(source, args, rawCommand)
    if not args[1] then
        print("^1[Atlas Woodcutting]^7 Usage: /testscenario [scenario_name] [duration_ms]")
        return
    end
    
    local scenarioName = args[1]
    local duration = tonumber(args[2]) or 5000
    local ped = PlayerPedId()
    
    print("^2[TEST SCENARIO]^7 Testing scenario: " .. scenarioName .. " for " .. duration .. "ms")
    
    ClearPedTasks(ped)
    Wait(50)
    
    TaskStartScenarioInPlace(ped, GetHashKey(scenarioName), -1, true, false, false, false)
    
    Citizen.SetTimeout(duration, function()
        ClearPedTasks(ped)
        print("^2[TEST SCENARIO]^7 Scenario test completed")
    end)
end)

-- Test complete chopping animation (like VORP lumberjack system)
RegisterCommand('testchopanimation', function(source, args, rawCommand)
    local duration = tonumber(args[1]) or 10000
    local ped = PlayerPedId()
    
    print("^2[TEST CHOP ANIMATION]^7 Testing complete chopping system for " .. duration .. "ms")
    
    -- Simulate the full chopping experience
    EquipTool(GetHashKey('p_axe02x'))
    TaskStartScenarioInPlace(ped, GetHashKey("WORLD_HUMAN_TREE_CHOP"), -1, true)
    
    -- Test swing animation after 2 seconds
    Citizen.SetTimeout(2000, function()
        if hastool then
            print("^3[TEST CHOP ANIMATION]^7 Testing swing animation...")
            Anim(ped, "amb_work@world_human_tree_chop_new@working@pre_swing@male_a@trans", "pre_swing_trans_after_swing", -1, 0)
        end
    end)
    
    -- Cleanup after duration
    Citizen.SetTimeout(duration, function()
        ClearPedTasks(ped)
        removeToolFromPlayer()
        releasePlayer()
        print("^2[TEST CHOP ANIMATION]^7 Complete animation test finished")
    end)
end)

-- [[ ANIMATION TEST ]]
-- Tests various animation approaches (enhanced version of original)
--   /testanim scenario <name> [duration]      -> Scenario only
--   /testanim dict <dict> <anim> [duration]   -> TaskPlayAnim
--   /testanim axe <model> [scenario] [dur]    -> Attach axe prop + scenario
RegisterCommand('testanim', function(source, args, rawCommand)
    local mode = args[1]
    local duration = tonumber(args[#args]) or 6000
    if type(duration) ~= "number" then duration = 6000 end
    local ped = PlayerPedId()

    if mode == "scenario" then
        local scenarioName = args[2]
        if not scenarioName then
            print("^1[TESTANIM]^7 Usage: /testanim scenario <name> [duration_ms]")
            return
        end
        print("^2[TESTANIM]^7 ========================================")
        print("^2[TESTANIM]^7 Scenario: " .. scenarioName)
        print("^2[TESTANIM]^7 Duration: " .. duration .. "ms")

        ClearPedTasks(ped)
        Citizen.Wait(50)
        
        print("^3[TESTANIM]^7 [1] Starting TaskStartScenarioInPlace...")
        TaskStartScenarioInPlace(ped, GetHashKey(scenarioName), -1, true, false, false, false)
        Citizen.Wait(200)
        
        local active = pcall(function() return IsPedActiveInScenario(ped) end)
        local still = IsPedStill(ped)
        print("^3[TESTANIM]^7     IsPedActiveInScenario: " .. tostring(active))
        print("^3[TESTANIM]^7     IsPedStill: " .. tostring(still))

        print("^3[TESTANIM]^7 [2] Running " .. duration .. "ms...")
        Citizen.Wait(duration)
        ClearPedTasks(ped)
        print("^2[TESTANIM]^7 Done.")
        print("^2[TESTANIM]^7 ========================================")

    elseif mode == "dict" then
        local dict = args[2]
        local anim = args[3]
        if not dict or not anim then
            print("^1[TESTANIM]^7 Usage: /testanim dict <dict> <anim> [duration_ms]")
            return
        end
        print("^2[TESTANIM]^7 ========================================")
        print("^2[TESTANIM]^7 Dict:     " .. dict)
        print("^2[TESTANIM]^7 Anim:     " .. anim)
        print("^2[TESTANIM]^7 Duration: " .. duration .. "ms")

        ClearPedTasks(ped)
        Citizen.Wait(50)

        print("^3[TESTANIM]^7 [1] DoesAnimDictExist: " .. tostring(DoesAnimDictExist(dict)))
        print("^3[TESTANIM]^7 [2] Loading dict...")
        RequestAnimDict(dict)
        local t = GetGameTimer()
        while not HasAnimDictLoaded(dict) do
            if GetGameTimer() - t > 5000 then
                print("^1[TESTANIM]^7     TIMEOUT")
                return
            end
            Citizen.Wait(0)
        end
        print("^2[TESTANIM]^7     Loaded in " .. (GetGameTimer() - t) .. "ms")

        print("^3[TESTANIM]^7 [3] Playing...")
        TaskPlayAnim(ped, dict, anim, 1.0, -1.0, duration, 1, 0, false, false, false)
        Citizen.Wait(150)
        print("^3[TESTANIM]^7     IsPlaying: " .. tostring(IsEntityPlayingAnim(ped, dict, anim, 3)))

        print("^3[TESTANIM]^7 [4] Running " .. duration .. "ms...")
        Citizen.Wait(duration)
        StopAnimTask(ped, dict, anim, 1.0)
        RemoveAnimDict(dict)
        ClearPedTasks(ped)
        print("^2[TESTANIM]^7 Done.")
        print("^2[TESTANIM]^7 ========================================")

    elseif mode == "axe" then
        local axeModel = args[2] or "p_axe01x"
        local scenarioName = args[3] or "WORLD_HUMAN_TREE_CHOP"
        local axeHash = GetHashKey(axeModel)

        print("^2[TESTANIM]^7 ========================================")
        print("^2[TESTANIM]^7 Axe:      " .. axeModel)
        print("^2[TESTANIM]^7 Scenario: " .. scenarioName)
        print("^2[TESTANIM]^7 Duration: " .. duration .. "ms")

        ClearPedTasks(ped)
        Citizen.Wait(50)

        -- Load and attach axe
        print("^3[TESTANIM]^7 [1] Loading axe model...")
        RequestModel(axeHash)
        local t = GetGameTimer()
        while not HasModelLoaded(axeHash) do
            if GetGameTimer() - t > 5000 then
                print("^1[TESTANIM]^7     TIMEOUT — model: " .. axeModel)
                return
            end
            Citizen.Wait(0)
        end
        print("^2[TESTANIM]^7     Loaded in " .. (GetGameTimer() - t) .. "ms")

        print("^3[TESTANIM]^7 [2] Creating & attaching axe to right hand...")
        local axeObj = CreateObject(axeHash, GetEntityCoords(ped), true, true, true)
        local boneIndex = GetEntityBoneIndexByName(ped, "PH_R_HAND")
        AttachEntityToEntity(axeObj, ped, boneIndex,
            0.0, 0.0, 0.0,   -- x, y, z offset
            0.0, 0.0, 0.0,   -- rotation x, y, z
            true, false, false, false, 2, true)

        -- Start scenario
        print("^3[TESTANIM]^7 [3] Starting scenario...")
        TaskStartScenarioInPlace(ped, GetHashKey(scenarioName), -1, true, false, false, false)
        Citizen.Wait(200)
        local active = pcall(function() return IsPedActiveInScenario(ped) end)
        print("^3[TESTANIM]^7     IsPedActiveInScenario: " .. tostring(active))

        print("^3[TESTANIM]^7 [4] Running " .. duration .. "ms...")
        Citizen.Wait(duration)

        -- Cleanup
        ClearPedTasks(ped)
        if DoesEntityExist(axeObj) then
            DeleteEntity(axeObj)
        end
        SetModelAsNoLongerNeeded(axeHash)
        print("^2[TESTANIM]^7 Done (axe deleted).")
        print("^2[TESTANIM]^7 ========================================")

    else
        print("^2[TESTANIM]^7 Usage:")
        print("^2[TESTANIM]^7   /testanim dict <dict> <anim> [duration]")
        print("^2[TESTANIM]^7   /testanim scenario <name> [duration]")
        print("^2[TESTANIM]^7   /testanim axe [model] [scenario] [duration]")
        print("^2[TESTANIM]^7 ")
        print("^2[TESTANIM]^7 Examples:")
        print("^2[TESTANIM]^7   /testanim dict amb_work@world_human_tree_chop@male_a@idle_a idle_b")
        print("^2[TESTANIM]^7   /testanim axe p_axe01x WORLD_HUMAN_TREE_CHOP 6000")
    end
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

-- Admin animation test event (triggered by server)
RegisterNetEvent('atlas_woodcutting:client:adminAnimTest')
AddEventHandler('atlas_woodcutting:client:adminAnimTest', function(duration)
    print("^2[ADMIN ANIM TEST]^7 Animation test triggered by admin for " .. duration .. "ms")
    
    local ped = PlayerPedId()
    
    -- Test the full VORP lumberjack animation system
    EquipTool(GetHashKey('p_axe02x'))
    
    -- Start tree chop scenario
    TaskStartScenarioInPlace(ped, GetHashKey("WORLD_HUMAN_TREE_CHOP"), -1, true)
    
    -- Test swing animation after a delay
    Citizen.SetTimeout(2000, function()
        if hastool then
            print("^3[ADMIN ANIM TEST]^7 Testing swing animation...")
            Anim(ped, "amb_work@world_human_tree_chop_new@working@pre_swing@male_a@trans", "pre_swing_trans_after_swing", -1, 0)
        end
    end)
    
    -- Cleanup after duration
    Citizen.SetTimeout(duration, function()
        ClearPedTasks(ped)
        removeToolFromPlayer()
        releasePlayer()
        print("^2[ADMIN ANIM TEST]^7 Admin animation test completed")
    end)
end)

-- Real-time configuration update event
RegisterNetEvent('atlas_woodcutting:client:updateConfig')
AddEventHandler('atlas_woodcutting:client:updateConfig', function(configKey, newValue)
    if configKey == 'ChopAnimationTime' then
        AtlasWoodConfig.ChopAnimationTime = newValue
        print("^2[CONFIG UPDATE]^7 ChopAnimationTime updated to " .. newValue .. "ms")
    elseif configKey == 'maxMovementDistance' then
        AtlasWoodConfig.Animations.interruption.maxMovementDistance = newValue
        print("^2[CONFIG UPDATE]^7 Max movement distance updated to " .. newValue .. "m")
    elseif configKey == 'checkInterval' then
        AtlasWoodConfig.Animations.interruption.checkInterval = newValue
        print("^2[CONFIG UPDATE]^7 Check interval updated to " .. newValue .. "ms")
    end
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

-- Enhanced Chopping System with Advanced Interruption Detection
RegisterNetEvent('atlas_woodcutting:client:beginMinigame')
AddEventHandler('atlas_woodcutting:client:beginMinigame', function(token)
    print("^2[CHOP FLOW]^7 beginMinigame [CLIENT] - Token: " .. token)
    print("^2[CHOP FLOW]^7 Setting isBusy = true")
    isBusy = true
    active = true
    isChopping = true
    choppingProgress = 0.0
    swing = 0

    local playerPed = PlayerPedId()
    local startCoords = GetEntityCoords(playerPed)
    local startTime = GetGameTimer()
    local duration = AtlasWoodConfig.ChopAnimationTime
    local interrupted = false

    -- Start VORP lumberjack-style chopping system
    print("^2[CHOP FLOW]^7 Starting VORP-style chopping animation...")
    
    -- Equip the axe tool (like VORP lumberjack)
    EquipTool(GetHashKey('p_axe02x'))
    
    -- Simulate the swinging system from VORP lumberjack
    local swingcount = math.random(3, 8) -- Random number of swings needed
    
    -- Enhanced interruption monitoring thread
    local lastSwingTime = 0
    local swingInProgress = false
    local playerStartHealth = GetEntityHealth(playerPed)
    local interruptionReason = nil
    
    Citizen.CreateThread(function()
        print("^2[CHOP FLOW]^7 Starting enhanced interruption monitoring...")
        
        while hastool and active and not interrupted do
            -- DON'T freeze player - let them move naturally and detect movement input
            -- FreezeEntityPosition(playerPed, true) -- Removed this line
            
            local currentTime = GetGameTimer()
            local currentCoords = GetEntityCoords(playerPed)
            local currentHealth = GetEntityHealth(playerPed)
            
            -- 1. MOVEMENT INPUT DETECTION (WASD keys)
            local movementDetected = false
            
            -- Check for movement input (all directional keys)
            if IsControlPressed(0, 0x8FD015D8) or  -- W (INPUT_MOVE_UP_ONLY)
               IsControlPressed(0, 0xD27782E3) or  -- S (INPUT_MOVE_DOWN_ONLY) 
               IsControlPressed(0, 0x7065027D) or  -- A (INPUT_MOVE_LEFT_ONLY)
               IsControlPressed(0, 0xB4E465B4) or  -- D (INPUT_MOVE_RIGHT_ONLY)
               IsControlPressed(0, 0x3D99EEC6) or  -- Left Stick Movement
               IsControlPressed(0, 0x0499D4A5) then -- Right Stick Movement
                movementDetected = true
                interruptionReason = "Movement input detected (player tried to move)"
            end
            
            -- 2. POSITION CHANGE DETECTION (backup method)
            local distance = #(startCoords - currentCoords)
            if distance > 1.0 then -- Much smaller threshold since we're not freezing
                movementDetected = true
                interruptionReason = "Player moved " .. string.format("%.1fm", distance) .. " from start position"
            end
            
            -- 3. HEALTH/DAMAGE DETECTION
            if currentHealth < playerStartHealth then
                interrupted = true
                interruptionReason = "Player took damage (health: " .. playerStartHealth .. " → " .. currentHealth .. ")"
                print("^1[CHOP FLOW]^7 Interrupted - " .. interruptionReason)
                break
            end
            
            -- 4. DEATH/DYING DETECTION
            if IsPedDeadOrDying(playerPed, false) then
                interrupted = true
                interruptionReason = "Player died or is dying"
                print("^1[CHOP FLOW]^7 Interrupted - " .. interruptionReason)
                break
            end
            
            -- 5. COMBAT DETECTION (if player enters combat)
            if IsPedInCombat(playerPed, 0) then
                interrupted = true
                interruptionReason = "Player entered combat"
                print("^1[CHOP FLOW]^7 Interrupted - " .. interruptionReason)
                break
            end
            
            -- 6. MOVEMENT INPUT INTERRUPTION
            if movementDetected then
                interrupted = true
                print("^1[CHOP FLOW]^7 Interrupted - " .. interruptionReason)
                break
            end
            
            -- 7. SWING PROGRESSION (only if not interrupted)
            if not swingInProgress and (currentTime - lastSwingTime) > (1500 + math.random(500, 1000)) then
                if swing < swingcount then
                    swingInProgress = true
                    swing = swing + 1
                    choppingProgress = swing / swingcount
                    
                    print("^3[CHOP FLOW]^7 Swing " .. swing .. "/" .. swingcount .. " (" .. math.floor(choppingProgress * 100) .. "%)")
                    
                    -- Play swing animation (like VORP lumberjack)
                    Anim(playerPed, "amb_work@world_human_tree_chop_new@working@pre_swing@male_a@trans", "pre_swing_trans_after_swing", -1, 0)
                    
                    lastSwingTime = currentTime
                    swingInProgress = false
                else
                    -- All swings completed
                    print("^2[CHOP FLOW]^7 All swings completed!")
                    break
                end
            end

            Wait(50) -- Check every 50ms for responsive interruption detection
        end

        -- Enhanced cleanup with interruption reason
        isChopping = false
        choppingProgress = 0.0
        active = false
        swing = 0
        
        print("^2[CHOP FLOW]^7 Progress complete - Interrupted: " .. tostring(interrupted))
        if interrupted and interruptionReason then
            print("^3[CHOP FLOW]^7 Interruption reason: " .. interruptionReason)
        end
        
        ClearPedTasks(playerPed)
        removeToolFromPlayer()
        releasePlayer()

        if interrupted then
            print("^1[CHOP FLOW]^7 Chopping interrupted!")
            -- Show interruption message to player
            if interruptionReason then
                -- You could add a notification here if you want:
                -- TriggerEvent('vorp:TipBottom', interruptionReason, 3000)
            end
            isBusy = false
        else
            print("^2[CHOP FLOW]^7 Sending finishChop to server")
            isBusy = false
            TriggerServerEvent('atlas_woodcutting:server:finishChop', token)
        end
    end)
end)
