local isBusy = false
local LocalTreeEntities = {}

-- [[ NODE SYNC & SPAWNING ]]

local function SpawnLocalTree(node)
    local model = node.model_hash
    if not HasModelLoaded(model) then
        RequestModel(model)
        while not HasModelLoaded(model) do Citizen.Wait(1) end
    end

    local tree = CreateObject(model, node.x, node.y, node.z, false, false, false)
    FreezeEntityPosition(tree, true)
    SetEntityAsMissionEntity(tree, true, true)
    table.insert(LocalTreeEntities, tree)
    SetModelAsNoLongerNeeded(model)
end

RegisterNetEvent('Atlas_Woodcutting:Client:SyncNodes')
AddEventHandler('Atlas_Woodcutting:Client:SyncNodes', function(nodes)
    for _, node in ipairs(nodes) do SpawnLocalTree(node) end
end)

RegisterNetEvent('Atlas_Woodcutting:Client:SpawnSingleNode')
AddEventHandler('Atlas_Woodcutting:Client:SpawnSingleNode', function(node)
    SpawnLocalTree(node)
end)

-- Run this on startup/join
Citizen.CreateThread(function()
    TriggerServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
end)

-- [[ GENERATION ]]

RegisterNetEvent('Atlas_Woodcutting:Client:GenerateForestNodes')
AddEventHandler('Atlas_Woodcutting:Client:GenerateForestNodes', function(forestId, center, radius, count, modelName)
    for i = 1, count do
        local angle, r = math.random() * 2 * math.pi, radius * math.sqrt(math.random())
        local x, y = center.x + r * math.cos(angle), center.y + r * math.sin(angle)
        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)
        if foundGround then
            TriggerServerEvent('Atlas_Woodcutting:Server:SaveNode', forestId, vec3(x, y, groundZ), modelName)
        end
        Citizen.Wait(200)
    end
end)

-- [[ INTERACTION ]]

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local pCoords = GetEntityCoords(PlayerPedId())
        local pForward = GetEntityForwardVector(PlayerPedId())
        local start, target = pCoords + vec3(0, 0, 0.6), pCoords + (pForward * 2.2) + vec3(0, 0, 0.6)

        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 273, PlayerPedId(), 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        -- FIX: Use Type check to avoid Native Crash
        if hit == 1 and entityHit ~= 0 and GetEntityType(entityHit) == 3 then
            local treeCoords = GetEntityCoords(entityHit)
            local model = GetEntityModel(entityHit)

            -- If it's one of our props or a known tree
            if model == `p_tree_pine_01` or Config.Trees[model] then
                local str = CreateVarString(10, "LITERAL_STRING", "Tree Detected | [G] Chop")
                SetTextScale(0.35, 0.35)
                DisplayText(str, 0.5, 0.88)

                if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', treeCoords)
                end
            end
        end
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
