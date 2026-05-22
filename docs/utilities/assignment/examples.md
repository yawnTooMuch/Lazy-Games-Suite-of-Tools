# Assignment Examples

Practical, scenario-based examples for every public API in Assignment. Each section demonstrates realistic usage patterns including argument forwarding, cancellation, and edge cases.

---

## Spawn

**Pooled Family.** Runs work immediately. Recycled execution and automatic cleanup. Best for short, self-contained tasks.

**Scenario A — Fire-and-forget callback**
```luau
-- Run a non-blocking save without stalling the current frame.
-- Execution continues on the next line immediately.
Assignment.Spawn(function()
    DataService:SavePlayerData(player)
end)
```

**Scenario B — Resume an existing thread with arguments**
```luau
local pendingThread = coroutine.create(function(value: number)
    print("Resumed with:", value) --> "Resumed with: 42"
end)

Assignment.Spawn(pendingThread, 42)
```

**Scenario C — Brief yield inside a pooled call**
```luau
-- A short yield is fine here — the work finishes quickly
-- and the shared worker is free again as soon as it does.
Assignment.Spawn(function()
    Assignment.Wait(0.1)
    applyStatusEffect(player, "Stunned")
end)
```

---

## SpawnIsolated

**Isolated Family.** Runs work immediately at full engine priority in a dedicated thread. Bypasses all throttling. Returns a `thread` cancellation token. Use when work will sleep for a long time or involve repeated slow yields.

**Scenario A — Long-polling loop with multi-second intervals**
```luau
--[[
	This loop sleeps for 30 seconds each iteration. Running it through
	Spawn would keep the shared worker occupied for that entire sleep, 
	leaving all other short incoming work without a free worker to reuse.
	SpawnIsolated gives this task its own dedicated engine thread so the
	shared worker is never involved.
]]
local serviceThread = Assignment.SpawnIsolated(function()
    while gameActive do
        Assignment.Wait(30)
        syncLeaderboardData()
    end
end)

onGameEnd:Connect(function()
    Assignment.Cancel(serviceThread)
end)
```

**Scenario B — Multi-step workflow with slow async calls**
```luau
--[[
	Each DataStore call may take several seconds to complete.
	Isolating this work keeps the shared worker free the entire time
	so short tasks elsewhere in your code are never delayed.
]]
Assignment.SpawnIsolated(function()
    local profileData = DataService:LoadProfile(player)

    Assignment.Wait(0) -- yield one frame between steps

    local inventoryData = DataService:LoadInventory(player)

    Assignment.Wait(0)
    applyLoadedData(player, profileData, inventoryData)
end)
```

**Scenario C — Isolated thread with external cancellation**
```luau
local monitorThread = Assignment.SpawnIsolated(function()
    while true do
        Assignment.Wait(5)
        checkServerHealth()
    end
end)

onServerShutdown:Connect(function()
    Assignment.Cancel(monitorThread)
end)
```

---

## Defer

**Pooled Family.** Queues work for the next available frame. Large backlogs are spread across frames automatically — no single frame is overwhelmed. Full `Handle`-based cancellation.

**Scenario A — Defer heavy setup out of module load**
```luau
-- Avoid blocking the current frame with expensive setup.
-- This runs on the very next frame after this code executes.
Assignment.Defer(function()
    buildLookupTable()
    cachePlayerData()
end)
```

**Scenario B — Cancel a deferred call before it fires**
```luau
local handle = Assignment.Defer(function()
    sendWelcomeNotification(player)
end)

-- Player disconnected before the next frame
if not player:IsDescendantOf(game) then
    handle:Break()
end
```

**Scenario C — Defer a thread with arguments**
```luau
local handshakeThread = coroutine.create(function(sessionId: string, token: string)
    validateHandshake(sessionId, token)
end)

local handle = Assignment.Defer(handshakeThread, sessionId, authToken)
```

**Scenario D — Spreading a large batch of work across frames**
```luau
-- Deferring many calls at once lets Assignment spread them across frames
-- rather than processing everything in one spike.
for _, system in ipairs(systemsToInit) do
    Assignment.Defer(system.Initialize, system)
end
```

---

## DeferIsolated

**Isolated Family.** Queues work for the next available frame at full engine priority. Bypasses frame-spread throttling. Returns a `thread` cancellation token. Use when the deferred work will then sleep for a long time.

**Scenario A — Deferred batch of slow async writes**
```luau
--[[
	Each DataStore write may yield for several seconds. DeferIsolated
	queues the batch to the next frame but gives it a dedicated engine 
	thread, so the shared worker is never occupied during any of those writes.
]]
Assignment.DeferIsolated(function()
    for _, record in ipairs(pendingRecords) do
        DataService:Write(record)
        Assignment.Wait(0) -- breathe between writes
    end
end)
```

**Scenario B — Deferred isolated call with cancellation**
```luau
local thread = Assignment.DeferIsolated(function()
    local result = HttpService:GetAsync(endpoint)

    processResult(result)
end)

-- If the request is no longer needed before the next frame fires
if requestAborted then
    Assignment.Cancel(thread)
end
```

---

## Delay

