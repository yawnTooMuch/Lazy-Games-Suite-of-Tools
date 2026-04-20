# Stamp Best Practices

This guide covers the correct mental models and architectural patterns for using **Stamp** effectively. Every practice explains not only what to do, but why — in terms of the user-visible consequences.

---

## 1. The Behavioural Component Pattern

The central philosophy of Stamp is to replace monolithic object scripts with small, reusable **behaviours** — one stream per concern, each completely independent.

Think of each `StampStream` like a React component. In React you build a `HealthBar` component once and render it wherever health exists — on a player card, an NPC nameplate, a boss UI. You do not copy the component for each context; you apply the same component to whatever needs it. **Stamp** works identically. You build a `Health` stream once — with all its `Tagged` logic, attribute initialization, and `ObserveAttribute` listeners — and then you apply it by tagging any entity that has health: players, NPCs, props, vehicles, breakable terrain, whatever. The same logic runs for all of them without a single line being duplicated.

This means your codebase grows by adding new streams, not by expanding existing scripts. A `Stun` stream handles stun for every entity type. A `Pickup` stream handles pickup logic for every collectible. Each stream is a self-contained unit of behaviour that can be applied, removed, and tested in isolation. When you need to change how health works, you change it in one place — the health stream — and every entity type benefits immediately.

The stream is also a **globally accessible object**. Because `Stamp.Register("Health")` always returns the same live stream for the lifetime of that tag, any other script in your codebase can acquire that stream by calling `Stamp.Register("Health")` itself. The cleaner pattern, however, is to have the system that *owns* the behaviour return the stream from its module, so consuming scripts require the system — not Stamp directly, **BUT** this introduces heavy coupling and required structure that the owning script must load first since other scripts is dependent on it. By using `Stamp.Register` directly anywhere in the game scripts, it doesnt matter who loads first whether its the scripts that just consume the stream or the script that setup the stream, both just modified/use the same stream.

### The Problem

```luau
-- ServerScriptService/NPCMain.lua
-- A single script handles health, AI, and interactions for a specific NPC type.
-- If a barrel needs the same "Health" logic, you must copy and adapt the entire script.
local function handleNPC(npc)
    local health = 100
    npc.Touched:Connect(function()  -- Never disconnected; lives forever in memory
        health -= 10
    end)

    task.spawn(function()
        while npc.Parent do  -- Checks every frame even when nothing has changed
            task.wait(1)
        end
    end)
end
```

**Why this is wrong:** The logic is locked to one object type. Any resource created here has no guaranteed cleanup path — when the NPC is removed, the `Touched` connection and the loop remain alive, silently consuming memory and CPU for the rest of the server's lifetime. If a barrel or vehicle also needs health, the code must be duplicated, which means bugs must also be fixed in two places.

!!! warning "Side Effect"
    Any event connection or loop created without scope binding accumulates silently. A server that spawns and removes hundreds of entities over a session will accumulate thousands of dead connections and zombie loops with no mechanism to release them.

### The Solution — The Owning System

```luau
-- ServerScriptService/Systems/HealthSystem.lua
-- Build the Health component once.
local Stamp = require(path.to.Stamp)

local healthStream = Stamp.Register("Health")

healthStream.Signals.Tagged:Connect(function(entity, scope)
    -- Works identically whether entity is a Player character, an Orc, a Barrel, or a Car
    healthStream:SetAttribute(entity, "Health", 100)
    healthStream:SetAttribute(entity, "MaxHealth", 100)

    healthStream:ObserveAttribute(entity, "Health", function(hp)
        -- This listener stops automatically when the tag is removed from any entity type
        if hp <= 0 then entity:Destroy() end
    end)
end)
```

### The Solution — Consuming Scripts

