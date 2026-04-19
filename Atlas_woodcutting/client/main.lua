local isBusy = false
local LocalTrees = {}  -- [entityHandle] = forestId
local debugMode = true -- Set to false once the UI is confirmed working

-- [[ UI DRAWING ]]

local function DrawWoodcuttingPrompt()
    -- Background Box
    DrawRect(0.5, 0.91, 0.15, 0.045, 0, 0, 0, 180)

    -- The "G" Button Look
    SetTextScale(0.38, 0.38)
    SetTextColor(0, 0, 0, 255)
    SetTextCentre(true)
    local gButton = CreateVarString(10, "LITERAL_STRING", "G")
    DrawRect(0.465, 0.91, 0.02, 0.03, 255, 255, 255, 255)
    DisplayText(gButton, 0.465, 0.895)

    -- The Action Text
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(false)
    SetTextFontForCurrentCommand(1)
    local promptText = CreateVarString(10, "LITERAL_STRING", "CHOP TREE")
    DisplayText(promptText, 0.485, 0.895)
end

-- [[ SPAWNING LOGIC ]]

local function SpawnLocalTree(node)
    local modelHash = GetHashKey(node.model_name)

    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = 0
        while not HasModelLoaded(modelHash) and timeout < 100 do
            Citizen.Wait(10)
            timeout = timeout + 1
        end
    end

    if HasModelLoaded(modelHash) then
        local _, groundZ = GetGroundZFor_3dCoord(node.x, node.y, 1000.0, 0)

        -- -0.2m Burial to hide root gaps
        local tree = CreateObject(modelHash, node.x, node.y, groundZ - 0.2, false, false, false)

        -- Vertical growth + Random orientation
        local randomYaw = math.random(0, 360) + 0.0
        SetEntityRotation(tree, 0.0, 0.0, randomYaw, 2, true)

        FreezeEntityPosition(tree, true)
        SetEntityAsMissionEntity(tree, true, true)

        LocalTrees[tree] = node.forest_id
        if debugMode then print("^3[Atlas Debug]^7 Spawned " .. node.model_name .. " (Handle: " .. tree .. ")") end
        SetModelAsNoLongerNeeded(modelHash)
    end
end

-- [[ EVENTS & SYNC ]]

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

-- [[ DEBUG COMMAND ]]

RegisterCommand('debugtrees', function()
    print("^3[Atlas Debug]^7 CURRENT LOCAL ENTITIES:")
    local count = 0
    for handle, fId in pairs(LocalTrees) do
        count = count + 1
        print(string.format("  - Entity: %s | Forest: %s | Exists: %s", handle, fId, DoesEntityExist(handle)))
    end
    print("^3[Atlas Debug]^7 Total: " .. count)
end)

-- [[ INTERACTION LOOP ]]

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        local start = pCoords + vec3(0, 0, 1.0)
        local target = pCoords + (pForward * 2.5) + vec3(0, 0, 1.0)

        -- Visualize the "eyes" of the script
        if debugMode then
            DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)
        end

        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 16, playerPed, 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        if hit == 1 and entityHit ~= 0 then
            if LocalTrees[entityHit] then
                DrawWoodcuttingPrompt()
                if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', GetEntityCoords(entityHit))
                end
            end
        end
    end
end)

-- [[ GENERATION ]]

RegisterNetEvent('Atlas_Woodcutting:Client:GenerateForestNodes')
AddEventHandler('Atlas_Woodcutting:Client:GenerateForestNodes', function(forestId, center, radius, count, modelName)
    for i = 1, count do
        local angle = math.random() * 2 * math.pi
        local r = radius * math.sqrt(math.random())
        local x = center.x + r * math.cos(angle)
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
