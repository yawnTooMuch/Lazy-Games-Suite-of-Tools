# Relay Examples

This page demonstrates every API and method in the Relay library through practical, scenario-based examples. Each scenario illustrates a distinct usage pattern with inline comments explaining what happens at runtime.

---

## Global Relay APIs

### Relay.Inject

Registers an external library into Relay. Call this before any system that relies on `:BindTo()` or a custom scheduler.

**Scenario A — Injecting both dependencies at startup**
```luau
local Relay      = require(path.to.Relay)
local Reaper     = require(path.to.Reaper)
local Assignment = require(path.to.Assignment)

-- Reaper is now linked. :BindTo() will work on all signals and connections.
Relay.Inject("Reaper", Reaper)

-- Relay's internal scheduler now routes through Assignment instead of the native task library.
Relay.Inject("Assignment", Assignment)
```

**Scenario B — Injecting only Reaper (Assignment optional)**
```luau
local Relay  = require(path.to.Relay)
local Reaper = require(path.to.Reaper)

Relay.Inject("Reaper", Reaper)
-- Relay works correctly. :BindTo() is now available.
-- Native task.spawn, task.defer, etc. are still used for scheduling.
```

**Scenario C — Using :BindTo() without injecting Reaper (Studio error path)**
```luau
local Relay  = require(path.to.Relay)
local signal = Relay.Create("MySignal")

-- In Studio: throws a descriptive error asking you to inject Reaper first.
-- In production: no error, but the bind is silently skipped — the connection will leak.
signal:BindTo(workspace.SomePart)
```

---

### Relay.Create

Creates a new signal or retrieves the existing one for a given ID. The registry is global — any script calling `Create` with the same ID gets the same object.

**Scenario A — Creating a new signal**
```luau
local combatSignal = Relay.Create("Combat_PlayerDamaged")
-- A new signal is created and stored in the global registry under "Combat_PlayerDamaged".
-- combatSignal now has :Connect(), :Fire(), :Wait(), and all other methods available.
```

**Scenario B — Retrieving an existing signal across scripts**
```luau
-- In Script A (ServerScriptService/CombatSystem):
local signal = Relay.Create("Combat_PlayerDamaged")
signal:Fire(player, 50)

-- In Script B (ServerScriptService/QuestSystem):
local signal = Relay.Create("Combat_PlayerDamaged")
-- Relay finds "Combat_PlayerDamaged" already registered.
-- Returns the same signal — no new object is created.
signal:Connect(function(player, damage)
    -- This fires when CombatSystem fires the signal.
    updateQuestProgress(player, damage)
end)
```

**Scenario C — Signal ID collision (intentional registry sharing)**
```luau
-- Both calls return the exact same SignalObject reference.
local a = Relay.Create("SharedEvent")
local b = Relay.Create("SharedEvent")

print(a == b) -- true
```

---

### Relay.Exists

Returns whether a signal is currently alive in the registry. Useful for system readiness checks.

**Scenario A — Checking before acting**
```luau
if Relay.Exists("Combat_PlayerDamaged") then
    -- The signal is live in the registry right now.
    local signal = Relay.Create("Combat_PlayerDamaged")
    signal:Connect(onDamage)
end
-- If Exists() returns false, nobody has created this signal yet.
```

**Scenario B — Using Exists as a system readiness check**
```luau
-- A subsystem checks if a coordinator signal has been established
-- before trying to hook into it.
if not Relay.Exists("DungeonSystem_Ready") then
    warn("DungeonSystem has not initialised yet. Skipping hook.")
    return
end

Relay.Create("DungeonSystem_Ready"):Once(onDungeonReady)
```

---

## SignalObject Methods

### Connect

Registers a persistent callback that runs every time the signal fires, until explicitly disconnected.

**Scenario A — Persistent listener**
```luau
local signal = Relay.Create("Player_Scored")

local connection = signal:Connect(function(player, points)
    -- Executes every time "Player_Scored" is fired, for the lifetime of this connection.
    print(player.Name .. " scored " .. points .. " points!")
end)

-- Later, when cleanup is needed:
connection:Disconnect()
-- The callback will no longer execute on future fires.
```

