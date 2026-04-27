# API Reference

ByteWave exposes a **Server** entry point (used in server scripts) and a **Client** entry point (used in LocalScripts). Both share the same Gateway/Path model. Each entry point also exposes two sub-modules: `ByteWave.State` and `ByteWave.Action`.

---

## Exported Types

### Server-Side Types

#### `ByteWavePacket`
Passed to middleware functions. Represents a fully-decoded inbound packet before any listeners receive it.

| Field | Type | Description |
|:---|:---|:---|
| `Player` | `Player` | The player who sent the packet. |
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Path` | `string` | The path within the gateway. |
| `Value` | `any` | The payload to be broadcasted. |

#### `InboundPacket`
Passed to gateway listeners on the server. Identical to `ByteWavePacket` but without the `Gateway` field (the gateway is already known by the listener that registered for it).

| Field | Type | Description |
|:---|:---|:---|
| `Player` | `Player` | The player who sent the packet. |
| `Path` | `string` | The path within the gateway. |
| `Value` | `any` | The payload to be broadcasted. |

#### `SendConfig` *(server)*
Options dictionary for `ByteWave.Send` on the server.

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `____TargetPlayer` | `Player?` | `nil` | Send to one player. `nil` broadcasts to all. |
| `____IsReliable` | `boolean?` | `true` | Channel to use. `True` for reliable, `False` for unreliable. |
| `____InternString` | `boolean?` | `false` | Compresses both Gateway and Path into 2 bytes integer representation. |

#### `SpatialConfig`
Options dictionary for `ByteWave.SpatialSend`. `____Radius` is required.

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `____Radius` | `number` | *(required)* | Discovery radius in studs. |
| `____Use3D` | `boolean?` | `false` | Proximity model to use. `True` for sphere, `False` for cylinder. |
| `____IsReliable` | `boolean?` | `false` | Channel to use. `True` for reliable, `False` for unreliable. |
| `____InternString` | `boolean?` | `false` | Compresses both Gateway and Path into 2 bytes integer representation. |

#### `ListenConfig` *(server)*
Options dictionary for `ByteWave.Listen` on the server.

| Field | Type | Description |
|:---|:---|:---|
| `____BindTo` | `Instance?` | When this Instance is destroyed, the listener is automatically removed. |

#### `DisconnectObject`
Returned by `Listen`. Call `Disconnect()` to unregister the callback.

| Field | Type |
|:---|:---|
| `Disconnect` | `() -> ()` |

---

### Client-Side Types

#### `Packet`
Passed to gateway listeners on the client.

| Field | Type | Description |
|:---|:---|:---|
| `Path` | `string` | The path within the gateway. |
| `Value` | `any` | The payload to be broadcasted. |

#### `SendConfig` *(client)*
Options dictionary for `ByteWave.Send` on the client.

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `____IsReliable` | `boolean?` | `true` | Channel to use. `True` for reliable, `False` for unreliable. |

#### `ListenConfig` *(client)*
Options dictionary for `ByteWave.Listen` on the client.

| Field | Type | Description |
|:---|:---|:---|
| `____BindTo` | `Instance?` | When this Instance is destroyed, the listener is automatically removed. |

#### `RequestConfig`
Options dictionary for `ByteWave.Request`.

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `____Timeout` | `number?` | `5` | Seconds to wait before the request is considered timed out. Must be positive number. |

---

### State Types

#### `StateScope`
```luau
type StateScope = "Global" | "Private" | "Filtered" | "Spatial_Global" | "Spatial_Private" | "Spatial_Filtered"
```
Determines which clients receive and observe a StateObject.

| Value | Who receives it |
|:---|:---|
| `"Global"` | All connected clients. |
| `"Private"` | One named owner player. |
| `"Filtered"` | An explicit allow-list of players. |
| `"Spatial_Global"` | All players within the anchor's radius. |
| `"Spatial_Private"` | Only the owner player, and only when in range. |
| `"Spatial_Filtered"` | Only allow-listed players, and only when in range. |

#### `StateObject` *(server)*
See the **State Server — StateObject Methods** section below.

#### `StateObject` *(client)*
See the **State Client — StateObject Methods** section below.

#### `GetStateConfig` *(client)*
Options dictionary for `ByteWave.State.GetState` on the client.

| Field | Type | Default | Description |
|:---|:---|:---|:---|
| `____Timeout` | `number?` | `5` | Seconds to wait before returning `nil`. Must be positive number. |

---

## ByteWave Server

**Module:** `ByteWave_Server`  
Require this on the server. All public APIs are described below.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Send](#send-server)** | `void` | Queues a packet for delivery to one player or all players. |
| **[Listen](#listen-server)** | `DisconnectObject` | Registers a callback to receive all packets arriving on a named gateway. |
| **[SpatialSend](#spatialsend)** | `void` | Queues a packet for delivery to all players within a radius of an anchor point. |
| **[SetGatewayWhitelist](#setgatewaywhitelist)** | `void` | Restricts a gateway to a specific list of UserIds. |
| **[SetRequestHandler](#setrequesthandler)** | `void` | Registers a server-side handler for client RPC requests on a named gateway. |
| **[AttachMiddleware](#attachmiddleware)** | `void` | Attaches a custom function that intercepts every inbound packet before listeners receive it. |
| **[PlayerAdded](#playeradded)** | `void` | Registers a callback that fires when a player completes the connection handshake. |
| **[Inject](#inject-server)** | `void` | Injects an external library from the Lazy Games Suite of Tools into the ByteWave suite. |

---

<a id="send-server"></a>
#### `Send` *(server)*
Queues a packet to be sent to a specific player or broadcast to all players on the next Heartbeat flush.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Path` | `string` | The path within the gateway. |
| `Value` | `any` | The payload to be broadcasted. |
| `Options` | `SendConfig?` | (Optional) Controls target player, reliability, and string interning. |

