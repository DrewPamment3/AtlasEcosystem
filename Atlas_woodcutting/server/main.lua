local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local SpawnedNodes = {}
local RestrictedZones = {}

--- @section Internal Helpers

local function SpawnTree(modelHash, x, y, z, tier)
    print(string.format("^3[Atlas Debug]^7 Attempting to spawn tree: %s at %.2f, %.2f, %.2f", modelHash, x, y, z))

    local tree = CreateObject(modelHash, x, y, z, true, true, false)

    Citizen.Wait(150) -- Increased wait for entity registration

    if DoesEntityExist(tree) then
        FreezeEntityPosition(tree, true)
        SetEntityAsMissionEntity(tree, true, true)
        SpawnedNodes[tree] = { tier = tier or 1 }
        print("^2[Atlas Debug]^7 Entity successfully spawned and frozen. Handle: " .. tree)
        return tree
    else
        print("^1[Atlas Debug]^7 FAILED to spawn entity. Check model hash and coordinates.")
        return nil
    end
end

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    print("^3[Atlas Debug]^7 Resource stopping. Cleaning up entities...")
    for entity, _ in pairs(SpawnedNodes) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
end)

--- @section Initialization

Citizen.CreateThread(function()
    Citizen.Wait(3000)
    print("^3[Atlas Debug]^7 Starting Initialization...")

    -- Load Restricted Zones
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_zones', {}, function(zones)
        if zones then
            RestrictedZones = zones
            print("^2[Atlas Debug]^7 Loaded " .. #zones .. " restricted zones.")
        end
    end)

    -- Load and Spawn Nodes
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            print("^3[Atlas Debug]^7 Found " .. #nodes .. " nodes in DB. Spawning...")
            for _, node in ipairs(nodes) do
                SpawnTree(node.model_hash, node.x, node.y, node.z, 1)
            end
        end
    end)
end)

--- @section Admin Commands

RegisterCommand('createforest', function(source, args)
    local _source = source
    print("^3[Atlas Debug]^7 /createforest command triggered by Source: " .. _source)

    if _source == 0 then return print("^1[Atlas Debug]^7 Error: Console cannot run this.") end

    local user = VORPcore.getUser(_source)
    if not user then return print("^1[Atlas Debug]^7 Error: Could not get user from VORP core.") end

    local group = user.getGroup
    print("^3[Atlas Debug]^7 Player Group: " .. tostring(group))

    -- Check group (ensure your DB group matches 'admin')
    if group ~= 'admin' then
        return print("^1[Atlas Debug]^7 Permission Denied: Player is group '" .. tostring(group) .. "' not 'admin'.")
    end

    local playerPed = GetPlayerPed(_source)
    local pCoords = GetEntityCoords(playerPed)

    local radius = tonumber(args[1]) or 20.0
    local count = tonumber(args[2]) or 10
    local tier = tonumber(args[3]) or 1
    local model = `p_tree_pine_01`

    print(string.format("^3[Atlas Debug]^7 Inserting Forest: R:%.1f, C:%s, T:%s", radius, count, tier))

    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier) VALUES (?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier }, function(forestId)
            if forestId then
                print("^2[Atlas Debug]^7 Forest record created. ID: " ..
                forestId .. ". Pinging client for ground probing...")
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, forestId, pCoords, radius,
                    count, model)
            else
                print("^1[Atlas Debug]^7 DB Error: Failed to insert forest record.")
            end
        end)
end)

--- @section Data Handling

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, modelHash)
    print(string.format("^3[Atlas Debug]^7 Node Received from Client. ForestID: %s | Model: %s", forestId, modelHash))

    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_hash) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelHash }, function(id)
            if id then
                print("^2[Atlas Debug]^7 Node saved to DB (ID: " .. id .. "). Spawning entity...")
                SpawnTree(modelHash, coords.x, coords.y, coords.z, 1)
            else
                print("^1[Atlas Debug]^7 DB Error: Failed to save node coordinates.")
            end
        end)
end)

-- Rest of the harvesting events remain the same...
