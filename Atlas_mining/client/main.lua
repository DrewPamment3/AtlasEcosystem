local isBusy = false
local CampRegistry = {}    -- {campId, rockIndex, coords, entity (rock or mined), isDepleted}
local RenderedCamps = {}   -- Camps currently being rendered
local MinedRockMap = {}    -- Map of rockIndex -> depleted rock entity for quick lookup

-- Tool validation cache
local ValidationCache = {} -- Cache validation results to avoid spamming server
local LastValidationRequest = 0 -- Prevent spamming validation requests
local CurrentPromptState = { text = "MINE ROCK", disabled = false } -- Current prompt state

-- Interaction throttling to prevent G-key spam
local LastInteractionTime = 0
local InteractionCooldown = 1000 -- 1 second cooldown between interactions

-- Pickaxe prop state (vorp_mining animation logic)
local tool = nil
local hastool = false

-- Startup debug
print("^2[ATLAS MINING CLIENT]^7 Client script loaded. Waiting 5s before playerLoaded trigger...")

-- Audio Bank Loading
local audioLoaded = false

local function LoadMiningAudioBanks()
    if audioLoaded then return end
    
    print("^3[ATLAS MINING AUDIO]^7 Loading audio banks for RedM...")
    
    local banks = {"HUD_GOLD_MINING_SOUNDSET", "OFF_MISSION_SOUNDSET"}
    local allLoaded = true
    
    for _, bank in ipairs(banks) do
        local success = pcall(function()
            RequestAmbientAudioBank(bank)
        end)
        
        if success then
            print("^2[ATLAS MINING AUDIO]^7 Requested: " .. bank)
        else
            print("^1[ATLAS MINING AUDIO]^7 Failed to request: " .. bank)
            allLoaded = false
        end
    end
    
    -- Wait for banks to load (RedM loads asynchronously)
    print("^3[ATLAS MINING AUDIO]^7 Waiting for audio banks to load...")
    Citizen.Wait(3000) -- Give RedM time to load the banks
    
    audioLoaded = true
    print("^2[ATLAS MINING AUDIO]^7 Audio system ready!")
end

-- RDR3/RedM sound playing function with correct native signatures
local function PlayMiningSound(soundName, soundSet)
    -- RDR3 PlaySoundFrontend: (soundName, soundSet, p2, p3)
    -- No soundId/integer as the first argument like GTA V
    local success = pcall(function()
        PlaySoundFrontend(soundName, soundSet, true, 0)
    end)
    
    if success then
        if AtlasMiningConfig.DebugLogging then
            print("^2[MINING SOUND]^7 Played: " .. soundName .. " from " .. soundSet)
        end
        return true
    else
        -- Fallback: Try PlaySoundFromEntity if PlaySoundFrontend fails
        local success2 = pcall(function()
            PlaySoundFromEntity(soundName, PlayerPedId(), soundSet, true, 0, 0)
        end)
        
        if success2 then
            if AtlasMiningConfig.DebugLogging then
                print("^2[MINING SOUND]^7 Played (fallback): " .. soundName .. " from " .. soundSet)
            end
            return true
        else
            print("^1[MINING SOUND]^7 Failed to play sound: " .. soundName .. " from " .. soundSet)
            return false
        end
    end
end

-- Load audio banks on script start
Citizen.CreateThread(function()
    Citizen.Wait(3000) -- Wait longer for RedM to be ready
    print("^3[ATLAS MINING AUDIO]^7 Initializing audio system...")
    LoadMiningAudioBanks()
    
    -- Force load if it failed
    if not audioLoaded then
        print("^3[ATLAS MINING AUDIO]^7 First attempt failed, trying again...")
        Citizen.Wait(2000)
        LoadMiningAudioBanks()
    end
    
    -- Final fallback - just mark as loaded and try direct sound calls
    if not audioLoaded then
        print("^3[ATLAS MINING AUDIO]^7 Using fallback mode - sounds will be attempted directly")
        audioLoaded = true
    end
end)

-- [[ UI ]]
local function DrawMiningPrompt(promptText, isDisabled)
    promptText = promptText or "MINE ROCK"
    isDisabled = isDisabled or false
    
    local x, y = 0.5, 0.92
    local promptWidth = 0.15 -- Wider to accommodate longer text
    
    -- Background color - darker if disabled
    local bgAlpha = isDisabled and 120 or 180
    DrawRect(x, y, promptWidth, 0.045, 0, 0, 0, bgAlpha)
    
    -- G key button
    local buttonColor = isDisabled and {150, 150, 150, 255} or {255, 255, 255, 255}
    SetTextScale(0.38, 0.38)
    SetTextColor(0, 0, 0, 255)
    SetTextCentre(true)
    local gText = CreateVarString(10, "LITERAL_STRING", "G")
    DrawRect(x - 0.055, y, 0.022, 0.032, buttonColor[1], buttonColor[2], buttonColor[3], buttonColor[4])
    DisplayText(gText, x - 0.055, y - 0.016)
    
    -- Prompt text - greyed out if disabled
    SetTextScale(0.32, 0.32) -- Smaller text to fit longer messages
    if isDisabled then
        SetTextColor(150, 150, 150, 255) -- Grey text for disabled
    else
        SetTextColor(255, 255, 255, 255) -- White text for enabled
    end
    SetTextCentre(false)
    SetTextFontForCurrentCommand(1)
    DisplayText(CreateVarString(10, "LITERAL_STRING", promptText), x - 0.035, y - 0.016)
