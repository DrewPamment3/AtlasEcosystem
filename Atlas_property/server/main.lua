print("^5======================================^7")
print("^5  ATLAS PROPERTY SERVER BOOTING^7")
print("^5======================================^7")

local VORPcore = exports.vorp_core:GetCore()
print("^2[ATLAS PROPERTY]^7 VORP core loaded")

local Config = AtlasPropertyConfig -- Reference shared config
print("^2[ATLAS PROPERTY]^7 Config loaded")

-- ============================================================
-- DATABASE INITIALIZATION
-- ============================================================
Citizen.CreateThread(function()
    Citizen.Wait(500)

    exports.oxmysql:execute([[
        CREATE TABLE IF NOT EXISTS atlas_properties (
            id INT AUTO_INCREMENT PRIMARY KEY,
            name VARCHAR(100) NOT NULL UNIQUE,
            type VARCHAR(50) NOT NULL DEFAULT 'house',
            boundary_points JSON NOT NULL DEFAULT '[]',
            owner_charid INT DEFAULT NULL,
            `value` DECIMAL(12,2) DEFAULT 0.00,
            rent_tax DECIMAL(10,2) DEFAULT 0.00,
            employees JSON DEFAULT '[]',
            metadata JSON DEFAULT '{}',
            is_valid TINYINT(1) DEFAULT 0,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])

    print("^2[ATLAS PROPERTY]^7 Database tables ensured")
end)

-- ============================================================
-- HELPER: ADMIN CHECK
-- ============================================================

--- Returns true if player source is admin, false otherwise. Notifies player on failure.
---@param _source number Player source
---@return boolean
local function IsAdmin(_source)
    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return false
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"

    for _, allowedGroup in ipairs(Config.AdminGroups) do
        if charGroup == allowedGroup then
            return true
        end
    end

    VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
    return false
end

-- ============================================================
-- HELPER: PARSE JSON FROM DB (oxmysql returns JSON as string)
-- ============================================================

--- Decode a JSON field from oxmysql. Returns empty table on failure.
---@param jsonValue string|table
---@return table
local function DecodeJSON(jsonValue)
    if type(jsonValue) == "table" then
        return jsonValue -- oxmysql may already decode
    end
    if type(jsonValue) == "string" and jsonValue ~= "" then
        local success, result = pcall(json.decode, jsonValue)
        if success then
            return result
        end
    end
    return {}
end

-- ============================================================
-- HELPER: REFRESH A SINGLE PROPERTY'S STATE (for is_valid logic)
-- ============================================================

local function CheckAndMarkPropertyValid(propertyName)
    exports.oxmysql:execute('SELECT boundary_points FROM atlas_properties WHERE name = ?', { propertyName }, function(result)
        if result and result[1] then
            local points = DecodeJSON(result[1].boundary_points)
            local validCount = 0
            for _ = 1, 4 do
                if points[_] and points[_].x and points[_].y and points[_].z then
                    validCount = validCount + 1
                end
            end
            local isValid = (validCount == 4) and 1 or 0
            exports.oxmysql:execute('UPDATE atlas_properties SET is_valid = ? WHERE name = ?', { isValid, propertyName })
            if Config.DebugLogging then
                print("^3[ATLAS PROPERTY]^7 Property '" .. propertyName .. "' is_valid = " .. isValid .. " (" .. validCount .. "/4 points)")
            end
        end
    end)
end

-- ============================================================
-- EVENTS: CLIENT REQUESTS FULL PROPERTY LIST (on player load)
-- ============================================================

RegisterServerEvent('atlas_property:server:requestAllProperties')
AddEventHandler('atlas_property:server:requestAllProperties', function()
    local _source = source

    exports.oxmysql:execute('SELECT id, name, type, boundary_points, is_valid FROM atlas_properties', {}, function(results)
        if not results then results = {} end

        -- Decode boundary_points for each row so client receives a proper table
        local properties = {}
        for _, row in ipairs(results) do
            table.insert(properties, {
                id = row.id,
                name = row.name,
                type = row.type,
                boundary_points = DecodeJSON(row.boundary_points),
                is_valid = row.is_valid == 1
            })
        end

        TriggerClientEvent('atlas_property:client:receiveAllProperties', _source, properties)

        if Config.DebugLogging then
            print("^2[ATLAS PROPERTY]^7 Sent " .. #properties .. " properties to player " .. _source)
        end
    end)
end)

-- ============================================================
-- EVENTS: CLIENT REQUESTS DETAILS FOR A SINGLE PROPERTY (menu view)
-- ============================================================

RegisterServerEvent('atlas_property:server:requestPropertyDetails')
AddEventHandler('atlas_property:server:requestPropertyDetails', function(propertyId)
    local _source = source

    exports.oxmysql:execute(
        'SELECT * FROM atlas_properties WHERE id = ?', { propertyId }, function(results)
            if results and results[1] then
                local row = results[1]
                local detail = {
                    id = row.id,
                    name = row.name,
                    type = row.type,
                    boundary_points = DecodeJSON(row.boundary_points),
                    owner_charid = row.owner_charid,
                    value = row.value,
                    rent_tax = row.rent_tax,
                    employees = DecodeJSON(row.employees),
                    metadata = DecodeJSON(row.metadata),
                    is_valid = row.is_valid == 1,
                    created_at = row.created_at,
                    updated_at = row.updated_at
                }
                TriggerClientEvent('atlas_property:client:receivePropertyDetails', _source, detail)
            else
                VORPcore.NotifyRightTip(_source, "~r~Property not found", 4000)
            end
        end
    )
end)

-- ============================================================
-- EVENTS: CLIENT SENDS PLAYER COORDS FOR /setpropertypoint
-- ============================================================

RegisterServerEvent('atlas_property:server:setBoundaryPoint')
AddEventHandler('atlas_property:server:setBoundaryPoint', function(propertyName, pointIndex, coords)
    local _source = source

    if not IsAdmin(_source) then return end
    if not propertyName or not pointIndex or not coords then
        VORPcore.NotifyRightTip(_source, "~r~Invalid data received", 4000)
        return
    end

    if pointIndex < 1 or pointIndex > 4 then
        VORPcore.NotifyRightTip(_source, "~r~Point must be 1, 2, 3, or 4", 4000)
        return
    end

    -- Fetch current boundary points
    exports.oxmysql:execute(
        'SELECT boundary_points FROM atlas_properties WHERE name = ?', { propertyName }, function(result)
            if not result or not result[1] then
                VORPcore.NotifyRightTip(_source, "~r~Property '" .. propertyName .. "' not found", 4000)
                return
            end

            local points = DecodeJSON(result[1].boundary_points)

            -- Ensure array has exactly 4 slots
            for i = 1, 4 do
                if not points[i] then
                    points[i] = { x = nil, y = nil, z = nil }
                end
            end

            -- Set the point
            points[pointIndex] = { x = coords.x, y = coords.y, z = coords.z }

            -- Save back as JSON
            local jsonStr = json.encode(points)
            exports.oxmysql:execute(
                'UPDATE atlas_properties SET boundary_points = ? WHERE name = ?',
                { jsonStr, propertyName }, function()
                    -- Check if property is now complete
                    local setCount = 0
                    for i = 1, 4 do
                        if points[i] and points[i].x and points[i].y and points[i].z then
                            setCount = setCount + 1
                        end
                    end

                    local isValid = (setCount == 4) and 1 or 0
                    exports.oxmysql:execute('UPDATE atlas_properties SET is_valid = ? WHERE name = ?', { isValid, propertyName })

                    VORPcore.NotifyRightTip(_source,
                        "~g~Point " .. pointIndex .. " set for '" .. propertyName .. "' (" .. setCount .. "/4 complete)",
                        4000)

                    if setCount == 4 then
                        VORPcore.NotifyRightTip(_source,
                            "~g~Property '" .. propertyName .. "' is now VALID! All 4 boundary points set.",
                            5000)
                    end

                    -- Notify all clients to refresh their property data
                    TriggerClientEvent('atlas_property:client:propertyUpdated', -1, propertyName)

                    print("^2[ATLAS PROPERTY ADMIN]^7 Point " .. pointIndex ..
                        " set for '" .. propertyName .. "' by player " .. _source ..
                        " (" .. setCount .. "/4 points)")
                end
            )
        end
    )
end)

-- ============================================================
-- EVENTS: ADMIN UPDATES PROPERTY FIELDS (from menu)
-- ============================================================

RegisterServerEvent('atlas_property:server:setOwner')
AddEventHandler('atlas_property:server:setOwner', function(propertyId, charId)
    local _source = source
    if not IsAdmin(_source) then return end

    charId = tonumber(charId)
    if not charId then
        VORPcore.NotifyRightTip(_source, "~r~Invalid character ID", 4000)
        return
    end

    exports.oxmysql:execute('UPDATE atlas_properties SET owner_charid = ? WHERE id = ?', { charId, propertyId }, function()
        VORPcore.NotifyRightTip(_source, "~g~Owner set to character ID " .. charId, 4000)
        TriggerClientEvent('atlas_property:client:propertyUpdated', -1, propertyId)
        print("^2[ATLAS PROPERTY ADMIN]^7 Property ID " .. propertyId .. " owner set to " .. charId .. " by " .. _source)
    end)
end)

RegisterServerEvent('atlas_property:server:addEmployee')
AddEventHandler('atlas_property:server:addEmployee', function(propertyId, charId)
    local _source = source
    if not IsAdmin(_source) then return end

    charId = tonumber(charId)
    if not charId then
        VORPcore.NotifyRightTip(_source, "~r~Invalid character ID", 4000)
        return
    end

    exports.oxmysql:execute('SELECT employees FROM atlas_properties WHERE id = ?', { propertyId }, function(result)
        if not result or not result[1] then
            VORPcore.NotifyRightTip(_source, "~r~Property not found", 4000)
            return
        end

        local employees = DecodeJSON(result[1].employees)

        -- Check for duplicates
        for _, existingId in ipairs(employees) do
            if existingId == charId then
                VORPcore.NotifyRightTip(_source, "~r~Character ID " .. charId .. " is already an employee", 4000)
                return
            end
        end

        table.insert(employees, charId)

        exports.oxmysql:execute('UPDATE atlas_properties SET employees = ? WHERE id = ?',
            { json.encode(employees), propertyId }, function()
                VORPcore.NotifyRightTip(_source, "~g~Added employee: Character ID " .. charId, 4000)
                TriggerClientEvent('atlas_property:client:propertyUpdated', -1, propertyId)
                print("^2[ATLAS PROPERTY ADMIN]^7 Property ID " .. propertyId .. " added employee " .. charId .. " by " .. _source)
            end)
    end)
end)

RegisterServerEvent('atlas_property:server:removeEmployee')
AddEventHandler('atlas_property:server:removeEmployee', function(propertyId, charId)
    local _source = source
    if not IsAdmin(_source) then return end

    charId = tonumber(charId)
    if not charId then
        VORPcore.NotifyRightTip(_source, "~r~Invalid character ID", 4000)
        return
    end

    exports.oxmysql:execute('SELECT employees FROM atlas_properties WHERE id = ?', { propertyId }, function(result)
        if not result or not result[1] then
            VORPcore.NotifyRightTip(_source, "~r~Property not found", 4000)
            return
        end

        local employees = DecodeJSON(result[1].employees)
        local removed = false

        for i = #employees, 1, -1 do
            if employees[i] == charId then
                table.remove(employees, i)
                removed = true
                break
            end
        end

        if not removed then
            VORPcore.NotifyRightTip(_source, "~r~Character ID " .. charId .. " is not an employee", 4000)
            return
        end

        exports.oxmysql:execute('UPDATE atlas_properties SET employees = ? WHERE id = ?',
            { json.encode(employees), propertyId }, function()
                VORPcore.NotifyRightTip(_source, "~g~Removed employee: Character ID " .. charId, 4000)
                TriggerClientEvent('atlas_property:client:propertyUpdated', -1, propertyId)
                print("^2[ATLAS PROPERTY ADMIN]^7 Property ID " .. propertyId .. " removed employee " .. charId .. " by " .. _source)
            end)
    end)
end)

RegisterServerEvent('atlas_property:server:setValue')
AddEventHandler('atlas_property:server:setValue', function(propertyId, newValue)
    local _source = source
    if not IsAdmin(_source) then return end

    newValue = tonumber(newValue)
    if not newValue or newValue < 0 then
        VORPcore.NotifyRightTip(_source, "~r~Invalid value (must be a positive number)", 4000)
        return
    end

    exports.oxmysql:execute('UPDATE atlas_properties SET `value` = ? WHERE id = ?', { newValue, propertyId }, function()
        VORPcore.NotifyRightTip(_source, "~g~Property value set to $" .. string.format("%.2f", newValue), 4000)
        TriggerClientEvent('atlas_property:client:propertyUpdated', -1, propertyId)
        print("^2[ATLAS PROPERTY ADMIN]^7 Property ID " .. propertyId .. " value set to " .. newValue .. " by " .. _source)
    end)
end)

RegisterServerEvent('atlas_property:server:setRentTax')
AddEventHandler('atlas_property:server:setRentTax', function(propertyId, newAmount)
    local _source = source
    if not IsAdmin(_source) then return end

    newAmount = tonumber(newAmount)
    if not newAmount or newAmount < 0 then
        VORPcore.NotifyRightTip(_source, "~r~Invalid rent/tax (must be a positive number)", 4000)
        return
    end

    exports.oxmysql:execute('UPDATE atlas_properties SET rent_tax = ? WHERE id = ?', { newAmount, propertyId }, function()
        VORPcore.NotifyRightTip(_source, "~g~Rent/Tax set to $" .. string.format("%.2f", newAmount), 4000)
        TriggerClientEvent('atlas_property:client:propertyUpdated', -1, propertyId)
        print("^2[ATLAS PROPERTY ADMIN]^7 Property ID " .. propertyId .. " rent/tax set to " .. newAmount .. " by " .. _source)
    end)
end)

RegisterServerEvent('atlas_property:server:setType')
AddEventHandler('atlas_property:server:setType', function(propertyId, newType)
    local _source = source
    if not IsAdmin(_source) then return end

    -- Validate type
    local validType = false
    for _, allowedType in ipairs(Config.PropertyTypes) do
        if newType == allowedType then
            validType = true
            break
        end
    end

    if not validType then
        VORPcore.NotifyRightTip(_source, "~r~Invalid property type: " .. tostring(newType), 4000)
        return
    end

    exports.oxmysql:execute('UPDATE atlas_properties SET type = ? WHERE id = ?', { newType, propertyId }, function()
        VORPcore.NotifyRightTip(_source, "~g~Property type set to: " .. newType, 4000)
        TriggerClientEvent('atlas_property:client:propertyUpdated', -1, propertyId)
        print("^2[ATLAS PROPERTY ADMIN]^7 Property ID " .. propertyId .. " type set to " .. newType .. " by " .. _source)
    end)
end)

-- ============================================================
-- ADMIN COMMANDS
-- ============================================================

-- /createproperty <name>
RegisterCommand('createproperty', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[ATLAS PROPERTY]^7 /createproperty must be run in-game")
        return
    end

    if not IsAdmin(_source) then return end

    local name = args[1]
    if not name or name == "" then
        VORPcore.NotifyRightTip(_source, "~r~Usage: /createproperty <name>", 4000)
        return
    end

    -- Check for duplicate name
    exports.oxmysql:execute('SELECT id FROM atlas_properties WHERE name = ?', { name }, function(result)
        if result and result[1] then
            VORPcore.NotifyRightTip(_source, "~r~A property named '" .. name .. "' already exists", 4000)
            return
        end

        exports.oxmysql:insert(
            'INSERT INTO atlas_properties (name, type, boundary_points, is_valid) VALUES (?, ?, ?, ?)',
            { name, 'house', '[]', 0 }, function(insertId)
                if insertId then
                    VORPcore.NotifyRightTip(_source,
                        "~g~Property '" .. name .. "' created! Use /setpropertypoint to define its 4 boundaries.",
                        5000)
                    print("^2[ATLAS PROPERTY ADMIN]^7 Property '" .. name .. "' (ID: " .. insertId .. ") created by player " .. _source)

                    -- Notify all clients to refresh
                    TriggerClientEvent('atlas_property:client:propertyUpdated', -1, name)
                else
                    VORPcore.NotifyRightTip(_source, "~r~Database error: Could not create property", 4000)
                end
            end)
    end)
end)

-- /setpropertypoint <name> <point (1-4)>
RegisterCommand('setpropertypoint', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[ATLAS PROPERTY]^7 /setpropertypoint must be run in-game")
        return
    end

    if not IsAdmin(_source) then return end

    local name = args[1]
    local pointIndex = tonumber(args[2])

    if not name or name == "" or not pointIndex then
        VORPcore.NotifyRightTip(_source, "~r~Usage: /setpropertypoint <name> <1|2|3|4>", 4000)
        return
    end

    if pointIndex < 1 or pointIndex > 4 then
        VORPcore.NotifyRightTip(_source, "~r~Point must be 1, 2, 3, or 4", 4000)
        return
    end

    -- Verify property exists
    exports.oxmysql:execute('SELECT id FROM atlas_properties WHERE name = ?', { name }, function(result)
        if not result or not result[1] then
            VORPcore.NotifyRightTip(_source, "~r~Property '" .. name .. "' not found", 4000)
            return
        end

        -- Ask client to send back coords
        TriggerClientEvent('atlas_property:client:capturePoint', _source, name, pointIndex)

        VORPcore.NotifyRightTip(_source,
            "~y~Capturing your current position as Point " .. pointIndex .. " for '" .. name .. "'...", 3000)
    end)
end)

-- NOTE: /atlasproperty command is handled CLIENT-SIDE (client/main.lua)
-- The client triggers the server event with proper source context, then opens the menu.

-- ============================================================
-- PLAYER DISCONNECT CLEANUP
-- ============================================================

AddEventHandler('playerDropped', function(reason)
    local _source = source
    if Config.DebugLogging then
        print("^3[ATLAS PROPERTY]^7 Player " .. _source .. " disconnected")
    end
    -- Nothing persistent to clean up for properties
end)
