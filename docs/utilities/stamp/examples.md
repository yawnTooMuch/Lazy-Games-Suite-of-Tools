# Stamp Examples

This page demonstrates every public API in the **Stamp** library with scenario-based examples. Each scenario exercises a meaningfully different usage pattern or edge case.

---

## Stamp.Inject

Provides the three required dependencies. Call all three before calling `Stamp.Register` anywhere in your codebase.

**Scenario A — Standard setup at the top of an initialization script**

```luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Suite = ReplicatedStorage.LazyGamesSuite

local Stamp      = require(Suite.Stamp)
local Reaper     = require(Suite.Reaper)
local Assignment = require(Suite.Assignment)
local Relay      = require(Suite.Relay)

-- Inject all three before registering any streams
Stamp.Inject("Reaper",     Reaper)
Stamp.Inject("Assignment", Assignment)
Stamp.Inject("Relay",      Relay)
```

**Scenario B — Injecting from a centralized bootstrap module**

```luau
-- GameBootstrap.lua  (runs once, required by all system scripts)
local function initialise()
    Stamp.Inject("Reaper",     require(path.to.Reaper))
    Stamp.Inject("Assignment", require(path.to.Assignment))
    Stamp.Inject("Relay",      require(path.to.Relay))
end
```

!!! danger "Strict Dependency: Reaper / Assignment / Relay"
    All three dependencies must be injected before calling `Stamp.Register`. Attempting to register a tag with any dependency missing throws an immediate error. Inject everything in one place at startup — not lazily inside individual system scripts.

!!! note "Studio Only"
    `ModuleName` must be a non-empty string and `ModuleTableObject` must be a table, or an error is thrown. Passing an unrecognised module name produces a warning but does not block injection.

---

## Stamp.Register

Returns the `StampStream` that controls a given tag. Calling it a second time with the same name returns the same live stream.

**Scenario A — Registering a new stream**

```luau
-- ServerScriptService/Systems/EnemySystem.lua
local enemyStream = Stamp.Register("Enemy")
-- enemyStream is now the authoritative controller for the "Enemy" tag
```

**Scenario B — Safe re-registration from multiple scripts**

```luau
-- Script A
local enemyStream = Stamp.Register("Enemy")

-- Script B (different script, same tag)
local alsoEnemyStream = Stamp.Register("Enemy")

-- Both variables point to the same live stream — no duplicate listeners created
print(enemyStream == alsoEnemyStream) -- true
```

!!! danger "Strict Dependency: Reaper / Assignment / Relay"
    Throws immediately if any of the three required dependencies have not been injected before this call.

!!! note "Studio Only"
    `TagName` must be a non-empty string or an error is thrown. Tag names longer than 100 characters produce a warning.

---

## Stamp.GetInstancesWithAttribute (Global)

Searches every registered stream simultaneously for instances that carry the named attribute.

**Scenario A — Filter by exact value**

```luau
-- Returns only instances across all streams where "IsBoss" is exactly true
local bosses = Stamp.GetInstancesWithAttribute("IsBoss", true)

for _, boss in bosses do
    print(boss.Name .. " is a boss")
end
```

**Scenario B — Check for attribute existence without filtering by value**

```luau
-- Returns every instance across all streams that has a "Health" attribute,
-- regardless of what that value currently is
local allCombatants = Stamp.GetInstancesWithAttribute("Health")
print("Total combatants with health: " .. #allCombatants)
```

!!! note "Studio Only"
    `Key` must be a non-empty string with a maximum of 100 characters. If `ExpectedValue` is provided, its type must be one of Roblox's supported attribute types (`string`, `number`, `boolean`, `UDim`, `UDim2`, `BrickColor`, `Color3`, `Vector2`, `Vector3`, `NumberRange`, `NumberSequence`, `ColorSequence`, `Rect`, `Font`), or an error is thrown.

---

## Stamp.Destroy (Global)

Destroys a named stream entirely, untagging all its instances and cleaning up all internal resources.

**Scenario A — End-of-round cleanup**

```luau
-- All "RoundPickup" instances are untagged and their scopes destroyed
Stamp.Destroy("RoundPickup")
```

**Scenario B — Conditional teardown**

