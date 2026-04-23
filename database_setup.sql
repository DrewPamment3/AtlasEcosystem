-- Atlas Ecosystem Database Setup
-- Run this file in your MySQL database to set up all required tables and items

-- =====================================================
-- ATLAS SKILLING TABLES
-- =====================================================

-- Create character_skills table if it doesn't exist
CREATE TABLE IF NOT EXISTS `character_skills` (
  `charidentifier` int(11) NOT NULL,
  `woodcutting_xp` int(11) NOT NULL DEFAULT 0,
  `mining_xp` int(11) NOT NULL DEFAULT 0,
  `smelting_xp` int(11) NOT NULL DEFAULT 0,
  `fishing_xp` int(11) NOT NULL DEFAULT 0,
  `smithing_xp` int(11) NOT NULL DEFAULT 0,
  `gunsmithing_xp` int(11) NOT NULL DEFAULT 0,
  `cooking_xp` int(11) NOT NULL DEFAULT 0,
  `farming_xp` int(11) NOT NULL DEFAULT 0,
  `stable_hand_xp` int(11) NOT NULL DEFAULT 0,
  `ranch_hand_xp` int(11) NOT NULL DEFAULT 0,
  `hunting_xp` int(11) NOT NULL DEFAULT 0,
  PRIMARY KEY (`charidentifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- =====================================================
-- ATLAS WOODCUTTING TABLES
-- =====================================================

-- Create forest management tables
CREATE TABLE IF NOT EXISTS `atlas_woodcutting_forests` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `x` float NOT NULL,
  `y` float NOT NULL,
  `z` float NOT NULL,
  `radius` int(11) NOT NULL,
  `tree_count` int(11) NOT NULL,
  `tier` int(11) NOT NULL,
  `model_name` varchar(100) NOT NULL,
  `name` varchar(100) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `atlas_woodcutting_nodes` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `forest_id` int(11) NOT NULL,
  `x` float NOT NULL,
  `y` float NOT NULL,
  `z` float NOT NULL,
  `model_name` varchar(100) NOT NULL,
  `is_dead` tinyint(1) NOT NULL DEFAULT 0,
  `respawn_time` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `forest_id` (`forest_id`),
  FOREIGN KEY (`forest_id`) REFERENCES `atlas_woodcutting_forests`(`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- =====================================================
-- VORP INVENTORY ITEMS - AXES
-- =====================================================

-- Insert axe items into VORP inventory items table
-- Note: Adjust the table name if your VORP installation uses a different items table name

INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`) VALUES
('crude_axe', 'Crude Axe', 1, 1, 'item_weapon', 0),
('fine_axe', 'Fine Axe', 1, 1, 'item_weapon', 0),
('great_axe', 'Great Axe', 1, 1, 'item_weapon', 0),
('superior_axe', 'Superior Axe', 1, 1, 'item_weapon', 0),
('legendary_axe', 'Legendary Axe', 1, 1, 'item_weapon', 0);

-- =====================================================
-- VORP INVENTORY ITEMS - WOOD TYPES
-- =====================================================

-- Insert wood items into VORP inventory items table
INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`) VALUES
('wood_crude', 'Crude Wood', 100, 1, 'item_standard', 0),
('wood_common', 'Common Wood', 100, 1, 'item_standard', 0),
('wood_rare', 'Rare Wood', 50, 1, 'item_standard', 0),
('wood_superior', 'Superior Wood', 25, 1, 'item_standard', 0),
('wood_legendary', 'Legendary Wood', 10, 1, 'item_standard', 0);

-- Alternative wood naming convention (if using different names)
INSERT IGNORE INTO `items` (`item`, `label`, `limit`, `can_remove`, `type`, `usable`) VALUES
('crude_wood', 'Crude Wood', 100, 1, 'item_standard', 0),
('fine_wood', 'Fine Wood', 100, 1, 'item_standard', 0),
('great_wood', 'Great Wood', 50, 1, 'item_standard', 0),
('superior_wood', 'Superior Wood', 25, 1, 'item_standard', 0),
('legendary_wood', 'Legendary Wood', 10, 1, 'item_standard', 0);

-- =====================================================
-- VERIFICATION QUERIES
-- =====================================================

-- Run these to verify the setup was successful:

-- Check if skill tables exist
-- SELECT COUNT(*) as skill_profiles FROM character_skills;

-- Check if forest tables exist  
-- SELECT COUNT(*) as total_forests FROM atlas_woodcutting_forests;
-- SELECT COUNT(*) as total_nodes FROM atlas_woodcutting_nodes;

-- Check if axe items were created
-- SELECT item, label FROM items WHERE item LIKE '%axe%';

-- Check if wood items were created
-- SELECT item, label FROM items WHERE item LIKE '%wood%';

-- =====================================================
-- ADMIN SETUP (OPTIONAL)
-- =====================================================

-- If you need to give yourself admin permissions, update your character:
-- UPDATE characters SET `group` = 'admin' WHERE charidentifier = YOUR_CHAR_ID;

-- Find your character ID first:
-- SELECT charidentifier, firstname, lastname FROM characters WHERE identifier = 'YOUR_STEAM_ID';

-- =====================================================
-- NOTES
-- =====================================================

-- 1. Make sure to replace YOUR_CHAR_ID and YOUR_STEAM_ID with actual values
-- 2. The items table name might be different in your VORP installation 
--    Common names: `items`, `vorp_items`, `inventory_items`
-- 3. Test the setup by:
--    - Joining the server
--    - Using /skills command
--    - Using /createforest command (as admin)
--    - Checking inventory for axe items
-- 4. If items still don't work, check your VORP inventory configuration
--    and make sure the item names match exactly

