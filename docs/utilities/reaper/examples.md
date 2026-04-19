# Reaper Examples

This page demonstrates every public API in the Reaper framework through scenario-based examples with inline commentary.

---

## Reaper Module APIs

### Reaper.Inject

Injects optional dependencies into Reaper before using advanced features.

**Scenario A — Injecting both Assignment and Relay at game startup**

```luau
local Reaper     = require(game.ReplicatedStorage.Reaper)
local Assignment = require(game.ReplicatedStorage.Assignment)
local Relay      = require(game.ReplicatedStorage.Relay)

-- Inject Assignment first so Scope:Repeat() becomes available
Reaper.Inject("Assignment", Assignment)

-- Inject Relay to activate the three global lifecycle signals
Reaper.Inject("Relay", Relay)

-- From this point on, Reaper.Signals.OnTracked/OnCleaned/OnRemoved are live
```

**Scenario B — Running Reaper standalone without any dependencies**

```luau
local Reaper = require(game.ReplicatedStorage.Reaper)

-- No Inject calls needed — Reaper tracks and cleans items immediately
-- Scope:Spawn(), :Defer(), :Delay(), :Connect() all work via native task.*
-- Scope:Repeat() is unavailable without Assignment
-- Reaper.Signals are no-op stubs that warn in Studio if connected to
local scope = Reaper.Scope("PlayerScope")
scope:Connect(workspace.ChildAdded, function(child)
    print("Added:", child.Name)
end)
```

---

### Reaper.Track

Registers a raw item into Reaper's memory system and returns a handle to manage its lifecycle.

**Scenario A — Tracking an Instance; death detected via the engine event, not polling**

```luau
local character = player.Character

-- Instances are always monitored via an AncestryChanged hook — not by polling.
-- The Frequency argument to :Configure() is ignored for Instances and forced to 0.
-- Reaper calls :Destroy() automatically when the character leaves the game world.
local track = Reaper.Track(character)
    :Configure("Character_" .. player.UserId, 0)
```

**Scenario B — Tracking a custom OOP object with a non-standard teardown method**

```luau
local weaponController = WeaponController.new(player)

-- "Dispose" is called instead of the default :Destroy() on teardown
local track = Reaper.Track(weaponController, "Table", "Dispose")
    :Configure("Weapon_" .. player.UserId, 0)
-- Frequency 0: no background polling — cleaned manually or via cascade
```

**Scenario C — Re-tracking an already-registered item returns the existing handle**

```luau
local part = Instance.new("Part", workspace)

local trackA = Reaper.Track(part)
local trackB = Reaper.Track(part) -- item already registered

print(trackA == trackB) -- true — same handle, no duplicate entry created
```

**Scenario D — Protected tracking for an Object Pool**

```luau
local pooledPart = objectPool:Acquire()

-- IsProtected = true: when this part leaves the workspace, Reaper releases it
-- from the registry without destroying it, so the pool can safely reclaim it
local track = Reaper.Track(pooledPart, nil, nil, true)
    :Configure("PooledPart_" .. pooledPart:GetAttribute("PoolID"), 0)
```

**Scenario E — Frequency-based polling for a Connection**

```luau
-- Connections and Threads placed in the background batch tier are eligible
-- to be promoted to the frequency-polled tier via a non-zero Configure value.
-- Here, Reaper checks whether this connection is still active every 3 seconds.
local conn = someRemoteEvent.OnServerEvent:Connect(onRemoteEvent)
local track = Reaper.Track(conn)
    :Configure("RemoteConn_" .. player.UserId, 3)
-- If the connection has been disconnected externally, Reaper detects it
-- within 3 seconds and removes it from the registry automatically
```

---

### Reaper.Scope

Creates a named, managed container that accumulates items and tears them all down together when the Scope is cleaned.

**Scenario A — Scoping a player's active connection set**

```luau
local combatScope = Reaper.Scope("Combat_" .. player.UserId)

-- All connections added here are disconnected when combatScope is cleaned
combatScope:Connect(player.Character.Humanoid.Died, function()
    print(player.Name, "died in combat")
end)

combatScope:Connect(player.Character.Humanoid.HealthChanged, function(health)
    updateHealthUI(player, health)
end)

-- When combat ends:
Reaper.Clean("Combat_" .. player.UserId)
-- Both connections are disconnected in one call
```

**Scenario B — Nested Scope for a sub-state within a larger state**

