local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}
local GlobalNodes = {}
local RestrictedZones = {}

-- [[ INITIALIZATION ]]

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    -- Load Restricted Zones
    exports.oxmysql:execute('SELECT * FROM atlas_woodcutting_zones', {}, function(zones)
        if zones then RestrictedZones = zones end
    end)

    -- Load Nodes from DB
    exports.oxmysql:execute('SELECT x, y, z, model_hash FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            GlobalNodes = nodes
            print("^2[Atlas]^7 Ready. Nodes Loaded: " .. #nodes)
        end
    end)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:PlayerLoaded')
AddEventHandler('Atlas_Woodcutting:Server:PlayerLoaded', function()
    local _source = source
    print("^3[Atlas]^7 Player " .. _source .. " requested sync. Sending " .. #GlobalNodes .. " nodes.")
    TriggerClientEvent('Atlas_Woodcutting:Client:SyncNodes', _source, GlobalNodes)
end)

-- [[ DATABASE SAVING ]]

RegisterServerEvent('Atlas_Woodcutting:Server:SaveNode')
AddEventHandler('Atlas_Woodcutting:Server:SaveNode', function(forestId, coords, modelName)
    local modelHash = GetHashKey(modelName)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_hash) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelHash }, function(id)
            if id then
                local node = { x = coords.x, y = coords.y, z = coords.z, model_hash = modelHash }
                table.insert(GlobalNodes, node)
                -- Real-time sync for everyone online
                TriggerClientEvent('Atlas_Woodcutting:Client:SpawnSingleNode', -1, node)
            end
        end)
end)

-- [[ ADMIN COMMANDS ]]

RegisterCommand('createforest', function(source, args)
    local _source = source
    if _source == 0 then return end

    local user = VORPcore.getUser(_source)
    if not user or user.getGroup ~= 'admin' then
        return print("^1[Atlas]^7 Access Denied.")
    end

    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius, count = tonumber(args[1]) or 15.0, tonumber(args[2]) or 10
    local model = args[3] or "p_tree_pine_01"

    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count) VALUES (?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count }, function(fId)
            if fId then
                TriggerClientEvent('Atlas_Woodcutting:Client:GenerateForestNodes', _source, fId, pCoords, radius, count,
                    model)
            end
        end)
end)

RegisterCommand('azone', function(source, args)
    local _source = source
    if _source == 0 or VORPcore.getUser(_source).getGroup ~= 'admin' then return end

    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius = tonumber(args[1]) or 50.0

    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_zones (x, y, z, radius) VALUES (?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius }, function(id)
            table.insert(RestrictedZones, { x = pCoords.x, y = pCoords.y, z = pCoords.z, radius = radius })
            print("^2[Atlas]^7 Restricted Zone Added.")
        end)
end)

-- [[ HARVESTING ]]

RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(treeCoords)
    local _source = source
    local pCoords = GetEntityCoords(GetPlayerPed(_source))

    for _, zone in ipairs(RestrictedZones) do
        if #(pCoords - vec3(zone.x, zone.y, zone.z)) < zone.radius then return end
    end

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
