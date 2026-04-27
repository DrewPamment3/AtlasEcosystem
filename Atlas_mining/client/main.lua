local isBusy = false
local CampRegistry = {}    -- {campId, rockIndex, coords, entity (rock or mined), isDepleted}
local RenderedCamps = {}   -- Camps currently being rendered
local MinedRockMap = {}    -- Map of rockIndex -> depleted rock entity for quick lookup

-- Pickaxe prop state (vorp_mining animation logic)
local tool = nil
local hastool = false

-- Startup debug
print("^2[ATLAS MINING CLIENT]^7 Client script loaded. Waiting 5s before playerLoaded trigger...")

-- [[ UI ]]
local function DrawMiningPrompt()
    local x, y = 0.5, 0.92
    DrawRect(x, y, 0.12, 0.045, 0, 0, 0, 180)
    SetTextScale(0.38, 0.38)
    SetTextColor(0, 0, 0, 255)
    SetTextCentre(true)
    local gText = CreateVarString(10, "LITERAL_STRING", "G")
    DrawRect(x - 0.035, y, 0.022, 0.032, 255, 255, 255, 255)
    DisplayText(gText, x - 0.035, y - 0.016)
    SetTextScale(0.35, 0.35)
    SetTextColor(255, 255, 255, 255)
    SetTextCentre(false)
    SetTextFontForCurrentCommand(1)
    DisplayText(CreateVarString(10, "LITERAL_STRING", "MINE ROCK"), x - 0.018, y - 0.016)
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

-- [[ INTERACTION LOOP ]]
Citizen.CreateThread(function()
    while true do
        Citizen.Wait(0)
        local playerPed = PlayerPedId()
        local pCoords = GetEntityCoords(playerPed)
        local pForward = GetEntityForwardVector(playerPed)

        -- Start at chest level, cast forward and downward to hit rocks on ground
        local start = pCoords + vec3(0, 0, 1.3)
        local target = pCoords + (pForward * 2.5) + vec3(0, 0, 0.3) -- 2.5m forward, 0.3m up (angled down from chest)

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
                DrawMiningPrompt()
                if IsControlJustPressed(0, AtlasMiningConfig.InteractionKey) and not isBusy then
                    print("^2[Mine Debug]^7 SUCCESS: Interaction for Camp " ..
                        matchedNode.campId .. " | Rock " .. matchedNode.rockIndex)
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
-- MINING FLOW (Animation + Timing)
-- =============================================

RegisterNetEvent('atlas_mining:client:beginMining')
AddEventHandler('atlas_mining:client:beginMining', function(token)
    print("^2[MINE FLOW]^7 beginMining [CLIENT] - Token: " .. token)
    print("^2[MINE FLOW]^7 Setting isBusy = true")
    isBusy = true

    -- Equip pickaxe with vorp_mining animation style
    local pickaxeHash = GetHashKey(AtlasMiningConfig.PickaxePropModel)
    EquipPickaxe(pickaxeHash)

    -- Play mining swing animation
    print("^2[MINE FLOW]^7 Playing mining swing animation: " .. AtlasMiningConfig.MiningAnimDict)
    PlayMineSwingAnimation()

    print("^2[MINE FLOW]^7 Waiting " .. AtlasMiningConfig.MineAnimationTime .. "ms for animation")
    Citizen.Wait(AtlasMiningConfig.MineAnimationTime)

    -- Clear tasks and remove pickaxe
    print("^2[MINE FLOW]^7 Animation complete, clearing tasks and removing pickaxe")
    ClearPedTasks(PlayerPedId())
    RemovePickaxeFromPlayer()

    print("^2[MINE FLOW]^7 Setting isBusy = false, sending finishMine to server")
    isBusy = false
    TriggerServerEvent('atlas_mining:server:finishMine', token)
    print("^2[MINE FLOW]^7 finishMine event sent")
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