```luau
local tradingScope = Reaper.Scope("Trading_" .. player.UserId)

-- Create a sub-scope for the item-selection phase
local itemSelectScope = Reaper.Scope("ItemSelect_" .. player.UserId)
itemSelectScope:Connect(tradeUI.ItemSelected, onItemSelected)

-- Bind the sub-scope to the parent; when trading ends, item selection also ends
itemSelectScope:BindToTrack(Reaper.Get("Trading_" .. player.UserId))
```

---

### Reaper.Clean

Immediately destroys one or more tracked items and cascades teardown to everything they own.

**Scenario A — Cleaning a single Scope by its ID**

```luau
-- Somewhere at match start:
local matchScope = Reaper.Scope("Match_Round1")
matchScope:Connect(game.Players.PlayerRemoving, onPlayerLeft)
matchScope:Spawn(function() runMatchTimer() end)

-- At match end:
Reaper.Clean("Match_Round1")
-- The PlayerRemoving connection is disconnected
-- The matchTimer thread is cancelled
-- matchScope is removed from the registry
```

**Scenario B — Cleaning multiple objects in a single call**

```luau
-- Clean three scopes created for a player when they leave
Reaper.Clean(
    "Combat_"  .. player.UserId,
    "UI_"      .. player.UserId,
    "Respawn_" .. player.UserId
)
-- All three are torn down sequentially in the same call
```

**Scenario C — Cleaning via a raw TrackObject reference**

```luau
local track = Reaper.Track(someInstance):Configure("SomeInstance", 5)

-- Later, clean via the handle directly (no ID lookup needed)
track:Destroy()  -- identical to Reaper.Clean(track)
```

---

### Reaper.Remove

Releases items from the registry without destroying them. Only the primary item is preserved; any chained children or bound Scopes are still destroyed.

**Scenario A — Reclaiming a pooled instance before re-use**

```luau
-- Release the root item from Reaper so neither system attempts to destroy it.
-- Any children chained to this track would be destroyed in the same call.
-- Chain nothing to a pooled item's track if you need children preserved too.
local evicted = Reaper.Remove("PooledPart_42")
-- evicted[1] is the raw Part instance, fully intact
objectPool:Release(evicted[1])
```

**Scenario B — Releasing multiple items and inspecting what was returned**

```luau
local removed = Reaper.Remove(
    "TempEffect_A",
    "TempEffect_B",
    "TempEffect_C"
)

for _, item in removed do
    print("Released:", tostring(item)) -- items are still alive; just de-registered
end
```

---

### Reaper.Get

Returns the live tracking handle for an item or Scope registered under a given identifier.

**Scenario A — Fetching a Scope from another module to chain additional items**

```luau
-- In UIManager.lua:
local uiScope = Reaper.Scope("UI_" .. player.UserId)
uiScope:Connect(screenGui.Activated, onUIActivated)

-- In CombatManager.lua (separate script, no shared reference):
local uiScope = Reaper.Get("UI_" .. player.UserId)

if uiScope then
    -- Chain a temporary combat HUD element to the existing UI scope
    uiScope:Chain(combatHUDFrame)
    -- When UIManager cleans "UI_playerX", the combatHUDFrame is also destroyed
end
```

**Scenario B — Checking existence before operating on a Scope**

```luau
local function tryCleanCombat(userId: number)
    local existing = Reaper.Get("Combat_" .. userId)

    if existing then
        Reaper.Clean("Combat_" .. userId)
    else
        warn("No active combat scope for user:", userId)
    end
end
```

---

### Reaper.Is and Reaper.IsCleanable

Guards for validating live Reaper handles before operating on them.

**Scenario A — Reaper.Is: guarding a function that accepts TrackObjects, ScopeObjects, or raw items**

```luau
local function safeChain(target: any, child: any)
    if Reaper.Is(target) then
        -- target is a live TrackObject or ScopeObject; safe to call :Chain()
        target:Chain(child)
    else
        -- target is a raw item or already-cleaned handle; register it first
        Reaper.Track(target):Chain(child)
    end
end
```

**Scenario B — Reaper.IsCleanable: checking a Scope before handing it to a system**

```luau
local function bindScopeToPlayer(scope: any, track: TrackObject)
    if not Reaper.IsCleanable(scope) then
        warn("Attempted to bind an invalid or destroyed scope — skipped.")
        return
    end
    -- Safe to call BindToTrack only after the guard passes
    (scope :: ScopeObject):BindToTrack(track)
end
```

