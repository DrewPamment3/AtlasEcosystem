AtlasWoodConfig = {}

-- Interaction & Rewards
AtlasWoodConfig.ChopXPReward = 20           -- DEPRECATED: Old flat XP reward (kept for compatibility)
AtlasWoodConfig.InteractionKey = 0x760A9C6F -- G key (0x760A9C6F)
AtlasWoodConfig.ChopAnimationTime = 5000    -- Milliseconds for chop animation
AtlasWoodConfig.MinChopTime = 5000          -- 5 Seconds

-- New tiered XP system
AtlasWoodConfig.XPSystem = {
    -- Base XP rewards by grove tier (doubles each tier)
    baseTierXP = {
        [1] = 150,  -- Tier 1 groves: 150 XP
        [2] = 300,  -- Tier 2 groves: 300 XP
        [3] = 600,  -- Tier 3 groves: 600 XP
        [4] = 1200, -- Tier 4 groves: 1200 XP
        [5] = 2400  -- Tier 5 groves: 2400 XP
    },

    -- Bonus XP multiplier when player gets bonus loot (double wood)
    bonusLootXPMultiplier = 2.0, -- Double XP when bonus loot triggers

    -- Optional: Additional multipliers for different axe tiers
    axeXPMultipliers = {
        [1] = 1.0, -- Crude axe: no bonus
        [2] = 1.1, -- Fine axe: +10% XP
        [3] = 1.2, -- Great axe: +20% XP
        [4] = 1.3, -- Superior axe: +30% XP
        [5] = 1.5  -- Legendary axe: +50% XP
    }
}

-- Debug Logging (set to false in production)
AtlasWoodConfig.DebugLogging = true -- Toggle all debug output

-- Distance & Rendering
AtlasWoodConfig.RenderDistance = 400       -- Max distance to render forests (meters)
AtlasWoodConfig.RespawnMinutesPerTier = 20 -- Base respawn time (doubled per tier level)

-- Basic Animation Configuration (kept minimal to not break functionality)
AtlasWoodConfig.BasicAnimationEnabled = true

-- Admin Command Validation
AtlasWoodConfig.RadiusRange = { min = 10, max = 50 }   -- Forest radius meters
AtlasWoodConfig.TreeCountRange = { min = 5, max = 25 } -- Trees per forest
AtlasWoodConfig.TierRange = { min = 1, max = 5 }       -- Forest tier levels (updated for 5 tiers)
AtlasWoodConfig.ModelLoadTimeout = 5000                -- Model load wait time (ms)

-- Loot Scaling
AtlasWoodConfig.WoodTiers = {
    { id = 1, name = "crude_wood",     minLevel = 1,  baseWeight = 100, weightMultiplier = 1.0 },
    { id = 2, name = "fine_wood",      minLevel = 1,  baseWeight = 5,   weightMultiplier = 1.5 },
    { id = 3, name = "great_wood",     minLevel = 20, baseWeight = 2,   weightMultiplier = 2.0 },
    { id = 4, name = "superior_wood",  minLevel = 45, baseWeight = 1,   weightMultiplier = 3.0 },
    { id = 5, name = "legendary_wood", minLevel = 70, baseWeight = 0.5, weightMultiplier = 5.0, reqAxeTier = 4 }
}

-- Zone-based multipliers (Higher tier = more rare wood weight)
AtlasWoodConfig.TierMultipliers = {
    [1] = 1.0, -- Trash tier groves
    [2] = 1.3, -- Poor tier groves
    [3] = 1.7, -- Common tier groves
    [4] = 2.2, -- Rare tier groves
    [5] = 3.0  -- Legendary tier groves
}

-- Grove unlock levels
AtlasWoodConfig.GroveUnlocks = {
    [1] = 1,  -- Tier 1 groves at level 1
    [2] = 20, -- Tier 2 groves at level 20
    [3] = 45, -- Tier 3 groves at level 45
    [4] = 80, -- Tier 4 groves at level 80
    [5] = 95  -- Tier 5 groves at level 95
}

