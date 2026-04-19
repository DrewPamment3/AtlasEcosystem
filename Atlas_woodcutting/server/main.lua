local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local GlobalNodes = {}

-- [[ INITIALIZATION ]]
Citizen.CreateThread(function()
    Citizen.Wait(1000)
    exports.oxmysql:execute('SELECT x, y, z, model_name, forest_id FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            GlobalNodes = nodes
            print("^2[Atlas]^7 Server loaded " .. #nodes .. " nodes from DB.")
        end
    end)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
AddEventHandler('Atlas_Woodcutting:Server:PlayerLoaded', function()
    TriggerClientEvent('Atlas_Woodcutting:Client:SyncNodes', source, GlobalNodes)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, modelName)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_name) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelName }, function(id)
            if id then
                local node = { x = coords.x, y = coords.y, z = coords.z, model_name = modelName, forest_id = forestId }
                table.insert(GlobalNodes, node)
                TriggerClientEvent('Atlas_Woodcutting:Client:SpawnSingleNode', -1, node)
            end
        end)
end)

-- [[ ADMIN COMMANDS ]]
RegisterCommand('createforest', function(source, args)
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user or user.getGroup ~= 'admin' then return end

    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius, count, tier = tonumber(args[1]) or 15.0, tonumber(args[2]) or 10, tonumber(args[3]) or 1
    local model, name = args[4] or "p_tree_pine01x", args[5] or "Unnamed_Grove"

    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier, model_name, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier, model, name }, function(fId)
            if fId then
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, fId, pCoords, radius, count,
                    model)
            end
        end)
end)

RegisterCommand('wipeforest', function(source, args)
    local _source = source
    local user = VORPcore.getUser(_source)
    if not user or user.getGroup ~= 'admin' then return end
    local targetName = args[1]
    if not targetName then return end

    exports.oxmysql:execute('SELECT id FROM atlas_woodcutting_forests WHERE name = ?', { targetName }, function(result)
        if result and result[1] then
            local fId = result[1].id
            exports.oxmysql:execute('DELETE FROM atlas_woodcutting_nodes WHERE forest_id = ?', { fId })
            exports.oxmysql:execute('DELETE FROM atlas_woodcutting_forests WHERE id = ?', { fId })
            for i = #GlobalNodes, 1, -1 do
                if GlobalNodes[i].forest_id == fId then table.remove(GlobalNodes, i) end
            end
            TriggerClientEvent('Atlas_Woodcutting:Client:WipeSpecificForest', -1, fId)
        end
    end)
end)

-- [[ HARVESTING ]]
RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(coords)
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