```luau
-- ServerScriptService/Systems/SpawnSystem.lua
-- Require stamp here in this script.
local Stamp = require(path.to.Stamp)
local healthStream = Stamp.Register("Health")

-- Apply the behaviour by tagging — no changes to HealthSystem required
if healthStream then
    healthStream:AddTag(workspace.Orc)         -- NPC gets health
    healthStream:AddTag(playerCharacter)       -- Player gets health
    healthStream:AddTag(workspace.FuelBarrel)  -- Prop gets health
    healthStream:AddTag(workspace.Jeep)        -- Vehicle gets health
end
```

```luau
-- ServerScriptService/Systems/CombatSystem.lua
-- Same setup as above
local Stamp = require(path.to.Stamp)
local healthStream = Stamp.Register("Health")

local function applyDamage(entity: Model, amount: number)
    local current = healthStream:GetAttribute(entity, "Health")
    if current then
        healthStream:SetAttribute(entity, "Health", math.max(0, current - amount))
    end
end
```

**Why this works:** The `Health` stream behaves identically regardless of what entity type carries the tag. Every resource created inside the `Tagged` callback is bound to the entity's scope, which is destroyed automatically when the tag is removed — for any entity type, without any per-type cleanup code. Any number of scripts can consume the stream through the owning module; none of them duplicate or re-declare the behaviour logic.

!!! tip "Register Is Idempotent"
    `Stamp.Register("Health")` called from multiple scripts always returns the same live stream. No duplicate listeners are created. Wrapping the stream in a module and returning it is the good pattern because it makes the ownership chain explicit **BUT** it also introduces coupling, calling `Register` directly from a consuming script is highly recommended when working with **Stamp**.

!!! info "One Stream, Many Entity Types"
    This is the key architectural insight: a `Tagged` callback does not care what type of entity fires it. The same health logic, the same attribute initialization, and the same cleanup guarantee apply equally to every entity that carries the tag — player, NPC, prop, or vehicle.

---

## 2. Always Bind Resources to the Scope

The `scope` parameter in `Signals.Tagged` callbacks is the most important tool Stamp provides for preventing memory leaks.

**The Golden Rule:** Every event connection, loop, or task you create inside a `Tagged` callback must be bound to the provided `scope`. Any resource created without scope binding can outlive the entity's tag and accumulate in memory.

### The Problem

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- This connection has no scope binding — it will never be cleaned up
    entity.PrimaryPart.Touched:Connect(function()
        print("touched")
    end)

    -- This loop has no scope binding — it will run until the server crashes
    task.spawn(function()
        while true do
            task.wait(1)
            print(entity.Name .. " still ticking")
        end
    end)
end)
```

**Why this is wrong:** When the entity is untagged, the `Touched` connection and the loop continue running. After many enemies are spawned and removed, hundreds of dead connections and zombie loops accumulate. After enough time, the server runs out of memory or the frame rate collapses.

!!! warning "Side Effect"
    Unscoped resources do not produce any error or warning when the entity is removed. The accumulation is entirely silent — the only signal is a gradual decline in server frame rate or an eventual out-of-memory crash.

### The Solution

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- This connection stops the moment the entity is untagged
    scope:Connect(entity.PrimaryPart.Touched, function()
        print("touched")
    end)

    -- This loop stops the moment the entity is untagged
    scope:Repeat(-1, 1, function()
        print(entity.Name .. " still ticking")
    end)
end)
```

**Why this works:** Every resource registered through the scope is tracked. When the tag is removed, the scope is torn down in one synchronised step — all connections disconnected, all loops stopped, all tasks cancelled. The entity leaves no trace.

!!! tip "The Scope Is the Guarantee"
    Binding to the scope is not just a cleanup convenience — it is the only mechanism that guarantees cleanup. If you are unsure whether a resource needs to be scoped, the answer is always yes. There is no downside to binding something that would have cleaned itself up anyway, but there is a significant downside to leaving something unbound that will not.

---

## 3. Use ObserveAttribute Instead of Polling

Stamp's `ObserveAttribute` replaces both the manual attribute-read loop and the manual signal setup that developers typically write by hand.

