# Examples

Practical, scenario-based examples for every public API. Each section shows at least two distinct usage patterns with inline commentary.

---

## RegisterTemplate

Declares a data location and its default schema. The returned handle is required for every `FetchData` call.

**Scenario A — Single location, default policy**

```luau
local Diary = require(game.ServerScriptService.Diary)

-- Define what a fresh player's stats look like.
-- Every field here becomes the default for a new player.
local StatsDefinition = Diary.RegisterTemplate("PlayerStats", {
    coins    = 0,
    level    = 1,
    xp       = 0,
    playtime = 0,
})

-- StatsDefinition is now the handle to pass to FetchData later.
-- Store it at module scope so all scripts can reach it.
```

**Scenario B — Multiple locations with custom cache policies**

```luau
local Diary = require(game.ServerScriptService.Diary)

-- High-value progression data: save frequently, keep in fast storage longer.
local ProgressionDefinition = Diary.RegisterTemplate("Progression", {
    questsCompleted = 0,
    bossesDefeated  = 0,
    highScore       = 0,
}, {
    ____ActiveTTL          = 86400,  -- keep in fast storage for 24 hours
    ____IdleTTL            = 108000, -- 30 hours for idle players
    ____IdleThreshold      = 60,     -- considered idle after 1 minute of inactivity
    ____IntervalMultiplier = 2,      -- idle players saved at 2x the base interval
})

-- Low-stakes cosmetic data: save less urgently.
local AppearanceDefinition = Diary.RegisterTemplate("Appearance", {
    hatColor  = "White",
    shirtId   = 0,
    pantsId   = 0,
}, {
    ____ActiveTTL          = 43200,
    ____IdleTTL            = 54000,
    ____IdleThreshold      = 120,   -- 2 minutes before considered idle
    ____IntervalMultiplier = 5,     -- idle appearance data saved very infrequently
})
```

---

## RegisterPolicy

Replaces the save and TTL behaviour for a location without touching the template.

**Scenario A — Tightening the policy after a live update**

```luau
-- Suppose a major update introduced high-value inventory data.
-- Re-tune the policy to protect it more aggressively.
Diary.RegisterPolicy("PlayerInventory", {
    ____ActiveTTL          = 86400,
    ____IdleTTL            = 108000,
    ____IdleThreshold      = 30,
    ____IntervalMultiplier = 2,
})
-- From this point on, inventory data is saved more frequently
-- and kept in fast storage for longer.
```

**Scenario B — Relaxing constraints for a non-critical location**

```luau
-- Chat preferences are low-stakes. Save them infrequently.
Diary.RegisterPolicy("ChatPreferences", {
    ____IdleThreshold      = 600,   -- 10 minutes before considered idle
    ____IntervalMultiplier = 10,    -- save at 10x the base interval when idle
})
-- Active TTL and idle TTL fall back to module defaults.
```

---

## FetchData

Returns the live in-memory data for a player. Mutations to the returned table take effect immediately.

**Scenario A — Reading a value after load**

```luau
-- In a gameplay system, retrieve a player's stats after load.
Diary.Signals.OnLoadCompleted:Connect(function(player)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    if not stats then
        -- Data didn't load — this player was likely kicked during the process.
        return
    end

    print(player.Name .. " loaded with " .. stats.coins .. " coins.")
end)
```

**Scenario B — Modifying data and marking it for saving**

```luau
-- Award coins after a purchase event.
local function awardCoins(player, amount)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    if not stats then return end  -- guard against data not loaded

    stats.coins += amount         -- directly mutate the live table
    Diary.MarkDirty(player.UserId, "PlayerStats")  -- tell the framework the data changed
    -- The auto-save loop will write this change on the next cycle.
end
```

**Scenario C — Checking data without modifying it**

```luau
-- A leaderboard function that reads coin totals without touching the save system.
local function getCoins(player)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    return stats and stats.coins or 0
end
```

---

## SaveData

Schedules an explicit, prompt write of data to storage. Use when timing matters.

**Scenario A — Force-save after a high-value transaction**

```luau
-- After a player spends premium currency, save immediately rather than waiting.
local function processPurchase(player, itemId)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    if not stats then return false end

    stats.coins -= 500
    -- Include MemoryStore in this save so other servers see the update promptly.
    Diary.SaveData(player.UserId, "PlayerStats", true)

    grantItem(player, itemId)
    return true
end
```

