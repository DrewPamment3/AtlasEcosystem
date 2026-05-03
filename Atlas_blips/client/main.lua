print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded")

local Config = AtlasBlipsConfig

local ActiveBlips = {}
local BlipsInitialized = false

-- ============================================================
-- SELF-TEST: Create a blip at player position to verify system works
-- ============================================================

local function RunSelfTest()
    Citizen.Wait(2000) -- Wait for radar to be ready
    
    local playerPed = PlayerPedId()
    if playerPed == 0 then
        print("^1[ATLAS BLIPS SELF-TEST]^7 Player ped not found yet")
        return false
    end
    
    local coords = GetEntityCoords(playerPed)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7 Testing at player pos: (%.1f, %.1f, %.1f)", coords.x, coords.y, coords.z))
    
    -- Test 1: AddBlipForRadius (pure floats, no hashes)
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 1: AddBlipForRadius...")
    local radiusBlip = AddBlipForRadius(coords.x, coords.y, coords.z, 50.0)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(radiusBlip)))
    
    if radiusBlip and radiusBlip ~= 0 then
        SetBlipAlpha(radiusBlip, 128)
        SetBlipColour(radiusBlip, 0x32A69E81) -- Grey
        print("^2[ATLAS BLIPS SELF-TEST]^7   Radius blip OK!")
    else
        print("^1[ATLAS BLIPS SELF-TEST]^7   Radius blip FAILED")
    end
    
    -- Test 2: AddBlipForCoord with just coords (GTA-style)
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 2: AddBlipForCoord(x,y,z)...")
    local spriteBlip1 = AddBlipForCoord(coords.x, coords.y, coords.z)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(spriteBlip1)))
    
    if spriteBlip1 and spriteBlip1 ~= 0 then
        -- Use the CONFIRMED RDR3 sprite: blip_event_appleseed = 0x7181B53C
        SetBlipSprite(spriteBlip1, 0x7181B53C, true)
        SetBlipColour(spriteBlip1, 0x662D3643) -- Brown
        SetBlipScale(spriteBlip1, 0.5)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Coord-only blip OK!")
    else
        print("^1[ATLAS BLIPS SELF-TEST]^7   Coord-only blip FAILED")
    end
    
    -- Test 3: AddBlipForCoord with hash first (RDR3-style)
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 3: AddBlipForCoord(hash,x,y,z)...")
    -- Use CONFIRMED sprite: blip_event_appleseed = 0x7181B53C
    local spriteBlip2 = AddBlipForCoord(0x7181B53C, coords.x, coords.y, coords.z)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(spriteBlip2)))
    
    if spriteBlip2 and spriteBlip2 ~= 0 then
        SetBlipColour(spriteBlip2, 0x662D3643)
        SetBlipScale(spriteBlip2, 0.5)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Hash-first blip OK!")
    else
        print("^1[ATLAS BLIPS SELF-TEST]^7   Hash-first blip FAILED")
    end
    
    -- Test 4: Citizen.InvokeNative RAW native call
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 4: InvokeNative ADD_BLIP_FOR_RADIUS...")
    local nativeBlip = Citizen.InvokeNative(0x45F13B7E0A770A54, coords.x, coords.y, coords.z, 50.0)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(nativeBlip)))
    
    if nativeBlip and nativeBlip ~= 0 then
        SetBlipAlpha(nativeBlip, 128)
        SetBlipColour(nativeBlip, 0x32A69E81)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Native radius blip OK!")
    else
        print("^1[ATLAS BLIPS SELF-TEST]^7   Native radius blip FAILED")
    end
    
    -- Determine which method works
    local methodFound = false
    
    if radiusBlip and radiusBlip ~= 0 then methodFound = true end
    if spriteBlip1 and spriteBlip1 ~= 0 then methodFound = true end
    if spriteBlip2 and spriteBlip2 ~= 0 then methodFound = true end
    if nativeBlip and nativeBlip ~= 0 then methodFound = true end
    
    print(string.format("^2[ATLAS BLIPS SELF-TEST]^7 === At least one method works: %s ===", tostring(methodFound)))
    
    -- Clean up test blips
    if radiusBlip and radiusBlip ~= 0 then RemoveBlip(radiusBlip) end
    if spriteBlip1 and spriteBlip1 ~= 0 then RemoveBlip(spriteBlip1) end
    if spriteBlip2 and spriteBlip2 ~= 0 then RemoveBlip(spriteBlip2) end
    if nativeBlip and nativeBlip ~= 0 then RemoveBlip(nativeBlip) end
    
    return methodFound
end

-- ============================================================
-- BLIP CREATION - Attempts multiple methods
-- ============================================================

