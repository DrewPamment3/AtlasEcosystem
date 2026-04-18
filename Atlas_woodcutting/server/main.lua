local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local SpawnedNodes = {}
local RestrictedZones = {}

--- @section Internal Helpers

local function SpawnTree(modelHash, x, y, z, tier)
    -- Using NoOffset for better ground alignment on server-side spawns
    -- Flags: isNetworked (true), thisScriptCheck (false), dynamic (false)
    local tree = CreateObjectNoOffset(modelHash, x, y, z, true, false, false)

    Citizen.Wait(200) -- Mandatory wait for OneSync to register the entity

    if DoesEntityExist(tree) then
        FreezeEntityPosition(tree, true)
        SetEntityAsMissionEntity(tree, true, true)
        SpawnedNodes[tree] = { tier = tier or 1 }
        print(string.format("^2[Atlas Debug]^7 SUCCESS: Spawned Entity %s (Model: %s)", tree, modelHash))
        return tree
    else
        print(string.format("^1[Atlas Debug]^7 FAILED: Engine refused to spawn model %s at %.2f, %.2f, %.2f", modelHash,
            x, y, z))
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
    print("^3[Atlas Debug]^7 Initializing DB Load...")

    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_zones', {}, function(zones)
        if zones then RestrictedZones = zones end
    end)

    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes and #nodes > 0 then
            print("^3[Atlas Debug]^7 Spawning " .. #nodes .. " persistent nodes...")
            for _, node in ipairs(nodes) do
                SpawnTree(node.model_hash, node.x, node.y, node.z, 1)
            end
        end
    end)
end)

--- @section Commands

RegisterCommand('createforest', function(source, args)
    local _source = source
    if _source == 0 then return end

    local user = VORPcore.getUser(_source)
    if not user or user.getGroup ~= 'admin' then return print("^1[Atlas]^7 Admin only.") end

    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius = tonumber(args[1]) or 15.0
    local count = tonumber(args[2]) or 5
    local tier = tonumber(args[3]) or 1
    local modelName = args[4] or "p_tree_pine_01"
    local modelHash = GetHashKey(modelName)

    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier, model_hash) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier, modelHash }, function(forestId)
            if forestId then
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, forestId, pCoords, radius,
                    count, modelName)
            end
        end)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, modelName)
    local modelHash = GetHashKey(modelName)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_hash) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelHash }, function(id)
            if id then SpawnTree(modelHash, coords.x, coords.y, coords.z, 1) end
        end)
end)

--- @section Harvesting (Request/Finish)

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
