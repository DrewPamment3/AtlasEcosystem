AtlasBlipsConfig = {}

-- ============================================================
-- GENERAL SETTINGS
-- ============================================================

-- Enable verbose console logging
AtlasBlipsConfig.DebugLogging = false

-- ============================================================
-- BLIP APPEARANCE
-- ============================================================

-- Color IDs (RDR3 Verified)
-- 26 = Brown (Woodcutting), 19 = Grey/Dark Grey (Mining)
AtlasBlipsConfig.Colors = {
    mining = 19,      -- Grey for mining camps
    woodcutting = 26, -- Brown for woodcutting forests
}

-- Sprite Hash Names for RDR3 Blips
-- These are the string names fed to GetHashKey() / AddBlipForCoord
AtlasBlipsConfig.Sprites = {
    mining = "blip_ambient_pickaxe",      -- Pickaxe icon for mining zones
    woodcutting = "blip_ambient_herb",    -- Leaf/herb icon for woodcutting zones
}

-- Radius Blip Alpha (128 = 50% transparent, makes the circle semi-transparent)
AtlasBlipsConfig.RadiusAlpha = 128

-- Scale of the sprite blip (icon size)
AtlasBlipsConfig.SpriteScale = 0.8

-- ============================================================
-- BLIP DISPLAY CATEGORIES
-- ============================================================

-- Toggle which types of blips are created
-- Set to false to disable a specific type of zone
AtlasBlipsConfig.ShowBlips = {
    mining = true,
    woodcutting = true,
}

-- ============================================================
-- DATABASE SETTINGS
-- ============================================================

-- Tables to query for zone data
AtlasBlipsConfig.Tables = {
    mining = "atlas_mining_camps",
    woodcutting = "atlas_woodcutting_forests",
}

-- ============================================================
-- CLIENT SETTINGS
-- ============================================================

-- Delay (in ms) after player loads before refreshing blips on reconnect
AtlasBlipsConfig.ReconnectBlipDelay = 3000