local function CreateZoneBlips(zoneData)
    if Config.DebugLogging then
        print(string.format("^3[ATLAS BLIPS]^7 Creating blips for %s zone ID %d '%s' at (%.1f, %.1f, %.1f) radius %.1f",
            zoneData.type, zoneData.id, zoneData.name, zoneData.x, zoneData.y, zoneData.z, zoneData.radius))
    end

    if not Config.ShowBlips[zoneData.type] then
        return nil
    end

    local colorHash = Config.Colors[zoneData.type]
    local spriteHash = Config.Sprites[zoneData.type]
    local radiusHash = Config.Sprites.radius

    -- ========================================================
    -- RADIUS BLIP - Multiple methods
    -- ========================================================
    local radiusBlip = nil
    
    -- Method A: Direct function call
    radiusBlip = AddBlipForRadius(zoneData.x, zoneData.y, zoneData.z, zoneData.radius)
    
    -- Method B: Native invoke fallback
    if not radiusBlip or radiusBlip == 0 then
        radiusBlip = Citizen.InvokeNative(0x45F13B7E0A770A54, zoneData.x, zoneData.y, zoneData.z, zoneData.radius)
    end
    
    if radiusBlip and radiusBlip ~= 0 then
        SetBlipSprite(radiusBlip, radiusHash, true)
        SetBlipColour(radiusBlip, colorHash)
        SetBlipAlpha(radiusBlip, Config.RadiusAlpha)
        print("^2[ATLAS BLIPS]^7   Radius blip OK: " .. tostring(radiusBlip))
    else
        print("^1[ATLAS BLIPS]^7   Radius blip FAILED for zone " .. zoneData.id)
    end

    -- ========================================================
    -- SPRITE BLIP - Multiple methods
    -- ========================================================
    local spriteBlip = nil
    
    -- Method A: GTA-style (coords only, set sprite later) - try first
    spriteBlip = AddBlipForCoord(zoneData.x, zoneData.y, zoneData.z)
    if spriteBlip and spriteBlip ~= 0 then
        SetBlipSprite(spriteBlip, spriteHash, true)
    end
    
    -- Method B: RDR3-style (hash first)
    if not spriteBlip or spriteBlip == 0 then
        spriteBlip = AddBlipForCoord(spriteHash, zoneData.x, zoneData.y, zoneData.z)
    end
    
    -- Method C: Native invoke
    if not spriteBlip or spriteBlip == 0 then
        spriteBlip = Citizen.InvokeNative(0x554D9D53F696D002, spriteHash, zoneData.x, zoneData.y, zoneData.z)
    end
    
    -- Method D: Native invoke with coords only
    if not spriteBlip or spriteBlip == 0 then
        spriteBlip = Citizen.InvokeNative(0x554D9D53F696D002, zoneData.x, zoneData.y, zoneData.z)
        if spriteBlip and spriteBlip ~= 0 then
            SetBlipSprite(spriteBlip, spriteHash, true)
        end
    end
    
    if spriteBlip and spriteBlip ~= 0 then
        SetBlipColour(spriteBlip, colorHash)
        SetBlipScale(spriteBlip, Config.SpriteScale)
        -- Name the blip
        Citizen.InvokeNative(0x9CB1A1623062F402, spriteBlip, zoneData.name)
        print("^2[ATLAS BLIPS]^7   Sprite blip OK: " .. tostring(spriteBlip) .. " name: " .. zoneData.name)
    else
        print("^1[ATLAS BLIPS]^7   Sprite blip FAILED for zone " .. zoneData.id)
    end

    local result = { radiusBlip = radiusBlip, spriteBlip = spriteBlip }
    if not radiusBlip and not spriteBlip then
        print("^1[ATLAS BLIPS]^7 Failed to create ANY blips for zone " .. zoneData.id)
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
            if blips.radiusBlip then SetBlipDisplay(blips.radiusBlip, displayMode) end
            if blips.spriteBlip then SetBlipDisplay(blips.spriteBlip, displayMode) end
        end
    end
end

-- ============================================================
-- BLIP REMOVAL
-- ============================================================

local function RemoveAllBlips()
    for _, blips in pairs(ActiveBlips) do
        if blips.radiusBlip then RemoveBlip(blips.radiusBlip) end
        if blips.spriteBlip then RemoveBlip(blips.spriteBlip) end
    end
    ActiveBlips = {}
end

local function RemoveZoneBlips(zoneKey)
    local blips = ActiveBlips[zoneKey]
    if not blips then return end
    if blips.radiusBlip then RemoveBlip(blips.radiusBlip) end
    if blips.spriteBlip then RemoveBlip(blips.spriteBlip) end
    ActiveBlips[zoneKey] = nil
end

-- ============================================================
-- INITIALIZATION (with self-test and delay)
-- ============================================================

Citizen.CreateThread(function()
    -- First, run self-test to verify blip system is functional
    print("^5======================================^7")
    print("^5  ATLAS BLIPS - SELF TEST STARTING^7")
    print("^5======================================^7")
    
    local blipsWorking = RunSelfTest()
    
    if not blipsWorking then
        print("^1[ATLAS BLIPS]^7 *** BLIP SYSTEM NOT WORKING - Check SDK/radar initialization ***")
        print("^1[ATLAS BLIPS]^7 *** Continuing anyway, but blips may not appear ***")
    end
    
    -- Now wait a bit more before requesting zone data
    Citizen.Wait(3000)
    print("^2[ATLAS BLIPS CLIENT]^7 Requesting zone data from server (after self-test)")
    TriggerServerEvent('atlas_blips:server:playerLoaded')
end)

-- ============================================================
-- RECEIVE ZONE DATA (with timing delay before creation)
-- ============================================================

RegisterNetEvent('atlas_blips:client:loadZones')
AddEventHandler('atlas_blips:client:loadZones', function(blipPayload)
    print("^2[ATLAS BLIPS]^7 Received " .. #blipPayload .. " zones from server")
    
    -- Small delay to ensure radar is ready before creating blips
    Citizen.Wait(500)

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
    print(string.format("^2[ATLAS BLIPS]^7 %s blips now: %s", zoneType, isEnabled and "ENABLED" or "DISABLED"))
    SetCategoryVisibility(zoneType, isEnabled)
end)

RegisterCommand('selftestblips', function(source, args)
    print("^2[ATLAS BLIPS]^7 Running blip self-test...")
    local testResult = RunSelfTest()
    print("^2[ATLAS BLIPS]^7 Self-test result: " .. tostring(testResult))
end)

RegisterCommand('refreshblipsclient', function(source, args)
    print("^2[ATLAS BLIPS]^7 Manually requesting zone data refresh...")
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