**Scenario B — Saving on a round-end checkpoint**

```luau
-- At the end of a match, save all participating players' progression data.
local function onRoundEnd(winners)
    for _, player in winners do
        local progression = Diary.FetchData(player.UserId, ProgressionDefinition)
        if not progression then continue end

        progression.questsCompleted += 1
        -- Defer to DataStore only (no MemoryStore update needed for checkpoint saves).
        Diary.SaveData(player.UserId, "Progression")
    end
end
```

---

## MarkDirty

Tells the auto-save loop that data has changed, without triggering an immediate write.

**Scenario A — High-frequency stat increments**

```luau
-- Playtime is updated every second. We don't want a DataStore write every second.
-- Mark dirty once per update cycle; the framework batches the actual writes.
game:GetService("RunService").Heartbeat:Connect(function(dt)
    for _, player in game.Players:GetPlayers() do
        local stats = Diary.FetchData(player.UserId, StatsDefinition)
        if stats then
            stats.playtime += dt
            Diary.MarkDirty(player.UserId, "PlayerStats")
            -- Only a single write will occur per auto-save interval,
            -- regardless of how many times this runs per second.
        end
    end
end)
```

**Scenario B — Marking after bulk changes**

```luau
-- After awarding a complex set of quest rewards, mark once after all changes are applied.
local function grantQuestRewards(player, questData)
    local stats = Diary.FetchData(player.UserId, StatsDefinition)
    local progression = Diary.FetchData(player.UserId, ProgressionDefinition)
    if not stats or not progression then return end

    stats.coins     += questData.coinReward
    stats.xp        += questData.xpReward
    progression.questsCompleted += 1

    -- One MarkDirty per location — not one per field.
    Diary.MarkDirty(player.UserId, "PlayerStats")
    Diary.MarkDirty(player.UserId, "Progression")
end
```

---

## HandleMemoryCaching

Pauses or resumes the MemoryStore auto-cache loop for a specific player and location.

**Scenario A — Disabling cache during a bulk migration**

```luau
-- Temporarily disable MemoryStore caching for a player whose data is being migrated.
-- This prevents stale intermediate states from being written to fast storage.
Diary.HandleMemoryCaching(player.UserId, "PlayerStats", true)  -- true = DISABLE caching

runMigration(player)

Diary.HandleMemoryCaching(player.UserId, "PlayerStats", false) -- false = RE-ENABLE caching
```

**Scenario B — Suppressing caching for a low-value location**

```luau
-- Chat preferences don't need MemoryStore caching at all.
-- Disable it entirely once the player loads to reduce MemoryStore write volume.
Diary.Signals.OnLoadCompleted:Connect(function(player)
    Diary.HandleMemoryCaching(player.UserId, "ChatPreferences", true)
end)
```

---

## OnLoadStarted / OnLoadCompleted

Signals that fire as data begins loading and when all data is fully ready.

**Scenario A — Showing a loading screen**

```luau
local loadingPlayers = {}

Diary.Signals.OnLoadStarted:Connect(function(player)
    loadingPlayers[player] = true
    -- Show a loading UI for this player via a RemoteEvent.
    LoadingEvent:FireClient(player, true)
end)

Diary.Signals.OnLoadCompleted:Connect(function(player)
    loadingPlayers[player] = nil
    -- Hide the loading UI and allow the player to spawn.
    LoadingEvent:FireClient(player, false)
    spawnPlayer(player)
end)
```

**Scenario B — Firing once for the first player loaded (admin setup)**

```luau
-- Only needed once: set up an admin panel after the first load completes.
Diary.Signals.OnLoadCompleted:Once(function(player)
    initAdminPanel()
end)
```

**Scenario C — Disconnecting a temporary listener**

```luau
-- A tutorial system that only cares about the very first session.
local connection
connection = Diary.Signals.OnLoadCompleted:Connect(function(player)
    if isTutorialEligible(player) then
        startTutorial(player)
        connection:Disconnect()  -- stop listening after the first eligible player
    end
end)
```

---

## WaitForValue

Polls a condition until it is met or a timeout expires. Handles errors with back-off.

**Scenario A — Waiting for an external system to be ready**

