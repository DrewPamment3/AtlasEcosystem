print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded. Registering event handlers...")

local Config = AtlasBlipsConfig

-- ============================================================
-- BLIP STORAGE
-- ============================================================
local ActiveBlips = {} -- {zoneId = {spriteBlip, radiusBlip}}

-- ============================================================
-- RUNTIME SPRITE HASH COMPUTATION
-- ============================================================
-- Joaat() the sprite names ONCE at load time so we have the correct integer hashes.
local function joaat(str)
    -- Cfx native GetHashKey uses the same Joaat algorithm.
    -- This local implementation avoids an extra native call per blip creation.
    -- But we CAN just call GetHashKey() directly -- it's simpler and safer.
    -- We'll use the native version.
    return GetHashKey(str)
end

local SpriteHashes = {}
SpriteHashes.mining      = joaat(Config.Sprites.mining)
SpriteHashes.woodcutting  = joaat(Config.Sprites.woodcutting)
SpriteHashes.radius       = joaat(Config.Sprites.radius)

if Config.DebugLogging then
    print("^2[ATLAS BLIPS]^7 Computed sprite hashes:")
    print("  mining:        " .. SpriteHashes.mining .. " (from '" .. Config.Sprites.mining .. "')")
    print("  woodcutting:   " .. SpriteHashes.woodcutting .. " (from '" .. Config.Sprites.woodcutting .. "')")
    print("  radius:        " .. SpriteHashes.radius .. " (from '" .. Config.Sprites.radius .. "')")
end

-- ============================================================
-- BLIP CREATION
-- ============================================================

-- Creates a single zone blip pair (icon blip + radius blip) on the map.
-- Returns { spriteBlip, radiusBlip } or nil on failure.
local function CreateZoneBlip(zoneData)
    local zoneType    = zoneData.type
    local zoneName    = zoneData.name or "Unknown"
    local x, y, z     = zoneData.x, zoneData.y, zoneData.z
    local radius      = zoneData.radius or 100.0
    local spriteHash  = SpriteHashes[zoneType]
    local colorIndex  = Config.Colors[zoneType] or 8  -- Default: Grey (0-indexed palette integer)

    if not Config.ShowBlips[zoneType] then
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7 Skipping " .. zoneType .. " zone '" .. zoneName .. "' (ShowBlips disabled)")
        end
        return nil
    end

    -- ============================================================
    -- STEP 1: CREATE THE ICON BLIP (the little icon on the map)
    -- ============================================================
    -- RDR2 CreateBlip signature: CreateBlip(blipHash, x, y, z)
    local spriteBlip = CreateBlip(spriteHash, x, y, z)
    if spriteBlip == 0 then
        print("^1[ATLAS BLIPS]^7 ERROR: CreateBlip returned 0 for " .. zoneType .. " '" .. zoneName .. "' at (" .. x .. ", " .. y .. ", " .. z .. ")")
        print("^1[ATLAS BLIPS]^7 Sprite hash used: " .. spriteHash .. " (from '" .. (Config.Sprites[zoneType] or "nil") .. "')")
        return nil
    end

    -- STEP 1b: Set a label (appears when hovering on the map)
    SetBlipName(spriteBlip, zoneName)

    -- ============================================================
    -- STEP 2: SET BLIP DISPLAY (CRITICAL - THIS WAS MISSING!)
    -- ============================================================
    -- Without this call, the blip EXISTS but is INVISIBLE.
    -- RDR2 BlipDisplayType values:
    --   0 = Don't Display (hidden)
    --   1 = Display on minimap only
    --   2 = Display on world map only
    --   3 = Display on both minimap AND world map (what we want)
    SetBlipDisplay(spriteBlip, 3)  -- ⬅ THIS IS WHY BLIPS WERE NEVER VISIBLE

    -- STEP 2b: Set the color index (palette index, NOT ARGB hex!)
    SetBlipColour(spriteBlip, colorIndex)

    -- STEP 2c: Set the scale
    SetBlipScale(spriteBlip, Config.SpriteScale)

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Created sprite blip: " .. zoneName .. " (type=" .. zoneType .. ", hash=" .. spriteHash .. ", color=" .. colorIndex .. ")")
    end

    -- ============================================================
    -- STEP 3: CREATE THE RADIUS BLIP (the shaded circle showing zone area)
    -- ============================================================
    local radiusBlip = CreateBlip(SpriteHashes.radius, x, y, z)
    if radiusBlip ~= 0 then
        SetBlipDisplay(radiusBlip, 3)
        SetBlipRadius(radiusBlip, radius)
        SetBlipAlpha(radiusBlip, Config.RadiusAlpha)
        SetBlipColour(radiusBlip, colorIndex)

        -- Match the sprite blip's scale so the radius anchor point is tiny
        SetBlipScale(radiusBlip, 0.1)

        if Config.DebugLogging then
            print("^2[ATLAS BLIPS]^7   + radius: " .. radius .. "m, alpha=" .. Config.RadiusAlpha)
        end
    else
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7   radius blip creation failed (this is sometimes normal)")
        end
    end

    return { spriteBlip = spriteBlip, radiusBlip = radiusBlip }