**Pooled Family.** Schedules work to run after a set duration. Cancelled work is silently discarded before it ever runs. Zero and negative durations queue on the next available frame, same as `Defer`.

**Scenario A — Ability cooldown reset**
```luau
setAbilityEnabled(player, "Dash", false)

local cooldownHandle = Assignment.Delay(5, function()
    setAbilityEnabled(player, "Dash", true)
end)

playerCooldowns[player] = cooldownHandle
```

**Scenario B — Cancel a delayed effect when conditions change**
```luau
local explosionHandle = Assignment.Delay(3, triggerExplosion, bombPosition)

onBombDefused:Connect(function()
    explosionHandle:Break()
    -- triggerExplosion will never run
end)
```

**Scenario C — Resume a thread after a delay with arguments**
```luau
local resultThread = coroutine.create(function(hitPosition: Vector3)
    spawnImpactEffect(hitPosition)
end)

Assignment.Delay(0.2, resultThread, hitPos)
```

**Scenario D — Passing zero or a negative duration**
```luau
-- Delay(0, ...) runs on the next available frame — same as Defer.
-- Useful when you want "as soon as possible" with a cancellable Handle.
local handle = Assignment.Delay(0, function()
    applyImmediateEffect(player)
end)

-- Negative values behave identically.
local handle2 = Assignment.Delay(-99, function()
    applyImmediateEffect(player)
end)

-- Both can be cancelled before the next frame fires.
handle:Break()
handle2:Break()
```

---

## DelayIsolated

**Isolated Family.** Schedules work after a set duration at full engine priority in a dedicated thread. Bypasses all throttling. Returns a `thread` cancellation token. Use when the work that fires after the delay will sleep for a long time.

**Scenario A — Delayed multi-step async operation**
```luau
--[[
	Each step involves a slow async call that may take several seconds.
	Running this through the standard Delay would keep the shared worker
	occupied for every one of those yields. DelayIsolated gives this
	work its own dedicated engine thread so the shared worker stays free.
]]
local operationThread = Assignment.DelayIsolated(10, function()
    local snapshot = DataService:LoadSnapshot(serverId)

    Assignment.Wait(0) -- breathe between steps
    ReplicationService:Push(snapshot)
end)

onShutdown:Connect(function()
    Assignment.Cancel(operationThread)
end)
```

**Scenario B — Delayed spawn with async setup and cancellation**
```luau
local spawnThread = Assignment.DelayIsolated(5, function()
    local config = ConfigService:Fetch(entityType) -- slow async call

    spawnEntity(spawnPoint, config)
end)

onZoneCleared:Connect(function()
    Assignment.Cancel(spawnThread)
end)
```

---

## Wait

Pauses the current thread for a duration and returns the actual time elapsed. Works correctly whether called from a pooled or isolated thread — no special handling needed.

**Scenario A — Timed loop using elapsed time for smooth interpolation**
```luau
local startTime = os.clock()
while true do
    Assignment.Wait(0.05)
    local t = math.min((os.clock() - startTime) / 2, 1)

    setAlpha(lerp(0, 1, t))
    if t >= 1 then break end
end
```

**Scenario B — Passing nil — one-frame yield**
```luau
-- Assignment.Wait() with no argument pauses for exactly one frame.
-- Useful for letting other queued work run before continuing.
Assignment.Spawn(function()
    startPhaseOne()
    Assignment.Wait()   -- yields one frame
    startPhaseTwo()
end)
```

**Scenario C — Passing zero — identical to nil**
```luau
-- Assignment.Wait(0) behaves the same as Assignment.Wait(nil).
-- Both yield for one frame. Use whichever reads more clearly.
Assignment.Spawn(function()
    for _, step in ipairs(initSteps) do
        step()
        Assignment.Wait(0) -- breathe between steps
    end
end)
```

**Scenario D — Passing a negative value**
```luau
-- Negative durations are treated the same as zero — one-frame yield, no error.
Assignment.Spawn(function()
    Assignment.Wait(-99) -- same as Wait(0)
    continueWork()
end)
```

**Scenario E — Called from inside an isolated thread**
```luau
--[[
	Assignment.Wait detects the context automatically.
	Inside an isolated thread it defers to the engine's native wait.
	No special handling needed at the call site.
]]
Assignment.SpawnIsolated(function()
    while active do
        Assignment.Wait(60) -- works correctly; no need to think about context
        runHourlyMaintenance()
    end
end)
```

---

## Repeat

Calls a function at a fixed interval for a set number of iterations or indefinitely.

**Scenario A — Finite countdown with early exit**
```luau
local countdownHandle = Assignment.Repeat(10, 1, function(iteration: number, handle: Assignment.Handle)
    local remaining = 10 - iteration + 1

    updateCountdownUI(remaining)

    if roundEnded then
        handle:Break() -- stop the loop early if the round ends before 10 ticks
    end
end)
```

**Scenario B — Infinite loop with external cancellation**
```luau
local pollHandle = Assignment.Repeat(-1, 30, function()
    refreshLeaderboard()
end)

onGameModeEnd:Connect(function()
    pollHandle:Break()
end)
```

