# Reaper Best Practices

This page teaches the correct mental models for using Reaper effectively — not just what to do, but why each pattern matters.

---

## 1. Use Tracks for Physical Entities, Scopes for Logic States

`TrackObject`s and `ScopeObject`s serve distinct roles in Reaper's two-tier memory hierarchy. Conflating them leads to inverted lifecycle dependencies.

A **Track** wraps a physical, tangible game entity — a `Player`, a `Vehicle`, a `Weapon`. It is the root anchor of a memory subtree. A **Scope** wraps a temporary logic state — `"CombatState"`, `"TradingSession"`, `"StunEffect"`. It accumulates connections and threads that belong to that state, not to a physical object.

### The Problem

```luau
-- Creating a Scope to represent a physical character anchor
local charScope = Reaper.Scope("Character_" .. userId)
charScope:Chain(character.Humanoid.Died:Connect(onDied))
-- charScope has no autonomous dead-state detection
-- If the character is destroyed by external code, nothing signals charScope to clean
-- The Humanoid.Died connection leaks silently
```

**Why this is wrong:** Scopes are placed in the zero-cost manual tier with no background monitoring. They have no autonomous dead-state detection. Using a Scope to represent a physical Instance means Reaper will never automatically clean it when that Instance is destroyed.

### The Solution

```luau
-- Track the physical entity — gets an AncestryChanged hook automatically
local charTrack = Reaper.Track(character):Configure("Character_" .. userId, 0)

-- Use a Scope for the logic that runs while the character is alive
local combatScope = Reaper.Scope("Combat_" .. userId)
combatScope:Connect(character.Humanoid.Died, onDied)

-- Bind the logic scope to the physical Track
charTrack:HandleScope(combatScope)
-- Now when the character Instance leaves the game, both are cleaned
```

**Why this works:** Tracking an Instance registers an `AncestryChanged` hook on it. When the Instance leaves the game world, Reaper triggers a full teardown cascade on the Track, which includes cleaning all bound Scopes — so `combatScope` is destroyed automatically.

---

## 2. Chain Raw Items, Not Tracking Handles

`:Chain()` expects the **raw underlying item**, not a Reaper handle wrapping it. Passing a `TrackObject` or `ScopeObject` into `:Chain()` creates redundant ownership pipelines and throws in Studio.

### The Problem

```luau
local conn    = workspace.ChildAdded:Connect(onChildAdded)
local tracker = Reaper.Track(conn)

-- Passing the TrackObject wrapper instead of the raw connection
vehicleTrack:Chain(tracker) -- throws in Studio
```

**Why this is wrong:** Reaper checks whether the argument is already a live tracking handle and throws immediately in Studio. Even without the error, passing a wrapper would create a second ownership record pointing to the same item, causing ambiguous teardown order.

### The Solution

```luau
local conn = workspace.ChildAdded:Connect(onChildAdded)

-- Chain the raw item directly
vehicleTrack:Chain(conn)

-- To bind a Scope, use HandleScope — not Chain
vehicleTrack:HandleScope(combatScope)
```

**Why this works:** `:Chain()` receives the raw item, detects its type, and records it as a child of this Track. Reaper owns it cleanly with a single, unambiguous ownership record.

---

## 3. Never Abandon Abstract Types Without a Lifecycle Anchor

Tables, functions, and unrecognised items are placed in the zero-cost manual tier because they have no native dead-state. Reaper will **never** automatically clean them. If they are not chained to a dying parent or explicitly cleaned, they will live in the registry indefinitely.

### The Problem

```luau
local dataCache = {}  -- a table tracking session data

-- Track it but don't chain it to anything
Reaper.Track(dataCache, "Table")
-- This table will stay registered forever
-- The player can leave and the server will never collect this memory
```

**Why this is wrong:** Reaper emits a Studio warning for exactly this pattern: tables are placed in the manual tier with no automated cleanup path. Without a lifecycle anchor, `dataCache` leaks.

