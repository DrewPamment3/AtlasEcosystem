print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded")

local Config = AtlasBlipsConfig -- Reference shared config

-- Track all created blips so we can clean up and recreate as needed
local ActiveBlips = {} -- { [zoneKey] = { radiusBlip, spriteBlip } }

-- Track whether we've received zone data yet
local BlipsInitialized = false

-- ============================================================
-- BLIP CREATION FUNCTIONS
-- ============================================================

-- Creates both a radius circle blip and a sprite icon blip for a zone
-- Returns { radiusBlip, spriteBlip } or nil on failure
local function CreateZoneBlips(zoneData)
    if Config.DebugLogging then
        print(string.format("^3[ATLAS BLIPS]^7 Creating blips for %s zone ID %d '%s' at (%.1f, %.1f, %.1f) radius %.1f",
            zoneData.type, zoneData.id, zoneData.name, zoneData.x, zoneData.y, zoneData.z, zoneData.radius))
    end

    -- Check if this zone type is enabled in config
    if not Config.ShowBlips[zoneData.type] then
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7 Skipping " .. zoneData.type .. " zone - disabled in config")
        end
        return nil
    end

    -- Get color and sprite settings for this zone type
    local colorID = Config.Colors[zoneData.type]
    local spriteName = Config.Sprites[zoneData.type]

    if not colorID or not spriteName then
        print("^1[ATLAS BLIPS]^7 ERROR: Missing config for zone type: " .. zoneData.type)
        return nil
    end

    -- Convert sprite name to hash
    local spriteHash = GetHashKey(spriteName)

    if Config.DebugLogging then
        print(string.format("^3[ATLAS BLIPS]^7   Sprite: %s (hash: %d), Color: %d", spriteName, spriteHash, colorID))
    end

    local radiusBlip = nil
    local spriteBlip = nil

    -- Create RADIUS BLIP (the area circle on the map)
    -- Native: AddBlipForRadius(x, y, z, radius) - 0x45F13B7E0A770A54
    local radiusSuccess = pcall(function()
        radiusBlip = AddBlipForRadius(zoneData.x, zoneData.y, zoneData.z, zoneData.radius)
    end)

    if not radiusSuccess or not radiusBlip or radiusBlip == 0 then
        print("^1[ATLAS BLIPS]^7 ERROR: Failed to create radius blip for " .. zoneData.type .. " zone " .. zoneData.id)

        -- Try fallback: create radius blip at the coords directly
        -- Some RedM builds may behave differently
        radiusSuccess = pcall(function()
            radiusBlip = AddBlipForRadius(zoneData.x, zoneData.y, zoneData.z, zoneData.radius)
        end)

        if not radiusSuccess or not radiusBlip or radiusBlip == 0 then
            print("^1[ATLAS BLIPS]^7 Fallback also failed for radius blip - zone will have icon only")
            radiusBlip = nil
        end
    end

    -- Style the radius blip
    if radiusBlip then
        SetBlipAlpha(radiusBlip, Config.RadiusAlpha)
        SetBlipColour(radiusBlip, colorID)
        -- Don't show the radius blip's own sprite (show it as a circle only)
        SetBlipSprite(radiusBlip, 0, true) -- Sprite 0 with high-altitude flag to make circle-only

        if Config.DebugLogging then
            print("^2[ATLAS BLIPS]^7   Radius blip created: " .. tostring(radiusBlip))
        end
    end

    -- Create SPRITE BLIP (the central icon on the map)
    -- Native: AddBlipForCoord(spriteHash, x, y, z) but in RDR3 we use:
    --   blip = AddBlipForCoord(x, y, z) then SetBlipSprite(blip, hash)
    -- Actually RDR3 has direct: blip = MapBlip(id) but standard CFX approach:
    local spriteSuccess = pcall(function()
        spriteBlip = AddBlipForCoord(zoneData.x, zoneData.y, zoneData.z)
    end)

    if not spriteSuccess or not spriteBlip or spriteBlip == 0 then
        -- Fallback: try the GTA-style MapBlip approach
        spriteSuccess = pcall(function()
            spriteBlip = AddBlipForCoord(zoneData.x, zoneData.y, zoneData.z)
        end)

        if not spriteSuccess or not spriteBlip or spriteBlip == 0 then
            print("^1[ATLAS BLIPS]^7 ERROR: Failed to create sprite blip for " .. zoneData.type .. " zone " .. zoneData.id)
            spriteBlip = nil
        end
    end

    -- Style the sprite blip
    if spriteBlip then
        SetBlipSprite(spriteBlip, spriteHash, true)
        SetBlipColour(spriteBlip, colorID)
        SetBlipScale(spriteBlip, Config.SpriteScale)
        SetBlipAsShortRange(spriteBlip, false) -- Show even at long range
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(zoneData.name)
        EndTextCommandSetBlipName(spriteBlip)

        if Config.DebugLogging then
            print("^2[ATLAS BLIPS]^7   Sprite blip created: " .. tostring(spriteBlip) .. " name: " .. zoneData.name)
        end
    end

    -- Return the blips we created (may have one or both)
    local result = { radiusBlip = radiusBlip, spriteBlip = spriteBlip }

    if not radiusBlip and not spriteBlip then
        print("^1[ATLAS BLIPS]^7 Failed to create ANY blips for " .. zoneData.type .. " zone " .. zoneData.id)
        return nil
    end

    return result
