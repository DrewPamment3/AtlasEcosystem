print("^5======================================^7")
print("^5  ATLAS PROPERTY CLIENT BOOTING^7")
print("^5======================================^7")

local VORPcore = exports.vorp_core:GetCore()
local VORPMenu = exports.vorp_menu:GetMenuData()
print("^2[ATLAS PROPERTY]^7 VORP core & menu loaded")

local Config = AtlasPropertyConfig -- Reference shared config
print("^2[ATLAS PROPERTY]^7 Config loaded")

-- ============================================================
-- CLIENT STATE
-- ============================================================

-- Full property cache (id => { id, name, type, boundary_points, is_valid })
local CachedProperties = {}

-- Nearby properties list (properties within NearbyScanRadius of player)
-- { id, name, centroidX, centroidY }
local NearbyProperties = {}

-- Player inside-state tracking per property
-- { [propertyId] = true/false }
local PlayerPropertyState = {}

-- ============================================================
-- HELPER: DISTANCE (2D)
-- ============================================================

local function Distance2D(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

-- ============================================================
-- PROXIMITY SCAN THREAD (every 5 seconds)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.NearbyScanInterval)

        local playerPed = PlayerPedId()
        if playerPed == 0 then
            goto continue_scan
        end

        local playerCoords = GetEntityCoords(playerPed)
        if not playerCoords then
            goto continue_scan
        end

        local newNearby = {}

        for _, prop in pairs(CachedProperties) do
            -- Only track valid properties
            if prop.is_valid and prop.boundary_points and #prop.boundary_points >= 4 then
                local cx, cy = Config.GetCentroid(prop.boundary_points)
                local dist = Distance2D(playerCoords.x, playerCoords.y, cx, cy)

                if dist <= Config.NearbyScanRadius then
                    table.insert(newNearby, {
                        id = prop.id,
                        name = prop.name,
                        centroidX = cx,
                        centroidY = cy
                    })
                end
            end
        end

        NearbyProperties = newNearby

        -- Clean up PlayerPropertyState for properties no longer nearby
        local nearbyIds = {}
        for _, np in ipairs(NearbyProperties) do
            nearbyIds[np.id] = true
        end
        for propId, _ in pairs(PlayerPropertyState) do
            if not nearbyIds[propId] then
                PlayerPropertyState[propId] = nil
                if Config.DebugLogging then
                    print("^3[ATLAS PROPERTY]^7 Player left vicinity of property " .. propId)
                end
            end
        end

        if Config.DebugLogging then
            print("^3[ATLAS PROPERTY]^7 Proximity scan: " .. #NearbyProperties .. " nearby properties within " .. Config.NearbyScanRadius .. "m")
        end

        ::continue_scan::
    end
end)

-- ============================================================
-- BOUNDARY CHECK THREAD (every 0.5 seconds)
-- ============================================================

Citizen.CreateThread(function()
    while true do
        Citizen.Wait(Config.BoundaryCheckInterval)

        local playerPed = PlayerPedId()
        if playerPed == 0 or #NearbyProperties == 0 then
            goto continue_boundary
        end

        local playerCoords = GetEntityCoords(playerPed)
        if not playerCoords then
            goto continue_boundary
        end

        for _, np in ipairs(NearbyProperties) do
            local prop = CachedProperties[np.id]
            if prop and prop.boundary_points then
                local isInside = Config.IsPointInQuadrilateral(
                    playerCoords.x, playerCoords.y,
                    prop.boundary_points
                )

                local wasInside = PlayerPropertyState[prop.id]

                if isInside ~= wasInside then
                    -- State changed
                    PlayerPropertyState[prop.id] = isInside
                    if isInside then
                        if Config.DebugLogging then
                            print("^2[ATLAS PROPERTY]^7 Player ENTERED property: " .. prop.name .. " (ID: " .. prop.id .. ")")
                        end
                    else
                        if Config.DebugLogging then
                            print("^3[ATLAS PROPERTY]^7 Player LEFT property: " .. prop.name .. " (ID: " .. prop.id .. ")")
                        end
                    end
                end
            end
        end

        ::continue_boundary::
    end
end)

-- ============================================================
-- EVENTS: RECEIVE DATA FROM SERVER
-- ============================================================

