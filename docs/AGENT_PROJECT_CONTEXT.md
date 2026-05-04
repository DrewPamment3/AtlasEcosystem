# Atlas Ecosystem - Complete Agent Reference

> **Purpose:** This document provides AI coding agents all context needed to work on this project without hallucinations about RedM, VORP, or FiveM natives.

---

## 1. WHAT THIS PROJECT IS

**Atlas Ecosystem** is a modular RPG-style gathering/skilling framework for **RedM** (Red Dead Redemption 2 multiplayer using the VORP framework). It adds deep MMO-style gathering professions with tool validation, level requirements, and persistence.

**Current resources (4 modules):**
| Resource | Purpose | Status |
|---|---|---|
| `Atlas_skilling` | Core XP engine, database, skill menu (`/skills`) | Stable |
| `Atlas_woodcutting` | Tree chopping with axes, groves, animations | Stable (duplicate code issue) |
| `Atlas_mining` | Rock mining with pickaxes, camps, nodes | Stable (duplicate code issue) |
| `Atlas_blips` | Map markers for gathering locations | Placeholder |

**The core loop:** Player walks to gathering location → prompt appears → player holds G key → tool+level validated server-side → progress bar + animation plays → XP awarded → tool durability decreases.

---

## 2. CRITICAL: THIS IS REDM, NOT FIVEM

**RedM uses RDR2, not GTA V.** This is the #1 source of errors from agents.