**Returns:** `void`

!!! note "Remote Communication"
    The packet is not sent immediately. It is accumulated in an outbound buffer and dispatched at the end of the current frame.

!!! tip "String interning for named paths"
    Pass `____InternString = true` when sending on a named gateway and path that are repeated across many frames. The name is registered once and reduced to two bytes for all subsequent sends.

---

<a id="listen-server"></a>
#### `Listen` *(server)*
Registers a callback to receive all packets arriving on the named gateway from any client.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Callback` | `(InboundPacket) -> ()` | Called for each arriving packet. |
| `Options` | `ListenConfig?` | (Optional) Provide `____BindTo` to auto-disconnect when an Instance is destroyed. |

**Returns:** `DisconnectObject`

!!! warning "Side Effect"
    Registering a listener on `"System"` is permitted but receives internal handshake and synchronization packets. These are not player data. The returned `DisconnectObject` for `"System"` is inert — the listener cannot be removed.

!!! tip "Lifetime management"
    Pass `{ ____BindTo = someInstance }` to have the listener removed automatically when `someInstance` is destroyed, with no manual `Disconnect()` call needed.

---

<a id="spatialsend"></a>
#### `SpatialSend`
Queues a packet for delivery to every player currently within the specified radius of an anchor point in the world.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Path` | `string` | The path within the gateway. |
| `Value` | `any` | The payload to be broadcasted. |
| `Anchor` | `BasePart | Model | Attachment` | The world position to measure distance. |
| `Options` | `SpatialConfig` | Required. Must include `____Radius`. |

**Returns:** `void`

!!! warning "Options is required"
    Unlike `Send`, the `Options` argument is not optional. Calling `SpatialSend` without an `Options` table containing `____Radius` raises an error in Studio.

!!! info "Cylinder vs Sphere"
    By default, distance is measured on the horizontal plane (XZ), allowing ±50 studs of vertical tolerance. Set `____Use3D = true` for a true three-dimensional sphere where vertical distance counts fully.

!!! tip "Unreliable is the default"
    `SpatialSend` defaults to unreliable delivery (`____IsReliable = false`). If the spatial data is critical (an initial snapshot rather than a repeating update), pass `____IsReliable = true`.

---

<a id="setgatewaywhitelist"></a>
#### `SetGatewayWhitelist`
Restricts access to a gateway so that only clients whose UserId appears in the list can send packets through it. Packets from any other player are silently dropped.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `AllowedUserIds` | `{ number }` | Array of UserIds permitted to send on this gateway. |

**Returns:** `void`

!!! warning "Side Effect"
    Calling this replaces any existing whitelist for the gateway entirely. There is no additive mode.

