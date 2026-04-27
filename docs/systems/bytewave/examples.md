# Examples

Practical, scenario-based examples for every ByteWave API and method.

---

## ByteWave Server

---

### `Inject` *(server)*

Injects an external library into the ByteWave suite before game logic starts. Two keys are accepted: `"Assignment"` replaces the internal scheduler; `"Twin"` hands spatial state discovery off to the Twin worker engine.

**Scenario A — Inject the Assignment scheduler**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)
local Assignment = require(game.ServerScriptService.Assignment)

-- Injecting Assignment will change ByteWave's native task scheduler to assignment scheduler
ByteWave.Inject("Assignment", Assignment)
```

**Scenario B — Inject Twin to accelerate spatial state discovery**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)
local Twin = require(game.ServerScriptService.Twin)

-- Twin replaces ByteWave's fixed-count native Actor pool.
-- Spatial discovery math is distributed across all available workers automatically.
ByteWave.Inject("Twin", Twin)
```

!!! warning "Twin Injection"
    `Twin` doesnt require strict timing when to inject the system onto `ByteWave` system but injection during mid-operation will guarantee data loss within the transition period.

**Scenario C — Inject both at initialization**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)
local Assignment = require(game.ServerScriptService.Assignment)
local Twin = require(game.ServerScriptService.Twin)

-- Injecting both overrides system to ByteWave
ByteWave.Inject("Assignment", Assignment)
ByteWave.Inject("Twin", Twin)
```

!!! info "Best Practice"
    It is still best to inject overrides to `ByteWave` if you wish to use them at the very start of the codebase before any real game logic begins. This ensures data entegrity and will guarantee no data loss since `ByteWave` will be ready when real game logics ever gets processed.

---

### `Send` *(server)*

Queues a packet for delivery to one player or all players. Defaults to reliable delivery. Flushed at the end of the current frame.

**Scenario A — Broadcast a global event to all players**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

-- No ____TargetPlayer specified — the packet goes to every connected client.
ByteWave.Send("GameEvents", "RoundStarted", { RoundNumber = 1, Duration = 120 })
```

**Scenario B — Send a targeted reliable packet to one player**

```luau
-- Only the winning player receives their updated score.
-- ____InternString = true registers "Score" once; every future send on this gateway and path costs 2 bytes.
ByteWave.Send("PlayerData", "Score", newScore, {
    ____TargetPlayer = winningPlayer,
    ____IsReliable   = true, -- Channel in use (True for Reliable, False for Unreliable)
    ____InternString = true, -- Converts string into 2 bytes integer representation
})
```

**Scenario C — Unreliable high-frequency position broadcast**

```luau
-- Position data sent every frame can afford to be unreliable.
game:GetService("RunService").Heartbeat:Connect(function()
	ByteWave.Send("WorldSync", "EnemyPosition", { 
		X = pos.X, 
		Z = pos.Z 
	}, {
		____IsReliable   = false, -- Channel to use (False = Unreliable)
		____InternString = true,  -- interned once; all subsequent sends cost 2 bytes
	})
end)
```

---

### `Listen` *(server)*

Registers a callback for every inbound packet arriving on a named gateway. Returns a `DisconnectObject`.

**Scenario A — Path multiplexing inside a single gateway listener**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

-- One listener handles all Combat paths — no separate RemoteEvent per action.
ByteWave.Listen("Combat", function(packet)
    local player = packet.Player

    if packet.Path == "DealDamage" then
        applyDamage(player, packet.Value.Target, packet.Value.Amount)

    elseif packet.Path == "ApplyEffect" then
        applyEffect(player, packet.Value.Effect)

    elseif packet.Path == "Knockback" then
        applyKnockback(player, packet.Value.Direction)
    end
end)
```

**Scenario B — Auto-disconnect when an Instance is destroyed**

```luau
local Zone = workspace.BattleZone

-- The listener is removed automatically when BattleZone is destroyed.
-- No manual :Disconnect() call is needed in cleanup code.
ByteWave.Listen("BattleZone", function(packet)
	handleZoneAction(packet.Player, packet.Path, packet.Value)
end, { 
	____BindTo = Zone -- The third parameter which is a config table has a property called "____BindTo" which accepts a `BasePart` or `Model`. It attaches this listener into the lifetime of the bounded object, when that object's lifetime reached, the listener dies also alongside it.
})
```

**Scenario C — Manual disconnect after a timed event**

```luau
local connection = ByteWave.Listen("Puzzle", function(packet)
    recordSubmission(packet.Player, packet.Value)
end)

-- When the event ends, stop receiving stale submissions.
task.delay(60, function()
    connection:Disconnect()
end)
```

!!! note "Logical Routers"
    `Gateways` and `Paths` are just purely logical routers in ByteWave's system, when you want to establish a new gateway or a new path, it doesn't mean it creates another set of `RemoteEvents`, instead the system will just create another router node that points to another new discovered gateways or paths so that the next time these gateways or paths is used again, it will just grab the existing node instead of creating a new one.

!!! tip "Conservative Programming"
    `ByteWave` does supports `Gateway` and `Path` with identical names. When you create both gateway and path with lets say named it "Hello", this is perfectly safe and will save you a half slot of the registry. Because ByteWave only uses single registry for its interning mechanism, a single "Hello" string when intern would only contain one ID (for example 10) so when you write `Gateway = "Hello` and `Path = "Hello` both gets converted to ID 10 which only consume one slot in the registry.

---

### `SpatialSend`

Delivers a packet only to players within a configured radius of a world anchor. Unreliable by default.

**Scenario A — Cylindrical radius (horizontal only, ignores vertical)**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)
local Explosion = workspace.ExplosionPart

-- Only players within 100 horizontal studs receive this.
-- ____IsReliable = true ensures no client within range misses a one-shot event.
ByteWave.SpatialSend("Effects", "Shockwave", { 
	Power = 80 
}, Explosion, {
	____Radius = 100, -- The radius in X axis = 100, Y axis automatically gets affected within ±50 Radius (per configuration default in the framework)
	____IsReliable = true,
})
```

