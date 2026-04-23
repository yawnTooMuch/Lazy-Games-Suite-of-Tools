# Best Practices

Correct mental models and common pitfalls. Every practice is grounded in user-visible consequences — not implementation internals.

---

## 1. Gate Gameplay Behind OnLoadCompleted, Not PlayerAdded

Data is not available the moment a player joins. Loading involves lease acquisition, cross-server validation, storage reads, and schema reconciliation — all of which take time.

### The Problem

```luau
game.Players.PlayerAdded:Connect(function(player)
    -- Wrong: data is not ready yet.
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    stats.coins += 100  -- stats is nil here — this crashes
    player:LoadCharacter()
end)
```

**Why this is wrong:** `FetchData` returns `nil` until the load sequence completes. Trying to read or modify data here will cause a nil-indexing error and may silently skip the award.

### The Solution

```luau
Diary.Signals.OnLoadCompleted:Connect(function(player)
    -- Data is guaranteed to be present here.
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    if not stats then return end  -- defensive guard for edge cases

    stats.coins += 100
    Diary.MarkDirty(player.UserId, "PlayerStats")
    player:LoadCharacter()
end)
```

**Why this works:** `OnLoadCompleted` fires only after every registered template has been fully loaded and reconciled. The data is guaranteed to be in memory, typed correctly, and ready to read and write.

---

## 2. Centralise All Template Registration in a Dedicated ModuleScript

`RegisterTemplate` returns a handle that you must pass to every `FetchData` call. The recommended pattern is to create a single ModuleScript whose sole responsibility is registering every template and exposing typed handle accessors. This module must be `require`d at the very first line of your server initialisation script — before any other module runs — so that all templates are registered within the boot window, before any player's load sequence can begin.

### The Problem

```luau
-- In a helper function, called many times during gameplay.
local function getCoins(player)
    -- Wrong: calls RegisterTemplate every time just to get the handle.
    local def = Diary.RegisterTemplate("PlayerStats", { coins = 0 })
    local stats = Diary.FetchData(player.UserId, def)
    return stats and stats.coins or 0
end
```

**Why this is wrong:** Every call re-registers the template, re-reconciles data for all online players, and marks their records dirty. On a busy server this generates unnecessary writes and can cause subtle data inconsistencies.

### The Solution

Create a dedicated `DiaryTemplates` ModuleScript. The moment it is `require`d, it registers every template and stores the handles internally. The rest of your codebase accesses handles through typed wrapper functions, never by calling `RegisterTemplate` again.

```luau
-- DiaryTemplates (ModuleScript)
local Diary = require(path.Diary)

-- Declare your schema types here. Diary strictly maps to these at runtime.
------------------------------------------------------------------------------------
export type PlayerStatsSchema = {
    health : number,
    mana   : number,
    -- add the rest of your player stats fields here
}

-- export type PlayerInventorySchema = { ... }
------------------------------------------------------------------------------------

local module  = {}
local handles = {}

local myTemplates = {
    ------------------------------------------------------------------------------------
    {
        location = "PlayerStats",
        schema   = {
            health = 100,
            mana   = 100,
        } :: PlayerStatsSchema,
    },
    -- add additional template entries here
    ------------------------------------------------------------------------------------
}

------------------------------------------------------------------------------------
-- Do not modify this block — it registers all templates on require.
local function initiate()
    for _, data in myTemplates do
        handles[data.location] = Diary.RegisterTemplate(data.location, data.schema)
    end
end
initiate()
------------------------------------------------------------------------------------

-- Expose a typed accessor for each handle.
------------------------------------------------------------------------------------
function module.PlayerStats(): Diary.DataDefinition<PlayerStatsSchema>
    return handles.PlayerStats :: Diary.DataDefinition<PlayerStatsSchema>
end

-- add further accessor functions here, one per registered location
------------------------------------------------------------------------------------

return module :: {
    PlayerStats: () -> Diary.DataDefinition<PlayerStatsSchema>,
    -- list additional accessors here to match the return type
}
```

Then, anywhere in your codebase that needs player data:

