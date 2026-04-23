# Examples

Practical scenarios for every Twin API method. Each example is self-contained and includes
comments explaining the user-visible outcome at every non-obvious step.

---

## Twin.Split

Dispatches a single parallel job. The callback fires in the same frame the worker finishes —
no extra frame of delay. Choose `"heavy"` (default) when the job should wait for bulk work to
clear; choose `"light"` for fast jobs that can run alongside active bulk work.

!!! info "What Twin passes in — and what comes back"
    **Your worker function receives one argument:** the `Payload` value you provided to
    `Twin.Split`. It can be any Luau value — a plain number, a string, a table, or `nil`.

    **Your worker function must return one value:** anything you return becomes the `Result`
    delivered to your callback. Return `nil` if there is no meaningful result.

    The required function signature inside your ModuleScript is:

    ```luau
    local MyModule = {}

    function MyModule.FunctionName(Payload: any): any
        -- Payload is exactly what you passed as the third argument to Twin.Split.
        -- Whatever you return here arrives as Result in your Split callback.
        return computedResult
    end

    return MyModule
    ```

    **Argument received by the worker function:**

    | Argument | Type | Description |
    | :--- | :--- | :--- |
    | `Payload` | `any` | The third argument you passed to `Twin.Split`. |

    **Argument delivered to your callback:**

    | Argument | Type | Description |
    | :--- | :--- | :--- |
    | `Result` | `any` | The single return value of your worker function. `nil` if the function returned nothing or threw an error. |

---

**Scenario A — Basic pathfinding off the main thread (heavy, default)**

The worker module:

```luau
-- PathModule (ModuleScript)
local PathModule = {}

function PathModule.FindPath(payload)
    -- payload is the plain table passed as Payload in the Twin.Split call.
    -- All computation happens here in the parallel worker — the main thread is free.
    local waypoints = runAStarSearch(payload.Start, payload.Goal, payload.Radius)
    -- Return a plain table of waypoints. This becomes `path` in the Split callback.
    return waypoints
end

return PathModule
```

The caller:

```luau
-- No Options table is passed — the default weight is "heavy".
-- A heavy job waits until all active BulkSplit batches finish before a worker picks it up.
Twin.Split(PathModule, "FindPath", {
    Start  = character.HumanoidRootPart.Position,
    Goal   = targetPosition,
    Radius = 4,
}, function(path)
    -- `path` is the table returned by PathModule.FindPath, delivered on the main thread.
    -- The main thread was never blocked during the calculation.
    if path then
        humanoid:MoveTo(path[1])
    end
end)
```

---

**Scenario B — Explicit heavy job that must not compete with bulk throughput**

The worker module:

```luau
-- MeshModule (ModuleScript)
local MeshModule = {}

function MeshModule.Build(payload)
    -- Expensive geometry construction that takes tens of milliseconds.
    -- Runs entirely in the parallel worker; the game loop is unaffected.
    local mesh = buildProceduralMesh(payload.vertexCount, payload.seed, payload.lod)
    -- `mesh` is returned as the Result in the Split callback.
    return mesh
end

return MeshModule
```

The caller:

```luau
-- Explicitly marked heavy. While any BulkSplit batch is in flight, this job sits in the
-- heavy queue and does not occupy a worker. Only after all bulk work clears will a worker
-- pick this up. This prevents an expensive mesh build from stealing a worker away from
-- time-sensitive bulk batches.
Twin.Split(MeshModule, "Build", {
    vertexCount = 2048,
    seed        = math.random(),
    lod         = 2,
}, function(mesh)
    -- Apply the finished mesh on the main thread where DataModel writes are safe.
    part.MeshId = mesh.id
    part.Size   = mesh.bounds
end, { ____Weight = "heavy" })
```

---

**Scenario C — Lightweight speculative job alongside active bulk work**

The worker module:

```luau
-- ScoreModule (ModuleScript)
local ScoreModule = {}

function ScoreModule.ComputeBonus(payload)
    -- Fast lookup — completes in microseconds.
    -- Safe to run speculatively while BulkSplit batches are in flight.
    return bonusTable[payload.playerId] or 0
end

return ScoreModule
```