**Scenario B — True spherical radius for a floating platform**

```luau
local Platform = workspace.FloatingPlatform

-- ____Use3D = true: vertical distance counts fully.
-- Players directly below or above but outside the sphere do not receive this.
ByteWave.SpatialSend("PlatformAudio", "Ambience", audioId, Platform, {
    ____Radius = 80, -- The radius in X axis and Y axis = 80 studs gets calculated in full sphere
    ____Use3D = true,
    ____IsReliable = false,
    ____InternString = true, -- Only activate interning if and only if this event is repeating
})
```

**Scenario C — Repeating per-frame position update to nearby players**

```luau
local NPC = workspace.EnemyNPC

-- Example a mini map update with radar system
game:GetService("RunService").Heartbeat:Connect(function()
    ByteWave.SpatialSend("NPCSync", "Position", {
        X = NPC.PrimaryPart.Position.X,
        Z = NPC.PrimaryPart.Position.Z,
    }, NPC.PrimaryPart, {
        ____Radius     = 100,
        ____IsReliable = false,
    })
end)
```

---

### `SetGatewayWhitelist`

Restricts a gateway so only clients whose UserId is in the list can send packets through it. All others are silently dropped before any listener sees them.

**Scenario A — Admin-only command gateway**

```luau
local ByteWave  = require(game.ServerScriptService.ByteWave)
local ADMIN_IDS = { 123456789, 987654321 }

ByteWave.SetGatewayWhitelist("AdminCommands", ADMIN_IDS)

-- Displays a world notification into the game
ByteWave.Listen("AdminCommands", function(packet)
    worldNotification(packet.Value)
end)
```

**Scenario B — Restrict a gateway to a single player (e.g. session host)**

```luau
-- Only the host player can send on this gateway during their session.
ByteWave.SetGatewayWhitelist("HostControls", { hostPlayer.UserId })

-- Controller listener to the event
ByteWave.Listen("HostControls", function(packet)
    if packet.Path == "StartGame" then startGame() end
    if packet.Path == "EndGame" then endGame() end
end)
```

**Scenario C — Cleaning an existing protected gateway**

```luau
-- Setting the value to nil will clear the registry and makes the gateway public again
ByteWave.SetGatewayWhitelist("AdminRoom", nil)
```

---

### `SetRequestHandler`

Registers a handler for client RPC calls. The handler's return value is automatically routed back to the requesting client's `Request` call.

**Scenario A — Inventory lookup**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

ByteWave.SetRequestHandler("Inventory", function(player, query)
    local item = InventoryService.GetItem(player, query.ItemId)

    return item -- becomes the second return of the client's ByteWave.Request()
end)
```

**Scenario B — Leaderboard fetch with failure handling**

```luau
ByteWave.SetRequestHandler("Leaderboard", function(player, query)
    local success, data = pcall(LeaderboardService.Fetch, query.Category)

    if not success then
        return nil  -- client receives (false, errorString) automatically
    end

    return data
end)
```

**Scenario C — DataStore-backed profile load**

```luau
ByteWave.SetRequestHandler("Profile", function(player, _query)
    -- This may yield for a DataStore call — ByteWave handles the async routing.
    local profile = DataService.LoadProfile(player)

    return profile
end)
```

---

### `AttachMiddleware`

Attaches a function that intercepts every inbound packet before any listener receives it. Return `false` to drop the packet silently.

**Scenario A — Block all traffic during a maintenance window**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)
local maintenanceMode = false

ByteWave.AttachMiddleware(function(packet)
    -- System packets are not passed through middleware and are never affected.
    if maintenanceMode then
        return false  -- silently drop everything during maintenance
    end
end)
```

**Scenario B — Validate payload structure before it reaches listeners**

```luau
ByteWave.AttachMiddleware(function(packet)
    -- Drop any Trading packet that arrives without a required ItemId field.
    if packet.Gateway == "Trading" then
        local value = packet.Value

        if type(value) ~= "table" or not value.ItemId then
            return false
        end
    end
    -- All other packets, and valid Trading packets, fall through.
end)
```

**Scenario C — Record Transactions**

```luau
ByteWave.AttachMiddleware(function(packet)
	if packet.Gateway == "Purchase" then
            task.defer(recordPurchase, packet)
	end
      -- Returning nil allows the packet through.
end)
```

---

### `PlayerAdded`

Fires once per player after ByteWave's connection handshake completes. Use this instead of `Players.PlayerAdded` when you need to send data to a player immediately on join.

**Scenario A — Send initial world state the moment a player is ready**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

ByteWave.PlayerAdded(function(player)
    -- The client's string registry is synchronized at this point.
    -- Named paths are safe to use immediately.
    ByteWave.Send("Init", "WorldSeed", currentSeed, {
        ____TargetPlayer = player,
        ____InternString = true,
    })
end)
```

**Scenario B — Create a private state and send it to the joining player**

```luau
ByteWave.PlayerAdded(function(player)
	-- DataStore load may yield — that is fine here.
	local profile = DataService.LoadProfile(player)
	local playerState = ByteWave.State.CreateState(
		"Player_" .. player.UserId,
		{ 
			Coins = profile.Coins, 
			Level = profile.Level 
		},
		"Private",
		player
	)
end)
```

---

## ByteWave.State — Server

---

### `SetSpatialRoot`

Overrides the workspace scope used for all spatial overlap queries. After calling this, ByteWave restricts spatial discovery to descendants of the specified folder. Must be called before creating any spatial states.

**Scenario A — Limit spatial queries to a specific map zone**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

-- Spatial discovery only considers objects inside MapZone.
-- Objects elsewhere in the workspace are ignored entirely.
local MapZone = workspace.CurrentMap

ByteWave.State.SetSpatialRoot(MapZone)

-- All subsequent spatial states will be scoped to MapZone.
ByteWave.State.CreateState("Pickup_01", { 
	Type = "Ammo"
}, "Spatial_Global", nil, MapZone.AmmoBox, 20)
```

