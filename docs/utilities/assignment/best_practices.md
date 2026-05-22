# Assignment Best Practices

---

## 1. Always Store Handles When Cancellation Is Possible

Any scheduled call that might need to be stopped requires you to keep its `Handle`. Once you discard it, there is no way to cancel the work — Assignment has no lookup by function reference.

### The Problem

```luau
-- Handle is thrown away immediately; the callback has no off switch
Assignment.Delay(5, function()
    destroyTower(tower) -- fires even if the tower is already gone
end)

tower.Destroying:Connect(function()
    -- Nothing to cancel here — destroyTower will run against a dead object
end)
```

**Why this is wrong:** With no handle in scope, there is nothing to call `Break` on. The scheduled work runs unconditionally when its time comes, regardless of whether the target still exists.

### The Solution

```luau
local destroyHandle = Assignment.Delay(5, function()
    destroyTower(tower)
end)

tower.Destroying:Connect(function()
    destroyHandle:Break() -- tells Assignment to silently skip this when the time comes
end)
```

**Why this works:** `Handle:Break()` marks the work as cancelled. When the scheduled time arrives, Assignment sees the flag and discards the task without running it. Calling `Break` early costs nothing and is always safe.

---

## 2. Avoid Using the Native `task` Library Inside Assignment-Managed Code

Assignment tracks all of the work it schedules so it can cancel it, throttle it, and migrate it on shutdown. When you call `task.*` functions directly from inside an Assignment-managed thread, that work steps outside Assignment's awareness entirely. The two schedulers end up sharing the same thread without either having the complete picture, which produces subtle bugs that are hard to reproduce.

### The Problem

```luau
Assignment.Spawn(function()
    task.wait(2)           -- Assignment loses track of this thread for 2 seconds;
                           -- cancellation and shutdown migration won't reach it here
    doWork()

    task.spawn(doMoreWork) -- this new thread is invisible to Assignment;
                           -- it won't be throttled, cancelled, or migrated
end)
```

**Why this is wrong:** When `task.wait` is called inside a thread Assignment spawned, the engine takes ownership of that thread for the duration of the wait. During that window, `Assignment.Cancel` cannot reach it — it simply finds nothing to cancel. When the thread wakes up it continues on the engine's terms, not Assignment's. Any work spawned with `task.spawn` inside an Assignment thread is similarly invisible: it bypasses throttling, will not be cancelled when its parent handle is broken, and will not be handed off safely on server shutdown.

### The Solution

```luau
Assignment.Spawn(function()
    Assignment.Wait(2)       -- Assignment keeps full track of this thread
    doWork()

    Assignment.Spawn(doMoreWork) -- runs through Assignment; tracked, throttled, cancellable
end)
```

**Why this works:** `Assignment.Wait` keeps the thread fully within Assignment's scheduling. When the wait is over, Assignment wakes it up correctly with the real elapsed time. Any new work dispatched via `Assignment.Spawn` stays inside Assignment's awareness, so cancellation and shutdown work as expected.

!!! info "`Assignment.Wait` Is Always the Right Yield"
    `Assignment.Wait` is context-aware — it does the right thing whether you are inside a pooled thread or an isolated thread. You never need to think about which one to use. Just call `Assignment.Wait` everywhere inside Assignment-managed code.

---

## 3. Use Isolated Variants for Long-Yielding Work — Not as a General Default

The Isolated Family (`SpawnIsolated`, `DeferIsolated`, `DelayIsolated`) is designed for **absolute control**: it bypasses all of Assignment's throttles, gives you a cancellation token to stop work at any moment, and forces the engine to prioritise your logic immediately. These are powerful properties — but they come with trade-offs that make isolated variants the wrong default for most scheduling work.

### Why This Matters

Think of the Pooled Family as sharing a single diligent worker among all your short tasks. That worker picks up a job, finishes it, and immediately takes the next one. Everything flows smoothly because jobs are short.

Now imagine a job that makes the worker sleep for 30 seconds — waiting on a DataStore call, an HTTP response, or a loop body with a long interval. While that worker sleeps, every other job that comes in has to bring in its own independent resource to get done. If several long-sleeping jobs run at the same time, you end up with a crowd of independent resources all active simultaneously: each one costs memory, and as the crowd grows the engine has to do progressively more work to manage them all, which eventually shows up as CPU pressure and frame drops.

