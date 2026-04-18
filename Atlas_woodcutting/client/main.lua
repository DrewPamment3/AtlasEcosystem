local isBusy = false

local function GetTreeMaterialInFront()
    local playerPed = PlayerPedId()
    local pCoords = GetEntityCoords(playerPed)
    local pForward = GetEntityForwardVector(playerPed)

    local start = pCoords + vec3(0, 0, 1.2)
    local target = start + (pForward * 2.5)

    DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)

    -- Flag 1 | 16 | 256 (Map, Objects, Foliage)
    local rayHandle = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 273, playerPed, 0)

    -- We use IncludingMaterial to see the physical property of the hit
    local _, hit, hitCoords, _, entityHit, materialHash = GetShapeTestResultIncludingMaterial(rayHandle)

    if hit ~= 0 then
        -- Even if entityHit is 0, materialHash will tell us if it's wood
        return hit, entityHit, materialHash, hitCoords
    end
    return nil
end

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local hit, entity, material, coords = GetTreeMaterialInFront()

        if hit == 1 then
            -- On-Screen Debug
            local text = string.format("Material: %s | Entity: %s", material, entity)

            -- Display the text (use the DrawTxt function we made earlier)
            DrawTxt(text, 0.5, 0.90)

            if IsControlJustReleased(0, 0x760A9C6F) and not isBusy then
                -- In RicX/Pro scripts, they check if material is in a 'Wood' list
                if Config.TreeMaterials[material] or entity ~= 0 then
                    TriggerServerEvent('Atlas_Woodcutting:Server:RequestStart', coords)
                end
            end
        end
    end
end)
