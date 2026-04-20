local VORPcore = exports.vorp_core:GetCore()
local Config = AtlasWoodConfig -- Reference shared config
local ActiveTasks = {}
local GlobalNodes = {}

Citizen.CreateThread(function()
    Citizen.Wait(1000)
    exports.oxmysql:execute('SELECT x, y, z, model_name, forest_id FROM atlas_woodcutting_nodes', {}, function(nodes)
        if nodes then
            GlobalNodes = nodes
            print("^2[Atlas]^7 Server loaded " .. #nodes .. " nodes from DB.")
        end
    end)
end)

RegisterServerEvent('atlas_woodcutting:server:playerLoaded')
AddEventHandler('atlas_woodcutting:server:playerLoaded', function()
    TriggerClientEvent('atlas_woodcutting:client:syncNodes', source, GlobalNodes)
end)

RegisterServerEvent('atlas_woodcutting:server:saveNode')
AddEventHandler('atlas_woodcutting:server:saveNode', function(forestId, coords, modelName)
    exports.oxmysql:insert('INSERT INTO atlas_woodcutting_nodes (forest_id, x, y, z, model_name) VALUES (?, ?, ?, ?, ?)',
        { forestId, coords.x, coords.y, coords.z, modelName }, function(id)
            if id then
                local node = { x = coords.x, y = coords.y, z = coords.z, model_name = modelName, forest_id = forestId }
                table.insert(GlobalNodes, node)
                TriggerClientEvent('atlas_woodcutting:client:spawnSingleNode', -1, node)
            else
                print("^1[Atlas Woodcutting]^7 Failed to save node for forest " .. forestId)
            end
        end)
end)

RegisterCommand('createforest', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /createforest is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user or user.group ~= 'admin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end
    local pCoords = GetEntityCoords(GetPlayerPed(_source))
    local radius, count, tier = tonumber(args[1]) or 15.0, tonumber(args[2]) or 10, tonumber(args[3]) or 1
    local model, name = args[4] or "p_tree_pine01x", args[5] or "Unnamed_Grove"

    -- Validate parameters against config ranges
    if radius < Config.RadiusRange.min or radius > Config.RadiusRange.max then
        VORPcore.NotifyRightTip(_source, "~r~Radius must be " .. Config.RadiusRange.min .. "-" .. Config.RadiusRange.max,
            4000)
        return
    end
    if count < Config.TreeCountRange.min or count > Config.TreeCountRange.max then
        VORPcore.NotifyRightTip(_source,
            "~r~Count must be " .. Config.TreeCountRange.min .. "-" .. Config.TreeCountRange.max, 4000)
        return
    end
    if tier < Config.TierRange.min or tier > Config.TierRange.max then
        VORPcore.NotifyRightTip(_source, "~r~Tier must be " .. Config.TierRange.min .. "-" .. Config.TierRange.max, 4000)
        return
    end
    exports.oxmysql:insert(
        'INSERT INTO atlas_woodcutting_forests (x, y, z, radius, tree_count, tier, model_name, name) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { pCoords.x, pCoords.y, pCoords.z, radius, count, tier, model, name }, function(fId)
            if fId then
                VORPcore.NotifyRightTip(_source, "~g~Forest '" .. name .. "' created with " .. count .. " trees", 4000)
                TriggerClientEvent('atlas_woodcutting:client:generateForestNodes', _source, fId, pCoords, radius, count,
                    model)
            else
                VORPcore.NotifyRightTip(_source, "~r~Failed to create forest in database", 4000)
                print("^1[Atlas Woodcutting]^7 Failed to insert forest for admin " .. _source)
            end
        end)
end)

RegisterCommand('wipeforest', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /wipeforest is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user or user.group ~= 'admin' then
        VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        return
    end
    local targetName = args[1]
    if not targetName then
        VORPcore.NotifyRightTip(_source, "~r~Usage: /wipeforest [forestname]", 4000)
        return
    end
    exports.oxmysql:execute('SELECT id FROM atlas_woodcutting_forests WHERE name = ?', { targetName }, function(result)
        if result and result[1] and result[1].id then
            local fId = result[1].id
            exports.oxmysql:execute('DELETE FROM atlas_woodcutting_nodes WHERE forest_id = ?', { fId })
            exports.oxmysql:execute('DELETE FROM atlas_woodcutting_forests WHERE id = ?', { fId })
            for i = #GlobalNodes, 1, -1 do
                if GlobalNodes[i].forest_id == fId then table.remove(GlobalNodes, i) end
            end
            TriggerClientEvent('atlas_woodcutting:client:wipeSpecificForest', -1, fId)
            VORPcore.NotifyRightTip(_source, "~g~Forest '" .. targetName .. "' wiped successfully", 4000)
        else
            VORPcore.NotifyRightTip(_source, "~r~Forest '" .. targetName .. "' not found", 4000)
        end
    end)
end)

RegisterCommand('listforests', function(source, args)
    local _source = source
    if _source == 0 then
        print("^3[Atlas Woodcutting]^7 /listforests is for in-game players only")
        return
    end

    local user = VORPcore.getUser(_source)
    if not user or user.group ~= 'admin' then
        if _source ~= 0 then
            VORPcore.NotifyRightTip(_source, "~r~Admin only command", 4000)
        end
        return
    end

    local page = tonumber(args[1]) or 1
    if page < 1 then page = 1 end

    exports.oxmysql:execute(
    'SELECT id, name, radius, tree_count, tier, x, y, z FROM atlas_woodcutting_forests ORDER BY name ASC', {},
        function(result)
            if not result or #result == 0 then
                print("^3[Atlas Woodcutting]^7 No forests found in database.")
                return
            end

            local itemsPerPage = 10
            local totalForests = #result
            local totalPages = math.ceil(totalForests / itemsPerPage)

            if page > totalPages then page = totalPages end

            local startIdx = (page - 1) * itemsPerPage + 1
            local endIdx = math.min(page * itemsPerPage, totalForests)

            -- Print header
            print("^2================================================^7")
            print(string.format("^2 ATLAS WOODCUTTING FORESTS - PAGE %d/%d^7", page, totalPages))
            print("^2================================================^7")
            print(string.format("^3%-4s^7 | ^3%-18s^7 | ^3%-7s^7 | ^3%-5s^7 | ^3%-4s^7 | ^3%-8s^7 | ^3%-8s^7 | ^3%-8s^7",
                "ID", "Name", "Radius", "Trees", "Tier", "X", "Y", "Z"))
            print("^2----|--------------------|---------|---------|---------|-----------|-----------|-----------^7")

            -- Print forest entries
            for i = startIdx, endIdx do
                local forest = result[i]
                print(string.format(
                    "^7%-4d^7 | ^6%-18s^7 | ^5%-7.1f^7 | ^4%-5d^7 | ^3%-4d^7 | ^2%-8.2f^7 | ^2%-8.2f^7 | ^2%-8.2f^7",
                    forest.id,
                    forest.name:sub(1, 18),
                    forest.radius,
                    forest.tree_count,
                    forest.tier,
                    forest.x,
                    forest.y,
                    forest.z
                ))
            end

            print("^2================================================^7")
            print(string.format("^3Total: %d forests | Showing %d-%d^7", totalForests, startIdx, endIdx))
            print("^2================================================^7")
        end)
end)

RegisterServerEvent('atlas_woodcutting:server:requestStart')
AddEventHandler('atlas_woodcutting:server:requestStart', function(coords)
    local _source = source
    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = { token = token, startTime = os.time() }
    TriggerClientEvent('atlas_woodcutting:client:beginMinigame', _source, token)
end)

RegisterServerEvent('atlas_woodcutting:server:finishChop')
AddEventHandler('atlas_woodcutting:server:finishChop', function(token)
    local _source = source
    local task = ActiveTasks[_source]
    if not task or task.token ~= token then return end

    local success, result = pcall(function()
        return exports.Atlas_skilling:AddSkillXP(_source, 'woodcutting', Config.ChopXPReward)
    end)

    if not success then
        print("^1[Atlas Woodcutting]^7 Error awarding XP to player " .. _source .. ": " .. tostring(result))
    end

    ActiveTasks[_source] = nil
end)

-- Player Disconnect Cleanup
AddEventHandler('playerDropped', function(reason)
    local _source = source
    if ActiveTasks[_source] then
        ActiveTasks[_source] = nil
        print("^2[Atlas Woodcutting]^7 Cleaned up active task for disconnected player " .. _source)
    end
end)
