# Relay Best Practices

This guide covers the recommended patterns for working with Relay. Each practice explains not just what to do, but why — grounded in how the library behaves from a developer's perspective.

---

## 1. Decouple Systems Using String IDs, Never Pass Signal Objects

The purpose of Relay's global registry is to let completely independent scripts communicate without importing each other. When you pass a `SignalObject` as a function argument or module return value, you recreate the exact coupling that Relay is designed to eliminate.

### The Problem

```luau
-- ModuleScript: CombatManager
local combatSignal = Relay.Create("Combat_BossKilled")
return {
    getBossKilledSignal = function()
        return combatSignal
    end
}

-- ModuleScript: QuestSystem
local CombatManager = require(path.to.CombatManager)
local signal = CombatManager.getBossKilledSignal() -- QuestSystem now depends on CombatManager
signal:Connect(awardQuestXP)
```

**Why this is wrong:** QuestSystem now has a hard dependency on CombatManager. If CombatManager is refactored, renamed, or removed, QuestSystem breaks. You've also lost the ability to hot-swap either system independently.

### The Solution

```luau
-- ModuleScript: CombatManager
Relay.Create("Combat_BossKilled"):Fire(bossName, reward)
-- CombatManager doesn't know and doesn't care who is listening.

-- ModuleScript: QuestSystem
Relay.Create("Combat_BossKilled"):Connect(function(bossName, reward)
    awardQuestXP(bossName, reward)
end)
-- QuestSystem doesn't know and doesn't care who is firing.
```

**Why this works:** Both scripts access the same `SignalObject` through the registry by ID. Neither requires, imports, or references the other. You can delete, reload, or swap either system without touching the other.

---

## 2. Always Bind Connection Lifetimes to Their Target Object

Every connection that modifies or reads from an object that can be destroyed must be bound to that object's lifetime. Leaving connections alive after their target is destroyed wastes memory, creates phantom callbacks that fire on stale data, and can cause hard-to-trace errors.

### The Problem

```luau
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        local connection = Relay.Create("GlobalTick"):Connect(function()
            healPlayer(character) -- character may already be destroyed
        end)

        -- connection is never stored. It will never be disconnected.
        -- Every time GlobalTick fires, it tries to access a potentially dead character.
        -- After the player leaves, this connection keeps the character in memory.
    end)
end)
```

**Why this is wrong:** The connection outlives the character. After the character model is destroyed and the player respawns, the old callback still fires — calling `healPlayer` on a destroyed `Model`. Over a session with many respawns, this creates an ever-growing list of dead callbacks on `GlobalTick`.

### The Solution

```luau
Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function(character)
        Relay.Create("GlobalTick"):Connect(function()
            healPlayer(character)
        end):BindTo(character)
        -- When the character model is destroyed, Reaper automatically disconnects
        -- this listener. No memory retained. No phantom callbacks.
    end)
end)
```

**Why this works:** `:BindTo(character)` registers the connection with Reaper's tracker. When `character` leaves the data model, Reaper fires cleanup and disconnects this listener automatically. `GlobalTick` loses exactly one listener and, if that was the last one, `OnAbandoned` fires to signal any background loops that they can stop.

---

## 3. Use OnAbandoned to Sleep Expensive Background Processes

Running heavy calculations every frame or every second when no code is consuming the results wastes server CPU. Relay's `OnAbandoned` companion signal is the idiomatic mechanism for pausing loops when the last listener drops.

### The Problem

```luau
-- A loop fires every second regardless of whether anything is listening.
task.spawn(function()
    while true do
        local enemies = doExpensivePathfindingSweep()
        Relay.Create("AI_EnemyMap"):Fire(enemies)
        task.wait(1)
    end
end)
-- If no player equips the minimap, or all players leave, this loop runs forever.
-- The pathfinding sweep runs every tick, every second, burning CPU for nothing.
```

**Why this is wrong:** When no code is listening, calling `:Fire()` iterates zero connections and the results are discarded. The sweep runs, the fire completes immediately against an empty list, and the entire cycle is wasted. This repeats every second indefinitely.

### The Solution

```luau
local aiSignal   = Relay.Create("AI_EnemyMap")
local loopActive = false

local function startLoop()
    if loopActive then return end
    loopActive = true
    task.spawn(function()
        while loopActive do
            aiSignal:Fire(doExpensivePathfindingSweep())
            task.wait(1)
        end
    end)
end

aiSignal.Signals.OnAbandoned:Connect(function()
    -- Last listener disconnected. Pause the loop until the next connect.
    loopActive = false
end)
```

