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

## 12. RegisterCommand Signature CORRECTION - DEPRECATED

**IMPORTANT:** Mistake #12 was WRONG. The solution was incorrect. See #13 for correct pattern.

---

## 13. RegisterCommand Args Format - CORRECT PATTERN

**Mistake:** Using wrong signature or trying to parse args as string

- ❌ Client command: `function(args)` - WRONG, should be `function(source, args, rawCommand)`
- ❌ Parsing args as string with `string.gmatch()` - WRONG, args is already a TABLE
- ❌ Thinking server and client have different arg formats - WRONG, both receive tables

**Correct Approach:**

- ✅ **Both server and client** use SAME signature:
  ```lua
  RegisterCommand('command', function(source, args, rawCommand)
      -- source: player ID on server, 0 on client
      -- args: TABLE {arg1, arg2, ...} (same on both!)
      -- rawCommand: full command string
  end)
  ```
- ✅ Use args directly as table:
  ```lua
  local modelName = args[1]      -- NOT arguments[1]
  local zOffset = args[2]        -- Direct access, no parsing needed
  ```
- ✅ The ONLY difference between server and client is `source`:
  - Server: `source` = actual player ID
  - Client: `source` = 0 (always)

**Key Lesson:**

- RegisterCommand signature is IDENTICAL on server and client
- `args` is a TABLE in both, NOT a string
- Never try to parse with `string.gmatch()` - it's already structured!
- The distinction between server/client is about WHAT you do, not HOW the args arrive

---

---

## 14. OxMySQL Export Names - CRITICAL ERROR PATTERN

**Mistake:** Using non-existent oxmysql export functions

- ❌ `exports.oxmysql:scalar_await()` - **DOES NOT EXIST** (causes script crash)
- ❌ Assuming all oxmysql versions have same exports

**Correct Approach:**

- ✅ Use `exports.oxmysql:scalar()` with callback for async:
  ```lua
  exports.oxmysql:scalar('SELECT ...', {params}, function(result)
      -- Handle result in callback
  end)
  ```
- ✅ Use `exports.oxmysql:scalar_sync()` for synchronous (when available):
  ```lua
  local success, result = pcall(function()
      return exports.oxmysql:scalar_sync('SELECT ...', {params})
  end)
  ```
- ✅ Always wrap database calls in pcall() to handle version differences
- ⚠️ **This error causes complete script failure** - test thoroughly

---

## 15. Animation Systems in RedM vs GTA V

**Mistake:** Assuming GTA V animations work in RedM

- ❌ `WORLD_HUMAN_TREE_CHOP_RAYFIRE` may not exist in RedM
- ❌ Many complex GTA V scenarios are not available
- ❌ Animations fail silently - no error messages

**Correct Approach:**

- ✅ Use basic, proven scenarios: `WORLD_HUMAN_TREE_CHOP`
- ✅ Always have fallback scenarios:
  ```lua
  if not IsPedUsingScenario(ped, "ADVANCED_SCENARIO") then
      TaskStartScenarioInPlace(ped, "BASIC_SCENARIO", -1, true)
  end
  ```
- ✅ Test all animations thoroughly on actual RedM server
- ⚠️ Scenarios failing can break entire interaction flow

---

## 16. Progress Bar Rendering Order Issues

**Mistake:** Defining functions after they're called in threads

- ❌ Calling `DrawProgressBar()` before function is defined
- ❌ Starting render threads before all functions exist

**Correct Approach:**

- ✅ Define ALL functions BEFORE starting threads:
  ```lua
  -- Define function FIRST
  local function DrawProgressBar(progress)
      -- Function code
  end
  
  -- THEN start thread that uses it
  Citizen.CreateThread(function()
      DrawProgressBar(progress)
  end)
  ```
- ✅ Use separate render thread at `Citizen.Wait(0)` for smooth UI
- ✅ Validate all parameters before drawing operations

---

## 17. Event Flow Chain Debugging

**Mistake:** Not tracking complete event flow through system

- ❌ Only debugging one side (client OR server)
- ❌ Assuming events are received if they're sent
- ❌ No unique identifiers to track specific interactions

**Correct Approach:**

- ✅ Debug COMPLETE flow: `client → server → client`
- ✅ Use unique tokens/IDs to trace interactions:
  ```lua
  -- Server
  local token = "CHOP_" .. math.random(1000, 9999)
  print("Sending token: " .. token)
  TriggerClientEvent('event', source, token)
  
  -- Client  
  AddEventHandler('event', function(token)
      print("Received token: " .. token) -- Should match!
  end)
  ```
- ✅ Log both successful operations AND errors
- ✅ Remove debug prints in production

---

## 18. Forest Subscription Timing Issues

**Mistake:** Relying only on periodic updates for real-time changes

- ❌ 15-second subscription updates too slow for admin commands
- ❌ Players don't see new forests until next update cycle
- ❌ No immediate notification system

**Correct Approach:**

- ✅ Immediate notification for real-time changes:
  ```lua
  -- When admin creates forest
  local closestForests = SubscribePlayerToForests(playerId, coords)
  TriggerClientEvent('loadForests', playerId, closestForests, nodes, states)
  ```
- ✅ Keep periodic updates for position changes
- ✅ Combine both systems for best user experience

---

## 19. Progress Thread State Management

**Mistake:** Complex thread logic breaking simple operations

- ❌ Over-complicating progress tracking with multiple conditions
- ❌ Threading issues causing progress to freeze at 0%
- ❌ Not validating thread state variables

**Correct Approach:**

- ✅ Keep progress threads SIMPLE:
  ```lua
  while GetGameTimer() - startTime < duration and not interrupted do
      choppingProgress = (GetGameTimer() - startTime) / duration
      Citizen.Wait(100) -- Simple, reliable
  end
  ```
- ✅ Use separate render thread for UI updates
- ✅ Always validate progress values (0-1 range)
- ✅ Add debug prints to track thread execution

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
- [ ] Are RegisterCommand args being accessed as TABLE directly? (No string parsing, use `args[1]` not `arguments[1]`)
- [ ] **NEW:** Are you using correct oxmysql export names? (scalar, NOT scalar_await)
- [ ] **NEW:** Are animations tested on actual RedM server? (Many GTA V scenarios don't exist)
- [ ] **NEW:** Are functions defined BEFORE threads that call them?
- [ ] **NEW:** Is complete event flow debugged with unique tokens/IDs?
- [ ] **NEW:** Are real-time changes immediately notified to players?
