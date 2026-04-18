local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local SpawnedNodes = {} -- [entityHandle] = { tier = x, forestId = y }
local RestrictedZones = {}

-- [[ INITIALIZATION ]]

MySQL.ready(function()
    -- Load Restricted Zones
    MySQL.query('SELECT * FROM atlas_woodcutting_zones', {}, function(zones)
        if zones then RestrictedZones = zones end
    end)

    -- Load existing Forests and their Nodes
    MySQL.query('SELECT * FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            for _, node in ipairs(nodes) do
                -- We only spawn when requested, or spawn all now
                -- For persistence, we create the objects on startup
                local tree = CreateObject(node.model_hash, node.x, node.y, node.z, true, true, false)
                FreezeEntityPosition(tree, true)
                SpawnedNodes[tree] = { tier = 1 } -- Default tier, can be joined via SQL if needed
            end
            print("^2[Atlas Woodcutting]^7 Spawned " .. #nodes .. " persistent tree nodes.")
        end
    end)
end)

-- [[ FOREST CREATION LOGIC ]]

RegisterCommand('createforest', function(source, args)
    local _source = source
    local radius = tonumber(args[1]) or 20.0
    local count = tonumber(args[2]) or 10
    local tier = tonumber(args[3]) or 1
    local pCoords = GetEntityCoords(GetPlayerPed(_source))

    MySQL.insert('INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier) VALUES (?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier }, function(forestId)
            if forestId then
                -- Tell Client to generate the positions (Snapping to ground)
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, forestId, pCoords, radius,
                    count)
            end
        end)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, model)
    MySQL.insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_hash) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, model }, function(id)
            local tree = CreateObject(model, coords.x, coords.y, coords.z, true, true, false)
            FreezeEntityPosition(tree, true)
            SpawnedNodes[tree] = { tier = 1 } -- Metadata
        end)
end)

-- [[ RESTRICTED ZONES ]]

RegisterCommand('azone', function(source, args)
    local radius = tonumber(args[1]) or 50.0
    local pCoords = GetEntityCoords(GetPlayerPed(source))
    MySQL.insert('INSERT INTO atlas_woodcutting_zones (x, y, z, radius) VALUES (?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius }, function(id)
            table.insert(RestrictedZones, { x = pCoords.x, y = pCoords.y, z = pCoords.z, radius = radius })
            print("^2[Atlas]^7 Restricted Zone Added.")
        end)
end)

-- [[ CORE HARVESTING ]]

RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(treeCoords, entity)
    local _source = source
    local pCoords = GetEntityCoords(GetPlayerPed(_source))

    -- 1. Zone Check
    for _, zone in ipairs(RestrictedZones) do
        if #(pCoords - vec3(zone.x, zone.y, zone.z)) < zone.radius then
            return print("^1[Atlas]^7 Action blocked by Restricted Zone.")
        end
    end

    -- 2. Security Token
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

    -- Give Reward (Loot Logic placeholder)
    exports.Atlas_Skilling:AddSkillXP(_source, 'woodcutting', 20)
    ActiveTasks[_source] = nil
end)
