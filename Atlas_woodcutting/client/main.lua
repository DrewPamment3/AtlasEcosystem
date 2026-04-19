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
        while not HasModelLoaded(modelHash) do Citizen.Wait(1) end
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

        -- UPDATED: Start at 0.9 (waist) and pull distance to 1.8m
        local start = pCoords + vec3(0, 0, 0.9)
        local target = pCoords + (pForward * 1.8) + vec3(0, 0, 0.9)

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
                if IsControlJustPressed(0, 0x760A9C6F) and not isBusy then
                    print("^2[Atlas Debug]^7 SUCCESS: Interaction for Forest " .. matchedNode.forest_id)
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', entCoords)
                end
            end
        end
    end
end)

-- [[ UTILITY ]]
RegisterCommand('debugtrees', function()
    print("^3[Atlas Debug]^7 Total in Registry: " .. #GroveRegistry)
    for i, node in ipairs(GroveRegistry) do
        print(string.format("Node %s: Forest %s | Entity %s", i, node.forest_id, node.entity))
    end
end)

-- [[ EVENTS ]]
RegisterNetEvent('Atlas_Woodcutting:Client:SyncNodes')
AddEventHandler('Atlas_Woodcutting:Client:SyncNodes', function(nodes)
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

RegisterNetEvent('Atlas_Woodcutting:Client:WipeSpecificForest')
AddEventHandler('Atlas_Woodcutting:Client:WipeSpecificForest', function(forestId)
    for i = #GroveRegistry, 1, -1 do
        if GroveRegistry[i].forest_id == forestId then
            if DoesEntityExist(GroveRegistry[i].entity) then DeleteEntity(GroveRegistry[i].entity) end
            table.remove(GroveRegistry, i)
        end
    end
end)

RegisterNetEvent('Atlas_Woodcutting:Client:SpawnSingleNode')
AddEventHandler('Atlas_Woodcutting:Client:SpawnSingleNode', function(node) SpawnLocalTree(node) end)

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
end)

RegisterNetEvent('Atlas_Woodcutting:Client:GenerateForestNodes')
AddEventHandler('Atlas_Woodcutting:Client:GenerateForestNodes', function(fId, center, radius, count, model)
    for i = 1, count do
        local angle, r = math.random() * 2 * math.pi, radius * math.sqrt(math.random())
        local x, y = center.x + r * math.cos(angle)
        local y = center.y + r * math.sin(angle)
        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)
        if foundGround then
            TriggerServerEvent('Atlas_Woodcutting:Server:SaveNode', fId, vec3(x, y, groundZ), model)
        end
        Citizen.Wait(300)
    end
end)

RegisterNetEvent('Atlas_Woodcutting:Client:BeginMinigame')
AddEventHandler('Atlas_Woodcutting:Client:BeginMinigame', function(token)
    isBusy = true
    TaskStartScenarioInPlace(PlayerPedId(), `WORLD_HUMAN_TREE_CHOP`, -1, true)
    Citizen.Wait(5000)
    ClearPedTasks(PlayerPedId())
    isBusy = false
    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token)
end)
