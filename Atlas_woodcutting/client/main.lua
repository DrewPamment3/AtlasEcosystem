local isBusy = false
local currentHitModel = 0
local currentHitEntity = 0
local raycastStatus = "Nothing Found"

-- Corrected RedM Text Drawing Function
local function DrawTxt(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    DisplayText(str, x, y)
end

--- @section Detection Logic
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)

    -- Start 0.5m behind the player and push 2.5m forward
    -- Height set to 1.0 (waist/chest)
    local start = pCoords - (pForward * 0.5) + vec3(0, 0, 1.0)
    local target = pCoords + (pForward * 2.5) + vec3(0, 0, 1.0)

    -- Draw the Line (Visual Debug)
    DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

    -- Flag 273 covers Map, Objects, and Foliage
    local rayHandle = StartShapeTestCapsule(start.x, start.y, start.z, target.x, target.y, target.z, 0.5, 273, playerPed,
        7)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 1 then
        currentHitEntity = entityHit
        currentHitModel = GetEntityModel(entityHit)
        raycastStatus = "HIT! Model: " .. currentHitModel
        return entityHit, hitCoords, currentHitModel
    else
        currentHitEntity = 0
        currentHitModel = 0
        raycastStatus = "Nothing Found"
        return nil
    end
end

--- @section Main Loop
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)

        -- Update detection every frame
        local entity, coords, model = GetTreeInFront()

        -- Draw UI Info
        DrawTxt("Woodcutting Debug", 0.5, 0.85)
        DrawTxt("Status: " .. raycastStatus, 0.5, 0.88)

        if currentHitModel ~= 0 then
            local isConfigured = Config.Trees[currentHitModel] ~= nil
            DrawTxt("In Config: " .. (isConfigured and "YES (Press G)" or "NO"), 0.5, 0.91)
        end

        -- Handle [G] Key
        if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
            if entity and model ~= 0 and Config.Trees[model] then
                TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
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

    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)