**Scenario B — Connecting multiple independent listeners to the same signal**
```luau
local signal = Relay.Create("Round_Started")

-- Listener 1: UI system updates the scoreboard
signal:Connect(function()
    scoreboardUI.Visible = true
end)

-- Listener 2: AI system spawns enemies
signal:Connect(function()
    spawnEnemyWave()
end)

-- When signal:Fire() is called, BOTH callbacks run in their own coroutines.
-- Neither blocks the other.
```

---

### Once

Registers a one-shot listener. The connection is severed before the callback runs, so the callback fires exactly once no matter how many times the signal fires afterward.

**Scenario A — Observing the disconnect-before-callback order**
```luau
local connection
connection = Relay.Create("DataStore_Loaded"):Once(function(data)
    -- By the time this line runs, connection is already disconnected.
    -- This is safe to call and will return false.
    print(connection:IsConnected()) -- false

    -- Connecting again from inside the callback creates a fresh listener —
    -- not a conflict with the one that just finished.
    Relay.Create("DataStore_Loaded"):Connect(onSubsequentLoad)

    initializeUI(data)
end)
```

**Scenario B — Early cancellation before fire**
```luau
local connection = Relay.Create("Match_Ended"):Once(function()
    showEndScreen()
end)

-- The match was cancelled before it ended. Cancel the one-shot listener too.
if matchCancelled then
    connection:Disconnect()
    -- showEndScreen will never be called, even if "Match_Ended" fires later.
end
```

---

### Wait

Suspends the calling coroutine until the signal fires. Returns whatever arguments were passed to `:Fire()`.

**Scenario A — Waiting for a signal in a task coroutine**
```luau
task.spawn(function()
    print("Waiting for the boss to spawn...")

    -- This coroutine is suspended here. Other code continues running normally.
    local bossModel, bossName = Relay.Create("Boss_Spawned"):Wait()

    -- Execution resumes when Fire("Boss_Spawned", model, name) is called elsewhere.
    print("Boss spawned: " .. bossName)
    trackBossHealth(bossModel)
end)
```

**Scenario B — Signal destroyed before it fires**
```luau
task.spawn(function()
    local a, b, c = Relay.Create("Countdown_Tick"):Wait()
    -- If the signal is Destroy()ed before it ever fires,
    -- this coroutine is resumed immediately with no arguments.
    print(a, b, c) -- nil  nil  nil
end)

-- Somewhere else, the signal is destroyed early (e.g., round cancelled):
Relay.Create("Countdown_Tick"):Destroy()
```

---

### Fire

Delivers arguments to all waiting coroutines and active connection callbacks. Each recipient runs in its own independent coroutine.

**Scenario A — Firing with multiple arguments**
```luau
local signal = Relay.Create("Enemy_Died")

signal:Connect(function(enemyName, killer, reward)
    print(enemyName .. " was killed by " .. killer.Name .. " for " .. reward .. " XP")
end)

-- All connected callbacks and waiting coroutines receive all three arguments.
signal:Fire("Goblin", game.Players.BedQuest, 100)
```

**Scenario B — Firing with no arguments**
```luau
local signal = Relay.Create("Shop_Closed")

signal:Connect(function()
    closeShopUI()
end)

-- Firing with no arguments is valid. Callbacks simply receive nothing.
signal:Fire()
```

**Scenario C — Firing in Studio after Destroy (error path)**
```luau
local signal = Relay.Create("Temp_Signal")
signal:Destroy()

-- In Studio: throws a descriptive error.
-- In production: silently does nothing.
signal:Fire("data")
```

