print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded. Subscription-based blip system.")

local Config = AtlasBlipsConfig

-- ============================================================
-- RUNTIME HASH COMPUTATION
-- ============================================================

local SpriteHashes = {
    mining      = GetHashKey(Config.Sprites.mining),
    woodcutting = GetHashKey(Config.Sprites.woodcutting),
    radius      = GetHashKey(Config.Sprites.radius),
}

local BLIP_STYLE_MISSION = GetHashKey("BLIP_STYLE_MISSION")
local BLIP_STYLE_RADIUS  = GetHashKey("BLIP_STYLE_RADIUS")

-- ============================================================
-- BLIP STATE (per-type, not global)
-- ============================================================

-- Mining blips: { [zoneKey] = { spriteBlip = handle, radiusBlip = nil } }
local MiningBlips = {}

-- Woodcutting blips
local WoodcuttingBlips = {}

-- ============================================================
-- RDR2 NATIVE HELPERS
-- ============================================================

local function RDR_BlipAddForCoord(styleHash, x, y, z)
    return Citizen.InvokeNative(0x554D9D53F696D002, styleHash, x, y, z)
end

local function RDR_SetBlipSprite(blip, spriteHash, toggle)
    Citizen.InvokeNative(0x74F74D3207ED525C, blip, spriteHash, toggle or true)
end

local function RDR_SetBlipName(blip, name)
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, name)
end

local function RDR_SetBlipDisplay(blip, displayType)
    Citizen.InvokeNative(0xA1509A8E850B0347, blip, displayType)
end

local function RDR_SetBlipColour(blip, colourIndex)
    Citizen.InvokeNative(0x03D7FB09E75D6B7E, blip, colourIndex)
end

local function RDR_SetBlipScale(blip, scale)
    Citizen.InvokeNative(0xD38744167B2FA257, blip, scale)
end

local function RDR_SetBlipAlpha(blip, alpha)
    Citizen.InvokeNative(0x45FF974EEE1C8734, blip, alpha)
end

local function RDR_SetBlipRadius(blip, radius)
    Citizen.InvokeNative(0x340CF8A9750E9669, blip, radius)
end

local function RDR_RemoveBlip(blip)
    if blip and blip ~= 0 then
        Citizen.InvokeNative(0xDEEDE7C41742E011, blip)
    end
end

-- ============================================================
-- BLIP CREATION / DESTRUCTION
-- ============================================================

local function CreateZoneBlip(zoneData)
    local zoneType   = zoneData.type
    local zoneName   = zoneData.name or (zoneType .. " Zone")
    local x, y, z    = zoneData.x, zoneData.y, zoneData.z
    local radius     = zoneData.radius or 100.0
    local spriteHash = SpriteHashes[zoneType]
    local colorIdx   = Config.Colors[zoneType] or 8

    if not Config.ShowBlips[zoneType] then
        return nil
    end

    local spriteBlip = RDR_BlipAddForCoord(BLIP_STYLE_MISSION, x, y, z)
    if not spriteBlip or spriteBlip == 0 then
        print("^1[ATLAS BLIPS]^7 Failed to create icon blip for " .. zoneType .. " '" .. zoneName .. "'")
        return nil
    end

    RDR_SetBlipSprite(spriteBlip, spriteHash, true)
    RDR_SetBlipName(spriteBlip, zoneName)
    RDR_SetBlipDisplay(spriteBlip, 3)
    RDR_SetBlipColour(spriteBlip, colorIdx)
    RDR_SetBlipScale(spriteBlip, Config.SpriteScale)
    RDR_SetBlipRadius(spriteBlip, radius)
    RDR_SetBlipAlpha(spriteBlip, 255)

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Created " .. zoneType .. " blip: '" .. zoneName .. "' at (" .. string.format("%.1f", x) .. ", " .. string.format("%.1f", y) .. ") radius=" .. radius)
    end

    return { spriteBlip = spriteBlip, radiusBlip = nil }
end

local function RemoveAllBlipsOfType(blipStore)
    for _, pair in pairs(blipStore) do
        RDR_RemoveBlip(pair.spriteBlip)
        if pair.radiusBlip and pair.radiusBlip ~= 0 then
            RDR_RemoveBlip(pair.radiusBlip)
        end
    end
end

-- ============================================================
-- SUBSCRIPTION-BASED ZONE HANDLERS (called by mining / woodcutting)
-- ============================================================

-- Called by Atlas_mining client when subscriptions change
AddEventHandler('atlas_blips:client:updateMiningZones', function(zones)
    -- Remove all existing mining blips
    RemoveAllBlipsOfType(MiningBlips)
    MiningBlips = {}

    if not zones or #zones == 0 then
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7 No mining zones in range - all mining blips removed")
        end
        return
    end

    local created = 0
    for _, zoneData in ipairs(zones) do
        local pair = CreateZoneBlip(zoneData)
        if pair then
            MiningBlips["mining_" .. (zoneData.id or created)] = pair
            created = created + 1
        end
    end

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Subscription update: " .. created .. " mining blips active")
    end
end)

-- Called by Atlas_woodcutting client when subscriptions change
AddEventHandler('atlas_blips:client:updateWoodcuttingZones', function(zones)
    -- Remove all existing woodcutting blips
    RemoveAllBlipsOfType(WoodcuttingBlips)
    WoodcuttingBlips = {}

    if not zones or #zones == 0 then
        if Config.DebugLogging then
            print("^3[ATLAS BLIPS]^7 No woodcutting zones in range - all woodcutting blips removed")
        end
        return
    end

    local created = 0
    for _, zoneData in ipairs(zones) do
        local pair = CreateZoneBlip(zoneData)
        if pair then
            WoodcuttingBlips["woodcutting_" .. (zoneData.id or created)] = pair
            created = created + 1
        end
    end

    if Config.DebugLogging then
        print("^2[ATLAS BLIPS]^7 Subscription update: " .. created .. " woodcutting blips active")
    end
end)

-- ============================================================
-- RESOURCE STOP CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName == GetCurrentResourceName() then
        RemoveAllBlipsOfType(MiningBlips)
        RemoveAllBlipsOfType(WoodcuttingBlips)
        MiningBlips = {}
        WoodcuttingBlips = {}
        print("^2[ATLAS BLIPS]^7 All blips cleaned up on resource stop")
    end
end)

print("^2[ATLAS BLIPS CLIENT]^7 Ready — Subscription-based blip system active.")