---

<a id="setrequesthandler"></a>
#### `SetRequestHandler`
Registers a handler function that is called when a client sends a request to the named gateway via `ByteWave.Request`. The return value of the handler is sent back to the client.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Callback` | `(Player, any) -> any` | Called with the requesting player and their query data. The return value is delivered to the client. |

**Returns:** `void`

!!! warning "Side Effect"
    Only one handler can be registered per gateway. Registering a second one replaces the first and logs a warning in Studio.

!!! note "Remote Communication"
    The handler's return value is routed back through the reliable channel automatically. The client's coroutine resumes when the response arrives.

---

<a id="attachmiddleware"></a>
#### `AttachMiddleware`
Attaches a function that is called for every inbound packet, before any gateway listeners receive it. Return `false` to drop the packet silently.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Callback` | `(ByteWavePacket) -> boolean` | Intercepts every inbound packet. Return `false` to drop it. |

**Returns:** `void`

!!! info "Order of evaluation"
    Middleware functions run in the order they were attached. ByteWave's built-in anti-spam protection is always the first middleware in the pipeline.

!!! warning "System packets are exempt"
    Packets on the `"System"` gateway (handshake, time sync, RPC responses) bypass all middleware, including the built-in anti-spam layer.

---

<a id="playeradded"></a>
#### `PlayerAdded`
Registers a callback that fires once for each player after they have completed ByteWave's connection handshake. This is the correct event to use instead of `Players.PlayerAdded` when you need to know that ByteWave is ready to send data to that player.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Callback` | `(Player) -> ()` | Called once per player on handshake completion. |

**Returns:** `void`

!!! warning "Not equivalent to Players.PlayerAdded"
    A player registered through `Players.PlayerAdded` has joined the server but has not yet completed ByteWave's handshake. Calling `Send` targeting that player before `PlayerAdded` fires may result in packets being queued before the client's string registry is synchronized.

---

<a id="inject-server"></a>
#### `Inject` *(server)*
Injects an external library/framework within the Lazy Games Suite of Tools environment. Currently supports the **Assignment** and **Twin** library.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `moduleName` | `string` | The name of the ModuleScript file. |
| `moduleTableObject` | `any` | The module table to inject. |

**Returns:** `void`

!!! danger "Strict Dependency: Assignment and Twin"
    `"Assignment"` must be injected before the first Heartbeat fires, otherwise it will not take effect. Inject it at the top of the server script before any game logic runs. `"Twin"` on the other hand do not require strict injection point but please be aware that if you inject `Twin` in mid-operation, data loss is possible during the transition window from native worker pool to delegating the parallel work to Twin. It still best to inject both `Assignment` and `Twin` during ByteWave initialization phase.


---

## ByteWave Client

