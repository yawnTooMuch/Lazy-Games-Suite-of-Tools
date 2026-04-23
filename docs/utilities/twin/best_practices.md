# Best Practices

Guidance on using Twin correctly and efficiently. Each practice explains the observable
consequence of getting it wrong and what the correct pattern gives you in return.

---

## 1. Never Store the BulkSplit Result Buffer

The table delivered to a `BulkSplit` callback is a reusable buffer that Twin recycles
immediately after your callback returns. It is not a permanent allocation.

### The Problem

```luau
-- The result table is assigned to a long-lived variable inside the callback.
local savedResults

Twin.BulkSplit(ProcessModule, "Run", items, function(results)
    savedResults = results  -- this table will be overwritten by the next BulkSplit job
end)

-- Later, elsewhere:
print(savedResults[1])  -- could be stale data from a completely different job
```

**Why this is wrong:** After your callback exits, Twin clears and returns that table to
its buffer pool. The next `BulkSplit` job will reuse the same table, overwriting every
index with new data. Any code holding the old reference now reads whatever the next job
put there — silently wrong results, with no error to indicate the problem.

### The Solution

```luau
-- Copy values out before the callback exits.
local savedResults = {}

Twin.BulkSplit(ProcessModule, "Run", items, function(results)
    table.move(results, 1, #results, 1, savedResults)
    -- savedResults is now a separate copy that belongs entirely to your code
end)
```

**Why this works:** Once you have copied the values into your own table, Twin's recycling
has no effect on your data. The copy is yours for as long as you hold the reference.

---

## 2. Never Yield Inside a Split Callback

A `Split` or `Sequence` callback fires synchronously on the main thread as part of Twin's
result delivery. Yielding inside it suspends that delivery path unexpectedly.

### The Problem

```luau
Twin.Split(DataModule, "Fetch", query, function(result)
    task.wait(1)  -- yields the main thread; Twin's delivery loop is now suspended
    applyResult(result)
end)
```

**Why this is wrong:** Yielding inside the callback suspends the coroutine that Twin uses
to deliver results. Other jobs whose results arrived while that coroutine was sleeping may
be delayed or delivered out of order. In the worst case, the frame budget check or watchdog
scan that runs on the same path is also stalled.

### The Solution

```luau
Twin.Split(DataModule, "Fetch", query, function(result)
    -- Store the result and schedule the deferred work separately.
    pendingResult = result
    task.defer(function()
        task.wait(1)
        applyResult(pendingResult)
    end)
    -- The callback itself returns immediately.
end)
```

**Why this works:** The callback returns immediately, Twin's delivery path is unblocked,
and your delayed work runs in a separate coroutine that does not affect any other jobs.

---

## 3. Match Job Weight to Its Role

Every `Split` and `Sequence` job has a weight: `"heavy"` (the default) or `"light"`. Using
the wrong weight causes either wasted parallelism or unintended interference with bulk work.

### The Problem

```luau
-- A job that only reads a tiny lookup table is dispatched as heavy.
-- It waits in line behind all active bulk work even though it poses no threat to throughput.
Twin.Split(LookupModule, "GetRank", playerId, function(rank)
    rankLabel.Text = rank
end)
-- Default weight is "heavy", so this waits until all BulkSplit batches are finished.
-- The label update is delayed for no reason.
```

**Why this is wrong:** Heavy jobs are deliberately held back until bulk work clears. A job
that takes microseconds to run does not need that protection. Marking it heavy adds latency
without any benefit.

### The Solution

```luau
-- A fast, non-blocking lookup is marked light so it can run alongside active bulk work.
Twin.Split(LookupModule, "GetRank", playerId, function(rank)
    rankLabel.Text = rank
end, { ____Weight = "light" })
```

**Why this works:** Light jobs are dispatched as soon as a worker is free, even while
bulk batches are in flight, as long as a free worker exists. The lookup completes in the
current frame without waiting for unrelated bulk work to finish.

**Decision guide:**

| Job characteristic | Correct weight |
| :--- | :--- |
| Computationally expensive; should not compete with bulk throughput | `"heavy"` (default) |
| Fast lookup, flag check, or transformation; safe to run alongside bulk | `"light"` |
| Unknown / conservative default | `"heavy"` |

---

## 4. Choose the Right BulkSplit Priority

The three priority lanes — `"critical"`, `"normal"`, and `"background"` — exist to let
important work jump the queue. Using the wrong priority either starves your work or, worse,
starves someone else's.

### The Problem

```luau
-- Everything is dispatched as critical, including low-urgency work.
Twin.BulkSplit(TileModule, "Generate", allTiles, onTilesReady, {
    ____Priority = "critical",  -- this is world generation, not a physics pre-solve
})
```