**Scenario C — Forwarding arguments to the callback**
```luau
Assignment.Repeat(6, 5, function(_, handle: Assignment.Handle, target: Player, amount: number)
    grantResource(target, amount)

    if target.Parent == nil then
        handle:Break() -- player left; stop awarding
    end
end, player, 10)
```

**Scenario D — Zero or nil interval — one-frame yield between iterations**
```luau
--[[
	Passing nil or 0 as the interval yields one frame between iterations
	rather than a timed wait. Useful for batch processing that should stay
	responsive but run as fast as possible.
]]
local batchHandle = Assignment.Repeat(#recordsToProcess, nil, function(iteration: number)
    processRecord(recordsToProcess[iteration])
end)
```

---

## Cancel

Stops a scheduled task before it runs. Accepts a `Handle` from any pooled call, a `thread` from any isolated call, or a raw `thread` currently suspended inside `Assignment.Wait`.

**Scenario A — Cancel a handle when a player disconnects**
```luau
local respawnHandle = Assignment.Delay(5, respawnPlayer, player)

player.AncestryChanged:Connect(function()
    if player.Parent == nil then
        Assignment.Cancel(respawnHandle)
    end
end)
```

**Scenario B — Cancel an isolated thread by reference**
```luau
local thread = Assignment.DelayIsolated(3, doLongAsyncWork)

onConditionChanged:Connect(function()
    Assignment.Cancel(thread)
end)
```

**Scenario C — Cancel a thread suspended in Assignment.Wait**
```luau
-- If you hold a reference to a thread that is mid-wait,
-- passing it to Cancel is safe and stops it from being resumed.
local workerThread: thread

workerThread = coroutine.create(function()
    while true do
        Assignment.Wait(10)
        doPeriodicWork()
    end
end)

coroutine.resume(workerThread)

onShutdownEarly:Connect(function()
    Assignment.Cancel(workerThread) -- the pending wait is discarded; the loop never resumes
end)
```

**Scenario D — Passing nil is safe**
```luau
-- Assignment.Cancel silently does nothing when passed nil.
-- Safe to call even if the handle was never assigned.
local handle: Assignment.Handle? = nil

if someCondition then
    handle = Assignment.Delay(2, doWork)
end

Assignment.Cancel(handle :: any)
```

---

## Migrate

Hands all pending scheduled work to the engine's native scheduler, preserving remaining time for each task.

**Scenario A — Automatic shutdown (no action required)**
```luau
-- Assignment handles this automatically when the server closes.
-- All pending work is handed off with remaining time intact.
-- No code is needed — shown here for reference only.
```

**Scenario B — Manual migration for a controlled shutdown sequence**
```luau
if RunService:IsServer() then
    Assignment.Migrate() -- hand everything off now

    -- All Assignment calls from this point forward go through the
    -- native scheduler, but the API surface stays the same.
    Assignment.Delay(1, announceShutdown)
end
```

---

## Switch

`Assignment.Switch` fetches or creates a named, global decision tree (singleton). Calling it with the same ID from any script always returns the same object with zero allocation cost.

**Scenario A — Setup and traverse in separate scripts**
```luau
-- Script A (runs at game start): compile all the rules
local CombatRouter = Assignment.Switch("CombatRouter")

CombatRouter
    :Case("Sword", "Idle")
    :Execute(playSwordIdle)

    :Case("Sword", "Attack")
    :Execute(playSwordAttack)

    :Case("Bow", "Idle")
    :Execute(playBowIdle)

    :Case("Bow", "Attack")
    :Execute(playBowAttack)
    
    :Default(playGenericAnimation)

-- Script B (runs in the animation loop): fetch and match, zero allocation
local CombatRouter = Assignment.Switch("CombatRouter") -- same object, no new memory

RunService.Heartbeat:Connect(function()
    local handler = CombatRouter:Match(currentWeapon, currentState)

    if handler then
        handler(character)
    end
end)
```

**Scenario B — Opcode conditions (numeric ranges and type checks)**
```luau
local HealthRouter = Assignment.Switch("HealthRouter")

-- Exact numeric match
HealthRouter
    :Case(100)
    :Execute(showFullHealthUI)

-- Range check: target health is between 1 and 49, inclusive
    :Case(Assignment.Op.InRange, 1, 49)
    :Execute(showLowHealthWarning)

-- Inequality check: target health is 0
    :Case(0)
    :Execute(triggerDeathSequence)

-- Type check: the value passed is not a number at all
    :Case(Assignment.Op.Type, "nil")
    :Execute(handleMissingHealthData)

-- Fallback for any unmatched value
    :Default(showNormalHealthUI)

-- Usage each frame
RunService.Heartbeat:Connect(function()
    local handler = HealthRouter:Match(character:GetAttribute("Health"))

    if handler then
        handler(character)
    end
end)
```

**Scenario C — OR gate (multiple cases sharing one handler)**
```luau
local DamageRouter = Assignment.Switch("DamageTypeRouter")

-- All three damage types share one handler — no :Execute() between them
DamageRouter
    :Case("Fire")
    :Case("Plasma")
    :Case("Explosion")
    :Execute(applyBurnEffect) -- fires for any of the three

    :Case("Ice")
    :Case("Frost")
    :Execute(applySlowEffect) -- another set of or conditions. Fires for any of the two

    :Default(applyGenericDamage)
```