**Scenario C — Distinguishing a TrackObject from a ScopeObject**

```luau
local handle = Reaper.Get("SomeID")

if Reaper.IsCleanable(handle) then
    -- handle is specifically a ScopeObject
    print("Got a scope:", handle.AssignID)
elseif Reaper.Is(handle) then
    -- handle is a TrackObject (not a Scope)
    print("Got a track:", handle.AssignID)
else
    print("Not found or already cleaned")
end
```

---

## TrackObject Methods

### :Configure

Assigns an identifier and polling frequency to a `TrackObject`. For Instances and manual-tier items, the Frequency argument is always forced to `0`; non-zero values are only meaningful for Connections and Threads.

**Scenario A — Configuring a Connection with a dead-state check interval**

```luau
-- Connections start in the background batch tier (30-second sweep).
-- Configure promotes this one to the frequency-polled tier at 5-second intervals.
local conn = someEvent:Connect(onEvent)
local connTrack = Reaper.Track(conn)
connTrack:Configure("EventConn_" .. player.UserId, 5)
-- Reaper checks every 5 seconds whether this connection is still active
```

**Scenario B — Configuring a long-lived object with a relaxed interval**

```luau
local conn = longLivedEvent:Connect(onLongLivedEvent)
local mapTrack = Reaper.Track(conn)

-- This connection rarely goes dead; check every 60 seconds to minimise overhead
mapTrack:Configure("LongConn_" .. player.UserId, 60)
```

**Scenario C — Configure with Frequency 0 for manual-only management**

```luau
local dataTrack = Reaper.Track(playerDataTable, "Table")

-- Tables have no native dead-state; opt out of polling entirely
dataTrack:Configure("PlayerData_" .. player.UserId, 0)
-- Must be cleaned explicitly: Reaper.Clean("PlayerData_playerX")
```

**Scenario D — Configuring an Instance track (Frequency is always 0)**

```luau
local character = player.Character

-- Frequency 0 is the only valid value for Instance tracks.
-- AncestryChanged detection is already registered at Track() time;
-- passing any other value here is silently treated as 0.
local charTrack = Reaper.Track(character)
    :Configure("Char_" .. player.UserId, 0)
```

---

### :Chain

Binds raw child items to a handle for cascade cleanup.

**Scenario A — Chaining a connection and a thread to an Instance track**

```luau
local characterTrack = Reaper.Track(character):Configure("Char_" .. userId, 0)

local healthConn = character.Humanoid.HealthChanged:Connect(onHealthChanged)
local animThread = task.spawn(runAnimationLoop, character)

-- Both are destroyed when the character Instance leaves the game world
characterTrack:Chain(healthConn)
characterTrack:Chain(animThread)
```

**Scenario B — Chaining with a custom teardown method**

```luau
local customObj = MyFramework.new()

-- MyFramework uses :Dispose() instead of :Destroy()
vehicleTrack:Chain(customObj, "Dispose")
-- On cascade, Reaper calls customObj:Dispose() instead of the default
```

**Scenario C — Fluent chaining across multiple items**

```luau
Reaper.Track(part):Configure("TrackedPart", 0)
    :Chain(part.Touched:Connect(onTouched))
    :Chain(part.ChildAdded:Connect(onChildAdded))
    :Chain(task.delay(10, destroyEffect, part))
-- All three children are torn down when the part leaves the game world
```

---

### :HandleScope

Subordinates an entire Scope to this handle.

**Scenario A — Binding a behaviour Scope to a character Track**

```luau
local charTrack   = Reaper.Track(character):Configure("Char_" .. userId, 0)
local combatScope = Reaper.Scope("Combat_" .. userId)

combatScope:Connect(character.Humanoid.Died, onDied)
combatScope:Spawn(combatLoop)

-- When the character is destroyed, the combat scope is fully torn down too
charTrack:HandleScope(combatScope)
```

**Scenario B — Binding a Scope by string ID (cross-script pattern)**

```luau
-- CharacterManager creates the Track:
local charTrack = Reaper.Track(character):Configure("Char_" .. userId, 0)

-- CombatManager creates the Scope independently:
local combatScope = Reaper.Scope("Combat_" .. userId)

-- CharacterManager binds by ID without needing the live ScopeObject reference:
charTrack:HandleScope("Combat_" .. userId)
```

---

## ScopeObject Methods

### :BindToTrack

Submits a Scope to be owned by a physical Track.

