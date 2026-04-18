local isBusy = false

--- @section Detection Logic
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)

    -- Start at chest height, push forward 2.5 meters
    local start = pCoords + vec3(0, 0, 1.2)
    local target = start + (pForward * 2.5)

    -- Flags: 1 (Map), 16 (Objects), 256 (Foliage/Trees) = 273
    -- StartShapeTestCapsule is the correct RedM native for this
    local rayHandle = StartShapeTestCapsule(start.x, start.y, start.z, target.x, target.y, target.z, 0.6, 273, playerPed,
        7)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    if hit ~= 0 then
        local model = 0
        if entityHit ~= 0 then
            model = GetEntityModel(entityHit)
        end

        -- DEBUG: If model is 0, it means you hit the "World/Map" but not a harvestable entity.
        print(string.format("^3[Atlas Debug]^7 Hit: %s | Entity: %s | Model: %s", hit, entityHit, model))

        if entityHit ~= 0 and model ~= 0 then
            return entityHit, hitCoords, model
        end
    end

    return nil
end

--- @section Interaction Loop
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        -- [G] key
        if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
            local entity, coords, model = GetTreeInFront()

            if entity and model ~= 0 then
                if Config.Trees[model] then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
                else
                    print("^1[Atlas Woodcutting]^7 Model " .. model .. " not in Config.Trees.")
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

    -- Finalize
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
