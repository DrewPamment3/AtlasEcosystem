print("^2[ATLAS BLIPS CLIENT]^7 Client script loaded")

local Config = AtlasBlipsConfig
local ActiveBlips = {}
local BlipsInitialized = false

-- ============================================================
-- RUNTIME NATIVE HASH DISCOVERY
-- RDR3 has different native hashes than GTA V. We compute them
-- via GetHashKey on the native name string at runtime.
-- ============================================================

local function DiscoverNativeHashes()
    print("^5======================================^7")
    print("^5  DISCOVERING RDR3 NATIVE HASHES^7")
    print("^5======================================^7")

    local nativeNames = {
        "ADD_BLIP_FOR_RADIUS",
        "ADD_BLIP_FOR_COORD",
        "SET_BLIP_SPRITE",
        "SET_BLIP_COLOUR",
        "SET_BLIP_ALPHA",
        "SET_BLIP_SCALE",
        "SET_BLIP_DISPLAY",
        "REMOVE_BLIP",
        "SET_BLIP_NAME_FROM_PLAYER_NAME",
        "DOES_BLIP_EXIST",
        "GET_FIRST_BLIP_INFO_ID",
        "GET_NEXT_BLIP_INFO_ID",
        "GET_BLIP_INFO_ID_COORD",
        "MAP_BLIP",
    }

    local discovered = {}

    for _, name in ipairs(nativeNames) do
        local hash = GetHashKey(name)
        print(string.format("^3  %s -> 0x%X (%d)^7", name, hash, hash))

        -- Test if the native actually exists by calling it with minimal args
        -- Most natives return something other than false if they exist
        local exists = false
        if hash ~= 0 then
            -- Quick viability check: call the native with zero args
            -- If the native doesn't exist, InvokeNative returns false
            local result = Citizen.InvokeNative(hash)
            exists = (result ~= false)
            print(string.format("^3    Exists? %s (InvokeNative result: %s)^7", tostring(exists), tostring(result)))
        end

        discovered[name] = { hash = hash, exists = exists }
    end

    -- Also log some known RDR3 sprite hashes for comparison
    print("^5======================================^7")
    print("^5  CHECKING KNOWN SPRITE HASHES^7")
    print("^5======================================^7")

    local knownStrings = {
        "blip_event_appleseed",  -- confirmed 1904459580 / 0x7181B53C
        "blip_ambient_pickaxe",
        "blip_ambient_herb",
        "blip_type_radius",
        "BLIP_COLOR_GREY",
        "BLIP_COLOR_BROWN",
    }

    for _, str in ipairs(knownStrings) do
        local hash = GetHashKey(str)
        print(string.format("^3  %s -> 0x%X (%d)^7", str, hash, hash))
    end

    return discovered
end

-- ============================================================
-- SELF-TEST: Try to create blips with discovered hashes
-- ============================================================

