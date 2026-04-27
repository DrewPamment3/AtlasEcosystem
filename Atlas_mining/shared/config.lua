AtlasMiningConfig = {}

-- Interaction & Rewards
AtlasMiningConfig.InteractionKey = 0x760A9C6F -- G key (0x760A9C6F)
AtlasMiningConfig.MineAnimationTime = 5000    -- Milliseconds for mining animation

-- Debug Logging (set to false in production)
AtlasMiningConfig.DebugLogging = true -- Toggle all debug output

-- Distance & Rendering
AtlasMiningConfig.RenderDistance = 400       -- Max distance to render camps (meters)
AtlasMiningConfig.RespawnMinutesPerTier = 20 -- Base respawn time (doubled per tier level)

-- Admin Command Validation
AtlasMiningConfig.RadiusRange = { min = 10, max = 50 }   -- Camp radius meters
AtlasMiningConfig.RockCountRange = { min = 5, max = 25 } -- Rocks per camp
AtlasMiningConfig.TierRange = { min = 1, max = 5 }       -- Camp tier levels
AtlasMiningConfig.ModelLoadTimeout = 5000                -- Model load wait time (ms)

-- ============================================================
-- ROCK CONFIGURATION
-- ============================================================

-- Rock models that can be mined (mixed randomly within each camp)
-- Use /testspawn <model> in-game to test rock models
AtlasMiningConfig.Rocks = {
    "roa_int_rock_07",
    "roa_int_rock_05",
    "roa_int_rock_08",
    "roa_int_rock_09",
}

-- Mined rock model (appears after rock is depleted, replaces the original)
AtlasMiningConfig.MinedRockModel = "p_int_rock01x"

-- Rock Model Z-Offsets (subtract from ground Z to sink rocks into terrain)
-- Use /testspawn [model] [zOffset] to test and find correct values
AtlasMiningConfig.RockModelZOffsets = {
    ["roa_int_rock_07"] = 0.5,
    ["roa_int_rock_05"] = 0.5,
    ["roa_int_rock_08"] = 0.5,
    ["roa_int_rock_09"] = 0.5,
}

-- Function to get Z offset for a model (returns default 0.0 if not found — rocks need positive Z offset to sink)
function AtlasMiningConfig.GetRockZOffset(modelName)
    return AtlasMiningConfig.RockModelZOffsets[modelName] or 0.0
end

