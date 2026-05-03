AtlasBlipsConfig = {}

-- ============================================================
-- GENERAL SETTINGS
-- ============================================================

-- Enable verbose console logging
AtlasBlipsConfig.DebugLogging = true

-- ============================================================
-- BLIP APPEARANCE
-- ============================================================

-- RDR3 Color Hashes (raw hex values, passed directly to natives)
AtlasBlipsConfig.Colors = {
    mining = 0x32A69E81,       -- BLIP_COLOR_GREY
    woodcutting = 0x662D3643, -- BLIP_COLOR_BROWN
}

-- RDR3 Sprite Hashes (raw hex values, passed directly to natives)
AtlasBlipsConfig.Sprites = {
    mining = 0x46E47A9A,         -- blip_ambient_pickaxe (unconfirmed, may need replacing)
    woodcutting = 0x7181B53C,    -- blip_event_appleseed (confirmed: 1904459580)
    radius = 0x697D59A,          -- blip_type_radius
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
