local VORPcore = exports.vorp_core:GetCore()
local ActiveTasks = {}

-- Function to calculate what the player gets
local function CalculateLoot(source, playerLevel, axeName)
    local axeData = Config.Axes[axeName] or Config.Axes["crude_axe"]
    local pool = {}
    local totalWeight = 0

    for _, wood in ipairs(Config.WoodTiers) do
        -- 1. Check Level Requirement
        if playerLevel >= wood.minLevel then
            -- 2. Check Axe Tier Hard-Lock (Legendary needs Superior+)
            local canHarvest = true
            if wood.reqAxeTier and axeData.tier < wood.reqAxeTier then
                canHarvest = false
            end

            if canHarvest then
                -- 3. Calculate Weight
                -- Level scales the base, Axe Power multiplies the result
                local weight = (wood.baseWeight + (playerLevel * 0.1)) * (axeData.power * wood.weightMultiplier)

                table.insert(pool, { name = wood.name, weight = weight })
                totalWeight = totalWeight + weight
            end
        end
    end

    -- 4. Roll the Dice
    local roll = math.random() * totalWeight
    local cursor = 0
    for _, item in ipairs(pool) do
        cursor = cursor + item.weight
        if roll <= cursor then
            return item.name
        end
    end
end

-- The Handshake: Client requests to start
RegisterServerEvent('Atlas_Woodcutting:Server:RequestStart')
AddEventHandler('Atlas_Woodcutting:Server:RequestStart', function(treeCoords)
    local _source = source
    -- Check distance, check inventory for any valid axe
    -- If valid:
    local token = "CHOP_" .. math.random(1000, 9999)
    ActiveTasks[_source] = {
        token = token,
        startTime = os.time(),
        coords = treeCoords
    }
    TriggerClientEvent('Atlas_Woodcutting:Client:BeginMinigame', _source, token)
end)

-- The Handshake: Client finishes
RegisterServerEvent('Atlas_Woodcutting:Server:FinishChop')
AddEventHandler('Atlas_Woodcutting:Server:FinishChop', function(token, axeName)
    local _source = source
    local task = ActiveTasks[_source]

    if not task or task.token ~= token then return end                            -- Invalid token
    if (os.time() - task.startTime) < (Config.MinChopTime / 1000) then return end -- Too fast

    local level = exports.Atlas_Skilling:GetSkillLevel(_source, 'woodcutting')
    local rewardItem = CalculateLoot(_source, level, axeName)

    -- Give Item via VORP
    -- exports.vorp_inventory:addItem(_source, rewardItem, 1)

    -- Give XP via Atlas_Skilling
    exports.Atlas_Skilling:AddSkillXP(_source, 'woodcutting', 20)

    ActiveTasks[_source] = nil -- Clear session
end)