**Scenario D — NoOp: intentionally silencing known states**
```luau
local EventRouter = Assignment.Switch("EventRouter")

-- "Idle" is a known state we want to do nothing with.
-- Using NoOp means the Default fallback is NOT called for it.
EventRouter
    :Case("Idle")
    :Execute(Assignment.Op.NoOp)

-- Unknown states still hit the default.
    :Case("Running")
    :Execute(playRunAnimation)

    :Default(logUnknownEvent)

-- In the loop:
local handler = EventRouter:Match(currentEvent)

if handler then
    handler() -- called for "Running" and any unmatched state, never for "Idle"
end
```

**Scenario E — Multi-step paths (compound matching)**
```luau
-- Rules can chain multiple steps to narrow the decision.
-- Each step in :Case() corresponds to one argument passed to :Match().
local ItemRouter = Assignment.Switch("InventoryItemRouter")

ItemRouter
    :Case("Weapon", "Sword")
    :Execute(equipSword)

    :Case("Weapon", "Bow")
    :Execute(equipBow)
    
    :Case("Consumable", "Potion")
    :Execute(usePotion)
    
    :Case("Consumable", "Antidote")
    :Execute(useAntidote)
    
    :Default(logUnknownItem)

-- Calling Match with two arguments walks the two-step path
local handler = ItemRouter:Match(item.Category, item.Type)

if handler then
    handler(player, item)
end
```

**Scenario F — No Default: unmatched states return nil**
```luau
--[[
	When no :Default() was set:
	
	:Match() returns nil for any value that does not match a compiled path.
	This is the correct pattern when unrecognized states require no action 
	and no fallback — the caller's nil check is the only gate needed.
]]
local InputRouter = Assignment.Switch("InputRouter")

InputRouter
    :Case("Jump")
    :Execute(handleJump)

    :Case("Sprint")
    :Execute(handleSprint)

    :Case("Crouch")
    :Execute(handleCrouch)

    :Case("Interact")
    :Execute(handleInteract)

-- No :Default — inputs not listed above produce nil from :Match and are silently skipped

RunService.Heartbeat:Connect(function()
    local handler = InputRouter:Match(currentInput)

    if handler then
        handler(player) -- only called for the four registered inputs
    end
end)
```

**Scenario G — Pure AND Gate: Deep Linear Conditions**
```Lua
--[[
	Op.AND placed as the last argument in :Case() seals the engine into
	continuation mode. The next :Case() call attaches directly to the
	end of the current path, building a deeply nested AND gate.

	This expresses A AND B AND C natively, allowing for infinite, 
	perfectly type-checked condition chains.
]]
local AbilityRouter = Assignment.Switch("AbilityRouter")

-- "Fire AND Staff AND Empowered": A strict, 3-step linear requirement
AbilityRouter
    :Case("Fire", Assignment.Op.AND)     -- Must be Fire, continue...
    :Case("Staff", Assignment.Op.AND)    -- Must be holding a Staff, continue...
    :Case("Empowered")                   -- Must be Empowered, seal the path!
    :Execute(handlePyroblast)

-- Standard single-step rules coexist alongside deeply nested AND rules natively.
-- This rule will catch :Match("Water") with no additional arguments required.
    :Case("Water")
    :Execute(handleBasicSplash)

    :Default(handleUnknownAbility)

-- Pass all three dynamic variables so the 3-step AND paths can evaluate natively
local handler = AbilityRouter:Match(currentElement, currentWeapon, currentBuff)

if handler then
    handler(player)
end
```

**Scenario H — Multi-Depth AND Chains (Argument Overloading)**
```luau
--[[
	A single router can seamlessly manage deeply nested AND chains of 
	varying lengths without conflict. 
	
	You can blindly pass the maximum number of variables into your :Match()
	call. The engine will automatically traverse as deep as it can, safely 
	execute the correct payload, and ignore any excess arguments.
]]
local CombatRouter = Assignment.Switch("CombatRouter")

-- "Fire AND Staff AND Empowered": A strict 3-step requirement
CombatRouter
	:Case("Fire", Assignment.Op.AND)       -- Must be Fire, continue...
	:Case("Staff", Assignment.Op.AND)      -- Must be holding a Staff, continue...
	:Case("Empowered")                     -- Must be Empowered, seal the path!
	:Execute(handlePyroblast)

-- "Water AND Wand": A 2-step requirement (Safely ignores args 3 and 4)
	:Case("Water", Assignment.Op.AND)      -- Must be Water, continue...
	:Case("Wand")                          -- Must be holding a Wand, seal the path!
	:Execute(handleTidalWave)

-- "Earth AND Hammer AND Fortified AND Enraged": A massive 4-step requirement
	:Case("Earth", Assignment.Op.AND)      -- Must be Earth, continue...
	:Case("Hammer", Assignment.Op.AND)     -- Must be holding a Hammer, continue...
	:Case("Fortified", Assignment.Op.AND)  -- Must be Fortified, continue...
	:Case("Enraged")                       -- Must be Enraged, seal the path!
	:Execute(handleDiamondSmash)

	:Default(handleBasicAttack)

-- Blindly pass ALL 4 dynamic variables into the router.
-- The engine dynamically evaluates the required depth and safely ignores the rest.
local handler = CombatRouter:Match(currentElement, currentWeapon, currentBuff, currentStatus)

if handler then
	handler(player)
end
```