**Scenario B — Switch the spatial root when the map changes**

```luau
local function onMapChanged(newMap)
    ByteWave.State.SetSpatialRoot(newMap)
end
```

!!! warning "Cleanup Before Re-Assign SpatialRoot"
    Because `SetSpatialRoot` heavily tied with ByteWave's spatial system, calling SetSpatialRoot to assign a new folder will make the existing spatial states invisible to clients. Ensure previous states are cleaned up properly before assigning a new spatial root folder.

---

### `CreateState`

Creates, registers, and immediately replicates a server-owned data object to eligible clients. The `Scope` argument determines which clients receive it and how they discover it — choose the wrong scope and clients either receive data they should not see, or never receive data they should.

!!! info "What happens the moment CreateState is called"
    ByteWave registers the new state in its internal `ActiveStates` dictionary under the provided `UniqueID`. For `Global`, `Private`, and `Filtered` scopes, a full replication packet (`OP_REPLICATE`) is queued immediately — the client receives the complete initial data table in the same frame flush. For all three `Spatial_*` scopes, no replication happens at creation time. Instead, ByteWave's spatial discovery loop (running every 300ms in parallel across Actor workers) will detect which players are within the anchor's radius and only then send the snapshot to each newly-in-range client.

!!! danger "UniqueID must be globally unique"
    Calling `CreateState` with a `UniqueID` that is already registered raises an error in Studio and produces undefined behaviour in production. Always include a player-specific or object-specific suffix (e.g. `"Inv_" .. player.UserId`) whenever creating per-player or per-object states.

---

**Scenario A — `Global` scope: visible to every connected client**

Every player currently connected receives the state immediately. Players who join later receive it automatically during their handshake full-sync.

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

local gameState = ByteWave.State.CreateState("GameState", {
    Phase = "Lobby",
    Players = 0,
    MaxRound = 5,
}, "Global")

-- Any subsequent mutation replicates to ALL clients automatically.
gameState:Set("Phase", "Active")
gameState:Increment("Players", 1)
```

!!! info "Behind the scenes — Global"
    `CreateState` immediately queues a replication broadcast. Every connected player's client receives the full data table in the next Heartbeat flush. Late-joining players receive it through the full-sync request that fires on their handshake completion.

---

**Scenario B — `Private` scope: delivered to exactly one player**

Only the named owner ever receives or observes this state. No other player is aware it exists.

```luau
ByteWave.PlayerAdded(function(player)
	local inventory = ByteWave.State.CreateState("Inv_" .. player.UserId, { 
		Coins = 0, 
		Items = {} 
	}, "Private", player)  -- the fourth argument is the owner
	inventory:Increment("Coins", 100) -- Adding 100 to the coins key
end)
```

!!! info "Behind the scenes — Private"
    Replication is sent only to the named owner. Every subsequent mutation — `Set`, `Increment`, etc. — is also routed exclusively to that player. No other client ever sees a packet for this state. When the owner leaves and `Destroy` is called, only that player receives the destroy state signal.

---

**Scenario C — `Filtered` scope: shared with an explicit allow-list**

Only the players passed in the allow-list receive and observe the state. Members can be added or removed later with `AddFilter` / `RemoveFilter`.

```luau
local function createPartyState(partyMembers: { Player })
	local partyState = ByteWave.State.CreateState("Party_" .. partyMembers[1].UserId, { 
		Size = #partyMembers, 
		Leader = partyMembers[1].DisplayName 
	}, "Filtered", partyMembers)  
	-- pass the array, ByteWave builds the internal filter map
	-- Must be an array of Player object { Player }
	return partyState
end
```

!!! info "Behind the scenes — Filtered"
    ByteWave converts the player array into an internal `{ [Player]: boolean }` hash-map at creation time. Replication is sent individually to each member in the list. Mutations are routed per-member through the same map. Adding a player later via `AddFilter` sends them a full snapshot at that point; `RemoveFilter` sends them destroy state signal to clear their local copy.

---

**Scenario D — `Spatial_Global` scope: discovered by proximity, visible to all players in range**

Any player who walks within the anchor's radius receives the full snapshot. Any player who leaves the radius receives a destroy signal and loses the local copy.

```luau
local chest = workspace.TreasureChest

local chestState = ByteWave.State.CreateState("Chest_01", 
	{ 
		IsOpen = false, 
		Contents = { "Gold", "Potion" } 
	}, "Spatial_Global", nil, chest, 30)
-- nil = no owner restriction; all players in range can see it
-- chest = the anchor BasePart or Model
-- 30 = radius in studs
```

!!! info "Behind the scenes — Spatial_Global"
    No replication happens at creation time. Every 300ms, ByteWave's spatial worker loop evaluates every player's position against all registered spatial anchors in parallel. When a player enters the 30-stud radius for the first time, replication is sent with the full snapshot. When they leave, destroy state signal is sent and their local visibility record is cleared. Mutations that occur while a player is in range are forwarded to all current observers.

---

**Scenario E — `Spatial_Private` scope: proximity-gated, only the owner sees it**

The state only replicates when the owner player is within the anchor's radius. If the owner leaves the radius, their local copy is destroyed. No other player ever receives it.

```luau
-- A player's personal quest marker that only appears when they are near it.
ByteWave.PlayerAdded(function(player)
	local marker = workspace.QuestMarkers:FindFirstChild("Marker_" .. player.UserId)
	if not marker then return end

	ByteWave.State.CreateState("QuestMarker_" .. player.UserId, { 
		QuestId = "Main_01", 
		Progress = 0 
	}, "Spatial_Private", player, marker, 50)
	-- player = owner: only this player
	-- marker = anchor
	-- 50 = radius in studs
end)
```

!!! info "Behind the scenes — Spatial_Private"
    The spatial worker evaluates position and scope together. Even if the player is within range, the packet is only sent to the owner of this private spatial state. A different player standing next to the anchor receives nothing. The owner's range entry and exit still trigger full snapshots and destroy signals respectively.

---

**Scenario F — `Spatial_Filtered` scope: proximity-gated, only allow-listed players see it**

A combination of `Filtered` and spatial. Only players both in the allow-list and within the radius receive the state.

```luau
local function createTeamObjective(teamMembers: { Player }, objectivePart: BasePart)
	return ByteWave.State.CreateState("Objective_" .. objectivePart.Name, { 
		Captured = false, 
		Progress = 0 
	}, "Spatial_Filtered", teamMembers, objectivePart, 75)
	-- only these players can ever receive it
	-- anchor
	-- radius in studs
