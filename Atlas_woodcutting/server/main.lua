local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local GlobalNodes = {} -- Store DB nodes in memory

-- [[ INITIALIZATION ]]

Citizen.CreateThread(function()
    Citizen.Wait(2000)
    -- Load Nodes from DB
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            GlobalNodes = nodes
            print("^2[Atlas]^7 Loaded " .. #nodes .. " nodes from DB. Waiting for players...")
        end
    end)
end)

-- When a player joins, send them the existing nodes to spawn
RegisterServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
AddEventHandler('Atlas_Woodcutting:Server:PlayerLoaded', function()
    local _source = source
    TriggerClientEvent('Atlas_Woodcutting:Client:SyncNodes', _source, GlobalNodes)
end)

-- [[ ADMIN COMMANDS ]]

RegisterCommand('createforest', function(source, args)
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user or user.getGroup ~= 'admin' then return end

    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius, count, tier = tonumber(args[1]) or 15.0, tonumber(args[2]) or 10, tonumber(args[3]) or 1
    local modelName = args[4] or "p_tree_pine_01"

    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier) VALUES (?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier }, function(forestId)
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
            if id then
                local newNode = { x = coords.x, y = coords.y, z = coords.z, model_hash = modelHash }
                table.insert(GlobalNodes, newNode)
                -- Tell ALL clients to spawn this new tree immediately
                TriggerClientEvent('Atlas_Woodcutting:Client:SpawnSingleNode', -1, newNode)
            end
        end)
end)

-- [[ HARVESTING ]] (Same as before, but using coords for validation)
RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(treeCoords)
    local _source = source
    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = { token = token, startTime = os.time() }
    TriggerClientEvent('Atlas_Woodcutting:Client:BeginMinigame', _source, token)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:FinishChop')
AddEventHandler('Atlas_Woodcutting:Server:FinishChop', function(token)
    local _source = source
    local task = ActiveTasks[_source]
    if not task or task.token ~= token then return end
    exports.Atlas_Skilling:AddSkillXP(_source, 'woodcutting', 20)
    ActiveTasks[_source] = nil
end)