end

-- [[ ANIMATION LOGIC (from vorp_mining) ]]

local function Anim(actor, dict, body, duration, flags, introtiming, exittiming)
    CreateThread(function()
        RequestAnimDict(dict)
        local dur = duration or -1
        local flag = flags or 1
        local intro = tonumber(introtiming) or 1.0
        local exit = tonumber(exittiming) or 1.0
        local timeout = 5
        while (not HasAnimDictLoaded(dict) and timeout > 0) do
            timeout = timeout - 1
            if timeout == 0 then
                print("^1[Atlas Mining]^7 Animation Failed to Load: " .. dict)
            end
            Wait(300)
        end
        TaskPlayAnim(actor, dict, body, intro, exit, dur, flag, 1, false, 0, false, "", true)
    end)
end

local function EquipPickaxe(toolhash)
    if tool then
        DeleteEntity(tool)
    end
    Wait(100)

    local ped = PlayerPedId()
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 0.0, 0.0)
    tool = CreateObject(toolhash, coords.x, coords.y, coords.z, true, false, false, false)
    AttachEntityToEntity(
        tool,
        ped,
        GetPedBoneIndex(ped, AtlasMiningConfig.PickaxeAttachBone),
        0.0, 0.0, 0.0, -- offsets
        0.0, 0.0, 0.0, -- rotations
        false, false, false, false,
        2, true, false, false
    )
    -- Apply carry style (same as vorp_mining pitchfork carry)
    Citizen.InvokeNative(0x923583741DC87BCE, ped, 'arthur_healthy')
    Citizen.InvokeNative(0x89F5E7ADECCCB49C, ped, "carry_pitchfork")
    Citizen.InvokeNative(0x2208438012482A1A, ped, true, true)
    ForceEntityAiAndAnimationUpdate(tool, true)
    Citizen.InvokeNative(0x3A50753042B6891B, ped, "PITCH_FORKS")

    hastool = true
end

local function RemovePickaxeFromPlayer()
    hastool = false
    if not tool then return end

    local ped = PlayerPedId()
    Citizen.InvokeNative(0xED00D72F81CF7278, tool, 1, 1)
    DeleteObject(tool)
    Citizen.InvokeNative(0x58F7DB5BD8FA2288, ped) -- Cancel Walk Style
    ClearPedDesiredLocoForModel(ped)
    ClearPedDesiredLocoMotionType(ped)
    tool = nil
end

local function PlayMineSwingAnimation()
    local ped = PlayerPedId()
    Anim(
        ped,
        AtlasMiningConfig.MiningAnimDict,
        AtlasMiningConfig.MiningAnimBody,
        -1,
        0
    )
end

-- [[ SPAWNING ]]