```luau
-- Require DiaryTemplates at the top of your server init script (first require).
local DiaryTemplates = require(path.DiaryTemplates)
local Diary          = require(path.Diary)

Diary.Signals.OnLoadCompleted:Connect(function(player)
    local stats = Diary.FetchData(player.UserId, DiaryTemplates.PlayerStats())

    print(stats.health, stats.mana)  -- prints 100  100
    print(stats)                     -- prints the full memory structure Diary maintains for this player
end)
```

**Why this works:** All templates are registered in a single pass the instant the module is required. Every accessor returns the same pre-registered handle — no re-registration, no reconciliation side-effects. The typed return signatures mean your editor can infer field names and catch type mismatches before runtime.

!!! tip "Module loader users"
    If your project uses a module loader or dependency injection system, ensure that `DiaryTemplates` is placed at the absolute top of the load order — before any module that might trigger player logic. Registration must complete before any player's load sequence begins.

---

## 3. Use MarkDirty for Frequent Changes, SaveData for Critical Ones

Both methods schedule data to be written, but they serve different purposes. Misusing `SaveData` on high-frequency data will quickly exhaust your DataStore write budget and trigger rate-limiting.

### The Problem

```luau
-- Wrong: calling SaveData inside a per-frame loop.
game:GetService("RunService").Heartbeat:Connect(function(dt)
    for _, player in game.Players:GetPlayers() do
        local stats = Diary.FetchData(player.UserId, StatsDefinition)
        if stats then
            stats.playtime += dt
            Diary.SaveData(player.UserId, "PlayerStats")  -- generates a DataStore write every frame
        end
    end
end)
```

**Why this is wrong:** `SaveData` attempts a real storage write on every call. At 60 frames per second with multiple players, this overwhelms the DataStore budget, triggers the back-off queue, and causes other players' saves to be delayed.

### The Solution

```luau
-- Correct: MarkDirty signals the change; the framework decides when to write.
game:GetService("RunService").Heartbeat:Connect(function(dt)
    for _, player in game.Players:GetPlayers() do
        local stats = Diary.FetchData(player.UserId, StatsDefinition)
        if stats then
            stats.playtime += dt
            Diary.MarkDirty(player.UserId, "PlayerStats")
            -- The framework writes at the configured save interval — not every frame.
        end
    end
end)

-- Reserve SaveData for moments that demand prompt persistence.
local function processPurchase(player)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    stats.coins -= 500
    Diary.SaveData(player.UserId, "PlayerStats", true)  -- write now, this is important
end
```

**Why this works:** `MarkDirty` is a pure in-memory operation. The framework's auto-save loop reads the flag and batches writes at the right cadence. `SaveData` is reserved for moments — purchases, level completions — where a delayed write would be unacceptable.

---

## 4. Always Guard FetchData for Nil

`FetchData` returns `nil` if a player's data has not yet loaded or if the player was kicked during loading. Unguarded nil access will crash your code.

### The Problem

```luau
local function addXP(player, amount)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    stats.xp += amount  -- will crash if stats is nil
end
```

**Why this is wrong:** If `addXP` is called before `OnLoadCompleted` fires — or if the player was disconnected mid-load — `FetchData` returns `nil` and this line throws an error.

### The Solution

```luau
local function addXP(player, amount)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    if not stats then
        -- Data not ready or player no longer valid. Silently bail.
        return
    end
    stats.xp += amount
    Diary.MarkDirty(player.UserId, "PlayerStats")
end
```

**Why this works:** The guard catches both the not-yet-loaded case and the post-kick case cleanly. No error, no silent corruption — the function simply does nothing when the data is unavailable.

---

## 5. Inject Assignment Before Any Player Can Join

The Assignment scheduler, if used, must replace the default task primitives before any background work begins. Injecting after the server is running risks some operations using different scheduling behaviour than others.

### The Problem

```luau
local Diary = require(game.ServerScriptService.Diary)

-- Wait until later to inject...
task.delay(5, function()
    local Assignment = require(game.ServerScriptService.Assignment)
    Diary.Inject("Assignment", Assignment)  -- too late: workers have already started
end)
```

**Why this is wrong:** Diary starts its background workers immediately on `require`. Workers that started before injection use the default `task.*` primitives. Workers started after use Assignment. The result is a mixed scheduler environment that can behave unpredictably under load.

### The Solution