```luau
-- Wait for an external manager module to finish its own initialisation.
local ExternalManager = require(game.ServerScriptService.ExternalManager)

local success, manager = Diary.WaitForValue(function()
    return ExternalManager.isReady() and ExternalManager or nil
end, {
    ____Timeout  = 30,
    ____PollRate = 1,
})

if success then
    print("External manager ready:", manager)
else
    warn("External manager failed to initialise within 30 seconds.")
end
```

**Scenario B — Polling for a player's data to appear**

```luau
-- Wait up to 5 seconds for a specific player's data to become available.
local function waitForPlayerData(player)
    local success, data = Diary.WaitForValue(function()
        return Diary.FetchData(player.UserId, StatsDefinition)
    end, {
        ____Timeout  = 5,
        ____PollRate = 0.2,
    })

    if success then
        return data
    else
        warn(player.Name .. "'s data was not available within 5 seconds.")
        return nil
    end
end
```

---

## PublishQueueEntry / ScanQueueEntry

Enqueue and dequeue payloads via MemoryStore queues.

**Scenario A — Publishing a cross-server trade offer**

```luau
-- A player initiates a trade. Publish the offer to a shared queue.
local function publishTradeOffer(fromUserId, toUserId, items)
    Diary.PublishQueueEntry("PendingTrades", {
        from  = fromUserId,
        to    = toUserId,
        items = items,
    }, {
        ____TimeSpan = 120,  -- offer expires after 2 minutes
        ____Priority = 1,
    })
    -- The entry is enqueued in the background; this returns immediately.
end
```

**Scenario B — Processing pending trades on a server loop**

```luau
-- Periodically drain trade offers and process them.
while true do
    local entries = Diary.ScanQueueEntry("PendingTrades", {
        ____Count    = 10,      -- process up to 10 trades at once
        ____OnDelete = true,    -- remove entries after reading
    })

    for _, offer in entries do
        processTrade(offer.from, offer.to, offer.items)
    end

    task.wait(5)
end
```

---

## WipeData

Permanently deletes all data for a player and bans them. Returns a copy for audit purposes.

**Scenario A — GDPR deletion request for an online player**

```luau
-- A support tool triggers a deletion request for a player currently in-server.
local function handleDeletionRequest(player, reason, requester)
    local package = Diary.WipeData(player, {
        reason    = reason,
        requester = requester,
    })

    -- package.audit contains the timestamped ban record.
    -- package.copy contains a snapshot of all data before deletion.
    logToAuditService(package.audit, package.copy)

    -- The player is kicked automatically. Deletion completes 20 seconds later.
end
```

**Scenario B — Deleting an offline player's data by UserId**

```luau
-- Process a queued deletion for a player who is not in the server.
local function deleteOfflinePlayer(userId)
    local package = Diary.WipeData(userId, {
        reason    = "Account closure via support request",
        requester = "Support Team",
    })

    if next(package.copy) then
        logToAuditService(package.audit, package.copy)
    end
end
```

---

## ExportData

Produces a complete, structured copy of all player data for right-of-access requests.

**Scenario A — Exporting data for an online player**

```luau
local function handleDataRequest(player)
    local package = Diary.ExportData(player.UserId, {
        reason    = "User Right of Access Request",
        requester = "Support Portal",
    })

    -- package.audit contains timestamps, server ID, and reason.
    -- package.copy is a map of memory location names to data tables.
    sendDataToUser(player, package)
end
```

**Scenario B — Exporting data for an offline player (yields)**

```luau
-- Run inside a task.spawn since this may yield to reach offline storage.
task.spawn(function()
    local userId = 123456789
    local package = Diary.ExportData(userId)

    saveExportToExternalService(package)
end)
```

---

## FetchTombstones

Returns a record of all wiped accounts and when they were deleted.

**Scenario A — Checking if a player was previously wiped**

```luau
local function wasPlayerWiped(userId)
    local tombstones = Diary.FetchTombstones()
    return tombstones[tostring(userId)] ~= nil
end
```

**Scenario B — Displaying a wipe history in an admin panel**

```luau
-- Fetch the full graveyard and display it for a server admin.
local tombstones = Diary.FetchTombstones()

for userId, timestamp in tombstones do
    local date = DateTime.fromUnixTimestamp(timestamp):ToIsoDate()
    print(string.format("UserId %s was wiped on %s", userId, date))
end
```

---

## SystemStats

Returns a live health snapshot for monitoring and debugging.

**Scenario A — Logging metrics every 60 seconds**

