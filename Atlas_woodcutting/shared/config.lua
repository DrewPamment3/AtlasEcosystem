Config = {}

-- Wood Definition
Config.WoodTiers = {
    { id = 1, name = "crude_wood",     minLevel = 1,  baseWeight = 100, weightMultiplier = 1.0 },
    { id = 2, name = "fine_wood",      minLevel = 1,  baseWeight = 5,   weightMultiplier = 1.5 },
    { id = 3, name = "great_wood",     minLevel = 20, baseWeight = 2,   weightMultiplier = 2.0 },
    { id = 4, name = "superior_wood",  minLevel = 45, baseWeight = 1,   weightMultiplier = 3.0 },
    { id = 5, name = "legendary_wood", minLevel = 70, baseWeight = 0.5, weightMultiplier = 5.0, reqAxeTier = 4 }
}

-- Axe Definition
Config.Axes = {
    ["crude_axe"]     = { tier = 1, power = 1.0 },
    ["fine_axe"]      = { tier = 2, power = 1.2 },
    ["great_axe"]     = { tier = 3, power = 1.5 },
    ["superior_axe"]  = { tier = 4, power = 2.0 },
    ["legendary_axe"] = { tier = 5, power = 3.0 }
}

-- Tree Hashes (What objects can be chopped)
Config.Trees = {
    [1035651700] = { name = "Pine", xp = 25 },
    [1998592543] = { name = "Oak", xp = 40 },
    -- Add more as needed
}

Config.MinChopTime = 5000 -- 5 seconds minimum to prevent speed-hacking
