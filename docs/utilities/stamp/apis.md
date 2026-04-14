# Stamp

The **Stamp** library is an advanced, memory-safe wrapper for Roblox's `CollectionService` and Attribute system. Designed as a core utility within the Lazy Games Suite, Stamp transforms standard tags into observable, memory-managed **Streams**. 

By automatically binding the lifecycle of a tagged instance to a **Reaper Scope**, Stamp eliminates the memory leaks and dangling connections commonly associated with custom component systems.

---

## Class: Stamp
The global module used to inject dependencies, register new tags, and perform global queries.

### Functions Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Inject](#inject)** `(ModuleName: string, ModuleTableObject: any)` | `void` | Injects required Lazy Games Suite dependencies (`Reaper`, `Assignment`, `Relay`). |
| **[Register](#register)** `(TagName: string)` | `StampStream` | Registers a new tag and returns its associated `StampStream`. |
| **[GetInstancesWithAttribute_](#getinstanceswithattribute_)** `(Key: string, ExpectedValue: any?)` | `{PVInstance}` | Globally returns all tagged instances possessing the specified attribute. |
| **[Destroy](#destroy)** `(TagName: string)` | `void` | Globally destroys a registered `StampStream` and cleans up its tracking. |
| **[CompactString](#compactstring)** `(InputString: string)` | `string` | Removes all whitespace, tabs, and newlines from a string. |

---

### Function Details

#### Inject
```luau
Stamp.Inject(ModuleName: string, ModuleTableObject: any): ()
```
Injects an external library within the Lazy Games Suite of Tools environment. **Must** be called for `Reaper`, `Assignment`, and `Relay` before `Register` can be used.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ModuleName` | `string` | The exact name of the ModuleScript ("Reaper", "Assignment", or "Relay"). |
| `ModuleTableObject` | `any` | The required module table/object to inject. |

**Returns:** `void`

---

#### Register
```luau
Stamp.Register(TagName: string): StampStream
```
Registers a new `StampStream` for the given `CollectionService` tag name. If a stream for this tag already exists, it returns the active stream.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `TagName` | `string` | The CollectionService tag to track. Triggers a warning if length exceeds 100 characters. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `StampStream` | The instantiated stream object controlling this tag. |

---

#### GetInstancesWithAttribute_
```luau
Stamp.GetInstancesWithAttribute(Key: string, ExpectedValue: any?): {PVInstance}
```
Queries globally across **all** registered stamps for instances that possess the given attribute key.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Key` | `string` | The attribute key to search for. |
| `ExpectedValue` | `any?` | *(Optional)* If provided, limits the returned instances to those matching this exact value. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `{PVInstance}` | An array of PVInstances matching the criteria. |

---

#### Destroy
```luau
Stamp.Destroy(TagName: string): ()
```
Destroys a registered `StampStream` by name, internally calling `RemoveAllTags()` and cleaning up all active Reaper scopes and Relays.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `TagName` | `string` | The name of the tag stream to destroy. |

**Returns:** `void`

---

#### CompactString
```luau
Stamp.Utility.CompactString(InputString: string): string
```
Takes an input string and removes all whitespace (spaces, tabs, newlines).

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `InputString` | `string` | The string to compact. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `string` | The compacted string. |

---

## Class: StampStream
An object representing a single, tracked `CollectionService` tag, returned by `Stamp.Register()`.

### Methods Summary

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[AddTag](#addtag)** `(Entity: PVInstance, IsAtomic: boolean?)` | `void` | Tags an entity and starts tracking its lifecycle. |
| **[AddTagDeferred](#addtagdeferred)** `(...)` | `void` | *(Client-Only)* Polls for an instance before tagging it. |
| **[RemoveTag](#removetag)** `(Entity: PVInstance)` | `void` | Removes the tag and destroys the entity's associated ReaperScope. |
| **[RemoveAllTags](#removealltags)** `()` | `void` | Iterates and removes the tag from all currently tracked instances. |
| **[GetAll](#getall)** `()` | `{PVInstance}` | Returns an array of all currently tracked instances. |
| **[GetCount](#getcount)** `()` | `number` | Returns the total integer count of currently tracked instances. |
| **[SetAttribute](#setattribute)** `(Entity: PVInstance, Key: string, Value: any)` | `void` | Sets a tracked attribute on a specific entity. |
| **[SetAttributeAll](#setattributeall)** `(Key: string, Value: any)` | `void` | Sets a tracked attribute across all currently tagged entities. |
| **[GetAttribute](#getattribute)** `(Entity: PVInstance, Key: string)` | `any` | Returns the value of an attribute on a specific entity. |
| **[GetInstancesWithAttribute__](#getinstanceswithattribute__)** `(Key: string, ExpectedValue: any?)` | `{PVInstance}` | Returns tracked instances within this stream possessing a specific attribute. |
| **[ObserveAttribute](#observeattribute)** `(Entity: PVInstance, Key: string, Callback: function, ScopeToBind: any?)` | `RBXScriptConnection` | Listens for attribute changes and cleans up automatically. |

### Events Summary

| Name | Description |
| :--- | :--- |
| **[Signals.Tagged](#signalstagged)** | Fired when an instance receives this tag. Provides the Instance and its `ReaperScope`. |
| **[Signals.Untagged](#signalsuntagged)** | Fired when an instance loses this tag. |

---

### Method Details

#### AddTag
```luau
StampStream:AddTag(Entity: PVInstance, IsAtomic: boolean?): ()
```
Applies the stream's tag to the specified entity.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The Model or BasePart to tag. |
| `IsAtomic` | `boolean?` | *(Optional)* If true, dynamically sets the entity's `ModelStreamingMode` to `Atomic` (Models only). |

---

#### AddTagDeferred
```luau
StampStream:AddTagDeferred(ParentFolder: Instance, EntityName: string, IsRecursive: boolean?, TimeoutSeconds: number?): ()
```
!!! Warning "Client-Only Context"
    This method is restricted to the Client. Calling it on the Server will yield a warning and terminate.

Safely handles Roblox `StreamingEnabled` by polling `ParentFolder` for `EntityName` at 0.5s intervals. Applies the tag once the instance streams in.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ParentFolder` | `Instance` | The folder or container to search within. |
| `EntityName` | `string` | The exact name of the entity to wait for. |
| `IsRecursive` | `boolean?` | *(Optional)* Uses `FindFirstChild(EntityName, true)` if true. Default `false`. |
| `TimeoutSeconds` | `number?` | *(Optional)* Time before giving up. Default is `60` seconds. |

---

#### RemoveTag
```luau
StampStream:RemoveTag(Entity: PVInstance): ()
```
Removes the tag from the entity. This triggers the `Untagged` event and **immediately cleans the associated ReaperScope**, disconnecting all internal events.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance to untag. |

---

#### RemoveAllTags
```luau
StampStream:RemoveAllTags(): ()
```
Iterates through all currently tracked instances in this stream and removes the tag from each one. Triggers `Untagged` and cleans scopes for all.

---

#### GetAll
```luau
StampStream:GetAll(): {PVInstance}
```
Returns an array of all instances currently tracked by this stream.

**Returns:**

| Type | Description |
| :--- | :--- |
| `{PVInstance}` | An array of currently tracked instances. |

---

#### GetCount
```luau
StampStream:GetCount(): number
```
Returns the total number of instances currently tracked by this stream.

**Returns:**

| Type | Description |
| :--- | :--- |
| `number` | The active instance count. |

---

#### SetAttribute
```luau
StampStream:SetAttribute(Entity: PVInstance, Key: string, Value: any): ()
```
Sets an attribute on a specific entity and tracks its relationship internally. Passing `nil` for the value will remove the attribute and clear the cache.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The target instance. |
| `Key` | `string` | The attribute name. |
| `Value` | `any` | The value to apply (or `nil` to clear). |

---

#### SetAttributeAll
```luau
StampStream:SetAttributeAll(Key: string, Value: any): ()
```
Applies the specified attribute and value to every instance currently tracked by this stream.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Key` | `string` | The attribute name. |
| `Value` | `any` | The value to apply (or `nil` to clear). |

---

#### GetAttribute
```luau
StampStream:GetAttribute(Entity: PVInstance, Key: string): any
```
Retrieves the current value of an attribute on a specific entity.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The target instance. |
| `Key` | `string` | The attribute name. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `any` | The current attribute value. |

---

#### GetInstancesWithAttribute__
```luau
StampStream:GetInstancesWithAttribute(Key: string, ExpectedValue: any?): {PVInstance}
```
Returns tracked instances within this stream possessing a specific attribute.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Key` | `string` | The attribute key to search for. |
| `ExpectedValue` | `any?` | *(Optional)* If provided, limits the returned instances to those matching this exact value. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `{PVInstance}` | An array of PVInstances matching the criteria. |

---

#### ObserveAttribute
```luau
StampStream:ObserveAttribute(Entity: PVInstance, Key: string, Callback: function, ScopeToBind: any?): RBXScriptConnection
```
Fires the callback immediately with the current attribute value, and then listens for future changes. The resulting connection is automatically bound to the entity's internal `ReaperScope` (or a custom provided scope) to prevent memory leaks.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance holding the attribute. |
| `Key` | `string` | The string name of the attribute. |
| `Callback` | `(Value: any) -> ()` | The function to execute on change. |
| `ScopeToBind` | `ReaperScope?` | *(Optional)* If omitted, defaults to the Entity's automated tag scope. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `RBXScriptConnection` | The raw event connection. |

---

#### Destroy
```luau
StampStream:Destroy(): ()
```
Destroys this specific stream instance. It automatically calls RemoveAllTags(), disconnects internal CollectionService listeners, destroys the associated Relays, and unregisters the stream from the global cache.

**Returns:** `void`

---

### Event Details

!!! tip "Design Philosophy: Automated Memory Management"
    Unlike standard Roblox events, Stamp signals **only** expose the `:Connect()` method and intentionally **do not return a connection object** (they return `void`). Furthermore, methods like `:Wait()` or `:Once()` are entirely disabled.
    
    This is a core pillar of the Lazy Games Suite. Stamp enforces **automated garbage collection**. Because every tagged entity is inextricably linked to a `ReaperScope`, the system automatically disconnects all internal events, loops, and threads the exact moment an entity loses its tag or is destroyed. You never have to manually track or call `:Disconnect()`, completely eliminating a massive source of memory leaks.

#### Signals.Tagged

**Available Methods:**
* `:Connect(Callback)` - Binds a function to run whenever an entity receives this tag.

```luau
StampStream.Signals.Tagged:Connect(Callback: (Entity: PVInstance, Scope: ReaperScope) -> ())
```
Fires immediately when an instance is tagged (or if it was already tagged prior to calling `Register()`).

**Callback Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance that was tagged. |
| `Scope` | `ReaperScope` | A unique garbage-collection scope bound to this entity's tag lifecycle. |

---

#### Signals.Untagged

**Available Methods:**
* `:Connect(Callback)` - Binds a function to run whenever an entity loses this tag.

```luau
StampStream.Signals.Untagged:Connect(Callback: (Entity: PVInstance) -> ())
```
Fires when an instance loses the tag, or when the instance is destroyed.

**Callback Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Entity` | `PVInstance` | The instance that lost the tag. |