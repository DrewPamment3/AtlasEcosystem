AtlasBlipsConfig = {}

-- ============================================================
-- GENERAL SETTINGS
-- ============================================================

-- Enable verbose console logging
AtlasBlipsConfig.DebugLogging = true

-- ============================================================
-- BLIP APPEARANCE
-- ============================================================

-- RDR3 Color Hashes (use native hash syntax `value`)
-- Color 19 (Grey) → BLIP_COLOR_GREY hash 0x32A69E81
-- Color 26 (Brown) → BLIP_COLOR_BROWN hash 0x662D3643
AtlasBlipsConfig.Colors = {
    mining = `BLIP_COLOR_GREY`,       -- 0x32A69E81
    woodcutting = `BLIP_COLOR_BROWN`, -- 0x662D3643
}

-- RDR3 Sprite Hashes
-- blip_ambient_pickaxe = 0x46E47A9A (pickaxe icon for mining)
-- blip_ambient_herb = 0x7C934E8A (herb/leaf icon for woodcutting)
-- blip_type_radius = 0x697D59A (radius circle type)
AtlasBlipsConfig.Sprites = {
    mining = `blip_ambient_pickaxe`,  -- 0x46E47A9A
    woodcutting = `blip_ambient_herb`, -- 0x7C934E8A
    radius = `blip_type_radius`,      -- 0x697D59A
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
