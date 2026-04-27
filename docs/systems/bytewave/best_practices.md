# Best Practices

---

## 1. Use `PlayerAdded` Instead of `Players.PlayerAdded` for Initial Sends

When you need to send data to a player the moment they join, reach for `ByteWave.PlayerAdded` rather than the standard Roblox `Players.PlayerAdded` event. `Players.PlayerAdded` fires the instant a player connects to the server — before ByteWave has completed its own handshake with the client. During that brief window, the client's string registry is empty, which means any named gateway or path you send will arrive as an unresolvable numeric ID and be silently ignored.

`ByteWave.PlayerAdded` fires only after the handshake is complete. By that point the client knows every interned name and is ready to receive data correctly.

### The Problem

```luau
-- Players.PlayerAdded fires before ByteWave's client is ready.
-- The packet is queued correctly on the server, but the client
-- cannot decode the gateway name and drops it silently.
game:GetService("Players").PlayerAdded:Connect(function(player)
    ByteWave.Send("Init", "WorldSeed", currentSeed, {
        ____TargetPlayer = player,
        ____InternString = true,
    })
end)
```

**Why this is wrong:** The client has not yet received its copy of the string registry. The gateway name `"Init"` is stored as a two-byte ID that the client does not recognize yet, so the packet is discarded on arrival.

### The Solution

```luau
-- ByteWave.PlayerAdded fires only after the handshake — safe to send immediately.
ByteWave.PlayerAdded(function(player)
    ByteWave.Send("Init", "WorldSeed", currentSeed, {
        ____TargetPlayer = player,
        ____InternString = true,
    })
end)
```

**Why this works:** By the time this callback fires, ByteWave has synchronized the string registry to the client and confirmed the connection is ready.

---

## 2. Always Use Separated Coroutines on Yielding APIs/Methods

Any ByteWave API that can suspend a coroutine — such as `ByteWave.Request` — must never be called directly on the main thread of a script or inside a connection callback. Calling a yielding API on a shared execution path suspends that entire path for however long the operation takes, blocking all subsequent code on that thread until it resumes.

This applies universally: if a ByteWave method can yield, it belongs in its own coroutine.

### The Problem

```luau
-- ByteWave.Request is called directly inside a connection callback.
-- If the server takes 2 seconds to respond, this entire callback is suspended
-- for 2 seconds, blocking any code that comes after it on the same thread.
button.Activated:Connect(function()
    local success, data = ByteWave.Request("Inventory", { ItemId = selectedItem })

    displayResult(success, data)  -- only runs after the yield resolves
end)
```

**Why this is wrong:** Connection callbacks share their execution with the event system. Suspending them for multiple seconds can cause frame drops and delayed event handling across the entire script.

### The Solution

```luau
-- Wrap the yielding call in its own coroutine so the callback returns immediately.
button.Activated:Connect(function()
    task.spawn(function()
        local success, data = ByteWave.Request("Inventory", { ItemId = selectedItem })

        displayResult(success, data)
    end)
end)
```

**Why this works:** The spawned coroutine runs independently. When `Request` yields, only that coroutine is suspended — the event system and all other callbacks continue running normally.

This same rule applies to every ByteWave API that can yield. Treat yielding calls as inherently requiring their own coroutine and you will never accidentally stall an execution path.

---

## 3. Intern Strings for Repeated Named Paths

ByteWave supports string interning as a bandwidth optimization for gateway and path names that are sent repeatedly. A path like `"EnemyPosition"` is serialized at its full byte length the first time it is sent without interning. With interning enabled, the name is registered as a two-byte ID on first use — every subsequent send costs only two bytes regardless of how long the name is.

Enable interning with `____InternString = true` in the options table on the first send for any fixed, design-time path name that will be sent more than once.

### The Problem

```luau
-- Sending a named path every Heartbeat without interning.
-- The full string is serialized into every single packet.
game:GetService("RunService").Heartbeat:Connect(function()
	ByteWave.Send("WorldSync", "EnemyPositionUpdate", { 
		X = x,
		Z = z
	}, {
		____IsReliable = false,
	})
end)
```

**Why this is wrong:** Without interning, the full string is written into every packet. At 60 Hz across many players this compounds quickly into unnecessary bandwidth usage.

### The Solution

```luau
-- Pass ____InternString = true on the first send.
-- After the first packet the name is registered as two bytes for all future sends.
ByteWave.Send("WorldSync", "EnemyPositionUpdate", {
	X = x, 
	Z = z 
}, {
	____IsReliable   = false,
	____InternString = true,
})
```

**Why this works:** After the first send, ByteWave's registry resolves the name to a fixed two-byte ID on both sides. All future packets for that path pay only that two-byte cost.