end

-- Removes a zone blip pair from the map.
local function RemoveZoneBlip(blipPair)
    if not blipPair then return end

    if blipPair.spriteBlip and blipPair.spriteBlip ~= 0 then
        RemoveBlip(blipPair.spriteBlip)
    end
    if blipPair.radiusBlip and blipPair.radiusBlip ~= 0 then
        RemoveBlip(blipPair.radiusBlip)
    end
end

-- Removes all active blips.
local function RemoveAllBlips()
    for zoneId, blipPair in pairs(ActiveBlips) do
        RemoveZoneBlip(blipPair)
    end
    ActiveBlips = {}
    print("^3[ATLAS BLIPS]^7 All blips removed")
end

-- ============================================================
-- EVENT: LOAD ZONES FROM SERVER
-- ============================================================
-- Fired by the server when:
--   (a) The player's character loads AND
--   (b) The server has finished loading zone data from the database
RegisterNetEvent('atlas_blips:client:loadZones')
AddEventHandler('atlas_blips:client:loadZones', function(blipPayload)
    print("^2[ATLAS BLIPS]^7 Received " .. #blipPayload .. " zones from server")

    -- Remove existing blips first (handles reconnection or manual refresh)
    RemoveAllBlips()

    -- Create blips for each zone
    local created = 0
    for _, zoneData in ipairs(blipPayload) do
        local blipPair = CreateZoneBlip(zoneData)
        if blipPair then
            ActiveBlips[zoneData.type .. "_" .. zoneData.id] = blipPair
            created = created + 1
        end
    end

    print("^2[ATLAS BLIPS]^7 Created " .. created .. " of " .. #blipPayload .. " zone blips on the map")
end)

-- ============================================================
-- PLAYER INITIALIZATION
-- ============================================================
-- RDR2/VORP doesn't always have a reliable client-side "character loaded"
-- event, but we MUST wait for the character to be selected before
-- requesting zone data (otherwise the server-side `source` won't match a
-- valid character).
--
-- Strategy: Wait a few seconds, then request zone data from the server.
-- The server's event handler (atlas_blips:server:playerLoaded) validates
-- the character internally.

Citizen.CreateThread(function()
    if Config.DebugLogging then
        print("^3[ATLAS BLIPS]^7 Player init thread started. Waiting " .. Config.ReconnectBlipDelay .. "ms before requesting zones...")
    end

    Citizen.Wait(Config.ReconnectBlipDelay)

    print("^2[ATLAS BLIPS]^7 Requesting zone data from server...")
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end)

-- ============================================================
-- ADMIN COMMAND: Manual refresh
-- ============================================================
RegisterCommand('refreshblips', function()
    print("^2[ATLAS BLIPS]^7 Manual refresh requested")
    RemoveAllBlips()
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end, false)

-- ============================================================
-- RESOURCE STOP (cleanup)
-- ============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        RemoveAllBlips()
    end
end)

print("^2[ATLAS BLIPS CLIENT]^7 Ready. Waiting for zone data from server...")
