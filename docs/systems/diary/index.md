# Diary

**Type:** Framework  
_A server-side data persistence framework for Roblox that handles player data loading, caching, automatic saving, and safe cleanup across the full session lifecycle._

---

## Overview

Diary is a complete data management layer for Roblox game servers. It replaces the need to manually wire together DataStore calls, MemoryStore caches, session handoff logic, and shutdown handlers — consolidating all of that responsibility into a single framework that operates from the moment a player's connection is detected until long after they have left.

The framework is built around a straightforward contract: register a template that defines what a player's data looks like, and Diary handles everything from there. It loads data when players join (resolving any conflicts left by a previous server), caches it in fast MemoryStore storage throughout the session, periodically persists changes to DataStore in the background, and performs a final flush on player departure and server shutdown. Your game code interacts only with a clean in-memory copy of the data, never directly with storage APIs.

Diary is designed for use on the server exclusively and integrates with the optional Assignment scheduling library from the Lazy Games Suite of Tools. It ships with Studio-mode awareness — data is kept entirely in memory during Studio testing so that live player records are never touched.

!!! tip "Bypass Studio Mode"
    When your'e in studio but still want to work with real API usage, just add `Diary._inStudio = false` somewhere in your codebase. This is safe to be called elsewhere but recommended to put it after where Diary is required.

---

## External Dependencies

- **DataStore (sub-module)** — Handles all DataStore read and write operations, including a write queue, debounce protection, and retry logic with exponential back-off.
- **MemoryStore (sub-module)** — Handles MemoryStore HashMap, SortedMap, and Queue interactions, plus the session lease subsystem that prevents two servers writing the same player's data simultaneously.
- **DependentServices (sub-module)** — Provides access to Roblox platform services, deep serialization and deserialization of Roblox-native types (Vector3, CFrame, Color3, etc.), and a cross-server messaging wrapper.
- **Assignment (optional injection)** — A custom task scheduler from the Lazy Games Suite that replaces the default `task.*` primitives with smarter concurrency management. Inject via `Diary.Inject("Assignment", module)`.

---

## Key Features

### Session Lease Protection

Think of a session lease as a hotel room key. When a player joins a server, that server immediately requests the key for their data. As long as the server holds the key, it has exclusive permission to overwrite the player's DataStore record directly. A server that does not hold the key — because the player's previous session is still being finalised elsewhere — writes only the *delta* of what changed rather than overwriting the whole record, so no data is lost during a server handoff.

Leases are renewed in the background on a regular interval and automatically released when the player leaves. If renewal fails, the framework marks the player and quietly attempts to reacquire the lease rather than stopping the session.

### Cross-Server Data Validation

When a player joins and their data shows signs of being actively owned by another server (a flag embedded in the stored record), Diary initiates a real-time handshake with that other server over MessagingService. The joining server waits for a reply: if the other server confirms the player is still connected there, the join is rejected cleanly; if the other server confirms the player has left, the join proceeds. This eliminates the window of vulnerability that occurs when a server shuts down just as the same player reconnects elsewhere.

When MessagingService is unavailable (Studio, private servers, or outages), the framework falls back to a timestamp-based heuristic — if the record has not been touched for over an hour and no lease is held, the data is considered safe to load.

### Idle-Aware Auto-Save

Rather than hammering storage at a fixed rate regardless of activity, Diary tracks the last time each player meaningfully interacted. Players who have been idle for a configurable period have their MemoryStore entries refreshed less frequently and kept alive for longer, reducing unnecessary API consumption. Active players are written to MemoryStore at the standard interval. Both thresholds are configurable per data location via cache policies.

Auto-saving only triggers when data has been explicitly marked as changed. Unmarked data is never written unnecessarily.