-- Comprehensive loot system configuration
AtlasWoodConfig.LootSystem = {
    -- Base weights for each wood type (starting point before any multipliers)
    baseWeights = {
        wood_crude = 100,    -- Always abundant
        wood_common = 20,    -- Starts appearing around level 15
        wood_rare = 6,       -- Starts appearing around level 35
        wood_superior = 2,   -- Starts appearing around level 60
        wood_legendary = 0.5 -- Starts appearing around level 85
    },

    -- Level requirements to start getting each wood type
    levelRequirements = {
        wood_crude = 1,
        wood_common = 15,
        wood_rare = 35,
        wood_superior = 60,
        wood_legendary = 85
    },

    -- Level scaling factors: higher = slower scaling, lower = faster scaling
    levelScaling = {
        wood_crude = 0,     -- No scaling (always same base weight)
        wood_common = 30,   -- Reaches 2x base weight at level 45 (15 + 30)
        wood_rare = 35,     -- Reaches 2x base weight at level 70 (35 + 35)
        wood_superior = 25, -- Reaches 2x base weight at level 85 (60 + 25)
        wood_legendary = 20 -- Reaches 2x base weight at level 105 (85 + 20, caps at 99)
    },

    -- Grove tier effects on each wood type (multipliers)
    groveEffects = {
        [1] = { -- Tier 1: Heavily favors crude
            wood_crude = 1.0,
            wood_common = 0.3,
            wood_rare = 0.0,
            wood_superior = 0.0,
            wood_legendary = 0.0
        },
        [2] = { -- Tier 2: Reduces crude, boosts common
            wood_crude = 0.7,
            wood_common = 1.5,
            wood_rare = 0.4,
            wood_superior = 0.0,
            wood_legendary = 0.0
        },
        [3] = { -- Tier 3: Balanced, introduces rare
            wood_crude = 0.5,
            wood_common = 1.2,
            wood_rare = 1.8,
            wood_superior = 0.6,
            wood_legendary = 0.0
        },
        [4] = { -- Tier 4: Reduces lower tiers, boosts superior
            wood_crude = 0.3,
            wood_common = 0.9,
            wood_rare = 1.4,
            wood_superior = 2.2,
            wood_legendary = 0.8
        },
        [5] = { -- Tier 5: Premium grove, best legendary chances
            wood_crude = 0.2,
            wood_common = 0.7,
            wood_rare = 1.0,
            wood_superior = 1.8,
            wood_legendary = 3.0
        }
    },

    -- Bonus loot system (second roll chance)
    bonusLoot = {
        baseChance = 12.0,     -- Base 12% chance for bonus loot
        levelBonus = 0.15,     -- +0.15% per woodcutting level (15% at level 100)
        maxBonusChance = 35.0, -- Cap at 35% total chance

        -- Axe bonuses
        axeBonus = {
            chanceBonus = 4.0, -- +4% bonus chance per axe tier above 1
            weightBonus = 0.15 -- +15% weight multiplier to non-crude woods per axe tier above 1
        }
    }
}

-- Axe level requirements
AtlasWoodConfig.AxeUnlocks = {
    ["axe_crude"] = 1,
    ["axe_common"] = 20,
    ["axe_great"] = 45,
    ["axe_superior"] = 70,
    ["axe_legendary"] = 90
}

AtlasWoodConfig.Axes = {
    ["axe_crude"]     = { tier = 1, power = 1.0 },
    ["axe_common"]    = { tier = 2, power = 1.2 },
    ["axe_great"]     = { tier = 3, power = 1.5 },
    ["axe_superior"]  = { tier = 4, power = 2.0 },
    ["axe_legendary"] = { tier = 5, power = 3.0 }
}

-- Fallback detection for random world trees (Material only)
AtlasWoodConfig.TreeMaterials = {
    [1184711311] = true, -- WOOD_SOLID
    [7587075] = true,
    [10008579] = true,
    [1697541] = true,
}

-- Static models you trust (Pine/Oak)
AtlasWoodConfig.Trees = {
    [1035651700] = { name = "Pine", xp = 25 },
    [1998592543] = { name = "Oak", xp = 40 },
    [1771086077] = { name = "Large Pine", xp = 30 },
}

-- Tree Model Z-Offsets (subtract from ground Z to properly position trees)
-- Use /spawntree [model] [zOffset] to test and find correct values
AtlasWoodConfig.TreeModelZOffsets = {
    ["p_tree_longleafpine_02"] = 1.0,
    ["p_tree_blue_oak_01"] = 2.0,
    ["p_tree_redwood_05"] = 1.0,
    ["p_tree_redwood_05_lg"] = 3.5,
    ["p_tree_engoak_01"] = 1.0,
}

-- Function to get Z offset for a model (returns default 0.2 if not found)
function AtlasWoodConfig.GetTreeZOffset(modelName)
    return AtlasWoodConfig.TreeModelZOffsets[modelName] or 0.2
end