local function SpawnLocalRock(node, campId, rockIndex, isDepleted)
    isDepleted = isDepleted or false
    local modelName
    if isDepleted then
        modelName = AtlasMiningConfig.MinedRockModel
    else
        modelName = node.model_name
    end
    local modelHash = GetHashKey(modelName)

    print("^3[SPAWN ROCK]^7 Attempting to spawn " .. modelName .. " for camp " .. campId .. " rockIndex " .. rockIndex .. " isDepleted=" .. tostring(isDepleted))

    -- Validate model
    if not IsModelValid(modelHash) then
        print("^1[SPAWN ROCK]^7 ERROR: Invalid model: " .. modelName .. " (hash: " .. modelHash .. ")")
        return
    end

    if not HasModelLoaded(modelHash) then
        print("^3[SPAWN ROCK]^7 Loading model: " .. modelName)
        RequestModel(modelHash)
        local timeout = GetGameTimer() + AtlasMiningConfig.ModelLoadTimeout
        while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
            Citizen.Wait(1)
        end

        if not HasModelLoaded(modelHash) then
            print("^1[SPAWN ROCK]^7 Failed to load model " .. modelName .. " within timeout")
            return
        end
        print("^2[SPAWN ROCK]^7 Model loaded: " .. modelName)
    end

    local foundGround, groundZ = GetGroundZFor_3dCoord(node.x, node.y, 1000.0, 0)
    if not foundGround then
        print("^1[SPAWN ROCK]^7 No ground found at (" .. node.x .. ", " .. node.y .. "), using node.z=" .. node.z)
        groundZ = node.z
    end
    local zOffset = AtlasMiningConfig.GetRockZOffset(modelName)
    local spawnZ = groundZ - zOffset
    print("^3[SPAWN ROCK]^7 Spawning at (" .. string.format("%.1f", node.x) .. ", " .. string.format("%.1f", node.y) .. ", " .. string.format("%.1f", spawnZ) .. ") groundZ=" .. string.format("%.1f", groundZ) .. " zOffset=" .. zOffset)

    local rock = CreateObject(modelHash, node.x, node.y, spawnZ, false, false, false)

    if rock == 0 then
        print("^1[SPAWN ROCK]^7 ERROR: CreateObject returned 0 for " .. modelName)
        return
    end

    print("^2[SPAWN ROCK]^7 Created entity " .. rock .. " for " .. modelName)

    SetEntityRotation(rock, 0.0, 0.0, math.random(0, 360) + 0.0, 2, true)
    FreezeEntityPosition(rock, true)
    SetEntityAsMissionEntity(rock, true, true)

    table.insert(CampRegistry, {
        campId = campId,
        rockIndex = rockIndex,
        coords = vec3(node.x, node.y, node.z),
        entity = rock,
        isDepleted = isDepleted
    })

    print("^2[SPAWN ROCK]^7 CampRegistry now has " .. #CampRegistry .. " entries")

    if isDepleted then
        MinedRockMap[rockIndex] = rock
    end

    SetModelAsNoLongerNeeded(modelHash)
    return rock
end

-- Function to request validation from server (throttled to prevent spam)
local function RequestValidation(campId)
    local currentTime = GetGameTimer()
    if currentTime - LastValidationRequest < 2000 then -- 2 second throttle
        return false
    end
    
    LastValidationRequest = currentTime
    TriggerServerEvent('atlas_mining:server:requestValidation', campId)
    return true
end

-- Event to receive validation results from server
RegisterNetEvent('atlas_mining:client:validationResult')
AddEventHandler('atlas_mining:client:validationResult', function(campId, promptText, isDisabled)
    ValidationCache[campId] = {
        promptText = promptText,
        isDisabled = isDisabled,
        timestamp = GetGameTimer()
    }
    CurrentPromptState.text = promptText
    CurrentPromptState.disabled = isDisabled
end)

-- [[ INTERACTION LOOP ]]
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        -- Start at waist level, cast forward and downward to hit rocks on ground
        local start = pCoords + vec3(0, 0, 0.6)
        local target = pCoords + (pForward * 2.5) + vec3(0, 0, 0.3) -- 2.5m forward, 0.3m up (angled down from waist)

        -- Always show debug line (you can disable this later by setting DebugLogging to false)
        if AtlasMiningConfig.DebugLogging then
            DrawLine(start.x, start.y, start.z, target.x, target.y, target.z, 255, 0, 0, 255)
        end

        local ray = StartShapeTestRay(start.x, start.y, start.z, target.x, target.y, target.z, 255, playerPed, 0)
        local _, hit, _, _, entityHit, _ = GetShapeTestResult(ray)

        if hit == 1 and entityHit ~= 0 then
            local entCoords = GetEntityCoords(entityHit)
            local matchedNode = nil
            for _, node in ipairs(CampRegistry) do
                -- Increased tolerance from 1.5 to 3.0 to account for large rock models
                if #(entCoords - node.coords) < 3.0 and not node.isDepleted then
                    matchedNode = node
                    break
                end
            end

            if matchedNode then
                -- Check if we have cached validation for this camp
                local campId = matchedNode.campId
                local cachedValidation = ValidationCache[campId]
                local currentTime = GetGameTimer()
                
                -- If no cache or cache is old (>10 seconds), request new validation
                if not cachedValidation or (currentTime - cachedValidation.timestamp > 10000) then
                    if RequestValidation(campId) then
                        -- Use default prompt while waiting for validation
                        CurrentPromptState.text = "MINE ROCK"
                        CurrentPromptState.disabled = false
                    end
                else
                    -- Use cached validation
                    CurrentPromptState.text = cachedValidation.promptText
                    CurrentPromptState.disabled = cachedValidation.isDisabled
                end
                
                DrawMiningPrompt(CurrentPromptState.text, CurrentPromptState.disabled)
                
                -- Only allow interaction if not disabled, not busy, and not on cooldown
                if IsControlJustPressed(0, AtlasMiningConfig.InteractionKey) and not isBusy and not CurrentPromptState.disabled then
                    local currentTime = GetGameTimer()
                    
                    -- Check interaction cooldown to prevent G-key spam
                    if currentTime - LastInteractionTime < InteractionCooldown then
                        print("^3[Mine Debug]^7 G key pressed but on cooldown (" .. (InteractionCooldown - (currentTime - LastInteractionTime)) .. "ms remaining)")
                        return
                    end
                    
                    print("^2[Mine Debug]^7 SUCCESS: Interaction for Camp " ..
                        matchedNode.campId .. " | Rock " .. matchedNode.rockIndex)
                    
                    -- Set interaction time and busy state immediately
                    LastInteractionTime = currentTime
                    isBusy = true  -- Set busy immediately to prevent double requests
                    
                    TriggerServerEvent('atlas_mining:server:requestStart', entCoords, matchedNode.campId,
                        matchedNode.rockIndex, {
                            x = matchedNode.coords.x,
                            y = matchedNode.coords.y,
                            z = matchedNode.coords.z
                        })
                end
            end
        end
    end
end)

