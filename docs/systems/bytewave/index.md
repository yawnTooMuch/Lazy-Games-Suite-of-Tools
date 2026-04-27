# ByteWave

**Type:** Framework  
_A binary-batching networking framework for Roblox that replaces raw RemoteEvents with structured, high-throughput packet routing, scoped state replication, and built-in anti-spam protection._

[Distribution:]() `Private Framework, exclusive only within Lazy Games usage.`

---

## Overview

ByteWave is the backbone networking engine for all Lazy Games projects, purpose-built to move data across the client-server boundary efficiently, reliably, and without the overhead that comes with managing raw RemoteEvents directly. Rather than maintaining a scattered collection of individual RemoteEvent instances throughout the codebase, ByteWave consolidates all communication through a structured Gateway and Path routing model. Everything queued during a frame is accumulated into compact binary buffers and flushed together at the end of that frame — one network round-trip carries dozens of individual packets, resulting in dramatically lower overhead and far fewer bytes on the wire.

The framework is split across two entry points: one required on the server and one on the client. Both expose the same conceptual model — **Gateways** as named routing channels and **Paths** as the addresses within them — so the mental model is identical regardless of which side you are writing code for. All serialization, interning, and chunking is handled invisibly; you call `Send` with a value and ByteWave decides the most efficient encoding.

ByteWave ships with two built-in sub-systems that plug directly into its networking layer. The **State** sub-system manages server-owned data objects that are automatically replicated to the correct clients and kept in sync as the data changes. The **Action** sub-system provides a lightweight pattern for clients to trigger named server-side handlers without building gateway listeners by hand. Both sub-systems are accessed through the main ByteWave module and require no additional remote setup.

---

## External Dependencies

- **Twin** *(optional, server-side State only)* — When injected, Twin replaces the built-in parallel worker pool used for spatial state discovery, distributing the position math across all available Actor workers instead of a fixed-count pool. ByteWave works without Twin; Twin simply makes large-server spatial queries faster.
- **Assignment** *(optional)* — A custom scheduler that can replace the standard `task.*` library throughout the entire suite.

---

## Key Features

### Auto Segregation of Packets

ByteWave never places all outbound data into a single general-purpose lane. As each packet is queued, ByteWave inspects its payload and automatically routes it into the most efficient lane for that data type. Numeric values travel through a compact binary lane optimized for tight integer encoding. Tables and complex structures travel through a separate serialization lane capable of handling arbitrary nested data. Reliable packets and unreliable packets are segregated into their own channels before anything leaves the server or client.

This segregation happens invisibly — you call `Send` and ByteWave decides the lane. The benefit is that a slow or large complex packet cannot interfere with a lightweight numeric update queued in the same frame. Each lane drains independently, so hot-path data always gets the most efficient representation without contending with heavier payloads in the same buffer.

### Auto Compression of Packets

Before any packet leaves the outbound buffer, ByteWave will inspect the serialized byte representation and apply format-appropriate compression automatically. The developer never calls a compression function — the pipeline detects payload size and type, selects the most compact encoding strategy for that class of data, and compresses before transmission. On the receiving end, the reverse step is applied transparently before the decoded value is delivered to any listener or state callback. From the developer's perspective, values go in and values come out — the compression round-trip is completely invisible.

### String Named Routing Mechanism

Instead of maintaining individual RemoteEvent instances scattered across the codebase — one per behavior — ByteWave introduces a two-level named routing model built on **Gateways** and **Paths**.

A **Gateway** is a named logical channel. You declare it by simply using its name in a `Send` or `Listen` call — there is no instance to create, no object to store, and no hierarchy to maintain in the DataModel. A gateway can represent any organizational boundary you choose: a gameplay system, a feature area, a data category.

A **Path** is the address within a gateway. Every gateway is a multiplexer — a single `Listen` callback on a gateway receives all traffic arriving on that gateway, regardless of which path it carries. The path value in the packet tells your callback which specific behavior or data is arriving. This means one listener function can handle dozens of distinct logical operations that would otherwise require dozens of separate RemoteEvents.

```
Gateway: "Combat"
  Path: "DealDamage"   → handler branch A
  Path: "ApplyEffect"  → handler branch B
  Path: "Knockback"    → handler branch C
```

!!! info "How Gateway and Path routing works — execution complexity"
    Internally, ByteWave maintains a flat hash-map of registered listeners keyed by gateway name. When an inbound packet arrives, the gateway lookup is a single O(1) hash-map read. There is no list to scan, no tree to walk, and no pattern matching — the correct listener is found in constant time regardless of how many gateways or paths are registered. Within the listener, path dispatching is the developer's responsibility (typically a simple `if`/`elseif` chain or another hash-map), but the ByteWave routing layer itself adds no additional overhead beyond that single O(1) lookup per inbound packet.
!!! danger "Reserved Gateways — Do Not Use"
    The gateway names `"System"` and `"State"` are strictly reserved for ByteWave's internal operations. **Never use either of these names as a gateway in `Send`, `Listen`, `SpatialSend`, `SetGatewayWhitelist`, or `SetRequestHandler` calls.** `"System"` is used for the connection handshake, time synchronization, and RPC routing. `"State"` is used for the State sub-system's replication pipeline. Sending or listening on either of these gateways from developer code will collide directly with ByteWave's internal logic and produce undefined, unpredictable behavior.

### Single-Frame Binary Batching