local function RunSelfTest(nativeHashes)
    Citizen.Wait(500)

    local playerPed = PlayerPedId()
    if playerPed == 0 then
        print("^1[ATLAS BLIPS SELF-TEST]^7 No player ped")
        return false
    end

    local coords = GetEntityCoords(playerPed)
    local x, y, z = coords.x, coords.y, coords.z
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7 Player at (%.1f, %.1f, %.1f)", x, y, z))

    local addRadiusHash = nativeHashes["ADD_BLIP_FOR_RADIUS"].hash
    local addCoordHash  = nativeHashes["ADD_BLIP_FOR_COORD"].hash
    local setSpriteHash = nativeHashes["SET_BLIP_SPRITE"].hash
    local setColourHash = nativeHashes["SET_BLIP_COLOUR"].hash
    local setAlphaHash  = nativeHashes["SET_BLIP_ALPHA"].hash
    local setScaleHash  = nativeHashes["SET_BLIP_SCALE"].hash
    local removeHash    = nativeHashes["REMOVE_BLIP"].hash
    local setNameHash   = nativeHashes["SET_BLIP_NAME_FROM_PLAYER_NAME"].hash
    local mapBlipHash   = nativeHashes["MAP_BLIP"].hash

    local anyWorked = false

    -- ===== Test 1: ADD_BLIP_FOR_RADIUS =====
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 1: ADD_BLIP_FOR_RADIUS (0x" .. string.format("%X", addRadiusHash) .. ")")
    local r1 = Citizen.InvokeNative(addRadiusHash, x, y, z, 50.0)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s (type: %s)", tostring(r1), type(r1)))

    if r1 and r1 ~= false and r1 ~= 0 then
        -- Try setting alpha (might fail, that's ok)
        Citizen.InvokeNative(setAlphaHash, r1, 128)
        local clr = GetHashKey("BLIP_COLOR_GREY")
        Citizen.InvokeNative(setColourHash, r1, clr)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Radius blip WORKED!")
        anyWorked = true
        Citizen.InvokeNative(removeHash, r1)
    end

    -- ===== Test 2: ADD_BLIP_FOR_COORD (coords only) =====
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 2: ADD_BLIP_FOR_COORD(x,y,z)")
    local r2 = Citizen.InvokeNative(addCoordHash, x, y, z)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s (type: %s)", tostring(r2), type(r2)))

    if r2 and r2 ~= false and r2 ~= 0 then
        local appleHash = GetHashKey("blip_event_appleseed")
        Citizen.InvokeNative(setSpriteHash, r2, appleHash, true)
        Citizen.InvokeNative(setColourHash, r2, GetHashKey("BLIP_COLOR_BROWN"))
        Citizen.InvokeNative(setScaleHash, r2, 0.5)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Coord-only blip WORKED!")
        anyWorked = true
        Citizen.InvokeNative(removeHash, r2)
    end

    -- ===== Test 3: ADD_BLIP_FOR_COORD (hash first) =====
    local appleHash = GetHashKey("blip_event_appleseed")
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7 Test 3: ADD_BLIP_FOR_COORD(hash 0x%X, x, y, z)", appleHash))
    local r3 = Citizen.InvokeNative(addCoordHash, appleHash, x, y, z)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s (type: %s)", tostring(r3), type(r3)))

    if r3 and r3 ~= false and r3 ~= 0 then
        Citizen.InvokeNative(setColourHash, r3, GetHashKey("BLIP_COLOR_BROWN"))
        Citizen.InvokeNative(setScaleHash, r3, 0.5)
        print("^2[ATLAS BLIPS SELF-TEST]^7   Hash-first blip WORKED!")
        anyWorked = true
        Citizen.InvokeNative(removeHash, r3)
    end

    -- ===== Test 4: MAP_BLIP (alternative RDR3 function) =====
    if mapBlipHash ~= 0 then
        print(string.format("^3[ATLAS BLIPS SELF-TEST]^7 Test 4: MAP_BLIP (0x%X)", mapBlipHash))
        local r4 = Citizen.InvokeNative(mapBlipHash, appleHash, x, y, z)
        print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s (type: %s)", tostring(r4), type(r4)))

        if r4 and r4 ~= false and r4 ~= 0 then
            Citizen.InvokeNative(setColourHash, r4, GetHashKey("BLIP_COLOR_BROWN"))
            Citizen.InvokeNative(setScaleHash, r4, 0.5)
            print("^2[ATLAS BLIPS SELF-TEST]^7   MAP_BLIP WORKED!")
            anyWorked = true
            Citizen.InvokeNative(removeHash, r4)
        end
    end

    -- ===== Test 5: Try ADD_BLIP_FOR_COORD with sprite hash as arg 1 AND coords =====
    -- Some builds expect (spriteHash, x, y, z) where spriteHash is actually just the first coord
    print("^3[ATLAS BLIPS SELF-TEST]^7 Test 5: ADD_BLIP_FOR_COORD with x as hash...")
    local r5 = Citizen.InvokeNative(addCoordHash, x, y, z, appleHash)
    print(string.format("^3[ATLAS BLIPS SELF-TEST]^7   Result: %s", tostring(r5)))

    if r5 and r5 ~= false and r5 ~= 0 then
        Citizen.InvokeNative(setSpriteHash, r5, appleHash, true)
        Citizen.InvokeNative(setColourHash, r5, GetHashKey("BLIP_COLOR_BROWN"))
        print("^2[ATLAS BLIPS SELF-TEST]^7   Test 5 WORKED!")
        anyWorked = true
        Citizen.InvokeNative(removeHash, r5)
    end

    print(string.format("^5[ATLAS BLIPS SELF-TEST]^7 === Any method worked: %s ===", tostring(anyWorked)))
    return anyWorked
end

-- ============================================================
-- ZONE BLIP CREATION (uses discovered hashes)
-- ============================================================

local function CreateZoneBlips(zoneData, nativeHashes)
    if not Config.ShowBlips[zoneData.type] then return nil end

    if Config.DebugLogging then
        print(string.format("^3[ATLAS BLIPS]^7 Creating blips for %s zone %d '%s' at (%.1f, %.1f, %.1f) r=%.1f",
            zoneData.type, zoneData.id, zoneData.name,
            zoneData.x, zoneData.y, zoneData.z, zoneData.radius))
    end

    local colorHash = GetHashKey("BLIP_COLOR_GREY")
    if zoneData.type == "woodcutting" then
        colorHash = GetHashKey("BLIP_COLOR_BROWN")
    end

    local radiusHash = nativeHashes["ADD_BLIP_FOR_RADIUS"].hash
    local coordHash  = nativeHashes["ADD_BLIP_FOR_COORD"].hash
    local spriteHash = nativeHashes["SET_BLIP_SPRITE"].hash
    local colourHash = nativeHashes["SET_BLIP_COLOUR"].hash
    local alphaHash  = nativeHashes["SET_BLIP_ALPHA"].hash
    local scaleHash  = nativeHashes["SET_BLIP_SCALE"].hash
    local removeHash = nativeHashes["REMOVE_BLIP"].hash
    local nameHash   = nativeHashes["SET_BLIP_NAME_FROM_PLAYER_NAME"].hash

    local iconSpriteHash
    if zoneData.type == "mining" then
        iconSpriteHash = GetHashKey("blip_ambient_pickaxe")
    else
        iconSpriteHash = GetHashKey("blip_event_appleseed")
    end
    local radiusSpriteHash = GetHashKey("blip_type_radius")

    -- Try RADIUS blip
    local radiusBlip = nil
    if radiusHash ~= 0 then
        radiusBlip = Citizen.InvokeNative(radiusHash, zoneData.x, zoneData.y, zoneData.z, zoneData.radius)
        if radiusBlip and radiusBlip ~= false and radiusBlip ~= 0 then
            Citizen.InvokeNative(spriteHash, radiusBlip, radiusSpriteHash, true)
            Citizen.InvokeNative(colourHash, radiusBlip, colorHash)
            Citizen.InvokeNative(alphaHash, radiusBlip, Config.RadiusAlpha)
            print("^2[ATLAS BLIPS]^7   Radius blip OK: #" .. tostring(radiusBlip))
        else
            print("^1[ATLAS BLIPS]^7   Radius blip FAILED (result: " .. tostring(radiusBlip) .. ")")
            radiusBlip = nil
        end
    end

    -- Try SPRITE blip (multiple signatures)
    local spriteBlip = nil
    if coordHash ~= 0 then
        -- Sig A: (x, y, z, [sprite?])
        spriteBlip = Citizen.InvokeNative(coordHash, zoneData.x, zoneData.y, zoneData.z)
        if (not spriteBlip or spriteBlip == false or spriteBlip == 0) then
            -- Sig B: (hash, x, y, z) — standard RDR3
            spriteBlip = Citizen.InvokeNative(coordHash, iconSpriteHash, zoneData.x, zoneData.y, zoneData.z)
        end
        if (not spriteBlip or spriteBlip == false or spriteBlip == 0) then
            -- Sig C: (x, y, z, hash) — reversed
            spriteBlip = Citizen.InvokeNative(coordHash, zoneData.x, zoneData.y, zoneData.z, iconSpriteHash)
        end

        if spriteBlip and spriteBlip ~= false and spriteBlip ~= 0 then
            Citizen.InvokeNative(spriteHash, spriteBlip, iconSpriteHash, true)
            Citizen.InvokeNative(colourHash, spriteBlip, colorHash)
            Citizen.InvokeNative(scaleHash, spriteBlip, Config.SpriteScale)
            if nameHash ~= 0 then
                Citizen.InvokeNative(nameHash, spriteBlip, zoneData.name)
            end
            print("^2[ATLAS BLIPS]^7   Sprite blip OK: #" .. tostring(spriteBlip) .. " '" .. zoneData.name .. "'")
        else
            print("^1[ATLAS BLIPS]^7   Sprite blip FAILED (all sigs)")
            spriteBlip = nil
        end
    end

    local result = { radiusBlip = radiusBlip, spriteBlip = spriteBlip }
    if not radiusBlip and not spriteBlip then
        print("^1[ATLAS BLIPS]^7 Both blips failed for zone " .. zoneData.id)
        return nil
    end
    return result
end

-- ============================================================
-- BLIP REMOVAL (uses discovered hash)
-- ============================================================

local function RemoveAllBlips(nativeHashes)
    local removeHash = nativeHashes["REMOVE_BLIP"].hash
    if removeHash == 0 then return end
    for _, blips in pairs(ActiveBlips) do
        if blips.radiusBlip then Citizen.InvokeNative(removeHash, blips.radiusBlip) end
        if blips.spriteBlip then Citizen.InvokeNative(removeHash, blips.spriteBlip) end
    end
    ActiveBlips = {}
end

local function RemoveZoneBlips(zoneKey, nativeHashes)
    local blips = ActiveBlips[zoneKey]
    if not blips then return end
    local removeHash = nativeHashes["REMOVE_BLIP"].hash
    if removeHash ~= 0 then
        if blips.radiusBlip then Citizen.InvokeNative(removeHash, blips.radiusBlip) end
        if blips.spriteBlip then Citizen.InvokeNative(removeHash, blips.spriteBlip) end
    end
    ActiveBlips[zoneKey] = nil
end

-- ============================================================
-- INITIALIZATION
-- ============================================================

Citizen.CreateThread(function()
    -- Step 1: Discover actual RDR3 native hashes
    local nativeHashes = DiscoverNativeHashes()

    -- Step 2: Run blip creation self-test with discovered hashes
    print("^5======================================^7")
    print("^5  ATLAS BLIPS — ATTEMPTING BLIP CREATION^7")
    print("^5======================================^7")
    local blipsWorking = RunSelfTest(nativeHashes)

    if blipsWorking then
        print("^2[ATLAS BLIPS]^7 *** BLIP CREATION TEST PASSED! ***")

        -- Step 3: Request zone data from server
        Citizen.Wait(2000)
        print("^2[ATLAS BLIPS]^7 Requesting zone data from server")
        TriggerServerEvent('atlas_blips:server:playerLoaded')

        -- Handle incoming zone data
        RegisterNetEvent('atlas_blips:client:loadZones')
        AddEventHandler('atlas_blips:client:loadZones', function(blipPayload)
            print("^2[ATLAS BLIPS]^7 Received " .. #blipPayload .. " zones from server")
            Citizen.Wait(500)
            RemoveAllBlips(nativeHashes)

            local miningCount, woodcuttingCount, failCount = 0, 0, 0
            for _, zoneData in ipairs(blipPayload) do
                local zoneKey = zoneData.type .. "_" .. zoneData.id
                RemoveZoneBlips(zoneKey, nativeHashes)

                local blips = CreateZoneBlips(zoneData, nativeHashes)
                if blips then
                    ActiveBlips[zoneKey] = blips
                    if zoneData.type == "mining" then miningCount = miningCount + 1
                    else woodcuttingCount = woodcuttingCount + 1 end
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
    else
        print("^1[ATLAS BLIPS]^7 *** ALL BLIP CREATION METHODS FAILED ***")
        print("^1[ATLAS BLIPS]^7 *** Blips will NOT be created ***")
    end
end)

-- ============================================================
-- COMMANDS
-- ============================================================

RegisterCommand('selftestblips', function(source, args)
    print("^2[ATLAS BLIPS]^7 Re-running discovery & self-test...")
    local nh = DiscoverNativeHashes()
    local ok = RunSelfTest(nh)
    print("^2[ATLAS BLIPS]^7 Self-test: " .. tostring(ok))
end)

-- ============================================================
-- CLEANUP
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        -- We don't have nativeHashes here, just clear ActiveBlips
        ActiveBlips = {}
    end
end)