RegisterNetEvent('atlas_property:client:receiveAllProperties')
AddEventHandler('atlas_property:client:receiveAllProperties', function(properties)
    if not properties then
        CachedProperties = {}
    else
        local newCache = {}
        for _, prop in ipairs(properties) do
            newCache[prop.id] = prop
        end
        CachedProperties = newCache
    end

    if Config.DebugLogging then
        local validCount = 0
        for _, _ in pairs(CachedProperties) do validCount = validCount + 1 end
        print("^2[ATLAS PROPERTY]^7 Client received " .. validCount .. " properties")
    end

    -- Check if this was triggered by /atlasproperty command (internal flag)
    if ShouldOpenMenu then
        ShouldOpenMenu = false
        OpenPropertyMenu()
    end
end)

RegisterNetEvent('atlas_property:client:receivePropertyDetails')
AddEventHandler('atlas_property:client:receivePropertyDetails', function(detail)
    if not detail then return end
    OpenPropertyDetailMenu(detail)
end)

-- Refresh a single property when server notifies of an update
RegisterNetEvent('atlas_property:client:propertyUpdated')
AddEventHandler('atlas_property:client:propertyUpdated', function(identifier)
    -- identifier could be propertyId (number) or propertyName (string)
    -- Re-request full property list from server to get fresh data
    if Config.DebugLogging then
        print("^3[ATLAS PROPERTY]^7 Property updated notification: " .. tostring(identifier))
    end
    TriggerServerEvent('atlas_property:server:requestAllProperties')
end)

-- ============================================================
-- EVENT: CAPTURE POINT FOR /setpropertypoint
-- ============================================================

RegisterNetEvent('atlas_property:client:capturePoint')
AddEventHandler('atlas_property:client:capturePoint', function(propertyName, pointIndex)
    local playerPed = PlayerPedId()
    if playerPed == 0 then return end

    local coords = GetEntityCoords(playerPed)
    if not coords then return end

    -- Send coords back to server
    TriggerServerEvent('atlas_property:server:setBoundaryPoint', propertyName, pointIndex, {
        x = coords.x,
        y = coords.y,
        z = coords.z
    })

    if Config.DebugLogging then
        print(string.format("^2[ATLAS PROPERTY]^7 Captured point %d for '%s': (%.2f, %.2f, %.2f)",
            pointIndex, propertyName, coords.x, coords.y, coords.z))
    end
end)

-- ============================================================
-- MENU: OPEN PROPERTY LIST (from /atlasproperty command)
-- ============================================================

local ShouldOpenMenu = false

RegisterCommand('atlasproperty', function()
    ShouldOpenMenu = true
    TriggerServerEvent('atlas_property:server:requestAllProperties')
end, false)

function OpenPropertyMenu()
    if not VORPMenu then
        print("^1[ATLAS PROPERTY]^7 VORP Menu export is nil! Check if vorp_menu is started.")
        return
    end

    VORPMenu.CloseAll()

    local elements = {}

    -- Build a sorted list from cache
    local sortedProperties = {}
    for _, prop in pairs(CachedProperties) do
        table.insert(sortedProperties, prop)
    end
    table.sort(sortedProperties, function(a, b) return a.name:lower() < b.name:lower() end)

    if #sortedProperties == 0 then
        table.insert(elements, {
            label = "No properties found",
            value = {},
            desc = "Use /createproperty to create one"
        })
    else
        for _, prop in ipairs(sortedProperties) do
            local statusText = ""
            local validDesc = ""
            if prop.is_valid then
                statusText = "~g~[Active]~s~ "
                validDesc = "Type: " .. (prop.type or "house") .. " | Fully defined"
            else
                statusText = "~y~[In Development]~s~ "
                local pointCount = 0
                if prop.boundary_points then
                    for _ = 1, 4 do
                        if prop.boundary_points[_] and prop.boundary_points[_].x then
                            pointCount = pointCount + 1
                        end
                    end
                end
                validDesc = pointCount .. "/4 boundary points set"
            end

            table.insert(elements, {
                label = statusText .. prop.name,
                value = { action = "viewDetails", propertyId = prop.id },
                desc = validDesc
            })
        end
    end

    VORPMenu.Open('default', GetCurrentResourceName(), 'atlas_property_main', {
        title = 'Atlas Properties',
        align = 'top-right',
        elements = elements
    }, function(data, menu)
        if data.current and data.current.value then
            local val = data.current.value
            if val.action == "viewDetails" and val.propertyId then
                TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
            end
        end
    end, function(data, menu)
        menu.close()
    end)
