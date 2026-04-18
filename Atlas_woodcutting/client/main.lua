local isBusy = false
local currentMaterial = 0
local currentEntity = 0

-- Helper for UI text
local function DrawTxt(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    DisplayText(str, x, y)
end

-- Detection using Material Flags
local function GetTreeMaterialInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)

    local start = pCoords + vec3(0, 0, 1.2)
    local target = start + (pForward * 2.2)

    DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

    -- Flag 273: Map (1) + Objects (16) + Foliage (256)
    local rayHandle = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 273, playerPed, 0)
    local _, hit, hitCoords, _, entityHit, materialHash = GetShapeTestResultIncludingMaterial(rayHandle)

    if hit == 1 then
        return hit, entityHit, materialHash, hitCoords
    end
    return nil
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local hit, entity, material, coords = GetTreeMaterialInFront()

        if hit == 1 then
            currentMaterial = material
            currentEntity = entity

            DrawTxt("Material: " .. material .. " | Entity: " .. entity, 0.5, 0.88)

            local isWood = Config.TreeMaterials[material] ~= nil
            DrawTxt("Is Harvestable Wood: " .. (isWood and "YES" or "NO"), 0.5, 0.91)

            if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                if isWood or (entity ~= 0 and Config.Trees[GetEntityModel(entity)]) then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
                end
            end
        else
            DrawTxt("Nothing Detected", 0.5, 0.88)
        end
    end
end)

RegisterNetEvent('Atlas_Woodcutting:Client:BeginMinigame')
AddEventHandler('Atlas_Woodcutting:Client:BeginMinigame', function(token)
    isBusy = true
    TaskStartScenarioInPlace(PlayerPedId(), `WORLD_HUMAN_TREE_CHOP`, -1, true)
    Citizen.Wait(Config.MinChopTime)
    ClearPedTasks(PlayerPedId())
    isBusy = false
    TriggerServerEvent('Atlas_Woodcutting:Server:FinishChop', token, "crude_axe")
end)
