print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded. Registering event handlers...")

local Config = AtlasBlipsConfig

-- ============================================================
-- BLIP STORAGE
-- ============================================================
local ActiveBlips = {}

-- ============================================================
-- RUNTIME SPRITE HASH COMPUTATION
-- ============================================================
local SpriteHashes = {}
SpriteHashes.mining      = GetHashKey(Config.Sprites.mining)
SpriteHashes.woodcutting  = GetHashKey(Config.Sprites.woodcutting)
SpriteHashes.radius       = GetHashKey(Config.Sprites.radius)

-- ============================================================
-- BLIP STYLE HASH
-- ============================================================
-- BlipAddForCoords(0x554D9D53F696D002) takes a STYLE hash as first param,
-- NOT a sprite hash. The style defines the visual behavior/appearance.
-- After creation, SetBlipSprite applies the specific icon.
-- Using BLIP_STYLE_MISSION as a reliable, visible default style.
local BLIP_STYLE_DEFAULT = GetHashKey("BLIP_STYLE_MISSION")

if Config.DebugLogging then
    print("^2[ATLAS BLIPS]^7 Computed sprite hashes:")
    print("  mining:        " .. SpriteHashes.mining .. " (from '" .. Config.Sprites.mining .. "')")
    print("  woodcutting:   " .. SpriteHashes.woodcutting .. " (from '" .. Config.Sprites.woodcutting .. "')")
    print("  radius:        " .. SpriteHashes.radius .. " (from '" .. Config.Sprites.radius .. "')")
    print("  style_default: " .. BLIP_STYLE_DEFAULT .. " (from 'BLIP_STYLE_MISSION')")
end

-- ============================================================
-- RDR2 NATIVE HELPERS
-- ============================================================
-- All natives confirmed from @nativewrappers/redm-codegen (Map.ts)
-- and cross-referenced with kibook/redm-blips and femga/rdr3_discoveries.

local function RDR_CreateBlipAtCoords(x, y, z)
    -- BlipAddForCoords: creates a blip at world coordinates using a style
    -- hash. Returns the blip handle, or 0/false on failure.
    -- Native: 0x554D9D53F696D002 (styleHash, x, y, z)
    -- Reference: @nativewrappers/redm-codegen Map.ts blipAddForCoords()
    return Citizen.InvokeNative(0x554D9D53F696D002, BLIP_STYLE_DEFAULT, x, y, z)
end

local function RDR_CreateRadiusBlip(radiusHash, x, y, z, radius)
    -- BlipAddForRadius: creates a radius-type blip (shaded circle zone).
    -- Different native from BlipAddForCoords — designed for area display.
    -- Native: 0x45F13B7E0A15C880 (blipHash, x, y, z, radius)
    -- Reference: @nativewrappers/redm-codegen Map.ts blipAddForRadius()
    return Citizen.InvokeNative(0x45F13B7E0A15C880, radiusHash, x, y, z, radius)
end

local function RDR_RemoveBlip(blip)
    if blip and blip ~= 0 then
        -- AbandonBlip: marks the blip as no longer needed for cleanup.
        -- Native: 0xDEEDE7C41742E011 (blip)
        -- Reference: @nativewrappers/redm-codegen Map.ts abandonBlip()
        Citizen.InvokeNative(0xDEEDE7C41742E011, blip)
    end
end

local function RDR_SetBlipName(blip, name)
    -- SetBlipNameFromPlayerString: sets the blip's hover label.
    -- Accepts a raw string name (NOT CreateVarString).
    -- Native: 0x9CB1A1623062F402 (blip, nameString)
    -- Reference: kibook/redm-blips SetBlipNameFromPlayerString()
    --            femga/rdr3_discoveries addBlipForCoords() example
    --            @nativewrappers/redm-codegen Map.ts setBlipName()
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name)
end

local function RDR_SetBlipSprite(blip, spriteHash, toggle)
    -- SetBlipSprite: applies the actual icon texture to a blip.
    -- Called AFTER BlipAddForCoords to set the visible icon.
    -- Native: 0x74F74D3207ED525C (blip, hash, toggle)
    -- Reference: @nativewrappers/redm-codegen Map.ts setBlipSprite()
    --            femga/rdr3_discoveries: hash confirmed as 0x74F74D3207ED525C
    Citizen.InvokeNative(0x74F74D3207ED525C, blip, spriteHash, toggle or true)
end

local function RDR_SetBlipColour(blip, colour)
    -- SetBlipColour: palette index (0-255), NOT hex ARGB.
    -- Native: 0x03D7FB09E75D6B7E
    Citizen.InvokeNative(0x03D7FB09E75D6B7E, blip, colour)
end

local function RDR_SetBlipScale(blip, scale)
    -- SetBlipScale
    -- Native: 0xD38744167B2FA257
    Citizen.InvokeNative(0xD38744167B2FA257, blip, scale)
end

local function RDR_SetBlipAlpha(blip, alpha)
    -- SetBlipAlpha (0-255)
    -- Native: 0x45FF974EEE1C8734
    Citizen.InvokeNative(0x45FF974EEE1C8734, blip, alpha)
end

local function RDR_SetBlipRadius(blip, radius)
    -- Sets the radius display size for a radius-type blip sprite.
    -- Must be called AFTER creation and AFTER SetBlipDisplay.
    -- Native: 0x340CF8A9750E9669
    Citizen.InvokeNative(0x340CF8A9750E9669, blip, radius)
end

local function RDR_SetBlipDisplay(blip, displayType)
    -- Sets WHERE the blip appears: 0=hidden, 2=main map, 3=both
    -- Native: 0xA1509A8E850B0347 (RDR2 hash for SetBlipDisplay)
    Citizen.InvokeNative(0xA1509A8E850B0347, blip, displayType)