```luau
local function endMatch()
    Stamp.Destroy("Enemy")
    Stamp.Destroy("Projectile")
    Stamp.Destroy("Pickup")
    -- Re-register fresh streams when the next match starts
end
```

**Scenario C — Global teardown**

```luau
-- From anywhere in the game scripts
local healthStamp = Stamp.Register("Health") -- Get the stamp

if healthStamp then
    healthStamp:Destroy -- Destroy locally
    -- or
    Stamp.Destroy("Health") -- Destroy globally
end
```

!!! note "Studio Only"
    `TagName` must be a non-empty string or an error is thrown. Calling `Destroy (Global)` on a tag that has no active stream produces a warning.

---

## Stamp.Utility.CompactString

Returns a copy of the input with all whitespace removed. If the input is not a non-empty string, a warning is printed and an empty string is returned.

**Scenario A — Normalising a tag name built from user input**

```luau
local rawName = "  Boss   Level  3 "
local tagName = Stamp.Utility.CompactString(rawName)
print(tagName) -- "BossLevel3"

local stream = Stamp.Register(tagName)
```

**Scenario B — Stripping formatting from a serialised identifier**

```luau
local serialised = "player\tslot\n02"
local clean = Stamp.Utility.CompactString(serialised)
print(clean) -- "playerslot02"
```

---

## StampStream:AddTag

Applies the stream's tag to an instance, which fires `Signals.Tagged` for all connected callbacks.

**Scenario A — Tagging a server-side model with atomic streaming**

```luau
-- Server: tag the Orc model and ensure its entire hierarchy streams as a unit
enemyStream:AddTag(workspace.Orc, true)
```

**Scenario B — Tagging a BasePart (no atomic flag)**

```luau
-- IsAtomic is only valid for Models; omit it or pass false for non-Model entities
local barrel = workspace.Breakables.Barrel
breakableStream:AddTag(barrel)
```

**Scenario C — Tagging multiple instances at spawn time**

```luau
local function spawnWave(enemies: {Model})
    for _, enemy in enemies do
        enemyStream:AddTag(enemy)
        -- Each AddTag fires Signals.Tagged for that specific instance
    end
end
```

**Scenario D — Tagging multiple instances globally**

```luau
local enemyStream = Stamp.Register("Enemy") -- Get the stamp

-- somewhere in the scripts of the game
local function spawnWave(enemies: {Model})
    for _, enemy in enemies do
        enemyStream:AddTag(enemy)
        -- Each AddTag fires Signals.Tagged for that specific instance
    end
end
```

!!! warning "Server-Only: IsAtomic"
    The `IsAtomic` parameter is only honoured when called from the **server**. Passing `true` on the client prints a warning and the streaming mode is left unchanged. Additionally, `IsAtomic` only applies to `Model` instances — passing `true` for a `BasePart` prints a warning and has no other effect.

!!! note "Studio Only"
    `Entity` must be a `PVInstance` and `IsAtomic`, if provided, must be a `boolean`, or errors are thrown.

---

## StampStream:AddTagDeferred

Client-only. Polls a folder until a named instance streams in, then tags it. Handles `StreamingEnabled` gracefully.

**Scenario A — Waiting for a streamed NPC with a custom timeout**

```luau
-- LocalScript
-- Polls workspace.Enemies every 0.5 s for up to 30 s for "BossOrc"
enemyStream:AddTagDeferred(workspace.Enemies, "BossOrc", false, 30)
```

**Scenario B — Recursive search with default timeout**

```luau
-- Searches all descendants of workspace.Level for "TreasureChest"
-- Gives up after the default 60 seconds if it never appears
interactableStream:AddTagDeferred(workspace.Level, "TreasureChest", true)
```

!!! warning "Client-Only Context"
    This method must only be called from a `LocalScript` or `ModuleScript` running on the client. Calling it from the server prints a warning and returns immediately without scheduling any polling. Use `AddTag` on the server.

!!! note "Studio Only"
    All parameters are type-validated. `TimeoutSeconds`, if provided, must be a positive number, or an error is thrown.

---

## StampStream:RemoveTag

Removes the tag from a single instance, triggering `Signals.Untagged` and destroying the entity's scope.

**Scenario A — Removing a tag when an enemy is defeated**