```luau
-- First line of your server script — before anything else.
local Diary      = require(game.ServerScriptService.Diary)
local Assignment = require(game.ServerScriptService.Assignment)

Diary.Inject("Assignment", Assignment)

-- Now register templates and connect signals.
local StatsDefinition = Diary.RegisterTemplate("PlayerStats", { coins = 0 })

Diary.Signals.OnLoadCompleted:Connect(function(player)
    player:LoadCharacter()
end)
```

**Why this works:** Injection happens synchronously before any player can arrive and before any deferred background operation runs. Every part of Diary uses the same scheduler from the start.

---

## 6. Separate Data Locations by Concern, Not by Size

It might seem efficient to put all player data into a single location. In practice, a single large location means every save writes the entire record even when only one small part changed.

### The Problem

```luau
-- One giant blob for everything.
local EverythingDefinition = Diary.RegisterTemplate("PlayerData", {
    coins         = 0,
    level         = 1,
    inventory     = {},
    settings      = { music = true, sfx = true },
    questProgress = {},
    -- ... 50 more fields
})
```

**Why this is wrong:** A purchase changes `coins`. A settings toggle changes `settings`. In both cases, the entire record — including inventory, quests, and everything else — is serialised and written. This wastes DataStore budget and slows down the save pipeline.

### The Solution

```luau
-- Separate locations for data that changes at different rates.
local StatsDefinition     = Diary.RegisterTemplate("PlayerStats",     { coins = 0, level = 1 })
local InventoryDefinition = Diary.RegisterTemplate("PlayerInventory", { items = {} })
local SettingsDefinition  = Diary.RegisterTemplate("PlayerSettings",  { music = true, sfx = true })
local QuestDefinition     = Diary.RegisterTemplate("PlayerQuests",    { progress = {} })

-- Each location can also carry its own cache policy.
Diary.RegisterPolicy("PlayerSettings", {
    ____IntervalMultiplier = 10,  -- settings rarely change; save infrequently
})
```

**Why this works:** Only the location whose data changed is written on each cycle. Frequently changing data (coins, XP) can be saved at one interval; rarely changing data (settings, appearance) at another. Write costs stay proportional to actual activity.

---

## 7. Use WipeData Only With Explicit Intent and Audit Logging

`WipeData` is permanent and irreversible. There is no recovery path. Build an audit trail before calling it, and never call it as a general punishment mechanism.

### The Problem

```luau
-- An overzealous anti-cheat that wipes data on detection.
local function onCheatDetected(player)
    Diary.WipeData(player)  -- irreversible; no audit trail; no human review
end
```

**Why this is wrong:** False positives are inevitable in any anti-cheat system. Destroying data without a human review step and an audit log is unrecoverable and puts you at legal and community risk.

### The Solution

```luau
-- Flag for human review first. Wipe only after confirmation.
local function flagForReview(player, evidence)
    queueForModReview(player.UserId, evidence)
    -- A moderation tool later calls:
end

local function executeVerifiedWipe(userId, reason, moderator)
    local package = Diary.WipeData(userId, {
        reason    = reason,
        requester = moderator,
    })
    -- Store the audit package in an external log before discarding it.
    persistAuditLog(package.audit, package.copy)
end
```

**Why this works:** The audit record returned by `WipeData` contains a formatted timestamp, the responsible moderator, and a full copy of all data at the moment of deletion. Persisting this before it is garbage-collected gives you a defensible paper trail.

---

## 8. Keep MemoryStore Caching Enabled for Active Players

Disabling MemoryStore caching via `HandleMemoryCaching` removes the fast-storage safety net. If a server crashes after caching is disabled and before the final DataStore write, data from that session may be partially or fully lost.

### The Problem

```luau
-- Disabling caching system-wide to reduce MemoryStore costs.
Diary.Signals.OnLoadCompleted:Connect(function(player)
    for _, location in {"PlayerStats", "PlayerInventory", "PlayerQuests"} do
        Diary.HandleMemoryCaching(player.UserId, location, true)  -- disabled for all locations
    end
end)
```

**Why this is wrong:** MemoryStore serves as a crash-safe buffer. Between DataStore writes (which happen at the configured interval), the MemoryStore copy is what a new server reads when a player reconnects. Disabling it means a reconnect after a crash loads potentially stale data.