### The Problem: Polling

```luau
-- Checks health every frame for this one NPC.
-- With 200 enemies active, this is 12,000 pointless reads per second
-- even when health has not changed at all.
task.spawn(function()
    while entity.Parent do
        local hp = entity:GetAttribute("Health")
        if hp and hp <= 0 then
            entity:Destroy()
            break
        end
        task.wait()
    end
end)
```

**Why this is wrong:** The CPU wakes up this code constantly, regardless of whether the attribute has actually changed. This pattern scales catastrophically in games with many entities.

!!! warning "Side Effect"
    Polling loops created with `task.spawn` have no guaranteed cleanup path. If the entity is removed before the loop's exit condition is met, the loop continues iterating on a destroyed instance indefinitely.

### The Problem: Manual Event Setup

```luau
-- More efficient than polling, but fragile.
local function onHealthChanged(value)
    if value <= 0 then entity:Destroy() end
end

-- Step 1: Handle the initial value (easy to forget)
local initial = entity:GetAttribute("Health")
if initial then onHealthChanged(initial) end

-- Step 2: Connect the change signal
local conn = entity:GetAttributeChangedSignal("Health"):Connect(function()
    onHealthChanged(entity:GetAttribute("Health"))
end)

-- Step 3: Manually disconnect when the entity is removed (very easy to forget)
-- If this is skipped, the connection stays alive forever.
```

**Why this is wrong:** This is three separate steps that must all be written correctly and kept in sync. Missing step 1 means your code doesn't reflect the current state. Missing step 3 causes a memory leak. Stamp collapses all three into one call.

### The Solution: ObserveAttribute

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- 1. Fires on the next frame with the current value (no manual initial read needed)
    -- 2. Fires again on every future change
    -- 3. Cleans up automatically when the entity's tag is removed
    enemyStream:ObserveAttribute(entity, "Health", function(hp)
        if hp <= 0 then entity:Destroy() end
    end)
end)
```

**Why this works:** The callback is scheduled immediately with whatever value the attribute currently holds, then re-fires only when the value actually changes. The CPU is idle in between. The connection is bound to the entity's scope automatically, so cleanup requires no extra code.

!!! warning "Asynchronous Initial Callback"
    The first callback invocation — the one that delivers the current value — does not run inline when `ObserveAttribute` is called. It is scheduled to run on the next available frame. Do not write code that assumes the initial callback has already executed by the time `ObserveAttribute` returns.

!!! tip "Event-Driven Over Time-Driven"
    `ObserveAttribute` only wakes up your code when the value actually changes. A health value sitting at 500 produces zero CPU activity between damage events. A polling loop at the same cadence would generate thousands of reads per second doing nothing useful.

---

## 4. Understand the ObserveAttribute Scope Waterfall

If you call `ObserveAttribute` outside a `Signals.Tagged` callback — for example from a UI system observing an entity it did not tag — you must understand how the connection's lifetime is determined.

### The Problem

```luau
-- A UI module observes an enemy's health to drive a health bar.
-- No scope is provided and the enemy is not being observed through its tag stream.
enemyStream:ObserveAttribute(enemy, "Health", function(hp)
    healthBar.Value = hp
end)
-- If the UI is destroyed before the enemy, this connection continues running
-- and attempts to write to a UI element that no longer exists.
```

**Why this is wrong:** Without a scope, if the entity is not currently tracked by the stream, the connection binds to the entity's object lifetime — which is correct for that specific case. But if you also need the connection to stop when *your* system shuts down, you need to pass your own scope.

!!! info "Scope Binding Waterfall"
    The connection's lifetime is determined in this priority order: 
    (1) custom scope provided → binds to it 
    (2) entity is tracked by this stream → binds to its tag scope
    (3) entity has a parent but is not tracked → binds to its object lifetime
    (4) entity has no parent → disconnected immediately
    Knowing which rule applies tells you exactly how long your connection will live.

### The Solution

```luau
-- A UI module that manages its own scope.
-- Passing the scope means the observation ends when the UI is torn down,
-- regardless of whether the enemy is still alive.
local uiScope = Reaper.Scope("HealthBarUI_" .. enemy.Name)