```luau
task.spawn(function()
    while true do
        task.wait(60)
        local stats = Diary.SystemStats()

        print("=== Diary Health ===")
        print("Players loaded:", stats.Players.____LoadedProfiles)
        print("DataStore queue:", stats.DataStore.____QueueSize)
        print("Active threads:", stats.System.____TotalThreads)
        print("MemoryStore healthy:", stats.System.____MemoryStoreHealthy)
    end
end)
```

**Scenario B — Admin command to check current state**

```luau
-- A simple admin chat command that prints the full stats snapshot.
game.Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(msg)
        if msg == "/diarystats" and isAdmin(player) then
            local stats = Diary.SystemStats()
            for group, fields in stats do
                for key, val in fields do
                    print(string.format("[%s] %s = %s", group, key, tostring(val)))
                end
            end
        end
    end)
end)
```

---

## GetDataSize

Returns the total number of cached keys for a player across all locations.

**Scenario A — Debugging a player's data footprint**

```luau
Diary.Signals.OnLoadCompleted:Connect(function(player)
    local size = Diary.GetDataSize(player.UserId)
    print(player.Name .. " has " .. size .. " total data keys cached.")
end)
```

**Scenario B — Alerting when a player's data exceeds a threshold**

```luau
-- Run a periodic check to catch unexpectedly large data sets.
task.spawn(function()
    while true do
        task.wait(60)
        for _, player in game.Players:GetPlayers() do
            local size = Diary.GetDataSize(player.UserId)
            if size > 500 then
                warn(player.Name .. " has an unusually large data set: " .. size .. " keys.")
            end
        end
    end
end)
```

---

## Inject

Replaces the default task scheduler with the Assignment library.

**Scenario A — Injecting Assignment at server start**

```luau
-- Always inject before any player can join.
local Diary      = require(game.ServerScriptService.Diary)
local Assignment = require(game.ServerScriptService.Assignment)

-- Assignment now powers all of Diary's internal scheduling.
Diary.Inject("Assignment", Assignment)

-- Register templates and set up signals after injection.
local StatsDefinition = Diary.RegisterTemplate("PlayerStats", {
    coins = 0,
    level = 1,
})
```

---

## IsOnline *(FEATURES_ENABLED required)*

Checks whether a player's online flag is set in MemoryStore.

**Scenario A — Conditional cross-server logic**

```luau
-- Before sending a cross-server message, confirm the target is online somewhere.
local function notifyPlayer(targetUserId, message)
    if Diary.IsOnline(targetUserId) then
        sendCrossServerMessage(targetUserId, message)
    else
        -- Queue the message for when they next log in.
        queueOfflineMessage(targetUserId, message)
    end
end
```

---

## SaveHumanoidDescription *(FEATURES_ENABLED required)*

Captures a player's appearance snapshot to fast storage.

**Scenario A — Saving on a periodic timer**

```luau
-- Keep the snapshot fresh so LoadPlayerGhostCharacterModel can use it.
Diary.Signals.OnLoadCompleted:Connect(function(player)
    task.spawn(function()
        while player.Parent do  -- while the player is in the game
            Diary.SaveHumanoidDescription(player)
            task.wait(55)  -- refresh before the 60-second TTL expires
        end
    end)
end)
```

---

## LoadPlayerGhostCharacterModel *(FEATURES_ENABLED required)*

Places a player's saved appearance as a character model in the world.

**Scenario A — Placing a ghost at a player's last position**

```luau
-- After a player leaves, place their ghost at their last known position.
game.Players.PlayerRemoving:Connect(function(player)
    Diary.SaveHumanoidDescription(player)  -- capture final state

    task.delay(1, function()  -- brief delay to let the save propagate
        local ghost = Diary.LoadPlayerGhostCharacterModel(player.UserId)
        if ghost then
            print("Ghost placed for " .. player.Name)
            task.delay(30, function()
                if ghost.Parent then ghost:Destroy() end
            end)
        end
    end)
end)
```

**Scenario B — Placing a ghost at a fixed spawn point**

```luau
-- Place a guest-of-honour ghost at the stage position.
local stagePosition = Vector3.new(0, 10, 50)
local ghost = Diary.LoadPlayerGhostCharacterModel(honoreeUserId, stagePosition)

if not ghost then
    warn("Could not reconstruct ghost — snapshot may have expired.")
end
```