**Scenario A — Standard bind from the Scope's perspective**

```luau
local playerTrack = Reaper.Track(player):Configure("Player_" .. userId, 0)
local uiScope     = Reaper.Scope("UI_" .. userId)

uiScope:Connect(screenGui.Activated, onActivated)

-- Bind this Scope to the player Track; cleaned when the player Track is cleaned
uiScope:BindToTrack(playerTrack)
```

**Scenario B — Binding after fully populating the Scope**

```luau
local inventoryScope = Reaper.Scope("Inventory_" .. userId)

for _, slot in inventoryFrame:GetChildren() do
    inventoryScope:Connect(slot.MouseButton1Click, function()
        onSlotClicked(slot)
    end)
end

-- Bind last, after all connections are established
local playerTrack = Reaper.Get("Player_" .. userId)
if playerTrack then
    inventoryScope:BindToTrack(playerTrack)
end
```

---

### :Unchain

Removes a child from a Scope without destroying it.

**Scenario A — Releasing a connection to transfer it to a new owner**

```luau
local scopeA = Reaper.Scope("ScopeA")
local conn    = workspace.ChildAdded:Connect(onChildAdded)
scopeA:Chain(conn)

-- Transfer ownership: release from A and give to B
local scopeB = Reaper.Scope("ScopeB")
scopeA:Unchain(conn) -- conn is still alive, just no longer owned by scopeA
scopeB:Chain(conn)   -- scopeB is now the owner
```

**Scenario B — Removing a conditional child before cleanup**

```luau
local sessionScope = Reaper.Scope("Session_" .. userId)
local tempEffect   = createParticleEffect()
sessionScope:Chain(tempEffect)

-- The effect was already manually destroyed; unchain to prevent double-teardown
tempEffect:Destroy()
sessionScope:Unchain(tempEffect)
```

---

### :CleanChild

Immediately destroys a specific child without waiting for the Scope to be cleaned.

**Scenario A — Destroying a temporary effect early**

```luau
local roundScope = Reaper.Scope("Round_" .. roundId)
local countdown  = createCountdownUI()
roundScope:Chain(countdown)

-- Round started; countdown UI is no longer needed
roundScope:CleanChild(countdown)
-- countdown is destroyed and removed from roundScope's child list
-- roundScope itself is still alive and tracking other children
```

**Scenario B — Conditionally cleaning one of several chained connections**

```luau
local adminScope = Reaper.Scope("Admin_" .. userId)
local kickConn   = kickButton.Activated:Connect(onKickClicked)
local banConn    = banButton.Activated:Connect(onBanClicked)

adminScope:Chain(kickConn)
adminScope:Chain(banConn)

-- Player lost admin; disable ban ability but keep kick
adminScope:CleanChild(banConn) -- banConn is disconnected and removed
-- kickConn is still alive and owned by adminScope
```

---

### :Connect

Connects a signal and automatically adds the connection to this Scope's child list.

**Scenario A — Replacing manual connection management**

```luau
-- Before Reaper: manual tracking required
local conn = character.Humanoid.Died:Connect(onDied)
-- (must remember to disconnect conn later...)

-- With Reaper Scope: automatic lifecycle
local charScope = Reaper.Scope("CharScope_" .. userId)
charScope:Connect(character.Humanoid.Died, onDied)
-- Disconnected automatically when charScope is cleaned
```

**Scenario B — Connecting a custom signal table**

```luau
local mySignal = Relay.Create("CustomEvent") -- a Relay signal object

local eventScope = Reaper.Scope("EventScope")
eventScope:Connect(mySignal, function(data)
    processData(data)
end)
-- Works with any table that has a :Connect(callback) method
```

---

### :Spawn

Spawns a coroutine and adds it to this Scope's child list. The coroutine is registered before it begins executing, so cleanup is safe regardless of timing.

**Scenario A — Running a polling loop tied to a player session**

```luau
local sessionScope = Reaper.Scope("Session_" .. userId)

sessionScope:Spawn(function()
    while true do
        task.wait(1)
        syncPlayerData(player)
    end
end)
-- When sessionScope is cleaned, the thread is cancelled
-- No dangling loop continues after the session ends
```

**Scenario B — Spawning with arguments**

```luau
local animScope = Reaper.Scope("Anim_" .. userId)

animScope:Spawn(function(character, speed)
    playRunAnimation(character, speed)
end, player.Character, 16)
-- Arguments are forwarded to the coroutine on first resume
```

