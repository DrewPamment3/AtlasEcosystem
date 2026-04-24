# Atlas Ecosystem - Troubleshooting Guide

## Issues Fixed in This Session

### 1. ❌ `scalar_await` Export Error - FIXED ✅

**Error Message:**
```
SCRIPT ERROR: @Atlas_skilling/server/main.lua:133: No such export scalar_await in resource oxmysql
```

**Problem:** The `scalar_await` function doesn't exist in oxmysql. Only `scalar` (with callback) and `scalar_sync` are available.

**Fix Applied:**
- Modified `GetSkillLevel` function to use `scalar` with callback for async operations
- Added new `GetSkillLevelSync` function using `scalar_sync` for synchronous needs
- Updated Atlas_woodcutting to use `GetSkillLevelSync` export

### 2. ❌ Missing Database Items Error - FIXED ✅

**Error Messages:**
```
[getItem7] Item [crude_axe] does not exist in DB.
[getItem7] Item [fine_axe] does not exist in DB.
[getItem7] Item [legendary_axe] does not exist in DB.
[getItem7] Item [superior_axe] does not exist in DB.
[getItem7] Item [great_axe] does not exist in DB.
```

**Problem:** Axe and wood items were not added to the VORP inventory database.

**Fix Applied:**
- Created `database_setup.sql` with all required items and tables
- Includes both axe items and wood items
- Includes proper VORP inventory item configuration

### 3. ❌ GetSkillLevel Export Returning Nil - FIXED ✅

**Error Message:**
```
[Atlas Woodcutting] Error getting player level for loot:
 An error occurred while calling export `GetSkillLevel` in resource `Atlas_skilling`:
   nil
```

**Problem:** The async `GetSkillLevel` was being called synchronously, causing nil returns.

**Fix Applied:**
- Atlas_woodcutting now uses `GetSkillLevelSync` for immediate level checks
- Original `GetSkillLevel` kept for backward compatibility with callback pattern

### 4. ❌ Trees Not Spawning When Forests Created - FIXED ✅

**Problem:** When admins created forests:
- Players got subscribed to forests correctly 
- But trees wouldn't spawn until reconnect
- 15-second subscription updates didn't trigger tree spawning for new forests

**Root Cause:**
1. `updateSubscriptions` only managed subscription lists but didn't trigger tree spawning for newly discovered forests
2. When admins created forests, existing players weren't immediately notified
3. Players had to wait for subscription update AND reconnect to see trees

**Fix Applied:**
1. **Enhanced updateSubscriptions**: Now detects when new forests are discovered and triggers `loadForests`
2. **Immediate notification**: When forests are created, all nearby players are instantly notified and get trees
3. **Added NotifyPlayersOfNewForest function**: Checks all players within range and forces subscription updates

---

## Required Setup Steps

### Step 1: Database Setup
Run the provided SQL script to create tables and items:

```sql
-- Execute database_setup.sql in your MySQL database
-- This creates:
-- - character_skills table
-- - atlas_woodcutting_forests table  
-- - atlas_woodcutting_nodes table
-- - All axe items (crude_axe, fine_axe, etc.)
-- - All wood items (wood_crude, wood_common, etc.)
```

### Step 2: Server Configuration
Ensure proper resource loading order in `server.cfg`:

```cfg
ensure vorp_core
ensure vorp_inventory
ensure vorp_menu
ensure oxmysql
ensure Atlas_skilling        # Must load BEFORE Atlas_woodcutting
ensure Atlas_woodcutting
```

### Step 3: Verification
Test the fixes:

1. **Skills System:**
   ```
   /skills - Should show skill menu without errors
   ```

2. **Admin Commands:**
   ```
   /givexp [id] [skill] [amount] - Should work without scalar_await error
   ```

3. **Forest Creation & Tree Spawning:**
   ```
   /createforest 20 10 1 p_tree_pine01x "Test Forest"
   # Should create forest, notify nearby players, and spawn trees immediately
   ```

4. **Inventory:**
   ```
   # Give yourself an axe to test:
   /give [your_id] crude_axe 1
   # Should work without "Item does not exist in DB" error
   ```

---

## Function Changes Made

### Atlas_skilling/server/main.lua

#### Before (Broken):
```lua
function GetSkillLevel(source, skill)
    -- ...
    local currentXP = exports.oxmysql:scalar_await(  -- ❌ scalar_await doesn't exist
        'SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?', 
        { charidentifier })
    -- ...
    return level  -- ❌ Returns immediately but uses async DB call
end
```

#### After (Fixed):
```lua
-- Async version with callback
function GetSkillLevel(source, skill, callback)
    -- ...
    exports.oxmysql:scalar('SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?', 
        { charidentifier }, function(currentXP)
            local level = 1
            if currentXP then
                level = math.floor(math.sqrt(currentXP / Config.XPFormulaDivisor)) + 1
            end
            if callback then callback(level) end
        end)
    return 1  -- Default return for backward compatibility
end

-- Synchronous version for immediate needs
function GetSkillLevelSync(source, skill)
    -- ...
    local success, currentXP = pcall(function()
        return exports.oxmysql:scalar_sync('SELECT ' .. skillColumn .. ' FROM character_skills WHERE charidentifier = ?', 
            { charidentifier })
    end)
    -- ...
    return level  -- ✅ Returns immediately with actual result
end
```

