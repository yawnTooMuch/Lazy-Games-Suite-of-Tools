# API Reference

Complete reference for every public method, signal, and type exported by Diary.

---

## Type Definitions

### `DataTable`

```luau
type DataTable = { [any]: any }
```

A generic table type used throughout Diary wherever an untyped data payload is accepted or returned.

---

### `DataDefinition<Schema>`

```luau
type DataDefinition<Schema> = {
    ____memoryLocation : string,
    structure          : Schema,
}
```

The opaque handle returned by `RegisterTemplate`. Pass this to `FetchData` to retrieve a player's typed data. Do not construct this manually.

---

### `CachePolicy`

```luau
type CachePolicy = {
    ____ActiveTTL          : number?,
    ____IdleTTL            : number?,
    ____IdleThreshold      : number?,
    ____IntervalMultiplier : number?,
}
```

Overrides the framework-wide defaults for a single data location. All fields are optional; omitted fields fall back to the module-level configuration constants.

| Field | Type | Description |
|:---|:---|:---|
| `____ActiveTTL` | `number?` | MemoryStore entry lifetime in seconds for active players. |
| `____IdleTTL` | `number?` | MemoryStore entry lifetime in seconds for idle players. |
| `____IdleThreshold` | `number?` | Seconds of inactivity before the player is considered idle. |
| `____IntervalMultiplier` | `number?` | Factor applied to the base save interval for idle players. |

---

### `QueuePublishConfig`

```luau
type QueuePublishConfig = {
    ____VisibilityTimeout : number?,
    ____TimeSpan          : number?,
    ____Priority          : number?,
}
```

Controls how an entry is placed onto a MemoryStore queue.

| Field | Type | Description |
|:---|:---|:---|
| `____VisibilityTimeout` | `number?` | Seconds the entry is hidden from other readers after being read. Clamped to 30–300. |
| `____TimeSpan` | `number?` | Entry lifetime in seconds. Default: `60`. |
| `____Priority` | `number?` | Relative ordering within the queue. Default: `1`. |

---

### `QueueScanConfig`

```luau
type QueueScanConfig = {
    ____Count        : number?,
    ____AllOrNothing : boolean?,
    ____WaitTimeout  : number?,
    ____OnDelete     : boolean?,
}
```

Controls how entries are read from a MemoryStore queue.

| Field | Type | Description |
|:---|:---|:---|
| `____Count` | `number?` | Maximum entries to read in a single call. Default: `1`. Capped at `100`. |
| `____AllOrNothing` | `boolean?` | When true, the read fails unless the full requested count is available. |
| `____WaitTimeout` | `number?` | Seconds to wait for entries if the queue is empty. Use `-1` for indefinite. Capped at 3600. |
| `____OnDelete` | `boolean?` | When true, entries are removed from the queue immediately after being read. |

---

### `WaitConfig`

```luau
type WaitConfig = {
    ____Timeout  : number?,
    ____PollRate : number?,
}
```

Controls the polling behaviour of `WaitForValue`.

| Field | Type | Description |
|:---|:---|:---|
| `____Timeout` | `number?` | Maximum seconds to wait before returning failure. Default: `10`. |
| `____PollRate` | `number?` | Seconds between poll attempts. Default: `0.2`. Minimum: `0.1`. |

---

### `DataPackage`

```luau
type DataPackage = {
    audit : { [string]: any },
    copy  : { [string]: DataTable },
}
```

Returned by `WipeData` and `ExportData`. Contains a formatted audit record and a snapshot of all data across every registered memory location.

| Field | Type | Description |
|:---|:---|:---|
| `audit` | `{ [string]: any }` | Timestamped record describing the action, requester, reason, and server ID. |
| `copy` | `{ [string]: DataTable }` | Map of memory location names to their data tables at the time of the operation. |

---

### `SystemStats`

```luau
type SystemStats = {
    System      : { ... },
    Players     : { ... },
    DataStore   : { ... },
    MemoryStore : { ... },
    Resources   : { ... },
}
```