```luau
local function onEnemyDefeated(enemy: Model)
    -- Fires Signals.Untagged and cleans up everything bound to this enemy's scope
    enemyStream:RemoveTag(enemy)
end
```

**Scenario B — Removing a tag to temporarily disable a behaviour**

```luau
-- Pause the "Interactable" behaviour while a cutscene plays
interactableStream:RemoveTag(workspace.Lever)
-- Re-enable it after the cutscene ends
task.delay(5, function()
    interactableStream:AddTag(workspace.Lever)
end)
```

!!! note "Studio Only"
    `Entity` must be a `PVInstance` or an error is thrown.

---

## StampStream:RemoveAllTags

Removes the tag from every instance currently carrying it in the game. Each removal fires `Signals.Untagged` and destroys that instance's scope — equivalent to calling `RemoveTag` on each individually.

**Scenario A — Clearing all enemies at round end**

```luau
local function onRoundEnd()
    enemyStream:RemoveAllTags()
    -- All Signals.Untagged callbacks fire; all enemy scopes are destroyed
end
```

**Scenario B — Resetting a pickup pool**

```luau
-- Clear all live pickups so a fresh set can be spawned
pickupStream:RemoveAllTags()
spawnNewPickups()
```

!!! note "Removing Tag Globally"
    Same pattern for `StampStream:RemoveAllTags()`, you just have to get the stamp and control it on a different script.

---

## StampStream:GetAll

Returns a snapshot array of all currently tracked instances. The result is built from this stream's own private roster — it does not query `CollectionService` globally and does not intersect with any other stream's data. Safe to modify; the stream is unaffected.

**Scenario A — Iterating all enemies for a broadcast**

```luau
local enemies = enemyStream:GetAll()
for _, enemy in enemies do
    enemy:SetAttribute("AlertLevel", "High")
end
```

**Scenario B — Passing the list to another system**

```luau
local function updateMinimap()
    local positions = {}
    for _, enemy in enemyStream:GetAll() do
        table.insert(positions, enemy:GetPivot().Position)
    end
    MinimapModule.SetEnemyPositions(positions)
end
```

---

## StampStream:GetCount

Returns the live count of tracked instances. This value is maintained incrementally as instances are tagged and untagged — always up to date, costs nothing to read.

**Scenario A — Gate logic on enemy count**

```luau
if enemyStream:GetCount() == 0 then
    RoundManager.EndRound()
end
```

**Scenario B — Display count in a UI label**

```luau
RunService.Heartbeat:Connect(function()
    countLabel.Text = "Enemies: " .. enemyStream:GetCount()
end)
```

---

## StampStream:SetAttribute

Sets a named attribute on a specific entity and registers it in the query cache. Passing `nil` removes the attribute from both the instance and the cache. If the attribute already holds the exact value being set, the call is a no-op and no write is performed.

**Scenario A — Initialising health on a newly tagged enemy**

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- Assign initial health; this value is immediately queryable via GetInstancesWithAttribute
    enemyStream:SetAttribute(entity, "Health", 500)
    enemyStream:SetAttribute(entity, "IsBoss", entity.Name == "BossOrc")
end)
```

**Scenario B — Removing an attribute by passing nil**

```luau
-- Passing nil removes the attribute from the instance and clears it from the query cache
enemyStream:SetAttribute(workspace.Orc, "Stunned", nil)
```

**Scenario C — Updating an attribute on damage**

```luau
local function applyDamage(enemy: Model, amount: number)
    local current = enemyStream:GetAttribute(enemy, "Health")
    if current then
        -- Stamp skips the write entirely if the new value is identical to the current one
        enemyStream:SetAttribute(enemy, "Health", math.max(0, current - amount))
    end
