# Atlas Ecosystem

A modular RedM (Red Dead Redemption 2) RPG framework providing progressive skill-based gameplay systems. Currently featuring a core skills system and woodcutting resource gathering module.

**Author:** DrewPamment3  
**Game:** Red Dead Redemption 3 (RedM)  
**Version:** 1.0

---

## 📋 Project Structure

```
AtlasEcosystem/
├── Atlas_skilling/              # Core Experience & Leveling System
│   ├── fxmanifest.lua          # Resource manifest & exports
│   ├── client/main.lua         # Client-side UI and menus
│   ├── server/main.lua         # Server logic, XP manager, data persistence
│   └── shared/config.lua       # Configuration constants
│
└── Atlas_woodcutting/           # Woodcutting Gathering Module
    ├── fxmanifest.lua          # Resource manifest & dependencies
    ├── client/main.lua         # Tree spawning, interaction detection, minigames
    ├── server/main.lua         # Forest management, node persistence, XP rewards
    └── shared/config.lua       # Woodcutting tiers, axes, zone multipliers
```

---

## 🎮 Module Overview

### **Atlas_skilling** - Core Skills System

The foundation system that manages experience points and skill progression for players.

**Exported Functions:**

- `AddSkillXP(source, skill, amount, personalMult)` - Award XP to a player for a specific skill
- `GetSkillLevel(source, skill)` - Retrieve current skill level

**Features:**

- Tracks **11 skills**: Woodcutting, Mining, Smelting, Fishing, Smithing, Gunsmithing, Cooking, Farming, Stable Hand, Ranch Hand, Hunting
- **Level Progression**: Uses formula `Level = floor(sqrt(XP / 1331)) + 1`
- **Max Cap**: Level 99, XP cap at 13,034,431
- **XP Multipliers**: Global multiplier (1.0 default) + personal multiplier support
- **Database Persistence**: Stores XP in `character_skills` table per character
- **Menu Command**: `/skills` to view all current skill levels
- **Level-Up Notifications**: Alerts and sound effects when leveling up

**Database Requirements:**

- `character_skills` table (auto-created on character select)
  - charidentifier, woodcutting_xp, mining_xp, smelting_xp, fishing_xp, smithing_xp, gunsmithing_xp, cooking_xp, farming_xp, stable_hand_xp, ranch_hand_xp, hunting_xp

**Dependencies:**

- vorp_core
- oxmysql

---

### **Atlas_woodcutting** - Gathering Module

Tree chopping system built on top of Atlas_skilling. Players chop trees to gather wood and earn Woodcutting XP.

**Features:**

#### **Wood Tiers (5 Levels)**

| Tier | Name           | Min Level | Drop Weight | Weight Multiplier | Req Axe    |
| ---- | -------------- | --------- | ----------- | ----------------- | ---------- |
| 1    | Crude Wood     | 1         | 100         | 1.0x              | -          |
| 2    | Fine Wood      | 1         | 5           | 1.5x              | -          |
| 3    | Great Wood     | 20        | 2           | 2.0x              | -          |
| 4    | Superior Wood  | 45        | 1           | 3.0x              | -          |
| 5    | Legendary Wood | 70        | 0.5         | 5.0x              | Tier 4 Axe |

#### **Axe Tiers (5 Levels)**

| Axe           | Tier | Power Multiplier |
| ------------- | ---- | ---------------- |
| Crude Axe     | 1    | 1.0x             |
| Fine Axe      | 2    | 1.2x             |
| Great Axe     | 3    | 1.5x             |
| Superior Axe  | 4    | 2.0x             |
| Legendary Axe | 5    | 3.0x             |

#### **Zone Multipliers**

Different forest zones can have tier multipliers affecting wood rarity:

- Tier 1 (Normal): 1.0x
- Tier 2 (Better): 1.5x
- Tier 3 (Rare): 2.5x
- Tier 4 (Legendary): 5.0x

#### **Interaction System**

- **Prompt**: Press G near trees to chop
- **Animation**: 5-second chopping animation
- **Raycast Detection**: Line from player shoulder to 1.3m ahead
- **XP Reward**: 20 XP per successful chop

#### **Admin Commands**

**`/createforest [radius] [count] [tier] [model] [name]`**

- Creates a new forest zone with dynamically spawned trees
- Default radius: 15m, count: 10 trees, tier: 1
- Example: `/createforest 20 15 2 p_tree_pine01x "Pine Grove"`

**`/wipeforest [name]`**

- Removes all trees and forest data from specified zone
- Example: `/wipeforest "Pine Grove"`

**`/listforests [page]`**

- Lists all forests currently in the database with details
- Displays ID, Name, Radius, Tree Count, Tier, and Coordinates
- Shows 10 forests per page (optional page parameter, default: 1)
- Sorted alphabetically by forest name
- Example: `/listforests` or `/listforests 2`
- Output: Formatted console table for easy viewing

**`/debugtrees`**

- Lists all currently spawned trees with their forest IDs and entity numbers

