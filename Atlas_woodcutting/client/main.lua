local isBusy = false
local debugMode = true

-- [[ DECORATOR REGISTRATION ]]
-- 3 = Integer. We register this so the engine knows 'atlas_grove' is a valid data field.
Citizen.CreateThread(function()
    if not DecorIsRegisteredAtAll("atlas_grove") then
        DecorRegister("atlas_grove", 3)
    end
end)

-- [[ UI DRAWING ]]
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
    local actionText = CreateVarString(10, "LITERAL_STRING", "CHOP TREE")
    DisplayText(actionText, x - 0.018, y - 0.016)
end

-- [[ SPAWNING & TAGGING ]]
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

    -- DECORATOR SET: This is the hard-coded property you wanted
    DecorSetInt(tree, "atlas_grove", node.forest_id)

    if debugMode then print("^3[Atlas]^7 Tagged Entity " .. tree .. " with Grove ID " .. node.forest_id) end
    SetModelAsNoLongerNeeded(modelHash)
end

-- [[ INTERACTION LOOP ]]
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        local start = pCoords + vec3(0, 0, 1.2)
        local target = pCoords + (pForward * 3.0) + vec3(0, 0, 1.2)

        if debugMode then DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255) end

        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 255, playerPed, 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        -- 1. UI DRAWING
        if hit == 1 and entityHit ~= 0 then
            -- DecorExist Check
            if DecorExistOn(entityHit, "atlas_grove") then
                DrawWoodcuttingPrompt()
            end
        end

        -- 2. BUTTON LOGIC
        if IsControlJustPressed(0, 0x760A9C6F) then
            print("^3[Atlas Debug]^7 G Pressed. Hit: " .. hit .. " | Entity: " .. (entityHit or "0"))

            if hit == 1 and entityHit ~= 0 then
                local model = GetEntityModel(entityHit)
                -- DecorGet Check
                if DecorExistOn(entityHit, "atlas_grove") then
                    local groveId = DecorGetInt(entityHit, "atlas_grove")
                    print("^2[Atlas Debug]^7 SUCCESS: Entity has 'atlas_grove' tag. ID: " .. groveId)

                    if not isBusy then
                        TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', GetEntityCoords(entityHit))
                    end
                else
                    print("^1[Atlas Debug]^7 FAILED: Entity " ..
                    entityHit .. " (Model: " .. model .. ") has NO 'atlas_grove' tag.")
                end
            end
        end
    end
end)

-- [[ SYNC & CLEANUP ]]
RegisterNetEvent('Atlas_Woodcutting:Client:SyncNodes')
AddEventHandler('Atlas_Woodcutting:Client:SyncNodes', function(nodes)
    local objects = GetGamePool('CObject')
    for _, entity in ipairs(objects) do
        if DecorExistOn(entity, "atlas_grove") then DeleteEntity(entity) end
    end
    for _, node in ipairs(nodes) do SpawnLocalTree(node) end
end)

RegisterNetEvent('Atlas_Woodcutting:Client:WipeSpecificForest')
AddEventHandler('Atlas_Woodcutting:Client:WipeSpecificForest', function(forestId)
    local objects = GetGamePool('CObject')
    for _, entity in ipairs(objects) do
        if DecorExistOn(entity, "atlas_grove") and DecorGetInt(entity, "atlas_grove") == forestId then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteEntity(entity)
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
        local _, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)
        TriggerServerEvent('Atlas_Woodcutting:Server:SaveNode', fId, vec3(x, y, groundZ), model)
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