end
```

!!! info "Behind the scenes — Spatial_Filtered"
    The spatial worker checks two conditions per player: their position is within radius AND their UserId is in the state's filter map. Both must be true for a snapshot to be sent. A player added to the filter via `AddFilter` while already in range will receive the snapshot immediately. A player removed via `RemoveFilter` while in range receives destroy state signal regardless of their position.

---

**Scenario G — Parent-child hierarchy**

A child state links itself to a parent at creation time. ByteWave tracks the relationship and, when the parent is destroyed, destroys all children from the deepest level up before destroying the parent itself.

```luau
-- Parent state: player profile
local playerState = ByteWave.State.CreateState("Player_" .. player.UserId, { 
	Level = 1, 
	XP = 0 
}, "Private", player)

-- Child state: inherits Private scope and owner from parent automatically.
-- Passing nil for Scope and OwnerOrFilter triggers inheritance.
local weaponState = ByteWave.State.CreateState("Weapon_" .. player.UserId, { 
	Equipped = "Sword", 
	Durability = 100 
}, nil, nil, nil, nil, { 
	____Parent = playerState 
}
-- inherit scope from parent
-- inherit owner from parent
-- no spatial anchor
-- no radius
)

-- Grandchild: also inherits down the chain.
local enchantState = ByteWave.State.CreateState("Enchant_" .. player.UserId, { 
	Element = "Fire", 
	Level = 2 
}, nil, nil, nil, nil, { 
	____Parent = weaponState 
})
```

!!! info "Behind the scenes — hierarchy destruction order"
    When `playerState:Destroy()` is called, ByteWave walks the children array in reverse order. `enchantState` is destroyed first (its destroy state signal is sent, its timers are cancelled, it is removed from the registry), then `weaponState`, and finally `playerState`. This guarantees that a grandchild's destroy callback fires before its parent's, so any logic that references the parent state is still valid at the time the child teardown runs.

!!! warning "Scope inheritance is a one-time copy"
    Scope and owner/filter are resolved from the parent at the moment `CreateState` is called. If the parent's owner changes after the child is created, the child's owner does not update automatically. For dynamic ownership you must manage each state's owner explicitly.

---

**Scenario H — Edge case: creating a Spatial state without an anchor**

ByteWave allows this but warns in Studio. The state is registered and mutations work normally, but no client ever discovers it spatially since there is no position to evaluate.

```luau
-- This is valid code but the state will never replicate to any client
local floatingState = ByteWave.State.CreateState("Orphan_01", { 
	Value = 42 
}, "Spatial_Global")
-- no anchor, no radius
-- In Studio: [ByteWave_State] Warning: Creating Spatial State 'Orphan_01'
-- without an Anchor. It will never be discovered.
```

!!! warning "Anchorless spatial states are invisible"
    An anchorless `Spatial_*` state consumes a registry slot and participates in dirty-queue processing, but the spatial discovery loop has no position to evaluate so no client ever enters or leaves its range. If you need a state that starts invisible and becomes discoverable later, create it with a `nil` anchor and reassign the anchor field before the next spatial tick — or use `Filtered` scope and manage visibility manually with `AddFilter`.


---

### `GetState` *(server)*

Returns the registered `StateObject` for the given ID, or `nil` if no state with that ID exists.

**Scenario A — Retrieve and mutate an existing state from another script**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

-- Get the state created from somewhere in the codebase
local gameState = ByteWave.State.GetState("GameState")

if gameState then
	gameState:Set("Phase", "Ended") -- Manipulate the state here in this script
end
```

**Scenario B — Guard against a state that may not exist yet**

```luau
local function addPlayerKill(player: Player)
    local stats = ByteWave.State.GetState("Stats_" .. player.UserId)

    if not stats then
        warn("Stats state not ready for", player.Name)

        return
    end

    stats:Increment("Kills", 1)
end
```

---

### `GetActiveStates`

Returns the complete dictionary of all currently registered states, keyed by their `UniqueID`. The returned table is a direct reference to ByteWave's live registry — do not modify it.

!!! warning "Do not modify the returned table"
    `GetActiveStates` returns the internal registry by reference, not a copy. Inserting or removing entries directly will corrupt ByteWave's state tracking. To remove a state, call `state:Destroy()` — never `ActiveStates[id] = nil`.

**Scenario A — Bulk update all states matching a naming pattern**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

local allStates = ByteWave.State.GetActiveStates()

for id, state in allStates do
    if string.find(id, "Chest_") then
        state:Set("IsOpen", false)  -- reset all chests at round end
    end
