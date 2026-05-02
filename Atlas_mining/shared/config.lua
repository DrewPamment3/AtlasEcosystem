AtlasMiningConfig = {}

-- Interaction & Rewards
AtlasMiningConfig.InteractionKey = 0x760A9C6F -- G key (0x760A9C6F)
AtlasMiningConfig.MineAnimationTime = 5000    -- Milliseconds for mining animation (DEPRECATED - now uses progress system)

-- Progress Bar System
AtlasMiningConfig.HitsRequired = 4        -- Fixed number of hits to mine a rock (always 4 swings)
AtlasMiningConfig.HitAnimationTime = 2500 -- Time for each mining hit animation (ms)

-- Interruption Detection (cancels mining if player moves, takes damage, or enters combat)
AtlasMiningConfig.Interruption = {
    enabled = true,
    maxMovementDistance = 1.0,  -- Max distance from start before cancelling
    checkInterval = 50,         -- How often to check for interruptions (ms)
    healthCheckEnabled = true,  -- Cancel if player takes damage
    combatCheckEnabled = true   -- Cancel if player enters combat
}

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
    ["roa_int_rock_07"] = 1.3,
    ["roa_int_rock_05"] = 1.3,
    ["roa_int_rock_08"] = 1.3,
    ["roa_int_rock_09"] = 1.3,
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
-- PICKAXE CONFIGURATION (Tier 1-5) - Updated to match DB
-- ============================================================

AtlasMiningConfig.Pickaxes = {
    ["pickaxe_crude"]     = { tier = 1, power = 1.0 },
    ["pickaxe_common"]    = { tier = 2, power = 1.2 },
    ["pickaxe_great"]     = { tier = 3, power = 1.5 },
    ["pickaxe_superior"]  = { tier = 4, power = 2.0 },
    ["pickaxe_legendary"] = { tier = 5, power = 3.0 }
}

AtlasMiningConfig.PickaxeUnlocks = {
    ["pickaxe_crude"] = 1,
    ["pickaxe_common"] = 20,
    ["pickaxe_great"] = 45,
    ["pickaxe_superior"] = 70,
    ["pickaxe_legendary"] = 90
}

-- ============================================================
-- ORE CONFIGURATION (Copper, Tin, Iron, Gold - each 5 tiers)
-- ============================================================

-- Rarity hierarchy (most common to rarest):
--   Copper > Tin > Iron > Gold
-- Each metal has 5 quality tiers: crude, common, great, superior, legendary

