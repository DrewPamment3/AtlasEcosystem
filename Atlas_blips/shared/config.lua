AtlasBlipsConfig = {}

-- ============================================================
-- GENERAL SETTINGS
-- ============================================================

-- Enable verbose console logging
AtlasBlipsConfig.DebugLogging = true

-- ============================================================
-- BLIP APPEARANCE
-- ============================================================

-- RDR2 Blip Color indices (INTEGER values, NOT hex color codes)
-- These are indices into the game's internal blip color palette
-- Common RDR2 values:
--   1 = Red, 2 = Green, 3 = Blue, 4 = White (player),
--   5 = Yellow, 6 = Orange, 7 = Light Blue, 8 = Grey,
--   11 = Dark Grey, 25 = Brown/Dark Orange, 27 = Light Brown
--   Full list: https://alloc8or.re/rdr3/doc/blips/
AtlasBlipsConfig.Colors = {
    mining      = 8,  -- Grey
    woodcutting = 27, -- Light Brown (native palette index)
}

-- RDR2 Blip Sprite Hash (Joaat integer)
-- These should be computed from the string name via GetHashKey()
-- But we define known-good values explicitly here for reference
AtlasBlipsConfig.Sprites = {
    -- All sprite names confirmed to exist in RDR2 via femga/rdr3_discoveries
    -- texture list: https://github.com/femga/rdr3_discoveries/tree/master/useful_info_from_rpfs/textures/blips
    mining      = "blip_gold",            -- Joaat: -1289383059
    woodcutting = "blip_event_appleseed", -- Joaat: 1904459580 (confirmed working)
    radius      = "blip_radius_search",   -- Joaat: 150441873 (confirmed in femga blip textures)
}

-- Radius Blip Alpha (0-255)
-- 128 = 50% transparent, makes the circle semi-transparent so it doesn't
-- block the underlying map terrain
AtlasBlipsConfig.RadiusAlpha = 128

-- Scale of the sprite blip (icon size on minimap/world map)
-- RDR2 blips are naturally larger than GTA V
-- 0.3-0.6 is a good range for visible but not oversized
AtlasBlipsConfig.SpriteScale = 0.4

-- ============================================================
-- BLIP DISPLAY CATEGORIES
-- ============================================================

-- Toggle which types of blips are shown on the map
AtlasBlipsConfig.ShowBlips = {
    mining      = true,
    woodcutting = true,
}

-- ============================================================
-- DATABASE SETTINGS
-- ============================================================

-- Tables queried for zone data on resource start
AtlasBlipsConfig.Tables = {
    mining      = "atlas_mining_camps",
    woodcutting = "atlas_woodcutting_forests",
}

-- ============================================================
-- CLIENT SETTINGS
-- ============================================================

-- Delay (ms) after player loads before requesting zone data
-- Allow time for the character system and other resources to initialize
AtlasBlipsConfig.ReconnectBlipDelay = 5000