end

-- ============================================================
-- BLIP CREATION
-- ============================================================

--- Creates a single zone blip pair on the map.
--- Sequence:
---   1. CreateBlipAtCoords with STYLE hash → gets blip handle
---   2. SetBlipSprite to apply the actual icon
---   3. SetBlipName for the hover label
---   4. SetBlipColour, SetBlipScale for appearance
---   5. CreateRadiusBlip for the zone circle
--- Returns { spriteBlip, radiusBlip } or nil on failure.
local function CreateZoneBlip(zoneData)
    local zoneType    = zoneData.type
    local zoneName    = zoneData.name or (zoneType .. " Zone")
    local x, y, z     = zoneData.x, zoneData.y, zoneData.z
    local radius      = zoneData.radius or 100.0
    local spriteHash  = SpriteHashes[zoneType]
    local colorIndex  = Config.Colors[zoneType] or 8

    if not Config.ShowBlips[zoneType] then
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7 Skipping " .. zoneType .. " zone '" .. zoneName .. "' (disabled)")
        end
        return nil
    end

    -- ============================================================
    -- STEP 1: CREATE BLIP (style-based, NOT sprite-based)
    -- ============================================================
    local spriteBlip = RDR_CreateBlipAtCoords(x, y, z)

    -- Validate handle: a valid blip handle is a non-zero integer
    if not spriteBlip or spriteBlip == 0 then
        print("^1[ATLAS BLIPS]^7 ERROR: CreateBlipAtCoords failed for " .. zoneType .. " '" .. zoneName .. "'")
        return nil
    end

    -- Step 1b: Apply the sprite icon to the style-created blip
    RDR_SetBlipSprite(spriteBlip, spriteHash, true)

    -- Step 1c: Set the name (hover label)
    RDR_SetBlipName(spriteBlip, zoneName)

    -- Step 1d: Color and scale
    RDR_SetBlipColour(spriteBlip, colorIndex)
    RDR_SetBlipScale(spriteBlip, Config.SpriteScale)

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Created sprite blip handle=" .. tostring(spriteBlip) ..
              " name='" .. zoneName .. "' type=" .. zoneType ..
              " spriteHash=" .. spriteHash .. " color=" .. colorIndex)
    end

    -- ============================================================
    -- STEP 2: CREATE RADIUS BLIP (the colored zone circle)
    -- ============================================================
    local radiusBlip = RDR_CreateRadiusBlip(SpriteHashes.radius, x, y, z, radius)

    if radiusBlip and radiusBlip ~= 0 then
        -- CRITICAL: Must call SetBlipDisplay or the radius circle is invisible
        RDR_SetBlipDisplay(radiusBlip, 3)   -- 3 = visible on minimap AND world map
        RDR_SetBlipRadius(radiusBlip, radius)
        RDR_SetBlipColour(radiusBlip, colorIndex)
        RDR_SetBlipAlpha(radiusBlip, Config.RadiusAlpha)
        RDR_SetBlipScale(radiusBlip, 0.01)   -- Keep anchor point tiny

        if Config.DebugLogging then
            print("^2[ATLAS BLIPS]^7   + radius blip handle=" .. tostring(radiusBlip) ..
                  " r=" .. radius .. " alpha=" .. Config.RadiusAlpha ..
                  " color=" .. colorIndex .. " display=3")
        end
    else
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7   radius blip creation returned nil/0 (may be normal)")
        end
    end

    return { spriteBlip = spriteBlip, radiusBlip = radiusBlip }
end

-- ============================================================
-- BLIP REMOVAL
-- ============================================================
local function RemoveZoneBlip(blipPair)
    if not blipPair then return end
    RDR_RemoveBlip(blipPair.spriteBlip)
    if blipPair.radiusBlip and blipPair.radiusBlip ~= 0 then
        RDR_RemoveBlip(blipPair.radiusBlip)
    end
end

local function RemoveAllBlips()
    for _, blipPair in pairs(ActiveBlips) do
        RemoveZoneBlip(blipPair)
    end
    ActiveBlips = {}
    if Config.DebugLogging then
        print("^3[ATLAS BLIPS]^7 All blips removed")
    end
end

-- ============================================================
-- EVENT: LOAD ZONES FROM SERVER
-- ============================================================
RegisterNetEvent('atlas_blips:client:loadZones')
AddEventHandler('atlas_blips:client:loadZones', function(blipPayload)
    print("^2[ATLAS BLIPS]^7 Received " .. #blipPayload .. " zones from server")

    RemoveAllBlips()

    local created = 0
    for _, zoneData in ipairs(blipPayload) do
        local blipPair = CreateZoneBlip(zoneData)
        if blipPair then
            ActiveBlips[blipPair.spriteBlip] = blipPair
            created = created + 1
        end
    end

    print("^2[ATLAS BLIPS]^7 Created " .. created .. " of " .. #blipPayload .. " zone blips on the map")
end)

-- ============================================================
-- PLAYER INITIALIZATION
-- ============================================================
Citizen.CreateThread(function()
    if Config.DebugLogging then
        print("^3[ATLAS BLIPS]^7 Player init thread. Waiting " .. Config.ReconnectBlipDelay .. "ms...")
    end
    Citizen.Wait(Config.ReconnectBlipDelay)
    print("^2[ATLAS BLIPS]^7 Requesting zone data from server...")
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end)

-- ============================================================
-- ADMIN COMMAND: Manual refresh
-- ============================================================
RegisterCommand('refreshblips', function()
    print("^2[ATLAS BLIPS]^7 Manual refresh triggered")
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
