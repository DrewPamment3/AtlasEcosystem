local isBusy = false

local function DrawTxt(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    DisplayText(str, x, y)
end

local function GetTreeMaterialInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)
    local start = pCoords - (pForward * 0.5) + vec3(0, 0, 0.6)
    local target = pCoords + (pForward * 2.2) + vec3(0, 0, 0.6)

    DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

    local rayHandle = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 273, playerPed, 0)
    local _, hit, hitCoords, _, entityHit, materialHash = GetShapeTestResultIncludingMaterial(rayHandle)

    return hit, entityHit, materialHash, hitCoords
end

-- Command to "Discover" a tree and get its config line
RegisterCommand('atree', function()
    local hit, entity, material, coords = GetTreeMaterialInFront()
    if hit == 1 then
        local model = (entity ~= 0) and GetEntityModel(entity) or 0
        print("^2[Atlas Discovery]^7 Copy this to Config.Trees:")
        print(string.format("[%s] = { name = 'Discovered Tree', xp = 25 },", model))
        print("^2[Atlas Discovery]^7 Copy this to Config.TreeMaterials:")
        print(string.format("[%s] = true,", material))
    else
        print("^1[Atlas Discovery]^7 No tree detected.")
    end
end)

-- Command to create a restricted zone at your feet
RegisterCommand('azone', function(source, args)
    local radius = tonumber(args[1]) or 50.0
    local coords = GetEntityCoords(PlayerPedId())
    print("^3[Atlas Discovery]^7 Copy this to Config.RestrictedZones:")
    print(string.format("{ coords = vec3(%.2f, %.2f, %.2f), radius = %.1f, name = 'New Restricted Zone' },", coords.x,
        coords.y, coords.z, radius))
end)

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local hit, entity, material, coords = GetTreeMaterialInFront()

        if hit == 1 then
            local model = (entity ~= 0) and GetEntityModel(entity) or 0
            local isWood = Config.TreeMaterials and Config.TreeMaterials[material] ~= nil
            local isKnownModel = Config.Trees and Config.Trees[model] ~= nil

            DrawTxt("Material: " .. material .. " | Model: " .. model, 0.5, 0.88)
            DrawTxt("Harvestable: " .. ((isWood or isKnownModel) and "YES (G)" or "NO"), 0.5, 0.91)

            if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                if isWood or isKnownModel then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
                end
            end
        else
            DrawTxt("Searching for tree...", 0.5, 0.88)
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
