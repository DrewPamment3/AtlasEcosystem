local isBusy = false
local debugMode = true
local GroveRegistry = {} -- Stores [coordKey] = {entity, forest_id}

-- [[ UI DRAWING ]]
local function DrawWoodcuttingPrompt()
    local x, y = 0.5, 0.92
    DrawRect(x, y, 0.12, 0.045, 0, 0, 0, 180)

    -- "G" Button Look
    SetTextScale(0.38, 0.38)
    SetTextColor(0, 0, 0, 255)
    SetTextCentre(true)
    local gText = CreateVarString(10, "LITERAL_STRING", "G")
    DrawRect(x - 0.035, y, 0.022, 0.032, 255, 255, 255, 255)
    DisplayText(gText, x - 0.035, y - 0.016)

    -- The Prompt
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(false)
    SetTextFontForCurrentCommand(1)
    local actionText = CreateVarString(10, "LITERAL_STRING", "CHOP TREE")
    DisplayText(actionText, x - 0.018, y - 0.016)
end

-- [[ COORD KEY HELPER ]]
-- Rounds to 1 decimal place to avoid floating point jitter
local function GetCoordKey(coords)
    return string.format("%.1f_%.1f", coords.x, coords.y)
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

    -- Source of Truth: Mapping the coordinates to the Forest ID
    local key = GetCoordKey(node)
    GroveRegistry[key] = { entity = tree, forest_id = node.forest_id }

    if debugMode then print("^3[Atlas]^7 Registered Tree at: " .. key) end
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
        local target = pCoords + (pForward * 2.5) + vec3(0, 0, 1.2)

        if debugMode then DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255) end

        -- Detect objects (16) and map geometry (1) for broad coverage
        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 16, playerPed, 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        if hit == 1 and entityHit ~= 0 then
            local entCoords = GetEntityCoords(entityHit)
            local key = GetCoordKey(entCoords)
            local nodeData = GroveRegistry[key]

            if nodeData then
                DrawWoodcuttingPrompt()

                if IsControlJustPressed(0, 0x760A9C6F) then
                    print("^2[Atlas]^7 Interaction Match: Key " .. key .. " belongs to Forest " .. nodeData.forest_id)
                    if not isBusy then
                        TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', entCoords)
                    end
                end
            elseif IsControlJustPressed(0, 0x760A9C6F) and debugMode then
                print("^1[Atlas]^7 G Pressed. No node found at coordinate key: " .. key)
            end
        end
    end
end)

-- [[ SYNC & CLEANUP ]]
RegisterNetEvent('Atlas_Woodcutting:Client:SyncNodes')
AddEventHandler('Atlas_Woodcutting:Client:SyncNodes', function(nodes)
    -- Clean world of all managed tree models before sync
    local objects = GetGamePool('CObject')
    for _, entity in ipairs(objects) do
        local model = GetEntityModel(entity)
        -- Add any tree models you use here to ensure a clean slate
        if model == `p_tree_pine01x` or model == `p_tree_oak01x` or model == `p_pine_01` then
            DeleteEntity(entity)
        end
    end
    GroveRegistry = {}
    for _, node in ipairs(nodes) do SpawnLocalTree(node) end
end)

RegisterNetEvent('Atlas_Woodcutting:Client:WipeSpecificForest')
AddEventHandler('Atlas_Woodcutting:Client:WipeSpecificForest', function(forestId)
    for key, data in pairs(GroveRegistry) do
        if data.forest_id == forestId then
            if DoesEntityExist(data.entity) then DeleteEntity(data.entity) end
            GroveRegistry[key] = nil
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
        local x, y = center.x + r * math.cos(angle), center.y + r * math.sin(angle)
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