---

### :Defer

Defers a callback and adds the scheduled task to this Scope's child list.

**Scenario A — Deferring a UI update to the end of the current frame**

```luau
local uiScope = Reaper.Scope("UI_" .. userId)

uiScope:Defer(function()
    -- Runs after the current resume cycle completes
    refreshInventoryUI(player)
end)
-- If uiScope is cleaned before this frame ends, the deferred task is cancelled
```

**Scenario B — Deferring initialisation that depends on other systems**

```luau
local initScope = Reaper.Scope("Init")

initScope:Defer(function()
    -- All synchronous setup has run; safe to initialise dependent systems now
    notifySystemsReady()
end)
```

---

### :Delay

Schedules a delayed task and adds it to this Scope's child list.

**Scenario A — Auto-expiring a timed buff**

```luau
local buffScope = Reaper.Scope("SpeedBuff_" .. userId)

applySpeedBuff(player, 1.5)

-- Remove buff after 10 seconds; also cancel if buffScope is cleaned early
buffScope:Delay(10, function()
    removeSpeedBuff(player)
    Reaper.Clean("SpeedBuff_" .. userId)
end)
```

**Scenario B — Delayed despawn of a temporary effect**

```luau
local fxScope = Reaper.Scope("HitFX_" .. hitId)
fxScope:Chain(effectPart)

-- Despawn after 2 seconds regardless of game state
fxScope:Delay(2, function()
    Reaper.Clean("HitFX_" .. hitId)
end)
```

---

### :Repeat

Creates a repeating scheduled task and adds it to this Scope's child list.

!!! danger "Strict Dependency: Assignment Library"
    `:Repeat()` requires the **Assignment** library to be injected. Without it, this method is a no-op.

**Scenario A — Periodic leaderboard sync during a match**

```luau
local matchScope = Reaper.Scope("Match_" .. matchId)

-- Sync leaderboard every 5 seconds for the duration of the match
matchScope:Repeat(-1, 5, function(iteration, handle)
    syncLeaderboard()
end)
-- Automatically cancelled when matchScope is cleaned at match end
```

**Scenario B — Running a fixed-count animation burst**

```luau
local animScope = Reaper.Scope("BurstAnim_" .. userId)

-- Flash the character 5 times with a 0.2s interval
animScope:Repeat(5, 0.2, function(i, handle)
    character.Humanoid.RootPart.Transparency = (i % 2 == 0) and 0 or 0.5
end)
```

---

## Global Lifecycle Signals

### Reaper.Signals.OnTracked, OnCleaned, OnRemoved

!!! danger "Strict Dependency: Relay Library"
    These signals are no-op stubs until Relay is injected. Connect only after calling `Reaper.Inject("Relay", Relay)`.

**Scenario A — Logging all tracked items for debugging**

```luau
Reaper.Signals.OnTracked:Connect(function(item, classification, assignId)
    print(string.format("[Reaper] Tracked: %s | Class: %s | ID: %s",
        tostring(item), classification, assignId or "none"))
end)
```

**Scenario B — Observing cleanups for analytics**

```luau
-- OnCleaned fires after the teardown action has run.
-- The item reference is available but may no longer be in a valid state.
local cleanCount = 0

Reaper.Signals.OnCleaned:Connect(function(item, classification)
    cleanCount += 1
    if classification == "Instance" then
        -- Read only metadata that does not require the Instance to be alive
        print(string.format("[Reaper] Instance destroyed (total cleans: %d)", cleanCount))
    end
end)
```

**Scenario C — Reacting to evictions from an Object Pool**

```luau
Reaper.Signals.OnRemoved:Connect(function(item, classification)
    if classification == "Instance" then
        -- An Instance was released (protected); return it to the pool
        -- It is still fully intact when OnRemoved fires
        objectPool:Release(item :: Instance)
    end
end)
```

**Scenario D — Using :Once() for a one-shot observation**

```luau
-- Wait for the very first item to be cleaned, then stop listening
Reaper.Signals.OnCleaned:Once(function(item, classification)
    print("First item cleaned:", classification)
    -- Connection is automatically disconnected after this fires once
end)
```

**Scenario E — Using :Wait() to yield until an eviction occurs**

```luau
-- Pause this coroutine until something is removed from the registry
local item, classification = Reaper.Signals.OnRemoved:Wait()
print("Something was evicted:", classification, tostring(item))
```