Every outbound packet — whether it carries a number, a string, or a table — is placed into a per-target buffer during the frame it is queued. At the end of each frame ByteWave drains those buffers in a single RemoteEvent call per player, per reliability channel. Think of it like a postal sorting office: letters dropped off throughout the day are bundled into one van run at closing time rather than dispatched one by one. Numeric values are stored in the tightest integer width that fits the value, so small integers cost one or two bytes instead of a full float.

### String Interning

Channel names and string paths are registered once as two-byte numeric identifiers the first time they appear. Every subsequent packet that uses the same name sends those two bytes rather than the full string. The mapping is synchronized to new clients on join, so the client decodes packets using the same compact IDs. This makes high-frequency sends on named paths — position updates, inventory changes, UI state — far cheaper over time than sending the string each frame.

### Dual Reliability Channels

Each queued packet is marked as either reliable (guaranteed delivery, ordered) or unreliable (fire-and-forget, lower overhead). ByteWave automatically routes the packet to the appropriate RemoteEvent. Packets carrying new interned strings are always promoted to reliable automatically — there is no risk of a client receiving a numeric ID before it has learned the corresponding string.

### Gateway Access Control and Middleware

Any named gateway can be restricted to a specific list of UserIds, preventing other clients from injecting traffic through it. Additionally, custom middleware functions can be attached to the inbound pipeline; each middleware receives every incoming packet before it reaches any listener and can return `false` to silently drop it. ByteWave's own anti-spam protection is installed as middleware automatically.

### Built-In Anti-Spam Protection

A token-bucket rate limiter evaluates every inbound packet before it reaches any listener. Players who send packets faster than the configured sustained rate have their tokens reduced; once tokens fall below the penalty threshold the player enters a probation window. A player who sustains spam for the full probation duration is kicked. Defense profiles are retained for ten minutes after a player leaves — a player who disconnects and reconnects immediately picks up exactly where the penalty left off rather than starting fresh.

!!! info "System gateway protection — isolated and purpose-built"
    The `"System"` gateway is intentionally exempt from the token-bucket middleware, but this does not leave it unprotected. ByteWave runs a completely separate, path-specific rate-limiting system exclusively for System traffic. Each internal System path has its own cap tuned to the expected frequency of that operation: handshake acknowledgement, time synchronization, and RPC communication are all governed by independent counters that reset every second. When a client exceeds the cap for any System path, ByteWave places that player on a per-path "wanted list" and silently stops processing their System traffic on that path for a configurable ban duration. Continued abuse while banned extends the penalty window further. Abuse of the handshake path specifically results in a permanent session-level ban with no recovery — ByteWave will not process any further handshake traffic from that client for the remainder of the server session. A background janitor periodically sweeps and evicts expired entries from both the rate counter ledger and the wanted list, keeping memory overhead bounded over long sessions.

### Automated Player Cleanup

When a player leaves the server, ByteWave automatically tears down every piece of infrastructure it built on their behalf — the developer does not write a single line of cleanup code.

On the networking side, all outbound data queued for that player is immediately discarded before it can be dispatched, their slot in the per-frame flush pipeline is released, and all rate-limiting and security tracking associated with their session is erased. There is no risk of a stale outbound batch arriving for a player who no longer exists, and no memory growth from accumulating per-player counters over a long server session.

On the state side, cleanup is similarly comprehensive but deliberately staged. The moment a player leaves, ByteWave stops replicating all spatial state to them, removes them from every filtered state they were subscribed to, and sends each of those filtered states a removal notification so their client copy is destroyed cleanly. Any state objects that were created as privately owned by that player — inventory records, session data, progression snapshots — are scheduled for destruction after a short grace window. This delay exists to handle race conditions such as a server-side script still writing final data before teardown; by the time the window expires, the state is guaranteed to be gone and all observers have been notified.

!!! info "Defense profiles survive disconnection"
    Anti-spam penalty records are intentionally exempt from the immediate cleanup pass. A player who disconnects and reconnects within a short window picks up exactly where their penalty left off rather than starting fresh. This prevents a common evasion pattern where a spamming client disconnects to reset its standing.

### Request/Response (RPC)

The client can send a request to a named server-side handler and yield until the response arrives or a timeout elapses. The server handler receives the request data and returns any value, which ByteWave automatically routes back to the waiting client coroutine. There is no manual ID tracking, no BindableEvent plumbing, and no risk of orphaned threads — ByteWave handles cleanup on timeout.

### Spatial State Replication

ByteWave does not rely on Roblox's native `StreamingEnabled` mechanism for proximity-based delivery. It maintains its own independent Level-of-Detail system, operating entirely outside the Roblox engine's streaming pipeline.

Every spatial state and spatial send is governed by a developer-defined radius anchored to a world object. ByteWave evaluates player positions against all registered spatial anchors on a regular tick, running the math in parallel across Actor workers. When a player enters a radius they receive the full current snapshot of everything within that area. When they leave, they receive a destroy signal and their local copy is cleaned up. Players who were never in range never receive the data at all.

This means spatial delivery is not an approximation or a hint to the engine — ByteWave guarantees that only players physically within the configured radius receive spatial packets and state replication. All the complexity of tracking who is in range, who just entered, who just left, and what data needs to be sent or removed is handled entirely by ByteWave. The developer declares a radius and an anchor; ByteWave handles the rest.

!!! danger "Reserved Gateways — Do Not Use"
    The `"State"` gateway is reserved exclusively for the State sub-system's internal replication traffic. Never address it directly from `Send`, `Listen`, or any other ByteWave API. All interaction with replicated state must go through `ByteWave.State` — using `"State"` as a raw gateway name will interfere with state synchronization for every player in the server.