-- Helper: Pick a random rock model from the config list
function AtlasMiningConfig.GetRandomRockModel()
    local rocks = AtlasMiningConfig.Rocks
    return rocks[math.random(1, #rocks)]
end

-- ============================================================
-- PICKAXE CONFIGURATION (Tier 1-5)
-- ============================================================

AtlasMiningConfig.Pickaxes = {
    ["crude_pickaxe"]     = { tier = 1, power = 1.0 },
    ["fine_pickaxe"]      = { tier = 2, power = 1.2 },
    ["great_pickaxe"]     = { tier = 3, power = 1.5 },
    ["superior_pickaxe"]  = { tier = 4, power = 2.0 },
    ["legendary_pickaxe"] = { tier = 5, power = 3.0 }
}

AtlasMiningConfig.PickaxeUnlocks = {
    ["crude_pickaxe"] = 1,
    ["fine_pickaxe"] = 20,
    ["great_pickaxe"] = 45,
    ["superior_pickaxe"] = 70,
    ["legendary_pickaxe"] = 90
}

-- ============================================================
-- ORE CONFIGURATION (All Iron-based tiers)
-- ============================================================

AtlasMiningConfig.OreTiers = {
    { id = 1, name = "iron_ore_crude",     minLevel = 1,  baseWeight = 100, weightMultiplier = 1.0 },
    { id = 2, name = "iron_ore_common",    minLevel = 1,  baseWeight = 5,   weightMultiplier = 1.5 },
    { id = 3, name = "iron_ore_rare",      minLevel = 20, baseWeight = 2,   weightMultiplier = 2.0 },
    { id = 4, name = "iron_ore_superior",  minLevel = 45, baseWeight = 1,   weightMultiplier = 3.0 },
    { id = 5, name = "iron_ore_legendary", minLevel = 70, baseWeight = 0.5, weightMultiplier = 5.0, reqPickaxeTier = 4 }
}

-- Camp-based multipliers (Higher tier = more rare ore weight)
AtlasMiningConfig.TierMultipliers = {
    [1] = 1.0, -- Low tier camps
    [2] = 1.3, -- Poor tier camps
    [3] = 1.7, -- Common tier camps
    [4] = 2.2, -- Rich tier camps
    [5] = 3.0  -- Legendary tier camps
}

-- Camp unlock levels
AtlasMiningConfig.CampUnlocks = {
    [1] = 1,  -- Tier 1 camps at level 1
    [2] = 20, -- Tier 2 camps at level 20
    [3] = 45, -- Tier 3 camps at level 45
    [4] = 80, -- Tier 4 camps at level 80
    [5] = 95  -- Tier 5 camps at level 95
}

-- ============================================================
-- LOOT SYSTEM (Same math as woodcutting)
-- ============================================================

AtlasMiningConfig.LootSystem = {
    -- Base weights for each ore type (starting point before any multipliers)
    baseWeights = {
        iron_ore_crude = 100,    -- Always abundant
        iron_ore_common = 20,    -- Starts appearing around level 15
        iron_ore_rare = 6,       -- Starts appearing around level 35
        iron_ore_superior = 2,   -- Starts appearing around level 60
        iron_ore_legendary = 0.5 -- Starts appearing around level 85
    },

    -- Level requirements to start getting each ore type
    levelRequirements = {
        iron_ore_crude = 1,
        iron_ore_common = 15,
        iron_ore_rare = 35,
        iron_ore_superior = 60,
        iron_ore_legendary = 85
    },

    -- Level scaling factors: higher = slower scaling, lower = faster scaling
    levelScaling = {
        iron_ore_crude = 0,     -- No scaling (always same base weight)
        iron_ore_common = 30,   -- Reaches 2x base weight at level 45 (15 + 30)
        iron_ore_rare = 35,     -- Reaches 2x base weight at level 70 (35 + 35)
        iron_ore_superior = 25, -- Reaches 2x base weight at level 85 (60 + 25)
        iron_ore_legendary = 20 -- Reaches 2x base weight at level 105 (85 + 20, caps at 99)
    },

    -- Camp tier effects on each ore type (multipliers)
    campEffects = {
        [1] = { -- Tier 1: Heavily favors crude
            iron_ore_crude = 1.0,
            iron_ore_common = 0.3,
            iron_ore_rare = 0.0,
            iron_ore_superior = 0.0,
            iron_ore_legendary = 0.0
        },
        [2] = { -- Tier 2: Reduces crude, boosts common
            iron_ore_crude = 0.7,
            iron_ore_common = 1.5,
            iron_ore_rare = 0.4,
            iron_ore_superior = 0.0,
            iron_ore_legendary = 0.0
        },
        [3] = { -- Tier 3: Balanced, introduces rare
            iron_ore_crude = 0.5,
            iron_ore_common = 1.2,
            iron_ore_rare = 1.8,
            iron_ore_superior = 0.6,
            iron_ore_legendary = 0.0
        },
        [4] = { -- Tier 4: Reduces lower tiers, boosts superior
            iron_ore_crude = 0.3,
            iron_ore_common = 0.9,
            iron_ore_rare = 1.4,
            iron_ore_superior = 2.2,
            iron_ore_legendary = 0.8
        },
        [5] = { -- Tier 5: Premium camp, best legendary chances
            iron_ore_crude = 0.2,
            iron_ore_common = 0.7,
            iron_ore_rare = 1.0,
            iron_ore_superior = 1.8,
            iron_ore_legendary = 3.0
        }
    },

    -- Bonus loot system (second roll chance)
    bonusLoot = {
        baseChance = 12.0,     -- Base 12% chance for bonus loot
        levelBonus = 0.15,     -- +0.15% per mining level (15% at level 100)
        maxBonusChance = 35.0, -- Cap at 35% total chance

        -- Pickaxe bonuses
        pickaxeBonus = {
            chanceBonus = 4.0, -- +4% bonus chance per pickaxe tier above 1
            weightBonus = 0.15 -- +15% weight multiplier to non-crude ores per pickaxe tier above 1
        }
    }
}

-- ============================================================
-- TIERED XP SYSTEM
-- ============================================================

AtlasMiningConfig.XPSystem = {
    -- Base XP rewards by camp tier (doubles each tier)
    baseTierXP = {
        [1] = 150,  -- Tier 1 camps: 150 XP
        [2] = 300,  -- Tier 2 camps: 300 XP
        [3] = 600,  -- Tier 3 camps: 600 XP
        [4] = 1200, -- Tier 4 camps: 1200 XP
        [5] = 2400  -- Tier 5 camps: 2400 XP
    },

    -- Bonus XP multiplier when player gets bonus loot (double ore)
    bonusLootXPMultiplier = 2.0, -- Double XP when bonus loot triggers

    -- Optional: Additional multipliers for different pickaxe tiers
    pickaxeXPMultipliers = {
        [1] = 1.0, -- Crude pickaxe: no bonus
        [2] = 1.1, -- Fine pickaxe: +10% XP
        [3] = 1.2, -- Great pickaxe: +20% XP
        [4] = 1.3, -- Superior pickaxe: +30% XP
        [5] = 1.5  -- Legendary pickaxe: +50% XP
    }
}

-- ============================================================
-- ANIMATION CONFIG (from vorp_mining logic)
-- ============================================================

-- Pickaxe prop model
AtlasMiningConfig.PickaxePropModel = "p_pickaxe01x"

-- Mining animation dictionary and body
AtlasMiningConfig.MiningAnimDict = "amb_work@world_human_pickaxe_new@working@male_a@trans"
AtlasMiningConfig.MiningAnimBody = "pre_swing_trans_after_swing"

-- Bone index for attaching pickaxe (7966 = left hand / pitchfork carry bone)
AtlasMiningConfig.PickaxeAttachBone = 7966

-- ============================================================
-- LOOT CALCULATION FUNCTIONS (Same math as woodcutting)
-- ============================================================

function AtlasMiningConfig.CalculateLootWeights(playerLevel, campTier, pickaxeTier, isBonus)
    local loot = AtlasMiningConfig.LootSystem
    local weights = {}
    local totalWeight = 0

    -- Validate camp access
    local requiredLevel = AtlasMiningConfig.CampUnlocks[campTier]
    if requiredLevel and playerLevel < requiredLevel then
        return nil, requiredLevel -- Return required level for error message
    end

    -- Calculate weights for each ore type
    for oreType, baseWeight in pairs(loot.baseWeights) do
        local minLevel = loot.levelRequirements[oreType]

        -- Skip if player doesn't meet level requirement
        if playerLevel >= minLevel then
            -- Base weight calculation with level scaling
            local weight = baseWeight
            local scalingFactor = loot.levelScaling[oreType]

            if scalingFactor > 0 and playerLevel > minLevel then
                local levelBonus = (playerLevel - minLevel) / scalingFactor
                weight = baseWeight * (1 + levelBonus)
            end

            -- Apply camp tier effects
            local campEffect = loot.campEffects[campTier] and loot.campEffects[campTier][oreType] or 1.0
            weight = weight * campEffect

            -- Apply pickaxe bonuses for higher-tier ores (not crude)
            if pickaxeTier > 1 and oreType ~= "iron_ore_crude" then
                local pickaxeMultiplier = 1 + ((pickaxeTier - 1) * loot.bonusLoot.pickaxeBonus.weightBonus)
                weight = weight * pickaxeMultiplier
            end

            -- For bonus loot, slightly reduce crude weight to make it more interesting
            if isBonus and oreType == "iron_ore_crude" then
                weight = weight * 0.7
            end

            weights[oreType] = weight
            totalWeight = totalWeight + weight
        end
    end

    return weights, totalWeight
end

function AtlasMiningConfig.RollForLoot(weights, totalWeight)
    if totalWeight <= 0 then return nil end

    local roll = math.random() * totalWeight
    local currentWeight = 0

    for oreType, weight in pairs(weights) do
        currentWeight = currentWeight + weight
        if roll <= currentWeight then
            return oreType
        end
    end

    -- Fallback to first available ore type
    for oreType, _ in pairs(weights) do
        return oreType
    end

    return nil
end

function AtlasMiningConfig.CalculateBonusChance(playerLevel, pickaxeTier)
    local bonusConfig = AtlasMiningConfig.LootSystem.bonusLoot

    -- Base chance + level bonus
    local chance = bonusConfig.baseChance + (playerLevel * bonusConfig.levelBonus)

    -- Pickaxe tier bonus
    if pickaxeTier > 1 then
        chance = chance + ((pickaxeTier - 1) * bonusConfig.pickaxeBonus.chanceBonus)
    end

    -- Cap at maximum
    chance = math.min(chance, bonusConfig.maxBonusChance)

    return chance
end

-- Calculate XP reward based on camp tier, pickaxe tier, and whether bonus loot was awarded
function AtlasMiningConfig.CalculateXPReward(campTier, pickaxeTier, hasBonusLoot)
    local xpConfig = AtlasMiningConfig.XPSystem

    -- Get base XP for this camp tier
    local baseXP = xpConfig.baseTierXP[campTier] or xpConfig.baseTierXP[1]

    -- Apply pickaxe multiplier
    local pickaxeMultiplier = xpConfig.pickaxeXPMultipliers[pickaxeTier] or 1.0
    local xpAmount = baseXP * pickaxeMultiplier

    -- Apply bonus loot multiplier if player got bonus loot
    if hasBonusLoot then
        xpAmount = xpAmount * xpConfig.bonusLootXPMultiplier
    end

    -- Round to nearest integer
    return math.floor(xpAmount + 0.5)
end

-- Validation function
function AtlasMiningConfig.ValidateLootSystem()
    local errors = {}

    -- Check that all ore types have required config
    for oreType, _ in pairs(AtlasMiningConfig.LootSystem.baseWeights) do
        if not AtlasMiningConfig.LootSystem.levelRequirements[oreType] then
            table.insert(errors, "Missing level requirement for " .. oreType)
        end
        if not AtlasMiningConfig.LootSystem.levelScaling[oreType] then
            table.insert(errors, "Missing level scaling for " .. oreType)
        end
    end

    -- Check camp effects
    for tier = 1, 5 do
        if not AtlasMiningConfig.LootSystem.campEffects[tier] then
            table.insert(errors, "Missing camp effects for tier " .. tier)
        end
    end

    if #errors > 0 then
        for _, error in ipairs(errors) do
            print("^1[Atlas Mining Config Error]^7 " .. error)
        end
        return false
    end

    return true
end