enemyStream:ObserveAttribute(enemy, "Health", function(hp)
    healthBar.Value = hp
end, uiScope)

-- Later, when the UI is cleaned up:
uiScope:Destroy() -- observation ends here
```

**Why this works:** The connection's lifetime is now controlled by the scope you own. When your system shuts down, you destroy its scope, which disconnects everything bound to it — including the observation.

!!! tip "Own Your Connections From Outside Tagged"
    Any time you call `ObserveAttribute` from outside a `Signals.Tagged` callback, always ask: "what scope should own this connection?" If you can't answer that question, create a dedicated scope for the observing system. A connection with no clear owner is a potential leak.

---

## 5. Use SetAttribute Instead of Direct Roblox Attributes (For Queryable Data)

When you set an attribute directly on an instance with `instance:SetAttribute(key, value)`, that value is invisible to Stamp's query system. `GetInstancesWithAttribute (Local)` only returns instances whose values were written through Stamp's own `SetAttribute` method.

### The Problem

```luau
-- This bypasses Stamp's query cache entirely
workspace.Orc:SetAttribute("Health", 500)

-- This call returns nothing — Stamp has no record of the "Health" attribute on the Orc
local results = enemyStream:GetInstancesWithAttribute("Health", 500)
print(#results) -- 0
```

**Why this is wrong:** Stamp cannot see values written by the native Roblox API. The query returns an empty result even though the attribute exists on the instance.

!!! warning "Side Effect"
    Writing attributes directly to instances does not update Stamp's query cache. There is no error or warning — the cache and the instance simply diverge silently, and queries return stale or empty results.

### The Solution

```luau
-- Write through Stamp so the value enters the query cache
enemyStream:SetAttribute(workspace.Orc, "Health", 500)

-- Now the query finds it correctly
local results = enemyStream:GetInstancesWithAttribute("Health", 500)
print(#results) -- 1
```

**Why this works:** `SetAttribute` writes the value to both the Roblox instance and Stamp's query index in one operation. Future `GetInstancesWithAttribute (Local)` calls find it immediately without walking the workspace hierarchy.

!!! tip "Reading Is Always Safe"
    `GetAttribute` falls back to the live Roblox value if no cached entry exists. So if an attribute was set directly on the instance (not through Stamp), `GetAttribute` will still return the correct value. The gap only affects *querying by attribute across many instances* — reads are always accurate.

---

## 6. Respect Attribute Type Constraints

Stamp enforces Roblox's attribute type rules. Only a specific set of types can be stored as instance attributes, and attempting to use an unsupported type will cause an error in Studio.

### The Problem

```luau
-- Passing a table or an Instance reference as an attribute value
enemyStream:SetAttribute(orc, "TargetPlayer", game.Players.LocalPlayer) -- Wrong: Instance type
enemyStream:SetAttribute(orc, "PatrolPath", {Vector3.new(0,0,0)})        -- Wrong: Table type
```

**Why this is wrong:** Roblox does not support `Instance` references or `table` values as attributes. In Studio, Stamp throws a descriptive error. In production, the behaviour is undefined.

!!! warning "Supported Attribute Types"
    Stamp's attribute cache only supports the types that Roblox itself permits: `string`, `number`, `boolean`, `UDim`, `UDim2`, `BrickColor`, `Color3`, `Vector2`, `Vector3`, `NumberRange`, `NumberSequence`, `ColorSequence`, `Rect`, and `Font`. The type check runs in Studio only. Always validate your attribute types during development so unsupported values are caught before they reach production.

### The Solution

```luau
-- Store a reference by a serialisable value instead
enemyStream:SetAttribute(orc, "TargetPlayerName", game.Players.LocalPlayer.Name)  -- Acceptable: string
enemyStream:SetAttribute(orc, "PatrolIndex", 1)                                   -- Acceptable: number
enemyStream:SetAttribute(orc, "HomePosition", Vector3.new(0, 0, 0))               -- Acceptable: Vector3
```

**Why this works:** Serialisable types like `string`, `number`, `boolean`, `Vector3`, `Color3`, and the other supported types replicate cleanly across the server/client boundary and are queryable through Stamp's attribute system.

!!! tip "Model References as Names"
    When you need to associate an entity with another object — such as a target player — store the player's `Name` or `UserId` as a `string` or `number` attribute, then look up the live object from that identifier when you need it. This keeps attributes serialisable and avoids the `Instance` type restriction entirely.

---

## 7. Server Authority and Client Reads

Stamp does not change the rules of Roblox networking, but it makes it easy to violate them if you are not deliberate.

**The three rules:**

1. **Only the server should tag and untag gameplay-critical objects.** Tags replicate to clients automatically. A client tagging an object changes nothing on the server.

2. **Never trust attribute values set by the client.** A client can call `SetAttribute` on its own machine, but those values do not replicate to the server. Treat any attribute your game logic depends on as server-authored.

3. **Clients should read attributes, not write them.** The correct pattern is: server calculates the value and writes it via `SetAttribute`; clients observe it via `ObserveAttribute` to drive UI or visual effects.

```luau
-- Server: calculates and writes
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    enemyStream:SetAttribute(entity, "Health", 200)
end)

-- Client: reads and visualises
-- LocalScript
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    enemyStream:ObserveAttribute(entity, "Health", function(hp)
        -- Drive a world-space health bar — reading only, never writing
        updateHealthBar(entity, hp)
    end)
end)
```

!!! note "CollectionService Tag Replication"
    `CollectionService` tags set on the server replicate to all clients automatically. A client-side `Stamp.Register("Enemy")` will fire `Signals.Tagged` for every server-tagged entity that streams in. The client never needs to call `AddTag` — the server's tagging is the source of truth.

!!! warning "Client Attributes Do Not Replicate"
    Attribute values written on the client via `SetAttribute` exist only on that client's machine. They are invisible to the server and to other clients. Any attribute that affects gameplay logic — health, damage, ownership — must be written exclusively from the server.

---

## 8. Choose Between Global and Stream-Level Queries

Stamp offers two levels of attribute query. Using the wrong one returns more data than you need and makes code harder to reason about.

| Goal | Use |
| :--- | :--- |
| Find any entity across all types that has a specific attribute | `Stamp.GetInstancesWithAttribute(key, value)` |
| Find entities of a specific type that have a specific attribute | `stream:GetInstancesWithAttribute(key, value)` |

### The Problem

```luau
-- You want all stunned *enemies*, but you query globally.
-- If the "Stunned" attribute is also used on players or props,
-- you get back all of them mixed together.
local allStunned = Stamp.GetInstancesWithAttribute("Stunned", true)
```

**Why this is wrong:** The global query does not discriminate between streams. If multiple object types use the same attribute key, you get all of them back — including types you did not intend to act on.

!!! warning "Side Effect"
    Attribute key names are not namespaced between streams. Two different streams can both use `"Stunned"` on their respective entities, and the global query will return all of them regardless of their type. This is correct behaviour for the global query — but it is the wrong tool when you only care about one stream.

### The Solution

```luau
-- Scoped to the enemy stream only — no false positives from other object types
local stunnedEnemies = enemyStream:GetInstancesWithAttribute("Stunned", true)
```

**Why this works:** The stream-level query considers only instances that are currently tracked by that specific stream. Results are precise and predictable regardless of what other streams use the same attribute key.

!!! tip "Prefer Stream-Level Queries in System Scripts"
    Within a system that owns a specific stream, always use the stream-level query. Reserve the global query for cross-system tooling — for example, a debug inspector that needs to display all entities carrying a given attribute regardless of which system manages them.

---

## 9. Destroy Streams at Phase Boundaries

Streams accumulate tracked instances, attribute cache entries, and signal connections for as long as they are live. If a behaviour is no longer needed — for example, because a match has ended — destroy the stream rather than leaving it running with zero instances.

### The Problem

```luau
-- The match ends but the stream is left running.
-- Its CollectionService listeners remain active, its signal objects stay in memory,
-- and any future accidental tagging would be silently processed.
function onMatchEnd()
    enemyStream:RemoveAllTags()
    -- stream is still live; nothing is actually released