**Why this works:** `OnAbandoned` fires in the same moment the last listener disconnects — there is no polling delay. The loop flag is cleared immediately and the background task stops on its next iteration. The next time any script calls `:Connect()` and then `startLoop()`, the loop resumes from scratch.

---

## 4. Use Specific, Namespaced Signal IDs

The global registry is shared across all scripts on the same VM context. A generic signal name is a collision waiting to happen, and collisions cause subtle, hard-to-debug cross-system interference.

### The Problem

```luau
-- DungeonSystem
Relay.Create("Update"):Fire(dungeonState)

-- WeatherSystem (a completely different team wrote this)
Relay.Create("Update"):Connect(function(data)
    -- Receives dungeonState unexpectedly. Errors or silently corrupts weather logic.
    applyWeather(data.temperature, data.wind)
end)
```

**Why this is wrong:** Both systems share `"Update"`. The registry returns the same `SignalObject` to both. WeatherSystem's callback now fires every time DungeonSystem fires its update, receiving data it cannot interpret.

### The Solution

```luau
-- DungeonSystem
Relay.Create("DungeonSystem_StateUpdate"):Fire(dungeonState)

-- WeatherSystem
Relay.Create("WeatherSystem_ConditionsChanged"):Connect(applyWeather)
-- Completely isolated. No cross-contamination possible.
```

**Why this works:** Two different string IDs are always two different `SignalObject` entries. The convention is `SystemName_EventName` — include both the owning system and the event noun. For instanced systems (multiple dungeons, multiple players), include a unique identifier: `"DungeonSystem_" .. dungeonId .. "_BossKilled"`.

---

## 5. Destroy Signals When Their Parent System Shuts Down

The automatic garbage collection path handles abandoned signals eventually, but "eventually" is not "immediately." If a game phase ends and you want instant memory reclamation and connection cleanup, call `:Destroy()` explicitly.

### The Problem

```luau
-- A new signal is created for each minigame round.
local roundSignal = Relay.Create("MiniGame_Round_" .. roundId)
roundSignal:Connect(onRoundEvent)

-- Round ends. Nothing is cleaned up.
-- The signal stays in the registry until the VM decides to collect it.
-- Coroutines yielded on this signal stay suspended indefinitely.
```

**Why this is wrong:** Coroutines that called `:Wait()` on this signal hold a strong reference to it, preventing automatic collection. Even without active waiters, connected callbacks keep their closures alive. Memory from a "finished" round persists until the VM's garbage collector decides to act — which may be many rounds later.

### The Solution

```luau
local roundSignal = Relay.Create("MiniGame_Round_" .. roundId)
roundSignal:Connect(onRoundEvent)

-- Round ends:
roundSignal:Destroy()
-- All connections are cancelled, all waiting coroutines are resumed immediately
-- (receiving no return values), and the signal is removed from the registry.
-- Memory from this round is released as soon as all local references are dropped.
```

**Why this works:** `:Destroy()` does not wait for the garbage collector. It immediately cancels every connection, resumes every suspended coroutine (so they are no longer blocking cleanup), and removes the signal from the registry. Once the last local variable pointing to `roundSignal` goes out of scope, the entire signal and its associated memory is freed.

---

## 6. Call Relay.Inject Before Any Game Logic Runs

`:BindTo()` requires Reaper to be injected before it is called. If injection happens after some systems have already called `:BindTo()`, those early calls throw in Studio and silently do nothing in production — the connection is never bound and will leak.

### The Problem

```luau
-- ServerScriptService/Main.server.lua
local CombatSystem = require(CombatSystem) -- CombatSystem calls :BindTo() in its constructor
local Relay        = require(Relay)
local Reaper       = require(Reaper)

Relay.Inject("Reaper", Reaper) -- Too late. CombatSystem already tried to use :BindTo().
```

**Why this is wrong:** Relay has no knowledge of Reaper at the moment CombatSystem initialises. In Studio, the `:BindTo()` call throws immediately. In production, it returns silently without setting up any lifetime tracking — the connection is never bound and will persist indefinitely.

### The Solution

```luau
-- ServerScriptService/Main.server.lua
-- Inject dependencies FIRST, before requiring any system that uses them.
local Relay        = require(Relay)
local Reaper       = require(Reaper)
local Assignment   = require(Assignment)

Relay.Inject("Reaper", Reaper)
Relay.Inject("Assignment", Assignment)

-- Now safe to initialise any system that uses :BindTo().
local CombatSystem = require(CombatSystem)
local QuestSystem  = require(QuestSystem)
```

**Why this works:** `Relay.Inject()` takes effect immediately and synchronously. All subsequent calls to `:BindTo()` anywhere in the same server context will find Reaper ready, regardless of which script makes the call.

