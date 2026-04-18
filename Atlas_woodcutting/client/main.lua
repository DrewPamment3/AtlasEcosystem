local isBusy = false
local currentHitModel = 0
local currentHitEntity = 0
local raycastStatus = "Nothing Found"

-- Simple 2D Text Drawing Function
local function DrawTxt(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextFontForCurrentCommand(1) -- Standard RDR2 font
    SetTextColor(255, 255, 255, 215)
    SetTextCentre(1)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    DrawText(str, x, y)
end

--- @section Detection Logic
local function GetTreeInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)

    -- Lowered to 0.8 (waist/chest height) so it doesn't overshoot
    local start = pCoords + vec3(0, 0, 0.8)
    local target = start + (pForward * 2.5)

    -- Draw the line so you can see it in real-time
    DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

    -- Flag 273 (Map + Objects + Foliage)
    local rayHandle = StartShapeTestCapsule(start.x, start.y, start.z, target.x, target.y, target.z, 0.5, 273, playerPed,
        7)
    local _, hit, hitCoords, _, entityHit = GetShapeTestResult(rayHandle)

    if hit == 1 then
        currentHitEntity = entityHit
        currentHitModel = GetEntityModel(entityHit)
        raycastStatus = "HIT! Model: " .. currentHitModel .. " | Entity: " .. entityHit
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

        -- 1. Update the detection every frame for the UI
        local entity, coords, model = GetTreeInFront()

        -- 2. Draw the Debug Text on Screen
        DrawTxt("Woodcutting Debug", 0.5, 0.85)
        DrawTxt("Status: " .. raycastStatus, 0.5, 0.88)
        if currentHitModel ~= 0 then
            local isConfigured = Config.Trees[currentHitModel] ~= nil
            DrawTxt("In Config: " .. (isConfigured and "YES (Press G)" or "NO"), 0.5, 0.91)
        end

        -- 3. Handle the Input
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

    print("^2[Atlas Woodcutting]^7 Starting chop...")
    TaskStartScenarioInPlace(playerPed, `WORLD_HUMAN_TREE_CHOP`, -1, true)

    Citizen.Wait(Config.MinChopTime)

    ClearPedTasks(playerPed)
    isBusy = false

    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)