-- [[ UTILITY COMMANDS ]]

RegisterCommand('debugrocks', function(source, args, rawCommand)
    print("^3[Atlas Mining Debug]^7 Total in Registry: " .. #CampRegistry)
    for i, node in ipairs(CampRegistry) do
        print(string.format("Node %s: Camp %s | Rock %s | Entity %s | IsDepleted %s", i, node.campId, node.rockIndex,
            tostring(node.entity), tostring(node.isDepleted)))
    end
end)

--- List all available rock models from config
RegisterCommand('listrocks', function(source, args, rawCommand)
    print("^2[Atlas Mining]^7 Configured Rock Models:")
    print("^3================================================^7")
    if #AtlasMiningConfig.Rocks == 0 then
        print("^1  (No rock models configured yet. Add them to Config.Rocks in shared/config.lua)")
    else
        for _, modelName in ipairs(AtlasMiningConfig.Rocks) do
            print("^2 - ^7" .. modelName)
        end
    end
    print("^3================================================^7")
    print("^3Usage:^7 /createcamp [radius] [count] [tier] [model] [name]")
    print("^3Test:^7 /testspawn [model] - spawns rock in front of you")
end)

--- DEBUG: Check audio bank loading status (/checkaudio)
RegisterCommand('checkaudio', function(source, args, rawCommand)
    print("^2[Atlas Mining Audio]^7 Audio Bank Status:")
    print("^3================================================^7")
    print("^3Audio System Loaded:^7 " .. tostring(audioLoaded))
    print("^3Sound Effects Enabled:^7 " .. tostring(AtlasMiningConfig.SoundEffects.enabled))
    print("^3RedM Compatibility Mode:^7 Active")
    print("^3================================================^7")
    
    if audioLoaded then
        print("^2✓ Audio system ready for mining sounds!^7")
        print("^2  Sounds will be played using RedM-compatible methods^7")
    else
        print("^1✗ Audio system not ready. Use /reloadaudio to try again.^7")
    end
    
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 255 },
        multiline = true,
        args = { "Audio Status", "Audio loaded: " .. tostring(audioLoaded) .. " - Check console for details" }
    })
end)

--- DEBUG: Reload audio banks (/reloadaudio)
RegisterCommand('reloadaudio', function(source, args, rawCommand)
    print("^3[Atlas Mining Audio]^7 Manually reloading audio banks...")
    audioLoaded = false
    LoadMiningAudioBanks()
    
    TriggerEvent('chat:addMessage', {
        color = { 255, 165, 0 },
        multiline = true,
        args = { "Audio Reload", "Attempting to reload audio banks - check console" }
    })
end)

--- DEBUG: Force enable audio (/forceaudio)
RegisterCommand('forceaudio', function(source, args, rawCommand)
    print("^3[Atlas Mining Audio]^7 Force enabling audio system...")
    audioLoaded = true
    
    print("^2[Atlas Mining Audio]^7 Audio system force enabled!")
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 0 },
        multiline = true,
        args = { "Audio Force", "Audio system enabled - try /testminingsounds" }
    })
end)

--- DEBUG: Spawn any model in front of player for testing (/testspawn <modelName>)
RegisterCommand('testspawn', function(source, args, rawCommand)
    if not args[1] then
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = { "Debug", "Usage: /testspawn [model]" }
        })
        return
    end

    local modelName = args[1]
    local modelHash = GetHashKey(modelName)

    -- Validate model exists
    if not IsModelValid(modelHash) then
        print("^1[Atlas Mining Debug]^7 Invalid model: " .. modelName)
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = { "Debug", "Invalid model: " .. modelName .. ". Check spelling." }
        })
        return
    end

    -- Load model
    if not HasModelLoaded(modelHash) then
        RequestModel(modelHash)
        local timeout = GetGameTimer() + 5000
        while not HasModelLoaded(modelHash) and GetGameTimer() < timeout do
            Citizen.Wait(1)
        end

        if not HasModelLoaded(modelHash) then
            print("^1[Atlas Mining Debug]^7 Failed to load model " .. modelName .. " within timeout")
            TriggerEvent('chat:addMessage', {
                color = { 255, 0, 0 },
                multiline = true,
                args = { "Debug", "Failed to load: " .. modelName }
            })
            return
        end
    end

    -- Position in front of player
    local ped = PlayerPedId()
    local pCoords = GetEntityCoords(ped)
    local heading = GetEntityHeading(ped)
    local forwardX = math.sin(math.rad(heading))
    local forwardY = -math.cos(math.rad(heading))

    -- Spawn 3 meters in front of player
    local spawnX = pCoords.x + (forwardX * 3)
    local spawnY = pCoords.y + (forwardY * 3)
    local spawnZ = pCoords.z

    -- Get ground Z
    local found, groundZ = GetGroundZFor_3dCoord(spawnX, spawnY, 1000.0, 0)
    if found then
        spawnZ = groundZ - 0.2
    end

    -- Spawn the object
    local obj = CreateObject(modelHash, spawnX, spawnY, spawnZ, false, false, false)
    SetEntityRotation(obj, 0.0, 0.0, 0.0, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityAsMissionEntity(obj, true, true)
    SetModelAsNoLongerNeeded(modelHash)

    print("^2[Atlas Mining Debug]^7 Spawned " .. modelName .. " at (" .. string.format("%.1f", spawnX) .. ", " .. string.format("%.1f", spawnY) .. ", " .. string.format("%.1f", spawnZ) .. ")")
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 0 },
        multiline = true,
        args = { "Debug", "Spawned: " .. modelName .. " in front of you" }
    })
