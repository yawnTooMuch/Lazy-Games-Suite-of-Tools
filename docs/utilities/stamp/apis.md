# Stamp API Reference

This page documents every public function, method, type, and signal surface exposed by the **Stamp** library.

---

## Class: Stamp

The top-level module. Used to inject dependencies, register streams, and perform cross-stream queries.

### Functions Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Inject](#inject)** `(ModuleName: string, ModuleTableObject: any)` | `void` | Provides a required Lazy Games Suite dependency to Stamp. |
| **[Register](#register)** `(TagName: string)` | `StampStream` | Returns the live stream for a tag, creating it if it does not yet exist. |
| **[GetInstancesWithAttribute (Global)](#getinstanceswithattribute-global)** `(Key: string, ExpectedValue: any?)` | `{PVInstance}` | Searches all registered streams for instances that possess the given attribute. |
| **[Destroy (Global)](#destroy-global)** `(TagName: string)` | `void` | Destroys the registered stream for a tag and cleans up all of its tracking. |
| **[Utility.CompactString](#utilitycompactstring)** `(InputString: string)` | `string` | Returns a copy of the string with all whitespace removed. |

---

### Function Details

#### Inject

```luau
Stamp.Inject(ModuleName: string, ModuleTableObject: any): ()
```

Injects an external library within the Lazy Games Suite of Tools environment. Currently supports the **Assignment**, **Relay** and **Reaper** libraries/frameworks.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ModuleName` | `string` | The name of the ModuleScript file. |
| `ModuleTableObject` | `any` | The required module table/object to inject. |

**Returns:** `void`

!!! danger "Strict Dependency: Reaper / Assignment / Relay"
    All three dependencies must be injected before calling `Stamp.Register`. Attempting to register a tag with any dependency missing throws an immediate error.

!!! note "Studio Only"
    In Roblox Studio, `ModuleName` must be a non-empty string and `ModuleTableObject` must be a table, or an error is thrown. Passing an unrecognised module name produces a warning but does not block injection.

---

#### Register

```luau
Stamp.Register(TagName: string): StampStream
```

Returns the active `StampStream` for the given tag. If no stream exists yet with a specific `TagName`, it creates a new one.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `TagName` | `string` | The `CollectionService` tag this stream will manage. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `StampStream` | The stream object for this tag. |

!!! danger "Strict Dependency: Reaper / Assignment / Relay"
    Throws immediately if any of the three required dependencies have not been injected.

!!! note "Studio Only"
    `TagName` must be a non-empty string or an error is thrown. Tag names longer than 100 characters produce a warning.

---

#### GetInstancesWithAttribute (Global)

```luau
Stamp.GetInstancesWithAttribute(Key: string, ExpectedValue: any?): {PVInstance}
```

Searches across **all** registered streams for instances that possess the given attribute key. Only instances with a live parent are included; entries for destroyed instances are excluded automatically.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Key` | `string` | The attribute name to search for. |
| `ExpectedValue` | `any?` | (Optional) When provided, only instances whose cached attribute value exactly matches this are returned. When omitted, all instances that possess the attribute — regardless of its value — are returned. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `{PVInstance}` | An array of matching `PVInstance`s. Returns an empty array if nothing matches. |

!!! note "Studio Only"
    `Key` must be a non-empty string with a maximum of 100 characters. If `ExpectedValue` is provided, its type must be one of Roblox's supported attribute types, or an error is thrown.

---

#### Destroy (Global)

```luau
Stamp.Destroy(TagName: string): ()
```

Destroys the registered stream for the named tag. Equivalent to calling `StampStream:Destroy()` directly. Has no effect if the stream has already been destroyed.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `TagName` | `string` | The tag name whose stream should be destroyed. |

**Returns:** `void`

!!! note "Studio Only"
    `TagName` must be a non-empty string or an error is thrown. Calling `Destroy (Global)` on a tag that has no active stream produces a warning in Studio.

---

#### Utility.CompactString

```luau
Stamp.Utility.CompactString(InputString: string): string
```

Returns a copy of the input string with all spaces, tabs, and newline characters removed. Useful for normalising tag names derived from user input or concatenated strings.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `InputString` | `string` | The string to compact. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `string` | The input string with all whitespace removed, or `""` if the input was invalid. |

---

## Class: StampStream

An object representing a single managed tag, returned by `Stamp.Register()`. Acts as the central controller for all tagging, attribute, and lifecycle operations on that tag.

### Methods Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[AddTag](#addtag)** `(Entity: PVInstance, IsAtomic: boolean?)` | `void` | Applies this stream's tag to the given entity. |
| **[AddTagDeferred](#addtagdeferred)** `(ParentFolder: Instance, EntityName: string, IsRecursive: boolean?, TimeoutSeconds: number?)` | `void` | Polls a parent folder until a named instance streams in, then tags it. |
| **[RemoveTag](#removetag)** `(Entity: PVInstance)` | `void` | Removes this stream's tag from the given entity. |
| **[RemoveAllTags](#removealltags)** `()` | `void` | Removes this stream's tag from every instance currently carrying it. |
| **[GetAll](#getall)** `()` | `{PVInstance}` | Returns an array of all instances currently tracked by this stream. |
| **[GetCount](#getcount)** `()` | `number` | Returns the number of instances currently tracked by this stream. |
| **[SetAttribute](#setattribute)** `(Entity: PVInstance, Key: string, Value: any)` | `void` | Sets a tracked attribute on a specific entity. |
| **[SetAttributeAll](#setattributeall)** `(Key: string, Value: any)` | `void` | Sets a tracked attribute on every instance currently in this stream. |
| **[GetAttribute](#getattribute)** `(Entity: PVInstance, Key: string)` | `any` | Returns the current value of an attribute on a specific entity. |
| **[GetInstancesWithAttribute (Local)](#getinstanceswithattribute-local)** `(Key: string, ExpectedValue: any?)` | `{PVInstance}` | Searches within this stream only for instances that possess the given attribute. |
| **[ObserveAttribute](#observeattribute)** `(Entity: PVInstance, Key: string, Callback: (Value: any) -> (), ScopeToBind: ReaperScope?)` | `RBXScriptConnection` | Fires a callback immediately with the current attribute value and again on every future change. |
| **[Destroy (Local)](#destroy-local)** `()` | `void` | Destroys this stream and cleans up all of its resources. |

### Events Summary

| Name | Description |
| :--- | :--- |
| **[Signals.Tagged](#signalstagged)** | Fires when an instance receives this tag. Provides the instance and its dedicated garbage-collection scope. |
| **[Signals.Untagged](#signalsuntagged)** | Fires when an instance loses this tag or is destroyed. |

---

### Method Details

#### AddTag

```luau
StampStream:AddTag(Entity: PVInstance, IsAtomic: boolean?): ()
```

Applies this stream's tag to the given entity via `CollectionService`. This triggers `Signals.Tagged` for any callbacks connected to this stream.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The `Model` or `BasePart` to tag. |
| `IsAtomic` | `boolean?` | (Optional), server-only. When `true`, sets the entity's `ModelStreamingMode` to `Atomic` before tagging, ensuring its entire hierarchy streams as a unit. Only valid for `Model` instances. |

**Returns:** `void`

!!! warning "Server-Only: IsAtomic"
    The `IsAtomic` parameter is only honoured when called from the **server**. Passing `true` on the client prints a warning and the streaming mode is left unchanged. Additionally, `IsAtomic` only applies to `Model` instances — passing `true` for a `BasePart` prints a warning and has no other effect.

!!! note "Studio Only"
    `Entity` must be a `PVInstance` and `IsAtomic`, if provided, must be a `boolean`, or errors are thrown.

---

#### AddTagDeferred

```luau
StampStream:AddTagDeferred(ParentFolder: Instance, EntityName: string, IsRecursive: boolean?, TimeoutSeconds: number?): ()
```

Polls `ParentFolder` every 0.5 seconds until a child named `EntityName` appears, then tags it. Designed to handle Roblox `StreamingEnabled` on the client, where an instance may not exist locally at the moment your script runs. The polling stops as soon as the instance is found and tagged, if `ParentFolder` is removed from the game hierarchy, or when the timeout elapses.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ParentFolder` | `Instance` | The container to search within. |
| `EntityName` | `string` | The exact name of the instance to wait for. |
| `IsRecursive` | `boolean?` | (Optional) When `true`, the search descends into all descendants of `ParentFolder`. Defaults to `false`. |
| `TimeoutSeconds` | `number?` | (Optional) The maximum number of seconds to keep polling before giving up. Defaults to `60`. |

**Returns:** `void`

!!! warning "Client-Only Context"
    This method must only be called from a `LocalScript` or `ModuleScript` running on the client. Calling it from the server prints a warning and returns immediately without scheduling any work.

!!! note "Studio Only"
    All parameters are type-validated. `TimeoutSeconds`, if provided, must be a positive number, or an error is thrown.

---

#### RemoveTag

```luau
StampStream:RemoveTag(Entity: PVInstance): ()
```

Removes this stream's tag from the given entity. Then fires `Signals.Untagged` immediately after removal.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance to untag. |

**Returns:** `void`

!!! note "Studio Only"
    `Entity` must be a `PVInstance` or an error is thrown.

---

#### RemoveAllTags

```luau
StampStream:RemoveAllTags(): ()
```

Removes this stream's tag from every instance in the game that currently carries it. Each removal fires `Signals.Untagged` immediately.

**Parameters:** `void`

**Returns:** `void`

---

#### GetAll

```luau
StampStream:GetAll(): {PVInstance}
```

Returns an array containing every instance currently tracked by this stream.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `{PVInstance}` | All instances the stream is currently tracking. Returns an empty table if none are tracked. |

---

#### GetCount

```luau
StampStream:GetCount(): number
```

Returns the number of instances currently tracked by this stream.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `number` | The current tracked instance count. |

---

#### SetAttribute

```luau
StampStream:SetAttribute(Entity: PVInstance, Key: string, Value: any): ()
```

Sets a named attribute on the given entity and registers the entity–key–value relationship in Stamp's query cache. Passing `nil` as the value removes the attribute from both the instance and the query cache.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance to set the attribute on. |
| `Key` | `string` | The attribute name. Maximum 100 characters. |
| `Value` | `any` | The value to assign. Pass `nil` to remove the attribute and clear it from the query cache. |

**Returns:** `void`

!!! warning "Supported Attribute Types"
    `Value` must be one of the types Roblox permits on instances: `string`, `number`, `boolean`, `UDim`, `UDim2`, `BrickColor`, `Color3`, `Vector2`, `Vector3`, `NumberRange`, `NumberSequence`, `ColorSequence`, `Rect`, or `Font`. In Studio, passing any other type throws an error.

!!! note "Studio Only"
    `Entity` must be a `PVInstance`; `Key` must be a non-empty string of no more than 100 characters. Calling `SetAttribute` on an instance that has no parent produces a warning.

!!! tip "Automatic Cache Cleanup"
    When you first set an attribute on an entity, Stamp silently registers a cleanup handler so that if the entity is ever destroyed, all of its cached attribute entries are removed automatically. You never need to call `SetAttribute(entity, key, nil)` for cleanup when an entity is being destroyed.

---

#### SetAttributeAll

```luau
StampStream:SetAttributeAll(Key: string, Value: any): ()
```

Sets the named attribute to the given value on every instance currently tracked by this stream.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Key` | `string` | The attribute name. |
| `Value` | `any` | The value to assign to all tracked instances. Pass `nil` to remove the attribute from all of them. |

**Returns:** `void`

!!! warning "Supported Attribute Types"
    The same type constraints as `SetAttribute` apply. In Studio, passing an unsupported type throws an error.

!!! note "Studio Only"
    `Key` must be a non-empty string of no more than 100 characters, or an error is thrown.

---

#### GetAttribute

```luau
StampStream:GetAttribute(Entity: PVInstance, Key: string): any
```

Returns the current value of the named attribute on the given entity. If no cached value exists, the live value is read directly from the instance as a fallback.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance to read the attribute from. |
| `Key` | `string` | The attribute name. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `any` | The current attribute value, or `nil` if the attribute does not exist on this entity. |

!!! note "Studio Only"
    `Entity` must be a `PVInstance` and `Key` must be a non-empty string of no more than 100 characters, or errors are thrown.

---

#### GetInstancesWithAttribute (Local)

```luau
StampStream:GetInstancesWithAttribute(Key: string, ExpectedValue: any?): {PVInstance}
```

Searches within this stream for instances that possess the named attribute. Only instances currently tracked by this stream are considered; instances from other streams that carry the same attribute are excluded. Only instances with a live parent are included.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Key` | `string` | The attribute name to search for. |
| `ExpectedValue` | `any?` | (Optional) When provided, only instances whose cached attribute value exactly matches this are returned. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `{PVInstance}` | An array of matching instances from this stream. Returns an empty table if nothing matches or the stream is empty. |

!!! note "Studio Only"
    `Key` must be a non-empty string of no more than 100 characters. If `ExpectedValue` is provided, its type must be a supported attribute type, or an error is thrown.

---

#### ObserveAttribute

```luau
StampStream:ObserveAttribute(Entity: PVInstance, Key: string, Callback: (Value: any) -> (), ScopeToBind: ReaperScope?): RBXScriptConnection
```

Subscribes to changes on the named attribute. The callback fires on the next available frame with the attribute's current value (if one exists and the entity is alive), then fires again each time the attribute changes in the future. Both the initial delivery and future deliveries only occur while the entity has a live parent.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance holding the attribute to observe. |
| `Key` | `string` | The attribute name to observe. |
| `Callback` | `(Value: any) -> ()` | The function to call immediately with the current value, and again on every future change. |
| `ScopeToBind` | `ReaperScope?` | (Optional) A custom scope to bind the connection to. When omitted, the scope is chosen automatically using the waterfall described below. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `RBXScriptConnection` | The raw event connection. |

!!! info "Scope Binding Waterfall"
    The returned connection's lifetime is determined as follows, in priority order:
    
    1. **Custom scope provided** — the connection is bound to `ScopeToBind` and is disconnected when that scope is destroyed.
    2. **Entity is tracked by this stream** — the connection is bound to the entity's tag scope and is disconnected automatically when the entity loses its tag or is destroyed.
    3. **Entity has a parent but is not in this stream** — the connection is bound to the entity's object lifetime and is disconnected when the entity is destroyed.
    4. **Entity has no parent** — the connection is disconnected immediately, before returning.

!!! warning "Asynchronous Initial Callback"
    The initial callback does not fire synchronously inline. It is scheduled to run on the next available frame. Do not write code that depends on the initial callback having already executed by the time `ObserveAttribute` returns.

!!! warning "RBXScriptConnection Handling"
    The raw event connection is returned for the purpose if ever you need logic that terminates the connection early. If not necessarily needed, do not store the returned `RBXScriptConnection` object, let Stamp handle the cleanup cycle.

!!! note "Studio Only"
    `Entity` must be a `PVInstance`; `Key` must be a non-empty string of no more than 100 characters; `Callback` must be a function. Violations throw errors.

---

#### Destroy (Local)

```luau
StampStream:Destroy(): ()
```

Initiate a cleanup event for this stream, destroying everything this stream associated with.

**Parameters:** `void`

**Returns:** `void`

---

### Event Details

!!! tip "Design Philosophy: Automated Memory Management"
    Stamp signals intentionally expose only `:Connect()` and return `void` from it — no connection object is given back. Methods like `:Wait()` and `:Once()` are not available. This is by design: because every tagged entity's lifetime is managed by a scope, the system disconnects all listeners the moment a tag is removed or an entity is destroyed. You never call `:Disconnect()` on a Stamp signal connection — the scope handles it.

---

#### Signals.Tagged

```luau
StampStream.Signals.Tagged:Connect(Callback: (Entity: PVInstance, Scope: ReaperScope) -> ())
```

Fires each time an instance receives this stream's tag.

**Available Methods:**

- `:Connect(Callback)` — Binds a function to run whenever an entity receives this tag.

**Callback Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance that was tagged. |
| `Scope` | `ReaperScope` | A garbage-collection scope unique to this entity's current tag lifecycle. Bind all events, loops, and tasks to this scope to guarantee they are cleaned up when the tag is removed. |

**Returns:** `void`

!!! info "Retroactive Subscription"
    Connecting to `Signals.Tagged` after instances are already tagged does not miss them. Upon connection, the callback is immediately scheduled for every instance the stream is already tracking (provided each instance still has a live parent). This means your setup logic runs for both past and future entities with a single `Connect` call.

!!! note "Studio Only"
    `Callback` must be a function or an error is thrown.

---

#### Signals.Untagged

```luau
StampStream.Signals.Untagged:Connect(Callback: (Entity: PVInstance) -> ())
```

Fires each time an instance loses this stream's tag, whether by an explicit `RemoveTag` call, by `RemoveAllTags`, or because the instance was destroyed.

**Available Methods:**

- `:Connect(Callback)` — Binds a function to run whenever an entity loses this tag.

**Callback Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance that lost the tag. |

**Returns:** `void`

!!! note "Studio Only"
    `Callback` must be a function or an error is thrown.