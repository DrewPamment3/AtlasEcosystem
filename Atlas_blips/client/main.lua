print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded. Registering event handlers...")

local Config = AtlasBlipsConfig

-- ============================================================
-- BLIP STORAGE
-- ============================================================
local ActiveBlips = {} -- {zoneKey = {spriteBlip, radiusBlip}}

-- ============================================================
-- RUNTIME HASH COMPUTATION
-- ============================================================

-- Sprite hashes (icon textures)
local SpriteHashes = {
    mining      = GetHashKey("blip_ambient_pickaxe"),   -- -1397823383
    woodcutting = GetHashKey("blip_event_appleseed"),   -- 1904459580
    radius      = GetHashKey("blip_radius_search"),     -- 150441873 (confirmed in femga rdr3_discoveries)
}

-- Style hashes (visual behavior category for BlipAddForCoord)
local BLIP_STYLE_MISSION = GetHashKey("BLIP_STYLE_MISSION")   -- For icon blips
local BLIP_STYLE_RADIUS  = GetHashKey("BLIP_STYLE_RADIUS")    -- For zone circle blips

if Config.DebugLogging then
    print("^2[ATLAS BLIPS]^7 Computed hashes:")
    print("  Sprite mining:     " .. SpriteHashes.mining)
    print("  Sprite woodcutting: " .. SpriteHashes.woodcutting)
    print("  Sprite radius:     " .. SpriteHashes.radius)
    print("  Style mission:     " .. BLIP_STYLE_MISSION)
    print("  Style radius:      " .. BLIP_STYLE_RADIUS)
end

-- ============================================================
-- RDR2 NATIVE HELPERS
-- ============================================================
-- All confirmed from femga/rdr3_discoveries and kibook/redm-blips

local function RDR_BlipAddForCoord(styleHash, x, y, z)
    -- Creates a blip at world coords with a style hash (NOT a sprite hash).
    -- Returns blip handle, or 0 on failure.
    -- Native: 0x554D9D53F696D002
    return Citizen.InvokeNative(0x554D9D53F696D002, styleHash, x, y, z)
end

local function RDR_SetBlipSprite(blip, spriteHash, toggle)
    -- Applies the icon texture. Called AFTER BlipAddForCoord.
    -- Native: 0x74F74D3207ED525C
    Citizen.InvokeNative(0x74F74D3207ED525C, blip, spriteHash, toggle or true)
end

local function RDR_SetBlipName(blip, name)
    -- Sets the hover label. Accepts raw Lua string (NOT CreateVarString).
    -- Native: 0x9CB1A1623062F402
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name)
end

local function RDR_SetBlipDisplay(blip, displayType)
    -- 0=hidden, 2=main map, 3=both minimap + world map
    -- Native: 0xA1509A8E850B0347
    Citizen.InvokeNative(0xA1509A8E850B0347, blip, displayType)
end

local function RDR_SetBlipColour(blip, colourIndex)
    -- palette index (0-255), NOT hex ARGB
    -- Native: 0x03D7FB09E75D6B7E
    Citizen.InvokeNative(0x03D7FB09E75D6B7E, blip, colourIndex)
end

local function RDR_SetBlipScale(blip, scale)
    -- Native: 0xD38744167B2FA257
    Citizen.InvokeNative(0xD38744167B2FA257, blip, scale)
end

local function RDR_SetBlipAlpha(blip, alpha)
    -- 0-255
    -- Native: 0x45FF974EEE1C8734
    Citizen.InvokeNative(0x45FF974EEE1C8734, blip, alpha)
end

local function RDR_SetBlipRadius(blip, radius)
    -- Defines the circle radius for radius-type blip sprites.
    -- Must be called AFTER creation and SetBlipDisplay.
    -- Native: 0x340CF8A9750E9669
    Citizen.InvokeNative(0x340CF8A9750E9669, blip, radius)
end

local function RDR_RemoveBlip(blip)
    if blip and blip ~= 0 then
        -- AbandonBlip
        -- Native: 0xDEEDE7C41742E011
        Citizen.InvokeNative(0xDEEDE7C41742E011, blip)
    end
end

-- ============================================================
-- BLIP CREATION
-- ============================================================

