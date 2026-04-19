# Reaper

**Type:** Framework (Singleton)  
_A deterministic, self-driving garbage collection and state management engine that autonomously monitors, tears down, and evicts tracked Roblox objects through a hierarchical ownership registry._

---

## Overview

Reaper is the foundational memory controller for the Lazy Games Suite. It solves a core problem in Luau game development: standard cleanup requires developers to manually track every connection, thread, and instance and manually invoke teardown logic at the right time. Missing a single cleanup step produces memory leaks, ghost connection states, and background CPU drain that compound silently until they degrade server performance.

Reaper replaces all manual teardown by accepting any `Reapable` item — an `Instance`, `RBXScriptConnection`, `thread`, `function`, or `table` — into a central memory registry. From that point forward, Reaper determines the correct teardown strategy based on the item's data type, monitors for natural end-of-life states, and executes teardown cascades automatically. The developer interacts only at the boundary: submit an item, optionally configure its identity and polling frequency, and forget it.

Reaper is used across both server-side and client-side scripts wherever game state requires lifecycle management — character systems, combat logic, UI controllers, and any system that creates temporary connections or threads. It integrates optionally with two modules from the Lazy Games Suite: **Assignment** (advanced thread scheduling inside Scopes) and **Relay** (high-performance lifecycle signals). Both are injected at runtime via `Reaper.Inject()` and Reaper operates as a standalone module without either.

---

## External Dependencies

| Name | Role | Injection |
| :--- | :--- | :--- |
| **Assignment** | Provides advanced thread scheduling methods (`Spawn`, `Defer`, `Delay`, `Wait`, `Cancel`, `Repeat`) used internally by `ScopeObject` helper methods. Without injection, Reaper falls back to native `task.*` equivalents for all methods except `Repeat`, which is unavailable. | `Reaper.Inject("Assignment", AssignmentModule)` |
| **Relay** | Powers the three global lifecycle signals (`OnTracked`, `OnCleaned`, `OnRemoved`). Without injection, these signals exist as no-op stubs that emit a Studio warning when connected to. | `Reaper.Inject("Relay", RelayModule)` |

---

## Key Features

### Exclusive Ownership via Last Call Supremacy

Every item tracked by Reaper can only have one owner at a time. Ownership is recorded in two central registries: one mapping each item to its own tracking handle, and one mapping chained children to the parent that owns them. When an item is submitted to a new Scope or Track via `:Chain()` or `:HandleScope()`, Reaper automatically releases it from its previous owner in constant time before registering the new relationship. Double-teardowns are structurally impossible without any developer coordination.

### Autonomous Dead-State Detection

Reaper runs a background listener on every heartbeat that continuously evaluates tracked items against their natural end-of-life conditions: an Instance is considered dead when it leaves the game world; a connection is considered dead when it is no longer active; a thread is considered dead when it has finished executing. When any of these conditions is met, Reaper executes the appropriate teardown action and removes the item from the registry — no developer intervention required.

### Smart Routing and the CPU Trap

When `Reaper.Track()` is called, the item's type determines which monitoring tier it enters:

- **Frequency-polled tier** — Connections and Threads that have been configured with a non-zero check frequency via `:Configure()`. Reaper evaluates each item against its frequency interval on a recurring frame cycle. This tier is the only one where the `Frequency` argument to `:Configure()` has any effect.
- **Background batch tier** — Connections and Threads that have not yet been configured. Evaluated in a rolling batch sweep every thirty seconds, spread across frames so no single frame is overwhelmed.
- **Event-driven tier** — Instances and Suite-integrated objects. Instances are monitored via an `AncestryChanged` hook; certain objects from the Lazy Games Suite that expose a dedicated abandonment signal are similarly hooked at registration time. Both are detected in zero background CPU time — the check fires only when the underlying engine event occurs.
- **Manual tier** — Tables, Functions, Scopes, unrecognised types, and any Connection or Thread configured with `Frequency = 0`. Because these have no concept of a "dead" state that Reaper can poll for, placing them in a polling loop would waste CPU asking a question that can never return `true`. They are registered at zero cost and cleaned only through teardown cascades or explicit `Reaper.Clean()` calls. A Studio warning is emitted when abstract types are tracked without a lifecycle anchor.

### Traceable Memory Hierarchy via Tracks and Scopes

Reaper enforces a two-tier ownership model. `TrackObject`s represent physical, tangible game entities — Players, Cars, Weapons — and act as root anchors in the memory tree. `ScopeObject`s represent temporary logic states — Combat, Trading, Stunned — and must always be parented under a Track or another Scope.

This hierarchy is enforced structurally. The binding methods validate their arguments and reject incorrect combinations: Scopes cannot own Tracks, and Tracks cannot adopt other Tracks as subordinate children. When a parent Track is cleaned, all chained children and all bound Scopes are torn down in a single cascade pass.

### Constant-Time Memory Removal

All internal registries are paired with index tables, so that removing any tracked item is always a constant-time operation regardless of how large the registry has grown. When an item is removed, it is swapped with the last entry in its list, the displaced entry's record is updated, and the final slot is cleared. This avoids the linear-cost shift that Luau's native `table.remove` would otherwise require and guarantees predictable performance at any scale.

### Time-Sliced Batch Processing

The background sweep over Connections and Threads processes at most 500 items per heartbeat frame. If a sweep cannot finish in a single frame, Reaper picks up exactly where it left off on the next heartbeat, spreading the cost across as many frames as needed. Even registries containing tens of thousands of items never cause a single-frame spike, and server frame rates remain consistent throughout.

### Protected States

Passing `IsProtected = true` to `Reaper.Track()` changes what happens when the item's natural end-of-life is detected. Instead of calling the item's teardown action, Reaper releases it from the registry intact. External Object Poolers can use this to safely reclaim instances from Reaper's tracking without the risk of Reaper interfering with the pool's ownership or destroying the object it needs to reuse.

### Custom Teardown Methods

Both `Reaper.Track()` and `:Chain()` accept an optional method name string. When teardown is triggered for that item, Reaper calls the named method on it instead of the default action for its type (`Destroy` for Instances, `Disconnect` for connections, `task.cancel` for threads). For table-typed objects, Reaper applies a smart three-step teardown cascade — attempting `:Destroy()`, then `:Disconnect()`, then cancellation as a scheduler handle — before falling back to a named method if one is provided. If the named method is not found on the object, a Studio warning is emitted noting potential memory leakage, and teardown is skipped for that item.

### Global Cross-Script Teardown and Fetching

Named Scopes and configured Tracks are indexed by their string identifier so that any script can locate them in constant time without sharing an object reference. `Reaper.Clean("SomeID")` and `Reaper.Get("SomeID")` resolve the string to the live handle and act on it immediately. The string ID is the only coupling required between two scripts — no module references, no shared tables, no event-based handshaking.

### Strict API Validation

In Roblox Studio, all public functions validate every argument and throw descriptive errors with full tracebacks when misused. Anti-patterns — chaining a wrapper object instead of the raw item, configuring an already-configured handle, registering a duplicate identifier — are caught at authoring time rather than discovered at runtime on a live server. In production, all validation is compiled away and these checks produce zero overhead.

### Global Lifecycle Signals

After Relay is injected, `Reaper.Signals.OnTracked`, `Reaper.Signals.OnCleaned`, and `Reaper.Signals.OnRemoved` become live signals. `OnTracked` fires when an item is first registered. `OnCleaned` fires immediately after the physical teardown action executes on an item. `OnRemoved` fires after an item is evicted from the registry without being destroyed. Before Relay injection, all three are no-op stubs that emit a Studio warning if connected to, but produce no runtime errors in production.