### The Solution

```luau
local dataCache = {}
local playerTrack = Reaper.Get("Player_" .. userId)

-- Configure it and chain it to the player's lifecycle anchor
Reaper.Track(dataCache, "Table"):Configure("DataCache_" .. userId, 0)
playerTrack:Chain(dataCache)

-- Or bypass independent tracking entirely and chain directly to a Scope
local sessionScope = Reaper.Get("Session_" .. userId)
if sessionScope then
    sessionScope:Chain(dataCache)
end
```

**Why this works:** Chaining `dataCache` to a Track or Scope that has a real dead-state — an Instance, or a Scope explicitly cleaned by code — guarantees it is collected when its logical owner ends.

---

## 4. Use Identifiers for Cross-Script Communication, Not Shared References

Passing `TrackObject` or `ScopeObject` references across module boundaries couples your scripts to each other's internals. Reaper's string-identifier registry was designed to eliminate this coupling.

### The Problem

```luau
-- CharacterManager.lua
local scope = Reaper.Scope("Combat_" .. userId)
-- ...passes `scope` to CombatManager as an argument or via a shared table
CombatManager.bindScope(scope)

-- CombatManager.lua
function CombatManager.bindScope(scope)
    scope:Connect(damageEvent.OnServerEvent, onDamage)
end
-- CharacterManager and CombatManager are now tightly coupled
```

**Why this is wrong:** Sharing handle references across scripts creates hidden dependencies. If `CharacterManager` changes how it creates the Scope, `CombatManager` breaks silently.

### The Solution

```luau
-- CharacterManager.lua: create the scope with a known ID
local scope = Reaper.Scope("Combat_" .. userId)

-- CombatManager.lua: fetch it independently by ID
local combatScope = Reaper.Get("Combat_" .. userId)
if combatScope then
    combatScope:Connect(damageEvent.OnServerEvent, onDamage)
end
-- No reference sharing required; both scripts are decoupled
```

**Why this works:** `Reaper.Get()` resolves the string identifier to the live handle in constant time. The string ID is the only contract between the two scripts — no module references, no shared tables, no event handshaking required.

---

## 5. Don't Configure the Same TrackObject Twice

`:Configure()` is a one-time operation. Attempting to re-configure a handle in Studio throws immediately. Architecturally, re-configuration implies a naming or ownership ambiguity that Reaper is designed to prevent.

### The Problem

```luau
local track = Reaper.Track(character):Configure("Char_" .. userId, 0)

-- Later, attempting to rename or change the frequency
track:Configure("Char_" .. userId .. "_v2", 5) -- throws in Studio
```

**Why this is wrong:** Once configured, the handle is registered under its identifier. Allowing re-configuration without first removing the original entry would create dangling identifier records in the registry.

### The Solution

```luau
-- Set the correct ID and frequency at creation time — configure once
local track = Reaper.Track(character):Configure("Char_" .. userId, 0)

-- If the lifecycle needs to restart, clean and re-track:
Reaper.Clean("Char_" .. userId)
local newTrack = Reaper.Track(character):Configure("Char_" .. userId, 0)
```

**Why this works:** Cleaning removes the handle and all its registry entries completely, allowing a fresh registration with a new identifier without any collision.

---

## 6. Prefer :BindToTrack Over :HandleScope for Scope-Perspective Binding

Both `scope:BindToTrack(track)` and `track:HandleScope(scope)` achieve identical results — they register the same parent–child relationship. However, `:BindToTrack()` is more readable when expressing a Scope's own intent to submit itself to a parent.

### The Problem

```luau
-- Binding from the Track's perspective is awkward when the Track
-- doesn't know about the Scope at construction time
local playerTrack = Reaper.Get("Player_" .. userId)
playerTrack:HandleScope(Reaper.Get("Combat_" .. userId))
-- Two lookups, two potential nils to guard
```

### The Solution

