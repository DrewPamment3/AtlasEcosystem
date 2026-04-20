local isBusy = false
local GroveRegistry = {}              -- {forestId, treeIndex, coords, entity (tree or stump), isStump}
local RenderedForests = {}            -- Forests currently being rendered
local TreeStumpMap = {}               -- Map of treeIndex -> stump entity for quick lookup

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
    local tree = CreateObject(modelHash, node.x, node.y, groundZ - 0.2, false, false, false)
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
                    print("^2[Atlas Debug]^7 SUCCESS: Interaction for Forest " .. matchedNode.forestId .. " | Tree " .. matchedNode.treeIndex)
                    TriggerServerEvent('atlas_woodcutting:server:requestStart', entCoords, matchedNode.forestId, matchedNode.treeIndex, {
                        x = matchedNode.coords.x,
                        y = matchedNode.coords.y,
                        z = matchedNode.coords.z
                    })
                end
            end
        end
    end
end)

-- [[ UTILITY ]]
RegisterCommand('debugtrees', function()
    print("^3[Atlas Debug]^7 Total in Registry: " .. #GroveRegistry)
    for i, node in ipairs(GroveRegistry) do
        print(string.format("Node %s: Forest %s | Tree %s | Entity %s | IsStump %s", i, node.forestId, node.treeIndex, tostring(node.entity), tostring(node.isStump)))
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
    -- Find and delete the tree entity
    for i = #GroveRegistry, 1, -1 do
        if GroveRegistry[i].forestId == forestId and GroveRegistry[i].treeIndex == treeIndex and not GroveRegistry[i].isStump then
            if DoesEntityExist(GroveRegistry[i].entity) then
                DeleteEntity(GroveRegistry[i].entity)
            end
            table.remove(GroveRegistry, i)
            break
        end
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
    -- Spawn a single new tree when a node is added to a forest we're tracking
    if RenderedForests[forestId] then
        local treeIndex = 0
        -- Count existing trees for this forest to get the new index
        for _, registryNode in ipairs(GroveRegistry) do
            if registryNode.forestId == forestId and not registryNode.isStump then
                treeIndex = treeIndex + 1
            end
        end
        treeIndex = treeIndex + 1
        
        SpawnLocalTree(node, forestId, treeIndex, false)
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('atlas_woodcutting:server:playerLoaded')
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
    isBusy = true
    TaskStartScenarioInPlace(PlayerPedId(), `WORLD_HUMAN_TREE_CHOP`, -1, true)
    Citizen.Wait(AtlasWoodConfig.ChopAnimationTime)
    ClearPedTasks(PlayerPedId())
    isBusy = false
    TriggerServerEvent('atlas_woodcutting:server:finishChop', token)
end)