!!! warning "Never Intern Dynamic Strings"
    The string registry holds up to 65,500 entries total. Interning is designed strictly for a fixed set of path and gateway names that are known at design time and remain constant across the lifetime of the server. If you pass `____InternString = true` with a string that is constructed at runtime — such as a path incorporating a player's UserId, an item's unique identifier, or any value that varies per call — each unique string creates a new registry entry. In a game with many players or items this will exhaust the registry and raise a fatal error that breaks all packet routing across the entire server.

```luau
-- NEVER do this — each unique path permanently consumes a registry slot.
for _, item in itemList do
    ByteWave.Send("Inventory", "Item_" .. item.UniqueId, item.Data, {
        ____InternString = true,
    })
end

-- Keep the path fixed and carry the dynamic data inside the payload.
for _, item in itemList do
    ByteWave.Send("Inventory", "ItemUpdate", { Id = item.UniqueId, Data = item.Data })
end
```

If a path changes per call or per player, it is not a candidate for interning. Carry the varying data in the value payload instead and keep the path name fixed.

---

## 4. Declare Configuration Tables in the Root Section of the Codebase

Many ByteWave APIs accept an options table as their final argument. A common mistake is to construct that table inline, directly at the call site. Every time the surrounding code runs — every Heartbeat, every event, every loop iteration — Lua allocates a brand-new table object, fills it with the same values it had last time, and then discards it once the call returns. The garbage collector must then reclaim that allocation. For code paths that fire frequently, this accumulates into a steady stream of short-lived allocations that pressure the GC unnecessarily.

Because configuration tables almost never change after the system is set up, there is no reason to construct them more than once. Declare them as upvalues at the top of the module and reuse the same table reference on every call.

### The Problem

```luau
-- A new table is allocated and immediately discarded on every Heartbeat.
game:GetService("RunService").Heartbeat:Connect(function()
	ByteWave.Send("WorldSync", "PositionUpdate", { 
		X = x, 
		Z = z 
	}, {
		____IsReliable   = false,
		____InternString = true,
	})
end)
```

```luau
-- A new table is created for every player every time this fires.
ByteWave.PlayerAdded(function(player)
    ByteWave.Send("Init", "WorldSeed", currentSeed, {
        ____TargetPlayer = player,
        ____InternString = true,
    })
end)
```

**Why this is wrong:** Each inline `{}` is a fresh heap allocation. On a Heartbeat connection at 60 Hz, that is 60 table allocations per second that all contain identical data. The `____TargetPlayer` case is slightly different because `TargetPlayer` varies per call — but the rest of the fields are constant and can still be partially pre-declared.

### The Solution

```luau
-- Declare config tables once at the top of the module.
local POSITION_SEND_CONFIG = {
	____IsReliable   = false,
	____InternString = true,
}

local INIT_SEND_CONFIG = {
	____InternString = true,
}

-- Reuse them everywhere they are needed.
game:GetService("RunService").Heartbeat:Connect(function()
	ByteWave.Send("WorldSync", "PositionUpdate", { 
		X = x,
		Z = z
	}, POSITION_SEND_CONFIG)
end)

ByteWave.PlayerAdded(function(player)
	INIT_SEND_CONFIG.____TargetPlayer = player
	ByteWave.Send("Init", "WorldSeed", currentSeed, INIT_SEND_CONFIG)
end)
```

**Why this works:** The table is allocated exactly once when the module loads. Every subsequent call reads and reuses the same object — no new allocation, no GC pressure. For fields like `____TargetPlayer` that must vary per call, mutating the single shared table inline is still cheaper than allocating an entirely new one each time.

Apply this pattern to every options table in ByteWave: send configs, state creation options, and action registration configs alike.

---

## 5. Destroy States When Their Anchor or Owner is No Longer Valid

A `StateObject` lives until you explicitly destroy it. If you create a spatial state for a world object that is later removed, or a private state for a player who has left, the state remains registered and continues to consume memory and replication cycles until `Destroy()` is called.

There are two main patterns for tying a state's lifetime to its anchor: connecting directly to the anchor's `Destroying` event, or delegating the cleanup to a garbage collector such as Reaper from the Lazy Games Suite of Tools.

---

### Scenario 1 — Direct Event Connection

The simplest approach is to connect to the anchor's `Destroying` event and call `Destroy()` on the state from there. This works well for any standard `Part`, `Model`, or other `Instance` that lives in the workspace.

#### The Problem

```luau
-- A spatial state is created for a chest. The chest is deleted during a map reset,
-- but the state is never cleaned up.
local chestState = ByteWave.State.CreateState("Chest_01", { 
	IsOpen = false 
}, "Spatial_Global", nil, chest, 30)

workspace.Chest_01:Destroy()
-- chestState is still registered and still tries to replicate to nearby players.
```

**Why this is wrong:** The anchor no longer exists, but the state's spatial discovery loop still processes it each tick. Clients who were previously observing the state never receive a destroy signal and are left with stale data.

#### The Solution

