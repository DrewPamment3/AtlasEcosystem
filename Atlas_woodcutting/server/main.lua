local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local SpawnedNodes = {}
local RestrictedZones = {}

--- @section Internal Helpers

local function SpawnTree(model, x, y, z, tier)
    -- CreateObject(modelHash, x, y, z, isNetworked, createHandle, dynamic)
    local tree = CreateObject(model, x, y, z, true, true, false)

    Citizen.Wait(50) -- Brief wait for server bucket/entity sync

    if DoesEntityExist(tree) then
        FreezeEntityPosition(tree, true)
        SetEntityAsMissionEntity(tree, true, true) -- Prevents engine despawning
        SpawnedNodes[tree] = { tier = tier or 1 }
        return tree
    end
    return nil
end

-- Cleanup entities on script stop to prevent stacking "ghost" trees
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    local count = 0
    for entity, _ in pairs(SpawnedNodes) do
        if DoesEntityExist(entity) then
            DeleteEntity(entity)
            count = count + 1
        end
    end
    print("^1[Atlas Woodcutting]^7 Cleanup: Deleted " .. count .. " spawned entities.")
end)

--- @section Initialization

Citizen.CreateThread(function()
    Citizen.Wait(2000) -- Wait for DB handshake

    -- Load Zones
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_zones', {}, function(zones)
        if zones then RestrictedZones = zones end
    end)

    -- Load and Spawn Nodes
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            local count = 0
            for _, node in ipairs(nodes) do
                local tree = SpawnTree(node.model_hash, node.x, node.y, node.z, 1)
                if tree then count = count + 1 end
            end
            print("^2[Atlas Woodcutting]^7 Persistent Start: Spawned " .. count .. " nodes.")
        end
    end)
end)

--- @section Forest & Node Management

RegisterCommand('createforest', function(source, args)
    local _source = source
    local radius = tonumber(args[1]) or 20.0
    local count = tonumber(args[2]) or 10
    local tier = tonumber(args[3]) or 1
    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local model = 1035651700 -- Default Pine

    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier) VALUES (?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier }, function(forestId)
            if forestId then
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, forestId, pCoords, radius,
                    count, model)
            end
        end)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, model)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_hash) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, model }, function(id)
            SpawnTree(model, coords.x, coords.y, coords.z, 1)
        end)
end)

RegisterCommand('azone', function(source, args)
    local radius = tonumber(args[1]) or 50.0
    local pCoords = GetEntityCoords(GetPlayerPed(source))

    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_zones (x, y, z, radius) VALUES (?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius }, function(id)
            table.insert(RestrictedZones, { x = pCoords.x, y = pCoords.y, z = pCoords.z, radius = radius })
            print("^2[Atlas]^7 Restricted Zone persisted to DB.")
        end)
end)

--- @section Harvesting Logic

RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(treeCoords, entity)
    local _source = source
    local pCoords = GetEntityCoords(GetPlayerPed(_source))

    -- Zone Check
    for _, zone in ipairs(RestrictedZones) do
        if #(pCoords - vec3(zone.x, zone.y, zone.z)) < zone.radius then
            return print("^1[Atlas]^7 Blocked: Player inside Restricted Zone.")
        end
    end

    -- Distance validation (Safety check)
    if #(pCoords - treeCoords) > 5.0 then return end

    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = {
        token = token,
        startTime = os.time(),
        tier = SpawnedNodes[entity] and SpawnedNodes[entity].tier or 1
    }

    TriggerClientEvent('Atlas_Woodcutting:Client:BeginMinigame', _source, token)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:FinishChop')
AddEventHandler('Atlas_Woodcutting:Server:FinishChop', function(token, axeName)
    local _source = source
    local task = ActiveTasks[_source]

    if not task or task.token ~= token then return end

    -- Verify time elapsed (MinChopTime is 5000ms)
    if (os.time() - task.startTime) < 4 then return end

    exports.Atlas_Skilling:AddSkillXP(_source, 'woodcutting', 20)

    -- Clean up task
    ActiveTasks[_source] = nil
end)