### The Solution

```luau
-- Only disable caching for truly low-stakes, non-persistent locations.
Diary.Signals.OnLoadCompleted:Connect(function(player)
    -- Chat preferences don't need crash recovery — disable caching only here.
    Diary.HandleMemoryCaching(player.UserId, "ChatPreferences", true)

    -- All other locations keep caching enabled (the default).
end)
```

**Why this works:** MemoryStore caching is enabled by default for a reason. Only opt specific low-value locations out — ones where losing a session's worth of changes is acceptable. For anything involving economy, progression, or inventory, leave caching on.

---

## 9. Don't Call FetchTombstones on Every Player Join

`FetchTombstones` performs a MemoryStore read (and potentially a DataStore read) every time it is called without a warm cache. Calling it per-player is expensive and redundant.

### The Problem

```luau
-- Called inside PlayerAdded for every joining player.
game.Players.PlayerAdded:Connect(function(player)
    local tombstones = Diary.FetchTombstones()
    if tombstones[tostring(player.UserId)] then
        player:Kick("Account deleted.")
    end
end)
```

**Why this is wrong:** Diary already performs ban checking internally during the load sequence — a banned player is kicked before their data is ever returned. Calling `FetchTombstones` here duplicates that work with an extra storage read per join.

### The Solution

```luau
-- Use FetchTombstones for admin tools, audits, and background checks — not per-join gates.
local function generateDeletionReport()
    local tombstones = Diary.FetchTombstones()
    local count = 0
    for _ in tombstones do count += 1 end
    print(string.format("%d accounts have been permanently deleted.", count))
end

-- Ban checking on join is handled automatically by Diary.
-- Trust OnLoadCompleted to only fire for valid, non-banned players.
Diary.Signals.OnLoadCompleted:Connect(function(player)
    player:LoadCharacter()  -- If we're here, the player is not banned.
end)
```

**Why this works:** The load sequence internally reads the ban record before any data is returned. If a ban is found, the player is kicked and `OnLoadCompleted` never fires for them. Your code in `OnLoadCompleted` can assume the player is valid.

---

## 10. Register All Templates Before the Server Opens to Players

Diary's load sequence reads every registered template when a player joins. If a template is registered after a player has already started loading, that location will not be included in their session.

### The Problem

```luau
local Diary = require(game.ServerScriptService.Diary)

-- Stats registered immediately.
local StatsDefinition = Diary.RegisterTemplate("PlayerStats", { coins = 0 })

-- But inventory is registered inside another script that loads a moment later.
task.delay(2, function()
    local InventoryDefinition = Diary.RegisterTemplate("PlayerInventory", { items = {} })
    -- Any player who joined in that 2-second window won't have inventory data loaded.
end)
```

**Why this is wrong:** Players who join during the gap between template registrations will have their load sequence begin before the second template exists. Their inventory location will be skipped entirely.

### The Solution

```luau
-- Register all templates at the top of a single server init script.
-- The 10-second boot window gives you time before the server opens to players.
local Diary = require(game.ServerScriptService.Diary)

local StatsDefinition     = Diary.RegisterTemplate("PlayerStats",     { coins = 0, level = 1 })
local InventoryDefinition = Diary.RegisterTemplate("PlayerInventory", { items = {} })
local QuestDefinition     = Diary.RegisterTemplate("PlayerQuests",    { active = {}, completed = {} })

-- All templates are in place before any player can arrive.
Diary.Signals.OnLoadCompleted:Connect(function(player)
    player:LoadCharacter()
end)
```

**Why this works:** Diary buffers players for 10 seconds at server startup. Registering all templates synchronously at the top of your init script guarantees they are all in place before any player's load sequence begins.

---

## 11. Configure Each Memory Location According to Its Behaviour

The default cache policy Diary ships with is a sensible starting point for general-purpose data, but it is not optimal for every location. Data that changes frequently deserves a shorter save interval; data that rarely changes can afford a much longer one. Tuning each location independently keeps total quota consumption proportional to actual activity rather than the worst-case assumption applied uniformly.

### The Problem

