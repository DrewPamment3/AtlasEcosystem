local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}

-- Check if player is in a "No Chopping" zone
local function IsInRestrictedZone(playerCoords)
    for _, zone in ipairs(Config.RestrictedZones) do
        local distance = #(playerCoords - zone.coords)
        if distance < zone.radius then
            return true, zone.name
        end
    end
    return false, nil
end

-- Loot logic remains the same
local function CalculateLoot(source, playerLevel, axeName)
    -- ... (Previous logic for Weight-based scaling)
    return "crude_wood" -- Fallback for testing
end

RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(treeCoords)
    local _source = source
    local playerCoords = GetEntityCoords(GetPlayerPed(_source))

    -- 1. Restricted Zone Check
    local isRestricted, zoneName = IsInRestrictedZone(playerCoords)
    if isRestricted then
        -- Notify player (using VORP or print for now)
        print("^1[Atlas Woodcutting]^7 Player " .. _source .. " blocked by zone: " .. zoneName)
        return
    end

    -- 2. Proximity to Tree Check
    if #(playerCoords - treeCoords) > 4.0 then return end

    -- 3. Token Generation
    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = {
        token = token,
        startTime = os.time(),
        coords = treeCoords
    }

    TriggerClientEvent('Atlas_Woodcutting:Client:BeginMinigame', _source, token)
end)

RegisterServerEvent('Atlas_Woodcutting:Server:FinishChop')
AddEventHandler('Atlas_Woodcutting:Server:FinishChop', function(token, axeName)
    local _source = source
    local task = ActiveTasks[_source]

    if not task or task.token ~= token then return end
    if (os.time() - task.startTime) < (Config.MinChopTime / 1000) then return end

    local level = exports.Atlas_Skilling:GetSkillLevel(_source, 'woodcutting')
    -- local reward = CalculateLoot(_source, level, axeName)

    -- Awarding XP through your export
    exports.Atlas_Skilling:AddSkillXP(_source, 'woodcutting', 20)

    ActiveTasks[_source] = nil
end)