end
```

!!! warning "Supported Attribute Types"
    `Value` must be one of the types Roblox permits on instances: `string`, `number`, `boolean`, `UDim`, `UDim2`, `BrickColor`, `Color3`, `Vector2`, `Vector3`, `NumberRange`, `NumberSequence`, `ColorSequence`, `Rect`, or `Font`. In Studio, passing any other type throws an error.

!!! note "Studio Only"
    `Entity` must be a `PVInstance`; `Key` must be a non-empty string of no more than 100 characters. Calling `SetAttribute` on an instance that has no parent produces a warning.

!!! tip "Automatic Cache Cleanup"
    When you first set an attribute on an entity, Stamp silently registers a cleanup handler so that if the entity is ever destroyed, all of its cached attribute entries are removed automatically. You never need to call `SetAttribute(entity, key, nil)` for cleanup when an entity is being destroyed.

---

## StampStream:SetAttributeAll

Sets the same attribute on every currently tracked instance in one call. The same no-op optimisation as `SetAttribute` applies per entity. Has no effect if the stream tracks zero instances.

**Scenario A — Triggering a global aggro state**

```luau
-- Every tracked enemy becomes aggressive simultaneously
enemyStream:SetAttributeAll("IsAggro", true)
```

**Scenario B — Clearing a status effect at round end**

```luau
-- Remove the "Frozen" attribute from all enemies at once
enemyStream:SetAttributeAll("Frozen", nil)
```

!!! warning "Supported Attribute Types"
    The same type constraints as `SetAttribute` apply. In Studio, passing an unsupported type throws an error.

!!! note "Studio Only"
    `Key` must be a non-empty string of no more than 100 characters, or an error is thrown.

---

## StampStream:GetAttribute

Returns an attribute value from the given entity. Values set through `SetAttribute` are read from Stamp's query cache first. If no cached value exists, the live Roblox attribute value is returned as a fallback.

**Scenario A — Reading health before applying damage**

```luau
local hp = enemyStream:GetAttribute(workspace.Orc, "Health")
if hp and hp > 0 then
    applyDamage(workspace.Orc, 25)
end
```

**Scenario B — Fallback to Roblox attribute when no cached value exists**

```luau
-- An attribute set directly on the instance (not through Stamp) is still returned
-- because GetAttribute falls back to the live Roblox read
local teamColor = enemyStream:GetAttribute(workspace.Orc, "TeamColor")
```

!!! note "Studio Only"
    `Entity` must be a `PVInstance` and `Key` must be a non-empty string of no more than 100 characters, or errors are thrown.

---

## StampStream:GetInstancesWithAttribute (Local)

Searches this stream only for instances carrying the named attribute. Results are scoped entirely to this stream — no other stream's instances are considered.

**Scenario A — Find all critically wounded enemies (filter by exact value)**

```luau
-- Returns only enemies in this stream where "Health" is exactly 1
local critical = enemyStream:GetInstancesWithAttribute("Health", 1)
for _, enemy in critical do
    playFlashEffect(enemy)