**Scenario D — Connecting mid-fire (deferral behaviour)**
```luau
local signal = Relay.Create("Phase_Changed")
local secondConnection

signal:Connect(function(phase)
    print("First listener: phase =", phase)

    -- This new connection is registered during an active fire cycle.
    -- It will NOT be called for this fire — only for the next one.
    secondConnection = signal:Connect(function(p)
        print("Second listener: phase =", p)
    end)
end)

signal:Fire("A")
-- Prints: "First listener: phase = A"
-- "Second listener" does NOT print here.

signal:Fire("B")
-- Prints: "First listener: phase = B"
-- Prints: "Second listener: phase = B"
```

---

### DisconnectAll

Cancels every active listener on the signal in a single call. The signal itself remains usable — new connections can be added afterward.

**Scenario A — Clearing all listeners at the end of a game phase**
```luau
local roundSignal = Relay.Create("Round_Event")

roundSignal:Connect(onPlayerScored)
roundSignal:Connect(onEnemyKilled)
roundSignal:Connect(updateLeaderboard)

-- Round ends. Remove all listeners in one call.
roundSignal:DisconnectAll()
-- All three callbacks are cancelled. The signal still exists and accepts new connections.
-- OnAbandoned fires here because the listener count reached zero.
```

**Scenario B — Triggering OnAbandoned intentionally**
```luau
local activeSignal = Relay.Create("Zone_Active")

activeSignal.Signals.OnAbandoned:Connect(function()
    -- This fires because DisconnectAll() was called below.
    shutdownZoneLoop()
end)

activeSignal:Connect(handleZoneEvent)
activeSignal:DisconnectAll()
-- handleZoneEvent is disconnected, then OnAbandoned fires → shutdownZoneLoop() runs.
```

---

### GetConnectionCount

Returns how many live listeners are currently attached to the signal. Useful for skipping expensive work when nobody is listening.

**Scenario A — Logging listener count for debugging**
```luau
local signal = Relay.Create("GlobalTick")

signal:Connect(updateLeaderboard)
signal:Connect(tickAI)
signal:Connect(tickWeather)

print(signal:GetConnectionCount()) -- 3

signal:DisconnectAll()

print(signal:GetConnectionCount()) -- 0
```

**Scenario B — Conditionally firing only when listeners exist**
```luau
local radarSignal = Relay.Create("RadarUpdate")

if radarSignal:GetConnectionCount() > 0 then
    -- At least one script is listening — the result of this call will be used.
    radarSignal:Fire(getNearbyEnemies())
else
    -- Nobody is listening. Skip the expensive work entirely.
    print("Radar has no active listeners. Skipping update.")
end
```

---

### Destroy

Permanently removes the signal from the registry, cancels all connections, and unblocks any coroutines suspended on `:Wait()`.

**Scenario A — Destroying a signal at the end of a match**
```luau
local matchSignal = Relay.Create("Match_1_Event")

matchSignal:Connect(onMatchEvent)

-- Match ends. Fully remove the signal and release all associated resources.
matchSignal:Destroy()
-- "Match_1_Event" is no longer in the registry.
-- Any coroutines waiting on this signal are resumed immediately with nil arguments.
-- The OnAbandoned companion is also destroyed.

-- A fresh signal can be created for the next match:
local newMatchSignal = Relay.Create("Match_2_Event")
```

**Scenario B — Calling Destroy twice (idempotent)**
```luau
local signal = Relay.Create("OneTime_Event")
signal:Destroy()

-- Destroy is safe to call more than once. The second call is silently ignored.
signal:Destroy()
```

---

### BindTo (Signal)

Ties the signal's lifetime to a Reaper-tracked object. When the object is destroyed, the signal is destroyed automatically.

**Scenario A — Binding a signal to a model's lifetime**
```luau
local dungeonModel  = workspace:WaitForChild("Dungeon_Instance_1")
local dungeonSignal = Relay.Create("Dungeon_1_BossKilled")

-- When Reaper detects that dungeonModel has been destroyed,
-- Relay automatically calls :Destroy() on this signal.
dungeonSignal:BindTo(dungeonModel)
```

