print("^5======================================^7")
print("^5  ATLAS BLIPS SERVER BOOTING^7")
print("^5======================================^7")

local VORPcore = exports.vorp_core:GetCore()
print("^2[ATLAS BLIPS]^7 VORP core loaded")

local Config = AtlasBlipsConfig -- Reference shared config
print("^2[ATLAS BLIPS]^7 Config loaded")

-- Cache of zone data from database, refreshed on resource start
local ZoneData = {
    mining = {},      -- { {id, name, x, y, z, radius, rock_count, tier}, ... }
    woodcutting = {}, -- { {id, name, x, y, z, radius, tree_count, tier}, ... }
}

-- ============================================================
-- DATABASE FETCHING
-- ============================================================

-- Helper: Fetch all zones from a given table and store in ZoneData[zoneType]
local function RefreshZoneData(zoneType, callback)
    local tableName = Config.Tables[zoneType]
    if not tableName then
        print("^1[ATLAS BLIPS]^7 ERROR: No table configured for zone type: " .. tostring(zoneType))
        if callback then callback() end
        return
    end

    if Config.DebugLogging then
        print("^3[ATLAS BLIPS]^7 Fetching " .. zoneType .. " zones from " .. tableName .. "...")
    end

    exports.oxmysql:execute('SELECT * FROM ' .. tableName, {}, function(results)
        if results then
            ZoneData[zoneType] = results
            if Config.DebugLogging then
                print("^2[ATLAS BLIPS]^7 Loaded " .. #results .. " " .. zoneType .. " zones from database")
                for _, zone in ipairs(results) do
                    print(string.format("^2[ATLAS BLIPS]^7   %s ID %d: '%s' at (%.1f, %.1f, %.1f) radius %.1f",
                        zoneType, zone.id, zone.name, zone.x, zone.y, zone.z, zone.radius))
                end
            end
        else
            print("^1[ATLAS BLIPS]^7 ERROR: Failed to load " .. zoneType .. " zones from database")
            ZoneData[zoneType] = {}
        end

        if callback then callback() end
    end)
end

-- Load all zone data on resource start
Citizen.CreateThread(function()
    Citizen.Wait(1500) -- Wait for database connection to be ready

    print("^2[ATLAS BLIPS]^7 Loading zone data from database...")

    -- Load mining zones first, then woodcutting zones
    RefreshZoneData("mining", function()
        print("^2[ATLAS BLIPS]^7 Mining zones loaded: " .. #ZoneData.mining)

        Citizen.Wait(500)
        RefreshZoneData("woodcutting", function()
            print("^2[ATLAS BLIPS]^7 Woodcutting zones loaded: " .. #ZoneData.woodcutting)
            print("^2[ATLAS BLIPS]^7 Total zones loaded: " .. (#ZoneData.mining + #ZoneData.woodcutting))
            print("^5======================================^7")
            print("^5  ATLAS BLIPS SERVER READY^7")
            print("^5======================================^7")
        end)
    end)
end)

-- ============================================================
-- EVENTS
-- ============================================================

-- Send zone data to a client when they load in
RegisterServerEvent('atlas_blips:server:playerLoaded')
AddEventHandler('atlas_blips:server:playerLoaded', function()
    local _source = source
    print("^2[ATLAS BLIPS]^7 Player " .. _source .. " loaded - sending zone data")

    -- Package data with type identifiers
    local blipPayload = {}

    -- Add mining zones
    for _, camp in ipairs(ZoneData.mining) do
        table.insert(blipPayload, {
            type = "mining",
            id = camp.id,
            name = camp.name,
            x = camp.x,
            y = camp.y,
            z = camp.z,
            radius = camp.radius,
            tier = camp.tier,
        })
    end

    -- Add woodcutting zones
    for _, forest in ipairs(ZoneData.woodcutting) do
        table.insert(blipPayload, {
            type = "woodcutting",
            id = forest.id,
            name = forest.name,
            x = forest.x,
            y = forest.y,
            z = forest.z,
            radius = forest.radius,
            tier = forest.tier,
        })
    end

    print("^2[ATLAS BLIPS]^7 Sending " .. #blipPayload .. " zones to player " .. _source ..
        " (Mining: " .. #ZoneData.mining .. ", Woodcutting: " .. #ZoneData.woodcutting .. ")")

    TriggerClientEvent('atlas_blips:client:loadZones', _source, blipPayload)
end)

-- ============================================================
-- ADMIN COMMANDS
-- ============================================================

-- Refresh zone data from database (useful after creating new zones via other modules)
RegisterCommand('refreshblips', function(source, args)
    local _source = source
    if _source == 0 then
        -- Server console can always use this
        print("^2[ATLAS BLIPS]^7 Refreshing zone data from console...")
        RefreshZoneData("mining", function()
            RefreshZoneData("woodcutting", function()
                print("^2[ATLAS BLIPS]^7 Zones refreshed - Mining: " .. #ZoneData.mining .. ", Woodcutting: " .. #ZoneData.woodcutting)
            end)
        end)
        return
    end

    -- In-game player - check admin
    local user = VORPcore.getUser(_source)
    if not user then
        VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
        return
    end

    local character = user.getUsedCharacter
    local charGroup = character and character.group or "user"
    if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end

    RefreshZoneData("mining", function()
        RefreshZoneData("woodcutting", function()
            VORPcore.NotifyRightTip(_source, "~g~Blip data refreshed - " ..
                #ZoneData.mining .. " mining, " .. #ZoneData.woodcutting .. " woodcutting zones", 4000)
            print("^2[ATLAS BLIPS]^7 Zones manually refreshed by admin " .. _source ..
                " - Mining: " .. #ZoneData.mining .. ", Woodcutting: " .. #ZoneData.woodcutting)
        end)
    end)
end)

-- List all zone data (server console command, also usable by admins in-game)
RegisterCommand('listblipzones', function(source, args)
    local _source = source
    if _source ~= 0 then
        local user = VORPcore.getUser(_source)
        if not user then
            VORPcore.NotifyRightTip(_source, "~r~Error loading user data", 4000)
            return
        end
        local character = user.getUsedCharacter
        local charGroup = character and character.group or "user"
        if charGroup ~= 'admin' and charGroup ~= 'superadmin' then
            VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
            return
        end
    end

    print("^2================================================^7")
    print("^2 ATLAS BLIPS - ZONE DATA SUMMARY^7")
    print("^2================================================^7")

    -- Mining zones
    print("^5MINING CAMPS (" .. #ZoneData.mining .. " total):^7")
    if #ZoneData.mining > 0 then
        print(string.format("^3%-4s^7 | ^3%-20s^7 | ^3%-7s^7 | ^3%-4s^7 | ^3%-9s^7 | ^3%-9s^7 | ^3%-8s^7",
            "ID", "Name", "Radius", "Tier", "X", "Y", "Z"))
        print("^2----|----------------------|---------|------|-----------|-----------|--------^7")
        for _, zone in ipairs(ZoneData.mining) do
            print(string.format("^7%-4d^7 | ^6%-20s^7 | ^5%-7.1f^7 | ^3%-4d^7 | ^2%-9.2f^7 | ^2%-9.2f^7 | ^2%-7.2f^7",
                zone.id, zone.name:sub(1, 20), zone.radius, zone.tier, zone.x, zone.y, zone.z))
        end
    else
        print("^3  No mining camps found.^7")
    end

    print("")

    -- Woodcutting zones
    print("^5WOODCUTTING FORESTS (" .. #ZoneData.woodcutting .. " total):^7")
    if #ZoneData.woodcutting > 0 then
        print(string.format("^3%-4s^7 | ^3%-20s^7 | ^3%-7s^7 | ^3%-4s^7 | ^3%-9s^7 | ^3%-9s^7 | ^3%-8s^7",
            "ID", "Name", "Radius", "Tier", "X", "Y", "Z"))
        print("^2----|----------------------|---------|------|-----------|-----------|--------^7")
        for _, zone in ipairs(ZoneData.woodcutting) do
            print(string.format("^7%-4d^7 | ^6%-20s^7 | ^5%-7.1f^7 | ^3%-4d^7 | ^2%-9.2f^7 | ^2%-9.2f^7 | ^2%-7.2f^7",
                zone.id, zone.name:sub(1, 20), zone.radius, zone.tier, zone.x, zone.y, zone.z))
        end
    else
        print("^3  No woodcutting forests found.^7")
    end

    print("^2================================================^7")
    print("^3Total Zones: ^7" .. (#ZoneData.mining + #ZoneData.woodcutting))
    print("^2================================================^7")

    if _source ~= 0 then
        VORPcore.NotifyRightTip(_source, "~g~Blip zones listed in server console", 3000)
    end
end)

-- ============================================================
-- PLAYER DISCONNECT CLEANUP
-- ============================================================

AddEventHandler('playerDropped', function(reason)
    local _source = source
    if Config.DebugLogging then
        print("^3[ATLAS BLIPS]^7 Player " .. _source .. " disconnected (reason: " .. tostring(reason) .. ")")
    end
    -- No persistent state to clean up for blips - they're client-side
end)
