local isBusy = false
local currentMaterial = 0
local currentEntity = 0

--- @section Helper Functions
-- Corrected RedM text drawing sequence
local function DrawTxt(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    DisplayText(str, x, y)
end

--- @section Detection Logic
-- Uses raycasting to detect trees by both Material and Model
local function GetTreeMaterialInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)

    -- Lowered height to 0.6 (waist/chest height)
    -- Starts 0.5m behind the player to ensure it doesn't miss the collision
    local start = pCoords - (pForward * 0.5) + vec3(0, 0, 0.6)
    local target = pCoords + (pForward * 2.2) + vec3(0, 0, 0.6)

    -- Visual Debug Line
    DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

    -- Flag 273 (1 | 16 | 256) hits Map, Objects, and Foliage
    local rayHandle = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 273, playerPed, 0)
    local _, hit, hitCoords, _, entityHit, materialHash = GetShapeTestResultIncludingMaterial(rayHandle)

    if hit == 1 then
        return hit, entityHit, materialHash, hitCoords
    end
    return nil
end

--- @section Main Loop
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local hit, entity, material, coords = GetTreeMaterialInFront()

        if hit == 1 then
            currentMaterial = material
            currentEntity = entity

            -- Resolve the model if an entity exists
            local model = 0
            if entity ~= 0 then model = GetEntityModel(entity) end

            -- Check against your Config
            local isWood = false
            if Config.TreeMaterials then
                isWood = Config.TreeMaterials[material] ~= nil
            end

            local isKnownModel = false
            if Config.Trees and model ~= 0 then
                isKnownModel = Config.Trees[model] ~= nil
            end

            -- Debug UI
            DrawTxt("Material: " .. material .. " | Model: " .. model, 0.5, 0.88)
            DrawTxt("Harvestable: " .. ((isWood or isKnownModel) and "YES (Press G)" or "NO"), 0.5, 0.91)

            -- Interaction: [G] key (0x760A9C6F)
            if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                if isWood or isKnownModel then
                    -- Send request to server
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
                end
            end
        else
            DrawTxt("Searching for tree...", 0.5, 0.88)
        end
    end
end)

--- @section Server Callbacks
-- Triggered by server after validation
RegisterNetEvent('Atlas_Woodcutting:Client:BeginMinigame')
AddEventHandler('Atlas_Woodcutting:Client:BeginMinigame', function(token)
    isBusy = true
    local playerPed = PlayerPedId()

    print("^2[Atlas Woodcutting]^7 Starting work session...")

    -- Start the wood chopping animation
    TaskStartScenarioInPlace(playerPed, `WORLD_HUMAN_TREE_CHOP`, -1, true)

    -- Wait for the chopping duration defined in config
    Citizen.Wait(Config.MinChopTime)

    -- Stop animation and reset busy status
    ClearPedTasks(playerPed)
    isBusy = false

    -- Finalize: Send token to server to claim XP and Loot
    -- Hardcoded 'crude_axe' for current testing
    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)