Isolated variants sidestep this entirely. Because they bypass the shared worker and run in their own dedicated engine-managed thread, the regular worker stays free at all times and short jobs are handled efficiently. The long-sleeping work runs independently without affecting anything else.

### The Problem — Long Work Through the Shared Pool

```luau
-- A 30-second loop keeps the shared worker occupied for the entire sleep.
-- Every Spawn or Delay call during those 30 seconds has to spin up a
-- temporary thread instead of reusing the shared one.
Assignment.Spawn(function()
    while active do
        Assignment.Wait(30)
        syncRemoteData()
    end
end)

-- A DataStore load can take several seconds — same problem.
Assignment.Spawn(function()
    local data = DataService:Load(player)

    applyData(player, data)
end)
```

**Why this is wrong:** Every second the shared worker spends sleeping on a long yield, incoming short work — UI updates, cooldown resets, status effects — has to bring in its own independent resource rather than using the available shared one. Under concurrent load this compounds: independent resources pile up, memory climbs, and the engine's housekeeping work intensifies to keep up.

### The Solution — Isolated Variants for Long-Yielding Tasks

```luau
-- The 30-second loop is isolated. The engine manages it independently.
-- The shared worker is never touched by this task.
Assignment.SpawnIsolated(function()
    while active do
        Assignment.Wait(30) -- works correctly in isolated threads too
        syncRemoteData()
    end
end)

-- The DataStore load runs in its own thread, keeping the pool free.
Assignment.SpawnIsolated(function()
    local data = DataService:Load(player)

    Assignment.Wait(0) -- yield one frame before continuing; lets other work run
    applyData(player, data)
end)

-- Short work still belongs on the standard pool.
Assignment.Spawn(function()
    Assignment.Wait(0.1)
    applyStatusEffect(player, "Stunned")
end)
```

**Why this works:** The long-sleeping threads are owned by the engine from the moment of creation. The shared worker is never involved with them. Short work always finds the shared worker free and ready, so no additional independent resources are created and memory stays stable.

!!! warning "Isolated Calls Return a Cancellation Token, Not a Handle"
    Isolated calls return a raw `thread` token instead of a `Handle`. You cancel them with `Assignment.Cancel(thread)`. There is no `Handle:Break()` equivalent. If you need to cancel work before it runs by holding a `Handle`, use a pooled variant instead.

!!! info "How to Decide"
    A useful rule of thumb: if the work calls into a slow external system (DataStore, HTTP, Messaging Service) or sleeps for more than a second, reach for an isolated variant. If the work is brief — a short calculation, a quick delay, a few frames of waiting — the Pooled Family handles it cleanly with less overhead and full cancellation via `Handle`.

---

## 4. Pass Arguments Directly — Avoid Wrapping Them in a Closure

When you schedule a call with `Delay`, `Defer`, or `Spawn`, you can pass arguments directly after the function. Assignment stores those values alongside the scheduled job and hands them back when the time comes. Wrapping them in a closure instead creates a new allocation every time you schedule work, which adds up under high call volume.

### The Problem

```luau
-- A new anonymous function is allocated for every scheduled call
Assignment.Delay(2, function()
    applyDamage(playerId, damage)
end)
```

**Why this is wrong:** At high call volume — hundreds of projectile impacts per second, for example — each closure is a small allocation. Those allocations accumulate and drive the garbage collector to run more often, showing up as periodic CPU spikes.

### The Solution

```luau
-- Arguments are stored directly alongside the job — no extra allocation
Assignment.Delay(2, applyDamage, playerId, damage)
```

**Why this works:** Assignment stores the arguments directly as part of the scheduled job entry and passes them straight to your function when it fires. No intermediate table or closure is created. For calls with more than four arguments, Assignment still handles it efficiently using a pooled scratch table that is recycled after each call rather than allocated fresh.

---

## 5. Pair Infinite `Repeat` Loops With Explicit Break Logic

`Repeat` with a count of `-1` runs forever. The only way to stop it is to call `Handle:Break()` or `Assignment.Cancel`. If no code path ever does that, the loop runs until the server shuts down — even if it is doing nothing useful.

### The Problem

```luau
-- This loop has no exit path — it will run for the lifetime of the server
Assignment.Repeat(-1, 1, function(i)
    if roundActive then
        updateScoreboard(i)
    end
    -- When roundActive is false this does nothing, but keeps looping regardless
end)
```

**Why this is wrong:** An idle loop that never stops still consumes scheduler time every iteration — it wakes up, runs, waits, and wakes up again indefinitely. Over a long session these costs accumulate quietly.

