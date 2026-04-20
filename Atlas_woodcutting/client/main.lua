local isBusy = false
local GroveRegistry = {}

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
local function SpawnLocalTree(node)
    local modelHash = GetHashKey(node.model_name)
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = GetGameTimer() + AtlasWoodConfig.ModelLoadTimeout
        while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
            Citizen.Wait(1)
        end

        if not HasModelLoaded(modelHash) then
            print("^1[Atlas Woodcutting]^7 Failed to load model " .. node.model_name .. " within timeout")
            return
        end
    end
    local _, groundZ = GetGroundZFor_3dCoord(node.x, node.y, 1000.0, 0)
    local tree = CreateObject(modelHash, node.x, node.y, groundZ - 0.2, false, false, false)
    SetEntityRotation(tree, 0.0, 0.0, math.random(0, 360) + 0.0, 2, true)
    FreezeEntityPosition(tree, true)
    SetEntityAsMissionEntity(tree, true, true)

    table.insert(GroveRegistry, {
        coords = vec3(node.x, node.y, node.z),
        forest_id = node.forest_id,
        entity = tree
    })
    SetModelAsNoLongerNeeded(modelHash)
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
                if #(entCoords - node.coords) < 1.5 then
                    matchedNode = node
                    break
                end
            end

            if matchedNode then
                DrawWoodcuttingPrompt()
                if IsControlJustPressed(0, AtlasWoodConfig.InteractionKey) and not isBusy then
                    print("^2[Atlas Debug]^7 SUCCESS: Interaction for Forest " .. matchedNode.forest_id)
                    TriggerServerEvent('atlas_woodcutting:server:requestStart', entCoords)
                end
            end
        end
    end
end)

-- [[ UTILITY ]]
RegisterCommand('debugtrees', function()
    print("^3[Atlas Debug]^7 Total in Registry: " .. #GroveRegistry)
    for i, node in ipairs(GroveRegistry) do
        print(string.format("Node %s: Forest %s | Entity %s", i, node.forest_id, tostring(node.entity)))
    end
end)

-- [[ EVENTS ]]
RegisterNetEvent('atlas_woodcutting:client:syncNodes')
AddEventHandler('atlas_woodcutting:client:syncNodes', function(nodes)
    local objects = GetGamePool('CObject')
    for _, entity in ipairs(objects) do
        local model = GetEntityModel(entity)
        if model == `p_tree_pine01x` or model == `p_tree_oak01x` or model == `p_pine_01` then
            DeleteEntity(entity)
        end
    end
    GroveRegistry = {}
    for _, node in ipairs(nodes) do SpawnLocalTree(node) end
end)

RegisterNetEvent('atlas_woodcutting:client:wipeSpecificForest')
AddEventHandler('atlas_woodcutting:client:wipeSpecificForest', function(forestId)
    for i = #GroveRegistry, 1, -1 do
        if GroveRegistry[i].forest_id == forestId then
            if DoesEntityExist(GroveRegistry[i].entity) then DeleteEntity(GroveRegistry[i].entity) end
            table.remove(GroveRegistry, i)
        end
    end
end)

RegisterNetEvent('atlas_woodcutting:client:spawnSingleNode')
AddEventHandler('atlas_woodcutting:client:spawnSingleNode', function(node) SpawnLocalTree(node) end)

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
