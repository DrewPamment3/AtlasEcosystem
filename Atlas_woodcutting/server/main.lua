local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local SpawnedNodes = {}
local RestrictedZones = {}

--- @section Internal Helpers

local function SpawnTree(modelHash, x, y, z, tier)
    local tree = CreateObject(modelHash, x, y, z, true, true, false)

    Citizen.Wait(100)

    if DoesEntityExist(tree) then
        FreezeEntityPosition(tree, true)
        SetEntityAsMissionEntity(tree, true, true)
        SpawnedNodes[tree] = { tier = tier or 1 }
        return tree
    else
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
    Citizen.Wait(2000)

    -- Load Restricted Zones
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_zones', {}, function(zones)
        if zones then RestrictedZones = zones end
    end)

    -- Load and Spawn Nodes
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            for _, node in ipairs(nodes) do
                SpawnTree(node.model_hash, node.x, node.y, node.z, 1)
            end
        end
    end)
end)

--- @section Admin Commands

-- Create Forest
RegisterCommand('createforest', function(source, args)
    local _source = source
    if _source == 0 then return print("^1[Atlas]^7 Error: Command must be run by a player.") end

    -- VORP Permission Check (Set to 'admin' or your preferred group)
    local Character = VORPcore.getUser(_source).getUsedCharacter
    local group = VORPcore.getUser(_source).getGroup

    if group ~= 'admin' then
        return print("^1[Atlas]^7 Access Denied for player " .. _source)
    end

    local playerPed = GetPlayerPed(_source)
    local pCoords = GetEntityCoords(playerPed)

    local radius = tonumber(args[1]) or 20.0
    local count = tonumber(args[2]) or 10
    local tier = tonumber(args[3]) or 1
    local model = `p_tree_pine_01` -- Constant for reliable testing

    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier) VALUES (?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier }, function(forestId)
            if forestId then
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, forestId, pCoords, radius,
                    count, model)
            end
        end)
end)

-- Create Restricted Zone
RegisterCommand('azone', function(source, args)
    local _source = source
    if _source == 0 then return end

    local group = VORPcore.getUser(_source).getGroup
    if group ~= 'admin' then return end

    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius = tonumber(args[1]) or 50.0

    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_zones (x, y, z, radius) VALUES (?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius }, function(id)
            table.insert(RestrictedZones, { x = pCoords.x, y = pCoords.y, z = pCoords.z, radius = radius })
        end)
end)

--- @section Harvesting Events

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, modelHash)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_hash) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelHash }, function(id)
            SpawnTree(modelHash, coords.x, coords.y, coords.z, 1)
        end)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(treeCoords, entity)
    local _source = source
    local pCoords = GetEntityCoords(GetPlayerPed(_source))

    for _, zone in ipairs(RestrictedZones) do
        if #(pCoords - vec3(zone.x, zone.y, zone.z)) < zone.radius then return end
    end

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
    if (os.time() - task.startTime) < 4 then return end

    exports.Atlas_Skilling:AddSkillXP(_source, 'woodcutting', 20)
    ActiveTasks[_source] = nil
end)
