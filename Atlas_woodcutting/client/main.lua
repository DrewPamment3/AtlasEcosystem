local isBusy = false
local LocalTrees = {}
local debugMode = true

-- [[ UI DRAWING ]]

local function DrawWoodcuttingPrompt()
    -- Moved to 0.5, 0.5 (Middle of Screen) to rule out HUD cutoff
    local screenX, screenY = 0.5, 0.5

    -- Background Box
    DrawRect(screenX, screenY, 0.15, 0.045, 0, 0, 0, 180)

    -- The "G" Button Look
    SetTextScale(0.38, 0.38)
    SetTextColor(0, 0, 0, 255)
    SetTextCentre(true)
    local gButton = CreateVarString(10, "LITERAL_STRING", "G")
    DrawRect(screenX - 0.035, screenY, 0.02, 0.03, 255, 255, 255, 255)
    DisplayText(gButton, screenX - 0.035, screenY - 0.015)

    -- The Action Text
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(false)
    SetTextFontForCurrentCommand(1)
    local promptText = CreateVarString(10, "LITERAL_STRING", "CHOP TREE")
    DisplayText(promptText, screenX - 0.015, screenY - 0.015)
end

-- [[ INTERACTION LOOP ]]

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        -- Start at chest height, shoot 3.5m forward (longer range for testing)
        local start = pCoords + vec3(0, 0, 1.2)
        local target = pCoords + (pForward * 3.5) + vec3(0, 0, 1.2)

        if debugMode then
            DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)
        end

        -- Mask -1 catches everything (Peds, Vehicles, Map, Props)
        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, -1, playerPed, 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        if hit == 1 and entityHit ~= 0 then
            if LocalTrees[entityHit] then
                DrawWoodcuttingPrompt()

                -- LOGGING: If this prints, the UI IS being called
                if GetGameTimer() % 1000 == 0 then
                    print("^2[Atlas Debug]^7 Interaction Active for Entity: " .. entityHit)
                end

                if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', GetEntityCoords(entityHit))
                end
            elseif debugMode and GetGameTimer() % 2000 == 0 then
                -- Check if we are hitting the floor or a different prop
                local model = GetEntityModel(entityHit)
                print("^3[Atlas Debug]^7 Ray hit Entity: " ..
                entityHit .. " | Model: " .. model .. " | Status: NOT IN TABLE")
            end
        end
    end
end)

-- [[ SPAWNING & SYNC ]]

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

    LocalTrees[tree] = node.forest_id
    SetModelAsNoLongerNeeded(modelHash)
end

RegisterNetEvent('Atlas_Woodcutting:Client:SyncNodes')
AddEventHandler('Atlas_Woodcutting:Client:SyncNodes', function(nodes)
    for entity, _ in pairs(LocalTrees) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    LocalTrees = {}
    for _, node in ipairs(nodes) do SpawnLocalTree(node) end
end)

RegisterNetEvent('Atlas_Woodcutting:Client:SpawnSingleNode')
AddEventHandler('Atlas_Woodcutting:Client:SpawnSingleNode', function(node)
    SpawnLocalTree(node)
end)

RegisterNetEvent('Atlas_Woodcutting:Client:WipeSpecificForest')
AddEventHandler('Atlas_Woodcutting:Client:WipeSpecificForest', function(forestId)
    for entity, fId in pairs(LocalTrees) do
        if fId == forestId then
            if DoesEntityExist(entity) then DeleteEntity(entity) end
            LocalTrees[entity] = nil
        end
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
end)

RegisterNetEvent('Atlas_Woodcutting:Client:GenerateForestNodes')
AddEventHandler('Atlas_Woodcutting:Client:GenerateForestNodes', function(forestId, center, radius, count, modelName)
    for i = 1, count do
        local angle, r = math.random() * 2 * math.pi, radius * math.sqrt(math.random())
        local x, y = center.x + r * math.cos(angle)
        local y = center.y + r * math.sin(angle)
        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)
        if foundGround then
            TriggerServerEvent('Atlas_Woodcutting:Server:SaveNode', forestId, vec3(x, y, groundZ), modelName)
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

RegisterCommand('debugtrees', function()
    print("^3[Atlas Debug]^7 CURRENT LOCAL ENTITIES:")
    local count = 0
    for handle, fId in pairs(LocalTrees) do
        count = count + 1
        print(string.format("  - Entity: %s | Forest: %s | Exists: %s", handle, fId, DoesEntityExist(handle)))
    end
    print("^3[Atlas Debug]^7 Total: " .. count)
end)
