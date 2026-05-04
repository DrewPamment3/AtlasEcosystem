# How to Prompt AI Agents for Atlas Ecosystem

> **Purpose:** This guide teaches you how to write prompts that make AI agents productive (not destructive) when working on this niche RedM/VORP project.

---

## The Golden Rule

**Always tell the agent "THIS IS REDM" in every prompt.** Agents default to assuming FiveM/GTA V. If you don't explicitly state the platform, they WILL hallucinate wrong natives, wrong framework APIs, and wrong patterns.

---

## PROMPT TEMPLATE (Copy & Fill In)

```
I'm working on [RESOURCE NAME] in the Atlas Ecosystem (RedM VORP framework).

The file I need changed is: [FULL PATH]

Context:
- This is RedM (RDR2), NOT FiveM (GTA V)
- Framework is VORP, NOT ESX or QBCore
- Reference docs are in /docs/AGENT_PROJECT_CONTEXT.md before coding

[DESCRIBE WHAT YOU WANT]

Before making changes:
1. Check docs/AGENT_PROJECT_CONTEXT.md for correct API patterns
2. Verify any natives exist in RDR2
3. Follow existing code patterns in the project
```

---

## PROMPT EXAMPLES

### ✅ GOOD PROMPT: "Add a new fishing module"

```
I want to add a new "Atlas_fishing" resource to the Atlas Ecosystem (RedM VORP).

This is RedM, NOT FiveM. Framework is VORP.

Please:
1. Study the existing Atlas_woodcutting and Atlas_mining modules as templates
2. Follow the EXACT same structure: shared/config.lua, server/main.lua, client/main.lua
3. Use VORP API patterns from docs/AGENT_PROJECT_CONTEXT.md
4. Add fishing rod definitions in config (like the Axes/Pickaxes tables)
5. Create a /fish command that opens a menu to select fishing spots
6. Wire up Atlas_skilling dependency for AddSkillXP

Reference files:
- docs/AGENT_PROJECT_CONTEXT.md (framework API, patterns)
- Atlas_woodcutting/shared/config.lua (config structure)
- Atlas_woodcutting/server/main.lua (server pattern)
```

### ✅ GOOD PROMPT: "Fix a bug in woodcutting"

```
BUG: Tree chopping doesn't award XP on my RedM VORP server.

This is RedM. Framework is VORP.

The relevant file is Atlas_woodcutting/server/main.lua

Please:
1. Read docs/AGENT_PROJECT_CONTEXT.md section 3 (VORP API) first
2. Read the current Atlas_woodcutting/server/main.lua
3. Check if AddSkillXP is being called correctly (VORPcore.getUser, User.getUsedCharacter pattern)
4. Check that the event flow is correct (client → server → validation → XP)
5. Add debug logging with ^3[DEBUG]^7 prefix so I can see what's happening

Note: There is code duplication between main.lua and tool_validation.lua - fix in BOTH files.
```

### ✅ GOOD PROMPT: "Add a new axe tier"

```
I want to add a "Legendary Axe" tier (tier 6) to Atlas_woodcutting.

This is RedM VORP. Reference docs/AGENT_PROJECT_CONTEXT.md.

Steps:
1. Add the axe definition to Atlas_woodcutting/shared/config.lua (follow existing pattern)
2. Create the item in vorp_inventory database if needed (tell me the SQL)
3. Set level requirement to 80 in GroveUnlocks
4. Give it power=4.0 (above tier 5)

Important: tier 5 is the current max, so check if any tier-gated logic needs updating.
```

### ❌ BAD PROMPT: "Fix my woodcutting"

```
my woodcutting doesnt work, plz fix it
```
**Why bad:** No platform info, no framework info, no file paths, no specific symptoms.

### ❌ BAD PROMPT: "Add ESX job integration"

```
add esx job checks to the mining script so only miners can mine
```
**Why bad:** ESX is FiveM-only. RedM uses VORP. Agent will write entirely wrong code.

---

## WHEN TO REFERENCE WHICH DOCUMENT

| You want to... | Tell the agent to read... |
|---|---|
| Add a new gathering module | `docs/AGENT_PROJECT_CONTEXT.md` sections 1-6 |
| Fix a VORP API call | `docs/AGENT_PROJECT_CONTEXT.md` section 3 (VORP Framework Specifics) |
| Add animations | `Atlas_woodcutting/ANIMATION_SYSTEM.md` |
| Change how XP is calculated | `Atlas_skilling/shared/config.lua` (XP formula) |
| Add new items/tools | The module's `shared/config.lua` + `docs/AGENT_PROJECT_CONTEXT.md` section 3 (inventory) |
| Understand resource structure | `docs/AGENT_PROJECT_CONTEXT.md` section 4 (Resource Architecture) |
| Check for known bugs | `docs/AGENT_PROJECT_CONTEXT.md` section 7 (Known Issues) |
| Fix code duplication | `docs/AGENT_PROJECT_CONTEXT.md` section 7 + `previous_mistakes.md` |
| Debug RedM natives | RDR2 native reference: https://vespura.com/fivem/dr-scratch/ |
| Understand module interactions | `docs/AGENT_PROJECT_CONTEXT.md` section 5 (Interdependencies) |

