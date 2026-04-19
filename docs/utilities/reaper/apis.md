# Reaper API Reference

This page documents every public function, method, type, and signal surface exposed by the **Reaper** framework.

---

## Class: Reaper

The global singleton module used to register items for tracking, instantiate Scopes, execute teardowns, fetch live handles, and inject optional dependencies.

### Functions Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Inject](#inject)** | `void` | Registers an external library from the Lazy Games Suite into Reaper's runtime, activating features that are unavailable without it. |
| **[Track](#track)** | `TrackObject` | Registers a raw item into Reaper's memory system and returns a handle to manage its lifecycle. |
| **[Scope](#scope)** | `ScopeObject` | Creates a named, managed container that accumulates items and tears them all down together when the Scope is cleaned. |
| **[Clean](#clean)** | `void` | Immediately destroys one or more tracked items and cascades teardown to everything they own. |
| **[Remove](#remove)** | `{Reapable}` | Releases one or more items from Reaper's registry without destroying them, returning the raw items to the caller. |
| **[Get](#get)** | `TrackObject?` | Returns the live tracking handle for an item or Scope registered under a given identifier, or `nil` if not found. |
| **[Is](#is)** | `boolean` | Returns `true` if a value is a live, uncleaned, un-evicted tracking handle — including both `TrackObject` and `ScopeObject` instances. |
| **[IsCleanable](#iscleanable)** | `boolean` | Returns `true` if a value is an uncleaned `ScopeObject` handle, regardless of its eviction state. |

---

### Function Details

#### Inject

```luau
Reaper.Inject(ModuleName: string, ModuleTableObject: any): ()
```

Injects an external library within the Lazy Games Suite of Tools environment. Currently supports the **Assignment** and **Relay** libraries.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ModuleName` | `string` | The name of the ModuleScript file. |
| `ModuleTableObject` | `any` | The required module table/object to inject. |

**Returns:** `void`

!!! tip "Standalone Operation"
    Reaper is fully functional without any injection. Inject **Assignment** to enable `:Repeat()` and advanced scheduling inside Scopes. Inject **Relay** to enable the three global lifecycle signals on `Reaper.Signals`.

---

#### Track

```luau
Reaper.Track(Item: Reapable, ItemClassification: Classification?, CustomMethod: string?, IsProtected: boolean?): TrackObject
```

Registers a raw item into Reaper's memory system and returns a handle to manage its lifecycle. If the item is already registered, the existing handle is returned without creating a duplicate entry. The item's type is detected automatically unless `ItemClassification` is explicitly provided.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Item` | `Reapable` | The `Instance`, `RBXScriptConnection`, `thread`, `function`, or `table` to register. |
| `ItemClassification` | `Classification?` | *(Optional)* Explicitly overrides auto-classification. Accepts `"Instance"`, `"Connection"`, `"Thread"`, `"Function"`, `"Table"`, `"Scope"`, or `"Unknown"`. |
| `CustomMethod` | `string?` | *(Optional)* Name of the method to call on the item during teardown instead of the default (`Destroy`, `Disconnect`, or `task.cancel`). |
| `IsProtected` | `boolean?` | *(Optional)* If `true`, the item is released from the registry intact when its natural end-of-life is detected, allowing external poolers to reclaim it instead of destroying it. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `TrackObject` | The tracking handle for the item. If the item was already registered, the existing handle is returned. |

!!! danger "Abstract Types Require a Lifecycle Anchor"
    Tracking a `Table`, `Function`, or `Unknown` type places it in the zero-cost manual tier because these types have no native dead-state. Reaper will never automatically clean them. You **must** chain them to a Scope or Track, or call `Reaper.Clean()` explicitly, to prevent memory leaks. A Studio warning is emitted whenever this pattern is detected.

!!! tip "Passing a Live Handle Returns It Unchanged"
    If you pass a live `TrackObject` or `ScopeObject` as the `Item` argument, `Reaper.Track()` detects it immediately and returns it as-is without creating any new registration. This makes it safe to call `Track()` defensively when the caller is uncertain whether an item is already registered.

!!! note "Studio Only"
    Argument validation and the `nil` guard only fire in Roblox Studio. In production, invalid inputs fail silently.

---

#### Scope

```luau
Reaper.Scope(ScopeID: string): ScopeObject
```

Creates a named, managed container that accumulates items and tears them all down together when the Scope is cleaned. The returned `ScopeObject` is fully configured on creation and immediately reachable by its ID from any script via `Reaper.Get()` or `Reaper.Clean()`.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ScopeID` | `string` | Unique string identifier for this Scope. Used for cross-script retrieval and teardown. Must not already be in use. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ScopeObject` | The Scope handle. |

!!! danger "Throws"
    Throws in Studio if `ScopeID` is an empty string or if a Scope or item with the same ID already exists in the registry.

---

#### Clean

```luau
Reaper.Clean(...: any): ()
```

Immediately destroys one or more tracked items and cascades teardown to everything they own. For each identifier, Reaper resolves it to its tracking handle, destroys the primary item, then recursively destroys all chained children and cleans all bound Scopes. The item is then removed from the registry.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `...` | `any` | Variadic list of identifiers. Each can be a string `AssignID`, a raw item reference, or a `TrackObject`. |

**Returns:** `void`

!!! warning "Cascade Teardown"
    `Reaper.Clean()` is recursive. Cleaning a Track also destroys all chained children and all bound Scopes, including their children. Ensure dependent systems do not hold stale references to objects in the teardown tree.

---

#### Remove

```luau
Reaper.Remove(...: any): {Reapable}
```

Releases one or more items from Reaper's registry without destroying them, returning the raw items to the caller. The primary item itself is left intact and de-registered so it can be safely reclaimed by an external system (such as an Object Pool). Any event-based death listener attached to the primary item is disconnected. Any children chained to the item and any Scopes bound to it are **destroyed**, not released — only the root item is preserved.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `...` | `any` | Variadic list of identifiers. Each can be a string `AssignID`, a raw item reference, or a `TrackObject`. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `{Reapable}` | An array of the raw primary items that were released, in the order they were processed. |

!!! warning "Children Are Destroyed, Not Released"
    `Reaper.Remove()` only preserves the **primary** item. Any items chained to it or Scopes bound to it are fully destroyed in the same call. If you need to preserve child items as well, unchain them first with `:Unchain()` before calling `Reaper.Remove()`.

---

#### Get

```luau
Reaper.Get(Identifier: any): TrackObject?
```

Returns the live tracking handle for an item or Scope registered under a given identifier, or `nil` if not found. String identifiers are resolved in constant time. Raw item references are also resolved in constant time via direct registry lookup. Returns `nil` if the identifier has never been registered, or if the object has already been cleaned or evicted.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Identifier` | `any` | A string `AssignID`/`ScopeID`, a raw item reference, or a `TrackObject`. Booleans and numbers are rejected in Studio. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `TrackObject?` | The live `TrackObject` or `ScopeObject`, or `nil` if not found. |

!!! tip "Cross-Script Appending"
    Use `Reaper.Get()` to retrieve a Scope created in another module and dynamically chain additional items to it. When that Scope is eventually cleaned, your chained items are torn down automatically — no shared reference required.

---

#### Is

```luau
Reaper.Is(Value: any): boolean
```

Returns `true` if a value is a live, uncleaned, un-evicted tracking handle — including both `TrackObject` and `ScopeObject` instances. Passing any other value — a raw `Instance`, a cleaned handle, a plain table, or `nil` — returns `false`.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Value` | `any` | The value to inspect. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `boolean` | `true` if `Value` is a live, valid `TrackObject` or `ScopeObject`; `false` otherwise. |

!!! tip "Scope Detection"
    `Reaper.Is()` returns `true` for live `ScopeObject`s as well as `TrackObject`s, because a Scope is an extension of a Track and passes the same validity checks. To test exclusively for a live Scope, use `Reaper.IsCleanable()` instead.

---

#### IsCleanable

```luau
Reaper.IsCleanable(Value: any): boolean
```

Returns `true` if a value is an uncleaned `ScopeObject` handle, regardless of its eviction state. Distinguishes a live `ScopeObject` from a plain `TrackObject`, a cleaned Scope, or any non-Reaper value. Unlike `Reaper.Is()`, this check does not require the handle to be un-evicted — an evicted Scope that has not been cleaned will still return `true`.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Value` | `any` | The value to inspect. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `boolean` | `true` if `Value` is a `ScopeObject` whose cleaned flag has not been set; `false` otherwise. |

---

## Class: TrackObject

The core handle representing a tracked item. Returned by `Reaper.Track()`. Holds the item reference, its resolved classification, and its configured identity.

### Methods Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Configure](#configure)** | `TrackObject` | Assigns a unique string identifier and a dead-state check interval to this handle, making it reachable by name from any script. |
| **[Chain](#chain)** | `TrackObject` | Subordinates a raw item to this handle so it is destroyed alongside it when this handle is cleaned. |
| **[HandleScope](#handlescope)** | `TrackObject` | Subordinates an entire Scope to this handle so it is cleaned when this handle is cleaned. |
| **[Destroy](#destroy)** | `void` | Immediately destroys this handle and everything it owns — equivalent to calling `Reaper.Clean` with this handle. |

---

### Method Details

#### Configure

```luau
TrackObject:Configure(AssignID: string, Frequency: number): TrackObject
```

Assigns a unique string identifier and a dead-state check interval to this handle, making it reachable by name from any script. A `Frequency` of `0` places the handle in the manual tier with no background polling; any positive value places eligible item types in the frequency-polled tier and schedules checks at that interval in seconds. Configuration is a one-time operation; calling `:Configure()` on an already-configured handle throws in Studio.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `AssignID` | `string` | Unique identifier used for cross-script retrieval and teardown. Must not already be in use. |
| `Frequency` | `number` | Dead-state check interval in seconds. `0` opts out of all background polling. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `TrackObject` | Returns `self` for method chaining. |

!!! warning "Frequency Is Ignored for Instances and Manual-Tier Items"
    Instances are always monitored via an `AncestryChanged` hook registered at tracking time — they receive event-driven detection regardless of what `Frequency` is passed. When `:Configure()` is called on an Instance track, the `Frequency` argument is silently ignored and treated as `0`. The same applies to `Table`, `Function`, `Scope`, and `Unknown` types. Only `Connection` and `Thread` items tracked in the background batch tier are eligible to be promoted into the frequency-polled tier by passing a non-zero value.

!!! danger "Throws"
    Throws in Studio if `AssignID` is empty or already registered, if `Frequency` is negative, or if this handle has already been configured, cleaned, or evicted.

---

#### Chain

```luau
TrackObject:Chain(ChildItem: Reapable, CustomMethod: string?): TrackObject
```

Subordinates a raw item to this handle so it is destroyed alongside it when this handle is cleaned. The item's type is auto-detected and the correct teardown action is stored. If the item currently belongs to another owner, it is released from that owner before being registered here — Last Call Supremacy. Returns `self` for fluent chaining.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ChildItem` | `Reapable` | The raw item to subordinate. Must not be `nil`, the handle's own item, or a `TrackObject`/`ScopeObject` wrapper. |
| `CustomMethod` | `string?` | *(Optional)* Explicit teardown method name to call on the child instead of the default. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `TrackObject` | Returns `self` for method chaining. |

!!! danger "Raw Items Only"
    Pass the raw underlying item, never a `TrackObject` or `ScopeObject` wrapper. To bind a Scope to a Track, use `:HandleScope()` or `ScopeObject:BindToTrack()`. Passing a wrapper throws in Studio.

---

#### HandleScope

```luau
TrackObject:HandleScope(Scope: string | ScopeObject): TrackObject
```

Subordinates an entire Scope to this handle so it is cleaned when this handle is cleaned. When teardown cascades to the Scope, the Scope's full child teardown runs in turn. Accepts either the live `ScopeObject` or its string `ScopeID`. If the Scope is currently owned by another manager, it is released first - Last Call Suppremacy.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Scope` | `string | ScopeObject` | The `ScopeObject` to subordinate, or its string `ScopeID`. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `TrackObject` | Returns `self` for method chaining. |

!!! danger "Throws"
    Throws in Studio if the argument is a `TrackObject` (not a Scope), a non-string primitive, or an empty string. Tracks may only handle Scopes — not other Tracks.

---

#### Destroy

```luau
TrackObject:Destroy(): ()
```

Immediately destroys this handle and everything it owns — equivalent to calling `Reaper.Clean` with this handle. All chained children are torn down and all bound Scopes are cleaned in the same cascade.

**Parameters:** `void`

**Returns:** `void`

---

## Class: ScopeObject

An extension of `TrackObject` representing a named, temporary logic state. Created via `Reaper.Scope()`. Inherits all `TrackObject` methods and adds the following.

### Methods Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[BindToTrack](#bindtotrack)** | `ScopeObject` | Submits this Scope to a Track so it is cleaned when the Track is cleaned. |
| **[Unchain](#unchain)** | `ScopeObject` | Removes a chained item from this Scope without destroying it. |
| **[CleanChild](#cleanchild)** | `ScopeObject` | Immediately destroys a specific item currently chained to this Scope, removing it from the Scope's child list. |
| **[Connect](#connect)** | `RBXScriptConnection` | Connects a callback to a signal and automatically adds the resulting connection to this Scope's child list. |
| **[Spawn](#spawn)** | `thread` | Launches a coroutine and automatically adds it to this Scope's child list, cancelling it if the Scope is cleaned. |
| **[Defer](#defer)** | `any` | Schedules a callback to run at the end of the current frame and adds the scheduled task to this Scope's child list. |
| **[Delay](#delay)** | `any` | Schedules a callback to run after a set number of seconds and adds the task to this Scope's child list. |
| **[Repeat](#repeat)** | `any` | Schedules a callback to repeat a fixed number of times and adds the task to this Scope's child list. |

---

### Method Details

#### BindToTrack

```luau
ScopeObject:BindToTrack(Track: TrackObject): ScopeObject
```

Submits this Scope to a Track so it is cleaned when the Track is cleaned. Achieves the same result as calling `Track:HandleScope(self)` but reads as the Scope declaring its own lifetime contract, which is preferred when the Scope is the acting module. The target Track must be configured with a string identifier before a Scope can bind to it.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Track` | `TrackObject` | The parent Track to bind this Scope to. Must not be a `ScopeObject` and must have a configured identifier. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ScopeObject` | Returns `self` for method chaining. |

!!! danger "Throws"
    Throws in Studio if this Scope has been cleaned or evicted, if `Track` is a `ScopeObject`, or if `Track` has no configured identifier.

---

#### Unchain

```luau
ScopeObject:Unchain(ChildItem: Reapable): ScopeObject
```

Removes a chained item from this Scope without destroying it. The item is de-registered from this Scope's ownership but is left fully intact.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ChildItem` | `Reapable` | The physical item to remove from this Scope's child list. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ScopeObject` | Returns `self` for method chaining. |

!!! danger "Throws"
    Throws in Studio if `ChildItem` is `nil` or if this Scope has already been destroyed.

---

#### CleanChild

```luau
ScopeObject:CleanChild(ChildItem: Reapable): ScopeObject
```

Immediately destroys a specific item currently chained to this Scope, removing it from the Scope's child list. The Scope itself remains alive and continues owning any other chained items. If the item has its own independent tracking handle, that handle is also cleaned.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ChildItem` | `Reapable` | The physical item to tear down and remove from this Scope. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ScopeObject` | Returns `self` for method chaining. |

!!! danger "Throws"
    Throws in Studio if `ChildItem` is `nil` or if this Scope has already been destroyed.

---

#### Connect

```luau
ScopeObject:Connect(Signal: any, Callback: function): RBXScriptConnection
```

Connects a callback to a signal and automatically adds the resulting connection to this Scope's child list. When the Scope is cleaned, the connection is automatically disconnected. Accepts `RBXScriptSignal` instances or any table with a `:Connect()` method.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Signal` | `any` | The event or signal to connect to. Must be an `RBXScriptSignal` or a table with a `:Connect()` function. |
| `Callback` | `function` | The function to execute when the signal fires. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `RBXScriptConnection` | The generated connection, also owned by this Scope. |

!!! danger "Throws"
    Throws in Studio if the Scope has been cleaned or evicted, if `Signal` is `nil` or not connectable, or if `Callback` is not a function.

---

#### Spawn

```luau
ScopeObject:Spawn(Callback: function, ...any): thread
```

Launches a coroutine and automatically adds it to this Scope's child list, cancelling it if the Scope is cleaned. The coroutine is registered to this Scope before it begins executing, so teardown is safe even if the Scope is cleaned from within the spawned function. Any arguments after `Callback` are forwarded to the coroutine on its first resume.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `function` | The function to run in the new coroutine. |
| `...` | `any` | Variadic arguments forwarded to the callback on resume. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `thread` | The spawned coroutine. |

!!! danger "Throws"
    Throws in Studio if the Scope has been cleaned or evicted, or if `Callback` is not a function.

---

#### Defer

```luau
ScopeObject:Defer(Callback: function, ...any): any
```

Schedules a callback to run at the end of the current frame and adds the scheduled task to this Scope's child list. If the Scope is cleaned before the deferred task executes, the task is cancelled and never runs.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `function` | The function to defer. |
| `...` | `any` | Variadic arguments forwarded to the callback when it executes. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `any` | The handle returned by the scheduler, usable for manual cancellation if needed. |

!!! danger "Throws"
    Throws in Studio if the Scope has been cleaned or evicted, or if `Callback` is not a function.

!!! note "Assignment vs Native Task"
    If Assignment is injected, the task is deferred instead in the next running frame.

---

#### Delay

```luau
ScopeObject:Delay(TimeDelay: number, Callback: function, ...any): any
```

Schedules a callback to run after a set number of seconds and adds the task to this Scope's child list. If the Scope is cleaned before the delay elapses, the task is cancelled and never runs.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `TimeDelay` | `number` | Seconds to wait before executing the callback. |
| `Callback` | `function` | The function to run after the delay. |
| `...` | `any` | Variadic arguments forwarded to the callback when it executes. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `any` | The handle returned by the scheduler, usable for manual cancellation if needed. |

!!! danger "Throws"
    Throws in Studio if the Scope has been cleaned or evicted, if `TimeDelay` is not a number, or if `Callback` is not a function.

---

#### Repeat

```luau
ScopeObject:Repeat(Count: number, Interval: number?, Callback: function, ...any): any
```

Schedules a callback to repeat a fixed number of times and adds the task to this Scope's child list. Each repetition is separated by `Interval` seconds. When the Scope is cleaned, any remaining repetitions are cancelled.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Count` | `number` | Total number of times to execute the callback. |
| `Interval` | `number?` | *(Optional)* Seconds between repetitions. Behaviour when omitted is defined by the injected Assignment scheduler. |
| `Callback` | `function` | The function to repeat. |
| `...` | `any` | Variadic arguments forwarded to the callback on each execution. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `any` | The handle returned by the Assignment scheduler. |

!!! danger "Strict Dependency: Assignment Library"
    `:Repeat()` requires the **Assignment** library to be injected via `Reaper.Inject("Assignment", ...)`. Without it, this method is a no-op stub and produces no repetitions.

!!! danger "Throws"
    Throws in Studio if the Scope has been cleaned or evicted, if `Count` is not a number, or if `Callback` is not a function.

---

## Global Events: Reaper.Signals

`Reaper.Signals` is a table containing three lifecycle event signals. All three are no-op stubs until the **Relay** library is injected. Each signal is a `ListenerSignal` and exposes `Connect`, `Once`, and `Wait` methods.

!!! danger "Strict Dependency: Relay Library"
    Global lifecycle signals are powered by **Relay**. Without injection, connecting to any signal emits a Studio warning and returns a permanently-disconnected dummy connection. No runtime errors occur in production.

---

### Reaper.Signals.OnTracked

```luau
Reaper.Signals.OnTracked:Connect(Callback: (Item: any, Classification: string, AssignID: string?) -> ()): ConnectionObject
```

Fires immediately after an item is inserted into the registry. The callback receives the raw item, its resolved classification string, and its identifier if already configured — which is typically `nil` at the moment of tracking since `:Configure()` is usually called after `Track()`.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `function` | Receives `(Item: any, Classification: string, AssignID: string?)`. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ConnectionObject` | A Relay connection handle. |

---

### Reaper.Signals.OnCleaned

```luau
Reaper.Signals.OnCleaned:Connect(Callback: (Item: any, Classification: string) -> ()): ConnectionObject
```

Fires immediately after the physical teardown action has run on an item. The callback receives the raw item and its classification string. Fires for every item in a cascade, not just the root — including all chained children.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `function` | Receives `(Item: any, Classification: string)`. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ConnectionObject` | A Relay connection handle. |

!!! tip "Fires After Teardown"
    When `OnCleaned` fires, the item's teardown action has already executed. The raw `Item` value in the callback is the reference that was tracked — it may no longer be in a valid state depending on its type (e.g., a destroyed `Instance`).

---

### Reaper.Signals.OnRemoved

```luau
Reaper.Signals.OnRemoved:Connect(Callback: (Item: any, Classification: string) -> ()): ConnectionObject
```

Fires after an item has been released from the registry without being destroyed. The callback receives the raw item and its classification string. The item is still fully intact at the time this fires.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `function` | Receives `(Item: any, Classification: string)`. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ConnectionObject` | A Relay connection handle. |

---

### Signal: Once

```luau
Reaper.Signals.OnTracked:Once(Callback: (Item: any, Classification: string, AssignID: string?) -> ()): ConnectionObject
Reaper.Signals.OnCleaned:Once(Callback: (Item: any, Classification: string) -> ()): ConnectionObject
Reaper.Signals.OnRemoved:Once(Callback: (Item: any, Classification: string) -> ()): ConnectionObject
```

Connects a one-shot callback to a signal. The callback fires at most once, then the connection is automatically disconnected. Returns the same `ConnectionObject` as `:Connect()`, which can be manually disconnected before the signal fires if the one-shot is no longer needed.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `function` | The function to execute once when the signal fires. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ConnectionObject` | A Relay connection handle that disconnects itself after firing once. |

---

### Signal: Wait

```luau
Reaper.Signals.OnTracked:Wait(): (any, string, string?)
Reaper.Signals.OnCleaned:Wait(): (any, string)
Reaper.Signals.OnRemoved:Wait(): (any, string)
```

Yields the calling thread until the signal fires once, then resumes it with the signal's arguments. Equivalent to calling `:Once()` and then yielding, but expressed inline.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `T...` | The arguments the signal fired with, matching the callback signature for each respective signal. |

!!! warning "Yields"
    `:Wait()` yields the calling thread indefinitely until the signal fires. If the signal never fires (for example, because no items are ever tracked after this point), the thread will yield forever. Without Relay injection, calling `:Wait()` on a stub signal yields forever and emits a Studio warning.

---

## Exported Types

### `Reapable`

```luau
type Reapable = Instance | RBXScriptConnection | thread | (() -> ()) | { [any]: any }
```

The union of all value types that Reaper is capable of tracking and tearing down.

---

### `Classification`

```luau
export type Classification = "Instance" | "Connection" | "Thread" | "Function" | "Table" | "Scope" | "Unknown"
```

A string literal union representing the seven item categories Reaper recognises. Auto-classified by `typeof()` unless overridden via the `ItemClassification` parameter of `Reaper.Track()`.

---

### `TrackObject`

The handle returned by `Reaper.Track()`. Contains the four public methods described above plus the following readable fields. Internal state fields are not part of the public API and should not be accessed directly.

| Field | Type | Description |
| :--- | :--- | :--- |
| `Item` | `Reapable` | The raw physical item being tracked. |
| `AssignID` | `string?` | The registered identifier, or `nil` if not yet configured. |
| `Frequency` | `number?` | The effective check interval in seconds. For Instances and manual-tier items, this is always `0` regardless of what was passed to `:Configure()`. |
| `Classification` | `Classification` | The resolved classification string. |
| `IsProtected` | `boolean` | Whether the item is released instead of destroyed when its natural end-of-life is detected. |

---

### `ScopeObject`

An extension of `TrackObject`. All `TrackObject` fields apply. The `Classification` field is always `"Scope"`.

---

### `ConnectionObject`

The handle returned by signal `:Connect()` and `:Once()` calls on `Reaper.Signals` entries. Provided by the Relay library when injected; returned as a permanently-disconnected stub without it.

| Method | Returns | Description |
| :--- | :--- | :--- |
| `Disconnect()` | `void` | Disconnects this connection so the callback no longer fires. |
| `IsConnected()` | `boolean` | Returns `true` if this connection is still active. |
| `BindTo(TieTarget)` | `ConnectionObject` | Ties this connection's lifetime to another object, automatically disconnecting when that object is destroyed. |

---

### `ListenerSignal<T...>`

The signal interface exposed by each entry in `Reaper.Signals`. All three methods are available on every signal.

| Method | Returns | Description |
| :--- | :--- | :--- |
| `Connect(Callback)` | `ConnectionObject` | Connects a persistent callback. Fires every time the signal fires. |
| `Once(Callback)` | `ConnectionObject` | Connects a one-shot callback. Disconnects automatically after firing once. |
| `Wait()` | `T...` | Yields the calling thread until the signal fires, then returns the signal's arguments. |