```luau
local chestState = ByteWave.State.CreateState("Chest_01", { 
	IsOpen = false
}, "Spatial_Global", nil, chest, 30)

-- Tie the state's lifetime directly to the anchor instance.
chest.Destroying:Connect(function()
	chestState:Destroy()
end)
```

**Why this works:** `Destroy()` sends a destroy packet to every client currently observing the state, removes the state from the registry, and cancels any pending timers — leaving no orphaned data on either side. The moment the chest leaves the game, the state is torn down with it.

---

### Scenario 2 — Managed Cleanup with Reaper

For more complex systems — maps that spawn and tear down many objects at once, or modules that manage many states across many instances — manually writing a `Destroying` connection per object becomes repetitive and easy to miss. In these cases, **Reaper** (part of the Lazy Games Suite of Tools) provides a structured garbage-collection system that cascades cleanup automatically.

The pattern is:

1. **Track** the anchor `Instance` with `Reaper.Track()` and give it a named identity via `:Configure()`.
2. **Create a Scope** with `Reaper.Scope()` to own everything that belongs to that anchor.
3. **Bind the Scope to the Track** with `Scope:BindToTrack()` so it is cleaned when the anchor is cleaned.
4. **Chain the `StateObject`** into the Scope using `:Chain()` with `"Destroy"` as the custom teardown method.

When Reaper detects that the anchor has been removed from the game (via its `AncestryChanged` hook), it automatically cleans the Track, which cascades to the Scope, which calls `chestState:Destroy()` — all without any manual `Destroying` connection.

#### The Solution

```luau
-- Track the anchor and give it a named identity.
-- The second argument to :Configure() is the polling frequency in seconds. Because `Track` detects BasePart, Model and other instance objects that has destroy signal when cleaned up, Reaper treat the tracked object as event driven. For script clarity, we will set the frequency to 0 (means event driven). Even if you put any numbers in here, it gets overriden by Reaper regardless.
local ChestTrack = Reaper.Track(chest):Configure("Chest_01_Track", 0)

-- Create a Scope to own everything this chest is responsible for.
local ChestScope = Reaper.Scope("Chest_01_Scope")

-- Bind the Scope's lifetime to the Track.
-- When the chest is destroyed, Reaper cleans the Track and cascades to this Scope.
ChestScope:BindToTrack(ChestTrack)

-- Create the spatial state and chain it into the Scope.
-- "Destroy" tells Reaper to call :Destroy() on the StateObject during teardown.
local chestState = ByteWave.State.CreateState("Chest_01", { 
	IsOpen = false 
}, "Spatial_Global", nil, chest, 30)

ChestScope:Chain(chestState, "Destroy")
```

**Why this works:** Reaper hooks into the chest's `AncestryChanged` event under the hood. When the chest leaves the game, `ChestTrack` is cleaned, the cascade reaches `ChestScope`, and `chestState:Destroy()` is called automatically. No manual event management is required, and the pattern scales cleanly to any number of objects in the map.

This approach also means that if the chest needs additional owned resources — connections, threads, or other states — they can all be chained into `ChestScope` and will be torn down together as a single unit when the anchor is gone.

---

## 6. Use the Action Sub-System for Client-Initiated Commands, Not Bare Gateways

When a client needs to trigger a specific server-side behavior — a button press, a player choice, a skill activation — the `ByteWave.Action` pair (`Action.Register` on the server, `Action.Send` on the client) provides a cleaner and safer structure than creating a raw gateway listener for each behavior.

With raw gateways you must manually validate the path string in every listener, handle unknown paths gracefully, and manage handler registration across multiple scripts. The Action sub-system centralizes this: each named action has exactly one handler and an optional configuration table readable via `GetConfig`.

!!! success "Pro Tip"
    Store all action names as constants in a shared module required by both the server and client. This eliminates typo bugs — a misspelled action name is caught at load time by the Studio parameter checker rather than silently failing at runtime.

```luau
-- Shared module: ActionNames.lua
return {
    PurchaseItem   = "PurchaseItem",
    RequestRespawn = "RequestRespawn",
    CastSpell      = "CastSpell",
}
```

```luau
-- Server
local Actions = require(shared.ActionNames)

ByteWave.Action.Register(Actions.PurchaseItem, { 
	MaxPerMinute = 5 
}, handlePurchase)
```

```luau
-- Client
local Actions = require(shared.ActionNames)

ByteWave.Action.Send(Actions.PurchaseItem, { 
	ItemId = "sword_01"
})
```

!!! warning "Action System Optimization"
    When you use the `Action` sub-system, by default ByteWave doesnt intern the strings here. This means that all actions logic ("Action" Gateway and developer defined ActionName) strings get to travel on the wire as full string bytes representation. To achieve optimization, send dummy payload in the server with the "Action" `Gateway` and a specified ActionName as `Path` with the string interning enabled.