end

-- ============================================================
-- MENU: PROPERTY DETAIL VIEW / EDIT
-- ============================================================

function OpenPropertyDetailMenu(detail)
    if not VORPMenu then
        print("^1[ATLAS PROPERTY]^7 VORP Menu export is nil!")
        return
    end

    VORPMenu.CloseAll()

    local elements = {}

    -- Title entry (non-interactive)
    local boundaryInfo = "Not fully defined"
    if detail.is_valid then
        boundaryInfo = "4/4 points set (Complete)"
    else
        local count = 0
        if detail.boundary_points then
            for _ = 1, 4 do
                if detail.boundary_points[_] and detail.boundary_points[_].x then
                    count = count + 1
                end
            end
        end
        boundaryInfo = count .. "/4 points set (Incomplete)"
    end

    local employeeList = ""
    if detail.employees and #detail.employees > 0 then
        local ids = {}
        for _, eid in ipairs(detail.employees) do
            table.insert(ids, tostring(eid))
        end
        employeeList = table.concat(ids, ", ")
    else
        employeeList = "None"
    end

    -- Info entry (non-clickable)
    table.insert(elements, {
        label = "Name: " .. detail.name,
        value = {},
        desc = "Type: " .. (detail.type or "house") .. " | " .. boundaryInfo
    })

    table.insert(elements, {
        label = "Owner: " .. (detail.owner_charid or "None"),
        value = {},
        desc = "Character ID that owns this property"
    })

    table.insert(elements, {
        label = "Value: $" .. string.format("%.2f", detail.value or 0),
        value = {},
        desc = "Property monetary value"
    })

    table.insert(elements, {
        label = "Rent/Tax: $" .. string.format("%.2f", detail.rent_tax or 0),
        value = {},
        desc = "Recurring rent or tax amount"
    })

    table.insert(elements, {
        label = "Employees: " .. employeeList,
        value = {},
        desc = "Character IDs with access"
    })

    -- Editable actions
    table.insert(elements, {
        label = "~b~[ Edit Owner ]",
        value = { action = "setOwner", propertyId = detail.id },
        desc = "Set the owner character ID"
    })

    table.insert(elements, {
        label = "~b~[ Add Employee ]",
        value = { action = "addEmployee", propertyId = detail.id },
        desc = "Add an employee by character ID"
    })

    table.insert(elements, {
        label = "~b~[ Remove Employee ]",
        value = { action = "removeEmployee", propertyId = detail.id },
        desc = "Remove an employee by character ID"
    })

    table.insert(elements, {
        label = "~b~[ Set Value ]",
        value = { action = "setValue", propertyId = detail.id },
        desc = "Set the property monetary value"
    })

    table.insert(elements, {
        label = "~b~[ Set Rent/Tax ]",
        value = { action = "setRentTax", propertyId = detail.id },
        desc = "Set the recurring rent or tax amount"
    })

    table.insert(elements, {
        label = "~b~[ Change Type: " .. (detail.type or "house") .. " ]",
        value = { action = "changeType", propertyId = detail.id },
        desc = "Change property type"
    })

    table.insert(elements, {
        label = "~r~[ Back ]",
        value = { action = "back" },
        desc = "Return to property list"
    })

    VORPMenu.Open('default', GetCurrentResourceName(), 'atlas_property_detail', {
        title = detail.name,
        align = 'top-right',
        elements = elements
    }, function(data, menu)
        if data.current and data.current.value then
            local val = data.current.value

            if val.action == "back" then
                -- Re-request list and go back
                TriggerServerEvent('atlas_property:server:requestAllProperties')

            elseif val.action == "setOwner" then
                menu.close()
                ShowInputDialog("Enter Character ID for Owner:", function(inputText)
                    local charId = tonumber(inputText)
                    if charId then
                        TriggerServerEvent('atlas_property:server:setOwner', val.propertyId, charId)
                    end
                    -- Re-open detail after a short delay
                    Citizen.Wait(300)
                    TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
                end)

            elseif val.action == "addEmployee" then
                menu.close()
                ShowInputDialog("Enter Character ID to add as Employee:", function(inputText)
                    local charId = tonumber(inputText)
                    if charId then
                        TriggerServerEvent('atlas_property:server:addEmployee', val.propertyId, charId)
                    end
                    Citizen.Wait(300)
                    TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
                end)

            elseif val.action == "removeEmployee" then
                menu.close()
                ShowInputDialog("Enter Character ID to remove from Employees:", function(inputText)
                    local charId = tonumber(inputText)
                    if charId then
                        TriggerServerEvent('atlas_property:server:removeEmployee', val.propertyId, charId)
                    end
                    Citizen.Wait(300)
                    TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
                end)

            elseif val.action == "setValue" then
                menu.close()
                ShowInputDialog("Enter new property value ($):", function(inputText)
                    local newVal = tonumber(inputText)
                    if newVal then
                        TriggerServerEvent('atlas_property:server:setValue', val.propertyId, newVal)
                    end
                    Citizen.Wait(300)
                    TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
                end)

            elseif val.action == "setRentTax" then
                menu.close()
                ShowInputDialog("Enter new rent/tax amount ($):", function(inputText)
                    local newVal = tonumber(inputText)
                    if newVal then
                        TriggerServerEvent('atlas_property:server:setRentTax', val.propertyId, newVal)
                    end
                    Citizen.Wait(300)
                    TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
                end)

            elseif val.action == "changeType" then
                OpenTypeSelectMenu(val.propertyId, detail.type)
            end
        end
    end, function(data, menu)
        menu.close()
    end)
