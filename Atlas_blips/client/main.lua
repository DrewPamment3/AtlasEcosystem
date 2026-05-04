print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded. Registering event handlers...")

local Config = AtlasBlipsConfig

-- ============================================================
-- BLIP STORAGE
-- ============================================================
local ActiveBlips = {} -- {zoneId = {spriteBlip, radiusBlip}}

-- ============================================================
-- RUNTIME SPRITE HASH COMPUTATION
-- ============================================================
-- Joaat() the sprite names ONCE at load time so we have correct integer hashes.
local SpriteHashes = {}
SpriteHashes.mining      = GetHashKey(Config.Sprites.mining)
SpriteHashes.woodcutting  = GetHashKey(Config.Sprites.woodcutting)
SpriteHashes.radius       = GetHashKey(Config.Sprites.radius)

if Config.DebugLogging then
    print("^2[ATLAS BLIPS]^7 Computed sprite hashes:")
    print("  mining:        " .. SpriteHashes.mining .. " (from '" .. Config.Sprites.mining .. "')")
    print("  woodcutting:   " .. SpriteHashes.woodcutting .. " (from '" .. Config.Sprites.woodcutting .. "')")
    print("  radius:        " .. SpriteHashes.radius .. " (from '" .. Config.Sprites.radius .. "')")
end

-- ============================================================
-- RDR2 NATIVE HELPERS
-- ============================================================
-- RDR2 does not expose named Lua functions like CreateBlip() or SetBlipDisplay().
-- Instead it uses Citizen.InvokeNative with hash values from the RDR2 native table.
--
-- The native hashes for blips are DIFFERENT than GTA V. Here are the confirmed
-- RDR2 hashes from https://alloc8or.re/rdr3/nativedb/:

local function RDR_CreateBlip(spriteHash, x, y, z)
    -- RADAR::BlipAddForCoord(spriteHash, x, y, z)
    -- Confirmed RDR2 hash from kibook/redm-blips and alloc8or.re
    return Citizen.InvokeNative(0x554D9D53F696D002, spriteHash, x, y, z)
end

local function RDR_RemoveBlip(blip)
    if blip and blip ~= 0 then
        -- RADAR::_0x86A652570E5F25DD(blip) — RDR2 RemoveBlip
        Citizen.InvokeNative(0x86A652570E5F25DD, blip)
    end
end

local function RDR_SetBlipName(blip, name)
    -- RADAR::SetBlipNameFromPlayerString(blip, varString)
    -- Uses CreateVarString (NOT VarString!) to build the string parameter
    local str = CreateVarString(10, "LITERAL_STRING", name)
    Citizen.InvokeNative(0xE4B10E5A20F3E9A2, blip, str)
end

local function RDR_SetBlipSprite(blip, spriteHash, toggle)
    -- RADAR::SET_BLIP_SPRITE(blip, spriteHash, toggle)
    -- RDR2 hash: 0x74F74D3207AD5EE5
    Citizen.InvokeNative(0x74F74D3207AD5EE5, blip, spriteHash, toggle or true)
end

local function RDR_SetBlipDisplay(blip, displayType)
    -- RADAR::SET_BLIP_DISPLAY(blip, displayType)
    -- GTA V hash: 0x9029B2F3DA924928
    -- displayType: 0=hidden, 1=minimap, 2=world map, 3=both
    Citizen.InvokeNative(0x9029B2F3DA924928, blip, displayType)
end

local function RDR_SetBlipColour(blip, colour)
    -- RADAR::SET_BLIP_COLOUR(blip, colour)
    -- GTA V hash: 0x03D7FB09E75D6B7E
    -- colour is a palette INDEX (0-255), NOT hex ARGB
    Citizen.InvokeNative(0x03D7FB09E75D6B7E, blip, colour)
end

local function RDR_SetBlipScale(blip, scale)
    -- RADAR::SET_BLIP_SCALE(blip, scale)
    -- GTA V hash: 0xD38744167B2FA257
    Citizen.InvokeNative(0xD38744167B2FA257, blip, scale)
end

local function RDR_SetBlipAlpha(blip, alpha)
    -- RADAR::SET_BLIP_ALPHA(blip, alpha)
    -- GTA V hash: 0x45FF974EEE1C8734
    -- alpha: 0-255
    Citizen.InvokeNative(0x45FF974EEE1C8734, blip, alpha)
