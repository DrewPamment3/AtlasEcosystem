local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local SpawnedNodes = {}
local RestrictedZones = {}

--- @section Internal Helpers

local function SpawnTree(modelName, x, y, z, tier)
    -- Convert string to hash if it's not already one
    local modelHash = type(modelName) == "string" and GetHashKey(modelName) or modelName

    -- Request the model for the server (OneSync requirement)
    -- CreateObject(hash, x, y, z, isNetworked, createHandle, dynamic)
    local tree = CreateObject(modelHash, x, y, z, true, true, false)

    Citizen.Wait(200) -- Give the engine time to register the entity

    if DoesEntityExist(tree) then
        FreezeEntityPosition(tree, true)
        SetEntityAsMissionEntity(tree, true, true)
        SpawnedNodes[tree] = { tier = tier or 1 }
        print(string.format("^2[Atlas Debug]^7 SUCCESS: Spawned %s (Handle: %s)", modelName, tree))
        return tree
    else
        print(string.format("^1[Atlas Debug]^7 FAILED: Server could not spawn model '%s'. It may not be a valid PROP.",
            modelName))
        return nil
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    for entity, _ in pairs(SpawnedNodes) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end)

--- @section Initialization

Citizen.CreateThread(function()
    Citizen.Wait(3000)
    print("^3[Atlas Debug]^7 Initializing Woodcutting System...")

    -- Load Restricted Zones
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_zones', {}, function(zones)
        if zones then RestrictedZones = zones end
    end)

    -- Load and Spawn Nodes
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes and #nodes > 0 then
            print("^3[Atlas Debug]^7 Found " .. #nodes .. " nodes in DB. Spawning...")
            for _, node in ipairs(nodes) do
                -- We use the hash from the DB
                SpawnTree(node.model_hash, node.x, node.y, node.z, 1)
            end
        else
            print("^3[Atlas Debug]^7 No nodes found in database.")
        end
    end)
end)

--- @section Admin Commands

RegisterCommand('createforest', function(source, args)
    local _source = source
    if _source == 0 then return end

    local user = VORPcore.getUser(_source)
    if not user or user.getGroup ~= 'admin' then
        return print("^1[Atlas Debug]^7 Access Denied.")
    end

    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius = tonumber(args[1]) or 15.0
    local count = tonumber(args[2]) or 5
    local tier = tonumber(args[3]) or 1

    -- Use a guaranteed harvestable PROP name
    local modelName = args[4] or "p_tree_pine_01"
    local modelHash = GetHashKey(modelName)

    print("^3[Atlas Debug]^7 Creating forest with model: " .. modelName)

    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier, model_hash) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier, modelHash }, function(forestId)
            if forestId then
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, forestId, pCoords, radius,
                    count, modelName)
            end
        end)
end)

--- @section Node Saving

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, modelName)
    local modelHash = GetHashKey(modelName)

    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_hash) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelHash }, function(id)
            if id then
                SpawnTree(modelHash, coords.x, coords.y, coords.z, 1)
            end
        end)
end)

--- @section Harvesting (Shortened for brevity - keep your existing Request/Finish logic)
-- (Keep your RequestStart and FinishChop logic from the previous turn here)