-- Loot calculation functions
function AtlasWoodConfig.CalculateLootWeights(playerLevel, groveTier, axeTier, isBonus)
    local loot = AtlasWoodConfig.LootSystem
    local weights = {}
    local totalWeight = 0

    -- Validate grove access
    local requiredLevel = AtlasWoodConfig.GroveUnlocks[groveTier]
    if requiredLevel and playerLevel < requiredLevel then
        return nil, requiredLevel -- Return required level for error message
    end

    -- Calculate weights for each wood type
    for woodType, baseWeight in pairs(loot.baseWeights) do
        local minLevel = loot.levelRequirements[woodType]

        -- Skip if player doesn't meet level requirement
        if playerLevel >= minLevel then
            -- Base weight calculation with level scaling
            local weight = baseWeight
            local scalingFactor = loot.levelScaling[woodType]

            if scalingFactor > 0 and playerLevel > minLevel then
                local levelBonus = (playerLevel - minLevel) / scalingFactor
                weight = baseWeight * (1 + levelBonus)
            end

            -- Apply grove tier effects
            local groveEffect = loot.groveEffects[groveTier] and loot.groveEffects[groveTier][woodType] or 1.0
            weight = weight * groveEffect

            -- Apply axe bonuses for higher-tier woods (not crude)
            if axeTier > 1 and woodType ~= "wood_crude" then
                local axeMultiplier = 1 + ((axeTier - 1) * loot.bonusLoot.axeBonus.weightBonus)
                weight = weight * axeMultiplier
            end

            -- For bonus loot, slightly reduce crude weight to make it more interesting
            if isBonus and woodType == "wood_crude" then
                weight = weight * 0.7
            end

            weights[woodType] = weight
            totalWeight = totalWeight + weight
        end
    end

    return weights, totalWeight
end

function AtlasWoodConfig.RollForLoot(weights, totalWeight)
    if totalWeight <= 0 then return nil end

    local roll = math.random() * totalWeight
    local currentWeight = 0

    for woodType, weight in pairs(weights) do
        currentWeight = currentWeight + weight
        if roll <= currentWeight then
            return woodType
        end
    end

    -- Fallback to first available wood type
    for woodType, _ in pairs(weights) do
        return woodType
    end

    return nil
end

function AtlasWoodConfig.CalculateBonusChance(playerLevel, axeTier)
    local bonusConfig = AtlasWoodConfig.LootSystem.bonusLoot

    -- Base chance + level bonus
    local chance = bonusConfig.baseChance + (playerLevel * bonusConfig.levelBonus)

    -- Axe tier bonus
    if axeTier > 1 then
        chance = chance + ((axeTier - 1) * bonusConfig.axeBonus.chanceBonus)
    end

    -- Cap at maximum
    chance = math.min(chance, bonusConfig.maxBonusChance)

    return chance
end

-- Calculate XP reward based on grove tier, axe tier, and whether bonus loot was awarded
function AtlasWoodConfig.CalculateXPReward(groveTier, axeTier, hasBonusLoot)
    local xpConfig = AtlasWoodConfig.XPSystem

    -- Get base XP for this grove tier
    local baseXP = xpConfig.baseTierXP[groveTier] or xpConfig.baseTierXP[1]

    -- Apply axe multiplier
    local axeMultiplier = xpConfig.axeXPMultipliers[axeTier] or 1.0
    local xpAmount = baseXP * axeMultiplier

    -- Apply bonus loot multiplier if player got bonus loot
    if hasBonusLoot then
        xpAmount = xpAmount * xpConfig.bonusLootXPMultiplier
    end

    -- Round to nearest integer
    return math.floor(xpAmount + 0.5)
end

function AtlasWoodConfig.GetPlayerAxeTier(source)
    -- This will be implemented in server-side code using VORP inventory
    -- Returns axe tier based on player's equipped/inventory axe
    return 1 -- Default fallback
end

-- Validation function
function AtlasWoodConfig.ValidateLootSystem()
    local errors = {}

    -- Check that all wood types have required config
    for woodType, _ in pairs(AtlasWoodConfig.LootSystem.baseWeights) do
        if not AtlasWoodConfig.LootSystem.levelRequirements[woodType] then
            table.insert(errors, "Missing level requirement for " .. woodType)
        end
        if not AtlasWoodConfig.LootSystem.levelScaling[woodType] then
            table.insert(errors, "Missing level scaling for " .. woodType)
        end
    end

    -- Check grove effects
    for tier = 1, 5 do
        if not AtlasWoodConfig.LootSystem.groveEffects[tier] then
            table.insert(errors, "Missing grove effects for tier " .. tier)
        end
    end

    if #errors > 0 then
        for _, error in ipairs(errors) do
            print("^1[Atlas Woodcutting Config Error]^7 " .. error)
        end
        return false
    end

    return true
end