--- Creates a single zone's blip pair: icon blip + radius circle.
--- @param zoneData table {type, name, x, y, z, radius, id}
--- @return table|nil {spriteBlip, radiusBlip}
local function CreateZoneBlip(zoneData)
    local zoneType   = zoneData.type
    local zoneName   = zoneData.name or (zoneType .. " Zone")
    local x, y, z    = zoneData.x, zoneData.y, zoneData.z
    local radius     = zoneData.radius or 100.0
    local spriteHash = SpriteHashes[zoneType]
    local colorIdx   = Config.Colors[zoneType] or 8

    if not Config.ShowBlips[zoneType] then
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7 Skipping " .. zoneType .. " '" .. zoneName .. "' (ShowBlips disabled)")
        end
        return nil
    end

    -- ============================================================
    -- ICON BLIP (the visible icon on the map)
    -- ============================================================
    local spriteBlip = RDR_BlipAddForCoord(BLIP_STYLE_MISSION, x, y, z)
    if not spriteBlip or spriteBlip == 0 then
        print("^1[ATLAS BLIPS]^7 ERROR: Failed to create icon blip for " .. zoneType .. " '" .. zoneName .. "'")
        return nil
    end

    RDR_SetBlipSprite(spriteBlip, spriteHash, true)
    RDR_SetBlipName(spriteBlip, zoneName)
    RDR_SetBlipDisplay(spriteBlip, 3)     -- Show on minimap + world map
    RDR_SetBlipColour(spriteBlip, colorIdx)
    RDR_SetBlipScale(spriteBlip, Config.SpriteScale)

    -- ============================================================
    -- RADIUS INDICATOR (applied to the icon blip itself)
    -- ============================================================
    -- Apply a colored shaded circle around the icon showing the zone boundary.
    -- Pattern: radius is added as a property of the icon blip, not a separate entity.
    -- Alpha set to 255 (fully opaque) because dark colors (brown/grey)
    -- need full opacity to show against the dark map background.
    RDR_SetBlipRadius(spriteBlip, radius)
    RDR_SetBlipAlpha(spriteBlip, 255)

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Icon: handle=" .. spriteBlip ..
              " name='" .. zoneName .. "' sprite=" .. spriteHash ..
              " color=" .. colorIdx .. " radius=" .. radius)
    end

    return { spriteBlip = spriteBlip, radiusBlip = nil }
end

-- ============================================================
-- CLEANUP
-- ============================================================

local function RemoveZoneBlip(blipPair)
    if not blipPair then return end
    RDR_RemoveBlip(blipPair.spriteBlip)
    if blipPair.radiusBlip and blipPair.radiusBlip ~= 0 then
        RDR_RemoveBlip(blipPair.radiusBlip)
    end
end

local function RemoveAllBlips()
    for _, pair in pairs(ActiveBlips) do
        RemoveZoneBlip(pair)
    end
    ActiveBlips = {}
end

-- ============================================================
-- EVENT: LOAD ZONES
-- ============================================================
RegisterNetEvent('atlas_blips:client:loadZones')
AddEventHandler('atlas_blips:client:loadZones', function(blipPayload)
    print("^2[ATLAS BLIPS]^7 Received " .. #blipPayload .. " zones from server")
    RemoveAllBlips()

    local created = 0
    for _, zoneData in ipairs(blipPayload) do
        local pair = CreateZoneBlip(zoneData)
        if pair then
            ActiveBlips[zoneData.type .. "_" .. (zoneData.id or #ActiveBlips)] = pair
            created = created + 1
        end
    end
    print("^2[ATLAS BLIPS]^7 Created " .. created .. " of " .. #blipPayload .. " zones")
end)

-- ============================================================
-- PLAYER INITIALIZATION
-- ============================================================
Citizen.CreateThread(function()
    if Config.DebugLogging then
        print("^3[ATLAS BLIPS]^7 Player init thread. Waiting " .. Config.ReconnectBlipDelay .. "ms...")
    end
    Citizen.Wait(Config.ReconnectBlipDelay)
    print("^2[ATLAS BLIPS]^7 Requesting zone data...")
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end)

-- ============================================================
-- REFRESH COMMAND
-- ============================================================
RegisterCommand('refreshblips', function()
    print("^2[ATLAS BLIPS]^7 Manual refresh triggered")
    RemoveAllBlips()
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end, false)

-- ============================================================
-- RESOURCE STOP
-- ============================================================
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        RemoveAllBlips()
    end
end)

print("^2[ATLAS BLIPS CLIENT]^7 Ready.")
