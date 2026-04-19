# Relay API Documentation

This section covers all available APIs, methods, and sub-objects within the **Relay** library.

---

## Class: Relay

The main module table returned by `require()`-ing the Relay `ModuleScript`. Used to create, query, and configure signals globally.

### Functions Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Create](#create)** | `SignalObject` | Creates a new signal for the given ID, or returns the existing signal if one is already registered under that ID. |
| **[Exists](#exists)** | `boolean` | Returns whether a signal with the given ID currently exists in the active registry. |
| **[Inject](#inject)** | `void` | Registers an external Lazy Games Suite library into Relay, enabling features that depend on it. |

---

### Function Details

#### **Create**
```luau
Relay.Create(SignalID: string): SignalObject
```
Creates a new signal for the given ID, or returns the existing signal if one is already registered under that ID.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `SignalID` | `string` | A unique non-empty string identifier for the signal. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `SignalObject` | The newly created signal, or the existing registered signal if `SignalID` is already in use. |

!!! note "Studio Only"
    Passing a non-string or an empty string will throw a descriptive error in Studio. On live servers, this validation is skipped.

---

#### **Exists**
```luau
Relay.Exists(SignalID: string): boolean
```
Returns whether a signal with the given ID currently exists in the active registry.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `SignalID` | `string` | The signal ID to check for an active registration. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `boolean` | `true` if a live signal is registered under this ID, `false` otherwise. |

!!! tip "Garbage Collection Awareness"
    Because the registry holds signals with weak references, a signal with no external references may be collected between an `Exists()` check and a subsequent `Create()` call. Do not rely on `Exists()` as a pre-creation guard in hot paths.

---

#### **Inject**
```luau
Relay.Inject(ModuleName: string, ModuleTableObject: any): void
```
Injects an external library within the Lazy Games Suite of Tools environment. Currently supports the **Assignment** and **Reaper** libraries/framework.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ModuleName` | `string` | The name of the ModuleScript file. |
| `ModuleTableObject` | `any` | The required module table/object to inject. |

**Returns:** `void`

!!! tip "What Each Injection Does"
    Injecting `"Reaper"` enables the `:BindTo()` method on both `SignalObject` and `ConnectionObject`. Injecting `"Assignment"` replaces Relay's internal scheduler with the methods provided by the custom module, allowing fine-grained control over coroutine timing and priority. For `"Assignment"`, any scheduler method not present in the provided table falls back to the equivalent native `task` function automatically.

---

## Class: SignalObject

The core signal primitive. Created and retrieved via `Relay.Create()`. Manages a list of active connection callbacks and a queue of waiting coroutines.

### Methods Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Connect](#connect)** | `ConnectionObject` | Registers a persistent callback that executes each time the signal fires. |
| **[Once](#once)** | `ConnectionObject` | Registers a one-shot callback that disconnects itself before executing on the next fire. |
| **[Wait](#wait)** | `...any` | Yields the calling coroutine until the signal fires, then returns the fired arguments. |
| **[Fire](#fire)** | `void` | Resumes all yielded Wait threads and executes all live connection callbacks asynchronously. |
| **[DisconnectAll](#disconnectall)** | `void` | Immediately cancels all active connections on this signal and fires the `OnAbandoned` sub-signal. |
| **[GetConnectionCount](#getconnectioncount)** | `number` | Returns the count of live, non-cancelled connections currently listening to this signal. |
| **[Destroy](#destroy)** | `void` | Permanently destroys the signal, cancels all connections, resumes any yielded Wait threads with no arguments, and removes it from the global registry. |
| **[BindTo](#bindto-signal)** | `SignalObject` | Binds this signal's lifetime to a Reaper-tracked target, destroying the signal automatically when the target is destroyed. |

---

### Method Details

#### **Connect**
```luau
SignalObject:Connect(Callback: (...any) -> ()): ConnectionObject
```
Registers a persistent callback that executes each time the signal fires.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `(...any) -> ()` | The function to execute each time the signal fires. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ConnectionObject` | A handle to the active connection. |

!!! note "Studio Only"
    Passing a non-function or connecting to a destroyed signal will throw a descriptive error in Studio.

---

#### **Once**
```luau
SignalObject:Once(Callback: (...any) -> ()): ConnectionObject
```
Registers a one-shot callback that disconnects itself before executing on the next fire.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Callback` | `(...any) -> ()` | The function to execute on the next fire. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ConnectionObject` | A handle to the temporary connection. |

!!! tip "Disconnect Happens First"
    The connection is severed before the user callback runs, not after. This means that if you check `connection:IsConnected()` from inside the callback, it will already return `false`. It also means re-connecting to the same signal from within the callback will create a fresh, independent connection rather than conflicting with the one being cleaned up.

!!! note "Studio Only"
    Passing a non-function or connecting to a destroyed signal will throw a descriptive error in Studio.

---

#### **Wait**
```luau
SignalObject:Wait(): ...any
```
Yields the calling coroutine until the signal fires, then returns the fired arguments.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `...any` | A tuple of the arguments passed to `:Fire()`. |

!!! warning "Yields"
    This method suspends the calling coroutine. It will not resume until `:Fire()` or `:Destroy()` is called on this signal. If `:Destroy()` is called before the signal fires, the coroutine resumes with no return values — all variables assigned from `:Wait()` will be `nil`.

!!! note "Studio Only"
    Calling `:Wait()` on a destroyed signal will throw a descriptive error in Studio.

---

#### **Fire**
```luau
SignalObject:Fire(...: any): void
```
Resumes all yielded Wait threads and executes all live connection callbacks asynchronously.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `...` | `any` | Any number of arguments forwarded to all waiting threads and connection callbacks. |

**Returns:** `void`

!!! tip "Execution Order"
    Waiting threads (from `:Wait()`) are resumed first. Connection callbacks are then executed in the order they were connected. All execution is asynchronous — each callback runs in its own independent coroutine via the active scheduler.

!!! tip "Mid-Fire Connections Are Deferred"
    Connections added to the signal from within a callback during an active fire cycle are registered immediately, but will not be invoked until the next call to `:Fire()`. Only connections that existed at the moment `:Fire()` was called participate in the current cycle.

!!! note "Studio Only"
    Firing a destroyed signal will throw a descriptive error in Studio.

---

#### **DisconnectAll**
```luau
SignalObject:DisconnectAll(): void
```
Immediately cancels all active connections on this signal and fires the `OnAbandoned` sub-signal.

**Parameters:** `void`

**Returns:** `void`

!!! warning "Side Effect"
    Triggers `SignalObject.Signals.OnAbandoned` after clearing all connections, even if the `OnAbandoned` signal itself has no listeners. The parent signal remains usable after this call — new connections can still be established.

!!! note "Studio Only"
    Calling `:DisconnectAll()` on a destroyed signal will throw a descriptive error in Studio.

---

#### **GetConnectionCount**
```luau
SignalObject:GetConnectionCount(): number
```
Returns the count of live, non-cancelled connections currently listening to this signal.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `number` | The number of active connections. |

!!! note "Studio Only"
    Calling this on a destroyed signal will throw a descriptive error in Studio.

---

#### **Destroy**
```luau
SignalObject:Destroy(): void
```
Permanently destroys the signal, cancels all connections, resumes any yielded Wait threads with no arguments, and removes it from the global registry.

**Parameters:** `void`

**Returns:** `void`

!!! danger "Irreversible"
    Once destroyed, a signal cannot be reconnected or fired. Any subsequent method call on a destroyed `SignalObject` will either silently no-op (in production) or throw a descriptive error (in Studio). Calling `:Destroy()` more than once is safe — subsequent calls are silently ignored. A new signal with the same ID can be created via `Relay.Create()`.

---

#### **BindTo (Signal)**
```luau
SignalObject:BindTo(TieTarget: any): SignalObject
```
Binds this signal's lifetime to a Reaper-tracked target, destroying the signal automatically when the target is destroyed.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `TieTarget` | `any` | The instance, table, or ID being tracked by Reaper. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `SignalObject` | Returns `self` to allow method chaining. |

!!! danger "Strict Dependency: Reaper"
    `Relay.Inject("Reaper", ...)` must be called before using `:BindTo()`. In Studio, calling this without Reaper injected, or passing `nil` as the target, will throw a descriptive error. Calling `:BindTo()` on an already-destroyed signal silently returns `self` with no effect.

---

## Class: ConnectionObject

A handle representing a single active listener on a `SignalObject`. Returned by `:Connect()` and `:Once()`.

### Methods Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Disconnect](#disconnect)** | `void` | Severs this connection from its parent signal, stopping the callback from receiving future fires. |
| **[IsConnected](#isconnected)** | `boolean` | Returns whether this connection is currently active and has not been disconnected or cancelled. |
| **[BindTo](#bindto-connection)** | `ConnectionObject` | Binds this connection's lifetime to a Reaper-tracked target, disconnecting it automatically when the target is destroyed. |

---

### Method Details

#### **Disconnect**
```luau
ConnectionObject:Disconnect(): void
```
Severs this connection from its parent signal, stopping the callback from receiving future fires.

**Parameters:** `void`

**Returns:** `void`

!!! tip "Idempotent"
    Calling `:Disconnect()` on an already-disconnected connection is safe and has no effect. Subsequent calls are silently ignored.

---

#### **IsConnected**
```luau
ConnectionObject:IsConnected(): boolean
```
Returns whether this connection is currently active and has not been disconnected or cancelled.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `boolean` | `true` if connected, `false` if cancelled or disconnected. |

---

#### **BindTo (Connection)**
```luau
ConnectionObject:BindTo(TieTarget: any): ConnectionObject
```
Binds this connection's lifetime to a Reaper-tracked target, disconnecting it automatically when the target is destroyed.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `TieTarget` | `any` | The instance, table, or ID being tracked by Reaper. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `ConnectionObject` | Returns `self` to allow method chaining. |

!!! danger "Strict Dependency: Reaper"
    `Relay.Inject("Reaper", ...)` must be called before using `:BindTo()`. In Studio, calling this without Reaper injected, or passing `nil` as the target, will throw a descriptive error. Calling `:BindTo()` on an already-disconnected connection silently returns `self` with no effect.

---

## Miscellaneous

### **SignalObject.Signals.OnAbandoned**
```luau
SignalObject.Signals.OnAbandoned:Connect(Callback: () -> ())
```
A built-in companion signal that fires automatically whenever the parent signal's live connection count drops to exactly zero.

This fires in two scenarios: when the last connection individually calls `:Disconnect()` or is cancelled, and when `:DisconnectAll()` is called explicitly. It does not fire when `:Destroy()` is called — destruction takes a separate cleanup path that destroys the `OnAbandoned` companion along with the parent.

!!! tip "Primary Use Case"
    Use `OnAbandoned` to pause expensive background loops (AI calculations, radar sweeps, frame-rate-dependent updates) when no scripts are actively listening, avoiding wasted CPU cycles in unpopulated areas or inactive game phases.

!!! info "No Recursive Abandonment"
    The `OnAbandoned` companion signal does not carry its own `.Signals` property. You cannot subscribe to an "abandoned" event on `OnAbandoned` itself — only top-level signals created via `Relay.Create()` have this companion.
