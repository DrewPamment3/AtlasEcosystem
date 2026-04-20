# Atlas Ecosystem - Previous Mistakes Reference

**DO NOT FALL INTO THESE TRAPS AGAIN**

## 1. Invalid RedM/VORP API Functions
**Mistake:** Using functions that don't exist in the RedM API
- ❌ `GetEntityForwardVector()` - doesn't exist
- ❌ `character.coords` - doesn't exist in VORP character object
- ❌ `VORPcore.NotifyTiny()` - doesn't exist in VORP API

**Correct Approach:**
- ✅ Calculate forward vector: `GetEntityHeading()` + `math.sin()/math.cos()` with `math.rad()`
- ✅ Get player coords: `GetPlayerPed(source)` → `GetEntityCoords(ped)`
- ✅ Notification API: `VORPcore.NotifyRightTip(source, message, duration)`

## 2. VORP Admin Group Storage
**Mistake:** Checking `user.group` for admin status
- ❌ `user.group` - doesn't reflect actual admin status (always "user")
- ❌ Database users table - not used by VORP

**Correct Approach:**
- ✅ Admin group stored in **character** object: `character.group`
- ✅ Database location: characters table, `group` column
- ✅ Correct check:
  ```lua
  local character = user.getUsedCharacter  -- Property, NOT method
  local charGroup = character and character.group or "user"
  if charGroup == 'admin' or charGroup == 'superadmin' then
  ```

## 3. Nil Object Checks
**Mistake:** Calling methods on objects without validating they exist
- ❌ Assuming `GetPlayerPed()` always returns valid ped
- ❌ Not checking if `user` or `character` objects exist before accessing properties

**Correct Approach:**
- ✅ Always validate before use:
  ```lua
  local ped = GetPlayerPed(source)
  if ped == 0 then return end  -- Invalid ped
  
  local user = VORPcore.getUser(source)
  if not user then return end
  
  local character = user.getUsedCharacter
  if not character then return end
  ```

## 4. VORP Character Access Pattern
**Mistake:** Treating `getUsedCharacter` as a method
- ❌ `user.getUsedCharacter()` - wrong, it's a property

**Correct Approach:**
- ✅ `user.getUsedCharacter` - access as property, no parentheses

## 5. Hard-Coded Configuration Values
**Mistake:** Embedding magic numbers in code
- ❌ `groundZ - 0.2` hard-coded Z offset
- ❌ Model names scattered throughout code
- ❌ Respawn times calculated in multiple places

**Correct Approach:**
- ✅ Move all tunable values to `shared/config.lua`
- ✅ Create helper functions like `GetTreeZOffset(modelName)`
- ✅ Reference via `Config.VariableName` or `AtlasWoodConfig.VariableName`

## 6. Game Coordinate System
**Mistake:** Confusing Z-axis positioning
- ❌ Not understanding that Z-offsets need to be **subtracted** from ground height to properly position objects at ground level

**Correct Approach:**
- ✅ `GetGroundZFor_3dCoord()` returns the Z position ON the ground
- ✅ Subtract offset to place object slightly below: `groundZ - zOffset`
- ✅ Use config table to store per-model offsets

## 7. Network Event Broadcasting
**Mistake:** Only sending events to subscribed players, missing new arrivals
- ❌ Only sending tree spawn to `ForestClients[forestId]` subscribers
- ❌ New players entering range don't get trees that were already created

**Correct Approach:**
- ✅ Broadcast new tree spawns to ALL clients: `TriggerClientEvent(..., -1, ...)`
- ✅ Send full state snapshot on player load: `loadForests` event with all tree states
- ✅ Clients filter based on distance/subscription internally

## 8. Client-Side State Management
**Mistake:** Not properly tracking rendered forest metadata
- ❌ Registry not storing forestId/treeIndex for proper lookups
- ❌ Can't distinguish between stumps and trees

**Correct Approach:**
- ✅ Store complete node info in registry:
  ```lua
  {
    forestId = forestId,
    treeIndex = treeIndex,
    coords = vec3(...),
    entity = entityHandle,
    isStump = booleanFlag
  }
  ```

## 9. Model Validation
**Mistake:** Not checking if model exists before attempting to load
- ❌ Directly calling `RequestModel()` on invalid model names
- ❌ No error feedback when model fails to load

**Correct Approach:**
- ✅ Validate with `IsModelValid(modelHash)` before requesting
- ✅ Check `HasModelLoaded()` with timeout
- ✅ Provide clear error messages to player

## 10. Transaction Timing Issues
**Mistake:** Assuming async callbacks complete instantly
- ❌ Creating forest, trees not showing until script restart
- ❌ Not accounting for database insert delays

**Correct Approach:**
- ✅ Use `ox_mysql` callbacks properly - code executes INSIDE the callback
- ✅ Don't assume data is available immediately after trigger
- ✅ Broadcast state changes AFTER database confirms success

## 11. Server-Side Commands with Client-Only Natives
**Mistake:** Using client-only game natives in server-side command handlers
- ❌ Server-side `/spawntree` using `GetGameTimer()`, `GetGroundZFor_3dCoord()`, `CreateObject()`
- ❌ These natives only exist on the **CLIENT**, not on the server
- ❌ Result: Script crashes with "attempt to call a nil value"

**Client-Only Natives (NEVER use in RegisterCommand on server):**
- `GetGameTimer()` - only client
- `GetGroundZFor_3dCoord()` - only client
- `CreateObject()` - only client
- `GetPlayerPed(source)` - server can use, but with restrictions
- `RequestModel()`, `HasModelLoaded()` - client only
- `GetHashKey()` - works on both, but usually implicit
- Entity creation/manipulation - mostly client

**Correct Approach:**
- ✅ Put debug/testing commands that need game natives on the **CLIENT-SIDE**
- ✅ Server-side `RegisterCommand` → only do server logic (DB, notifications, validation)
- ✅ If you need game interaction: use client command `RegisterCommand()` in client file
- ✅ Pattern for data needing server: Client triggers server event → server processes → broadcasts back to client

**Example Fix:**
```lua
-- WRONG: Server-side command
RegisterCommand('spawntree', function(source, args)
    local tree = CreateObject(...) -- ❌ CRASH: CreateObject doesn't exist on server
end)

-- RIGHT: Client-side command
RegisterCommand('spawntree', function(args)
    local tree = CreateObject(...) -- ✅ Works, client has this native
end)
```

---

## Quick Checklist Before Submitting Code
- [ ] Are you using valid RedM API functions? (Test in RedM docs)
- [ ] Did you check for nil before accessing properties?
- [ ] Is admin check using `character.group` not `user.group`?
- [ ] Are magic numbers in config, not hardcoded?
- [ ] Did you validate models with `IsModelValid()` before loading?
- [ ] Are events properly broadcasting (-1 for all, -source for others)?
- [ ] Did you account for async callback execution?
- [ ] Are client-only natives (CreateObject, GetGameTimer, etc) only in CLIENT files?
- [ ] Is your server-side RegisterCommand only doing server logic, not game manipulation?