end
```

**Scenario B — Diagnostic endpoint: count active states by category**

```luau
ByteWave.SetRequestHandler("AdminDiag", function(player, _)
	local states  = ByteWave.State.GetActiveStates()
	local counts  = { 
		Player = 0,
		Chest = 0, 
		Party = 0, 
		Other = 0 
	}

	for id, _ in states do
		if string.find(id, "Player_")  then 
			counts.Player += 1

		elseif string.find(id, "Chest_")  then 
			counts.Chest  += 1

		elseif string.find(id, "Party_")  then 
			counts.Party  += 1

		else
			counts.Other  += 1
		end
	end

	return counts
end)
```

**Scenario C — Full cleanup on round end: destroy all round-scoped states**

When a round ends, all states that were created for that round need to be destroyed cleanly so their clients receive destroy state signal and their timers are cancelled before the next round starts.

```luau
local function cleanupRoundStates()
	local allStates = ByteWave.State.GetActiveStates()

	-- Collect IDs first — destroying mid-iteration mutates the registry.
	local toDestroy = {}
	
	for id, state in allStates do
		if string.find(id, "Round_") or string.find(id, "Chest_") then
			table.insert(toDestroy, state)
		end
	end

	for _, state in toDestroy do
		state:Destroy()
	end
end
```

!!! danger "Never destroy states while iterating GetActiveStates"
    `state:Destroy()` removes the entry from the live registry that `GetActiveStates` returned. Calling it inside a `for id, state in allStates do` loop will corrupt the iterator. Always collect the states you want to destroy into a separate array first, then destroy them after the loop as shown above.

**Scenario D — Cleanup all states owned by a leaving player**

```luau
game:GetService("Players").PlayerRemoving:Connect(function(player)
	local allStates = ByteWave.State.GetActiveStates()
	local toDestroy = {}
	
	for id, state in allStates do
		-- Collect any state privately owned by this player.
		if state.Owner == player then
			table.insert(toDestroy, state)
		end
		
		-- Also remove them from any filtered states they belong to.
		if state.Filter and state.Filter[player] then
			state:RemoveFilter(player)
		end
	end

	for _, state in toDestroy do
		state:Destroy()
	end
end)
```

!!! info "Why collect then destroy"
    Destroying a state cancels its timers, fires destroy state signal to observers, removes it from `ActiveStates`, and recurses into children. All of this mutates the registry table you are iterating. The collect-then-destroy pattern ensures the iterator sees a consistent snapshot before any mutations begin.

!!! info "Automated Cleanup"
    `ByteWave` handles the cleanup automatically every single time there are players leaving. Creating another clean up routine is redundant when working with ByteWave, trust the framework in cleaning its own memory mess.

---

## StateObject — Server Methods

---

### `Set`

Sets a key to a new value. If the value changes, the update is replicated to eligible clients. Supports slash-delimited paths for deeply nested fields.

**Scenario A — Update a top-level key**

```luau
gameState:Set("Phase", "Active")
```

**Scenario B — Update a deeply nested field without touching the rest of the table**

```luau
-- Updates Stats → Combat → Kills without replacing Stats or Stats/Combat
playerState:Set("Stats/Combat/Kills", kills + 1)
```

**Scenario C — Delete a key by setting it to nil**

```luau
-- Removes the "TemporaryBuff" key from the state and replicates the deletion.
playerState:Set("TemporaryBuff", nil)
```

---

### `Get` *(server)*

Returns the current server-side value at the given key. Supports slash-delimited deep paths.

**Scenario A — Read a top-level value**

```luau
local phase = gameState:Get("Phase")

print("Current phase:", phase)
```

**Scenario B — Read a nested value**

```luau
local kills = playerState:Get("Stats/Combat/Kills")

if kills >= 10 then
    awardBadge(player, "FirstBlood")
end
```

---

### `AddFilter`

Adds a player to a `Filtered` or `Spatial_Filtered` state's allow-list. The player immediately receives a full snapshot of the current state data.

**Scenario A — Add a player to a party state when they join the party**

```luau
local partyState = ByteWave.State.GetState("Party_001")

if partyState then
    partyState:AddFilter(newMember)
    -- newMember immediately receives the full party state snapshot.
end
```

**Scenario B — Dynamically grant access to a restricted zone state**

```luau
local zoneState = ByteWave.State.GetState("SecretZone")

if zoneState and playerHasPermission(player) then
    zoneState:AddFilter(player)
end
```

---

### `RemoveFilter`

Removes a player from a `Filtered` or `Spatial_Filtered` state's allow-list. The player receives a destroy signal and their local copy is cleaned up.

**Scenario A — Remove a player from a party state when they leave the party**

```luau
local partyState = ByteWave.State.GetState("Party_001")

if partyState then
    partyState:RemoveFilter(leavingMember)
    -- leavingMember's client receives a destroy signal and removes the state locally.
end
```

**Scenario B — Revoke zone access**

```luau
local zoneState = ByteWave.State.GetState("SecretZone")

if zoneState then
    zoneState:RemoveFilter(player)
