local isBusy = false

--- @section Detection Logic
-- Checks what is directly in front of the player ped
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)
    local distance = 1.5 -- Keep it close for immersion

    -- Start the ray at chest height (Z + 1.0)
    local startCoords = vec3(pCoords.x, pCoords.y, pCoords.z + 1.0)
    local destination = startCoords + (pForward * distance)

    -- StartShapeTestCapsule: Radius 0.5 creates a "thick" line to catch tree trunks
    -- Flag -1: Hits everything (we filter manually)
    local rayHandle = StartShapeTestCapsule(startCoords.x, startCoords.y, startCoords.z, destination.x, destination.y,
        destination.z, 0.5, -1, playerPed, 0)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 1 and entityHit ~= 0 then
        -- Check if the entity is actually an Object (Type 3)
        -- Many RDR3 trees are type 3 props
        if GetEntityType(entityHit) == 3 then
            local model = GetEntityModel(entityHit)
            return entityHit, hitCoords, model
        end
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