```luau
-- In CombatManager.lua: the Scope binds itself after being populated
local combatScope = Reaper.Scope("Combat_" .. userId)
combatScope:Connect(damageEvent.OnServerEvent, onDamage)
combatScope:Spawn(combatTickLoop)

local playerTrack = Reaper.Get("Player_" .. userId)
if playerTrack then
    combatScope:BindToTrack(playerTrack)
end
-- The Scope is the actor — it declares its own lifetime contract
```

**Why this works:** Both paths register the same parent–child relationship. The `:BindToTrack()` form reads as the Scope declaring its own lifetime contract, making architectural intent clear without any functional difference.

---

## 7. Set Frequency Intentionally — Not Everything Needs Polling

Items placed in the frequency-polled tier are evaluated on a recurring frame cycle. Adding large numbers of items with aggressive short frequencies introduces meaningful heartbeat overhead even with the staggered sweep.

### The Problem

```luau
-- Tracking hundreds of connections with an aggressive frequency
for _, conn in activeConnections do
    Reaper.Track(conn):Configure("Conn_" .. conn:GetAttribute("ID"), 0.1)
end
-- The polled tier now has hundreds of entries checked very frequently
```

**Why this is wrong:** Each entry in the polled tier is tested against its interval on every sweep cycle. With hundreds of short-interval entries, the sweep executes that many checks every few frames, burning CPU on items that could be managed event-driven for free.

### The Solution

```luau
-- Option A: Use a Scope to manage short-lived groups; clean by event
local connScope = Reaper.Scope("ConnectionWave_" .. waveId)
for _, conn in activeConnections do
    connScope:Chain(conn)
end
connScope:Connect(someSignal, function()
    Reaper.Clean("ConnectionWave_" .. waveId)
end)

-- Option B: Leave Connections in the background batch tier (no Configure call)
-- They are swept automatically every 30 seconds at zero per-frame cost
Reaper.Track(conn)
```

**Why this works:** Connections that are not configured stay in the background batch tier and are checked in a time-sliced sweep every thirty seconds. The sweep processes at most 500 items per frame, so even large registries never spike the frame rate.

---

## 8. Do Not Assume Configure's Frequency Applies to All Item Types

The `Frequency` argument to `:Configure()` only promotes **Connections** and **Threads** into the frequency-polled tier. For any other item type — Instances, Tables, Functions, Scopes, and unrecognised types — the argument is silently ignored and the frequency is always treated as `0`. Assuming otherwise produces misleading code and unexpected monitoring gaps.

### The Problem

```luau
local character = player.Character

-- Assuming the character's dead-state is checked every 2 seconds via polling
local charTrack = Reaper.Track(character)
    :Configure("Char_" .. userId, 2)

-- The 2-second interval is never used. Reaper does not poll this Instance.
-- Dead-state detection happens immediately via AncestryChanged — which is better —
-- but the developer's mental model of the lifecycle is wrong.
-- If they later try to test timing assumptions based on the 2-second figure,
-- their tests will not behave as expected.
```

**Why this is wrong:** Instances always enter the event-driven detection pathway when first tracked. Calling `:Configure()` on an Instance track gives it a string identifier, but discards the Frequency value and sets it to `0`. The developer now has a `Frequency` field on the handle that does not reflect what they passed — and their timing assumptions are silently wrong.

### The Solution

```luau
-- For Instances: always pass 0. Detection is event-driven and always active.
local charTrack = Reaper.Track(character)
    :Configure("Char_" .. userId, 0)

-- For Connections and Threads: pass the desired interval in seconds.
local conn = someEvent:Connect(onEvent)
local connTrack = Reaper.Track(conn)
    :Configure("EventConn_" .. userId, 5) -- checked every 5 seconds
```

**Why this works:** Using `0` for Instances communicates that no polling is intended — because none occurs. The event-driven detection is always faster than any poll interval anyway: the moment the Instance leaves the game world, Reaper acts immediately, with no lag introduced by a check cycle.