**Database Requirements:**

- `atlas_woodcutting_forests` table
  - id, x, y, z, radius, tree_count, tier, model_name, name
- `atlas_woodcutting_nodes` table
  - id, forest_id, x, y, z, model_name

**Dependencies:**

- vorp_core
- vorp_inventory
- oxmysql
- **Atlas_skilling** (required - uses AddSkillXP)

---

## 🔧 Configuration

### **Atlas_skilling Config** (`shared/config.lua`)

```lua
Config.MenuKey = 0x8FD2C4BD          -- Menu hotkey (K)
Config.GlobalXPMultiplier = 1.0      -- Server-wide XP multiplier
Config.MaxXP = 13034431              -- Maximum XP per skill
Config.MaxLevel = 99                 -- Maximum skill level
Config.XPFormulaDivisor = 1331       -- Used in level calculation
```

### **Atlas_woodcutting Config** (`shared/config.lua`)

```lua
AtlasWoodConfig.MinChopTime = 5000   -- Minimum chop duration (ms)
AtlasWoodConfig.WoodTiers = {...}   -- Loot tiers with level reqs
AtlasWoodConfig.TierMultipliers = { -- Zone-based rarity multipliers
    [1] = 1.0,  [2] = 1.5,  [3] = 2.5,  [4] = 5.0
}
AtlasWoodConfig.Axes = {...}        -- Axe tier definitions
AtlasWoodConfig.TreeMaterials = {}  -- Fallback tree detection by material
AtlasWoodConfig.Trees = {...}       -- Static tree models with XP values
```

---

## 🚀 Getting Started

### **Prerequisites**

- RedM server running
- MySQL database
- VORP Core framework
- OxMySQL

### **Installation**

1. Place both `Atlas_skilling` and `Atlas_woodcutting` folders in your server's `resources/` directory
2. Add to `server.cfg`:
   ```
   ensure vorp_core
   ensure vorp_inventory
   ensure vorp_menu
   ensure oxmysql
   ensure Atlas_skilling
   ensure Atlas_woodcutting
   ```
3. Ensure MySQL tables are created (auto-created on first character select)

### **First Run**

- Players will get a skill profile auto-created when selecting a character
- Use `/skills` command to view your progression
- Admins can use `/createforest` to set up woodcutting zones

---

## 🔌 Integration Guide

### **Calling AddSkillXP from Another Module**

```lua
-- In your resource's server script
exports.Atlas_skilling:AddSkillXP(playerId, 'woodcutting', 50, 1.5)
-- Parameters: playerId, skillName, amount, personalMultiplier (optional)
```

### **Supported Skills**

- woodcutting
- mining
- smelting
- fishing
- smithing
- gunsmithing
- cooking
- farming
- stable_hand
- ranch_hand
- hunting

---

## 📊 Events

### **Client → Server**

- `atlas_skilling:getSkills` - Request skill data
- `Atlas_Woodcutting:Server:PlayerLoaded` - Sync all trees on load
- `Atlas_Woodcutting:Server:SaveNode` - Save new tree node
- `Atlas_Woodcutting:Server:RequestStart` - Start chopping interaction
- `Atlas_Woodcutting:Server:FinishChop` - Complete chop, award XP

### **Server → Client**

- `atlas_skilling:openMenu` - Display skills menu
- `atlas_skilling:xpNotification` - Show XP gain notification
- `atlas_skilling:levelUp` - Show level-up alert
- `Atlas_Woodcutting:Client:SyncNodes` - Sync forest trees
- `Atlas_Woodcutting:Client:BeginMinigame` - Start chopping animation

---

## 🎯 Expansion Ideas

The modular design supports easy expansion:

1. **Mining Module** - Follow woodcutting pattern for ore gathering
2. **Fishing Module** - Fish locations, water detection events
3. **Cooking/Smelting** - Recipes, resource conversion, crafting bench
4. **Hunting** - Animal tracking, reward XP for kills/pelts
5. **Farming** - Plant growth cycles, harvest mechanics
6. **Smithing** - Crafting system using gathered resources

Each can use the same `AddSkillXP` export to integrate with the core system.

---

## 🐛 Development Notes

- **Skill Formula**: `Level = floor(sqrt(XP / 1331)) + 1` → Exponential scaling
- **Tree Spawning**: Uses raycast detection from player shoulder (0.9m height)
- **Admin Checks**: Both woodcutting commands verify `user.getGroup == 'admin'`
- **Token System**: Chopping uses random tokens to prevent exploits
- **Auto-Cleanup**: Dead trees removed when forest is wiped

---

## 📝 Version History

**v1.0** (Initial Release)

- Atlas_skilling core system with 11 skills
- Atlas_woodcutting gathering module
- Forest generation and management
- XP and leveling system
- Skill menu UI

---

## 📧 Contact & Support

For issues, improvements, or integration questions, reference the exports and event system documented above. The modular design ensures compatibility with other VORP-based scripts.

---

_Last Updated: April 20, 2026_