**Scenario I — Advanced Architecture: Grouped & Compound Logic**
```luau
--[[
	Because the engine processes state linearly and caches endpoints, a single 
	Switch statement can house entirely disconnected logic groups (Grouped) 
	or deeply interwoven matrices (Compound) without memory conflicts.
]]
local MasterRouter = Assignment.Switch("MasterRouter")

------------------------------------------------------
-- PART 1: GROUPED LOGIC (Independent Chains)
------------------------------------------------------

-- You can safely stack pure OR chains and pure AND chains of any length. 
-- They will never overlap as long as you close each block with :Execute().

MasterRouter
	-- Group A: 3-Wide OR Gate (A OR B OR C)
	:Case("Slash")
	:Case("Stab")
	:Case("Crush")
	:Execute(handlePhysical)

	-- Group B: 3-Deep AND Gate (A AND B AND C)
	:Case("Fire", Assignment.Op.AND)
	:Case("Staff", Assignment.Op.AND)
	:Case("Empowered")
	:Execute(handlePyroblast)

	-- Group C: 6-Wide OR Gate (A OR B OR C OR D OR E OR F)
	:Case("Poison")
	:Case("Burn")
	:Case("Bleed")
	:Case("Freeze")
	:Case("Stun")
	:Case("Blind")
	:Execute(handleStatusEffect)

	-- Group D: 5-Deep AND Gate (A AND B AND C AND D AND E)
	:Case("Earth", Assignment.Op.AND)
	:Case("Hammer", Assignment.Op.AND)
	:Case("Fortified", Assignment.Op.AND)
	:Case("Enraged", Assignment.Op.AND)
	:Case("Giant")
	:Execute(handleEarthquake)

------------------------------------------------------
-- PART 2: COMPOUND LOGIC (Interleaved Matrices)
------------------------------------------------------

-- By alternating between Open and Sealed states within the same block, 
-- you can build incredibly complex Distributive Multiplexers.

	-- Compound 1: ((A AND B AND C) OR D) AND E
	:Case("Rogue", Assignment.Op.AND)     -- A (Sealed)
	:Case("Stealth", Assignment.Op.AND)   -- B (Sealed, appends to A)
	:Case("Dagger")                       -- C (Open, appends to B)
	:Case("Assassin", Assignment.Op.AND)  -- D (Sealed, creates new root branch)
	:Case("Critical")                     -- E (Open, distributes to Dagger AND Assassin)
	:Execute(handleAssassination)

	-- Compound 2: (((A OR B) AND C) OR D) AND E
	:Case("Warrior")                      -- A (Open)
	:Case("Paladin", Assignment.Op.AND)   -- B (Sealed, creates new root branch)
	:Case("Shield")                       -- C (Open, distributes to Warrior AND Paladin)
	:Case("Knight", Assignment.Op.AND)    -- D (Sealed, creates new root branch)
	:Case("Defend")                       -- E (Open, distributes to Shield AND Knight)
	:Execute(handleHeavyBlock)

	-- Compound 3: ((A AND B) OR C OR D) AND E
	:Case("Mage", Assignment.Op.AND)      -- A (Sealed)
	:Case("Staff")                        -- B (Open, appends to A)
	:Case("Warlock")                      -- C (Open, creates new root branch)
	:Case("Sorcerer", Assignment.Op.AND)  -- D (Sealed, creates new root branch)
	:Case("Cast")                         -- E (Open, distributes to Staff, Warlock, Sorcerer)
	:Execute(handleMagicCast)

	-- The Global Fallback
	:Default(handleUnknownAction)
```

!!! info "Step-by-Step: How the Engine Reads Compound 1"
    Let's break down exactly how the JIT compiler reads the first example to build `((Rogue AND Stealth AND Dagger) OR Assassin) AND Critical`:

    1. **`:Case("Rogue", Op.AND)`** → The engine creates a "Rogue" branch. *(Why AND?)* Because the `Op.AND` token is present, the engine "seals" this branch. It knows the next call must be a direct continuation, not an alternative.

    2. **`:Case("Stealth", Op.AND)`** → The engine attaches this directly under Rogue. The path is now `(Rogue AND Stealth)`. *(Why AND?)* Because `Op.AND` is present again, the path remains sealed. The engine expects another continuation.

    3. **`:Case("Dagger")`** → The engine attaches this directly under Stealth. The path is now `(Rogue AND Stealth AND Dagger)`. *(Why OR next?)* Because this line does **NOT** have an `Op.AND`! This is the critical pivot. The engine unseals the group, moves this completed chain into the pending queue, and prepares to build a brand-new parallel branch.

    4. **`:Case("Assassin", Op.AND)`** → Because the previous line was open, the engine creates a new, independent root branch. We logically now have `(Rogue AND Stealth AND Dagger) OR Assassin`. *(Why AND?)* Because `Op.AND` is applied here, it seals this new "Assassin" branch, telling the engine the next call must apply to everything currently pending.

    5. **`:Case("Critical")`** → The engine is in continuation mode. It takes "Critical" and mathematically distributes it to the ends of **all** open paths in the queue. It attaches to "Dagger", and it attaches to "Assassin". 

    The tree is finalized, perfectly expressing: `((Rogue AND Stealth AND Dagger) OR Assassin) AND Critical`. Once `:Execute(handleAssassination)` is called, the exact memory tree physically built in RAM looks like this:

    ```luau
	_Trie = {
		["Rogue"] = {
			["Stealth"] = {
				["Dagger"] = {
					["Critical"] = { 
						__EXECUTE = handleAssassination
					}
				}
			}
		},
		
		["Assassin"] = {
			["Critical"] = { 
				__EXECUTE = handleAssassination
			}
		}
	}
    ```

