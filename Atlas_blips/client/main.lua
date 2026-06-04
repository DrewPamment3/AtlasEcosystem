print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded. Subscription-based blip system.")

local Config              = AtlasBlipsConfig

-- ============================================================
-- RUNTIME HASH COMPUTATION
-- ============================================================

local SpriteHashes        = {
    mining      = GetHashKey(Config.Sprites.mining),
    woodcutting = GetHashKey(Config.Sprites.woodcutting),
    radius      = GetHashKey(Config.Sprites.radius),
}

local BLIP_STYLE_MISSION  = GetHashKey("BLIP_STYLE_DESTINATION")
local BLIP_STYLE_RADIUS   = GetHashKey("BLIP_STYLE_RADIUS")

-- ============================================================
-- BLIP POOL (reuse handles instead of creating/destroying)
-- ============================================================

local MAX_BLIPS           = 50

local MiningBlipPool      = {}
local WoodcuttingBlipPool = {}

local function InitPool(pool)
    if #pool == 0 then
        for i = 1, MAX_BLIPS do
            pool[i] = { handle = 0, active = false, zoneKey = nil }
        end
    end
end

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
    Citizen.InvokeNative(0x9029B2F3DA924928, blip, displayType)
end

local function SetBlipVisibility(blip, visible)
    if blip and blip ~= 0 then
        local displayId = visible and 3 or 0
        RDR_SetBlipDisplay(blip, displayId)
    end
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

local function RDR_SetBlipCoords(blip, x, y, z)
    Citizen.InvokeNative(0xC2F84B7F9C4D0C61, blip, x, y, z)
end

local function HideBlip(blip)
    SetBlipVisibility(blip, false)
end

local function ConfigureBlip(blip, zoneData)
    if not blip or blip == 0 then return end

    local zoneType   = zoneData.type
    local zoneName   = zoneData.name or (zoneType .. " Zone")
    local x, y, z    = zoneData.x, zoneData.y, zoneData.z
    local radius     = zoneData.radius or 100.0
    local spriteHash = SpriteHashes[zoneType] or GetHashKey("blip_ambient_axe")
    local colorIdx   = Config.Colors[zoneType] or 8

    RDR_SetBlipCoords(blip, x, y, z)
    RDR_SetBlipSprite(blip, spriteHash, true)
    RDR_SetBlipName(blip, zoneName)
    RDR_SetBlipColour(blip, colorIdx)
    RDR_SetBlipScale(blip, Config.SpriteScale)
    RDR_SetBlipRadius(blip, radius)
    RDR_SetBlipAlpha(blip, 255)
end

-- ============================================================
-- POOL-BASED ZONE UPDATER
-- ============================================================

local function UpdateZoneBlips(pool, zones, zoneType)
    InitPool(pool)

    -- Count elements safely (handles both standard arrays and dictionary payloads)
    local zoneCount = 0
    if zones then
        for _ in pairs(zones) do zoneCount = zoneCount + 1 end
    end

    -- Step 1: Deactivate and hide all currently active blips in this specific pool
    for i = 1, MAX_BLIPS do
        if pool[i].active then
            HideBlip(pool[i].handle)
            pool[i].active = false
            pool[i].zoneKey = nil
        end
    end

    if zoneCount == 0 then
        print("^3[ATLAS BLIPS]^7 No " .. zoneType .. " zones in range data payload — all " .. zoneType .. " blips hidden")
        return
    end

    -- Step 2: Assign zones to pool slots
    local activeCount = 0
    local zi = 0

    for _, zoneData in pairs(zones) do
        zi = zi + 1
        if zi > MAX_BLIPS then break end

        -- Inject type if missing from the source script event
        if not zoneData.type then zoneData.type = zoneType end

        local needNewHandle = true

        -- Reuse check for an already allocated handle
        for i = 1, MAX_BLIPS do
            if not pool[i].active and pool[i].handle ~= 0 then
                ConfigureBlip(pool[i].handle, zoneData)
                SetBlipVisibility(pool[i].handle, true)
                pool[i].active = true
                pool[i].zoneKey = zoneType .. "_" .. (zoneData.id or zi)
                needNewHandle = false
                activeCount = activeCount + 1
                break
            end
        end

        -- New creation check if pool slot is empty
        if needNewHandle then
            for i = 1, MAX_BLIPS do
                if pool[i].handle == 0 then
                    local x, y, z = zoneData.x, zoneData.y, zoneData.z
                    local handle = RDR_BlipAddForCoord(BLIP_STYLE_MISSION, x, y, z)

                    if handle and handle ~= 0 then
                        ConfigureBlip(handle, zoneData)
                        SetBlipVisibility(handle, true)
                        pool[i].handle = handle
                        pool[i].active = true
                        pool[i].zoneKey = zoneType .. "_" .. (zoneData.id or zi)
                        activeCount = activeCount + 1
                    end
                    break
                end
            end
        end
    end

    print("^2[ATLAS BLIPS]^7 Subscription update: " .. activeCount .. " " .. zoneType .. " blips active")
end

-- ============================================================
-- SUBSCRIPTION-BASED ZONE HANDLERS
-- ============================================================

AddEventHandler('atlas_blips:client:updateMiningZones', function(zones)
    UpdateZoneBlips(MiningBlipPool, zones, "mining")
end)

AddEventHandler('atlas_blips:client:updateWoodcuttingZones', function(zones)
    UpdateZoneBlips(WoodcuttingBlipPool, zones, "woodcutting")
end)

print("^2[ATLAS BLIPS CLIENT]^7 Ready — Pool-based blip system active.")