The caller:

```luau
-- Marked light: may run on a free worker even while BulkSplit batches are active.
-- Use this for fast, non-blocking jobs where waiting for bulk to clear is unnecessary.
Twin.Split(ScoreModule, "ComputeBonus", { playerId = localPlayer.UserId }, function(bonus)
    bonusLabel.Text = "+" .. tostring(bonus)
end, { ____Weight = "light" })
```

---

**Scenario D — Cancellation before the job runs**

```luau
-- Uses the same MeshModule from Scenario B — the worker contract is unchanged.
local handle = Twin.Split(MeshModule, "Build", meshParams, function(mesh)
    -- This callback will never fire if Disconnect() is called before the worker starts.
    -- If the worker already picked the job up, the result is silently discarded.
    applyMesh(mesh)
end)

-- The player left the game before the mesh was needed — cancel cleanly.
Players.PlayerRemoving:Connect(function(player)
    if player == targetPlayer then
        handle.Disconnect()
    end
end)
```

---

**Scenario E — Fanning out two independent Split calls and combining their results**

```luau
-- When two jobs don't depend on each other, dispatch both at once.
-- Both results arrive independently; you are responsible for combining them.
local resultA, resultB

Twin.Split(ModuleA, "Analyze", datasetA, function(result)
    resultA = result
    if resultB then
        finalize(resultA, resultB)  -- only runs once both callbacks have fired
    end
end)

Twin.Split(ModuleB, "Analyze", datasetB, function(result)
    resultB = result
    if resultA then
        finalize(resultA, resultB)
    end
end)
-- For ordered pipelines where step B depends on step A's output, use Twin.Sequence instead.
```

---

## Twin.BulkSplit

Fans a list of items across all available workers in parallel, then reassembles results in
the original order. The result table passed to the callback is a recycled buffer — copy any
values you need before the callback returns.

!!! info "What Twin passes in — and what comes back"
    Twin automatically slices your `Items` list into batches and sends each batch to a
    separate worker. Your batch function is called once per batch, not once per item.

    **Your batch function receives two arguments:**

    | Argument | Type | Description |
    | :--- | :--- | :--- |
    | `slice` | `{ any }` | A contiguous subset of your original `Items` list assigned to this worker. The slice is re-indexed from `1` — `slice[1]` is not necessarily `items[1]`. |
    | `sharedArgs` | `any?` | The value you passed as `____SharedArgs`. The same value is passed to every batch function call. `nil` if you did not provide `____SharedArgs`. |

    **Your batch function must return:** a table of the same length as `slice`. Twin places
    each returned value back into the correct position in the final results table using the
    original item indices. Returning a mis-sized table will produce `nil` gaps in the results.

    **Argument delivered to your callback:**

    | Argument | Type | Description |
    | :--- | :--- | :--- |
    | `Results` | `{ any }` | The fully reassembled results table. `Results[i]` corresponds to `Items[i]` from your original list. This buffer is recycled immediately after your callback exits — copy anything you need before returning. |

    The required function signature inside your ModuleScript is:

    ```luau
    local MyModule = {}

    function MyModule.FunctionName(slice: { any }, sharedArgs: any?): { any }
        local results = table.create(#slice)
        for i, item in slice do
            results[i] = processItem(item, sharedArgs)
        end
        -- Must return a table of the same length as `slice`.
        return results
    end

    return MyModule
    ```

---

**Scenario A — Normal priority NPC threat assessment (default)**

The worker module:

```luau
-- ThreatModule (ModuleScript)
local ThreatModule = {}

function ThreatModule.Assess(slice, sharedArgs)
    -- `slice` is one batch of npcData records for this worker to process.
    -- `sharedArgs` is the { playerPosition } table passed as ____SharedArgs.
    local results = table.create(#slice)
    for i, npc in slice do
        results[i] = computeThreatScore(npc.position, npc.health, sharedArgs.playerPosition)
    end
    -- Return a table the same length as slice — one score per NPC record.
    return results
end

return ThreatModule
```

The caller:

```luau
-- Priority "normal" is the default — dispatched after critical jobs but before background.
-- Shown explicitly here with ____Priority = "normal" for clarity.
local npcs = workspace.NPCFolder:GetChildren()
local npcData = {}
for i, npc in npcs do
    npcData[i] = { position = npc.PrimaryPart.Position, health = npc:GetAttribute("Health") }
end

Twin.BulkSplit(ThreatModule, "Assess", npcData, function(threats)
    -- threats[i] is the score for npcData[i] — index mapping is preserved.
    -- Copy the scores out before the callback exits; the buffer will be recycled.
    local scores = table.create(#threats)
    table.move(threats, 1, #threats, 1, scores)
    updateThreatDisplay(scores)
end, {
    ____SharedArgs = { playerPosition = localPlayer.Character.PrimaryPart.Position },
    ____Priority   = "normal",
})
```

---

**Scenario B — Critical-priority bulk job with a tight deadline**

The worker module:

```luau
-- PhysicsModule (ModuleScript)
local PhysicsModule = {}

function PhysicsModule.PreSolve(slice, sharedArgs)
    -- Each item in `slice` is a physics body record.
    -- `sharedArgs` carries the current timestep for this solve pass.
    local solutions = table.create(#slice)
    for i, body in slice do
        solutions[i] = solveConstraints(body, sharedArgs.dt)
    end
    return solutions
end

return PhysicsModule
```

The caller:

```luau
-- "critical" ensures this reaches workers before any queued normal or background jobs.
-- MaxWaitTime of 0.010 tightens the deadline so the scheduler promotes this job sooner.
Twin.BulkSplit(PhysicsModule, "PreSolve", bodyList, function(solutions)
    for i, body in bodyList do
        applyImpulse(body, solutions[i])
    end
end, {
    ____Priority    = "critical",
    ____MaxWaitTime = 0.010,
    ____SharedArgs  = { dt = workspace:GetRealPhysicsFPS() },
})
```

---

**Scenario C — Background tile generation (low urgency, cancellable)**

The worker module:

```luau
-- WorldModule (ModuleScript)
local WorldModule = {}

function WorldModule.GenerateTile(slice, sharedArgs)
    -- `slice` is a batch of tile coordinate records to generate.
    -- `sharedArgs` carries the world seed used for procedural generation.
    local tiles = table.create(#slice)
    for i, coord in slice do
        tiles[i] = generateTileData(coord.x, coord.z, sharedArgs.seed)
    end
    return tiles
end

return WorldModule
```

The caller:

```luau
-- "background" means this only runs when no critical or normal jobs are waiting.
-- Background jobs are never starved indefinitely — they are periodically promoted.
local generationHandle = Twin.BulkSplit(
    WorldModule,
    "GenerateTile",
    pendingTileCoords,
    function(tiles)
        -- tiles[i] corresponds to pendingTileCoords[i].
        -- Copy results before returning — the buffer is recycled after this callback exits.
        for i, coord in pendingTileCoords do
            tileCache[coord] = tiles[i]
        end
        renderNewTiles()
    end,
    {
        ____Priority   = "background",
        ____BatchSize  = 16,         -- smaller batches spread work across more workers
        ____SharedArgs = { seed = worldSeed },
    }
)

-- Cancel if the player moves far enough away that the tiles are no longer needed.
playerMovedFarAway:Connect(function()
    generationHandle.Disconnect()
end)
```

---

**Scenario D — Shared configuration passed to every batch**

The worker module:

```luau
-- FilterModule (ModuleScript)
local FilterModule = {}

function FilterModule.ApplyRules(slice, sharedArgs)
    -- `sharedArgs` is the same configuration table delivered to every batch.
    -- It carries a ruleset, timestamp, and a strict mode flag set by the caller.
    local results = table.create(#slice)
    for i, item in slice do
        results[i] = applyRuleSet(item, sharedArgs.rules, sharedArgs.strictMode)
    end
    return results
end

return FilterModule
```

The caller:

```luau
-- SharedArgs is passed as-is to every batch function call alongside the slice.
-- Use it for read-only configuration that applies equally to every item.
Twin.BulkSplit(FilterModule, "ApplyRules", itemList, function(filtered)
    local kept = {}
    for i, result in filtered do
        if result ~= nil then
            table.insert(kept, result)
        end
    end
    publishResults(kept)
end, {
    ____SharedArgs = {
        rules      = activeRuleSet,
        timestamp  = os.clock(),
        strictMode = true,
    },
})
```

---

**Scenario E — Empty input (fires immediately)**

```luau
-- When Items is empty, the callback fires synchronously before BulkSplit returns.
-- No workers are involved. Guard against this if your code assumes async delivery.
Twin.BulkSplit(ProcessModule, "Run", {}, function(results)
    -- results is an empty table — arrives immediately, no workers involved
    print("Nothing to process.")
end)
```

---

## Twin.Sequence

Runs an ordered pipeline of parallel jobs. Each step receives the previous step's result. The
`____Payload` field may be a plain value or a function that computes the payload from the
previous result at dispatch time.

!!! info "What Twin passes in — and what comes back for each step"
    Each step in a Sequence is a standard Split job under the hood. The same worker function
    contract applies to every step:

    **Your step function receives one argument:** the resolved `____Payload` for that step.
    If `____Payload` is a function, Twin calls it with the previous step's result at dispatch
    time and passes the returned value to the worker instead.

    **Your step function must return one value:** it becomes `Results[stepIndex]` in the
    final callback, and it is also the `prevResult` delivered to the next step's dynamic
    payload function.

    The required function signature for any step is:

    ```luau
    local StepModule = {}

    function StepModule.FunctionName(payload: any): any
        -- `payload` is the resolved ____Payload for this step.
        -- Whatever you return becomes Results[N] in the final Sequence callback
        -- and prevResult for the next step's ____Payload function.
        return processedValue
    end

    return StepModule
    ```

    **What arrives in your final callback:**

    | Argument | Type | Description |
    | :--- | :--- | :--- |
    | `Results` | `{ any }` | An ordered array where `Results[i]` is the return value of step `i`. `nil` at a position means that step's worker returned nothing or errored. |

!!! warning "The number of steps is unlimited — but each step re-enters the dispatch queue"
    A Sequence can contain any number of steps — ten, a hundred, or more. There is no
    enforced cap.

    However, Sequence steps are asynchronous. Each step is dispatched only after the previous
    step's worker finishes, and while that worker is running, Twin continues dispatching all
    other queued jobs normally. This means unrelated Split and BulkSplit jobs can complete in
    between your steps — a Sequence does not hold a lock on the worker pool.

    For chains with a large number of steps, this has a practical consequence: each handoff
    between steps involves re-entering the dispatch queue, waiting for a free worker, and
    competing with whatever else is queued at that moment. A Sequence with a hundred steps on
    a busy server may take considerably longer to finish than the same hundred operations run
    inside a single worker function that performs them all sequentially.

    **Guidance for long chains:**

    - If several consecutive steps are fast transformations on the same data, consolidate them
      into one worker function that performs all transformations internally. This eliminates
      the per-step queue re-entry and reduces total latency.
    - Reserve multi-step Sequences for pipelines where each step is genuinely heavy,
      operates on a different module, or where you need each intermediate result independently.
    - A chain of two to five steps is typically the sweet spot. Beyond ten steps, evaluate
      whether consolidation would serve the same goal with less overhead.

---

**Scenario A — Three-step data pipeline with static payloads**

The worker modules:

```luau
-- FetchModule (ModuleScript) — Step 1
local FetchModule = {}
function FetchModule.Load(payload)
    -- payload.datasetId identifies which dataset to load from a pre-cached store.
    -- Whatever is returned here becomes Results[1] in the final callback.
    return dataCache[payload.datasetId]
end
return FetchModule

-- TransformModule (ModuleScript) — Step 2
local TransformModule = {}
function TransformModule.Normalise(payload)
    -- payload.schema is the static ____Payload value defined on this step.
    -- Note: the previous step's result is NOT forwarded automatically with a static payload.
    -- Use a dynamic payload function (see Scenario B) to pass results between steps.
    return normaliseData(rawDataset, payload.schema)
end
return TransformModule

-- ValidateModule (ModuleScript) — Step 3
local ValidateModule = {}
function ValidateModule.Check(payload)
    -- payload is nil — this step inspects shared state set by the prior steps.
    return { valid = runValidation(), errors = collectErrors() }
end
return ValidateModule
```