end)

--- DEBUG: Test mining sound effects (/testminingsounds)
RegisterCommand('testminingsounds', function(source, args, rawCommand)
    if not AtlasMiningConfig.SoundEffects.enabled then
        TriggerEvent('chat:addMessage', {
            color = { 255, 165, 0 },
            multiline = true,
            args = { "Mining Sounds", "Sound effects are disabled in config!" }
        })
        return
    end

    print("^2[Atlas Mining Sounds]^7 Testing mining sound sequence...")
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 0 },
        multiline = true,
        args = { "Mining Sounds", "Testing sound sequence - check console for details" }
    })

    local sounds = AtlasMiningConfig.SoundEffects.sounds
    local timing = AtlasMiningConfig.SoundEffects.timing
    
    -- Test each sound with proper timing and individual bank loading
    Citizen.CreateThread(function()
        print("^3[SOUND TEST]^7 Playing pickaxe strike sound...")
        PlayMiningSound(sounds.pickaxeStrike.name, sounds.pickaxeStrike.soundset)
        
        Citizen.Wait(timing.metalHit - timing.pickaxeStrike)
        print("^3[SOUND TEST]^7 Playing metal hit sound...")
        PlayMiningSound(sounds.metalHit.name, sounds.metalHit.soundset)
        
        Citizen.Wait(timing.rockChip - timing.metalHit)
        print("^3[SOUND TEST]^7 Playing rock chip sound...")
        PlayMiningSound(sounds.rockChip.name, sounds.rockChip.soundset)
        
        print("^2[SOUND TEST]^7 Sound test complete!")
    end)
end)

--- DEBUG: Test individual mining sounds (/testminingsound <type>)
RegisterCommand('testminingsound', function(source, args, rawCommand)
    if not args[1] then
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = { "Mining Sounds", "Usage: /testminingsound [pickaxeStrike|metalHit|rockChip|pebbleDrop]" }
        })
        return
    end

    local soundType = args[1]
    local sounds = AtlasMiningConfig.SoundEffects.sounds
    
    if not sounds[soundType] then
        TriggerEvent('chat:addMessage', {
            color = { 255, 0, 0 },
            multiline = true,
            args = { "Mining Sounds", "Invalid sound type: " .. soundType }
        })
        return
    end

    local sound = sounds[soundType]
    print("^2[SOUND TEST]^7 Playing " .. soundType .. ": " .. sound.name .. " from " .. sound.soundset)
    print("^3[SOUND TEST]^7 Description: " .. sound.description)
    
    -- Use the new proper sound system
    PlayMiningSound(sound.name, sound.soundset)
    
    TriggerEvent('chat:addMessage', {
        color = { 0, 255, 0 },
        multiline = true,
        args = { "Mining Sounds", "Played: " .. soundType .. " (" .. sound.description .. ")" }
    })
end)

-- [[ EVENTS ]]

