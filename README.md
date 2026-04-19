# Relay

**Type:** Library  
_A purely Luau-based signal and event library that replaces `BindableEvent` with a global, decoupled, memory-safe communication backbone._

---

## Overview

Relay is a high-performance signal and event library for the Roblox Luau environment. It serves as a lightweight, memory-safe replacement for Roblox's native `BindableEvent` objects, designed for use across server-side, client-side, and shared systems within the Lazy Games Suite.

The problem Relay addresses is twofold. Native `BindableEvent` instances carry the cost of Luau-to-C++ boundary crossings on every fire and every connection — overhead that compounds under load. They are also first-class Roblox `Instance` objects, which means they must be parented, passed around, and manually destroyed. In high-complexity projects this creates tight coupling between systems and a persistent risk of memory leaks when cleanup is missed. Relay operates entirely within the Luau VM using optimised table closures, eliminating both the boundary cost and the instance lifecycle problem entirely.

Rather than passing signal objects between scripts, systems communicate by broadcasting to and listening on a shared global registry using plain string identifiers. A combat system can fire `"Combat_PlayerDamaged"` without knowing or caring that a quest system is listening. A quest system can connect without knowing or caring who fires. Neither script imports nor references the other. This decoupling is the primary architectural purpose of the library.

---

## External Dependencies

Relay integrates with two other libraries in the Lazy Games Suite, both registered at startup via `Relay.Inject()`:

- **Reaper**: Provides lifecycle tracking for signals and connections. Once injected, `:BindTo(target)` becomes available on any `SignalObject` or `ConnectionObject`, automatically destroying or disconnecting it when the tracked target is removed from the game. Without Reaper, calls to `:BindTo()` will throw an error in Studio.

- **Assignment**: A custom thread scheduler that replaces Luau's native `task` library internally. Once injected, all spawning, deferring, delaying, waiting, and cancellation calls inside Relay route through the custom scheduler instead, giving precise control over execution timing and priority.

Neither dependency is required for basic usage — Relay functions correctly without either, using the native `task` library as a fallback. Reaper is strictly required only if you intend to use `:BindTo()`.

---

## Key Features

### Iteration-Safe Event Firing

A common failure mode in custom signal libraries occurs when a callback disconnects itself during a firing loop, invalidating the iteration and causing other callbacks to be skipped. Relay avoids this by recording how many connections are active at the moment `:Fire()` is called, then iterating exactly that many entries. Any connection that cancels itself during the loop is marked and safely skipped, but no entries are removed from the list until the fire cycle completes. The compaction sweep only runs after the outermost fire has finished, guaranteeing that every connection that was live at the start of the fire gets a chance to execute.

This design also means that connections added from within a callback during an active fire cycle are registered, but will not be invoked until the next call to `:Fire()`. This prevents runaway re-entrance without any extra guard code on the caller's side.

### Autonomous Lifecycle Management via `:BindTo()`

By injecting the Reaper module, any `SignalObject` or `ConnectionObject` can be chained to the lifetime of a tracked target. When that target leaves the data model, the signal is destroyed or the connection is disconnected automatically — no manual cleanup code required. This removes an entire category of memory leak common in event-driven architectures, particularly for per-character, per-instance, and per-round listeners.

### The `OnAbandoned` Sub-Signal

Every `SignalObject` automatically carries a `.Signals.OnAbandoned` companion signal. This companion fires whenever the parent signal's listener count drops to exactly zero, whether through individual disconnections or a full `DisconnectAll()` call. It does not fire when `Destroy()` is called — destruction takes a separate cleanup path. `OnAbandoned` is the intended mechanism for pausing expensive background processes (AI loops, radar sweeps, timer systems) when no listeners remain, avoiding wasted CPU time in unpopulated areas or idle game phases.

### Global Weak Registry

Any script can retrieve a signal by its string identifier without importing any other module — both the emitter and the listener call `Relay.Create()` with the same ID and receive the same `SignalObject`. Signals that have no remaining external references outside the registry are eligible for automatic garbage collection by the Luau VM, so abandoned signals do not accumulate permanently in memory. Because of this, a signal may be collected between an `Exists()` check and a subsequent `Create()` call in low-reference scenarios. Do not rely on `Exists()` as a pre-creation guard.

### Drop-In Roblox API Compatibility

Relay's public method names — `Connect`, `Once`, `Wait`, `Fire` — are intentionally identical to those on Roblox's native `RBXScriptSignal` and `BindableEvent`. Existing code that connects to or fires native events can be migrated to Relay by swapping the signal source, with no changes to the connection or firing logic.

### Studio-Only Strict Validation

Relay includes a parameter validation layer that is active only inside Roblox Studio and automatically disabled on live servers. In Studio, common mistakes — passing a non-function to `Connect`, calling `Fire` on a destroyed signal, or using `:BindTo()` without Reaper injected — throw descriptive errors with full tracebacks. In production these checks are skipped entirely, adding zero validation overhead at runtime.