!!! info "Step-by-Step: How the Engine Reads Compound 2"
    Let's trace how the engine builds the nested multiplexer: `(((Warrior OR Paladin) AND Shield) OR Knight) AND Defend`.

    1. **`:Case("Warrior")`** → Creates the "Warrior" branch. *(Why OR next?)* There is no `Op.AND`, so the engine leaves this branch open, puts it in the pending queue, and prepares for an alternative.

    2. **`:Case("Paladin", Op.AND)`** → Creates a parallel "Paladin" root branch. We now have `(Warrior OR Paladin)`. *(Why AND?)* The `Op.AND` token seals this group. It tells the engine to stop building alternatives and switch into continuation mode for all pending branches.

    3. **`:Case("Shield")`** → The engine distributes "Shield" to the end of **both** Warrior and Paladin. We now have `((Warrior OR Paladin) AND Shield)`. *(Why OR next?)* Because there is no `Op.AND` here, the engine unseals this completed chunk, pushes it to the pending queue, and prepares for a brand-new alternative.

    4. **`:Case("Knight", Op.AND)`** → Creates a brand new, independent "Knight" branch. Logically, we have `(((Warrior OR Paladin) AND Shield) OR Knight)`. *(Why AND?)* The `Op.AND` seals the Knight branch and throws the engine back into continuation mode for everything currently pending.

    5. **`:Case("Defend")`** → The engine takes "Defend" and mathematically distributes it to the very end of all open paths. It attaches to "Shield", and it attaches to "Knight".

    The tree is finalized, perfectly expressing: `(((Warrior OR Paladin) AND Shield) OR Knight) AND Defend`. Once `:Execute(handleHeavyBlock)` is called, the exact memory tree physically built in RAM looks like this:

	```luau
	_Trie = {
		["Warrior"] = {
			["Shield"] = {
				["Defend"] = { 
					__EXECUTE = handleHeavyBlock
				}
			}
		},
		
		["Paladin"] = {
			["Shield"] = {
				["Defend"] = { 
					__EXECUTE = handleHeavyBlock 
				}
			}
		},
		
		["Knight"] = {
			["Defend"] = {
				__EXECUTE = handleHeavyBlock 
			}
		}
	}
	```

!!! info "Step-by-Step: How the Engine Reads Compound 3"
    Let's trace how the engine builds an OR-heavy matrix with a shared finisher: `((Mage AND Staff) OR Warlock OR Sorcerer) AND Cast`.

    1. **`:Case("Mage", Op.AND)`** → Creates the "Mage" branch. *(Why AND?)* The `Op.AND` seals the branch, telling the engine the next call is a direct requirement.

    2. **`:Case("Staff")`** → Attaches directly under Mage. We have `(Mage AND Staff)`. *(Why OR next?)* There is no `Op.AND`. The engine unseals this path, moves it to the pending queue, and prepares for an alternative.

    3. **`:Case("Warlock")`** → Creates a new, independent "Warlock" branch. We have `((Mage AND Staff) OR Warlock)`. *(Why OR next?)* Again, no `Op.AND`. The engine unseals Warlock, adds it to the pending queue alongside the Mage path, and prepares for yet another alternative.

    4. **`:Case("Sorcerer", Op.AND)`** → Creates a third independent branch, "Sorcerer". We have `((Mage AND Staff) OR Warlock OR Sorcerer)`. *(Why AND?)* The `Op.AND` seals the Sorcerer branch and triggers continuation mode. The engine prepares to distribute the next rule across all three items sitting in the pending queue.

    5. **`:Case("Cast")`** → The engine takes "Cast" and distributes it identically to the end of "Staff", the end of "Warlock", and the end of "Sorcerer".

    The tree is finalized, perfectly expressing: `((Mage AND Staff) OR Warlock OR Sorcerer) AND Cast`. Once `:Execute(handleMagicCast)` is called, the exact memory tree physically built in RAM looks like this:

	```luau
	_Trie = {
		["Mage"] = {
			["Staff"] = {
				["Cast"] = { 
					__EXECUTE = handleMagicCast 
				}
			}
		},

		["Warlock"] = {
			["Cast"] = { 
				__EXECUTE = handleMagicCast 
			}
		},

		["Sorcerer"] = {
			["Cast"] = { 
				__EXECUTE = handleMagicCast 
			}
		}
	}
	```