### Natives
- RedM uses **RDR2 natives**, NOT GTA V natives. The native hash sets are DIFFERENT.
- Many GTA V natives DO NOT EXIST in RDR2 and vice versa.
- **NEVER assume a GTA V native works in RedM.** Always verify against [RDR2 native reference](https://vespura.com/fivem/dr-scratch/).
- Common traps:
  - `GetEntityCoords` works, but `GetEntityHeading` has different behavior
  - Particle effects: most GTA V particle dictionaries don't exist in RDR2
  - Animation dictionaries: RDR2 has its own set (e.g., `amb_work@world_human_tree_chop_new@working@pre_swing@male_a@trans`)
  - `TaskStartScenarioInPlace` takes a scenario name (string), not a native hash
  - RDR2 uses `0x923583741DC87BCE` (not GTA equivalents) for locomotion overrides

### RedM-Specific Restrictions
- `fx_version 'cerulean'`, `game 'rdr3'` in every fxmanifest
- `rdr3_warning` line is REQUIRED in fxmanifest
- `lua54 'yes'` — Official VORP resources (vorp_core, vorp_inventory, vorp_crafting) all use `lua54 'yes'`. The Atlas project currently has it COMMENTED OUT (`-- lua54 'yes'`) but should be enabled for compatibility with modern VORP.
- **Certain GTA V native categories are ABSENT**: vehicle natives, aircraft, etc.

### Audio/Particles in RedM
- `RequestAmbientAudioBank()` - RedM uses ambient audio banks, NOT GTA V sound sets
- Audio banks: `"HUD_GOLD_MINING_SOUNDSET"`, `"OFF_MISSION_SOUNDSET"` etc.
- Particle effects: `"scr_bike_rear_wheels"` is NOT available. Use RDR2 particles only.
- `PlaySoundFrontend("SELECT", "HUD_SHOP_SOUNDSET", ...)` - this specific call MAY work but is a GTA V soundset

---

## 3. VORP FRAMEWORK SPECIFICS

VORP (Vice Online Roleplay) is THE framework for RedM. It's NOT ESX or QBCore (those are FiveM).

### Core API (CRITICAL - DO NOT HALLUCINATE)

```lua
-- Get the core (THIS IS CORRECT):
local VORPcore = exports.vorp_core:GetCore()

-- Get a user object (THIS IS CORRECT):
local User = VORPcore.getUser(source)  -- NOT VORPcore.getUser(source) (no capital U)

-- Get character data (THIS IS CORRECT):
local Character = User.getUsedCharacter  -- It's a TABLE, not a function
local charidentifier = Character.charIdentifier  -- Note exact casing

-- NOT these (common hallucinations):
-- VORPcore.getUser(source).getUsedCharacter()  -- WRONG: getUsedCharacter is not a function
-- VORPcore.Functions.GetPlayer(source)  -- WRONG: This is QBCore syntax
-- exports.vorp_core:GetPlayer(source)  -- WRONG: Not how VORP works
```

### VORP Inventory
```lua
-- Get an item (returns TABLE with count, metadata, slot, id):
local item = exports.vorp_inventory:getItem(source, itemName)
-- item can be:
--   { count = 1, metadata = { durability = 85 }, slot = 1, id = 123 }
--   OR { [1] = { count = 1, ... }, [2] = { count = 1, ... } } (array)

-- Add item:
exports.vorp_inventory:addItem(source, itemName, quantity, metadata)

-- Remove item (subItem, NOT removeItem):
exports.vorp_inventory:subItem(source, itemName, quantity, metadata)
```

### VORP Menu
```lua
local VORPMenu = exports.vorp_menu:GetMenuData()

VORPMenu.Open('default', GetCurrentResourceName(), 'menu_id', {
    title = 'Menu Title',
    align = 'top-right',
    elements = {
        { label = "Option", value = {}, desc = "Description" }
    }
}, function(data, menu) menu.close() end, function(data, menu) menu.close() end)

VORPMenu.CloseAll()
```

### VORP Notifications
```lua
-- Correct notification methods:
VORPcore.NotifyTop(title, message, duration)     -- Top notification
VORPcore.NotifyCenter(message, duration)          -- Center notification
VORPcore.NotifyRightTip(source, message, duration) -- Server-side right tip
```

### VORP Events
```lua
-- Character selection (SERVER-SIDE):
RegisterNetEvent('vorp:SelectedCharacter')
AddEventHandler('vorp:SelectedCharacter', function(source, character)
    local charidentifier = character.charIdentifier
end)

-- Character selection (CLIENT-SIDE):
-- There is NO reliable client-side character selected event in all VORP versions.
-- Pattern: Use server event and TriggerClientEvent back to client.
```

---

## 4. RESOURCE ARCHITECTURE

### Standard Structure
```
Atlas_<name>/
├── fxmanifest.lua     # Resource manifest
├── shared/
│   └── config.lua     # Shared configuration (read by both client AND server)
├── client/
│   └── main.lua       # Client-side code (visuals, prompts, UI, animations)
└── server/
    └── main.lua       # Server-side code (validation, database, rewards)
```

### fxmanifest.lua Pattern
```lua
fx_version 'cerulean'
game 'rdr3'
rdr3_warning 'I acknowledge that this is a prerelease build of RedM, and I am aware my resources *will* become incompatible once RedM ships.'

author 'DrewPamment3'
description 'Atlas <Name> - <Brief>'
version '1.0'

shared_scripts { 'shared/config.lua' }
client_scripts { 'client/main.lua' }
server_scripts { 'server/main.lua' }

dependencies {
    'vorp_core',
    'vorp_inventory',
    'oxmysql',
    'Atlas_skilling'
}
```

**Important:** `Atlas_skilling` MUST be in dependencies of every module that uses `AddSkillXP` or `GetSkillLevelSync`.

### Client/Server/Shared Separation
- **Shared config** (`shared/config.lua`): Constants, item definitions, grove/camp coordinates. Available to BOTH sides.
- **Client** (`client/main.lua`): Render prompts, animations, progress bars, visual effects. NO database access.
- **Server** (`server/main.lua`): Tool validation, XP awarding, database operations, item manipulation. Has `source` parameter.

---

## 5. RESOURCE INTERDEPENDENCIES

```
Atlas_skilling (CORE - must start first)
    ├── Provides: AddSkillXP(), GetSkillLevelSync(), /skills command
    ├── Database: character_skills table (via oxmysql)
    └── No dependencies (except vorp_core, oxmysql)

Atlas_woodcutting
    ├── Depends on: Atlas_skilling (for AddSkillXP, GetSkillLevelSync)
    ├── Uses: vorp_inventory (for axe tools)
    └── Global exports: ValidateWoodcuttingTools, HandleAxeDurability

Atlas_mining
    ├── Depends on: Atlas_skilling (for AddSkillXP, GetSkillLevelSync)
    ├── Uses: vorp_inventory (for pickaxe tools)
    └── Global exports: ValidateMiningTools (embedded in main.lua)

Atlas_blips
    └── Depends on: Atlas_woodcutting, Atlas_mining (reads their configs)
```

### The Skill XP Bridge
- **Server-side:** `AddSkillXP(source, skillName, amount, personalMultiplier)` - global function from `Atlas_skilling`
- **Server-side sync:** `exports['Atlas_skilling']:GetSkillLevelSync(source, skillName)` - returns skill LEVEL (number)
- **Database table:** `character_skills` with columns like `woodcutting_xp`, `mining_xp`, `smelting_xp`, etc.

---

## 6. CODE PATTERNS USED IN THIS PROJECT

### Tool Validation Pattern
Every gathering module follows this exact flow:
1. Player triggers prompt (client → server event)
2. Server calls validation function:
   - Check debug mode bypass
   - Check level requirements (using `GetSkillLevelSync`)
   - Check inventory for tool (using `getItem`)
   - Find best tool by tier
   - Check durability
   - Return structured result
3. If valid → start task, play animation, run progress
4. On completion → award XP, reduce durability, give loot

### Structured Validation Result
```lua
{
    hasValidTool = boolean,
    bestTool = { name = string, tier = number, durability = number, power = number },
    levelValid = boolean,
    requiredLevel = number or nil,
    errorMessage = string or nil,
    willBreak = boolean
}
```

### Prompt Rendering (Client-Side)
```lua
-- VORP-style prompts:
local str = "MINE ROCK"
local group = VORPcore.Prompts():GetGroup("atlas_mining")
local prompt = group:RegisterPrompt(str, 0x760A9C6F, 1, 1, true, 'hold', timedevent)
-- 0x760A9C6F = G key
-- 'hold' = must hold the key, timed event
```

### Database Pattern (oxmysql)
```lua
-- SELECT with callback:
exports.oxmysql:execute('SELECT * FROM table WHERE id = ?', { id }, function(result)
    if result and result[1] then -- result is always an array
        -- use result[1]
    end
end)

-- Sync scalar (returns single value):
exports.oxmysql:scalar('SELECT xp FROM character_skills WHERE charidentifier = ?', { id }, function(value)
    -- value is the single result
end)
```

---

## 7. KNOWN ISSUES & PITFALLS

### 🔴 CRITICAL: Code Duplication in Woodcutting & Mining
**Both `Atlas_woodcutting/server/main.lua` and `Atlas_woodcutting/server/tool_validation.lua` contain IDENTICAL functions:**
- `GetPlayerAxes()`
- `GetBestAxe()`
- `CheckLevelRequirement()`
- `ValidateWoodcuttingTools()`
- `HandleAxeDurability()`
- `GetWoodcuttingPromptText()`

The function definitions in `main.lua` SHADOW those in `tool_validation.lua` (if both are loaded). This means if you fix a bug in one, the other still has it. **The fix:** Delete the duplicated code from `main.lua` and `require` or just rely on `tool_validation.lua` loading first.

### 🔴 CRITICAL: Mining has the same duplication pattern
`Atlas_mining/server/main.lua` has `GetPlayerPickaxes()`, `GetBestPickaxe()`, `CheckLevelRequirement()`, `ValidateMiningTools()` embedded, while there's no separate `tool_validation.lua` for mining yet. The validation functions should be extracted to their own file.

### 🟡 Potential Issues
- **Client-side playerLoaded event:** Relying on `playerLoaded` trigger with a 5-second wait is fragile. Not all VORP versions fire consistent client-side character events.
- **Audio bank loading:** `Citizen.Wait(3000)` is a crude delay. The proper pattern polls for bank load status.
- **Config reference pattern:** `local Config = AtlasWoodConfig` in server code works but is fragile if the shared config rename is missed.
- **Global function registration:** Functions registered on `_G` can collide with other resources.

### 🟡 RedM Compatibility Notes
- `RemoveAmbientAudioBank` - may not exist in all RedM builds (safety-wrap with `pcall`)
- `RequestAmbientAudioBank` - must be called, then WAIT for load
- `ClearPedDesiredLocoForModel` and `ClearPedDesiredLocoMotionType` may not exist in early RedM builds
- Scenario names are CASE SENSITIVE and must match EXACTLY

### 🔴 RDR2 Blip API (CORRECT VALUES)

RedM uses **RDR2 blip natives** with a completely different creation pattern than GTA V:

```lua
-- ⬅ CRITICAL: RDR2 blips are created in TWO STEPS:
-- Step 1: Create a blip with a STYLE hash (NOT a sprite/icon hash)
local blip = Citizen.InvokeNative(0x554D9D53F696D002, styleHash, x, y, z)
-- Step 2: Apply the sprite icon AFTER creation
Citizen.InvokeNative(0x74F74D3207ED525C, blip, spriteHash, true)

-- OR for radius blips (zone circles), use the dedicated native:
local radiusBlip = Citizen.InvokeNative(0x45F13B7E0A15C880, hash, x, y, z, radius)

-- Blip name uses raw string (NOT CreateVarString):
Citizen.InvokeNative(0x9CB1A1623062F402, blip, "Zone Name")

-- Palette indices (NOT hex ARGB!):
-- 1=Red, 2=Green, 3=Blue, 5=Yellow, 6=Orange
-- 8=Grey, 11=DarkGrey, 25=Brown, 27=LightBrown
Citizen.InvokeNative(0x03D7FB09E75D6B7E, blip, 8)  -- SetBlipColour
```

**DO NOT:**
- Pass a sprite hash directly to `BlipAddForCoords` — it takes a STYLE hash first
- Skip `SetBlipSprite()` — the style-created blip has no icon until you set one
- Use `CreateBlip()` or `AddBlipForCoord()` — these are GTA V Lua wrappers that don't exist in RedM
- Use `CreateVarString` for blip names — `SetBlipNameFromPlayerString` takes a raw Lua string
- Use GTA V native hashes for `SetBlipSprite` — RDR2 uses `0x74F74D3207ED525C` (NOT `0x74F74D3207AD5EE5`)
- Remove blips with `0x86A652570E5F25DD` — RDR2 uses `0xDEEDE7C41742E011` (AbandonBlip)

---

## 8. DEBUGGING & LOGGING

### Console Log Format
```lua
print("^2[Atlas Woodcutting]^7 Message here")
-- ^2 = green, ^3 = yellow, ^1 = red, ^5 = cyan, ^6 = purple, ^7 = white
```

### Debug Mode
Every config has `Config.DebugLogging` (boolean). When enabled:
- Level requirements are bypassed
- Tool requirements are bypassed
- Durability is not consumed
- Extra logging is printed

### Testing Commands
```
/skills          - Open skill menu (from Atlas_skilling)
/testchopanimation [ms]  - Test woodcutting animation
/testscenario [name] [ms] - Test a specific scenario
/listscenarios   - List available animation scenarios
/animationstatus - Show current animation config
```

---

## 9. FILE INDEX

```
f:\Code Projects\AtlasEcosystem\
├── docs/
│   └── AGENT_PROJECT_CONTEXT.md    ← YOU ARE HERE
├── Atlas_skilling/                  ← CORE MODULE (must start first)
│   ├── fxmanifest.lua
│   ├── shared/config.lua            ← XP formula, global multiplier, max level
│   ├── server/main.lua              ← AddSkillXP(), database, skill fetching
│   └── client/main.lua              ← /skills command, menu rendering, notifications
├── Atlas_woodcutting/               ← TREE CHOPPING MODULE
│   ├── fxmanifest.lua
│   ├── shared/config.lua            ← AtlasWoodConfig: axes, groves, loot tables
│   ├── server/main.lua              ← Forest/grove management, task handling, validation
│   ├── server/tool_validation.lua   ← ⚠️ DUPLICATED validation functions
│   ├── client/main.lua              ← Prompt rendering, animation, progress bar
│   ├── ANIMATION_SYSTEM.md          ← Animation documentation
│   └── VORP_ANIMATION_INTEGRATION.md ← VORP lumberjack port documentation
├── Atlas_mining/                    ← ROCK MINING MODULE
│   ├── fxmanifest.lua
│   ├── shared/config.lua            ← AtlasMiningConfig: pickaxes, camps, loot tables
│   ├── server/main.lua              ← ⚠️ HAS EMBEDDED DUPLICATE validation functions
│   └── client/main.lua              ← Prompt rendering, animation, mining audio
└── Atlas_blips/                     ← MAP MARKERS MODULE
    ├── fxmanifest.lua
    ├── shared/config.lua
    ├── server/main.lua
    └── client/main.lua            ← Blip creation/management
```

---

## 10. WHEN ADDING NEW FEATURES

### Checklist for Agents
1. ✅ Is this RedM (RDR2) or FiveM (GTA V)? Check all natives, particle effects, animations.
2. ✅ Does it follow the existing resource structure pattern (shared/client/server)?
3. ✅ Is `Atlas_skilling` in `dependencies` in fxmanifest?
4. ✅ Does it use the established tool validation pattern?
5. ✅ Are VORP API calls correct (getUser, getUsedCharacter, NotifyTop, etc.)?
6. ✅ Are oxmysql calls using the correct pattern (execute with placeholders)?
7. ✅ Does `Config.DebugLogging` hook into the bypass logic?
8. ✅ Is the config in the correct file (server-only config goes in server, shared config in shared/)?

### What NOT To Do
- ❌ Do not use FiveM/QBCore/ESX patterns (e.g., `QBCore.Functions.GetPlayer`)
- ❌ Do not use GTA V natives without verifying they exist in RDR2
- ❌ Do not add new particle effects without testing RDR2 compatibility
- ❌ Do not modify the database schema without creating a migration note
- ❌ Do not remove `rdr3_warning` from fxmanifest
- ❌ Do not use `lua54 'yes'` in fxmanifest (RedM uses 5.3)
- ❌ Do not call `getUsedCharacter()` as a function (it's a table property)