end
```

---

### `Append`

Adds a value after the highest currently occupied numeric index in the state data.

**Scenario A — Add an item to the end of an inventory list**

```luau
-- Appends "Potion" after whatever is currently the last numeric entry.
inventoryState:Append("Potion")
inventoryState:Append("Sword")
-- Result: { [1] = "Potion", [2] = "Sword" }
```

**Scenario B — Log game events into a state list**

```luau
matchLog:Append({ Timestamp = os.clock(), Message = "Round started" })
matchLog:Append({ Timestamp = os.clock(), Message = "First kill registered" })
```

---

### `Remove`

Removes the value at the specified key or numeric index. When operating on a numeric index, `EnableShifting` controls how the list is restructured.

**Scenario A — Delete a string key (simple delete)**

```luau
-- Removes the key entirely. No list reordering.
inventoryState:Remove("EquippedSword")
```

**Scenario B — Delete a numeric index without restructuring (leaves a gap)**

```luau
-- Index 3 becomes nil; indices 4, 5, ... are untouched.
inventoryState:Remove(3)
```

**Scenario C — Tail swap (`EnableShifting = false`) — O(1), order not preserved**

```luau
-- The last element moves into the vacated slot. Fast for unordered lists.
inventoryState:Remove(2, false)
-- Before: { [1]="Sword", [2]="Shield", [3]="Helmet", [4]="Boots" }
-- After:  { [1]="Sword", [2]="Boots", [3]="Helmet" }
```

**Scenario D — Sequential shift (`EnableShifting = true`) — O(n), order preserved**

```luau
-- Every element above index 1 shifts down. Use for ordered queues or ranked lists.
inventoryState:Remove(1, true)
-- Before: { [1]="Sword", [2]="Shield", [3]="Helmet", [4]="Boots" }
-- After:  { [1]="Shield", [2]="Helmet", [3]="Boots" }
```

---

### `Swap`

Exchanges the values at two keys within the state in a single replicated operation.

**Scenario A — Swap two leaderboard positions**

```luau
-- Swap first and second place in a ranked list.
leaderboardState:Swap(1, 2)
```

**Scenario B — Swap two inventory slots**

```luau
-- Move item from slot 3 to slot 7 and vice-versa.
inventoryState:Swap(3, 7)
```

---

### `Patch`

Sets multiple keys to the same boolean value in one replicated call. Useful for bulk flag operations.

**Scenario A — Clear all quest completion flags at once**

```luau
questState:Patch({ "Quest1Done", "Quest2Done", "Quest3Done" }, false)
```

**Scenario B — Mark multiple achievements as unlocked**

```luau
achievementState:Patch({ "FirstKill", "FirstWin", "FirstCraft" }, true)
```

---

### `Toggle`

Flips the boolean stored at the given key.

**Scenario A — Toggle a chest open/closed**

```luau
chestState:Toggle("IsOpen")
-- If IsOpen was false, it becomes true and replicates; and vice-versa.
```

**Scenario B — Toggle a door lock state**

```luau
doorState:Toggle("IsLocked")
```

---

### `Increment`

Adds `Amount` to the numeric value at `TargetKey`. Treats a missing key as zero.

**Scenario A — Add score when a player earns points**

```luau
playerState:Increment("Score", 50)
```

**Scenario B — Track kills in a match**

```luau
matchState:Increment("TotalKills", 1)
playerState:Increment("Kills", 1)
```

---

### `Decrement`

Subtracts `Amount` from the numeric value at `TargetKey`.

**Scenario A — Spend coins on a purchase**

```luau
playerState:Decrement("Coins", itemPrice)
```

**Scenario B — Reduce ammo on fire**

```luau
weaponState:Decrement("Ammo", 1)

if weaponState:Get("Ammo") <= 0 then
    triggerReload(player)
end
```

---

### `Multiply`

Multiplies the numeric value at `TargetKey` by `Amount`.

**Scenario A — Apply a damage multiplier to a stat**

```luau
-- Double the player's damage stat.
playerState:Multiply("Damage", 2)
```

**Scenario B — Scale a reward by a bonus factor**

```luau
playerState:Multiply("Score", bonusMultiplier)
```

---

### `Divide`

Divides the numeric value at `TargetKey` by `Amount`. `Amount` must not be zero.

**Scenario A — Halve a resource on a penalty event**

```luau
playerState:Divide("Coins", 2)
```

**Scenario B — Normalize a stat to a per-round value**

```luau
-- After 5 rounds, store average kills per round.
matchState:Divide("TotalKills", 5)
```

---

### `SetTemporary`

Sets a key to a value for a fixed duration, then automatically reverts to the previous value or deletes the key.

**Scenario A — Timed speed boost that reverts on expiry**

```luau
-- SpeedMultiplier becomes 2.0 for 10 seconds, then restores to whatever it was before.
-- Calling SetTemporary again on the same key before expiry cancels the old timer.
playerState:SetTemporary("SpeedMultiplier", 2.0, 10, true)
```

**Scenario B — Temporary debuff that clears on expiry**

```luau
-- "Stunned" key is set to true, then deleted (not reverted) after 3 seconds.
playerState:SetTemporary("Stunned", true, 3, false)
```

**Scenario C — Timed zone access flag**

```luau
-- Grant access for 30 seconds, then automatically remove the flag.
playerState:SetTemporary("ZoneAccess", true, 30, false)
```

---

### `Destroy` *(server StateObject)*

Cancels all active timers on this state, destroys all child states (deepest-first), sends a destroy signal to all eligible clients, and unregisters the state from the active registry.

**Scenario A — Destroy a chest state when the chest is removed from the world**

```luau
local chestState = ByteWave.State.GetState("Chest_01")

workspace.TreasureChest.Destroying:Connect(function()
    if chestState then
        chestState:Destroy()
        -- All observing clients receive a destroy packet and clean up their local copy.
    end
end)
```

**Scenario B — Clean up a player's private states on leave**

```luau
game:GetService("Players").PlayerRemoving:Connect(function(player)
    local inventory = ByteWave.State.GetState("inventory_"    .. player.UserId)
    local weapon = ByteWave.State.GetState("Weapon_" .. player.UserId)

    if inventory then inventory:Destroy() end
    if weapon then weapon:Destroy() end
end)
```

---

## ByteWave.Action — Server

---

### `Register`

Registers a named handler that fires when a client sends an action with the matching name. An optional configuration table can be stored alongside the handler and retrieved with `GetConfig`.

**Scenario A — Register an action with configuration metadata**

```luau
local ByteWave = require(game.ServerScriptService.ByteWave)

ByteWave.Action.Register("PurchaseItem", {
	MaxPerMinute  = 10,
	RequiredLevel = 5,
}, function(player, payload)
	local config = ByteWave.Action.GetConfig("PurchaseItem")
	
	if not meetsRequirements(player, config) then return end
	
	processPurchase(player, payload.ItemId)
end)
```

**Scenario B — Register an action with no configuration**

```luau
ByteWave.Action.Register("RequestRespawn", nil, function(player, _payload)
    if canRespawn(player) then
        spawnPlayer(player)
    end
end)
```

---

### `GetConfig`

Returns the configuration table stored when `Register` was called for the named action. Returns `nil` if the action is not registered or was registered without a config.

**Scenario A — Read config inside the handler**

```luau
ByteWave.Action.Register("CastSpell", {
	Cooldown = 2,
	ManaCost = 30,
	MaxDistance = 50,
}, function(player, payload)
	local config = ByteWave.Action.GetConfig("CastSpell")
	
	if player:GetAttribute("Mana") < config .ManaCost then return end
	
	castSpell(player, payload.SpellId, config .MaxDistance)
end)
```

**Scenario B — Read config from outside the handler (e.g. a validation module)**

```luau
local function validateAction(actionName: string, player: Player): boolean
    local config = ByteWave.Action.GetConfig(actionName)

    if not config then return true end  -- no restrictions

    return player.Level >= (config.RequiredLevel or 0)