### Atlas_woodcutting/server/main.lua

#### Before (Broken):
```lua
local success, playerLevel = pcall(function()
    return exports['Atlas_skilling']:GetSkillLevel(source, 'woodcutting')  -- ❌ Async call used synchronously
end)
```

#### After (Fixed):
```lua
local success, playerLevel = pcall(function()
    return exports['Atlas_skilling']:GetSkillLevelSync(source, 'woodcutting')  -- ✅ Synchronous call
end)
```

#### Tree Spawning Fix:
```lua
-- NEW: Enhanced updateSubscriptions with new forest detection
RegisterServerEvent('atlas_woodcutting:server:updateSubscriptions')
AddEventHandler('atlas_woodcutting:server:updateSubscriptions', function()
    -- ... existing code ...
    
    -- Track current subscriptions BEFORE update
    local currentSubscriptions = {}
    for forestId, clients in pairs(ForestClients) do
        if clients[_source] then
            currentSubscriptions[forestId] = true
        end
    end
    
    local closestForests = SubscribePlayerToForests(_source, playerCoords)
    
    -- Check if any NEW forests were discovered
    local newForests = {}
    for _, forest in ipairs(closestForests) do
        if not currentSubscriptions[forest.id] then
            table.insert(newForests, forest)
        end
    end
    
    -- If new forests discovered, send full forest data
    if #newForests > 0 then
        TriggerClientEvent('atlas_woodcutting:client:loadForests', _source, closestForests, GlobalNodes, ForestTreeStates)
    end
end)

-- NEW: Immediate notification when forests are created
local function NotifyPlayersOfNewForest(forestId, forestCoords, radius, tier, name)
    local players = GetPlayers()
    for _, playerId in ipairs(players) do
        local playerSource = tonumber(playerId)
        if playerSource then
            -- Check if player is within range
            local distance = GetDistance(playerCoords, forestCoords)
            if distance <= Config.RenderDistance then
                -- Force immediate subscription update and tree loading
                local closestForests = SubscribePlayerToForests(playerSource, playerCoords)
                TriggerClientEvent('atlas_woodcutting:client:loadForests', playerSource, closestForests, GlobalNodes, ForestTreeStates)
                VORPcore.NotifyRightTip(playerSource, "~b~New forest discovered: " .. name, 3000)
            end
        end
    end
end
```

---

## Common Issues & Solutions

### Issue: "scalar_sync is not a function"
**Solution:** Update your oxmysql resource to the latest version that supports `scalar_sync`.

### Issue: Items still don't exist after running SQL
**Solution:** 
1. Check your VORP inventory table name - it might be `vorp_items` instead of `items`
2. Modify the SQL script to use the correct table name
3. Restart the vorp_inventory resource: `restart vorp_inventory`

### Issue: "GetSkillLevelSync is not exported"
**Solution:** 
1. Restart Atlas_skilling resource: `restart Atlas_skilling`
2. Check that the fxmanifest.lua includes the new export
3. Ensure Atlas_skilling loads before Atlas_woodcutting

### Issue: Trees still not spawning when forests are created
**Solution:**
1. Check if players are within Config.RenderDistance (400m default) of the new forest
2. Verify debug logging shows "New forest discovered" messages
3. Test by disconnecting/reconnecting - if trees appear then, the notification system needs debugging

### Issue: Admin commands don't work
**Solution:**
1. Set your character group to admin:
   ```sql
   UPDATE characters SET `group` = 'admin' WHERE charidentifier = YOUR_CHAR_ID;
   ```
2. Remember: VORP uses `character.group`, not `user.group`

---

## Testing Checklist

- [ ] No `scalar_await` errors in console
- [ ] `/skills` command works
- [ ] `/givexp` command works for admins
- [ ] Axe items can be given via `/give` command
- [ ] Wood items can be given via `/give` command
- [ ] `/createforest` works without GetSkillLevel errors
- [ ] **NEW:** Trees spawn immediately when forests are created (no reconnect needed)
- [ ] **NEW:** Players within 400m get "New forest discovered" notification
- [ ] Chopping trees awards XP without errors
- [ ] Loot system works and gives appropriate wood types

---

## Performance Notes

- `GetSkillLevelSync` should only be used when you need immediate results
- For non-critical operations, use the async `GetSkillLevel` with callback
- The sync version uses blocking database calls, so use sparingly
- The new forest notification system checks all players when forests are created - consider optimizing for high-player-count servers

---

## Emergency Rollback

If issues persist, you can temporarily disable the new notification system by commenting out the NotifyPlayersOfNewForest call in the createforest command:

```lua
-- Temporary disable
-- NotifyPlayersOfNewForest(fId, pCoords, radius, tier, name)
```

This will revert to the old behavior where players need to wait for subscription updates or reconnect to see new forests.
