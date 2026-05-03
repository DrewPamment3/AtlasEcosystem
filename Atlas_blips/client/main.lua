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

    -- Hash the string names at RUNTIME using the game engine's GetHashKey
    -- This avoids compile-time backtick hashing producing wrong values
    local colorName = Config.Colors[zoneData.type]
    local spriteName = Config.Sprites[zoneData.type]
    local radiusName = Config.Sprites.radius

    if not colorName or not spriteName then
        print("^1[ATLAS BLIPS]^7 ERROR: Missing config for zone type: " .. zoneData.type)
        return nil
    end

    local colorHash = GetHashKey(colorName)
    local spriteHash = GetHashKey(spriteName)
    local radiusHash = GetHashKey(radiusName)

    if Config.DebugLogging then
        print(string.format("^3[ATLAS BLIPS]^7   Sprite: '%s' -> 0x%X, Color: '%s' -> 0x%X, Radius: '%s' -> 0x%X",
            spriteName, spriteHash, colorName, colorHash, radiusName, radiusHash))
    end

    -- ========================================================
    -- 1. Create RADIUS BLIP (The Area Circle)
    -- Native: 0x45F13B7E0A770A54 (ADD_BLIP_FOR_RADIUS)
    -- RDR3 Signature: (float x, float y, float z, float radius)
    -- ========================================================
    local radiusBlip = nil
    local radiusSuccess = pcall(function()
        radiusBlip = AddBlipForRadius(zoneData.x, zoneData.y, zoneData.z, zoneData.radius)
    end)

    if not radiusSuccess or not radiusBlip or radiusBlip == 0 then
        print("^1[ATLAS BLIPS]^7 WARNING: Failed to create radius blip for " .. zoneData.type .. " zone " .. zoneData.id)
        radiusBlip = nil
    end

    -- Style the radius blip
    if radiusBlip then
        SetBlipSprite(radiusBlip, radiusHash, true) -- Set as radius/circle type
        SetBlipColour(radiusBlip, colorHash)
        SetBlipAlpha(radiusBlip, Config.RadiusAlpha)

        if Config.DebugLogging then
            print("^2[ATLAS BLIPS]^7   Radius blip created: " .. tostring(radiusBlip))
        end
    end

    -- ========================================================
    -- 2. Create SPRITE BLIP (The Icon)
    -- Native: 0x554D9D53F696D002 (ADD_BLIP_FOR_COORD)
    -- RDR3 Signature: (Hash blipHash, float x, float y, float z)
    -- ========================================================
    local spriteBlip = nil
    local spriteSuccess = pcall(function()
        spriteBlip = AddBlipForCoord(spriteHash, zoneData.x, zoneData.y, zoneData.z)
    end)

    if not spriteSuccess or not spriteBlip or spriteBlip == 0 then
        print("^1[ATLAS BLIPS]^7 ERROR: Failed to create sprite blip for " .. zoneData.type .. " zone " .. zoneData.id)
        spriteBlip = nil
    end

    -- Style the sprite blip
    if spriteBlip then
        SetBlipColour(spriteBlip, colorHash)
        SetBlipScale(spriteBlip, Config.SpriteScale)

        -- Set the Name (RDR3 Native: 0x9CB1A1623062F402)
        -- SetBlipNameFromPlayerName is the RDR3 standard for assigning a string label
        Citizen.InvokeNative(0x9CB1A1623062F402, spriteBlip, zoneData.name)

        if Config.DebugLogging then
            print("^2[ATLAS BLIPS]^7   Sprite blip created: " .. tostring(spriteBlip) .. " name: " .. zoneData.name)
        end
    end

    -- ========================================================
    -- Return result
    -- ========================================================
    local result = { radiusBlip = radiusBlip, spriteBlip = spriteBlip }

    if not radiusBlip and not spriteBlip then
        print("^1[ATLAS BLIPS]^7 Failed to create ANY blips for " .. zoneData.type .. " zone " .. zoneData.id)
        return nil
    end

    return result
end

-- ============================================================
-- BLIP CATEGORY VISIBILITY (Toggle without deleting/recreating)
-- ============================================================

local function SetCategoryVisibility(category, visible)
    local displayMode = visible and 2 or 0 -- 2 is visible, 0 is hidden (RDR3 SetBlipDisplay)
    local count = 0
    for zoneKey, blips in pairs(ActiveBlips) do
        if zoneKey:match("^" .. category .. "_") then
            if blips.radiusBlip then
                SetBlipDisplay(blips.radiusBlip, displayMode)
            end
            if blips.spriteBlip then
                SetBlipDisplay(blips.spriteBlip, displayMode)
            end
            count = count + 1
        end
    end
    if Config.DebugLogging then
        print(string.format("^2[ATLAS BLIPS]^7 Set %d %s zones to visibility mode %d", count, category, displayMode))
    end
end

-- ============================================================
-- BLIP REMOVAL FUNCTIONS
-- ============================================================

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

    -- Use SetBlipDisplay to toggle visibility without deleting blips
    SetCategoryVisibility(zoneType, isEnabled)
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