end
```

---

## ByteWave Client

---

### `Inject` *(client)*

Injects an external library within the Lazy Games Suite of Tools environment. Currently supports the **Assignment** library.

**Scenario A — Inject Assignment on the client**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)
local Assignment = require(game.StarterPlayerScripts.Assignment)

-- Inject at the top of the client bootstrap script, before any game logic.
ByteWave.Inject("Assignment", Assignment)
```

**Scenario B — Conditional injection based on environment**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)

-- Only inject in production where Assignment is available.
local ok, Assignment = pcall(require, game.StarterPlayerScripts.Assignment)
if ok then
    ByteWave.Inject("Assignment", Assignment)
end
```

---

### `Send` *(client)*

Queues a packet to be delivered to the server on the next Heartbeat. Reliable by default.

**Scenario A — Send a reliable user action**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)

-- A button press that must not be lost in transit.
ByteWave.Send("Combat", "DealDamage", { 
	Target = targetId, 
	Amount = 25 
})
```

**Scenario B — Send frequent unreliable input**

```luau
-- Mouse position sent every frame
game:GetService("RunService").Heartbeat:Connect(function()
	ByteWave.Send("Input", "MousePosition", { 
		X = mouseX, 
		Y = mouseY 
	}, {
		____IsReliable = false, -- True for Reliable, False for Unreliable
	})
end)
```

---

### `Listen` *(client)*

Registers a callback for packets arriving from the server on the named gateway. Returns a `DisconnectObject`.

**Scenario A — Handle multiple server events on a single gateway**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)

ByteWave.Listen("GameEvents", function(packet)
    if packet.Path == "RoundStarted" then
        UI.ShowCountdown(packet.Value.Duration)

    elseif packet.Path == "RoundEnded" then
        UI.ShowResults(packet.Value)

    elseif packet.Path == "PlayerJoined" then
        UI.AddPlayerToList(packet.Value.Name)
    end
end)
```

**Scenario B — Lifetime-bound listener tied to a UI element**

```luau
local screenGui = script.Parent

-- Listener is removed automatically when the ScreenGui is destroyed.
ByteWave.Listen("UIUpdates", function(packet)
	updateDisplay(packet.Path, packet.Value)
end, {
	____BindTo = screenGui 
})
```

**Scenario C — Manual disconnect after a timed phase**

```luau
local lobbyConnection = ByteWave.Listen("Lobby", function(packet)
    handleLobbyEvent(packet.Path, packet.Value)
end)

-- When the game starts, stop listening for lobby packets.
ByteWave.Listen("GameEvents", function(packet)
    if packet.Path == "RoundStarted" then
        lobbyConnection:Disconnect()
    end
end)
```

---

### `Request`

Sends a request to the server and yields until a response arrives or the timeout elapses.

**Scenario A — Fetch inventory data from the server**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)

task.spawn(function()
    local success, data = ByteWave.Request("Inventory", { ItemId = "sword_01" }) -- Send a request/response cycle event. This is identical to how remote function mechanism

    if success then
        displayItem(data)
    else
        warn("Inventory request failed:", data)
    end
end)
```

**Scenario B — Request with a custom timeout for a slow DataStore operation**

```luau
task.spawn(function()
	local success, leaderboard = ByteWave.Request("Leaderboard", { 
		Category = "Weekly" 
	}, {
		____Timeout = 15,  -- allow up to 15 seconds for a DataStore-backed result
	})

	if success and leaderboard then
		populateLeaderboard(leaderboard)
	end
end)
```

**Scenario C — Fetch initial profile data immediately after joining**

```luau
task.spawn(function()
    local success, profile = ByteWave.Request("Profile", nil)

    if not success then
        warn("Profile load failed, using defaults")

        profile = { Coins = 0, Level = 1 }
    end

    applyProfileToUI(profile)
end)
```

---

### `GetServerTime`

Returns an estimate of the current server clock, adjusted for round-trip latency using an exponential moving average.

**Scenario A — Stamp client-side events with server time**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)

local function recordAction(actionName: string)
	local serverStamp = ByteWave.GetServerTime()
	
	ByteWave.Send("Audit", "Action", { 
		Name = actionName,
		At = serverStamp 
	})
end
```

**Scenario B — Drive a countdown display synchronized to the server**

```luau
-- endTime was received via Listen when the round started.
local endTime: number

ByteWave.Listen("GameEvents", function(packet)
    if packet.Path == "RoundStarted" then
        endTime = packet.Value.EndTime
    end
end)

game:GetService("RunService").Heartbeat:Connect(function()
    if not endTime then return end

    local remaining = endTime - ByteWave.GetServerTime()

    UI.SetCountdown(math.max(0, math.floor(remaining)))
end)
```

---

## ByteWave.State — Client

---

### `GetState` *(client)*

Returns the locally cached `StateObject` for the given ID. Yields up to the configured timeout if the state has not arrived yet.

**Scenario A — Wait for a state to arrive and then use it**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)

task.spawn(function()
    -- Yields up to 5 seconds (default). Returns nil on timeout.
    local gameState = ByteWave.State.GetState("GameState")

    if not gameState then
        warn("GameState did not arrive in time")

        return
    end

    UI.SetPhase(gameState:Get("Phase"))
end)
```

**Scenario B — Retrieve a state with a longer custom timeout**

