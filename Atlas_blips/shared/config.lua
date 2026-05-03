AtlasBlipsConfig = {}

-- ============================================================
-- GENERAL SETTINGS
-- ============================================================

-- Enable verbose console logging
AtlasBlipsConfig.DebugLogging = true

-- ============================================================
-- BLIP APPEARANCE
-- ============================================================

-- STRING NAMES for RDR3 colors (hashed at runtime via GetHashKey)
AtlasBlipsConfig.Colors = {
    mining = "BLIP_COLOR_GREY",       -- RDR3 standard grey
    woodcutting = "BLIP_COLOR_BROWN", -- RDR3 standard brown
}

-- STRING NAMES for RDR3 sprites (hashed at runtime via GetHashKey)
AtlasBlipsConfig.Sprites = {
    mining = "blip_ambient_pickaxe",  -- Pickaxe icon for mining zones
    woodcutting = "blip_ambient_herb", -- Herb/leaf icon for woodcutting zones
    radius = "blip_type_radius",      -- Radius circle type
}

-- Radius Blip Alpha (128 = 50% transparent, makes the circle semi-transparent)
AtlasBlipsConfig.RadiusAlpha = 128

-- Scale of the sprite blip (icon size)
-- RDR3 blips are much larger than GTA V; 0.2-0.5 is appropriate
AtlasBlipsConfig.SpriteScale = 0.2

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
AtlasBlipsConfig.ReconnectBlipDelay = 5000