---

## HOW TO VERIFY AGENT OUTPUT

### 🔴 Immediate Red Flags (STOP - agent is wrong)
- Agent uses `ESX`, `QBCore`, `QBCore.Functions` - wrong framework
- Agent uses GTA V coordinates (Los Santos) instead of RDR2 (New Austin, etc.)
- Agent adds `'es_extended'` or `'qb-core'` to dependencies
- Agent uses `GetPlayerFromId()` instead of VORPcore.getUser()
- Agent uses `TriggerClientEvent('QBCore:Notify', ...)` - wrong notification system
- Agent references vehicle natives or aircraft - RedM has horses, not cars

### 🟡 Warning Signs (verify carefully)
- Agent adds new particle effects - many GTA V particles don't exist in RDR2
- Agent adds new sound sets - test them on your server
- Agent changes the database schema - back up first
- Agent references GTA V map locations - RDR2 map is entirely different
- Agent uses `Citizen.Wait(0)` in a loop - can freeze RedM

### ✅ Good Signs
- Agent reads `docs/AGENT_PROJECT_CONTEXT.md` before coding
- Agent checks existing code patterns in the project
- Agent uses `^2[Module Name]^7` logging format
- Agent adds `Config.DebugLogging` gates for debug code
- Agent follows the existing resource structure (shared/client/server)
- Agent wraps new native calls in `pcall()` for safety

---

## COMMON TASKS & HOW TO PROMPT THEM

### "I need a new gathering skill" (e.g., herbalism, hunting)
```
Create a new Atlas_herbalism resource based on Atlas_woodcutting's structure.
Use THIS TEMPLATE:
- Copy Atlas_woodcutting/shared/config.lua pattern → Atlas_herbalism/shared/config.lua
- Replace "Axes" with "Sickles", "Forests" with "HerbFields"
- Keep the tool_validation.lua pattern
- Keep the client prompt/animation pattern
- Change the skill name to "herbalism" in all AddSkillXP calls
Read docs/AGENT_PROJECT_CONTEXT.md first.
```

### "My [resource] server crashes on startup"
```
Debug crash in Atlas_[resource]/server/main.lua on RedM VORP.

Read docs/AGENT_PROJECT_CONTEXT.md section 7 (Known Issues).
Check for:
1. Code duplication issues (section 7 CRITICAL)
2. Config reference mismatches
3. Missing nil checks on VORPcore.getUser() returns
4. Missing pcall() wrappers on native calls
Add protective nil checks and print debug logs.
```

### "Add a config option for [feature]"
```
Add a config option for [FEATURE] to Atlas_[resource]/shared/config.lua.

This is RedM VORP. Follow existing config patterns:
1. Add the option to the config table
2. Add a comment explaining the option
3. Wire it up in both server/main.lua AND client/main.lua
4. Gate it behind Config.DebugLogging for debug features
```

---

## THE SCRATCH FILE SYSTEM

After each agent session, quickly note what worked and what didn't in `previous_mistakes.md`. This FILE IS READ BY EVERY AGENT. Keep it updated.

**Current contents of previous_mistakes.md that agents should know:**
- Never use `getUsedCharacter()` as a function call (it's a property)
- Never use FiveM/QBCore syntax
- Never remove debug logging
- Always handle `vorp_inventory:getItem` returning arrays vs single items
- Always add nil guards to event handlers
- Never assume GTA V particles work in RedM
- Test on RedM SERVER build, not client-only

---

## QUICK REFERENCE: Framework APIs

```
# VORP Core
local VORPcore = exports.vorp_core:GetCore()
local User = VORPcore.getUser(source)
local char = User.getUsedCharacter  -- PROPERTY, not function
local cid = char.charIdentifier

# VORP Inventory
exports.vorp_inventory:getItem(source, name)     -- returns table
exports.vorp_inventory:addItem(source, name, qty, metadata)
exports.vorp_inventory:subItem(source, name, qty, metadata)

# VORP Notifications
VORPcore.NotifyTop(title, msg, duration)
VORPcore.NotifyCenter(msg, duration)
VORPcore.NotifyRightTip(source, msg, duration)

# Atlas Skilling
AddSkillXP(source, skillName, amount, multiplier)     -- global function
exports['Atlas_skilling']:GetSkillLevelSync(source, skillName)  -- returns level

# RedM Natives Check
https://vespura.com/fivem/dr-scratch/  -- Select RDR3 tab
```
