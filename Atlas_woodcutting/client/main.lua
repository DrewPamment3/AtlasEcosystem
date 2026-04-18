local isBusy = false

--- @section Detection Logic
-- Uses a Sphere Sweep to detect tree trunks in a 3D volume
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)

    -- Start the sweep 1 meter BEHIND the player and end 3 meters IN FRONT
    -- This ensures we catch the tree even if we are standing right against it
    local start = pCoords - (pForward * 1.0) + vec3(0, 0, 1.0)
    local target = pCoords + (pForward * 3.0) + vec3(0, 0, 1.0)

    -- Flag 273: 1 (Map) + 16 (Objects) + 256 (Foliage)
    -- Radius 1.2: A thick sphere to ensure we hit the trunk
    local rayHandle = StartShapeTestSphere(start.x, start.y, start.z, target.x, target.y, target.z, 1.2, 273, playerPed,
        7)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    -- DEBUG: This will show if we hit ANY world collision
    if hit ~= 0 then
        local model = GetEntityModel(entityHit)
        print(string.format("^3[Atlas Debug]^7 Hit: %s | Entity: %s | Model: %s", hit, entityHit, model))

        if entityHit ~= 0 then
            return entityHit, hitCoords, model
        end
    else
        print("^3[Atlas Debug]^7 Raycast missed everything. Walk closer or face the trunk directly.")
    end

    return nil
end

--- @section Interaction Loop
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        -- 0x760A9C6F: [G] key
        if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
            local entity, coords, model = GetTreeInFront()

            if entity then
                if Config.Trees[model] then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
                else
                    -- Found a model, but it's not in our list
                    print("^1[Atlas Woodcutting]^7 Unregistered Tree Model: " .. model)
                end
            end
        end
    end
end)

--- @section Event Handlers
RegisterNetEvent('Atlas_Woodcutting:Client:BeginMinigame')
AddEventHandler('Atlas_Woodcutting:Client:BeginMinigame', function(token)
    isBusy = true
    local playerPed = PlayerPedId()

    print("^2[Atlas Woodcutting]^7 Starting chop...")
    TaskStartScenarioInPlace(playerPed, `WORLD_HUMAN_TREE_CHOP`, -1, true)

    Citizen.Wait(Config.MinChopTime)

    ClearPedTasks(playerPed)
    isBusy = false

    -- Finalize with the server
    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        -- Match the math in your GetTreeInFront function
        local start = pCoords + vec3(0, 0, 1.2)
        local target = start + (pForward * 2.5)

        -- DrawLine(startX, startY, startZ, endX, endY, endZ, R, G, B, Alpha)
        DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)
    end
end)
