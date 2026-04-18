local isBusy = false

--- @section Detection Logic
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)
    local distance = 2.5 -- Increased slightly for easier detection

    -- Start 1 meter above ground to hit the trunk, not the dirt
    local startX, startY, startZ = pCoords.x, pCoords.y, pCoords.z + 1.2
    local destX = startX + (pForward.x * distance)
    local destY = startY + (pForward.y * distance)
    local destZ = startZ + (pForward.z * distance)

    -- Flag -1 hits everything. 0.5 radius capsule is a thick beam.
    local rayHandle = StartShapeTestCapsule(startX, startY, startZ, destX, destY, destZ, 0.5, -1, playerPed, 0)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    -- DEBUG: This will always print when you press G, even if it hits nothing
    print(string.format("^3[Atlas Debug]^7 Raycast Hit: %s | EntityHandle: %s", hit, entityHit))

    if hit == 1 and entityHit ~= 0 then
        local model = GetEntityModel(entityHit)
        local eType = GetEntityType(entityHit)

        -- Logging what we found
        print(string.format("^2[Atlas Woodcutting]^7 Found Model: %s | Type: %s", model, eType))

        return entityHit, hitCoords, model
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

            if entity and Config.Trees[model] then
                TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
            elseif entity then
                -- This helps you see why a tree ISN'T working (it's not in your config)
                print("^1[Atlas Woodcutting]^7 This model (" .. model .. ") is not in Config.Trees!")
            end
        end
    end
end)

--- @section Event Handlers
RegisterNetEvent('Atlas_Woodcutting:Client:BeginMinigame')
AddEventHandler('Atlas_Woodcutting:Client:BeginMinigame', function(token)
    isBusy = true
    local playerPed = PlayerPedId()

    TaskStartScenarioInPlace(playerPed, `WORLD_HUMAN_TREE_CHOP`, -1, true)

    Citizen.Wait(Config.MinChopTime)

    ClearPedTasks(playerPed)
    isBusy = false

    -- Hardcoded 'crude_axe' for initial testing
    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)