---

## 9. Only Override Auto-Classification When the Item Type Is Certain

`Reaper.Track()` accepts an optional `ItemClassification` argument that tells Reaper exactly how to monitor and tear down an item, bypassing the automatic type detection. Used correctly, this is a useful escape hatch — for example, when a table should be treated as a connection-like object with a `:Disconnect()` teardown. Used incorrectly, it assigns the wrong monitoring strategy and the wrong teardown action to the item, producing silent failures that are difficult to trace.

Reaper's auto-detection is reliable for all seven recognised types. Only supply a manual classification when you have a concrete, deterministic reason — such as registering a well-known custom object whose shape you control — and never in code paths that accept arbitrary items from outside callers.

### The Problem

```luau
-- A utility that accepts any item and tracks it, always forcing "Connection"
local function trackItem(item: any)
    Reaper.Track(item, "Connection")
end

-- Works fine when item is actually a connection:
trackItem(workspace.ChildAdded:Connect(onChildAdded))

-- Breaks silently when item is anything else:
trackItem(someInstance)
-- Reaper now monitors someInstance as if it were a connection.
-- It checks whether someInstance.Connected is false — a field that doesn't exist.
-- Dead-state detection never triggers correctly.
-- On teardown, Reaper calls :Disconnect() on an Instance instead of :Destroy(),
-- which either errors or does nothing — and the Instance is never cleaned up.
```

**Why this is wrong:** Forcing a classification routes the item into the wrong monitoring strategy and pairs it with the wrong teardown action. When the item type does not match the declared classification, dead-state detection silently misfires and teardown either errors or leaves the item alive in memory.

### The Solution

```luau
-- Let Reaper detect the type when the input is variable or unknown
local function trackItem(item: any)
    Reaper.Track(item) -- auto-classification is safe for all recognised types
end

-- Only supply an explicit classification for a known, controlled object shape
local mySignalWrapper = { Connected = true, Disconnect = function(self) self.Connected = false end }
Reaper.Track(mySignalWrapper, "Connection")
-- Safe: the object genuinely behaves like a connection and Reaper can act on it correctly
```

**Why this works:** Auto-classification uses `typeof()` to determine the item's actual runtime type and selects the correct monitoring and teardown path for it. Reaper only needs a manual hint when the item is a table that intentionally mimics another type's interface — and even then, only when the developer can guarantee that every item reaching that code path has the right shape.

---

## 10. Use :Destroy() for Readability, Not as a Behavioural Difference

`TrackObject:Destroy()` is syntactic sugar for `Reaper.Clean(self)`. There is no functional difference. Use whichever reads most naturally in context — typically `:Destroy()` at the call site of the object's owning module, and `Reaper.Clean(id)` from external scripts.

### Example

```luau
-- These are completely equivalent:
charTrack:Destroy()
Reaper.Clean(charTrack)
Reaper.Clean("Char_" .. userId)
Reaper.Clean(character) -- if `character` is the raw item registered in Reaper
```

!!! success "Pro Tip: The Three-Layer Rule"
    Structure your memory hierarchy in three clear layers for every game system:

    1. **Physical Layer (Track)** — The root Instance that represents the game entity (Player, NPC, Vehicle). Registered via `Reaper.Track()` with a meaningful identifier and `Frequency = 0`, relying on event-driven detection.
    2. **Behavioural Layer (Scope)** — One Scope per distinct logic state active on that entity (Combat, Trading, Stunned). Each Scope is bound to the Physical Track via `:BindToTrack()`.
    3. **Event Layer (Chain / Connect)** — All individual connections, threads, and sub-objects are chained into their relevant Behavioural Scope, never directly to the Physical Track.

    This three-layer model guarantees that destroying a single physical entity cascades cleanly through all behavioural states and all their events, with zero manual tracking code required anywhere outside the initial setup.