end

-- ============================================================
-- MENU: TYPE SELECTION SUBMENU
-- ============================================================

function OpenTypeSelectMenu(propertyId, currentType)
    if not VORPMenu then return end

    local elements = {}

    for _, typeName in ipairs(Config.PropertyTypes) do
        local prefix = ""
        if typeName == currentType then
            prefix = "~g~* ~s~" -- Mark current type
        end

        table.insert(elements, {
            label = prefix .. typeName:gsub("_", " "),
            value = { action = "selectType", propertyId = propertyId, type = typeName },
            desc = "Set property type to " .. typeName
        })
    end

    table.insert(elements, {
        label = "~r~[ Back ]",
        value = { action = "back", propertyId = propertyId },
        desc = "Return to property details"
    })

    VORPMenu.Open('default', GetCurrentResourceName(), 'atlas_property_type_select', {
        title = 'Select Property Type',
        align = 'top-right',
        elements = elements
    }, function(data, menu)
        if data.current and data.current.value then
            local val = data.current.value
            if val.action == "selectType" then
                TriggerServerEvent('atlas_property:server:setType', val.propertyId, val.type)
                menu.close()
                Citizen.Wait(300)
                TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
            elseif val.action == "back" then
                menu.close()
                TriggerServerEvent('atlas_property:server:requestPropertyDetails', val.propertyId)
            end
        end
    end, function(data, menu)
        menu.close()
    end)
end

-- ============================================================
-- INPUT DIALOG HELPER (uses vorp_inputs)
-- ============================================================

--- Displays an input dialog and calls callback with the result.
--- Falls back to VORP notifications if vorp_inputs is unavailable.
---@param promptText string
---@param callback function Receives the input string (or nil if cancelled)
function ShowInputDialog(promptText, callback)
    -- Try using vorp_inputs
    local success, inputExport = pcall(function()
        return exports.vorp_inputs
    end)

    if success and inputExport then
        inputExport:ShowInput(promptText, "", function(result)
            if result and result ~= "" then
                callback(result)
            end
            -- If empty/cancelled, callback is not called
        end)
    else
        -- Fallback: notify and return nil after a moment
        print("^1[ATLAS PROPERTY]^7 vorp_inputs not available! Cannot show input dialog: " .. promptText)
        VORPcore.NotifyRightTip(PlayerId(), "~r~vorp_inputs not available", 4000)
    end
end

-- ============================================================
-- PLAYER LOADED: REQUEST PROPERTIES FROM SERVER
-- ============================================================

AddEventHandler('vorp:SelectedCharacter', function()
    Citizen.Wait(2000) -- Wait for everything to initialize
    print("^2[ATLAS PROPERTY]^7 Player loaded - requesting property data from server...")
    TriggerServerEvent('atlas_property:server:requestAllProperties')
end)

print("^5======================================^7")
print("^5  ATLAS PROPERTY CLIENT READY^7")
print("^5======================================^7")