---

## 7. Batch High-Frequency Fires — Never Fire Per Frame

Every call to `:Fire()` carries two costs that scale with the number of active listeners: spawning one coroutine per listener to deliver the arguments, and performing a pass over the connection list afterward to evict any listeners that disconnected during delivery. This cleanup pass is what keeps Relay free of the signal-skipping bug — where a connection that removes itself mid-fire would otherwise cause subsequent listeners in the same cycle to be silently skipped. The trade-off is that the pass runs on every single fire, every time.

At low fire rates (once per second, once per event) this cost is negligible. At high fire rates — particularly `RunService.Heartbeat`, which fires ~60 times per second — the cost multiplies. A signal with 10 listeners firing every frame runs its cleanup pass 60 times per second against all 10 entries, and spawns 600 coroutines per second. Add more signals or more listeners and the pressure compounds quickly.

The solution is batching: instead of firing once per event as events occur at high frequency, accumulate events into a shared state table during the interval and fire once at the end of it with the whole batch. Listeners receive everything in one delivery at a fraction of the coroutine and cleanup cost.

### The Problem

```luau
-- Every projectile that hits something fires its own signal, every frame.
-- In a busy combat scene this fires dozens of times per frame across many signals.
RunService.Heartbeat:Connect(function(dt)
    for _, hit in pendingHits do
        -- One fire per hit: one coroutine spawned per listener, one cleanup pass per fire.
        -- With 8 listeners and 30 hits per frame: 240 coroutines + 240 cleanup passes per frame.
        Relay.Create("Combat_HitRegistered"):Fire(hit.attacker, hit.target, hit.damage)
    end
    table.clear(pendingHits)
end)
```

**Why this is wrong:** The per-fire overhead scales with both the number of hits and the number of listeners. In a light scene this is invisible; in a heavy combat scene with many projectiles and many listening systems (UI, audio, quest tracking, kill feed, analytics), the scheduler is hit with a burst of coroutine allocations and cleanup work every single frame. The work is proportional to `fires × listeners`, not just `fires`.

### The Solution

```luau
-- Accumulate all hits that occurred this frame into one table.
-- Fire once per frame with the whole batch — one coroutine per listener, one cleanup pass, full stop.
RunService.Heartbeat:Connect(function(dt)
    if #pendingHits == 0 then return end -- Skip the fire entirely if nothing happened.

    -- All listeners receive the complete batch in a single delivery.
    Relay.Create("Combat_HitsProcessed"):Fire(pendingHits, dt)
    table.clear(pendingHits)
end)

-- Listeners unpack the batch themselves:
Relay.Create("Combat_HitsProcessed"):Connect(function(hits, dt)
    for _, hit in hits do
        updateHealthBar(hit.target, hit.damage)
    end
end)

Relay.Create("Combat_HitsProcessed"):Connect(function(hits, dt)
    for _, hit in hits do
        playHitSound(hit.target, hit.damage)
    end
end)
```

**Why this works:** Regardless of how many hits occurred in the frame, `:Fire()` is called exactly once. The cleanup pass runs once. Each listener spawns one coroutine — not one per hit. The listeners themselves iterate the batch, which is plain Luau table iteration with no per-iteration scheduler involvement. As listener count grows, cost grows linearly with listeners, not with `listeners × events`.

!!! tip "Batch More Than Just Per-Frame Work"
    The batching principle applies to any signal that could fire more than a few times per second: projectile collisions, input state changes, inventory delta updates, network replication ticks, or animation frame events. As a rule of thumb — if a signal could fire more than 10 times per second under realistic load, it is a batching candidate. Design the signal to carry a table of events rather than one argument set per event.

!!! tip "Skip the Fire When the Batch Is Empty"
    In the batched pattern, always guard against firing with an empty payload — an early `if #batch == 0 then return end` before the `:Fire()` call costs nothing and avoids waking listeners unnecessarily on frames where nothing happened. This is especially valuable for signals that are only busy during active combat or interaction and idle the rest of the time.

---

!!! success "Pro Tip: Avoid Firing on RunService.Heartbeat"
    Relay spawns each callback in its own independent coroutine every time `:Fire()` is called. Calling `:Fire()` on `RunService.Heartbeat` with 20 active connections creates 20 new coroutines every ~1/60th of a second — roughly 1,200 coroutines per second. Under load, this strains the scheduler significantly. If you need per-frame signal behaviour, use a single `Heartbeat` callback that reads from a shared state table, rather than routing each frame through a Relay signal to multiple listeners.