!!! info "DataStore writes are event-driven, not interval-driven"
    The background auto-save cycle exclusively targets **MemoryStore** — it keeps the fast cache layer current so any server that needs a player's data next can load it immediately without touching DataStore. DataStore is written only in response to discrete events: a player leaving the server, the server shutting down, or an explicit `Diary.SaveData` call from your code. This separation is intentional. MemoryStore is the live, low-latency cache; DataStore is the durable record of last resort, and it is written only when a meaningful boundary in the session lifecycle is crossed — such as a trade completing, a purchase being confirmed, or a session ending. If you need a DataStore write to happen at a specific moment in your game's logic (for example, after a Robux transaction), call `Diary.SaveData` explicitly at that point rather than relying on the auto-save cycle.

### Hybrid Write Strategy

Every write goes through a two-stage decision. The framework first attempts a direct, immediate DataStore write. If the current save rate is too high, if a write for that player is still in-flight, or if a previous write was too recent, it routes the work to a background write queue instead. The queue drains in small batches on a controlled schedule, ensuring the server never exhausts its DataStore budget even during heavy join/leave traffic.

At server shutdown, the queue is flushed synchronously within the allowed close window, and all pending writes are forced through before the server exits.

### Boot Sequence Buffering

Diary needs a brief window at startup to initialise its cross-server messaging subscriptions and background workers. Players who join during this window are buffered internally and processed in order once the server is ready, rather than being kicked or having their load silently skipped. Players who disconnect during the boot window are removed from the buffer cleanly.

### Template-Based Schema Reconciliation

Each data location in your game is defined by a template — a default table that describes what a fresh player's data looks like. When a returning player's stored data is loaded, it is automatically reconciled against the current template: new keys added since the player last played are inserted with their default values, and keys that no longer exist in the template are removed. This makes iterating on your data schema safe without requiring migration scripts.

If a template is registered or updated while players are already online, all cached data for those players is reconciled immediately and marked for saving.

### Delta Roblox-Type Serialization

DataStore only accepts JSON-compatible data. Diary transparently converts Roblox-native types — Vector3, CFrame, Color3, UDim2, Font, EnumItem, TweenInfo, and over a dozen more — into a portable format on the way out, and reconstructs them faithfully on the way back in. This happens automatically; your game code always sees real Roblox types.

What makes this more than a simple conversion pass is the delta layer underneath it. The framework maintains a private copy of every player's data exactly as it appeared at the last serialization point. Before any subsequent save, it compares the current state field-by-field against that copy. Only fields that have actually changed since the last write are serialized and included in the outgoing payload — everything else is reused from the previously computed result. A player whose inventory changed but whose stats did not will produce a serialization output that touches only the inventory fields. This means serialization cost is proportional to the rate of change in the data, not to the total size of the data.

### GDPR-Ready Data Lifecycle

Two APIs cover the full data lifecycle demanded by platform and legal requirements. `WipeData` permanently deletes all storage entries for a player, records a timestamped tombstone, bans the account from re-entering, and returns a full copy of the deleted data for audit purposes. `ExportData` produces a complete structured copy of all data across all memory locations, with a formatted audit record. Both work for online and offline players.

### Studio Safety Mode

When running inside Roblox Studio, Diary redirects all storage operations to an in-memory table instead of making real DataStore or MemoryStore API calls. Player data loads, saves, and reconciliation all behave identically to production — only the persistence target changes. A warning is printed at startup to make the distinction clear.

### Auto Player Join and Player Leave Handler

Diary wires up every step of the player data lifecycle automatically — you never write a single line of join or leave plumbing. When a player connects, the framework acquires their session lease, validates their record against any previously owning server, fetches their stored data, reconciles it against your templates, and places a clean copy into memory. When that player leaves, the framework saves every data location, releases the session lease, and clears all internal state for that player in the correct order. At server shutdown, the same process runs in parallel across all remaining players, respecting concurrency limits and flushing the write queue before the process exits.

Your only responsibility is to tell the framework what the data looks like. Everything between "player joined" and "player's data is safely on disk" is handled without any code on your part.

### Delta Updates From External Sources