end
```

**Why this is wrong:** `RemoveAllTags` untags the current instances, but the stream itself remains registered. Its `CollectionService` listeners continue listening, its signal objects remain in memory, and if any script accidentally tags an entity with the old tag name, the stream will silently process it.

!!! warning "Side Effect"
    A live stream with zero tracked instances still holds active `CollectionService` event connections. Over many rounds where streams are never destroyed, these accumulate alongside new ones, consuming memory and slightly increasing the cost of every future tag event on the server.

### The Solution

```luau
function onMatchEnd()
    -- RemoveAllTags runs internally first, then all listeners and relays are destroyed
    enemyStream:Destroy()
    enemyStream = nil

    -- Re-register a fresh stream at the start of the next match
end
```

**Why this works:** `Destroy (Local)` performs a complete teardown: all entities are untagged, all scope-bound resources are released, and the stream is removed from Stamp's registry. Re-registering the same tag name at the start of the next match gives you a clean slate.

!!! tip "Destroy Then Re-Register"
    Destroying a stream does not prevent you from creating a new one with the same tag name. Calling `Stamp.Register("Enemy")` after `Stamp.Destroy("Enemy")` (or `enemyStream:Destroy()`) creates a completely fresh stream with no inherited state. This is the recommended pattern for round-based or phase-based game modes.

---

## 10. Do Not Manually Manage Entity Scopes

The garbage-collection scope provided to each `Signals.Tagged` callback belongs entirely to Stamp. Stamp creates it, tracks it, and destroys it at the exact moment the entity loses its tag. Attempting to take ownership of this scope yourself — by binding it to an external track or submitting it to another part of the garbage-collection system — breaks that contract and produces unpredictable behaviour.

The underlying framework operates on a **Last Call Supremacy** model: whenever an object is registered with a new owner, it is immediately released from its previous one. This means that the instant you try to bind an entity's scope to an external track, the scope leaves Stamp's boundary entirely. Stamp can no longer destroy it when the tag is removed. The scope will instead live until the external track decides to clean it — which may be much later, or never.

### The Problem

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- Attempting to bind the entity's scope to an external track
    -- immediately removes it from Stamp's control.
    someExternalTrack:HandleScope(scope)

    scope:Connect(entity.PrimaryPart.Touched, function()
        print("touched")
    end)
    -- When the enemy is untagged, Stamp can no longer clean this scope.
    -- The Touched connection leaks until someExternalTrack is cleaned instead.
end)
```