RegisterNetEvent('atlas_mining:client:loadCamps')
AddEventHandler('atlas_mining:client:loadCamps', function(camps, nodes, campRockStates)
    print("^2[LOAD CAMPS]^7 loadCamps received! camps=" .. #camps .. " nodes=" .. #nodes)
    if #camps > 0 then
        local campIds = {}
        for _, c in ipairs(camps) do
            table.insert(campIds, tostring(c.id))
        end
        print("^2[LOAD CAMPS]^7 Camp IDs: " .. table.concat(campIds, ", "))
    end
    if #nodes > 0 then
        local sampleNode = nodes[1]
        print("^2[LOAD CAMPS]^7 First node: camp_id=" .. tostring(sampleNode.camp_id) .. " model=" .. tostring(sampleNode.model_name) .. " pos=(" .. string.format("%.1f", sampleNode.x) .. ", " .. string.format("%.1f", sampleNode.y) .. ", " .. string.format("%.1f", sampleNode.z) .. ")")
    end

    -- Clear existing registry
    for _, node in ipairs(CampRegistry) do
        if DoesEntityExist(node.entity) then
            DeleteEntity(node.entity)
        end
    end
    CampRegistry = {}
    MinedRockMap = {}
    RenderedCamps = {}

    -- Load camps in range
    for _, camp in ipairs(camps) do
        RenderedCamps[camp.id] = camp

        -- Find and spawn all rocks for this camp
        local rockIndex = 0
        for _, node in ipairs(nodes) do
            if node.camp_id == camp.id then
                rockIndex = rockIndex + 1
                local isDepleted = campRockStates[camp.id] and campRockStates[camp.id][rockIndex]

                if isDepleted then
                    -- Spawn depleted rock model
                    SpawnLocalRock(node, camp.id, rockIndex, true)
                else
                    -- Spawn regular rock
                    SpawnLocalRock(node, camp.id, rockIndex, false)
                end
            end
        end
    end

    print("^2[LOAD CAMPS]^7 Done — CampRegistry has " .. #CampRegistry .. " entries")
end)

RegisterNetEvent('atlas_mining:client:rockMinedDeath')
AddEventHandler('atlas_mining:client:rockMinedDeath', function(campId, rockIndex, nodeData)
    print("^2[MINE FLOW]^7 rockMinedDeath [CLIENT] received - Camp " .. campId .. " | Rock " .. rockIndex)
    print("^2[MINE FLOW]^7 CampRegistry size: " .. #CampRegistry)

    -- Find and delete the rock entity
    local found = false
    for i = #CampRegistry, 1, -1 do
        local node = CampRegistry[i]
        if node.campId == campId and node.rockIndex == rockIndex and not node.isDepleted then
            print("^2[MINE FLOW]^7 Found matching rock at index " .. i .. ", deleting entity " .. tostring(node.entity))
            if DoesEntityExist(node.entity) then
                DeleteEntity(node.entity)
                found = true
            end
            table.remove(CampRegistry, i)
            break
        end
    end

    if not found then
        print("^1[MINE FLOW]^7 ERROR: No matching rock found in registry!")
    end

    -- Spawn depleted rock model
    SpawnLocalRock(nodeData, campId, rockIndex, true)
    print("^3[Atlas Mining]^7 Rock " .. rockIndex .. " in camp " .. campId .. " mined, depleted model spawned")
end)

RegisterNetEvent('atlas_mining:client:rockRespawn')
AddEventHandler('atlas_mining:client:rockRespawn', function(campId, rockIndex, nodeData)
    -- Find and delete the depleted rock entity
    for i = #CampRegistry, 1, -1 do
        if CampRegistry[i].campId == campId and CampRegistry[i].rockIndex == rockIndex and CampRegistry[i].isDepleted then
            if DoesEntityExist(CampRegistry[i].entity) then
                DeleteEntity(CampRegistry[i].entity)
            end
            table.remove(CampRegistry, i)
            break
        end
    end

    MinedRockMap[rockIndex] = nil

    -- Respawn rock
    SpawnLocalRock(nodeData, campId, rockIndex, false)
    print("^3[Atlas Mining]^7 Rock " .. rockIndex .. " in camp " .. campId .. " respawned")
end)

RegisterNetEvent('atlas_mining:client:wipeSpecificCamp')
AddEventHandler('atlas_mining:client:wipeSpecificCamp', function(campId)
    for i = #CampRegistry, 1, -1 do
        if CampRegistry[i].campId == campId then
            if DoesEntityExist(CampRegistry[i].entity) then DeleteEntity(CampRegistry[i].entity) end
            table.remove(CampRegistry, i)
        end
    end
end)

RegisterNetEvent('atlas_mining:client:wipeAllCamps')
AddEventHandler('atlas_mining:client:wipeAllCamps', function()
    for i = #CampRegistry, 1, -1 do
        if DoesEntityExist(CampRegistry[i].entity) then DeleteEntity(CampRegistry[i].entity) end
        table.remove(CampRegistry, i)
    end
    CampRegistry = {}
    MinedRockMap = {}
    RenderedCamps = {}
end)

RegisterNetEvent('atlas_mining:client:spawnSingleNode')
AddEventHandler('atlas_mining:client:spawnSingleNode', function(node, campId)
    -- Count existing rocks for this camp to get the new index
    local rockIndex = 0
    for _, registryNode in ipairs(CampRegistry) do
        if registryNode.campId == campId and not registryNode.isDepleted then
            rockIndex = rockIndex + 1
        end
    end
    rockIndex = rockIndex + 1

    SpawnLocalRock(node, campId, rockIndex, false)
end)

-- Generate camp nodes (called after /createcamp)
-- Client picks random positions, server picks the actual model to keep everything synced
RegisterNetEvent('atlas_mining:client:generateCampNodes')
AddEventHandler('atlas_mining:client:generateCampNodes', function(cId, center, radius, count, model)
    for i = 1, count do
        local angle, r = math.random() * 2 * math.pi, radius * math.sqrt(math.random())
        local x = center.x + r * math.cos(angle)
        local y = center.y + r * math.sin(angle)
        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, 1000.0, 0)
        if foundGround then
            -- Pass model (nil = server picks random from Config.Rocks)
            TriggerServerEvent('atlas_mining:server:saveNode', cId, vec3(x, y, groundZ), model)
        end
        Citizen.Wait(300)
    end
end)

-- =============================================
-- MINING FLOW WITH PROGRESS BAR (like woodcutting)
-- =============================================

local miningProgress = {
    active = false,
    token = nil,
    hitsRequired = 0,
    hitsCompleted = 0,
    animationDelay = AtlasMiningConfig.HitAnimationTime or 2500 -- Time between each hit
}

local function DrawMiningProgressBar()
    if not miningProgress.active then return end
    
    local progress = miningProgress.hitsCompleted / miningProgress.hitsRequired
    local x, y = 0.5, 0.85
    local width, height = 0.25, 0.02
    
    -- Debug: Print progress values
    if AtlasMiningConfig.DebugLogging then
        if GetGameTimer() % 1000 < 50 then -- Print every ~1 second to avoid spam
            print("^3[PROGRESS DEBUG]^7 Active: " .. tostring(miningProgress.active) .. 
                  " | Hits: " .. miningProgress.hitsCompleted .. "/" .. miningProgress.hitsRequired .. 
                  " | Progress: " .. string.format("%.2f", progress))
        end
    end
    
    -- Background (black)
    DrawRect(x, y, width, height, 0, 0, 0, 200)
    
    -- Progress sections
    local sectionWidth = width / miningProgress.hitsRequired
    for i = 1, miningProgress.hitsRequired do
        local sectionX = x - (width/2) + (sectionWidth * (i - 0.5))
        if i <= miningProgress.hitsCompleted then
            -- Completed section (grey)
            DrawRect(sectionX, y, sectionWidth * 0.95, height * 0.9, 128, 128, 128, 255)
        else
            -- Uncompleted section (transparent/black)
            DrawRect(sectionX, y, sectionWidth * 0.95, height * 0.9, 32, 32, 32, 255)
        end
    end
    
    -- Border (white)
    DrawRect(x, y - height/2 - 0.001, width + 0.004, 0.002, 255, 255, 255, 255) -- Top
    DrawRect(x, y + height/2 + 0.001, width + 0.004, 0.002, 255, 255, 255, 255) -- Bottom
    DrawRect(x - width/2 - 0.002, y, 0.002, height + 0.004, 255, 255, 255, 255) -- Left
    DrawRect(x + width/2 + 0.002, y, 0.002, height + 0.004, 255, 255, 255, 255) -- Right
    
    -- Text
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(true)
    SetTextFontForCurrentCommand(1)
    DisplayText(CreateVarString(10, "LITERAL_STRING", 
        "Mining Progress: " .. miningProgress.hitsCompleted .. "/" .. miningProgress.hitsRequired), x, y - 0.04)
end

-- Progress bar drawing thread
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        if miningProgress.active then
            DrawMiningProgressBar()
        else
            Citizen.Wait(500)
        end
    end
end)

local function DoMiningHit()
    local ped = PlayerPedId()
    
    -- Play mining swing animation
    PlayMineSwingAnimation()
    
    -- Create a separate thread for sound timing so it doesn't block the main flow
    Citizen.CreateThread(function()
        if AtlasMiningConfig.SoundEffects.enabled and audioLoaded then
            local sounds = AtlasMiningConfig.SoundEffects.sounds
            local timing = AtlasMiningConfig.SoundEffects.timing
            
            -- Wait for pickaxe strike timing, then play main strike sound
            Citizen.Wait(timing.pickaxeStrike)
            PlayMiningSound(sounds.pickaxeStrike.name, sounds.pickaxeStrike.soundset)
            
            -- Wait for metal hit timing, then play metallic "ting" sound
            local metalDelay = timing.metalHit - timing.pickaxeStrike
            if metalDelay > 0 then
                Citizen.Wait(metalDelay)
            end
            PlayMiningSound(sounds.metalHit.name, sounds.metalHit.soundset)
            
            -- Wait for rock chipping timing, then play chipping sound
            local chipDelay = timing.rockChip - timing.metalHit
            if chipDelay > 0 then
                Citizen.Wait(chipDelay)
            end
            PlayMiningSound(sounds.rockChip.name, sounds.rockChip.soundset)
            
            if AtlasMiningConfig.DebugLogging then
                print("^3[MINE SOUNDS]^7 Played sound sequence: Strike → Metal Hit → Rock Chip")
            end
        elseif AtlasMiningConfig.SoundEffects.enabled and not audioLoaded then
            print("^1[MINE SOUNDS]^7 Audio banks not loaded! Cannot play mining sounds.")
        end
    end)
    
    -- Wait for full animation time
    Citizen.Wait(miningProgress.animationDelay)
    
    -- Clear animation
    ClearPedTasks(ped)
    
    -- Increment progress
    miningProgress.hitsCompleted = miningProgress.hitsCompleted + 1
    
    print("^2[MINE PROGRESS]^7 Hit " .. miningProgress.hitsCompleted .. "/" .. miningProgress.hitsRequired .. " completed")
end

RegisterNetEvent('atlas_mining:client:beginMining')
AddEventHandler('atlas_mining:client:beginMining', function(token, hitsRequired)
    print("^2[MINE FLOW]^7 beginMining [CLIENT] - Token: " .. token .. " | Hits required: " .. hitsRequired)
    print("^2[MINE FLOW]^7 Setting isBusy = true")
    isBusy = true

    -- Initialize progress system
    miningProgress.active = true
    miningProgress.token = token
    miningProgress.hitsRequired = hitsRequired or AtlasMiningConfig.HitsRequired or 4
    miningProgress.hitsCompleted = 0

    local playerPed = PlayerPedId()
    local startCoords = GetEntityCoords(playerPed)
    local startHealth = GetEntityHealth(playerPed)
    local interrupted = false
    local interruptionReason = nil

    -- Equip pickaxe with vorp_mining animation style
    local pickaxeHash = GetHashKey(AtlasMiningConfig.PickaxePropModel)
    EquipPickaxe(pickaxeHash)

    -- Use the same swing-based system as woodcutting
    local lastSwingTime = 0
    local swingInProgress = false

    -- Interruption monitoring thread (like woodcutting)
    Citizen.CreateThread(function()
        print("^2[MINE FLOW]^7 Starting interruption monitoring...")
        
        while hastool and miningProgress.active and not interrupted do
            local currentHealth = GetEntityHealth(playerPed)
            
            -- 1. MOVEMENT INPUT DETECTION (WASD keys) - RDR2 controls
            local movementDetected = false
            
            -- Check for movement input (RDR2 control scheme)
            if IsControlPressed(0, GetHashKey("INPUT_MOVE_UP_ONLY")) or      -- W
               IsControlPressed(0, GetHashKey("INPUT_MOVE_DOWN_ONLY")) or    -- S  
               IsControlPressed(0, GetHashKey("INPUT_MOVE_LEFT_ONLY")) or    -- A
               IsControlPressed(0, GetHashKey("INPUT_MOVE_RIGHT_ONLY")) or   -- D
               IsControlPressed(0, GetHashKey("INPUT_MOVE_LR")) or           -- Left stick
               IsControlPressed(0, GetHashKey("INPUT_MOVE_UD")) then         -- Right stick
                movementDetected = true
                interruptionReason = "Movement input detected (player tried to move)"
            end
            
            -- 2. HEALTH/DAMAGE DETECTION
            if currentHealth < startHealth then
                interrupted = true
                interruptionReason = "Player took damage"
                break
            end
            
            -- 3. DEATH/DYING DETECTION
            if IsPedDeadOrDying(playerPed, false) then
                interrupted = true
                interruptionReason = "Player died or is dying"
                break
            end
            
            -- 4. COMBAT DETECTION
            if IsPedInCombat(playerPed, 0) then
                interrupted = true
                interruptionReason = "Player entered combat"
                break
            end
            
            -- 5. RAGDOLL DETECTION
            if IsPedRagdoll(playerPed) then
                interrupted = true
                interruptionReason = "Player ragdolled"
                break
            end
            
            -- 6. MOVEMENT INPUT INTERRUPTION
            if movementDetected then
                interrupted = true
                print("^1[MINE FLOW]^7 Interrupted - " .. interruptionReason)
                break
            end
            
            -- 6. SWING PROGRESSION (only if not interrupted)
            local currentTime = GetGameTimer()
            if not swingInProgress and (currentTime - lastSwingTime) > (1500 + math.random(500, 1000)) then
                if miningProgress.hitsCompleted < miningProgress.hitsRequired then
                    swingInProgress = true
                    DoMiningHit()
                    lastSwingTime = currentTime
                    swingInProgress = false
                else
                    -- All swings completed
                    print("^2[MINE FLOW]^7 All swings completed!")
                    break
                end
            end

            Wait(50) -- Check every 50ms for responsive interruption detection
        end

        -- Cleanup
        miningProgress.active = false
        ClearPedTasks(playerPed)
        RemovePickaxeFromPlayer()
        
        print("^2[MINE FLOW]^7 Progress complete - Interrupted: " .. tostring(interrupted))
        if interrupted and interruptionReason then
            print("^3[MINE FLOW]^7 Interruption reason: " .. interruptionReason)
        end

        if interrupted then
            print("^1[MINE FLOW]^7 Mining interrupted!")
            isBusy = false
        else
            print("^2[MINE FLOW]^7 Mining complete! Sending finishMine to server")
            isBusy = false
            TriggerServerEvent('atlas_mining:server:finishMine', miningProgress.token)
        end
    end)
end)

-- =============================================
-- INITIALIZATION
-- =============================================

Citizen.CreateThread(function()
    Citizen.Wait(5000)
    TriggerServerEvent('atlas_mining:server:playerLoaded')
end)

-- Periodic subscription update: refresh every 15 seconds
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(15000)
        TriggerServerEvent('atlas_mining:server:updateSubscriptions')
    end
end)

-- Clean up on resource stop
AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end
    RemovePickaxeFromPlayer()
end)
