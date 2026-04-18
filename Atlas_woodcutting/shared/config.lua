AtlasWoodConfig = {}

AtlasWoodConfig.MinChopTime = 5000 -- 5 Seconds

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
