print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded")

local Config = AtlasBlipsConfig

local ActiveBlips = {}
local BlipsInitialized = false

-- ============================================================
-- NATIVE HASHES (RDR3 — all calls must use Citizen.InvokeNative)
-- ============================================================

local NATIVE_ADD_BLIP_FOR_RADIUS = 0x45F13B7E0A770A54
local NATIVE_ADD_BLIP_FOR_COORD    = 0x554D9D53F696D002
local NATIVE_SET_BLIP_SPRITE        = 0xDF735600A4696DAF
local NATIVE_SET_BLIP_COLOUR        = 0x03D7FB09E75D6B7E
local NATIVE_SET_BLIP_ALPHA         = 0x45FF974EEE1C8734
local NATIVE_SET_BLIP_SCALE         = 0xD38744167B2FA257
local NATIVE_SET_BLIP_DISPLAY       = 0x9029B2F3DA924928
local NATIVE_REMOVE_BLIP            = 0x86A652570E5F25DD
local NATIVE_SET_BLIP_NAME          = 0x9CB1A1623062F402

-- ============================================================
-- SELF-TEST: Create a blip at player position using InvokeNative only
-- ============================================================

local function RunSelfTest()
    Citizen.Wait(2000)

    local playerPed = PlayerPedId()
    if playerPed == 0 then
        print("^1[ATLAS BLIPS SELF-TEST]^7 Player ped not found yet")
        return false
    end

    local coords = GetEntityCoords(playerPed)
    local x, y, z = coords.x, coords.y, coords.z
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7 Testing at (%.1f, %.1f, %.1f)", x, y, z))

    -- Test 1: ADD_BLIP_FOR_RADIUS via InvokeNative
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 1: ADD_BLIP_FOR_RADIUS...")
    local radiusBlip = Citizen.InvokeNative(NATIVE_ADD_BLIP_FOR_RADIUS, x, y, z, 50.0)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(radiusBlip)))

    if radiusBlip and radiusBlip ~= 0 then
        Citizen.InvokeNative(NATIVE_SET_BLIP_ALPHA, radiusBlip, 128)
        Citizen.InvokeNative(NATIVE_SET_BLIP_COLOUR, radiusBlip, 0x32A69E81)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Radius blip OK!")
    else
        print("^1[ATLAS BLIPS SELF-TEST]^7   Radius blip FAILED")
    end

    -- Test 2: ADD_BLIP_FOR_COORD with coords only (x, y, z)
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 2: ADD_BLIP_FOR_COORD(x, y, z)...")
    local spriteBlip1 = Citizen.InvokeNative(NATIVE_ADD_BLIP_FOR_COORD, x, y, z)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(spriteBlip1)))

    if spriteBlip1 and spriteBlip1 ~= 0 then
        Citizen.InvokeNative(NATIVE_SET_BLIP_SPRITE, spriteBlip1, 0x7181B53C, true)
        Citizen.InvokeNative(NATIVE_SET_BLIP_COLOUR, spriteBlip1, 0x662D3643)
        Citizen.InvokeNative(NATIVE_SET_BLIP_SCALE, spriteBlip1, 0.5)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Coord-only blip OK!")
    else
        print("^1[ATLAS BLIPS SELF-TEST]^7   Coord-only blip FAILED")
    end

    -- Test 3: ADD_BLIP_FOR_COORD with hash first (hash, x, y, z)
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 3: ADD_BLIP_FOR_COORD(hash, x, y, z)...")
    local spriteBlip2 = Citizen.InvokeNative(NATIVE_ADD_BLIP_FOR_COORD, 0x7181B53C, x, y, z)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(spriteBlip2)))

    if spriteBlip2 and spriteBlip2 ~= 0 then
        Citizen.InvokeNative(NATIVE_SET_BLIP_COLOUR, spriteBlip2, 0x662D3643)
        Citizen.InvokeNative(NATIVE_SET_BLIP_SCALE, spriteBlip2, 0.5)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Hash-first blip OK!")
    else
        print("^1[ATLAS BLIPS SELF-TEST]^7   Hash-first blip FAILED")
    end

    -- Summary
    local anyWorked = false
    if radiusBlip and radiusBlip ~= 0 then anyWorked = true end
    if spriteBlip1 and spriteBlip1 ~= 0 then anyWorked = true end
    if spriteBlip2 and spriteBlip2 ~= 0 then anyWorked = true end

    print(string.format("^5[ATLAS BLIPS SELF-TEST]^7 === At least one method works: %s ===", tostring(anyWorked)))

    -- Cleanup
    if radiusBlip and radiusBlip ~= 0 then
        Citizen.InvokeNative(NATIVE_REMOVE_BLIP, radiusBlip)
    end
    if spriteBlip1 and spriteBlip1 ~= 0 then
        Citizen.InvokeNative(NATIVE_REMOVE_BLIP, spriteBlip1)
    end
    if spriteBlip2 and spriteBlip2 ~= 0 then
        Citizen.InvokeNative(NATIVE_REMOVE_BLIP, spriteBlip2)
    end

    return anyWorked