!!! info "The Engine's Mental Model: Forward-Only & AND Gate Precedence"
    To master compound logic, you must understand two core architectural rules of the `Assignment` compiler: **It never goes backward**, and **AND always overrules OR**.
    
    During the Setup Phase, the engine reads your `:Case()` chains in a single, linear pass. It only ever builds forward.
    
    **1. The OR State (Parallel Collection)**
    When you call `:Case()` without an `Op.AND`, the engine builds a branch and leaves it open. It pushes this endpoint into a forward-facing "Pending Queue." As you chain more ORs together, they sit side-by-side in this pool, expanding horizontally with equal priority.
    
    **2. The AND Precedence (The Wrapper)**
    The `Op.AND` token has absolute structural priority. It acts as a massive logical parenthesis. When the compiler encounters an `Op.AND`, it says: *"Stop collecting. Take every single branch currently sitting in the Pending Queue, wrap them together into one group, and force all of them to step one level deeper."*
    
    **The Golden Rule:** The compiler is always moving forward. OR expands the current level horizontally. AND forcefully wraps that entire horizontal layer and drills vertically into a new node.

!!! warning "The Architectural Limitation: Symmetrical Bracket Logic"
    Because the compiler uses a forward-only waterfall approach, it cannot natively express symmetrical bracketed logic, such as **`(A OR B) AND (C OR D)`**.
    
    **Why?** The engine cannot "pause" distribution. If you build `(A OR B)` and seal it with `Op.AND`, the *very next* `:Case("C")` you write is instantly distributed to A and B. If you try to write `:Case("D")` immediately after, the engine assumes you are done with the AND chain and creates a brand-new root branch, resulting in `((A OR B) AND C) OR D`.
    
    **The Solution:**
    The router is designed for hierarchical game state (e.g., Element -> Weapon -> Status). If you have highly complex, symmetrical math conditions `(if (x or y) and (z or w))`, do not force it into the memory tree. Simply route the path to a broader `:Case()` and use native Lua `if/else` statements inside your `:Execute()` payload!

**Scenario J — Dynamic Math & Logic Opcodes**
```luau
--[[
	While standard strings and numbers create O(1) exact-match branches, 
	you can also pass Mathematical Opcodes into :Case() to route data 
	dynamically. 
	
	The syntax is strictly: :Case(Opcode, Subject)
	You can still append `Op.AND` as the final argument to chain them.
]]
local CombatRouter = Assignment.Switch("CombatRouter")

-- A pure Math condition (If TargetHealth < 20)
CombatRouter
	:Case(Assignment.Op.LessThan, 20)
	:Execute(handleExecution)

-- Compound Math & Exact Matches (If Weapon != "WoodSword" AND Health > 80)
	:Case(Assignment.Op.NotEqual, "WoodSword", Assignment.Op.AND) -- Sealed!
	:Case(Assignment.Op.GreaterThan, 80) -- Continuation!
	:Execute(handleArmorPenetration)

-- Exact Matches ALWAYS win over Math Opcodes
	:Case(15) 
	:Execute(handleExactFifteen)

	:Default(handleStandardDamage)

-------------------------------------
-- RUNTIME EXAMPLES
-------------------------------------

-- Example A: 10 is less than 20
local ActionA = CombatRouter:Match(10) 

-- Example B: "IronSword" != "WoodSword", and 90 > 80
local ActionB = CombatRouter:Match("IronSword", 90)

-- Example C: Prioritized over Example A
-- Even though 15 is Less Than 20, the engine checks Exact Matches first!
local ActionC = CombatRouter:Match(15) 

--[[
	Exact Memory Tree Built:
	
	_Trie = {
		-- The O(1) Exact Match Dictionary
		[15] = { 
		__EXECUTE = handleExactFifteen 
		},
		
		-- The Flexible Operator Array
		__OPERATORS = {
			{
				Opcode = Assignment.Op.LessThan,
				Subject = 20,
				
				Node = { 
					__EXECUTE = handleExecution 
				}
			},
			
			{
				Opcode = Assignment.Op.NotEqual,
				Subject = "WoodSword",
				
				Node = {
					__OPERATORS = {
						{
							Opcode = Assignment.Op.GreaterThan,
							Subject = 80,
							
							Node = { 
								__EXECUTE = handleArmorPenetration
							}
						}
					}
				}
			}
		}
	}
]]
```

!!! info "Architectural Priority: Exact Match vs. Math Arrays"
    When you pass an argument into :Match(), the engine does not evaluate the tree randomly. It strictly follows a 3-step performance waterfall to ensure blazing-fast execution times:

    1. **The Fast-Path (Exact Match):** The engine first performs an `O(1)` dictionary lookup. If you pass `15`, it instantly checks `_Trie[15]`. If it finds it, it jumps straight in, completely skipping all math.

    2. **The Range Path:** If the exact match fails, it checks for numerical ranges (`__RANGES`).

    3. **The Math Path (Opcodes):** Only if the first two fail does the engine loop through the `__OPERATORS` array, testing your variable against the `Subject` using your requested `Opcode`.

    **The Takeaway:** Exact matches are "free" in terms of CPU cost. Math opcodes are incredibly powerful, but cost a few extra CPU cycles because they evaluate sequentially. Always use exact matches when possible, and reserve Opcodes for true dynamic ranges.

