print("^3[Atlas]^7 Client script loaded. Waiting for initialization...")

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
    local model = node.model_hash
    print(string.format("^3[Atlas Debug]^7 Processing node: %s at %.2f, %.2f", model, node.x, node.y))

    if not IsModelInCdimage(model) then
        return print("^1[Atlas Debug]^7 ERROR: Model " .. model .. " is not in the game files.")
    end

    RequestModel(model)
    local timeout = 0
    while not HasModelLoaded(model) and timeout < 100 do
        Citizen.Wait(10)
        timeout = timeout + 1
    end

    if HasModelLoaded(model) then
        local tree = CreateObject(model, node.x, node.y, node.z, false, false, false)
        if DoesEntityExist(tree) then
            FreezeEntityPosition(tree, true)
            SetEntityAsMissionEntity(tree, true, true)
            LocalTrees[tree] = true
            SetModelAsNoLongerNeeded(model)
            print("^2[Atlas Debug]^7 Successfully spawned tree handle: " .. tree)
        else
            print("^1[Atlas Debug]^7 FAILED to create object despite model being loaded.")
        end
    else
        print("^1[Atlas Debug]^7 FAILED to load model: " .. model .. " (Timeout)")
    end
end

RegisterNetEvent('Atlas_Woodcutting:Client:SyncNodes')
AddEventHandler('Atlas_Woodcutting:Client:SyncNodes', function(nodes)
    print("^2[Atlas Debug]^7 SYNC RECEIVED. Node Count: " .. #nodes)

    -- Cleanup existing
    for entity, _ in pairs(LocalTrees) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    LocalTrees = {}

    for i, node in ipairs(nodes) do
        SpawnLocalTree(node)
    end
    print("^2[Atlas Debug]^7 Sync sequence complete.")
end)

-- Initial Sync Request
Citizen.CreateThread(function()
    print("^3[Atlas Debug]^7 Waiting 5s to ping server...")
    Citizen.Wait(5000)
    print("^3[Atlas Debug]^7 Pinging server for nodes...")
    TriggerServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
end)

RegisterCommand('refresh_trees', function()
    print("^3[Atlas Debug]^7 Manual refresh triggered.")
    TriggerServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
end)

-- [[ GENERATION ]]

RegisterNetEvent('Atlas_Woodcutting:Client:GenerateForestNodes')
AddEventHandler('Atlas_Woodcutting:Client:GenerateForestNodes', function(forestId, center, radius, count, modelName)
    print("^3[Atlas]^7 Generation started for Forest " .. forestId)
    for i = 1, count do
        local angle = math.random() * 2 * math.pi
        local r = radius * math.sqrt(math.random())
        local x = center.x + r * math.cos(angle)
        local y = center.y + r * math.sin(angle)
        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)

        if foundGround then
            print("^2[Atlas]^7 Node " .. i .. " ground found at " .. groundZ)
            TriggerServerEvent('Atlas_Woodcutting:Server:SaveNode', forestId, vec3(x, y, groundZ), modelName)
        else
            print("^1[Atlas]^7 Node " .. i .. " FAILED to find ground.")
        end
        Citizen.Wait(500)
    end
end)

-- [[ INTERACTION ]]

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        local start = pCoords + vec3(0, 0, 1.0)
        local target = pCoords + (pForward * 2.2) + vec3(0, 0, 1.0)
        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 16, playerPed, 0)
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