```luau
task.spawn(function()
	-- Give this state up to 15 seconds — it may arrive after a slow DataStore load.
	local profileState = ByteWave.State.GetState("Player_" .. localPlayer.UserId, {
		____Timeout = 15
	})

	if profileState then
		UI.ApplyProfile(profileState:Get("Coins"), profileState:Get("Level"))
	end
end)
```

---

### `OnCreatedState`

Registers a callback that fires whenever a new `StateObject` is received from the server. Also immediately fires for every state that has already arrived before this call.

**Scenario A — React to spatial states entering the player's range**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)

ByteWave.State.OnCreatedState(function(state)
    if string.find(state.UniqueID, "Chest_") then
        spawnChestUI(state)

        -- Clean up the UI when the state is destroyed (player leaves range).
        state:OnDestroyedState(function()
            removeChestUI(state.UniqueID)
        end)
    end
end)
```

**Scenario B — Register listeners for any player-private state on creation**

```luau
ByteWave.State.OnCreatedState(function(state)
    if string.find(state.UniqueID, "Inv_") then
        -- Watch the Coins key for any state whose ID starts with "Inv_".
        state:Listen("Coins", function(newCoins)
            UI.UpdateCoinDisplay(newCoins)
        end)
    end
end)
```

---

## StateObject — Client Methods

---

### `Get` *(client)*

Returns the current locally cached value at the given key. Supports slash-delimited deep paths.

**Scenario A — Read a top-level value**

```luau
local phase = gameState:Get("Phase")

UI.SetPhase(phase)
```

**Scenario B — Read a nested value**

```luau
local kills = playerState:Get("Stats/Combat/Kills")

UI.SetKillCounter(kills)
```

**Scenario C — Guard against a nil value on first read**

```luau
local coins = playerState:Get("Coins") or 0

UI.UpdateCoinDisplay(coins)
```

---

### `Listen` *(client StateObject)*

Registers a callback that fires whenever the server updates the given key. Fires once immediately with the current value if the key is already populated. Returns a `DisconnectObject`.

**Scenario A — Drive a UI label from a live state value**

```luau
task.spawn(function()
    local gameState = ByteWave.State.GetState("GameState")

    if not gameState then return end

    -- Fires immediately with the current Phase, then on every server-side change.
    local phaseConn = gameState:Listen("Phase", function(newPhase, oldPhase)
        UI.SetPhase(newPhase)
    end)

    -- Listener disconnection happens automatically in the background once this state gets destroyed
end)
```

**Scenario B — Listen to a nested path**

```luau
task.spawn(function()
    local playerState = ByteWave.State.GetState("Player_" .. localPlayer.UserId)

    if not playerState then return end

    playerState:Listen("Stats/Combat/Kills", function(newKills)
        UI.SetKillCounter(newKills)
    end)
end)
```

**Scenario C — Watch multiple keys**

```luau
task.spawn(function()
    local inv = ByteWave.State.GetState("Inv_" .. localPlayer.UserId)

    if not inv then return end

    -- listen directly and forget about cleanup, these gets cleaned up automatically in the background once the state gets destroyed
    inv:Listen("Coins", function(value) UI.UpdateCoins(value) end)
    inv:Listen("Level", function(value) UI.UpdateLevel(value) end)
end)
```

---

### `OnDestroyedState`

Registers a callback that fires when the server instructs this state to be destroyed. Returns a `DisconnectObject`.

**Scenario A — Remove world UI when a spatial state leaves range**

```luau
ByteWave.State.OnCreatedState(function(state)
    if string.find(state.UniqueID, "Chest_") then
        local chestUI = spawnChestUI(state)

        -- Called when the player moves out of range or the chest is removed.
        state:OnDestroyedState(function()
            chestUI:Destroy()
        end)
    end
end)
```

---

### `Destroy` *(client StateObject)*

Fires all destroy listeners, clears all key listeners and data, and removes this state from the local registry. Usually called automatically when the server sends a destroy instruction. You may call it manually to proactively clean up.

**Scenario A — Manually destroy a state that is no longer needed**

```luau
-- The server has signaled via a custom gateway that this state is stale.
ByteWave.Listen("Cleanup", function(packet)
    if packet.Path == "RemoveState" then
        local state = ByteWave.State.GetState(packet.Value.StateId)  -- not yet destroyed by server

        if state then
            state:Destroy()  -- fires all OnDestroyedState callbacks then wipes the local copy
        end
    end
end)
```

**Scenario B — Destroy a state when its owner UI is closed**

```luau
task.spawn(function()
	local hudState = ByteWave.State.GetState("HUDState")
	
	if not hudState then return end

	-- If the HUD frame is destroyed manually (e.g. custom UI toggle), clean up the state too.
	local tempConn = script.Parent.Destroying:Connect(function()
		if hudState then
			hudState:Destroy()
			task.delay(1, function()
				tempConn:Disconnect()
				temoConn = nil
			end)
		end
	end)
end)
```

---

## ByteWave.Action — Client

---

### `Send` *(client Action)*

Sends a named action to the server. The server-side handler registered under the same name is called with the player and the payload.

**Scenario A — Trigger a server action from a button press**

```luau
local ByteWave = require(game.StarterPlayerScripts.ByteWave)
local button = script.Parent.PurchaseButton

button.Activated:Connect(function()
	ByteWave.Action.Send("PurchaseItem", { 
		ItemId = "shield_01", 
		Currency = "Gems" 
	})
end)
```

**Scenario B — Send an action with no payload**

```luau
-- Some actions carry no data — just the name is enough.
ByteWave.Action.Send("RequestRespawn")
```

**Scenario C — Send an action in response to a game event**

```luau
ByteWave.Listen("GameEvents", function(packet)
	if packet.Path == "RoundEnded" and packet.Value.Winner == localPlayer.UserId then
		-- Automatically claim a reward when the local player wins.
		ByteWave.Action.Send("ClaimWinReward", { 
			RoundId = packet.Value.RoundId 
		})
	end
end)
```