**Why this is wrong:** The moment `HandleScope` is called, the scope is transferred to a new owner under Last Call Supremacy. Stamp's untag pathway can no longer reach it. Everything bound to the scope — connections, loops, tasks — will persist until the external track is eventually destroyed, which may be at a completely unrelated time. This defeats the entire purpose of Stamp's automated lifecycle management.

!!! warning "Last Call Supremacy"
    The garbage-collection framework that backs Stamp uses a Last Call Supremacy model: registering an object with a new owner always releases it from its previous one. Because Stamp registers each entity scope internally when the tag is applied, any external re-registration immediately evicts the scope from Stamp's control. There is no way to transfer ownership back.

### The Solution

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- Use the scope as Stamp intended: bind resources directly to it.
    -- Stamp will destroy the scope — and everything in it — when the tag is removed.
    scope:Connect(entity.PrimaryPart.Touched, function()
        print("touched")
    end)

    -- If you need to observe this entity from a completely separate system,
    -- create a fresh scope that belongs to that system — do not share the entity's scope.
    local externalScope = Reaper.Scope("ExternalSystem_" .. entity.Name)
    enemyStream:ObserveAttribute(entity, "Health", function(hp)
        -- drive external system logic
    end, externalScope)
    -- externalScope is owned and destroyed by the external system independently
