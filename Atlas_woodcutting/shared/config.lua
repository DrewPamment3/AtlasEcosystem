AtlasWoodConfig = {}

-- Interaction & Rewards
AtlasWoodConfig.ChopXPReward = 20           -- XP per successful chop
AtlasWoodConfig.InteractionKey = 0x760A9C6F -- G key (0x760A9C6F)
AtlasWoodConfig.ChopAnimationTime = 5000    -- Milliseconds for chop animation
AtlasWoodConfig.MinChopTime = 5000          -- 5 Seconds

-- Animation Configuration (Try these in order, falls back to scenario if none available)
AtlasWoodConfig.ChopAnimations = {
    -- Candidate animations to try (add more as you discover them)
    -- Format: { dict = "dictionary_name", anim = "animation_name", duration = milliseconds }
    { dict = "combat@damage@rb_writhe", anim = "rb_writhe_loop", duration = 5000 },
    { dict = "melee@scratching", anim = "scratching_ground", duration = 5000 },
    { dict = "misscompstat@idle", anim = "base_idle", duration = 5000 },
}
AtlasWoodConfig.UseScenarioFallback = true -- If no animation dict available, use WORLD_HUMAN_TREE_CHOP scenario

-- Interrupt Detection
AtlasWoodConfig.DetectHealthDrop = true     -- Cancel chop if player health drops
AtlasWoodConfig.DetectMovement = true       -- Cancel chop if player presses WASD/movement
AtlasWoodConfig.MovementKeys = { 32, 33, 34, 35 } -- Space(32), W(33), A(34), S(35), D(36) - RedM keycodes

-- Distance & Rendering
AtlasWoodConfig.RenderDistance = 400       -- Max distance to render forests (meters)
AtlasWoodConfig.RespawnMinutesPerTier = 20 -- Base respawn time (doubled per tier level)

-- Admin Command Validation
AtlasWoodConfig.RadiusRange = { min = 10, max = 50 }   -- Forest radius meters
AtlasWoodConfig.TreeCountRange = { min = 5, max = 25 } -- Trees per forest
AtlasWoodConfig.TierRange = { min = 1, max = 4 }       -- Forest tier levels
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
    [1] = 1.0, -- Normal
    [2] = 1.5, -- Better
    [3] = 2.5, -- Rare
    [4] = 5.0  -- Legendary
}

AtlasWoodConfig.Axes = {
    ["crude_axe"]     = { tier = 1, power = 1.0 },
    ["fine_axe"]      = { tier = 2, power = 1.2 },
    ["great_axe"]     = { tier = 3, power = 1.5 },
    ["superior_axe"]  = { tier = 4, power = 2.0 },
    ["legendary_axe"] = { tier = 5, power = 3.0 }
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
    ["p_tree_redwood_05_lg"] = 1.5,
    ["p_tree_engoak_01"] = 1.0,
    ["prop_tree_stump_01"] = 0.5,  -- Stump model
}

-- Function to get Z offset for a model (returns default 0.2 if not found)
function AtlasWoodConfig.GetTreeZOffset(modelName)
    return AtlasWoodConfig.TreeModelZOffsets[modelName] or 0.2
end

-- Function to try loading animation dictionaries and return first available (CLIENT-ONLY)
-- Returns: {dict=string, anim=string} or nil if none available
function AtlasWoodConfig.GetAvailableAnimation()
    if not IsDuplicityVersion() then -- Only run on client
        for _, animData in ipairs(AtlasWoodConfig.ChopAnimations) do
            if HasAnimDictLoaded(animData.dict) or GetHashKey(animData.dict) then
                return animData
            end
        end
    end
    return nil
end