end

-- Remove all active blips from the map
local function RemoveAllBlips()
    if Config.DebugLogging then
        print("^3[ATLAS BLIPS]^7 Removing all active blips...")
    end

    local removedCount = 0
    for zoneKey, blips in pairs(ActiveBlips) do
        if blips.radiusBlip then
            local success = pcall(function()
                RemoveBlip(blips.radiusBlip)
            end)
            if success then
                removedCount = removedCount + 1
            end
        end
        if blips.spriteBlip then
            local success = pcall(function()
                RemoveBlip(blips.spriteBlip)
            end)
            if success then
                removedCount = removedCount + 1
            end
        end
    end

    ActiveBlips = {}

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Removed " .. removedCount .. " blips")
    end
end

-- Remove blips for a specific zone key
local function RemoveZoneBlips(zoneKey)
    local blips = ActiveBlips[zoneKey]
    if not blips then return end

    if blips.radiusBlip then
        pcall(function() RemoveBlip(blips.radiusBlip) end)
    end
    if blips.spriteBlip then
        pcall(function() RemoveBlip(blips.spriteBlip) end)
    end

    ActiveBlips[zoneKey] = nil
end

-- ============================================================
-- PLAYER LOADED / TRIGGER TO REQUEST ZONE DATA
-- ============================================================

-- Send playerLoaded event to server when the player finishes loading
Citizen.CreateThread(function()
    -- Wait for player to be fully loaded
    Citizen.Wait(5000)
    print("^2[ATLAS BLIPS CLIENT]^7 Player loaded - requesting zone data from server")

    local success = pcall(function()
        TriggerServerEvent('atlas_blips:server:playerLoaded')
    end)

    if success then
        print("^2[ATLAS BLIPS CLIENT]^7 playerLoaded event sent to server")
    else
        print("^1[ATLAS BLIPS CLIENT]^7 Failed to trigger playerLoaded event")
    end
end)

-- ============================================================
-- RECEIVE ZONE DATA FROM SERVER
-- ============================================================