---

## Op

`Assignment.Op` is a frozen enum dictionary. Opcodes are passed to `:Case()` during setup to compile non-equality comparison rules. They are never used at runtime or passed to `:Match()`.

**Scenario A — InRange (requires two number subjects)**
```luau
local ScoreRouter = Assignment.Switch("ScoreRouter")

-- InRange is the only opcode that takes two subjects: Min and Max (inclusive)
ScoreRouter
    :Case(Assignment.Op.InRange, 0, 999)
    :Execute(rankBronze)

    :Case(Assignment.Op.InRange, 1000, 4999)
    :Execute(rankSilver)

    :Case(Assignment.Op.InRange, 5000, 9999)
    :Execute(rankGold)
```

**Scenario B — Type and IsA**
```luau
local TargetRouter = Assignment.Switch("TargetRouter")

-- Type checks typeof() — works on any Luau value
TargetRouter
    :Case(Assignment.Op.Type, "number")
    :Execute(handleNumericTarget)

    :Case(Assignment.Op.Type, "string")
    :Execute(handleStringTarget)

-- IsA checks a Roblox class hierarchy — safely skipped if target is not an Instance
    :Case(Assignment.Op.IsA, "BasePart")
    :Execute(handlePartTarget)

    :Case(Assignment.Op.IsA, "Model")
    :Execute(handleModelTarget)
```

**Scenario C — All remaining single-subject operators (NotEqual, LessThan, LessThanOrEqual, GreaterThan, GreaterThanOrEqual)**
```luau
-- All five operators below require exactly one subject and are safely skipped
-- if the runtime value is not a number (NotEqual is the exception — it works on any type).

--[[
	Ordering matters: 
	
	Opcodes are evaluated in the order they were compiled. More specific thresholds 
	must be compiled before broader ones so that the narrower check fires first. 
	
	In the ping example below, GreaterThanOrEqual(500) is compiled before GreaterThan(200)
	so that critical (≥500) takes priority over poor (>200). The same logic applies to the
	lower-bound pair.
]]
local PingRouter = Assignment.Switch("PingRouter")

PingRouter
    -- LessThanOrEqual: ping is at or below 50ms — excellent
    :Case(Assignment.Op.LessThanOrEqual, 50)
    :Execute(showExcellentSignal)

    -- LessThan: ping is below 100ms — good (51–99ms; ≤50 was already caught above)
    :Case(Assignment.Op.LessThan, 100)
    :Execute(showGoodSignal)

    -- GreaterThanOrEqual: ping is at or above 500ms — critical (compiled before GreaterThan)
    :Case(Assignment.Op.GreaterThanOrEqual, 500)
    :Execute(showCriticalSignal)

    -- GreaterThan: ping is above 200ms — poor (201–499ms; ≥500 was already caught above)
    :Case(Assignment.Op.GreaterThan, 200)
    :Execute(showPoorSignal)

    -- Default catches the fair range (100–200ms) that no opcode claimed
    :Default(showFairSignal)

-- NotEqual works on any type, not just numbers. It is most useful for
-- filtering out a single known sentinel value before any other logic runs.
local SessionRouter = Assignment.Switch("SessionRouter")

SessionRouter
    -- Fire only when the session token is not the uninitialized placeholder.
    -- Any token that is not UNINITIALIZED_TOKEN reaches this handler.
    :Case(Assignment.Op.NotEqual, UNINITIALIZED_TOKEN)
    :Execute(beginSession)

    :Default(requestNewToken)
```

**Scenario D — AND (structural token: no subject, not a comparison)**
```luau
--[[
	Op.AND is not a comparison operator and takes no subject.
	It is placed as the last argument in :Case() to activate the
	Distributive Multiplexer for the next :Case() call.

	Simple sequential AND — equivalent to :Case("Weapon", "Sword")
]]
local EquipRouter = Assignment.Switch("EquipRouter")

EquipRouter
    :Case("Weapon", Assignment.Op.AND) -- must be "Weapon", then continue...
    :Case("Sword")                     -- must be "Sword"
    :Execute(equipSword)

-- Distributive AND across an OR gate — "(Shield OR Barrier) AND Active":
local DefenseRouter = Assignment.Switch("DefenseRouter")

DefenseRouter
    :Case("Shield", Assignment.Op.AND) -- Shield branch, continue...
    :Case("Barrier", Assignment.Op.AND) -- Barrier branch, continue...
    :Case("Active")                     -- distributed: ("Shield","Active") and ("Barrier","Active")
    :Execute(activateDefense)

-- :Match() must supply all steps as separate arguments
local handler = DefenseRouter:Match(currentDefenseType, currentState)

if handler then
    handler(player)
end
```