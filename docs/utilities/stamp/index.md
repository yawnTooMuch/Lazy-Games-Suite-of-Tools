# Stamp Library Overview

The **Stamp** library is an advanced, memory-safe wrapper for Roblox's `CollectionService` and Attribute system. Designed as a core utility within the Lazy Games Suite, Stamp transforms standard tags into observable, memory-managed **Streams**. 

By automatically binding the lifecycle of a tagged instance to a **Reaper Scope**, Stamp eliminates the memory leaks and dangling connections commonly associated with custom component systems.

---

## Core Philosophy

Standard `CollectionService` requires developers to manually track `GetInstanceAddedSignal`, `GetInstanceRemovedSignal`, and manage the cleanup of active connections. Stamp handles all of this under the hood. 

When you register a Stamp, you are creating a dedicated **StampStream**. This stream tracks all entities with a specific tag, provides isolated signals for when entities receive or lose the tag, and automatically provisions a garbage-collection scope for each instance.

### The Dependency Injection
Stamp relies heavily on the broader Lazy Games ecosystem to function. Before Stamp can be used, it must be injected with three core suite modules:
* **Reaper:** For automated memory and scope management.
* **Relay:** For high-performance, custom event signals.
* **Assignment:** For thread scheduling and polling.

---

## Key Features

### 1. Object-Oriented Streams (`StampStream`)
Instead of referencing strings globally, `Stamp.Register("TagName")` returns a `StampStream` object. This object acts as the central controller for that specific tag, providing methods like `AddTag()`, `RemoveTag()`, and `GetAll()`.

### 2. Automated Lifecycle Management
When an entity is tagged, the `Signals.Tagged` event fires and automatically provides a **ReaperScope** dedicated to that specific instance. When the tag is removed (or the instance is destroyed), the ReaperScope is instantly cleaned, safely disconnecting all bound events, loops, and threads.

### 3. Advanced Attribute Tracking
Stamp acts as a high-speed cache for Roblox Attributes. 
* **Global Queries:** Using `GetInstancesWithAttribute()`, you can instantly query all active entities sharing a specific attribute value without iterating over the entire game.
* **Observation:** `ObserveAttribute()` automatically tracks attribute changes and binds the connection directly to the instance's ReaperScope to prevent memory leaks.

### 4. Deferred Tagging (Client-Side Streaming)
Roblox's `StreamingEnabled` can cause issues on the client when attempting to tag instances that haven't replicated yet. Stamp solves this with `AddTagDeferred()`, which safely polls the parent folder until the instance streams in, automatically tagging it once it arrives.

### 5. Strict API Police
To prevent silent failures in production, Stamp features a built-in `ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE`. Active only in Roblox Studio, this strict validation layer actively monitors parameter types, string lengths, and object classes, instantly throwing descriptive errors if the API is misused.