### The Solution

```luau
local scoreHandle = Assignment.Repeat(-1, 1, function(_, handle)
    if not roundActive then
        handle:Break() -- stops the loop after this iteration

        return
    end

    updateScoreboard()
end)

-- Also stop it from outside when the game mode ends
onGameModeEnd:Connect(function()
    scoreHandle:Break()
end)
```

**Why this works:** `Break` is checked both before the callback runs and immediately after it returns. Calling it inside the callback stops the loop before the next wait period — no partial interval is observed after cancellation.

---

## 6. Cancel Handles on Disconnect and Validate Ephemeral Instances

Any work scheduled against a specific Roblox instance (like a `Player`, `BasePart`, or `Model`) must account for the reality that the object might be destroyed before the timer finishes. If you do not clean up your handles or validate your instances, the scheduled work will fire against a dead object and throw engine errors.

### The Problem

- Trusting the Timer Blindly

```luau
-- Scenario A: Player leaves early
Players.PlayerAdded:Connect(function(player)
	Assignment.Delay(300, function()
		grantDailyBonus(player) -- Error if the player left at second 150!
	end)
end)

-- Scenario B: Part destroyed early by another script
Assignment.Delay(5, function()
	part.Color = Color3.new(1, 0, 0) -- Error if the part was already destroyed!
end)
```

**Why this is wrong:** The scheduling engine blindly respects the timers you set. It has no magical way of knowing that the Roblox instance captured in your closure has been destroyed.

### The Solution 

- Tracking vs. Guarding

Depending on the lifespan of the object, you should either strictly track the handle, or implement a validation guard.

#### Strategy A: Handle Tracking (For Players & Long Timers)
For persistent objects like Players with long-running tasks, rigorously track and break the handles when they disconnect to save CPU cycles.

```luau
local playerHandles: { [Player]: { Assignment.Handle } } = {}

Players.PlayerAdded:Connect(function(player)
	local bonusHandle = Assignment.Delay(300, grantDailyBonus, player)
	
	playerHandles[player] = playerHandles[player] or {}
	table.insert(playerHandles[player], bonusHandle)
end)

Players.PlayerRemoving:Connect(function(player)
	local handles = playerHandles[player]
	
	if handles then
		for _, handle in handles do
			handle:Break() -- The 300-second timer is aborted completely
		end

		playerHandles[player] = nil
	end
end)
```

#### Strategy B: Validation Guards (For Ephemeral VFX & Short Timers)
For highly temporary objects like VFX parts or projectiles, it is often overkill to manually track every single handle in a table. Instead, place a strict validation guard at the top of your delayed callback.

```luau
Assignment.Delay(5, function()
	-- The Guard: If the instance is dead, just silently abort.
	if not part or not part.Parent then return end 

	part.Color = Color3.new(1, 0, 0)
end)
```

**Why this works:** Both solutions protect the engine from evaluating dead memory. Strategy A stops the work from even attempting to execute, making it highly optimal for long-running Player timers. Strategy B lets the short timer execute but safely aborts, making it perfect for chaotic, short-lived instances where strict handle tracking would unnecessarily bloat your source code.

---

## 7. Compile Switch Rules at Startup — Never Inside Loops

`Assignment.Switch` compiles rules into a permanent in-memory decision tree the first time each `:Case():Execute()` chain is evaluated. Calling these builder methods inside a heartbeat loop or a frequently-fired event does not re-route existing rules — it attempts to extend the tree on every call, which corrupts the structure and triggers errors.

### The Problem

```luau
-- This runs every frame — the builder is never meant to run this way
RunService.Heartbeat:Connect(function()
    Assignment.Switch("DamageRouter")
        :Case("Fire")
        :Execute(applyBurnEffect) -- tries to add a rule every frame
    
    local handler = Assignment.Switch("DamageRouter")
        :Match(currentDamageType)

    if handler then 
        handler(player) 
    end
end)
```

**Why this is wrong:** Builder methods are designed to be called a fixed number of times at setup. Running them inside a loop means the engine is continuously re-processing rule definitions it has already compiled, growing the tree and eventually hitting structural limits.

### The Solution

