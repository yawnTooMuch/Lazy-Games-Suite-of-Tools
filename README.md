# Stamp

**Type:** Library  
_Stamp is a memory-safe, object-oriented wrapper for Roblox's `CollectionService` and `Attribute System` that turns raw tags into observable, automatically managed lifecycle streams._

---

## Overview

Working with `CollectionService` directly places a heavy bookkeeping burden on the developer. Every time an instance gains or loses a tag, you must remember to connect the right signals, manage a table of live connections, and manually disconnect everything the moment the instance is removed — or risk a creeping memory leak that silently degrades server performance. Stamp removes that burden entirely.

When you call `Stamp.Register("TagName")`, Stamp returns a **StampStream** — a dedicated controller for that tag. The stream automatically listens for any instance that gains or loses the tag, assigns each newly tagged instance its own isolated **ReaperScope**, and fires reactive signals your code can subscribe to. When a tag is removed or an instance is destroyed, the scope is torn down immediately, disconnecting every event, loop, and task that was bound to it. No tables to maintain. No connections to track. No leaks.

Stamp is used across both the server and client. Server-side, it manages gameplay entities such as enemies, interactable props, and match state objects. Client-side, it handles UI bindings and streaming-safe deferred tagging for instances that may not have replicated yet. Because `CollectionService` tags replicate across the network, a single tag registered on the server automatically triggers the stream on any client that has also registered it.

---

## External Dependencies

Stamp requires three other modules from the Lazy Games Suite to be injected before any stream can be registered. Attempting to register a tag without all three present results in an immediate error.

- **Reaper** — Provides the garbage-collection scope system. Stamp provisions a unique scope for every tagged instance and relies on Reaper to destroy it when the tag is removed.
- **Relay** — Provides the high-performance custom signal objects that back `.Signals` APIs.
- **Assignment** — Provides the thread scheduler. Stamp uses it to safely spawn initial attribute callbacks and to drive the polling loop inside `AddTagDeferred`.

---

## Key Features

### Object-Oriented Streams (`StampStream`)

Rather than working with string tag names scattered across your codebase, `Stamp.Register("TagName")` returns a `StampStream` object. This object is the single authoritative controller for that tag: it owns the `AddTag`, `RemoveTag`, `GetAll`, and attribute methods. Calling `Register` a second time with the same tag name returns the same live stream rather than creating a duplicate, making it safe to require from multiple scripts.

### Automated Lifecycle Management

Each time an instance receives a tag, Stamp automatically allocates a dedicated garbage-collection scope for it and fires `Signals.Tagged`, passing both the instance and that scope to your callback. Any event, loop, or task you bind to the scope lives exactly as long as the tag does — no longer, no shorter. When the tag is removed or the instance is destroyed, the scope is torn down and every resource bound to it is released in one synchronised operation.

Think of the scope like a contract: everything created inside a `Tagged` callback and bound to the scope is guaranteed to be cleaned up the moment the instance leaves the stream — without you writing a single line of cleanup code.

### Instant Tag Querying

Every stream keeps its own private roster of the instances it currently tracks. When you call `GetAll()` or `GetCount()`, Stamp reads directly from that roster — it does not ask `CollectionService` for all tagged instances across the whole game, and it does not search any global table shared with other streams. The result is always scoped to exactly the entities that belong to your stream, and the cost of the query grows only with the number of instances in that specific stream, not with the total number of tagged objects in the game.

This is distinct from the attribute query system: attribute queries filter across cached values, whereas `GetAll()` simply returns the bounded set of instances that are live inside this stream right now. Both are fast for the same reason — neither walks the workspace hierarchy.

### Advanced Attribute Tracking

Stamp maintains an internal lookup table for attributes set through its own API, enabling fast querying without walking the workspace hierarchy. Two levels of query are available:

- **Global** — `Stamp.GetInstancesWithAttribute(Key, Value?)` searches across every registered stream simultaneously.
- **Local** — `StampStream:GetInstancesWithAttribute(Key, Value?)` narrows the search to only the instances tracked by that specific stream.

Both functions accept an optional value filter. Omitting the value returns every instance that possesses the attribute at all, regardless of its current value. Only instances with a live parent are returned; entries for destroyed instances are excluded automatically.

!!! warning "Supported Attribute Types"
    Stamp's attribute cache only supports the types that Roblox itself permits on instances: `string`, `number`, `boolean`, `UDim`, `UDim2`, `BrickColor`, `Color3`, `Vector2`, `Vector3`, `NumberRange`, `NumberSequence`, `ColorSequence`, `Rect`, and `Font`. Attempting to set or query an unsupported type will throw an error in Studio.

### Reactive Attribute Observation

`StampStream:ObserveAttribute()` collapses three separate tasks — reading the current value, connecting a change listener, and cleaning up that listener — into a single call. The callback fires immediately with the attribute's current value, then fires again on every future change. The connection is automatically tied to the tagged instance's scope, so it is disconnected the moment the tag is removed, with no manual intervention required.

### Deferred Tagging for Client-Side Streaming

When Roblox's `StreamingEnabled` is active, instances do not always exist on the client at the moment a script runs. `AddTagDeferred` solves this by polling a parent folder at regular intervals until the named instance streams in, then tagging it automatically. A configurable timeout ensures the polling does not run indefinitely if the instance never arrives.

### Studio Parameter Validation

In Roblox Studio, Stamp activates a strict parameter validation layer across every public API call. It checks argument types, enforces string length limits, validates attribute types against Roblox's supported set, and throws descriptive, traceback-annotated errors the moment something is passed incorrectly. This layer is disabled automatically in live game servers, so there is no performance cost in production.