end
```

**Scenario B — Find all stunned enemies regardless of stun duration**

```luau
-- Returns every enemy that has the "Stunned" attribute, whatever its value
local stunned = enemyStream:GetInstancesWithAttribute("Stunned")
print(#stunned .. " enemies are currently stunned")
```

!!! note "Studio Only"
    `Key` must be a non-empty string of no more than 100 characters. If `ExpectedValue` is provided, its type must be a supported attribute type, or an error is thrown.

---

## StampStream:ObserveAttribute

Fires immediately with the current value, then again on every future change. The connection's lifetime is managed automatically through the scope binding waterfall.

**Scenario A — React to health changes with automatic scope cleanup**

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- No custom scope passed — the connection binds to the entity's tag scope (waterfall rule 2)
    -- and is disconnected automatically when the entity is untagged
    enemyStream:ObserveAttribute(entity, "Health", function(newHealth)
        if newHealth <= 0 then
            entity:Destroy()
        end
    end)
end)
```

**Scenario B — Using a custom scope to observe an entity from outside a Tagged callback**

```luau
-- A UI system needs to observe an enemy's health from a different module.
-- A custom scope is passed so the connection is tied to the UI's own lifetime (waterfall rule 1).
local uiScope = Reaper.Scope("UIHealthBar_" .. enemy.Name)

enemyStream:ObserveAttribute(enemy, "Health", function(newHealth)
    healthBar.Size = UDim2.fromScale(newHealth / maxHealth, 1)
end, uiScope)

-- When the UI is destroyed, uiScope:Destroy() is called and the observation ends
```

**Scenario C — Observing an untracked instance (property binding)**

```luau
-- A BasePart that carries an attribute but is not tagged in any stream.
-- No custom scope is passed and the entity is not tracked, so the connection
-- binds to the part's own object lifetime (waterfall rule 3).
local platform = workspace.MovingPlatform

propStream:ObserveAttribute(platform, "IsActive", function(active)
    platform.CanCollide = active
end)
-- Connection cleans up automatically when the platform is destroyed
```

!!! info "Scope Binding Waterfall"
    The returned connection's lifetime is determined as follows, in priority order:

    1. **Custom scope provided** — the connection is bound to `ScopeToBind` and is disconnected when that scope is destroyed.
    2. **Entity is tracked by this stream** — the connection is bound to the entity's tag scope and is disconnected automatically when the entity loses its tag or is destroyed.
    3. **Entity has a parent but is not in this stream** — the connection is bound to the entity's object lifetime and is disconnected when the entity is destroyed.
    4. **Entity has no parent** — the connection is disconnected immediately, before returning.

!!! warning "Asynchronous Initial Callback"
    The initial callback does not fire synchronously inline. It is scheduled to run on the next available frame. Do not write code that depends on the initial callback having already executed by the time `ObserveAttribute` returns.

!!! note "Studio Only"
    `Entity` must be a `PVInstance`; `Key` must be a non-empty string of no more than 100 characters; `Callback` must be a function. Violations throw errors.

---

## StampStream:Destroy (Local)

Destroys the stream.

**Scenario A — Teardown after a match phase ends**

```luau
local function onPhaseEnd()
    -- All tracked instances are untagged (Signals.Untagged fires for each),
    -- then all internal listeners and signal objects are released
    enemyStream:Destroy()
    enemyStream = nil
end
```

**Scenario B — Re-creating a stream after destruction**

```luau
-- Destroying and re-registering gives you a completely fresh stream
enemyStream:Destroy()

-- Safe to re-register the same tag name
enemyStream = Stamp.Register("Enemy")
```

---

## Signals.Tagged

Fires when an instance receives the tag. Provides a scope for safe resource binding.

**Scenario A — Setting up per-entity behaviour with scope-bound resources**

```luau
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    -- Initialize state
    enemyStream:SetAttribute(entity, "Health", 200)

    -- This connection is automatically cleaned up when the entity is untagged
    scope:Connect(entity.PrimaryPart.Touched, function(hit)
        if hit.Parent:FindFirstChild("Humanoid") then
            print(entity.Name .. " touched a player")
        end
    end)

    -- This loop stops automatically when the entity is untagged
    scope:Repeat(-1, 2, function()
        print(entity.Name .. " is still alive")
    end)
end)
```

**Scenario B — Connecting after instances are already tagged (retroactive replay)**

```luau
-- Three enemies were tagged before this Connect call.
-- The callback is scheduled immediately for all three of them —
-- no instances are missed.
enemyStream.Signals.Tagged:Connect(function(entity, scope)
    print(entity.Name .. " processed")
end)
-- Prints three times on the next frame for pre-existing enemies,
-- then continues firing for any future enemies
```

!!! info "Retroactive Subscription"
    Connecting to `Signals.Tagged` after instances are already tagged does not miss them. Upon connection, the callback is immediately scheduled for every instance the stream is already tracking (provided each instance still has a live parent). This means your setup logic runs for both past and future entities with a single `Connect` call.

!!! note "Studio Only"
    `Callback` must be a function or an error is thrown.

---

## Signals.Untagged

Fires when an instance loses the tag or is destroyed.

**Scenario A — Playing a death effect on untag**

```luau
enemyStream.Signals.Untagged:Connect(function(entity)
    -- entity still exists here (it hasn't been garbage-collected yet)
    ParticleModule.PlayDeathBurst(entity:GetPivot().Position)
    print(entity.Name .. " left the enemy stream")
end)
```

**Scenario B — Counting total enemies defeated over a round**

```luau
local defeated = 0

enemyStream.Signals.Untagged:Connect(function(_entity)
    defeated += 1
    print("Enemies defeated this round: " .. defeated)
end)
```

!!! note "Studio Only"
    `Callback` must be a function or an error is thrown.

!!! tip "Scope Has Already Been Cleaned"
    By the time `Signals.Untagged` fires, the entity's garbage-collection scope has already been destroyed. Any events, loops, or tasks that were bound to that scope are no longer running. You can still read properties from the entity itself — it has not been destroyed yet — but you cannot rely on any scope-bound behaviour still being active.