Not all writes to a player's data originate from the server they are currently on. Robux purchases processed through a web backend, gifts sent from another server, or administrative adjustments made via external tooling all need a path into the player's live record without overwriting what the current server has already changed. Diary handles this through delta merging: any write that arrives from a source that does not hold the player's session lease is applied as an arithmetic delta rather than a full replacement. Numeric fields are incremented by the difference between the incoming value and a known baseline, and structural changes are merged field-by-field. The result is that the current server's in-progress changes and the external update coexist cleanly in the final stored record, with neither source overwriting the other.

### Multiple Fail-Safe Mechanisms

Diary does not rely on a single path to persist data safely. Instead it operates in layered phases, each serving as a fallback for the one before it. During a session, data is held in fast MemoryStore storage so that a reconnecting server can always load the most recent copy without touching DataStore. If a direct DataStore write fails, the write is retried with exponential back-off before being routed to a background queue. If the queue entry itself cannot be written before the retry limit, it is held for one final forced attempt at server shutdown. Session leases are renewed on a background loop, and if renewal fails the framework quietly attempts reacquisition rather than abandoning the session. At shutdown, a deadline-aware flush loop continues processing until either the queue is empty or the engine's allowed close window is fully consumed. At no point is a failure silently discarded while a retry path remains available.

### Fixed Queue Implementation

The background write queue is not unbounded. Its effective depth is kept proportional to the number of players currently tracked by the framework — specifically, the queue will not grow beyond a threshold tied to the active player count. This means that as players leave and their data is resolved, their queue slots are retired and the overall queue shrinks accordingly. A single player's writes can never accumulate indefinitely and crowd out writes for other players. The queue is a controlled, bounded resource that scales with the server's actual workload rather than growing freely under adverse conditions.

### Less Quota Usage

In its default configuration, Diary operates at approximately 38–40% of both the DataStore and MemoryStore quota available to a Roblox server. This is a deliberate design target. The idle-aware save intervals, delta-only serialization, batch write scheduling, and fixed queue depth all contribute to keeping consumption well below the platform ceiling. The remaining 60% of quota is available for your game's own DataStore and MemoryStore usage — leaderboards, global event counters, auction systems, or anything else your game requires — without competing with Diary's operations.

### Heavy Data Compression

When non-primitive values are stored through Diary — such as Vector3 positions, CFrame orientations, Color3 values, or UDim2 layout descriptors — those values are not stored as verbose JSON objects. Instead, each value is packed into a binary buffer and encoded as a compact Base64 string before being written to storage. A Vector3, which would otherwise require three separate floating-point fields in a JSON structure, is packed into 12 bytes and represented as a 16-character string. A full CFrame — position plus rotation matrix — is packed into 48 bytes.

!!! info "How Diary compresses Roblox types"
    Each supported Roblox type maps to a fixed-size binary buffer. The individual components of the value (X, Y, Z for a Vector3; the twelve matrix floats for a CFrame; R, G, B for a Color3, and so on) are written into the buffer as raw 32-bit floats or 16-bit integers using direct memory writes, with no separators or field names. That buffer is then Base64-encoded into a plain ASCII string. On read, the string is decoded back to the buffer and the components are read from their fixed byte offsets. The result is a stored representation that is significantly smaller than an equivalent JSON object, has no parsing ambiguity, and round-trips losslessly within 32-bit float precision.

### Non-Blocking Operation

Diary is designed to stay out of your game's execution path. The overwhelming majority of its work — lease renewal, auto-save cycles, batch queue draining, cross-server validation, and housekeeping sweeps — runs entirely on background threads. Your scripts are never made to wait for these operations. Calling `MarkDirty` or `SaveData` from your game logic schedules work and returns immediately; the actual storage I/O happens asynchronously.