```luau
-- Once at startup or module load: compile all the rules
local DamageRouter = Assignment.Switch("DamageRouter")

    DamageRouter
        :Case("Fire")
        :Execute(applyBurnEffect)

        :Case("Ice")
        :Execute(applyFrostEffect)

        :Case("Lightning")
        :Execute(applyStunEffect)

        :Default(applyPhysicalDamage)

-- Every frame: fetch and match only — zero allocation, zero compilation
RunService.Heartbeat:Connect(function()
    local handler = Assignment.Switch("DamageRouter")
        :Match(currentDamageType)

    if handler then
        handler(player)
    end
end)
```

**Why this works:** Fetching an existing switch by its ID is a single dictionary lookup — it costs nothing and returns the already-compiled tree instantly. All the expensive rule-building happened exactly once, at startup, and the result is reused for the lifetime of the system.

---

## 8. Use the OR Gate for Shared Handlers — Keep Source Code Clean

When multiple conditions should trigger the exact same function, chain the `:Case()` calls together before a single `:Execute()`. Calling `:Execute()` after every individual `:Case()` achieves the same mechanical result in the engine, but it severely bloats your source code and makes maintenance a headache.

### The Problem

```luau
local Router = Assignment.Switch("ElementRouter")

-- Three separate Execute calls for the same function
Router
    :Case("Fire")
    :Execute(applyBurnEffect)

    :Case("Plasma")
    :Execute(applyBurnEffect)

    :Case("Explosion")
    :Execute(applyBurnEffect)
```