end

-- ============================================================
-- ZONE BLIP CREATION (InvokeNative exclusively)
-- ============================================================

local function CreateZoneBlips(zoneData)
    if Config.DebugLogging then
        print(string.format("^3[ATLAS BLIPS]^7 Creating blips for %s zone %d '%s' at (%.1f, %.1f, %.1f) r=%.1f",
            zoneData.type, zoneData.id, zoneData.name,
            zoneData.x, zoneData.y, zoneData.z, zoneData.radius))
    end

    if not Config.ShowBlips[zoneData.type] then
        return nil
    end

    local colorHash  = Config.Colors[zoneData.type]
    local spriteHash = Config.Sprites[zoneData.type]
    local radiusHash = Config.Sprites.radius

    -- -------------------------------------------
    -- RADIUS BLIP
    -- -------------------------------------------
    local radiusBlip = Citizen.InvokeNative(
        NATIVE_ADD_BLIP_FOR_RADIUS,
        zoneData.x, zoneData.y, zoneData.z, zoneData.radius
    )

    if radiusBlip and radiusBlip ~= 0 then
        Citizen.InvokeNative(NATIVE_SET_BLIP_SPRITE, radiusBlip, radiusHash, true)
        Citizen.InvokeNative(NATIVE_SET_BLIP_COLOUR, radiusBlip, colorHash)
        Citizen.InvokeNative(NATIVE_SET_BLIP_ALPHA,  radiusBlip, Config.RadiusAlpha)
        print("^2[ATLAS BLIPS]^7   Radius blip OK: #" .. tostring(radiusBlip))
    else
        print("^1[ATLAS BLIPS]^7   Radius blip FAILED for zone " .. zoneData.id)
        radiusBlip = nil
    end

    -- -------------------------------------------
    -- SPRITE BLIP — try 3 signatures
    -- -------------------------------------------
    local spriteBlip = nil

    -- Attempt A: (x, y, z) — coords only, sprite set separately
    spriteBlip = Citizen.InvokeNative(NATIVE_ADD_BLIP_FOR_COORD,
        zoneData.x, zoneData.y, zoneData.z)
    if spriteBlip and spriteBlip ~= 0 then
        Citizen.InvokeNative(NATIVE_SET_BLIP_SPRITE, spriteBlip, spriteHash, true)
    end

    -- Attempt B: (hash, x, y, z) — hash first
    if not spriteBlip or spriteBlip == 0 then
        spriteBlip = Citizen.InvokeNative(NATIVE_ADD_BLIP_FOR_COORD,
            spriteHash, zoneData.x, zoneData.y, zoneData.z)
    end

    -- Attempt C: (x, y, z) with sprite set after, using radiusHash as placeholder then swap
    if not spriteBlip or spriteBlip == 0 then
        -- Try creating with radiusHash first (some builds need *any* valid hash)
        spriteBlip = Citizen.InvokeNative(NATIVE_ADD_BLIP_FOR_COORD,
            radiusHash, zoneData.x, zoneData.y, zoneData.z)
        if spriteBlip and spriteBlip ~= 0 then
            -- Swap to the correct sprite
            Citizen.InvokeNative(NATIVE_SET_BLIP_SPRITE, spriteBlip, spriteHash, true)
        end
    end

    if spriteBlip and spriteBlip ~= 0 then
        Citizen.InvokeNative(NATIVE_SET_BLIP_COLOUR, spriteBlip, colorHash)
        Citizen.InvokeNative(NATIVE_SET_BLIP_SCALE,  spriteBlip, Config.SpriteScale)
        Citizen.InvokeNative(NATIVE_SET_BLIP_NAME,   spriteBlip, zoneData.name)
        print("^2[ATLAS BLIPS]^7   Sprite blip OK: #" .. tostring(spriteBlip) .. " '" .. zoneData.name .. "'")
    else
        print("^1[ATLAS BLIPS]^7   Sprite blip FAILED for zone " .. zoneData.id)
        spriteBlip = nil
    end

    local result = { radiusBlip = radiusBlip, spriteBlip = spriteBlip }
    if not radiusBlip and not spriteBlip then
        print("^1[ATLAS BLIPS]^7 Neither blip created for zone " .. zoneData.id)
        return nil
    end
    return result