RegisterNetEvent('atlas_blips:client:loadZones')
AddEventHandler('atlas_blips:client:loadZones', function(blipPayload)
    print("^2[ATLAS BLIPS]^7 Received " .. #blipPayload .. " zones from server")

    -- Remove all existing blips before recreating
    RemoveAllBlips()

    local miningCount = 0
    local woodcuttingCount = 0
    local failCount = 0

    -- Create blips for each zone
    for _, zoneData in ipairs(blipPayload) do
        local zoneKey = zoneData.type .. "_" .. zoneData.id

        -- Remove any stale blip for this zone key before creating new ones
        RemoveZoneBlips(zoneKey)

        local blips = CreateZoneBlips(zoneData)

        if blips then
            ActiveBlips[zoneKey] = blips
            if zoneData.type == "mining" then
                miningCount = miningCount + 1
            elseif zoneData.type == "woodcutting" then
                woodcuttingCount = woodcuttingCount + 1
            end
        else
            failCount = failCount + 1
        end
    end

    BlipsInitialized = true

    print(string.format("^2[ATLAS BLIPS]^7 Blips created: %d mining, %d woodcutting, %d failed",
        miningCount, woodcuttingCount, failCount))

    print("^2[ATLAS BLIPS]^7 Total active blip zones: " .. tostring(miningCount + woodcuttingCount))

    if Config.DebugLogging then
        print("^5======================================^7")
        print("^5  ATLAS BLIPS CLIENT READY^7")
        print("^5======================================^7")
    end
end)

-- ============================================================
-- COMMAND: Toggle blip visibility for a zone type
-- ============================================================

RegisterCommand('toggleblips', function(source, args)
    local zoneType = args[1] and args[1]:lower()
    if not zoneType or (zoneType ~= "mining" and zoneType ~= "woodcutting") then
        print("^3[ATLAS BLIPS]^7 Usage: /toggleblips [mining|woodcutting]")
        print("^3[ATLAS BLIPS]^7 Current state:")
        print("^3  Mining: ^7" .. tostring(Config.ShowBlips.mining))
        print("^3  Woodcutting: ^7" .. tostring(Config.ShowBlips.woodcutting))
        return
    end

    -- Toggle the config value
    Config.ShowBlips[zoneType] = not Config.ShowBlips[zoneType]
    local isEnabled = Config.ShowBlips[zoneType]

    print(string.format("^2[ATLAS BLIPS]^7 %s blips now: %s", zoneType, isEnabled and "ENABLED" or "DISABLED"))

    -- If enabled, recreate from server; if disabled, remove matching blips
    if isEnabled then
        -- Request full zone data reload from server
        TriggerServerEvent('atlas_blips:server:playerLoaded')
    else
        -- Remove all blips for this zone type
        local removedCount = 0
        for zoneKey, blips in pairs(ActiveBlips) do
            if zoneKey:match("^" .. zoneType .. "_") then
                if blips.radiusBlip then
                    pcall(function() RemoveBlip(blips.radiusBlip) end)
                end
                if blips.spriteBlip then
                    pcall(function() RemoveBlip(blips.spriteBlip) end)
                end
                ActiveBlips[zoneKey] = nil
                removedCount = removedCount + 1
            end
        end
        print(string.format("^2[ATLAS BLIPS]^7 Removed %d %s blip zones", removedCount, zoneType))
    end
end)

-- ============================================================
-- COMMAND: Manually request blip data refresh from server
-- ============================================================

RegisterCommand('refreshblipsclient', function(source, args)
    print("^2[ATLAS BLIPS]^7 Manually requesting blip refresh from server...")
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end)

-- ============================================================
-- RESOURCE STOP CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        print("^2[ATLAS BLIPS]^7 Resource stopping - removing all blips")
        RemoveAllBlips()
    end
end)

-- ============================================================
-- PERIODIC RECONNECT FALLBACK
-- ============================================================

-- If blips aren't initialized after a delay, retry requesting from server
Citizen.CreateThread(function()
    Citizen.Wait(Config.ReconnectBlipDelay + 5000)

    if not BlipsInitialized then
        print("^3[ATLAS BLIPS]^7 Blips not initialized after delay - retrying...")
        pcall(function()
            TriggerServerEvent('atlas_blips:server:playerLoaded')
        end)
    end
end)