A snapshot of live operational metrics. Returned by `SystemStats()`.

---

### `SignalConnection`

```luau
type SignalConnection = {
    Disconnect : (self: SignalConnection) -> (),
    Connected  : boolean,
}
```

Returned by `Signal:Connect(...)`. Call `:Disconnect()` to stop receiving events.

---

### `DiarySignal`

```luau
type DiarySignal = {
    Connect : (self: DiarySignal, callback: (Player) -> ()) -> SignalConnection,
    Once    : (self: DiarySignal, callback: (Player) -> ()) -> (),
}
```

The signal interface used by `Diary.Signals.OnLoadStarted` and `Diary.Signals.OnLoadCompleted`.

---

## API Summary

### Core Data APIs

| Name | Returns | Description |
|:---|:---|:---|
| **[RegisterTemplate](#registertemplate)** | `DataDefinition<Schema>` | Declares a data location and its default schema; returns a handle for use with FetchData. |
| **[RegisterPolicy](#registerpolicy)** | `void` | Replaces or sets the cache policy for a named data location. |
| **[FetchData](#fetchdata)** | `Schema?` | Returns the current in-memory data for a player at a given location. |
| **[SaveData](#savedata)** | `void` | Schedules a save of a player's data for a specific location to storage. |
| **[MarkDirty](#markdirty)** | `void` | Marks a player's data as changed so the auto-save loop will persist it on the next cycle. |
| **[HandleMemoryCaching](#handlememorycaching)** | `void` | Enables or disables the MemoryStore auto-cache loop for a specific player and location. |

### Lifecycle & Events

| Name | Returns | Description |
|:---|:---|:---|
| **[Signals.OnLoadStarted](#onloadstarted)** | `DiarySignal` | Fires for every player whose data has begun loading. |
| **[Signals.OnLoadCompleted](#onloadcompleted)** | `DiarySignal` | Fires for every player once all data templates have finished loading. |
| **[WaitForValue](#waitforvalue)** | `(boolean, ...any)` | Polls a callback until it returns a non-nil value or a timeout expires. |

### Queue APIs

| Name | Returns | Description |
|:---|:---|:---|
| **[PublishQueueEntry](#publishqueueentry)** | `void` | Publishes a data payload to a named MemoryStore queue. |
| **[ScanQueueEntry](#scanqueueentry)** | `DataTable` | Reads entries from a named MemoryStore queue and returns them. |

### Data Lifecycle APIs

| Name | Returns | Description |
|:---|:---|:---|
| **[WipeData](#wipedata)** | `DataPackage` | Permanently deletes all stored data for a player and bans the account. |
| **[ExportData](#exportdata)** | `DataPackage` | Exports a full copy of all stored data for a player with an audit record. |
| **[FetchTombstones](#fetchtombstones)** | `{ [string]: number }` | Returns the record of all previously wiped player IDs and their deletion timestamps. |

### Diagnostics & Utilities

| Name | Returns | Description |
|:---|:---|:---|
| **[SystemStats](#systemstats)** | `SystemStats` | Returns a live snapshot of framework health metrics. |
| **[ThreadCount](#threadcount)** | `number` | Returns the estimated number of active threads currently managed by the framework. |
| **[GetDataSize](#getdatasize)** | `number` | Returns the total number of cached data keys across all locations for a player. |
| **[Inject](#inject)** | `void` | Injects a compatible external scheduler into the framework. |

### Featured APIs

!!! info "Requires FEATURES_ENABLED"
    The following APIs are only available when `FEATURES_ENABLED` is set to `true` in the module configuration. They will not exist on the Diary table otherwise.

| Name | Returns | Description |
|:---|:---|:---|
| **[IsOnline](#isonline)** | `boolean` | Returns whether a player is currently marked as online in MemoryStore. |
| **[SaveHumanoidDescription](#savehumanoiddescription)** | `void` | Captures a player's appearance and last position to MemoryStore. |
| **[LoadPlayerGhostCharacterModel](#loadplayerghostcharactermodel)** | `Model?` | Reconstructs and places a player's saved appearance as a character model in the world. |

---

## Detail Entries

---

### RegisterTemplate

```luau
Diary.RegisterTemplate(memoryLocation: string, template: Schema, policy: CachePolicy?): DataDefinition<Schema>
```

Declares a data location and its default schema; returns a handle for use with FetchData. Call this once per data location at server startup, before any players join. The returned handle is the only way to retrieve a player's data via `FetchData` — store it in a variable.

When called while players are already online, all currently cached data for those players is immediately reconciled against the new template: missing keys are added with their default values and removed keys are cleared.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `memoryLocation` | `string` | A unique name for this data slot. Used as the DataStore and MemoryStore key. |
| `template` | `Schema` | The default data table for a new player. All keys and their default values. |
| `policy` | `CachePolicy?` | Optional TTL and save-interval overrides. Falls back to module-level configuration if omitted. |

**Returns:**

| Type | Description |
|:---|:---|
| `DataDefinition<Schema>` | An opaque handle. Pass this to `FetchData` to access typed player data. |

!!! tip "Store the returned handle"
    Keep the `DataDefinition` in a module-level variable. You need it every time you call `FetchData`. Calling `RegisterTemplate` twice for the same location replaces the template and re-reconciles live data.

!!! warning "Side Effect"
    If players are online when this is called, their cached data is immediately reconciled and marked for saving.

---

### RegisterPolicy

```luau
Diary.RegisterPolicy(memoryLocation: string, policy: CachePolicy): ()
```

Replaces or sets the cache policy for a named data location. Use this to change TTL or idle-save behaviour for a location without re-registering the entire template.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `memoryLocation` | `string` | The name of the data location whose policy to replace. |
| `policy` | `CachePolicy` | The new TTL and interval configuration. All fields are optional; omitted fields use module defaults. |

**Returns:** `void`

!!! danger "Throws"
    In Studio (debug mode), throws if `memoryLocation` is not a non-empty string or if `policy` is not a table.

---

### FetchData

```luau
Diary.FetchData(playerUserID: number, structureDefinition: DataDefinition<Schema>): Schema?
```

Returns the current in-memory data for a player at a given location. Returns `nil` if the player's data has not finished loading yet.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The player's UserId. |
| `structureDefinition` | `DataDefinition<Schema>` | The handle returned by `RegisterTemplate`. |

**Returns:**

| Type | Description |
|:---|:---|
| `Schema?` | A direct reference to the live data table. Mutations to this table are reflected immediately. Returns `nil` if the data is not yet loaded. |

!!! warning "Yields"
    Internally polls with a short timeout until the data is available. For most in-session use, this returns immediately. Check for `nil` to detect the not-yet-loaded case.

!!! tip "Mutate directly"
    The returned table is the live data copy. You can read and write fields on it directly. Call `MarkDirty` afterwards to tell the auto-save loop to persist the change.

---

### SaveData

```luau
Diary.SaveData(playerUserID: number, memoryLocation: string, updateMemoryStore: boolean?): ()
```

Schedules a save of a player's data for a specific location to storage. Use this when you want to guarantee a write at a specific point in your game logic (e.g., after a purchase), rather than waiting for the next auto-save cycle.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The player's UserId. |
| `memoryLocation` | `string` | The data location name to save. |
| `updateMemoryStore` | `boolean?` | When true, also writes the data to MemoryStore in addition to DataStore. Default: `false`. |

**Returns:** `void`

!!! info "Deferred execution"
    The actual write is scheduled for the next available opportunity. This call never blocks. If the write system is busy, the write is placed in the background queue automatically.

!!! tip "Pairing with MarkDirty"
    `SaveData` always writes regardless of the dirty flag. Use `MarkDirty` alone when you are happy for the auto-save loop to decide when to write. Use `SaveData` when you need the write to happen promptly.

---

### MarkDirty

```luau
Diary.MarkDirty(playerUserID: number, memoryLocation: string): ()
```

Marks a player's data as changed so the auto-save loop will persist it on the next cycle.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The player's UserId. |
| `memoryLocation` | `string` | The data location to mark. |

**Returns:** `void`

!!! tip "Preferred pattern for frequent updates"
    For high-frequency changes (inventory updates, stat increments), prefer `MarkDirty` over `SaveData`. The auto-save loop batches all dirty locations together efficiently and respects the configured save interval.

---

### HandleMemoryCaching

```luau
Diary.HandleMemoryCaching(playerUserID: number, memoryLocation: string, state: boolean): ()
```

Enables or disables the MemoryStore auto-cache loop for a specific player and location. When disabled, data for that location is no longer pushed to MemoryStore automatically between saves. Re-enable with `state = false`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The player's UserId. |
| `memoryLocation` | `string` | The data location to toggle. |
| `state` | `boolean` | Pass `true` to **disable** caching; `false` to **re-enable** it. |

**Returns:** `void`

!!! warning "Inverted polarity"
    The `state` parameter is intentionally inverted: `true` means "stop caching", `false` means "resume caching". This is by design to match an internal enabled/disabled semantic. Read carefully.

---

### OnLoadStarted

```luau
Diary.Signals.OnLoadStarted:Connect(callback: (Player) -> ()): SignalConnection
Diary.Signals.OnLoadStarted:Once(callback: (Player) -> ()): ()
```

Fires for every player whose data has begun loading. Fires retroactively for any players who are already loaded when a listener is connected.

**Parameters (`Connect`):**

| Name | Type | Description |
|:---|:---|:---|
| `callback` | `(Player) -> ()` | Called with the Player instance whose load just began. |

**Returns (`Connect`):**

| Type | Description |
|:---|:---|
| `SignalConnection` | Call `:Disconnect()` to stop receiving events. |

**Returns (`Once`):** `void`

---

### OnLoadCompleted

```luau
Diary.Signals.OnLoadCompleted:Connect(callback: (Player) -> ()): SignalConnection
Diary.Signals.OnLoadCompleted:Once(callback: (Player) -> ()): ()
```

Fires for every player once all data templates have finished loading. Fires retroactively for already-loaded players when a listener is connected.

**Parameters (`Connect`):**

| Name | Type | Description |
|:---|:---|:---|
| `callback` | `(Player) -> ()` | Called with the Player instance whose data is fully ready. |

**Returns (`Connect`):**

| Type | Description |
|:---|:---|
| `SignalConnection` | Call `:Disconnect()` to stop receiving events. |

**Returns (`Once`):** `void`

!!! tip "The right spawn gate"
    Always gate character spawning and gameplay initialisation behind `OnLoadCompleted`, not `PlayerAdded`. Data is not guaranteed to be available at the time `PlayerAdded` fires.

---

### WaitForValue

```luau
Diary.WaitForValue(callbackFunction: () -> ...any, options: WaitConfig?): (boolean, ...any)
```

Polls a callback until it returns a non-nil value or a timeout expires.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `callbackFunction` | `() -> ...any` | Called repeatedly until it returns a non-nil first value. |
| `options` | `WaitConfig?` | Optional timeout and poll interval overrides. |

**Returns:**

| Type | Description |
|:---|:---|
| `boolean` | `true` if the callback returned a value before the timeout; `false` on timeout or persistent error. |
| `...any` | All return values from the final successful callback call, or an error string on failure. |

!!! warning "Yields"
    This function yields the calling thread for up to `____Timeout` seconds. Do not call it from a path that must not yield (e.g., inside a tight update loop).

---

### PublishQueueEntry

```luau
Diary.PublishQueueEntry(queueName: string, dataReference: DataTable, options: QueuePublishConfig?): ()
```

Publishes a data payload to a named MemoryStore queue.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `queueName` | `string` | The name of the target queue. |
| `dataReference` | `DataTable` | The data table to publish. Must be DataStore-serialisable. |
| `options` | `QueuePublishConfig?` | Optional visibility timeout, TTL, and priority. |

**Returns:** `void`

!!! warning "Deferred write"
    The publish is scheduled, not immediate. Do not assume the entry is visible to readers the moment this call returns.

---

### ScanQueueEntry

```luau
Diary.ScanQueueEntry(queueName: string, options: QueueScanConfig?): DataTable
```

Reads entries from a named MemoryStore queue and returns them. If `____OnDelete` is set in options, entries are removed from the queue after reading.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `queueName` | `string` | The name of the queue to read from. |
| `options` | `QueueScanConfig?` | Optional count, all-or-nothing, timeout, and delete-on-read configuration. |

**Returns:**

| Type | Description |
|:---|:---|
| `DataTable` | The deserialized entries read from the queue. Returns an empty table if none were available or the read failed. |

!!! warning "Yields"
    This function yields the calling thread until the read completes. If `____WaitTimeout` is set, it may yield for that many seconds waiting for entries to appear.

---

### WipeData

```luau
Diary.WipeData(playerInstance: Player | number, informationTable: DataTable?, isRecursed: boolean?): DataPackage
```

Permanently deletes all stored data for a player, records a tombstone, and bans the account from re-entering. Returns a full copy of all data as it existed before deletion, along with a timestamped audit record.

If the player is currently online, they are kicked and the deletion is scheduled after a short delay to allow the kick to propagate. If offline, deletion proceeds immediately.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerInstance` | `Player | number` | The Player instance or their numeric UserId. |
| `informationTable` | `DataTable?` | Optional extra fields to merge into the ban record (e.g., `reason`, `requester`). |
| `isRecursed` | `boolean?` | Internal use only. Do not pass this argument manually. |

**Returns:**

| Type | Description |
|:---|:---|
| `DataPackage` | Contains the ban audit record and a copy of all data before deletion. |

!!! danger "Irreversible"
    This operation is permanent. Data is deleted from both DataStore and MemoryStore. The tombstone prevents future data loads for this UserId. There is no undo.

!!! warning "Online player delay"
    When the target player is currently in the server, the actual storage deletion is deferred by 20 seconds to allow the kick to complete. The returned `DataPackage` reflects the data at the time of the call, not after the deferred deletion.

---

### ExportData

```luau
Diary.ExportData(playerUserID: number, requestInfo: AuditInfo?): DataPackage
```

Exports a full copy of all stored data for a player with an audit record. For online players, data is read from the live in-memory cache. For offline players, data is fetched from MemoryStore, falling back to DataStore.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The player's UserId. |
| `requestInfo` | `{ reason: string?, requester: string? }?` | Optional audit metadata. |

**Returns:**

| Type | Description |
|:---|:---|
| `DataPackage` | Audit record plus a copy of all data across all registered memory locations. |

!!! warning "Yields for offline players"
    Fetching data for offline players requires live storage reads, which yield the calling thread.

---

### FetchTombstones

```luau
Diary.FetchTombstones(): { [string]: number }
```

Returns the record of all previously wiped player IDs and their deletion timestamps.

**Parameters:** `void`

**Returns:**

| Type | Description |
|:---|:---|
| `{ [string]: number }` | Map of UserId strings to Unix timestamps of when the wipe occurred. |

!!! warning "Yields"
    May yield when reading from DataStore if the MemoryStore cache has expired.

---

### SystemStats

```luau
Diary.SystemStats(): SystemStats
```

Returns a live snapshot of framework health metrics.

**Parameters:** `void`

**Returns:**

| Type | Description |
|:---|:---|
| `SystemStats` | A table with five sub-groups: `System`, `Players`, `DataStore`, `MemoryStore`, and `Resources`. See type definition for field details. |

The returned table contains:

- **System**: Server ID, shutdown flag, Studio flag, MemoryStore health flag, total thread count.
- **Players**: Number of loaded profiles, active auto-save sessions, players missing a lease.
- **DataStore**: Current queue depth and active write operations.
- **MemoryStore**: Pending batch writes and owned lease count.
- **Resources**: Serialisation cache size and active key lock count.

---

### ThreadCount

```luau
Diary.ThreadCount(): number
```

Returns the estimated number of active threads currently managed by the framework. Includes base workers, the DataStore queue processor, and any in-flight per-player save threads.

**Parameters:** `void`

**Returns:**

| Type | Description |
|:---|:---|
| `number` | Estimated active thread count. |

---

### GetDataSize

```luau
Diary.GetDataSize(playerUserID: number): number
```

Returns the total number of cached data keys across all locations for a player.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The player's UserId. |

**Returns:**

| Type | Description |
|:---|:---|
| `number` | Total key count across all memory locations. Returns `0` if no data is cached for this player. |

---

### Inject

```luau
Diary.Inject(moduleName: string, moduleTableObject: any): ()
```

Injects an external library within the Lazy Games Suite of Tools environment.
Currently supports the "Assignment" library.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `moduleName` | `string` | The name of the ModuleScript file. |
| `moduleTableObject` | `any` | The module table to inject. |

**Returns:** `void`

!!! tip "Inject before players join"
    Call `Inject` at the very beginning of your server script, before any player can arrive. Injecting after the server is running may cause some operations to execute under the default scheduler.

---

### IsOnline

```luau
Diary.IsOnline(playerUserID: number): boolean
```

Returns whether a player is currently marked as online in MemoryStore.

!!! info "Requires FEATURES_ENABLED"
    This method only exists when `FEATURES_ENABLED = true`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The player's UserId to check. |

**Returns:**

| Type | Description |
|:---|:---|
| `boolean` | `true` if the player's online flag is set in MemoryStore; `false` otherwise. |

!!! warning "Eventual consistency"
    The online flag is managed via MemoryStore and may not reflect the exact moment of join or departure. Do not use it as a strict presence check for gameplay-critical logic.

---

### SaveHumanoidDescription

```luau
Diary.SaveHumanoidDescription(player: Player): ()
```

Captures a player's current appearance (accessories, body parts, clothes, body colours, scales) and last known position to MemoryStore with a 60-second TTL. This snapshot can later be used by `LoadPlayerGhostCharacterModel`.

!!! info "Requires FEATURES_ENABLED"
    This method only exists when `FEATURES_ENABLED = true`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `player` | `Player` | The Player whose appearance to capture. |

**Returns:** `void`

!!! warning "Yields"
    Waits for the player's character and humanoid to be present before reading the description. Do not call during PlayerRemoving unless the character is guaranteed to still exist.

!!! tip "TTL is short"
    The snapshot expires after 60 seconds. Call this close to when you intend to use `LoadPlayerGhostCharacterModel`, or call it on a timer to keep it fresh.

---

### LoadPlayerGhostCharacterModel

```luau
Diary.LoadPlayerGhostCharacterModel(playerUserID: number, spawnPosition: Vector3?): Model?
```

Reconstructs and places a player's saved appearance as a non-playable character model in the world, using the snapshot written by `SaveHumanoidDescription`.

!!! info "Requires FEATURES_ENABLED"
    This method only exists when `FEATURES_ENABLED = true`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `playerUserID` | `number` | The UserId of the player whose appearance to reconstruct. |
| `spawnPosition` | `Vector3?` | Where to place the model. Falls back to the last known position from the snapshot if omitted. |

**Returns:**

| Type | Description |
|:---|:---|
| `Model?` | The placed character model, or `nil` if the snapshot could not be found or the humanoid was missing. |

!!! warning "Yields"
    Fetches the snapshot from MemoryStore and applies the HumanoidDescription, both of which yield.

!!! danger "Strict Dependency: FEATURES_ENABLED + Mesh Template"
    Requires a `"Mesh Template"` model in `ServerStorage`, generated automatically at startup when `FEATURES_ENABLED = true`. If the template is not present, this will error.