```luau
-- Using the default policy for everything — even data that almost never changes.
local StatsDefinition     = Diary.RegisterTemplate("PlayerStats",     { coins = 0 })
local SettingsDefinition  = Diary.RegisterTemplate("PlayerSettings",  { music = true })
local InventoryDefinition = Diary.RegisterTemplate("PlayerInventory", { items = {} })
-- All three locations save at the same 15-second interval, regardless of how
-- often each one actually changes. Settings quotas are wasted.
```

**Why this is wrong:** Every location consuming the same cadence means low-activity locations eat into the quota headroom that high-activity ones need during traffic spikes. The default is a conservative fallback, not a recommended steady-state.

### The Solution

```luau
-- Economy data changes constantly — save promptly and keep in fast storage a long time.
local StatsDefinition = Diary.RegisterTemplate("PlayerStats", {
    coins = 0,
    level = 1,
}, {
    ____ActiveTTL          = 86400,  -- 24 hours in fast storage
    ____IdleThreshold      = 30,
    ____IntervalMultiplier = 2,
})

-- Settings almost never change — save infrequently and keep TTLs modest.
local SettingsDefinition = Diary.RegisterTemplate("PlayerSettings", {
    music = true,
    sfx   = true,
}, {
    ____ActiveTTL          = 43200,
    ____IdleThreshold      = 300,    -- 5 minutes before considered idle
    ____IntervalMultiplier = 8,      -- save at 8× the base interval when idle
})

-- Inventory changes in bursts — moderate policy, shorter idle threshold.
local InventoryDefinition = Diary.RegisterTemplate("PlayerInventory", {
    items = {},
}, {
    ____ActiveTTL          = 86400,
    ____IdleThreshold      = 60,
    ____IntervalMultiplier = 3,
})
```

**Why this works:** Each location now saves at a cadence that matches how it actually behaves in gameplay. The quota freed from infrequently-changing locations is available for your game's own DataStore and MemoryStore calls, keeping total consumption well within the 38–40% target that Diary is designed to maintain.

---

## 12. Only Interact With Diary's Main Surface APIs — Avoid the Low-Level Sub-Modules

Diary exposes three internal sub-modules — `DataStore`, `MemoryStore`, and `DependentServices` — as properties of the main table. These exist so that the sub-systems can communicate with each other during initialisation and dependency injection. They are not intended to be called from game code.

### The Problem

```luau
local Diary = require(path.Diary)

-- Directly calling the DataStore sub-module to save a player's data.
Diary.DataStore.SaveData(player.UserId, "PlayerStats", stats)

-- Directly reading from MemoryStore, bypassing the in-memory cache.
local raw = Diary.MemoryStore.FetchData(player.UserId, "PlayerStats", { ____MapType = true })
```

**Why this is wrong:** The high-level APIs maintain a precise set of guarantees: the session lease is checked, the in-memory copy is the source of truth, the dirty flag is respected, debounce windows are enforced, and the write queue is used when appropriate. Calling the sub-modules directly bypasses every one of those safeguards. The result is desynchronisation between what Diary believes the current data state is and what is actually written to storage, potential double-writes that violate rate limits, and data loss if the sub-module's return value is used to mutate state that Diary is separately tracking.

### The Solution

```luau
local Diary = require(path.Diary)

-- Always use the main surface APIs — they are the safe, complete interface.
local stats = Diary.FetchData(player.UserId, DiaryTemplates.PlayerStats())
stats.coins += 100
Diary.MarkDirty(player.UserId, "PlayerStats")

-- For explicit saves, use SaveData — it routes correctly through all safeguards.
Diary.SaveData(player.UserId, "PlayerStats", true)
```

**Why this works:** The main surface APIs are the complete, safe interface to the framework. They encapsulate every decision about when, how, and where to write — so your code is insulated from the complexity of the storage layer entirely. The sub-modules are an implementation detail; treat them as if they do not exist.

---

!!! success "Pro Tip"
    Think of Diary's read path and write path as completely independent. Reading (`FetchData`) is always instant and never touches storage. Writing (`MarkDirty`, `SaveData`) schedules work that the framework manages on your behalf. This separation means you can read data as frequently as you like — in Heartbeat, in RemoteFunction handlers, anywhere — with zero I/O cost. Only writes have budget implications.