end)
```

**Why this works:** The entity's scope stays inside Stamp's boundary. When the tag is removed, Stamp destroys the scope and everything bound to it on schedule. Any external system that needs its own connection lifetime creates its own scope — the two lifetimes remain independent and neither interferes with the other.

!!! tip "One Scope Per Owner"
    If multiple independent systems need to react to the same entity, each system creates its own scope rather than sharing the entity's tag scope. This keeps each system's cleanup path completely self-contained: destroying one system's scope has no effect on any other system's connections or the entity's tag scope itself.

---

## 11. The "Configure-Then-Tag" Pattern (Hydrate Before Announcing)

If you must set attributes to an entity outside the `Signals.Tagged` signal, always set its attributes, properties, and network ownership *before* applying the tag. `AddTag` should be the absolute final line of the code.

### The Problem

If you apply the tag before setting attributes, you create a severe race condition. The `.Tagged` signal fires synchronously the exact millisecond `:AddTag()` is called across all listening scripts. This is a race condition.

```luau
-- BAD: Tag-Then-Configure
BurningStamp:AddTag(Fireball) -- The .Tagged signal fires instantly here!
BurningStamp:SetAttribute(Fireball, "Damage", 50) -- Too late. Listening systems already read 'nil'.

-- COMBAT SYSTEM SCRIPT
-- Somewhere scripts in the game inside the Combat System
BurningStamp.Signals.Tagged:Connect(function(Entity, Scope)
    -- ERROR: The damage attribute hasn't been set yet!
    local damage = BurningStamp:GetAttribute(Entity, "Damage") 
end)
```

### The Solution

```luau
-- GOOD: Configure-Then-Tag
BurningStamp:SetAttribute(Fireball, "Damage", 50)
BurningStamp:SetAttribute(Fireball, "Owner", Player.UserId)

-- NOW announce it to the world:
BurningStamp:AddTag(Fireball)

-- COMBAT SYSTEM SCRIPT
-- Somewhere scripts in the game inside the Combat System
BurningStamp.Signals.Tagged:Connect(function(Entity, Scope)
    -- PERFECT: The data is immediately available synchronously.
    local damage = BurningStamp:GetAttribute(Entity, "Damage") 
    
    -- ObserveAttribute instantly fires with the correct initial value ('50')
    BurningStamp:ObserveAttribute(Entity, "Damage", function(value)
        print("Fireball damage is: ", value)
    end)
end)
```

**Why this works (and why it is memory-safe):** Stamp handles this order of operations flawlessly. When you set an attribute on an untagged entity, Stamp caches the data and quietly uses `Reaper.Track(Entity)` to ensure the cache doesn't leak if the instance is destroyed prematurely. When you subsequently call `AddTag`, Stamp generates the dedicated `Reaper.Scope` for the entity's behaviours. If the entity is later destroyed, Reaper gracefully cleans both the tag's logic scope and the underlying attribute cache without any conflicts.

---

!!! success "Pro Tip: Keep Tag Names Short"
    `CollectionService` tags replicate across the network. Every byte in a tag name is transmitted to every client that joins the server. Short, descriptive names like `"Enemy"` or `"Pickup"` keep join overhead low. If you find yourself writing tag names longer than 20 characters, consider whether you are using tags as serialised data rather than as category identifiers — and if so, use attributes instead.