end

local function RDR_SetBlipRadius(blip, radius)
    -- RADAR::_0x340CF8A9750E9669(blip, radius)
    -- This sets the radius for radius-type blips
    Citizen.InvokeNative(0x340CF8A9750E9669, blip, radius)
end

local function RDR_SetBlipVisibleOnMap(blip, toggle)
    -- RADAR::SET_BLIP_HIDDEN_ON_LEGEND(blip, toggle)
    -- We want it VISIBLE, so we pass FALSE to SET_BLIP_HIDDEN = it IS shown
    -- RDR2 hash: 0x9E55299D23E4138C
    Citizen.InvokeNative(0x9E55299D23E4138C, blip, not toggle)
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
    local colorIndex  = Config.Colors[zoneType] or 8  -- Default: Grey (palette index)

    if not Config.ShowBlips[zoneType] then
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7 Skipping " .. zoneType .. " zone '" .. zoneName .. "' (ShowBlips disabled)")
        end
        return nil
    end

    -- ============================================================
    -- STEP 1: CREATE THE ICON BLIP
    -- ============================================================
    -- RDR2: Citizen.InvokeNative(0x554D9D53F696D002, spriteHash, x, y, z, 0)
    local spriteBlip = RDR_CreateBlip(spriteHash, x, y, z)

    if spriteBlip == 0 then
        print("^1[ATLAS BLIPS]^7 ERROR: CreateBlip returned 0 for " .. zoneType .. " '" .. zoneName .. "' at (" .. x .. ", " .. y .. ", " .. z .. ")")
        print("^1[ATLAS BLIPS]^7 Sprite hash used: " .. spriteHash .. " (const = " .. (Config.Sprites[zoneType] or "nil") .. ")")
        return nil
    end

    -- STEP 1b: Name the blip (appears on hover)
    RDR_SetBlipName(spriteBlip, zoneName)

    -- STEP 1c: ⬅ CRITICAL: Must set display or blip stays hidden!
    -- displayType=3 means visible on minimap AND world map
    RDR_SetBlipDisplay(spriteBlip, 3)

    -- STEP 1d: Color (palette index)
    RDR_SetBlipColour(spriteBlip, colorIndex)

    -- STEP 1e: Scale (RDR2 blips are large; 0.3-0.6 is a reasonable size)
    RDR_SetBlipScale(spriteBlip, Config.SpriteScale)

    -- STEP 1f: Ensure it's visible on the legend
    RDR_SetBlipVisibleOnMap(spriteBlip, true)

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Created sprite blip handle=" .. spriteBlip .. " name=" .. zoneName .. " type=" .. zoneType .. " hash=" .. spriteHash)
    end

    -- ============================================================
    -- STEP 2: CREATE THE RADIUS BLIP (shaded circle)
    -- ============================================================
    local radiusBlip = RDR_CreateBlip(SpriteHashes.radius, x, y, z)
    if radiusBlip ~= 0 then
        RDR_SetBlipDisplay(radiusBlip, 3)
        RDR_SetBlipRadius(radiusBlip, radius)
        RDR_SetBlipAlpha(radiusBlip, Config.RadiusAlpha)
        RDR_SetBlipColour(radiusBlip, colorIndex)
        RDR_SetBlipScale(radiusBlip, 0.1)
        RDR_SetBlipVisibleOnMap(radiusBlip, true)

        if Config.DebugLogging then
            print("^2[ATLAS BLIPS]^7   + radius: " .. radius .. "m, alpha=" .. Config.RadiusAlpha)
        end
    else
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7   radius blip creation returned 0 (may be normal for this sprite type)")
        end
    end

    return { spriteBlip = spriteBlip, radiusBlip = radiusBlip }
end

-- Removes a zone blip pair from the map.
local function RemoveZoneBlip(blipPair)
    if not blipPair then return end
    RDR_RemoveBlip(blipPair.spriteBlip)
    RDR_RemoveBlip(blipPair.radiusBlip)
end

-- Removes all active blips.
local function RemoveAllBlips()
    for zoneId, blipPair in pairs(ActiveBlips) do
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

    -- Remove existing blips first (handles reconnection or manual refresh)
    RemoveAllBlips()

    -- Create blips for each zone
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