**Why this is wrong:** Critical jobs are always dispatched before normal and background
jobs. If every job claims critical priority, the ordering guarantee becomes meaningless and
genuinely time-sensitive work gains nothing from the priority system.

### The Solution

```luau
-- Physics pre-solve: blocks the next frame if it doesn't finish → critical.
Twin.BulkSplit(PhysicsModule, "PreSolve", bodies, applyImpulses, {
    ____Priority = "critical",
})

-- NPC behaviour update: needs to happen this second, but not sub-frame → normal.
Twin.BulkSplit(AIModule, "Tick", npcList, updateNPCs, {
    ____Priority = "normal",
})

-- World tile generation: nice to have soon, no hard deadline → background.
Twin.BulkSplit(TileModule, "Generate", pendingTiles, cacheTiles, {
    ____Priority = "background",
})
```

**Why this works:** Twin drains critical jobs first, then normal, then background. Background
jobs are never starved indefinitely — they are periodically promoted regardless — so even
the lowest-priority work is guaranteed to eventually run.

---

## 5. Design Worker Functions to Accept and Return Plain Data

Worker functions execute inside a parallel worker. When a worker is desynchronized, only a
specific subset of Roblox API members are safe to access. Most DataModel reads and all
DataModel writes are forbidden in that context.

!!! note "What you CAN read inside a parallel worker"
    Roblox assigns every API member one of four thread-safety levels. The two levels that
    permit access from a desynchronized parallel thread are:

    **Read Parallel** — can be read but not written:

    - `BasePart.CFrame`, `BasePart.Position`, `BasePart.Orientation`, `BasePart.Size`
    - `BasePart.Anchored`, `BasePart.Color`, `BasePart.BrickColor`, `BasePart.Transparency`
    - `BasePart.AssemblyLinearVelocity`, `BasePart.AssemblyAngularVelocity`
    - `Instance.Name`, `Instance.Parent`, `Instance.ClassName`

    **Safe** — can be read and called:

    - `Workspace:Raycast()` and spatial query methods such as `GetPartBoundsInBox`
    - `Instance:GetAttribute()`, `Instance:GetAttributes()`
    - `Instance:FindFirstChild()`, `Instance:FindFirstAncestorOfClass()`
    - `Instance:IsA()`, `Instance:IsDescendantOf()`
    - `SharedTable` read operations

    Any API member with no thread-safety tag defaults to **Unsafe** and will throw an error
    if accessed from a parallel thread. Most events, `GetChildren()`, `GetDescendants()`, and
    all property writes fall into this category. When in doubt, collect the data on the main
    thread before dispatch and pass it as plain tables through Twin's `Payload` or
    `SharedArgs`. See [Roblox thread safety documentation](https://create.roblox.com/docs/scripting/multithreading#thread-safety)
    for the full per-member safety table.

!!! warning "Twin uses BindableEvent and Actor:SendMessage — not SharedTable"
    Twin intentionally does not use `SharedTable` for data transport. Instead it uses
    `Actor:SendMessage` to send work to workers and `BindableEvent:Fire` to return results
    to the main thread. This is a deliberate design choice that gives you complete freedom
    to use ordinary Luau tables as your `Payload`, `SharedArgs`, and return values — no
    SharedTable API, no atomic update functions, no structural constraints.

    The trade-off is that both `Actor:SendMessage` and `BindableEvent:Fire` **deep-copy**
    all data they carry. Every value you pass to Twin — the `Payload` on a `Split` call,
    the `SharedArgs` on a `BulkSplit`, the slice sent to each batch worker, and the result
    table returned from each worker — is fully serialised and copied as it crosses the
    parallel boundary in both directions.

    The cost of this copy is directly proportional to the size and depth of the data. A
    small table of numbers crosses cheaply. A deeply nested table with hundreds of entries
    takes measurably longer. This is not a bug or a limitation of Twin specifically — it is
    the fundamental cost of safe cross-boundary data transfer in Roblox's parallel model.

    Practice 9 in this document is dedicated to minimising this cost.

### The Problem

```luau
-- ThreatModule (worker module)
local ThreatModule = {}

function ThreatModule.Assess(payload)
    -- GetChildren() is Unsafe — this errors in a parallel worker.
    -- workspace itself cannot be freely accessed from a desynchronized thread.
    local npcs = workspace.NPCFolder:GetChildren()
    return computeThreat(npcs, payload.playerPos)
end

return ThreatModule
```

**Why this is wrong:** `GetChildren()` is marked Unsafe by Roblox and throws an error
when called from a desynchronized parallel thread. Even if no error occurred, reading
live instance data from inside a parallel worker creates a race condition — the main
thread may be modifying those same instances at the same moment.

### The Solution

```luau
-- ThreatModule (worker module)
-- All instance data is pre-collected on the main thread and passed in as plain tables.
local ThreatModule = {}

function ThreatModule.Assess(payload)
    -- payload.npcData is a plain Luau table — safe to read in a parallel worker.
    local threats = table.create(#payload.npcData)
    for i, npc in payload.npcData do
        threats[i] = computeThreat(npc.position, npc.health, payload.playerPos)
    end
    return threats
end

return ThreatModule

-- Caller (main thread): collect instance data before dispatch.
local npcData = {}
for i, npc in workspace.NPCFolder:GetChildren() do
    -- Extract only what the worker needs — position and health as plain values.
    npcData[i] = { position = npc.PrimaryPart.Position, health = npc:GetAttribute("Health") }
end

Twin.BulkSplit(ThreatModule, "Assess", npcData, function(threats)
    updateThreats(threats)
end, { ____SharedArgs = { playerPos = player.Character.PrimaryPart.Position } })
```

**Why this works:** All `GetChildren()` and property reads happen on the main thread
before dispatch, where they are safe. The worker receives a plain Luau table containing
only the values it needs. Results are returned as plain values and delivered back to the
main thread for any DataModel writes.

---

## 6. Keep Callbacks Cheap — Reserve Heavy Logic for Workers

Callbacks run on the main thread. A callback that performs significant computation is
identical, from the frame budget's perspective, to running that computation inline. The
entire point of Twin is to move expensive work off the main thread.

### The Problem

```luau
Twin.Split(PrepModule, "Prepare", rawData, function(prepared)
    -- This loop runs on the main thread — it defeats the purpose of using Twin at all
    local processed = {}
    for i = 1, 10000 do
        processed[i] = transform(prepared[i])
    end
    applyResults(processed)
end)
```

**Why this is wrong:** The callback runs synchronously on the main thread in the same
frame the worker finishes. A 10,000-iteration loop here costs the same frame time as
running it without Twin.

### The Solution

```luau
-- Move the transformation into the worker module, not the callback.
-- PrepModule.PrepareAndTransform now does both steps in parallel.
Twin.Split(PrepModule, "PrepareAndTransform", rawData, function(processed)
    -- The callback does only what must happen on the main thread: writing results out.
    applyResults(processed)
end)
```

**Why this works:** The transformation runs off the main thread inside the worker. The
callback only applies the finished result — a cheap write operation that costs negligible
frame time.

---

## 7. Use Sequence for Dependent Pipelines, Not Nested Callbacks

When job B needs job A's result, the instinct is to dispatch B inside A's callback. This
works, but it creates nesting that becomes hard to read and cancel cleanly.

### The Problem

```luau
-- Three dependent steps, nested three levels deep.
Twin.Split(StepAModule, "Run", input, function(resultA)
    Twin.Split(StepBModule, "Run", resultA, function(resultB)
        Twin.Split(StepCModule, "Run", resultB, function(resultC)
            finish(resultC)
        end)
    end)
end)
-- Cancelling at any point requires tracking three separate handles.
-- Error handling at each level is duplicated.
```

**Why this is wrong:** Beyond two levels, nested callbacks become hard to follow and
nearly impossible to cancel atomically. There is no single point to call that stops the
whole pipeline.

### The Solution

```luau
-- The same three steps expressed as a Sequence.
local pipelineHandle = Twin.Sequence({
    { ____Module = StepAModule, ____FunctionName = "Run", ____Payload = input },
    {
        ____Module       = StepBModule,
        ____FunctionName = "Run",
        ____Payload      = function(prevResult) return prevResult end,
    },
    {
        ____Module       = StepCModule,
        ____FunctionName = "Run",
        ____Payload      = function(prevResult) return prevResult end,
    },
}, function(results)
    finish(results[3])
end)

-- One handle cancels the entire pipeline at any point.
cancelButton.Activated:Connect(function()
    pipelineHandle.Disconnect()
end)
```

**Why this works:** Sequence manages the chaining internally. Dynamic payload functions
pass each step's result forward automatically. A single `Disconnect()` on the handle
cancels the current step and prevents any further steps from dispatching.

---

## 8. Only Store Handles When Cancellation Is Critical

Every Twin call returns a `Handle`. A handle becomes inert the moment its job completes
naturally — it holds nothing and does nothing after that point. Storing every handle as a
matter of habit is storing garbage: references to objects that are no longer relevant to
Twin or to your logic.

### The Problem

```luau
-- Storing a handle for a fire-and-forget job that will never be cancelled.
local handle = Twin.Split(ScoreModule, "ComputeBonus", playerId, function(bonus)
    bonusLabel.Text = "+" .. tostring(bonus)
end, { ____Weight = "light" })
-- `handle` is never used. It sits in a variable until the scope closes.
-- Multiplied across hundreds of calls, this is hundreds of dead references.
```

**Why this is wrong:** The job either completes and the handle becomes inert, or the
scope exits and the variable is collected anyway. Storing the handle bought nothing. When
every call follows this pattern, your code is cluttered with variables that serve no
purpose.

### The Solution

```luau
-- Fire-and-forget: discard the handle entirely.
Twin.Split(ScoreModule, "ComputeBonus", playerId, function(bonus)
    bonusLabel.Text = "+" .. tostring(bonus)
end, { ____Weight = "light" })
-- No variable. The job runs, the callback fires, and everything cleans up automatically.
```

**Store a handle only when you have a concrete reason to cancel:**

```luau
-- A long-running generation job tied to a specific game object.
-- If the object is destroyed mid-job, the callback must be suppressed.
local generationHandle = Twin.BulkSplit(WorldModule, "GenerateTile", pendingCoords, function(tiles)
    applyTiles(tiles)  -- applies to a specific zone that may no longer exist
end, { ____Priority = "background" })

zone.Destroying:Connect(function()
    generationHandle.Disconnect()
    -- Suppresses the callback even if workers are still running.
end)
```

**Why this works:** Twin is responsible for cleaning up completed jobs. Your code is only
responsible for the jobs it needs to cancel. Storing a handle is a commitment that you
will call `Disconnect()` on it under some condition — if that condition does not exist,
the handle should not be stored.

---

## 9. Only Pass the Data the Worker Actually Needs

Because all data travelling to and from Twin's workers is deep-copied on every crossing,
the cost of each job is not just computation time — it also includes the serialisation cost
of the data you send and the data you return. Sending large, irrelevant, or deeply nested
structures makes every job slower before the worker function even starts.

### The Problem

```luau
-- Sending an entire NPC model's data table, including animation state, sounds, GUI refs,
-- and dozens of other fields the worker will never touch.
local npcRecords = {}
for i, npc in npcs do
    npcRecords[i] = npc:GetAttributes()  -- returns every attribute on the instance
end

Twin.BulkSplit(ThreatModule, "Assess", npcRecords, function(threats)
    updateThreats(threats)
end)
-- The worker only uses `health` and `position`, but every attribute crosses the boundary.
```

**Why this is wrong:** Every field in every record is deep-copied when the job is
dispatched and again when results are returned. The worker pays a serialisation cost
proportional to how much data was sent, regardless of how much of that data it actually
reads. Sending one hundred fields to a function that uses two means ninety-eight fields
are copied, transmitted, and collected for free — or rather, not for free at all.

### The Solution

```luau
-- Extract only the fields the worker function actually uses before dispatch.
local npcRecords = {}
for i, npc in npcs do
    npcRecords[i] = {
        position = npc.PrimaryPart.Position,  -- used by the worker
        health   = npc:GetAttribute("Health"), -- used by the worker
        -- nothing else
    }
end

Twin.BulkSplit(ThreatModule, "Assess", npcRecords, function(threats)
    updateThreats(threats)
end)
```

**Why this works:** The data crossing the parallel boundary is exactly as large as it
needs to be. Serialisation is fast, the worker receives a clean, minimal payload, and
the result table is compact. The saving compounds with batch size: a hundred items where
each saves ten unnecessary fields means a thousand fewer values copied per dispatch.

**The same rule applies to return values.** If your worker computes a rich intermediate
structure but the caller only needs one number from it, return only that number. Every
field in the returned table is also deep-copied on the way back.

```luau
-- Worker returns an entire intermediate structure when only the score is needed.
function ThreatModule.Assess(payload)
    local result = runFullThreatAnalysis(payload)
    return result  -- contains score, breakdown, path, confidence, logs...
end

-- Worker returns only what the caller will use.
function ThreatModule.Assess(payload)
    local result = runFullThreatAnalysis(payload)
    return result.score  -- one number; the rest is discarded before the boundary
end
```

---

!!! success "Pro Tip"
    Twin's worker pool size is configured separately for server and client. If your
    telemetry consistently shows all workers busy and queues growing, the first thing to
    check is whether your workload genuinely needs more workers or whether your worker
    functions are slower than expected. Increasing the worker count helps with
    throughput-limited workloads; optimising the worker function — or reducing the size of
    the data it receives and returns — helps with latency-limited ones. Use `Twin.Report()`
    in Studio with telemetry enabled to measure average worker execution times before
    deciding which lever to pull.
