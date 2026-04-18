local isBusy = false

--- @section Detection Logic
-- Checks what is directly in front of the player ped
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)
    local distance = 2.5

    -- Calculate destination point based on forward vector
    local destination = pCoords + (pForward * distance)

    -- Flag 17 (1 | 16) targets both Map Objects and Scripted Props
    local rayHandle = StartShapeTestRay(pCoords.x, pCoords.y, pCoords.z, destination.x, destination.y, destination.z, 17,
        playerPed, 0)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 1 and entityHit ~= 0 then
        local model = GetEntityModel(entityHit)
        return entityHit, hitCoords, model
    end
    return nil
end

--- @section Interaction Loop
-- Main thread for input detection
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        -- 0x760A9C6F: [G] key (INPUT_INTERACT_ANIMAL)
        if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
            local entity, coords, model = GetTreeInFront()

            -- Debugging: Prints hashes to F8 console to help build your Config.Trees list
            if entity then
                print("^2[Atlas Woodcutting]^7 Found Model Hash: " .. model)
            end

            if entity and Config.Trees[model] then
                -- Request the secure session from the server
                TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
            end
        end
    end
end)

--- @section Event Handlers
-- Triggered by server after successful validation of position and tools
RegisterNetEvent('Atlas_Woodcutting:Client:BeginMinigame')
AddEventHandler('Atlas_Woodcutting:Client:BeginMinigame', function(token)
    isBusy = true
    local playerPed = PlayerPedId()

    -- Start the woodcutting scenario
    TaskStartScenarioInPlace(playerPed, `WORLD_HUMAN_TREE_CHOP`, -1, true)

    -- Placeholder for work duration
    -- In the future, replace this Wait with a proper VORP or custom Minigame export
    Citizen.Wait(Config.MinChopTime)

    -- Stop animation and reset busy status
    ClearPedTasks(playerPed)
    isBusy = false

    -- Finalize: Send token back to server to receive XP and Loot
    -- Note: 'crude_axe' is hardcoded here for initial testing
    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)