**Scenario B — Chaining BindTo with Create**
```luau
-- Create the signal and bind it to the map folder in a single expression.
Relay.Create("Map_Hazard_" .. mapId):BindTo(mapFolder)
-- The signal is automatically destroyed when mapFolder is removed.
```

---

## ConnectionObject Methods

### Disconnect

Severs the connection from its parent signal. Safe to call multiple times.

**Scenario A — Manual cleanup**
```luau
local connection = Relay.Create("Player_Chat"):Connect(function(msg)
    filterProfanity(msg)
end)

-- Player muted. Stop the listener.
connection:Disconnect()

-- Safe to call again — already disconnected, nothing happens.
connection:Disconnect()
```

**Scenario B — Disconnecting inside the callback**
```luau
local connection
connection = Relay.Create("Reward_Ready"):Connect(function(item)
    -- Disconnect before doing work to prevent double-triggers on re-entrant fires.
    connection:Disconnect()
    givePlayerItem(item)
end)
-- This is equivalent to :Once(), but gives you explicit control over
-- when the disconnect happens relative to the rest of the callback logic.
```

---

### IsConnected

Returns whether this specific connection handle is still active.

**Scenario A — Guarding against stale connection references**
```luau
local connection = Relay.Create("Damage_Event"):Connect(onDamage)

-- Some time later, somewhere in the codebase:
if connection:IsConnected() then
    -- Still active. Safe to disconnect or inspect.
    connection:Disconnect()
end
```

**Scenario B — Polling connection state in a loop**
```luau
task.spawn(function()
    local connection = Relay.Create("Heartbeat"):Connect(onHeartbeat)

    while connection:IsConnected() do
        -- As long as this listener is alive, do some bookkeeping.
        task.wait(5)
    end

    print("Heartbeat listener was disconnected. Exiting poll loop.")
end)
```

---

### BindTo (Connection)

Ties the connection's lifetime to a Reaper-tracked object. When the object is destroyed, the connection is disconnected automatically.

**Scenario A — Binding a UI connection to the character**
```luau
local character = player.Character or player.CharacterAdded:Wait()

-- When the character is removed from the game, this connection is
-- disconnected automatically — no manual cleanup needed.
Relay.Create("Combat_DamageTaken"):Connect(function(amount)
    updateHealthBar(amount)
end):BindTo(character)
```

**Scenario B — Binding multiple connections to the same target**
```luau
local character = player.Character

Relay.Create("Round_Tick"):Connect(function()
    healOverTime(character)
end):BindTo(character) -- Disconnects when character is destroyed

Relay.Create("Zone_Entered"):Connect(function(zone)
    applyZoneEffect(character, zone)
end):BindTo(character) -- Also disconnects when character is destroyed

-- No manual cleanup needed. Both connections are tied to the character's lifetime.
```

---

## Miscellaneous

### SignalObject.Signals.OnAbandoned

A companion signal that fires automatically when the parent signal's listener count drops to zero. The primary tool for pausing background work when it has no audience.

**Scenario A — Pausing a background loop when no listeners remain**
```luau
local radarSignal  = Relay.Create("RadarPing")
local radarRunning = false

local function startRadar()
    if radarRunning then return end
    radarRunning = true
    task.spawn(function()
        while radarRunning do
            radarSignal:Fire(getNearbyEnemies())
            task.wait(1)
        end
    end)
end

radarSignal.Signals.OnAbandoned:Connect(function()
    -- The last listener disconnected. Stop the expensive loop immediately.
    radarRunning = false
end)

-- When a player equips the radar item:
local conn = radarSignal:Connect(updateRadarUI)
startRadar()

-- When the player unequips it (and it was the only listener):
conn:Disconnect()
-- Listener count hits zero → OnAbandoned fires → radarRunning = false → loop exits.
```

**Scenario B — One-shot teardown when a signal is abandoned**
```luau
Relay.Create("Minigame_Timer").Signals.OnAbandoned:Once(function()
    -- Fires the first time the listener count reaches zero.
    -- The Once connection then removes itself automatically.
    cleanupMinigameState()
end)
```