The caller:

```luau
-- Each step runs only after the previous step's worker reports back.
Twin.Sequence({
    {
        ____Module       = FetchModule,
        ____FunctionName = "Load",
        ____Payload      = { datasetId = "zone_12" },
        ____Weight       = "heavy",
    },
    {
        ____Module       = TransformModule,
        ____FunctionName = "Normalise",
        ____Payload      = { schema = "v2" },
        -- Static payload: does not automatically use the previous step's result.
        -- Use a dynamic payload function (Scenario B) to forward results between steps.
    },
    {
        ____Module       = ValidateModule,
        ____FunctionName = "Check",
        ____Payload      = nil,
    },
}, function(results)
    -- results[1] = Load result, results[2] = Normalise result, results[3] = Check result
    if results[3].valid then
        applyDataset(results[1])
    end
end)
```

---

**Scenario B — Dynamic payload chaining (each step feeds the next)**

The worker modules:

```luau
-- AnalysisModule (ModuleScript) — Step 1
local AnalysisModule = {}
function AnalysisModule.Run(payload)
    -- payload is rawSensorData passed directly from the caller.
    -- Returns a feature vector that Step 2 will use.
    return { features = extractFeatures(payload), confidence = 0.85 }
end
return AnalysisModule

-- ClassifierModule (ModuleScript) — Step 2
local ClassifierModule = {}
function ClassifierModule.Classify(payload)
    -- payload is the table built by the dynamic ____Payload function for this step,
    -- which received AnalysisModule.Run's return value as `prevResult`.
    return { label = classify(payload.features, payload.threshold), score = payload.confidence }
end
return ClassifierModule

-- ActionModule (ModuleScript) — Step 3
local ActionModule = {}
function ActionModule.Decide(payload)
    -- payload is built from ClassifierModule.Classify's return value by the function below.
    return selectAction(payload.classification, payload.context)
end
return ActionModule
```

The caller:

```luau
-- The ____Payload on Steps 2 and 3 is a function.
-- Twin calls it at dispatch time with the previous step's result as the argument,
-- just before sending the job to a worker.
Twin.Sequence({
    {
        ____Module       = AnalysisModule,
        ____FunctionName = "Run",
        ____Payload      = rawSensorData,
    },
    {
        ____Module       = ClassifierModule,
        ____FunctionName = "Classify",
        ____Payload      = function(prevResult)
            -- prevResult is the return value of AnalysisModule.Run
            return { features = prevResult.features, threshold = 0.75, confidence = prevResult.confidence }
        end,
    },
    {
        ____Module       = ActionModule,
        ____FunctionName = "Decide",
        ____Payload      = function(prevResult)
            -- prevResult is the return value of ClassifierModule.Classify
            return { classification = prevResult, context = gameContext }
        end,
    },
}, function(results)
    executeDecision(results[3])
end)
```

---

**Scenario C — Cancellation mid-chain**

```luau
-- The chain is started when a round begins.
-- If the round ends before all steps complete, cancel cleanly.
local chainHandle = Twin.Sequence({
    { ____Module = StepA, ____FunctionName = "Run", ____Payload = roundData },
    { ____Module = StepB, ____FunctionName = "Run", ____Payload = nil },
    { ____Module = StepC, ____FunctionName = "Run", ____Payload = nil },
}, function(results)
    announceRoundResult(results)
end)

roundEnded.Event:Connect(function()
    -- Cancels the currently in-flight step and prevents any further steps from dispatching.
    -- The final callback never fires, regardless of which step was running.
    chainHandle.Disconnect()
end)
```

---

**Scenario D — Single-step sequence (equivalent to a named Split)**