**Why this is wrong:** While the engine handles this fine, it bloats your script file and violates the DRY (Don't Repeat Yourself) principle. If you ever need to swap out `applyBurnEffect` for a new function, you are forced to manually track down and update three separate lines of code.

### The Solution

```luau
local Router = Assignment.Switch("ElementRouter")

-- One Execute call covers all three cases — the native OR gate
Router
	:Case("Fire")
	:Case("Plasma")
	:Case("Explosion")

	:Execute(applyBurnEffect) -- A single, centralized binding
```

**Why this works:** By chaining `:Case()` calls without an intervening `:Execute()`, you visually group related logic together. The source code is significantly shorter, highly readable, and perfectly organized. When you need to update the handler for this entire group of elements, you only have to change a single line of code!

---

## 9. Handling "Do Nothing" States: Traditional Workarounds vs. Op.NoOp

When your switch utilizes a strict `:Default()` fallback to catch errors, you will inevitably encounter valid states that simply require *no action* (e.g., an "Idle" state). You must prevent these valid states from triggering the error fallback. 

Without engine support, developers are forced to use unoptimized workarounds to silence the router. `Assignment` provides `Op.NoOp` to solve this natively at the compiler level.

### The Problem

- Traditional Workarounds

**Workaround 1: The Empty Closure (Memory Waste)**
```luau
local StateRouter = Assignment.Switch("PlayerStateRouter")

-- Allocates a useless function in memory just to silence the engine
StateRouter
    :Case("Idle")
    :Execute(function() end) 
```
**Why this is wrong:** You are forcing the Luau VM to allocate a closure in memory, which eventually has to be garbage-collected, just to tell the engine to do nothing. 

**Workaround 2: The Default Bypass (Logic Leaking)**
```luau
StateRouter
    :Default(function(state)
        -- Leaking routing logic into the fallback handler!
        if state == "Idle" or state == "Stunned" then return end 

        warn("Critical: Unknown player state:", state)
    end)
```
**Why this is wrong:** You are completely defeating the purpose of a State Machine. Routing logic (`if state == "Idle"`) belongs in the tree, not hardcoded inside your execution payloads. This makes the code incredibly difficult to maintain.

### The Solution

- Native Op.NoOp

```luau
local StateRouter = Assignment.Switch("PlayerStateRouter")

StateRouter
    :Case("Running")
    :Execute(playRunAnimation)

-- Explicitly tell the compiler this path intentionally does nothing.
    :Case("Idle")
    :Execute(Assignment.Op.NoOp)

    :Default(function(state)
        warn("Critical: Unknown player state:", state)
    end)
```

**Why this works:** `Assignment.Op.NoOp` is a static, compile-time token, it is not a function. When the `:Match()` method hits a `NoOp` token, it safely returns `nil` and explicitly aborts the `:Default()` fallback. 

* **Zero memory allocation** (no useless closures are created).
* **Perfect logic isolation** (your Default fallback stays clean).
* **Clear developer intent** (anyone reading your code knows you intentionally ignored this state).

---

## 10. Use `Op.AND` to Distribute Shared Conditions — Don't Hardcode Duplicates

When multiple branches (an OR pool) all require the exact same follow-up condition, `Op.AND` allows you to mathematically distribute that shared condition across the entire pool in a single pass. Hardcoding the paths separately forces the JIT compiler to parse redundant chains and scatters your logic across multiple bindings.

### The Problem

```luau
local AbilityRouter = Assignment.Switch("AbilityRouter")

-- The "Empowered" requirement is manually built for every element
AbilityRouter
	:Case("Fire", Assignment.Op.AND)
	:Case("Empowered")
	:Execute(handleEmpoweredElement)

	:Case("Ice", Assignment.Op.AND)
	:Case("Empowered")
	:Execute(handleEmpoweredElement)

	:Case("Lightning", Assignment.Op.AND)
	:Case("Empowered")
	:Execute(handleEmpoweredElement)
```

**Why this is wrong:** While this creates the correct memory tree, it bloats your source code and forces you to bind the `handleEmpoweredElement` execution pointer three separate times. If you ever want to add `"Earth"` or change the handler, you must manually update multiple isolated blocks of code. 

### The Solution

```luau
local AbilityRouter = Assignment.Switch("AbilityRouter")

-- Collect the elements into an OR pool, seal it, and distribute the condition.
AbilityRouter
	:Case("Fire")                           -- Open (Added to pending queue)
	:Case("Ice")                            -- Open (Added to pending queue)
	:Case("Lightning", Assignment.Op.AND)   -- Sealed! Wraps the entire pending queue.
	:Case("Empowered")                      -- Distributed to all three simultaneously
	:Execute(handleEmpoweredElement)        -- ONE binding shared across all three paths
```

**Why this works:** By leaving Fire and Ice open, they collect in a pending queue. Placing `Op.AND` on Lightning seals that queue. When the engine reads `:Case("Empowered")`, it natively distributes that requirement to the end of all three branches at once. 

**The Technical Reality:** To maintain `O(1)` dictionary lookup speeds, the compiler still physically generates an `"Empowered"` node under each element in the RAM tree. However, it only binds the `__EXECUTE` pointer *once*, perfectly sharing your handler across the entire matrix. You get infinite logic scaling from a single block of highly readable code.

!!! info "AND Does Not Replace OR for Independent Handlers"
    `Op.AND` is for deepening branches that already exist, not for grouping branches that have different handlers. If "Fire" and "Ice" each need their own specific handler *without* a required second condition, use a pure OR gate (chain them together without `Op.AND`).

---

## 11. Scope Switches by Scenario and Pass Maximum Expected Arguments

Instead of building a single, monolithic router for your entire codebase, you should scope your switches to specific gameplay scenarios (e.g., a `SpellRouter`, a `MeleeRouter`, or an `InteractionRouter`). Once scoped, do not manually filter the context you pass to them. **Throw the absolute maximum number of expected arguments for that scenario into a single `:Match()` call.** Because the engine utilizes an Early Exit Cache, it will evaluate as deeply as it can, safely execute the highest-priority payload, and gracefully ignore any excess data.

### The Problem

- Pre-Filtering Arguments

```luau
local SpellRouter = Assignment.Switch("SpellRouter")

-- A 1-step rule
SpellRouter
    :Case("Earth")
    :Execute(castBasicEarth)

-- A 3-step rule
    :Case("Fire", Assignment.Op.AND)
    :Case("Staff", Assignment.Op.AND)
    :Case("Empowered")
    :Execute(castMeteor)

-- The Developer tries to "protect" the router by checking args manually
local function TryCastSpell(element, weapon, buff)
	if buff then
		return SpellRouter:Match(element, weapon, buff)

	elseif weapon then
		return SpellRouter:Match(element, weapon)

	else
		return SpellRouter:Match(element)
	end
end
```

**Why this is wrong:** You are wasting CPU cycles doing the engine's job for it. The developer is assuming that passing 3 arguments into a 1-step `"Earth"` rule will cause a crash or a default fallback. It won't! This manual `if/elseif` wrapper is completely unnecessary.

### The Solution 

- The Universal Cast

```luau
local SpellRouter = Assignment.Switch("SpellRouter")

-- Tier 3: Requires 3 arguments
SpellRouter
	:Case("Fire", Assignment.Op.AND)
	:Case("Staff", Assignment.Op.AND)
	:Case("Empowered")
	:Execute(castMeteor)

-- Tier 2: Requires 2 arguments
	:Case("Water", Assignment.Op.AND)
	:Case("Staff")
	:Execute(castTidalWave)

-- Tier 1: Requires 1 argument
	:Case("Earth")
	:Execute(castBasicEarth)

--[[
	The Universal Cast:
	
	Blindly pass the absolute maximum expected arguments.
	The router naturally degrades to the deepest valid execution it can find.
]]
local Action = SpellRouter:Match(currentElement, currentWeapon, currentBuff)

if Action then 
	Action() 
end
```

**Why this works:** It creates a modular, incredibly clean Developer Experience (DX). By scoping the switch strictly to "Spells", you know exactly what variables matter. You can pass all 3 variables blindly every single time:

* If you pass `("Fire", "Staff", "Empowered")`, it matches all 3 and casts Meteor.

* If you pass `("Water", "Staff", "Empowered")`, it matches the first 2, caches the TidalWave payload, hits a dead end on `"Empowered"`, **breaks safely**, and executes TidalWave! It gracefully ignores the 3rd argument.

* If you pass `("Earth", "Staff", "Empowered")`, it matches Earth, caches the payload, breaks on `"Staff"`, and cleanly executes BasicEarth.

!!! tip "The Golden Rule of Routing"
    Isolate your routers by scenario, and always pass the maximum available context state into `:Match()`. As long as you correctly terminated your deep paths with `:Execute()`, the engine will mathematically guarantee the correct action is returned.

## 12. Avoid Compacting Arguments — Preserve Type-Checking and Auto-Complete

While the `Assignment` engine mechanically allows you to pass multiple arguments into a single `:Case()` call to act as a shorthand AND gate, you should strictly avoid doing this. Compacting arguments breaks Luau’s type-checking and disables auto-complete. To leverage strict typing and intellisense, always use one condition per `:Case()` call.

### The Problem 

- Compacting Arguments

```luau
local ItemRouter = Assignment.Switch("ItemRouter")

-- Compacting multiple conditions into a single method call
ItemRouter
	:Case("Weapon", "Sword")
	:Execute(equipSword)
```

**Why this is wrong:** While the engine will compile this correctly, Luau’s type solver struggles with variadic generic arguments inside chained methods. By compacting `"Weapon"` and `"Sword"` into a single call, the type-checker goes blind. You lose your strict autocomplete suggestions, making typos much more likely and debugging much harder.

### The Solution

- One Condition Per Call

```luau
local ItemRouter = Assignment.Switch("ItemRouter")

-- Explicit chaining using Op.AND
ItemRouter
	:Case("Weapon", Assignment.Op.AND)
	:Case("Sword")
	:Execute(equipSword)
```

**Why this works:** By strictly passing one condition per `:Case()`, you allow Luau's type solver to evaluate the chain step-by-step. The IDE can perfectly track the generic types being passed down the tree, keeping your auto-complete active, your type-checking strict, and your development speed high.

!!! tip "Design for the IDE, Not Just the Engine"
    Always remember that other developers will be reading and extending your routers. Writing verbose, clearly chained logic `(:Case(A, Op.AND):Case(B))` is vastly superior to shorthand tricks `(:Case(A, B))` when it preserves the power of the script editor.

!!! info "Two Ways to Build AND Logic (IDE Compatibility)"
    The engine mechanically supports two different ways to write AND conditions, but they drastically affect your Developer Experience (DX) in strict Luau environments:

    * **The Shorthand (Avoid):** Passing multiple arguments like `:Case("Weapon", "Sword")` acts as a native AND gate in the engine. However, compressing them into a single variadic call causes the Luau type-solver to go blind, breaking your auto-complete and type-checking.

    * **The Explicit Chain (Recommended):** Chaining your conditions like `:Case("Weapon", Assignment.Op.AND):Case("Sword")` achieves the exact same routing, but evaluates step-by-step. This preserves the IDE's ability to track generic types, keeping your intellisense active and your code fully type-safe.

---

!!! success "Pro Tip — Use `Assignment.Cancel` in Generic Cleanup Systems"
    `handle:Break()` and `Assignment.Cancel(handle)` do the same thing for a `Handle`. The advantage of `Assignment.Cancel` is that it also accepts a raw `thread` returned from isolated calls — or any thread currently suspended inside `Assignment.Wait` — stopping it cleanly in either case. If you are building a general-purpose cleanup registry that might hold any of these types, `Assignment.Cancel` is the single call that handles all of them.