AtlasMiningConfig.OreTiers = {
    -- COPPER (most common - good for beginners)
    { id = 1,  metal = "copper", name = "copper_crude",     minLevel = 1,  baseWeight = 120, weightMultiplier = 1.0 },
    { id = 2,  metal = "copper", name = "copper_common",    minLevel = 1,  baseWeight = 8,   weightMultiplier = 1.5 },
    { id = 3,  metal = "copper", name = "copper_great",     minLevel = 20, baseWeight = 3,   weightMultiplier = 2.0 },
    { id = 4,  metal = "copper", name = "copper_superior",  minLevel = 45, baseWeight = 1.5, weightMultiplier = 3.0 },
    { id = 5,  metal = "copper", name = "copper_legendary", minLevel = 70, baseWeight = 0.8, weightMultiplier = 5.0, reqPickaxeTier = 4 },
    -- TIN (common - similar to copper)
    { id = 6,  metal = "tin", name = "tin_crude",     minLevel = 1,  baseWeight = 100, weightMultiplier = 1.0 },
    { id = 7,  metal = "tin", name = "tin_common",    minLevel = 1,  baseWeight = 7,   weightMultiplier = 1.5 },
    { id = 8,  metal = "tin", name = "tin_great",     minLevel = 20, baseWeight = 2.5, weightMultiplier = 2.0 },
    { id = 9,  metal = "tin", name = "tin_superior",  minLevel = 45, baseWeight = 1.2, weightMultiplier = 3.0 },
    { id = 10, metal = "tin", name = "tin_legendary", minLevel = 70, baseWeight = 0.6, weightMultiplier = 5.0, reqPickaxeTier = 4 },
    -- IRON (uncommon - mid-tier resource)
    { id = 11, metal = "iron", name = "iron_ore_crude",     minLevel = 1,  baseWeight = 80,  weightMultiplier = 1.0 },
    { id = 12, metal = "iron", name = "iron_ore_common",    minLevel = 10, baseWeight = 5,   weightMultiplier = 1.5 },
    { id = 13, metal = "iron", name = "iron_ore_great",     minLevel = 30, baseWeight = 2,   weightMultiplier = 2.0 },
    { id = 14, metal = "iron", name = "iron_ore_superior",  minLevel = 55, baseWeight = 1,   weightMultiplier = 3.0 },
    { id = 15, metal = "iron", name = "iron_ore_legendary", minLevel = 80, baseWeight = 0.4, weightMultiplier = 5.0, reqPickaxeTier = 4 },
    -- GOLD (rare - most valuable, hardest to find)
    { id = 16, metal = "gold", name = "gold_crude",     minLevel = 20, baseWeight = 40,  weightMultiplier = 1.0 },
    { id = 17, metal = "gold", name = "gold_common",    minLevel = 30, baseWeight = 3,   weightMultiplier = 1.5 },
    { id = 18, metal = "gold", name = "gold_great",     minLevel = 50, baseWeight = 1,   weightMultiplier = 2.0 },
    { id = 19, metal = "gold", name = "gold_superior",  minLevel = 75, baseWeight = 0.5, weightMultiplier = 3.0 },
    { id = 20, metal = "gold", name = "gold_legendary", minLevel = 95, baseWeight = 0.2, weightMultiplier = 5.0, reqPickaxeTier = 5 }
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
-- LOOT SYSTEM (Copper, Tin, Iron, Gold + Gem drops)
-- ============================================================

AtlasMiningConfig.LootSystem = {
    -- Base weights for each ore type (starting point before any multipliers)
    baseWeights = {
        -- Copper (most common)
        copper_crude = 120,
        copper_common = 20,
        copper_great = 6,
        copper_superior = 3,
        copper_legendary = 0.8,
        -- Tin (common)
        tin_crude = 100,
        tin_common = 15,
        tin_great = 5,
        tin_superior = 2.5,
        tin_legendary = 0.6,
        -- Iron (uncommon)
        iron_ore_crude = 80,
        iron_ore_common = 10,
        iron_ore_great = 3,
        iron_ore_superior = 1.5,
        iron_ore_legendary = 0.4,
        -- Gold (rare)
        gold_crude = 40,
        gold_common = 5,
        gold_great = 1.5,
        gold_superior = 0.7,
        gold_legendary = 0.2
    },

    -- Level requirements to start getting each ore type
    levelRequirements = {
        -- Copper (earliest)
        copper_crude = 1,
        copper_common = 1,
        copper_great = 20,
        copper_superior = 45,
        copper_legendary = 70,
        -- Tin (early)
        tin_crude = 1,
        tin_common = 1,
        tin_great = 20,
        tin_superior = 45,
        tin_legendary = 70,
        -- Iron (mid-game)
        iron_ore_crude = 1,
        iron_ore_common = 10,
        iron_ore_great = 30,
        iron_ore_superior = 55,
        iron_ore_legendary = 80,
        -- Gold (late-game, rare)
        gold_crude = 20,
        gold_common = 30,
        gold_great = 50,
        gold_superior = 75,
        gold_legendary = 95
    },

    -- Level scaling factors: higher = slower scaling, lower = faster scaling
    levelScaling = {
        -- Copper
        copper_crude = 0,
        copper_common = 35,
        copper_great = 40,
        copper_superior = 30,
        copper_legendary = 25,
        -- Tin
        tin_crude = 0,
        tin_common = 35,
        tin_great = 40,
        tin_superior = 30,
        tin_legendary = 25,
        -- Iron
        iron_ore_crude = 0,
        iron_ore_common = 40,
        iron_ore_great = 45,
        iron_ore_superior = 35,
        iron_ore_legendary = 28,
        -- Gold (slower scaling = stays rare longer)
        gold_crude = 0,
        gold_common = 50,
        gold_great = 55,
        gold_superior = 45,
        gold_legendary = 35
    },

    -- Camp tier effects on each ore type (multipliers)
    campEffects = {
        [1] = { -- Tier 1: Copper & Tin only, heavily favors crude
            copper_crude = 1.0,    copper_common = 0.3, copper_great = 0.0, copper_superior = 0.0, copper_legendary = 0.0,
            tin_crude = 0.8,        tin_common = 0.2,    tin_great = 0.0,    tin_superior = 0.0,    tin_legendary = 0.0,
            iron_ore_crude = 0.5,   iron_ore_common = 0.1, iron_ore_great = 0.0, iron_ore_superior = 0.0, iron_ore_legendary = 0.0,
            gold_crude = 0.1,       gold_common = 0.0,   gold_great = 0.0,   gold_superior = 0.0,   gold_legendary = 0.0
        },
        [2] = { -- Tier 2: Introduces more common tiers, tiny gold
            copper_crude = 0.8,    copper_common = 1.2, copper_great = 0.3, copper_superior = 0.0, copper_legendary = 0.0,
            tin_crude = 0.7,        tin_common = 1.0,    tin_great = 0.3,    tin_superior = 0.0,    tin_legendary = 0.0,
            iron_ore_crude = 0.6,   iron_ore_common = 0.8, iron_ore_great = 0.2, iron_ore_superior = 0.0, iron_ore_legendary = 0.0,
            gold_crude = 0.2,       gold_common = 0.0,   gold_great = 0.0,   gold_superior = 0.0,   gold_legendary = 0.0
        },
        [3] = { -- Tier 3: Balanced, introduces great tiers
            copper_crude = 0.5,    copper_common = 1.0, copper_great = 1.5, copper_superior = 0.4, copper_legendary = 0.0,
            tin_crude = 0.5,        tin_common = 1.0,    tin_great = 1.5,    tin_superior = 0.4,    tin_legendary = 0.0,
            iron_ore_crude = 0.4,   iron_ore_common = 0.7, iron_ore_great = 1.0, iron_ore_superior = 0.3, iron_ore_legendary = 0.0,
            gold_crude = 0.3,       gold_common = 0.2,   gold_great = 0.4,   gold_superior = 0.0,   gold_legendary = 0.0
        },
        [4] = { -- Tier 4: Higher tiers appear, gold becomes viable
            copper_crude = 0.3,    copper_common = 0.7, copper_great = 1.2, copper_superior = 1.8, copper_legendary = 0.6,
            tin_crude = 0.3,        tin_common = 0.7,    tin_great = 1.2,    tin_superior = 1.8,    tin_legendary = 0.6,
            iron_ore_crude = 0.2,   iron_ore_common = 0.5, iron_ore_great = 0.8, iron_ore_superior = 1.5, iron_ore_legendary = 0.5,
            gold_crude = 0.4,       gold_common = 0.4,   gold_great = 0.8,   gold_superior = 1.0,   gold_legendary = 0.3
        },
        [5] = { -- Tier 5: Premium camp, best rare ore & legendary chances
            copper_crude = 0.2,    copper_common = 0.5, copper_great = 0.9, copper_superior = 1.5, copper_legendary = 2.5,
            tin_crude = 0.2,        tin_common = 0.5,    tin_great = 0.9,    tin_superior = 1.5,    tin_legendary = 2.5,
            iron_ore_crude = 0.15,  iron_ore_common = 0.4, iron_ore_great = 0.7, iron_ore_superior = 1.2, iron_ore_legendary = 2.0,
            gold_crude = 0.5,       gold_common = 0.6,   gold_great = 1.2,   gold_superior = 2.0,   gold_legendary = 3.0
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
-- GEM DROP SYSTEM
-- ============================================================
-- Gems are a separate roll after ore is determined
-- Base 3% flat chance, pickaxe tiers add up to a max of 15%

AtlasMiningConfig.GemSystem = {
    enabled = true,

    -- Flat base chance (3% - same for all players regardless of level)
    baseChance = 3.0,

    -- Additional chance per pickaxe tier (each tier above 1 adds this %)
    -- Tier 1 = +0%, Tier 2 = +3%, Tier 3 = +6%, Tier 4 = +9%, Tier 5 = +12%
    pickaxeTierBonus = 3.0,

    -- Maximum total gem chance (cap)
    maxChance = 15.0,

    -- List of possible gems and their relative weights
    gems = {
        { name = "uncut_amethyst",      weight = 15,  minLevel = 1 },
        { name = "uncut_lapis_lazuli",  weight = 13,  minLevel = 1 },
        { name = "uncut_topaz",         weight = 12,  minLevel = 1 },
        { name = "uncut_emerald",       weight = 10,  minLevel = 5 },
        { name = "uncut_sapphire",      weight = 9,   minLevel = 5 },
        { name = "uncut_ruby",          weight = 8,   minLevel = 15 },
        { name = "uncut_opal",          weight = 7,   minLevel = 25 },
        { name = "uncut_jade",          weight = 6,   minLevel = 40 },
        { name = "uncut_onyx",          weight = 4,   minLevel = 55 },
        { name = "uncut_diamond",       weight = 3,   minLevel = 70 }
    }
}

-- Function to calculate gem drop chance
function AtlasMiningConfig.CalculateGemChance(pickaxeTier)
    local gemConfig = AtlasMiningConfig.GemSystem
    if not gemConfig.enabled then return 0.0 end

    local chance = gemConfig.baseChance

    -- Pickaxe tier bonus
    if pickaxeTier > 1 then
        chance = chance + ((pickaxeTier - 1) * gemConfig.pickaxeTierBonus)
    end

    -- Cap at maximum
    chance = math.min(chance, gemConfig.maxChance)

    return chance
end

-- Function to roll for a gem (returns gem name or nil)
function AtlasMiningConfig.RollForGem(pickaxeTier, playerLevel)
    local gemConfig = AtlasMiningConfig.GemSystem
    if not gemConfig.enabled then return nil end

    local chance = AtlasMiningConfig.CalculateGemChance(pickaxeTier)
    local roll = math.random() * 100

    if roll > chance then
        return nil -- No gem dropped
    end

    -- Roll which gem type
    local validGems = {}
    local totalGemWeight = 0

    for _, gem in ipairs(gemConfig.gems) do
        if playerLevel >= gem.minLevel then
            table.insert(validGems, gem)
            totalGemWeight = totalGemWeight + gem.weight
        end
    end

    if #validGems == 0 or totalGemWeight <= 0 then
        return nil
    end

    local gemRoll = math.random() * totalGemWeight
    local currentWeight = 0

    for _, gem in ipairs(validGems) do
        currentWeight = currentWeight + gem.weight
        if gemRoll <= currentWeight then
            return gem.name
        end
    end

    -- Fallback to first valid gem
    return validGems[1] and validGems[1].name or nil
end

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

            -- For bonus loot, slightly reduce ALL crude ore weights to make it more interesting
            if isBonus and oreType:find("_crude$") then
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