end

-- ============================================================
-- CATEGORY VISIBILITY
-- ============================================================

local function SetCategoryVisibility(category, visible)
    local displayMode = visible and 2 or 0
    for zoneKey, blips in pairs(ActiveBlips) do
        if zoneKey:match("^" .. category .. "_") then
            if blips.radiusBlip then
                Citizen.InvokeNative(NATIVE_SET_BLIP_DISPLAY, blips.radiusBlip, displayMode)
            end
            if blips.spriteBlip then
                Citizen.InvokeNative(NATIVE_SET_BLIP_DISPLAY, blips.spriteBlip, displayMode)
            end
        end
    end
end

-- ============================================================
-- BLIP REMOVAL
-- ============================================================

local function RemoveAllBlips()
    for _, blips in pairs(ActiveBlips) do
        if blips.radiusBlip then
            Citizen.InvokeNative(NATIVE_REMOVE_BLIP, blips.radiusBlip)
        end
        if blips.spriteBlip then
            Citizen.InvokeNative(NATIVE_REMOVE_BLIP, blips.spriteBlip)
        end
    end
    ActiveBlips = {}
end

local function RemoveZoneBlips(zoneKey)
    local blips = ActiveBlips[zoneKey]
    if not blips then return end
    if blips.radiusBlip then
        Citizen.InvokeNative(NATIVE_REMOVE_BLIP, blips.radiusBlip)
    end
    if blips.spriteBlip then
        Citizen.InvokeNative(NATIVE_REMOVE_BLIP, blips.spriteBlip)
    end
    ActiveBlips[zoneKey] = nil
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

Citizen.CreateThread(function()
    print("^5======================================^7")
    print("^5  ATLAS BLIPS — SELF TEST^7")
    print("^5======================================^7")

    local blipsWorking = RunSelfTest()

    if not blipsWorking then
        print("^1[ATLAS BLIPS]^7 *** BLIP NATIVE TEST FAILED — blips may not render ***")
    end

    -- Extra delay before requesting real zone data
    Citizen.Wait(3000)
    print("^2[ATLAS BLIPS CLIENT]^7 Requesting zone data from server")
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end)

-- ============================================================
-- RECEIVE ZONE DATA
-- ============================================================

RegisterNetEvent('atlas_blips:client:loadZones')
AddEventHandler('atlas_blips:client:loadZones', function(blipPayload)
    print("^2[ATLAS BLIPS]^7 Received " .. #blipPayload .. " zones from server")

    Citizen.Wait(500) -- let radar finish init

    RemoveAllBlips()

    local miningCount = 0
    local woodcuttingCount = 0
    local failCount = 0

    for _, zoneData in ipairs(blipPayload) do
        local zoneKey = zoneData.type .. "_" .. zoneData.id
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

    print(string.format("^2[ATLAS BLIPS]^7 Total: %d mining, %d woodcutting, %d failed",
        miningCount, woodcuttingCount, failCount))
    print("^5======================================^7")
    print("^5  ATLAS BLIPS CLIENT READY^7")
    print("^5======================================^7")
end)

-- ============================================================
-- COMMANDS
-- ============================================================

RegisterCommand('toggleblips', function(source, args)
    local zoneType = args[1] and args[1]:lower()
    if not zoneType or (zoneType ~= "mining" and zoneType ~= "woodcutting") then
        print("^3[ATLAS BLIPS]^7 Usage: /toggleblips [mining|woodcutting]")
        return
    end
    Config.ShowBlips[zoneType] = not Config.ShowBlips[zoneType]
    local isEnabled = Config.ShowBlips[zoneType]
    print(string.format("^2[ATLAS BLIPS]^7 %s blips: %s", zoneType, isEnabled and "ON" or "OFF"))
    SetCategoryVisibility(zoneType, isEnabled)
end)

RegisterCommand('selftestblips', function(source, args)
    print("^2[ATLAS BLIPS]^7 Running self-test...")
    local ok = RunSelfTest()
    print("^2[ATLAS BLIPS]^7 Self-test: " .. tostring(ok))
end)

RegisterCommand('refreshblipsclient', function(source, args)
    print("^2[ATLAS BLIPS]^7 Requesting zone data refresh...")
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end)

-- ============================================================
-- CLEANUP & RETRY
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        RemoveAllBlips()
    end
end)

Citizen.CreateThread(function()
    Citizen.Wait(Config.ReconnectBlipDelay + 10000)
    if not BlipsInitialized then
        print("^3[ATLAS BLIPS]^7 Retrying zone data request...")
        TriggerServerEvent('atlas_blips:server:playerLoaded')
    end
end)