**Module:** `ByteWave_Client`  
Require this in LocalScripts. The module yields until the connection handshake completes before returning.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Send](#send-client)** | `void` | Queues a packet to be sent to the server. |
| **[Listen](#listen-client)** | `DisconnectObject` | Registers a callback to receive all packets arriving on a named gateway from the server. |
| **[Request](#request)** | `boolean, any` | Sends a request to the server and yields until a response arrives or the timeout elapses. |
| **[GetServerTime](#getservertime)** | `number` | Returns the current server clock, estimated using round-trip time sampling. |
| **[Inject](#inject-client)** | `void` | Injects an external library into the ByteWave suite on the client. |

---

<a id="send-client"></a>
#### `Send` *(client)*
Queues a packet to be sent to the server on the next Heartbeat flush.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Path` | `string` | The path within the gateway. |
| `Value` | `any` | The payload to be broadcasted. |
| `Options` | `SendConfig?` | (Optional) Control channel via `____IsReliable`. |

**Returns:** `void`

---

<a id="listen-client"></a>
#### `Listen` *(client)*
Registers a callback to receive all packets arriving from the server on the named gateway.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Callback` | `(Packet) -> ()` | Called for each incoming packet. Runs deferred. |
| `Options` | `ListenConfig?` | (Optional) Provide `____BindTo` to auto-disconnect on Instance destruction. |

**Returns:** `DisconnectObject`

---

<a id="request"></a>
#### `Request`
Sends a request to the server and yields the calling coroutine until the server responds or the timeout elapses.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Gateway` | `string` | The gateway the packet arrived on. |
| `Data` | `any?` | (Optional) Payload passed to the server handler. |
| `Options` | `RequestConfig?` | (Optional) Set `____Timeout` to control how long to wait. |

**Returns:** `boolean, any`

- First return: `true` if the server responded successfully, `false` on error or timeout.
- Second return: the server handler's return value on success, an error string on failure, or `"Timeout"` if the wait expired.

!!! warning "Yields"
    This method suspends the calling coroutine until a response arrives. Do not call it on the main script thread in a context where yielding would stall other logic. Call it inside a `task.spawn`, `Assignment.Spawn` (if using Assignment library) or a dedicated coroutine.

!!! tip "Default timeout"
    If `____Timeout` is omitted the request waits up to 5 seconds. For operations that may take longer (e.g. DataStore-backed queries), increase the timeout explicitly.

---

<a id="getservertime"></a>
#### `GetServerTime`
Returns an estimate of the current server clock, adjusted for network latency using an exponential moving average of recent round-trip times.

**Parameters:** `void`

**Returns:** `number` — estimated server time in seconds.

!!! info "Accuracy note"
    The estimate improves over time as more round-trip samples accumulate. During the first few seconds after joining the value may be slightly imprecise.

---

<a id="inject-client"></a>
#### `Inject` *(client)*
Injects an external library within the Lazy Games Suite of Tools environment. Currently supports the **Assignment** library.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `moduleName` | `string` | The name of the ModuleScript file. |
| `moduleTableObject` | `any` | The module table to inject. |

**Returns:** `void`

!!! danger "Strict Dependency: Assignment"
    Just like the server version, `"Assignment"` must be injected before the first Heartbeat fires, otherwise it will not take effect. Inject it at the ByteWave initialization phase before any game logic runs.

---

## ByteWave State — Server (`ByteWave.State`)

**Accessed via:** `ByteWave.State` on the server.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[CreateState](#createstate)** | `StateObject` | Creates and registers a new replicated state object. |
| **[GetState](#getstate-server)** | `StateObject?` | Returns the StateObject for a given ID, or nil if it does not exist. |
| **[GetActiveStates](#getactivestates)** | `{ [string]: StateObject }` | Returns the full dictionary of all currently registered states. |
| **[SetSpatialRoot](#setspatialroot)** | `void` | Overrides the workspace root used for spatial overlap queries. |

---

<a id="createstate"></a>
#### `CreateState`
Creates, registers, and optionally immediately replicates a new StateObject with the given data and scope.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `UniqueID` | `string` | A unique string identifier for this state. Must be non-empty and not already in use. |
| `InitialData` | `{ [string | number]: any }` | The initial data table. Immediately replicated to eligible clients. |
| `Scope` | `StateScope?` | Controls which clients receive this state. Defaults to `"Spatial_Global"`. |
| `OwnerOrFilter` | `(Player | { Player })?` | A single Player (for Private scopes) or an array of Players (for Filtered scopes). |
| `Anchor` | `BasePart | Model?` | Required for Spatial scopes. The world object whose position determines discovery. |
| `Radius` | `number?` | Discovery radius in studs for Spatial scopes. Defaults to `150`. |
| `HierarchyInfo` | `{ Parent: StateObject? }?` | Links this state as a child of another. Children inherit their parent's scope and owner/filter when not specified. |

**Returns:** `StateObject`

!!! danger "Throws"
    Raises an error if `UniqueID` is empty or already registered. Raises an error if a Spatial scope is specified with an `Anchor` that is not a `BasePart` or `Model`.

!!! warning "Spatial without Anchor"
    Creating a Spatial-scoped state without an `Anchor` logs a warning in Studio. The state will never be discovered by any client.

---

<a id="getstate-server"></a>
#### `GetState` *(server)*
Returns the StateObject registered under the given ID.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `UniqueID` | `string` | The identifier of the state to retrieve. |

**Returns:** `StateObject?` — the state handle, or `nil` if no state with that ID exists.

---

<a id="getactivestates"></a>
#### `GetActiveStates`
Returns the complete dictionary of all currently registered states, keyed by their UniqueID.

**Parameters:** `void`

**Returns:** `{ [string]: StateObject }`

!!! warning "Side Effect"
    The returned table is a direct reference to the live registry. Do not modify it.

---

<a id="setspatialroot"></a>
#### `SetSpatialRoot`
Overrides the workspace scope used for all spatial overlap queries. By default queries search the entire workspace. After calling this, queries are restricted to descendants of the specified folder.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `folder` | `Instance` | The root Instance to scope all spatial queries within. |

**Returns:** `void`

!!! warning "Must be called before creating Spatial states"
    This setting is applied once at startup. Calling it after Spatial states have already been created will not retroactively narrow their search scope.

---

<a id="stateobject-server"></a>
### StateObject Methods (Server)
All methods below are called on a StateObject handle returned by `CreateState` or `GetState`.

#### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Set](#set)** | `void` | Sets a key to a new value and queues the change for replication. |
| **[Get](#get-server)** | `any` | Returns the current value stored at a key. |
| **[AddFilter](#addfilter)** | `void` | Adds a player to a Filtered state's allow-list and sends an initial full-sync to that player. |
| **[RemoveFilter](#removefilter)** | `void` | Removes a player from a Filtered state's allow-list and sends a destroy signal to that player. |
| **[Append](#append)** | `void` | Adds a value after the highest existing numeric index. |
| **[Remove](#remove)** | `void` | Removes a value by key or index, with optional list-restructuring behaviour. |
| **[Swap](#swap)** | `void` | Exchanges the values at two keys. |
| **[Patch](#patch)** | `void` | Sets multiple keys to the same boolean value in one call. |
| **[Toggle](#toggle)** | `void` | Flips the boolean value at a key. |
| **[Increment](#increment)** | `void` | Adds a number to the value at a key. |
| **[Decrement](#decrement)** | `void` | Subtracts a number from the value at a key. |
| **[Multiply](#multiply)** | `void` | Multiplies the value at a key by an amount. |
| **[Divide](#divide)** | `void` | Divides the value at a key by an amount. |
| **[SetTemporary](#settemporary)** | `void` | Sets a key to a value for a fixed duration, then reverts or clears it. |
| **[Destroy](#destroy-server)** | `void` | Removes the state, cancels all timers, destroys all children, and notifies clients. |

---

<a id="set"></a>
#### `Set`
Sets a key to a new value. If the value differs from the current one, the change is marked for replication to all eligible clients. Supports slash-delimited paths for deep nested access (e.g. `"inventory/weapons/1"`).

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Key` | `string | number` | The path as a key to write specific target on the state's data tree. |
| `Value` | `any` | The new value. Pass `nil` to delete the key. |

**Returns:** `void`

!!! info "Numeric fast path"
    When `Key` is a plain string and `Value` is a number, the update is delivered through a compact binary channel in the same frame rather than waiting for the next dirty-queue flush 50ms later.

---

<a id="get-server"></a>
#### `Get` *(server)*
Returns the value stored at the given key. Supports slash-delimited deep paths.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Key` | `string` | The path as a key to fetch specific target on the state's data tree. |

**Returns:** `any`

---

<a id="addfilter"></a>
#### `AddFilter`
Adds a player to this state's allow-list. The player immediately receives a full snapshot of the state's current data. Has no effect on non-Filtered states.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `player` | `Player` | The player to add. |

**Returns:** `void`

!!! note "Remote Communication"
    Calling this on a `"Filtered"` state immediately sends a full-sync replication packet to the newly added player.

---

<a id="removefilter"></a>
#### `RemoveFilter`
Removes a player from this state's allow-list and sends a destroy signal to that player. Has no effect on non-Filtered states.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `player` | `Player` | The player to remove. |

**Returns:** `void`

!!! note "Remote Communication"
    The removed player receives a destroy instruction and their local copy of the state is cleaned up.


---

<a id="append"></a>
#### `Append`
Adds a value after the highest currently occupied numeric index in the state data.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Value` | `any` | The value to append. |

**Returns:** `void`

---

<a id="remove"></a>
#### `Remove`
Removes the value at the specified key or numeric index and replicates the deletion. When operating on a numeric index, the optional `EnableShifting` parameter controls how the list is restructured after the removal.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetLocation` | `string | number` | The key or numeric index to remove. |
| `EnableShifting` | `boolean?` | Controls list restructuring for numeric indices. See behaviour table below. |

**`EnableShifting` behaviour:**

| Value | Behaviour |
|:---|:---|
| `nil` *(default)* | Deletes the key directly. No reordering — may leave a gap in a numeric list. |
| `false` | Tail swap — the last element is moved into the vacated slot and the tail is cleared. O(1), but does not preserve order. |
| `true` | Sequential shift — every element above the removed index shifts down by one. Preserves order, O(n). |

**Returns:** `void`

!!! info "String keys always use simple deletion"
    When `TargetLocation` is a string, `EnableShifting` is ignored and the key is simply set to `nil`, regardless of the value passed.

---

<a id="swap"></a>
#### `Swap`
Exchanges the values stored at two keys within the state in a single replicated operation.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Key1` | `string | number` | The first key. |
| `Key2` | `string | number` | The second key. |

**Returns:** `void`

---

<a id="patch"></a>
#### `Patch`
Sets every key in the provided array to the same boolean value in a single call.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetKeys` | `{ string | number }` | Array of keys to update. |
| `Value` | `boolean` | The value to assign to each key. |

**Returns:** `void`

---

<a id="toggle"></a>
#### `Toggle`
Flips the boolean stored at the given key.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetKey` | `string | number` | The key whose boolean value to flip. |

**Returns:** `void`

---

<a id="increment"></a>
#### `Increment`
Adds `Amount` to the numeric value at `TargetKey`. If the key is empty it is treated as zero.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetKey` | `string | number` | The key to increment. |
| `Amount` | `number` | The amount to add. |

**Returns:** `void`

!!! danger "Throws"
    In Studio, raises an error if the existing value at `TargetKey` is not a number.

---

<a id="decrement"></a>
#### `Decrement`
Subtracts `Amount` from the numeric value at `TargetKey`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetKey` | `string | number` | The key to decrement. |
| `Amount` | `number` | The amount to subtract. |

**Returns:** `void`

---

<a id="multiply"></a>
#### `Multiply`
Multiplies the numeric value at `TargetKey` by `Amount`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetKey` | `string | number` | The key to multiply. |
| `Amount` | `number` | The multiplier. |

**Returns:** `void`

---

<a id="divide"></a>
#### `Divide`
Divides the numeric value at `TargetKey` by `Amount`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetKey` | `string | number` | The key to divide. |
| `Amount` | `number` | The divisor. Must not be zero. |

**Returns:** `void`

!!! danger "Throws"
    Raises an error in Studio if `Amount` is zero.

---

<a id="settemporary"></a>
#### `SetTemporary`
Sets a key to a value for `Duration` seconds. When the duration expires the value is either restored to what it was before the call, or deleted entirely.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `TargetKey` | `string | number` | The key to temporarily set. |
| `Value` | `any` | The temporary value. |
| `Duration` | `number` | How long in seconds before the effect expires. Must be positive. |
| `RevertOnExpiry` | `boolean?` | `true` (default) restores the previous value; `false` deletes the key. |

**Returns:** `void`

!!! info "Stacking SetTemporary calls"
    Calling `SetTemporary` on the same key while a previous call's timer is still running cancels the old timer before applying the new one. Only the most recent call's duration and behavior take effect.

---

<a id="destroy-server"></a>
#### `Destroy` *(server)*
Cancels all active timers on this state, destroys all child states in hierarchy order (deepest first), notifies all eligible clients to remove their local copy, and unregisters the state from the active registry.

**Parameters:** `void`

**Returns:** `void`

!!! warning "Irreversible"
    Once destroyed, a StateObject cannot be used again. Attempting to call methods on a destroyed state has undefined behavior.

---

## ByteWave State — Client (`ByteWave.State`)

**Accessed via:** `ByteWave.State` on the client.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[GetState](#getstate-client)** | `StateObject?` | Waits up to a timeout for a state to arrive, then returns it. |
| **[OnCreatedState](#oncreatedstate)** | `void` | Registers a callback that fires whenever a new state is received from the server. |

---

<a id="getstate-client"></a>
#### `GetState` *(client)*
Returns the locally cached StateObject for the given ID. If the state has not arrived yet, the call yields until it does or the timeout elapses.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Id` | `string` | The unique identifier of the state. |
| `Options` | `GetStateConfig?` | Optional. Set `____Timeout` to override the default 5-second wait. |

**Returns:** `StateObject?` — the state handle, or `nil` if the timeout elapsed.

!!! warning "Yields"
    This method may suspend the calling coroutine for up to the configured timeout. Do not call it during game initialization code that must complete immediately.

---

<a id="oncreatedstate"></a>
#### `OnCreatedState`
Registers a callback that fires whenever a new StateObject is received from the server. Also immediately fires for every state that has already arrived before this call was made.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Callback` | `(StateObject) -> ()` | Called with each new StateObject on creation. |

**Returns:** `void`

---

<a id="stateobject-client"></a>
### StateObject Methods (Client)
#### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Get](#get-client)** | `any` | Returns the current local value at a key. |
| **[Listen](#listen-state-client)** | `DisconnectObject` | Registers a change listener for a key and returns a disconnect object. |
| **[OnDestroyedState](#ondestroyedstate)** | `DisconnectObject` | Registers a callback that fires when the server removes this state. |
| **[Destroy](#destroy-client)** | `void` | Cleans up the local state and fires all destroy listeners. |

---

<a id="get-client"></a>
#### `Get` *(client)*
Returns the current locally cached value at the given key. Supports slash-delimited deep paths.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Key` | `string` | The key to read to. |

**Returns:** `any`

---

<a id="listen-state-client"></a>
#### `Listen` *(client StateObject)*
Registers a callback that fires whenever the server updates the given key on this state. Immediately fires once with the current value if the key is already populated.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Key` | `string` | The key to watch. |
| `Callback` | `(newValue: any, oldValue: any) -> ()` | Called with the new value and the previous value on each change. The first call (immediate) passes `nil` as the old value. |

**Returns:** `DisconnectObject` — call `:Disconnect()` to unregister the listener.

---

<a id="ondestroyedstate"></a>
#### `OnDestroyedState`
Registers a callback that fires when the server instructs this state to be destroyed.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Callback` | `() -> ()` | Called when this state is destroyed. |

**Returns:** `DisconnectObject` — call `:Disconnect()` to unregister the callback.

---

<a id="destroy-client"></a>
#### `Destroy` *(client)*
Fires all destroy listeners, clears all listeners and data, and removes this state from the local registry. Typically called automatically when the server sends a destroy instruction; you may call it manually to proactively clean up.

**Parameters:** `void`

**Returns:** `void`

---

## ByteWave Action — Server (`ByteWave.Action`)

**Accessed via:** `ByteWave.Action` on the server.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Register](#register)** | `void` | Registers a named handler that fires when a client sends an action with that name. |
| **[GetConfig](#getconfig)** | `{ [string]: any }?` | Returns the configuration table associated with a registered action. |

---

<a id="register"></a>
#### `Register`
Registers a handler function that is called when a client sends an action with the matching name through `ByteWave.Action.Send`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `ActionName` | `string` | The unique name identifying this action. |
| `Configuration` | `{ [string]: any }?` | Optional metadata table associated with this action. Retrievable via `GetConfig`. |
| `Handler` | `(Player, any) -> ()` | Called with the triggering player and the payload when the action arrives. |

**Returns:** `void`

!!! warning "Side Effect"
    Registering a handler for a name that is already registered replaces the previous handler. A warning is logged in Studio.

---

<a id="getconfig"></a>
#### `GetConfig`
Returns the configuration table that was passed when `Register` was called for the named action.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `ActionName` | `string` | The action name to look up. |

**Returns:** `{ [string]: any }?` — the config table, or `nil` if the action is not registered or was registered without a config.

---

## ByteWave Action — Client (`ByteWave.Action`)

**Accessed via:** `ByteWave.Action` on the client.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Send](#action-send)** | `void` | Sends a named action to the server. |

---

<a id="action-send"></a>
#### `Send` *(Action)*
Sends a named action request to the server. The server-side handler registered under the same name will be called.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `ActionName` | `string` | The name of the action to trigger. |
| `Payload` | `{ [string]: any }?` | Optional data table passed to the server handler. |

**Returns:** `void`

!!! danger "Strict Dependency: ByteWave"
    `ByteWave.Action` is initialized automatically when the main client module is required. Calling `Send` before the main client module has finished loading will log a warning and do nothing.