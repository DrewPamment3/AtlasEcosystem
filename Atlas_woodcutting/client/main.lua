local isBusy = false
local LocalTrees = {}

local function DrawTxt(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    DisplayText(str, x, y)
end

-- [[ SPAWNING ]]
local function SpawnLocalTree(node)
    local modelName = node.model_name
    local modelHash = GetHashKey(modelName)

    print("^3[Atlas]^7 Requesting: " .. modelName)

    if not IsModelInCdimage(modelHash) then
        return print("^1[Atlas]^7 ERROR: Model '" .. modelName .. "' not in manifest.")
    end

    RequestModel(modelHash)
    local timeout = 0
    while not HasModelLoaded(modelHash) and timeout < 100 do
        Citizen.Wait(10)
        timeout = timeout + 1
    end

    if HasModelLoaded(modelHash) then
        local tree = CreateObject(modelHash, node.x, node.y, node.z, false, false, false)
        FreezeEntityPosition(tree, true)
        SetEntityAsMissionEntity(tree, true, true)
        LocalTrees[tree] = true
        SetModelAsNoLongerNeeded(modelHash)
        print("^2[Atlas]^7 Spawned: " .. modelName .. " (Handle: " .. tree .. ")")
    else
        print("^1[Atlas]^7 FAILED to load: " .. modelName)
    end
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

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
end)

RegisterCommand('refresh_trees', function()
    TriggerServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
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

-- [[ INTERACTION ]]
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local pCoords = GetEntityCoords(PlayerPedId())
        local pForward = GetEntityForwardVector(PlayerPedId())
        local start, target = pCoords + vec3(0, 0, 1.0), pCoords + (pForward * 2.2) + vec3(0, 0, 1.0)
        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 16, PlayerPedId(), 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        if hit == 1 and LocalTrees[entityHit] then
            DrawTxt("Harvest Tree [G]", 0.5, 0.88)
            if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', GetEntityCoords(entityHit))
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
