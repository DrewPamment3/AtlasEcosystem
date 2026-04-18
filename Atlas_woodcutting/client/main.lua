local isBusy = false

-- Function to find what is in front of the player
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)
    local distance = 2.5 -- How far the player can reach

    -- Calculate the point in front of the player
    local destination = pCoords + (pForward * distance)

    -- Flag 16 is for Objects (trees/props). Flag 1 is for Map objects.
    -- We use a combination to ensure we hit static world trees.
    local rayHandle = StartShapeTestRay(pCoords.x, pCoords.y, pCoords.z, destination.x, destination.y, destination.z, 17,
        playerPed, 0)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 1 and entityHit ~= 0 then
        local model = GetEntityModel(entityHit)
        return entityHit, hitCoords, model
    end
    return nil
end

-- Main Interaction Thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0) -- 0ms while checking for input

        -- Use your preferred key (e.g., [E] / INPUT_CONTEXT)
        if IsControlJustReleased(0, `INPUT_CONTEXT`) and not isBusy then
            local entity, coords, model = GetTreeInFront()

            -- Debug: Uncomment the line below to see hashes of objects you look at in F8
            if entity then print("Hit Model Hash: " .. model) end

            if entity and Config.Trees[model] then
                -- Trigger server to check inventory and start session
                TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
            end
        end
    end
end)

-- Server acknowledges and tells client to start "working"
RegisterNetEvent('Atlas_Woodcutting:Client:BeginMinigame')
AddEventHandler('Atlas_Woodcutting:Client:BeginMinigame', function(token)
    isBusy = true

    local playerPed = PlayerPedId()

    -- 1. Start Animation
    TaskStartScenarioInPlace(playerPed, `WORLD_HUMAN_TREE_CHOP`, -1, true)

    -- 2. VORP Progress Bar (Simulated Minigame for now)
    -- exports['vorp_progressbar']:start("Chopping Tree...", Config.MinChopTime, function(wait)
    --     if not wait then
    --         -- Completion logic
    --     end
    -- end)

    -- For testing without the progress bar script installed yet:
    Citizen.Wait(Config.MinChopTime)

    -- 3. Cleanup
    ClearPedTasks(playerPed)
    isBusy = false

    -- 4. Tell server we are done.
    -- NOTE: In a real scenario, we'd pass the actual axe name from inventory.
    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)