!!! warning "APIs that yield the calling thread"
    A small number of APIs do suspend the caller while they wait for a result. These are:

    - **`FetchData`** — polls briefly until data is confirmed available. In practice returns immediately during an active session, but yields until confirmed.
    - **`WaitForValue`** — by design; polls a condition on a configurable interval until it resolves or times out.
    - **`ScanQueueEntry`** — waits for the MemoryStore queue read to complete, and optionally waits for entries to appear if `____WaitTimeout` is set.
    - **`ExportData`** — yields when fetching data for an offline player, as it must perform live storage reads.
    - **`FetchTombstones`** — may yield when the MemoryStore cache has expired and a DataStore fallback read is required.
    - **`LoadPlayerGhostCharacterModel`** *(FEATURES_ENABLED only)* — yields while fetching the appearance snapshot and applying the HumanoidDescription.
    - **`SaveHumanoidDescription`** *(FEATURES_ENABLED only)* — yields waiting for the character and humanoid to be present.

    All other public APIs return immediately without suspending the thread.

### Redis-Like Architecture

Diary treats fast MemoryStore storage as a local cache layer in front of the persistent DataStore backend — the same principle used by Redis in traditional server architectures. The first time a player's data is needed, the framework checks MemoryStore before falling back to DataStore. Once loaded, the data lives in both the in-process memory table and the MemoryStore cache simultaneously. Every subsequent read within that session is served entirely from in-process memory — no network call, no storage API, no latency. Every write refreshes the MemoryStore entry so that any other server that needs the data next (such as after a server transfer) can load the most recent version from the cache rather than from the slower persistent store. DataStore is the source of long-term truth; MemoryStore is the fast, always-current layer that everything else reads from first.

### Folder-Like Structure

Think of Diary's storage layout as a nested folder hierarchy. Diary itself is the root folder. Each memory location you register — `"PlayerStats"`, `"PlayerInventory"`, `"PlayerSettings"` — is a sub-folder inside that root. Within each sub-folder, every player's data is filed under their UserId as a distinct section. The result is a clean, navigable structure where every piece of data has an unambiguous address: *root → location → player*.

```
Diary/
├── PlayerStats/
│   ├── 12345678   ← player A's stats
│   ├── 87654321   ← player B's stats
│   └── ...
├── PlayerInventory/
│   ├── 12345678   ← player A's inventory
│   └── ...
└── PlayerSettings/
    ├── 12345678   ← player A's settings
    └── ...
```

When you call any API that takes a `memoryLocation` string, you are pointing Diary at the correct sub-folder. When you also supply a UserId, you are pointing it at the exact section within that sub-folder. This makes it immediately clear which slice of the database you are reading from, writing to, or saving — no ambiguity about where the data lives or which player it belongs to.

---

## Configuration Reference

The following constants at the top of the main module control framework-wide behaviour. No API call is needed to change them — edit the values directly before deployment.

| Constant | Default | Effect |
|:---|:---|:---|
| `DEBUG_MODE` | `IsStudio()` | Enables verbose logging when true. Defaults to true in Studio. |
| `FEATURES_ENABLED` | `false` | Enables the optional ghost-character and online-status APIs. |
| `BASE_CACHE_INTERVAL` | `15` | Seconds between auto-save cycles for active players. |
| `ACTIVE_TTL` | `43200` | MemoryStore entry lifetime (seconds) for active players (12 hours). |
| `IDLE_TTL` | `54000` | MemoryStore entry lifetime (seconds) for idle players (15 hours). |
| `IDLE_THRESHOLD` | `30` | Seconds of inactivity before a player is considered idle. |
| `IDLE_INTERVAL_MULTIPLIER` | `3` | Factor applied to the base save interval for idle players. |
| `LEASE_TTL` | `90` | Session lease lifetime in seconds before it must be renewed. |
| `LEASE_RENEW_INTERVAL` | `60` | Seconds between background lease renewal attempts. |
| `MAX_CONCURRENT_SAVES` | `50` | Maximum parallel save threads during server shutdown. |
| `JANITOR_INTERVAL` | `30` | Seconds between background housekeeping sweeps. |
| `NORMAL_JOIN_OPERATION` | `1` | Seconds before the join validation batch is dispatched. |
| `BULK_JOIN_OPERATION` | `4` | Extra seconds added to the batch window during a join surge. |
| `BULK_JOIN_THRESHOLD` | `10` | Concurrent joining players required to trigger the surge extension. |
