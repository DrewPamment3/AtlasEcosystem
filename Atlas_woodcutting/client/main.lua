local isBusy = false

local function DrawTxt(text, x, y)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    local str = CreateVarString(10, "LITERAL_STRING", text)
    DisplayText(str, x, y)
end

-- [[ NODE GENERATION ]]

RegisterNetEvent('Atlas_Woodcutting:Client:GenerateForestNodes')
AddEventHandler('Atlas_Woodcutting:Client:GenerateForestNodes', function(forestId, center, radius, count, modelName)
    print("^3[Atlas Client]^7 Probing terrain for " .. count .. " trees...")

    for i = 1, count do
        local angle = math.random() * 2 * math.pi
        local r = radius * math.sqrt(math.random())
        local x = center.x + r * math.cos(angle)
        local y = center.y + r * math.sin(angle)

        -- Find the dirt
        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)

        if foundGround then
            print("^2[Atlas Client]^7 Found ground at " .. groundZ .. ". Sending to server...")
            TriggerServerEvent('Atlas_Woodcutting:Server:SaveNode', forestId, vec3(x, y, groundZ), modelName)
        else
            print("^1[Atlas Client]^7 Ground not loaded at this X/Y. Skipping node.")
        end

        Citizen.Wait(500) -- Give plenty of time for server to process each spawn
    end
end)

-- [[ INTERACTION ]]

local function GetTreeInFront()
    local pCoords = GetEntityCoords(PlayerPedId())
    local pForward = GetEntityForwardVector(PlayerPedId())
    local start = pCoords - (pForward * 0.5) + vec3(0, 0, 0.6)
    local target = pCoords + (pForward * 2.2) + vec3(0, 0, 0.6)

    DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

    local rayHandle = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 273, PlayerPedId(), 0)
    local _, hit, _, _, entityHit, material = GetShapeTestResultIncludingMaterial(rayHandle)

    if hit == 1 then
        return true, entityHit, material
    end
    return false, 0, 0
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local hit, entity, material = GetTreeInFront()

        if hit then
            local model = (entity ~= 0) and GetEntityModel(entity) or 0
            local isWood = Config.TreeMaterials[material] ~= nil
            local isKnown = Config.Trees[model] ~= nil or entity ~= 0 -- All spawned nodes have an Entity ID

            DrawTxt("Tree Detected | Entity: " .. entity, 0.5, 0.88)

            if (isWood or isKnown) and not isBusy then
                DrawTxt("Press [G] to Chop", 0.5, 0.91)
                if IsControlJustReleased(0, 0x760A9C6F) then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', GetEntityCoords(entity), entity)
                end
            end
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