```luau
-- A one-element Sequence behaves identically to a Split call.
-- Use Sequence when you may want to add pipeline steps later without restructuring.
Twin.Sequence({
    {
        ____Module       = ComputeModule,
        ____FunctionName = "Calculate",
        ____Payload      = inputParams,
        ____Weight       = "light",
    },
}, function(results)
    applyResult(results[1])
end)
```

---

## Twin.Report

Returns a health snapshot of the scheduler. Always returns `nil` when telemetry is disabled
in configuration. Call at any frequency without affecting the sample buffer.

---

**Scenario A — Periodic health logging**

```luau
-- Log the overall scheduler health every 10 seconds.
-- TELEMETRY_ENABLED must be true in TwinConfiguration for this to return data.
task.spawn(function()
    while true do
        task.wait(10)
        local report = Twin.Report()
        if report then
            print(("Twin health [%s] over %.1fs (%d samples)"):format(
                report.Overall,
                report.WindowSec,
                report.SampleCount
            ))
        end
    end
end)
```

---

**Scenario B — Drilling into specific groups on a Red signal**

```luau
local report = Twin.Report()
if not report then return end -- telemetry disabled or no frames sampled yet

if report.Overall == "Red" then
    -- Find which group is causing the alert and log actionable details.
    if report.Pools.Status == "Red" then
        print("Pool pressure detected:")
        print("  ResultBuffer free:", report.Pools.ResultBuffer.Value, "/", report.Pools.ResultBuffer.Capacity)
        print("  BulkBatch free:", report.Pools.BulkBatch.Value, "/", report.Pools.BulkBatch.Capacity)
    end

    if report.Queues.Status == "Red" then
        print("Queue backlog detected:")
        print("  Heavy queue peak depth:", report.Queues.Heavy.Value)
        print("  BulkNormal queue peak depth:", report.Queues.BulkNormal.Value)
    end

    if report.Workers.Status == "Red" then
        print("Worker performance degraded:")
        print("  Watchdog recoveries this window:", report.Workers.WatchdogInterventions.Value)
        for workerId, execEntry in report.Workers.AvgExecTime do
            if execEntry.Status ~= "Healthy" then
                print(("  Worker %d avg exec time: %.3fs [%s]"):format(
                    workerId, execEntry.Value, execEntry.Status
                ))
            end
        end
    end

    if report.Starvation.Status == "Red" then
        print("Starvation detected:")
        print("  Heavy jobs skipped (peak):", report.Starvation.HeavySkipCount.Value)
        print("  Background jobs skipped (peak):", report.Starvation.BgSkipCount.Value)
    end
end
```

---

**Scenario C — Guard: telemetry disabled**

```luau
-- Always guard against nil — Report() returns nil when telemetry is off.
local function checkHealth()
    local report = Twin.Report()
    if not report then
        -- Either TELEMETRY_ENABLED is false, or startup just occurred with no frames yet.
        return
    end
    -- Safe to read report fields here.
    return report.Overall
end
```

---

## Twin.Inject

Replaces Twin's internal task scheduler with an external library. Only `"Assignment"` is
currently supported. Any functions the library does not provide fall back to Roblox's `task`
equivalents automatically.

---

**Scenario A — Injecting the Assignment scheduler at startup**

```luau
-- Call Inject once, as early as possible, before any Twin.Split / BulkSplit calls.
-- ModuleTableObject must be the table returned by require(AssignmentModule).
local Assignment = require(AssignmentModule)
Twin.Inject("Assignment", Assignment)

-- All subsequent Twin calls now route through Assignment's scheduler
-- for spawn, defer, delay, wait, cancel, and repeat operations.
Twin.Split(WorkModule, "DoWork", payload, function(result)
    handleResult(result)
end)
```

---

**Scenario B — Partial injection (missing functions fall back gracefully)**

```luau
-- If Assignment only provides some of the scheduler functions,
-- Twin fills in any gaps with Roblox's native task library automatically.
-- You do not need to implement every function.
local PartialScheduler = {
    Spawn = Assignment.Spawn,
    Wait  = Assignment.Wait,
    -- Defer, Delay and Cancel will fall back to task.defer, task.delay, etc.
}
Twin.Inject("Assignment", PartialScheduler)
```