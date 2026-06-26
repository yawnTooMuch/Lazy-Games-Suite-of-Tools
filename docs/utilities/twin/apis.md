# API Reference

Complete reference for all public functions and exported types in the Twin framework.

---

## Summary

### Dispatch Methods

_Send work to parallel workers. All three methods return a [`Handle`](#handle) that cancels
the job when `Disconnect()` is called._

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Twin.Split](#twinsplit)** | `Handle` | Dispatches a single parallel job and delivers the result to a callback in the same frame the worker finishes. |
| **[Twin.BulkSplit](#twinbulksplit)** | `Handle` | Dispatches a list of items out across all workers in parallel and reassembles the results in original order. |
| **[Twin.Sequence](#twinsequence)** | `Handle` | Runs an ordered chain of parallel jobs where each step receives the previous step's result. |

### Utility Methods

| Name | Returns | Description |
| :--- | :--- | :--- |
| **[Twin.Report](#twinreport)** | `TelemetryReport?` | Returns a structured health snapshot of the scheduler's current state, or `nil` when telemetry is disabled. |
| **[Twin.GetTaskLoad](#twingettaskload)** | `{ Environment: string, MainThread: number, Workers: { number } }` | Returns the Job Manager's live CPU utilization snapshot for the main thread and all workers. |
| **[Twin.Inject](#twininject)** | `void` | Replaces Twin's internal task scheduler with an external library from the Lazy Games Suite. |

---

## Dispatch Methods

---

#### Twin.Split

```luau
Twin.Split(
    Module       : ModuleScript,
    FunctionName : string,
    Payload      : any,
    Callback     : SplitCallback,
    Options      : SplitOptions?
): Handle
```

Dispatches a single parallel job and delivers the result to a callback in the same frame the
worker finishes. The job is sent to the best available worker. When the worker completes, the
callback fires synchronously on the main thread with no additional frame delay.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Module` | `ModuleScript` | The ModuleScript that contains the function to run. This module is required inside the worker. |
| `FunctionName` | `string` | The name of the function to call on the module. Must be a function that accepts a single argument and returns a single value. |
| `Payload` | `any` | The value passed to the worker function as its only argument. |
| `Callback` | `SplitCallback` | Called with the function's return value when the job completes. Must not yield. |
| `Options` | `SplitOptions?` | (Optional) Table controlling dispatch weight. See [`SplitOptions`](#splitoptions). |

**Returns:**

| Type | Description |
| :--- | :--- |
| `Handle` | Call `Disconnect()` on this to cancel the job before it runs, or to suppress the callback if the job is already in flight. |

!!! warning "Callback Must Not Yield"
    The callback fires directly on the main thread. Calling `task.wait`, `coroutine.yield`, or
    any other yielding function inside the callback will cause an error. Perform only
    synchronous work — update state, fire events, enqueue a new job — and return immediately.

!!! info "Weight: Heavy vs Light"
    The default weight is `"heavy"`. Heavy jobs wait until all bulk work in flight has
    finished before occupying a worker. Use `"heavy"` for expensive jobs that should not
    compete with BulkSplit throughput.

    Set `____Weight = "light"` for jobs that are fast and non-blocking. Light jobs are allowed
    to run speculatively alongside active bulk work when the scheduler detects that a bulk
    worker is slow or a deadline has been exceeded. Light jobs also benefit from starvation
    protection: if a heavy job has been waiting too long, it is automatically promoted to the
    light lane.

!!! note "Studio Validation"
    When running in Roblox Studio, Twin validates that `FunctionName` exists in `Module` and
    is callable before the job is enqueued. This check does not run in live servers or
    published clients.

!!! warning "Worker Errors Deliver nil"
    If the worker function throws an error, Twin catches it via `pcall`, logs a warning to
    the output, and delivers `nil` as the `Result` to your callback. Guard against `nil` in
    your callback whenever the worker function might fail.

---

#### Twin.BulkSplit

```luau
Twin.BulkSplit(
    Module       : ModuleScript,
    FunctionName : string,
    Items        : { any },
    Callback     : BulkCallback,
    Options      : BulkOptions?
): Handle
```

Dispatches a list of items out across all workers in parallel and reassembles the results in
original order. The items list is automatically divided into batches and distributed across
every available worker. When every worker has reported back, the callback fires with a single
result table where `results` is identical to `items` fully assembled back automatically.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Module` | `ModuleScript` | The ModuleScript containing the batch function to run on each slice. |
| `FunctionName` | `string` | The name of the batch function. Its signature must be `(slice: { any }, sharedArgs: any?) -> { any }`, returning a result table the same length as the slice. |
| `Items` | `{ any }` | The full list of inputs to distribute. The list is sliced and each slice is sent to a separate worker. |
| `Callback` | `BulkCallback` | Called with the reassembled results table when all workers have finished. See the warning below about buffer lifetime. |
| `Options` | `BulkOptions?` | (Optional) Table controlling batch size, shared arguments, deadline, and priority. See [`BulkOptions`](#bulkoptions). |

**Returns:**

| Type | Description |
| :--- | :--- |
| `Handle` | Call `Disconnect()` on this to cancel all remaining batches. Batches already delivered to workers will finish, but the callback will never fire. |

!!! danger "Do Not Store the Result Buffer"
    The results table passed to your callback is a pooled buffer. Twin schedules it for
    recycling after your callback returns — treat the buffer as invalid the moment your
    callback exits. Storing the table reference — assigning it to a module-level variable,
    inserting it into another table, capturing it in a closure — will cause that variable to
    be silently overwritten once the buffer is reused by a future job. Copy any values you
    need before the callback exits.

    ```luau
    -- Wrong — the table will be overwritten
    Twin.BulkSplit(Mod, "Compute", items, function(results)
        self.cachedResults = results
    end)

    -- Correct — copy what you need immediately
    Twin.BulkSplit(Mod, "Compute", items, function(results)
        table.move(results, 1, #results, 1, self.cachedResults)
    end)
    ```

!!! warning "Empty Input Fires Immediately"
    Passing an empty `Items` table causes the callback to fire synchronously before
    `BulkSplit` returns, with an empty result table. No workers are involved.

!!! info "Batch Function Contract"
    The function named by `FunctionName` receives a _slice_ of the original item list (not
    the full list) plus the optional `SharedArgs` value. It must return a table of the same
    length as the slice. Twin uses the `StartIndex` of each slice to place results back into
    the correct positions in the final buffer, so returning a mis-sized table will silently
    produce `nil` gaps in the results.

!!! info "Priority Scheduling"
    BulkSplit jobs are queued in one of three priority lanes: `"critical"`, `"normal"`, or
    `"background"`. Workers always drain critical jobs first, then normal, then background.
    Background jobs are never starved indefinitely — they are periodically force-promoted
    regardless of what else is queued.

!!! warning "Worker Errors Produce nil Entries"
    If a batch function throws an error, Twin catches it, logs a warning, and treats that
    batch's result as `nil`. Affected indices in the reassembled results table will contain
    `nil`. Guard against nil entries in your callback if the batch function can fail.

---

#### Twin.Sequence

```luau
Twin.Sequence(
    Steps    : { ChainStep },
    Callback : SequenceCallback
): Handle
```

Runs an ordered chain of parallel jobs where each step can receive the previous step's result via dynamic payload. Steps are dispatched one at a time, in order. Step 2 only dispatches after Step 1's worker finishes; Step 3 only dispatches after Step 2, and so on. The final callback receives a table
containing every step's result in order: `results[1]` is Step 1's result, `results[2]` is
Step 2's, and so on.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `Steps` | `{ ChainStep }` | An ordered array of step descriptors. Each step specifies the module, function name, payload, and optional weight. See [`ChainStep`](#chainstep). |
| `Callback` | `SequenceCallback` | Called with all step results in order when the last step completes. |

**Returns:**

| Type | Description |
| :--- | :--- |
| `Handle` | Call `Disconnect()` to cancel the chain at any point. The current in-flight step is cancelled, and no further steps are dispatched. The final callback never fires. |

!!! info "Dynamic Payloads"
    The `____Payload` field on a step may be a plain value **or** a function. If it is a
    function, Twin calls it with the previous step's result at dispatch time — just before
    the step is sent to a worker — and uses the return value as the actual payload. This lets
    you build pipelines where each step's input depends on the previous step's output without
    writing nested callbacks.

    ```luau
    {
        ____Module       = SomeModule,
        ____FunctionName = "Transform",
        ____Payload      = function(prevResult)
            return { input = prevResult, scale = 2 }
        end,
    }
    ```

!!! warning "Payload Function Errors Stop the Chain"
    If a dynamic payload function throws an error, the chain halts at that step and the final
    callback never fires. Only payload function errors stop the chain entirely.

!!! warning "Worker Errors Set the Step Result to nil"
    If a step's worker function throws an error, Twin catches it, logs a warning, and sets
    that step's result to `nil` in the final `Results` array. A worker error does not halt
    the chain — subsequent steps still dispatch. Check each entry in `Results` if any step's
    worker function might fail.

---

## Utility Methods

---

#### Twin.Report

```luau
Twin.Report(): TelemetryReport?
```

Returns a structured health snapshot of the scheduler's current state, or `nil` when
telemetry is disabled. The snapshot is computed from a rolling window of sampled frames.
Calling `Report` is safe at any frequency and does not reset the sample buffer.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `TelemetryReport?` | A full health report across pools, queues, workers, the frame governor, and starvation counters. `nil` if telemetry is disabled in configuration or if no frames have been sampled yet. |

!!! note "Telemetry Must Be Enabled"
    Telemetry sampling is disabled by default. To receive non-nil reports, set
    `TELEMETRY_ENABLED = true` in `TwinConfiguration` at the top of the Twin source. When
    disabled, all sampling overhead is eliminated — `Report()` returns `nil` immediately with
    no computation.

!!! info "Reading the Report"
    Each metric in the report carries a `Status` field: `"Healthy"`, `"Warm"`, or
    `"Overloaded"`. Each group (Pools, Queues, Workers, FrameGovernor, Starvation) rolls up
    to a `"Green"`, `"Yellow"`, or `"Red"` group status. The top-level `Overall` field is
    the worst group status across all five groups. Use `Overall == "Red"` as your alert
    threshold and drill into the individual groups to find the cause.

---

#### Twin.GetTaskLoad

```luau
Twin.GetTaskLoad(): { Environment: string, MainThread: number, Workers: { number } }
```

Returns a lightweight, instantaneous snapshot of the Job Manager's live CPU utilization.
Unlike `Twin.Report`, this call reads directly from a pre-computed report table updated once
per second — it performs no ring-buffer computation and carries zero overhead.

**Parameters:** `void`

**Returns:**

| Type | Description |
| :--- | :--- |
| `{ Environment: string, MainThread: number, Workers: { number } }` | A table containing the execution context, main-thread script cost, and a per-worker utilization array. |

**Return table fields:**

| Field | Type | Description |
| :--- | :--- | :--- |
| `Environment` | `string` | `"Server"` or `"Client"`, indicating which context this instance is running in. |
| `MainThread` | `number` | Main-thread script time as a percentage over the last one-second window (e.g. `2.34` means 2.34%). |
| `Workers` | `{ number }` | Array where index `i` is Worker `i`'s busy-frame percentage over the last one-second window (e.g. `Workers[1] = 80` means Worker 1 was busy 80% of sampled frames). |

!!! note "Job Manager Must Be Enabled"
    `GetTaskLoad` reads the report table produced by the Job Manager. If `JOB_MANAGER_ENABLED`
    is `false`, this table is never populated and all fields remain at their zero state. The
    Job Manager is enabled by default.

!!! info "One-Second Resolution"
    The report table updates once per second. Calling `GetTaskLoad` more frequently returns
    the same snapshot until the next one-second window closes.

---

#### Twin.Inject

```luau
Twin.Inject(ModuleName: string, ModuleTableObject: any): ()
```

Injects an external library within the Lazy Games Suite of Tools environment. Currently supports the "Assignment" library.

**Parameters:**

| Name | Type | Description |
| :--- | :--- | :--- |
| `ModuleName` | `string` | The name of the ModuleScript file. |
| `ModuleTableObject` | `any` | The required module table/object to inject. |

**Returns:** `void`

!!! tip "When to Use Inject"
    Only call `Inject` if your project uses the Assignment scheduler from the Lazy Games
    Suite and you need Twin's internal coroutine management to participate in the same
    scheduling budget. For all other projects, skip `Inject` entirely.

---

## Exported Types

---

### Handle

```luau
export type Handle = {
    Disconnect : () -> ()
}
```

Returned by [`Twin.Split`](#twinsplit), [`Twin.BulkSplit`](#twinbulksplit), and
[`Twin.Sequence`](#twinsequence). Call `Disconnect()` to cancel the associated job or chain.

Cancellation is immediate from your code's perspective: the callback will never fire after
`Disconnect()` is called. If a worker is already running the job, the worker finishes
normally, but its result is silently discarded.

---

### SplitCallback

```luau
export type SplitCallback = (Result: any) -> ()
```

The callback type for [`Twin.Split`](#twinsplit). Receives the single return value of the
worker function. Must not yield.

---

### BulkCallback

```luau
export type BulkCallback = (Results: { any }) -> ()
```

The callback type for [`Twin.BulkSplit`](#twinbulksplit). Receives the reassembled results
table. The table is a pooled buffer — see the danger admonition on `BulkSplit` for the
lifetime rule.

---

### SequenceCallback

```luau
export type SequenceCallback = (Results: { any }) -> ()
```

The callback type for [`Twin.Sequence`](#twinsequence). Receives an array where index `i`
holds the result returned by step `i`.

---

### SplitOptions

```luau
export type SplitOptions = {
    ____Weight : ("light" | "heavy")?
}
```

Optional options table for [`Twin.Split`](#twinsplit).

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `____Weight` | `"light" | "heavy"` | `"heavy"` | Controls whether this job waits for all bulk work to clear (`"heavy"`) or may run speculatively alongside active bulk jobs (`"light"`). |

---

### BulkPriority

```luau
export type BulkPriority = "critical" | "normal" | "background"
```

Dispatch priority for [`Twin.BulkSplit`](#twinbulksplit).

| Value | Behaviour |
| :--- | :--- |
| `"critical"` | Dispatched before all other queued bulk jobs. Use for work that is blocking player-visible systems. |
| `"normal"` | Default priority. Dispatched after critical jobs clear. |
| `"background"` | Dispatched only when no critical or normal jobs are waiting, but periodically promoted to prevent indefinite starvation. |

---

### BulkOptions

```luau
export type BulkOptions = {
    ____BatchSize   : number?,
    ____SharedArgs  : any?,
    ____MaxWaitTime : number?,
    ____Priority    : BulkPriority?
}
```

Optional options table for [`Twin.BulkSplit`](#twinbulksplit).

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `____BatchSize` | `number?` | `ceil(itemCount / workerCount)` | How many items to place in each batch. Smaller batches mean more workers are used; larger batches reduce overhead but reduce parallelism. |
| `____SharedArgs` | `any?` | `nil` | A value passed as the second argument to every batch function call alongside the slice. Use this for configuration that applies to all items equally — a timestamp, a ruleset, a reference object. |
| `____MaxWaitTime` | `number?` | `0.050` seconds | The deadline after which a waiting bulk job may preempt single-job dispatch, allowing its batches to reach workers faster. |
| `____Priority` | `BulkPriority?` | `"normal"` | The priority lane to place this job in. See [`BulkPriority`](#bulkpriority). |

---

### ChainStep

```luau
export type ChainStep = {
    ____Module       : ModuleScript,
    ____FunctionName : string,
    ____Payload      : any?,
    ____Weight       : ("light" | "heavy")?
}
```

One step in a [`Twin.Sequence`](#twinsequence) chain.

| Field | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `____Module` | `ModuleScript?` | — | **Required.** The module containing the function to run for this step. |
| `____FunctionName` | `string?` | — | **Required.** The name of the function on the module to call. |
| `____Payload` | `any?` | `nil` | The value passed to the worker function. May be a plain value, or a function `(prevResult: any) -> any` that is called at dispatch time with the previous step's result. |
| `____Weight` | `"light" | "heavy"?` | `"heavy"` | Dispatch weight for this step. See the Weight description on [`SplitOptions`](#splitoptions). |

---

### TelemetryReport

```luau
export type TelemetryReport = {
    Pools         : { ... },
    Queues        : { ... },
    Workers       : { ... },
    FrameGovernor : { ... },
    Starvation    : { ... },
    Overall       : TelemetryGroupStatus,
    WindowSec     : number,
    SampleCount   : number,
    Timestamp     : number,
}
```

Returned by [`Twin.Report`](#twinreport). Contains five group sub-tables plus three
top-level summary fields.

**Top-level fields:**

| Field | Type | Description |
| :--- | :--- | :--- |
| `Overall` | `TelemetryGroupStatus` | The worst status across all five groups. `"Green"` means all groups are healthy. `"Yellow"` means at least one group is warm. `"Red"` means at least one group is overloaded. |
| `WindowSec` | `number` | How many seconds have elapsed since the last time `Report()` was called (or since startup, if this is the first call). |
| `SampleCount` | `number` | Number of Heartbeat frames included in the current ring buffer. |
| `Timestamp` | `number` | The `os.clock()` value at the moment the report was generated. |

**Pools group** — health of each pre-allocated pool. Low free slots indicate heavy throughput
or a pool size that needs tuning.

| Field | Type | Description |
| :--- | :--- | :--- |
| `Pools.Node` | `TelemetryPoolEntry` | Queue node pool: `Value` = free slots, `Capacity` = total slots, `Status` = health. |
| `Pools.SingleJob` | `TelemetryPoolEntry` | Single-job descriptor pool. |
| `Pools.BulkEntry` | `TelemetryPoolEntry` | Bulk-job descriptor pool. |
| `Pools.BulkBatch` | `TelemetryPoolEntry` | Batch descriptor pool. |
| `Pools.ResultBuffer` | `TelemetryPoolEntry` | Result buffer pool. |
| `Pools.Status` | `TelemetryGroupStatus` | Worst pool status. |

**Queues group** — peak queue depths over the sample window. Deep queues indicate more work
is arriving than workers can handle.

| Field | Type | Description |
| :--- | :--- | :--- |
| `Queues.Light` | `TelemetryQueueEntry` | Peak depth of the lightweight single-job queue. |
| `Queues.Heavy` | `TelemetryQueueEntry` | Peak depth of the heavyweight single-job queue. |
| `Queues.BulkCritical` | `TelemetryQueueEntry` | Peak depth of the critical bulk queue. |
| `Queues.BulkNormal` | `TelemetryQueueEntry` | Peak depth of the normal-priority bulk queue. |
| `Queues.BulkBackground` | `TelemetryQueueEntry` | Peak depth of the background bulk queue. |
| `Queues.Status` | `TelemetryGroupStatus` | Worst queue status. |

**Workers group** — worker count and average execution times.

| Field | Type | Description |
| :--- | :--- | :--- |
| `Workers.Total` | `number` | Total number of workers in the pool. |
| `Workers.Free` | `number` | Workers not currently running a job (latest sample). |
| `Workers.Busy` | `number` | Workers currently running a job (latest sample). |
| `Workers.AvgExecTime` | `{ [number]: TelemetryWorkerExec }` | Per-worker mean execution time (seconds) over the sample window, with a health status per worker. |
| `Workers.WatchdogInterventions` | `{ Value: number, Status: TelemetryStatus }` | Total number of unresponsive-worker recoveries in the sample window. |
| `Workers.Status` | `TelemetryGroupStatus` | Worst worker status. |

**FrameGovernor group** — main-thread dispatch budget.

| Field | Type | Description |
| :--- | :--- | :--- |
| `FrameGovernor.BudgetMs` | `{ Value: number, Status: TelemetryStatus }` | The configured per-frame dispatch budget in milliseconds. Status is always `"Healthy"` (this is a fixed configuration value). |
| `FrameGovernor.OverBudgetRate` | `{ Value: number, Status: TelemetryStatus }` | Fraction of sampled frames where the budget was exceeded (0.0–1.0). High values mean the main thread is spending too much time on dispatch. |
| `FrameGovernor.ActiveBulkCount` | `{ Value: number, Status: TelemetryStatus }` | Peak number of bulk jobs in flight at the same time during the sample window. |
| `FrameGovernor.Status` | `TelemetryGroupStatus` | Worst frame governor status. |

**Starvation group** — skip counters for lower-priority work.

| Field | Type | Description |
| :--- | :--- | :--- |
| `Starvation.BgSkipCount` | `{ Value: number, Status: TelemetryStatus }` | Peak number of consecutive frames a background bulk job was skipped in favour of higher-priority work. |
| `Starvation.HeavySkipCount` | `{ Value: number, Status: TelemetryStatus }` | Peak number of consecutive frames a heavy single job was skipped while bulk work was active. |
| `Starvation.Status` | `TelemetryGroupStatus` | Worst starvation status. |

---

### TelemetryStatus

```luau
export type TelemetryStatus = "Healthy" | "Warm" | "Overloaded"
```

Health status for an individual metric. `"Warm"` means the value has crossed the warning
threshold. `"Overloaded"` means it has crossed the critical threshold.

---

### TelemetryGroupStatus

```luau
export type TelemetryGroupStatus = "Green" | "Yellow" | "Red"
```

Rolled-up health status for a group of metrics. `"Yellow"` if any metric in the group is
`"Warm"`. `"Red"` if any metric is `"Overloaded"`.

---

### TelemetryPoolEntry

```luau
export type TelemetryPoolEntry = {
    Value    : number,
    Capacity : number,
    Status   : TelemetryStatus,
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `Value` | `number` | Current number of free (available) slots in the pool. |
| `Capacity` | `number` | Total pool capacity as configured. |
| `Status` | `TelemetryStatus` | Health derived from the ratio of free slots to capacity. |

---

### TelemetryQueueEntry

```luau
export type TelemetryQueueEntry = {
    Value  : number,
    Status : TelemetryStatus,
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `Value` | `number` | Peak queue depth over the sample window. |
| `Status` | `TelemetryStatus` | Health derived from the peak depth against configured warn and critical thresholds. |

---

### TelemetryWorkerExec

```luau
export type TelemetryWorkerExec = {
    Value  : number,
    Status : TelemetryStatus,
}
```

| Field | Type | Description |
| :--- | :--- | :--- |
| `Value` | `number` | Mean execution time for this worker in seconds, averaged over the sample window using an exponential moving average. |
| `Status` | `TelemetryStatus` | Health derived from the mean execution time against configured warn and critical thresholds. |

---

## Configuration

All configuration constants are defined in the `TwinConfiguration` block at the top of the
Twin source file. Edit them directly before deploying. No external config file is required.

Constants that default to `game:GetService("RunService"):IsStudio()` are active only in
Roblox Studio and automatically inactive in live servers and published clients.

---

### Worker Pool

Controls how many parallel Actor workers Twin spawns at startup. Workers are the execution
kernels that run your functions off the main thread. Spawning more workers increases
throughput for concurrent jobs but also increases memory overhead and Actor initialization
time.

| Constant | Default | Description |
| :--- | :--- | :--- |
| `SERVER_WORKER_COUNT` | `3` | Number of parallel Actor workers spawned on the server. Server workloads are typically lower-frequency than client-side simulation, so a smaller pool is the default. |
| `CLIENT_WORKER_COUNT` | `5` | Number of parallel Actor workers spawned on the client. Higher than the server default to accommodate the greater job throughput typical of client-side simulation. |

!!! tip "Understanding server and client worker counts"
    **On the server**, adding more workers does not grant more CPU cores.
    Roblox allocates server cores based exclusively on a game's maximum player
    count — not on whether parallel Luau is used. Community testing has
    established the following approximate scale: 1–19 players receive 1 core,
    20+ players receive 2, 30+ players receive 3, and 100 players receive 5.
    This is by design; a Roblox engine engineer confirmed in 2025 that reducing
    thread count actually improved performance for most games due to thread
    switching costs and cache pressure from under-utilized cores. `SERVER_WORKER_COUNT`
    should not exceed the core count your player cap realistically earns —
    workers beyond that share the same core and add contention with no throughput
    gain. The default of `3` aligns with the allocation for a 30-player server.

    **On the client**, there is no equivalent platform restriction. Workers run
    on the player's own hardware, which varies widely. When scoping
    `CLIENT_WORKER_COUNT`, the developer should assess the range of devices their
    audience is likely to use. A minimum gaming device — an entry-level PC or
    current-generation mobile — typically has between 5 and 7 CPU cores available.
    `5` is therefore a reasonable conservative floor for most games, with higher
    values appropriate if the game's minimum supported device is known to have
    more cores.

---

### Dispatch Behavior

Controls how the scheduler prioritises, promotes, and gates work each frame.

| Constant | Default | Description |
| :--- | :--- | :--- |
| `ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE` | Studio only | When true, validates all parameters on every API call and raises a descriptive error if a value is the wrong type or missing. Has no runtime cost outside Studio. |
| `ENABLE_TYPO_POLICE` | Studio only | When true, requires and inspects the target ModuleScript before enqueueing a job, catching missing function names early. Has no runtime cost outside Studio. |
| `DEFAULT_MAX_WAIT` | `0.050` | The fallback `____MaxWaitTime` used by `BulkSplit` calls that do not provide their own. A bulk job waiting longer than this may preempt single-job dispatch to reach workers faster. In seconds. |
| `STARVATION_THRESHOLD` | `10` | Number of consecutive frames a heavy single job may be skipped while bulk work is active before being force-promoted to the light lane. |
| `BG_STARVATION_THRESHOLD` | `50` | Number of consecutive frames a background bulk job may be skipped before being force-promoted past normal-priority bulk work. |
| `SPECULATIVE_THRESHOLD` | `0.016` | Average worker execution time in seconds above which the scheduler treats a worker as running slow and allows light single jobs to dispatch speculatively alongside active bulk work. |
| `EMA_ALPHA` | `0.25` | Smoothing factor for the per-worker exponential moving average of execution time. Higher values make the average react faster to recent samples; lower values smooth over spikes. |
| `FRAME_BUDGET_SEC` | `0.017` | Maximum main-thread time in seconds Twin may spend dispatching single jobs in a single frame. Bulk batch dispatch is exempt from this gate. |

---

### Memory Pools

Twin pre-allocates all internal objects at startup and recycles them after each job. Pool
sizes are fixed at startup. A pool that runs out of free slots will cause dispatch to stall
until a slot is released, which is reported as `"Overloaded"` in `Twin.Report()`.

| Constant | Default | Description |
| :--- | :--- | :--- |
| `NODE_POOL_SIZE` | `256` | Pre-allocated queue node structs used to link jobs in the dispatch queues. One node is consumed per queued job and returned when the job is dispatched. |
| `SINGLE_JOB_POOL_SIZE` | `64` | Pre-allocated job descriptor structs for `Split` and `Sequence` step jobs. One is borrowed per in-flight single job. |
| `BULK_ENTRY_POOL_SIZE` | `16` | Pre-allocated master descriptors for `BulkSplit` jobs. One is borrowed per active `BulkSplit` call and returned when all batches complete. This caps how many concurrent `BulkSplit` calls can be in flight simultaneously. |
| `BULK_BATCH_POOL_SIZE` | `64` | Pre-allocated batch slice descriptors. One is borrowed per in-flight batch sent to a worker. |
| `RESULT_BUFFER_POOL_SIZE` | `16` | Pre-allocated result arrays returned to `BulkSplit` callbacks. Caps how many `BulkSplit` results can be in the delivery pipeline at once. |
| `MAX_BATCH_SIZE` | `256` | Hard upper limit on items placed in a single batch slice. Batch size is calculated automatically from item count and worker count, but this constant prevents any single batch from growing larger than this value. |
| `MAX_RESULT_ITEMS` | `1024` | The pre-allocated slot count of each result buffer. A `BulkSplit` job with more items than this value cannot use the pool and will allocate a temporary table instead. |

!!! tip "Sizing the pools"
    Pool sizes should be at least as large as the maximum number of concurrent jobs you
    expect to have in flight simultaneously. For example, if your game can have up to 8
    concurrent `BulkSplit` calls active at the same time, `BULK_ENTRY_POOL_SIZE` should be
    at least `8`. Use `Twin.Report()` with telemetry enabled to observe peak pool usage and
    tune accordingly.

---

### Telemetry

Controls whether and how Twin samples its own internal state for health reporting.

| Constant | Default | Description |
| :--- | :--- | :--- |
| `TELEMETRY_ENABLED` | Studio only | Master switch for all telemetry sampling. When `false`, no frame samples are taken, the ring buffer is not populated, and `Twin.Report()` returns `nil` immediately with no computation. Set to `true` in production if live health monitoring is needed. |
| `TELEMETRY_FLUSH_INTERVAL` | `10` | Seconds between automatic telemetry window resets. After each reset, `Twin.Report()` reflects only samples taken since the last flush. |
| `TELEMETRY_MAX_DEFER_SEC` | `30` | Maximum seconds the flush coroutine may wait before forcing a flush, regardless of activity. |
| `TELEMETRY_RING_SIZE` | `600` | Number of Heartbeat frame samples held in the rolling buffer. At 60 fps, `600` represents a 10-second window. Increasing this value captures longer trends at the cost of more memory. |

---

### Job Manager

Controls the in-game CPU utilization overlay.

| Constant | Default | Description |
| :--- | :--- | :--- |
| `JOB_MANAGER_ENABLED` | `true` | Master switch for the Job Manager overlay. When `true`, Twin generates a `ScreenGui` at startup showing live main-thread and per-worker CPU utilization, updated every second. Set to `false` to suppress the overlay entirely. |

---

### Watchdog

Controls the background scan that detects and recovers unresponsive workers.

| Constant | Default | Description |
| :--- | :--- | :--- |
| `WATCHDOG_ENABLED` | `true` | Master switch for the watchdog recovery system. When `false`, hung workers are never detected and in-flight jobs will wait indefinitely. Only disable if you have confirmed the watchdog is interfering with intentionally long-running jobs. |
| `WATCHDOG_TIMEOUT` | `5.0` | Seconds a worker may be continuously busy before being declared unresponsive. When the timeout is exceeded, the worker is freed, its generation tag is incremented (invalidating any late response), and the job is re-queued. |
| `WATCHDOG_INTERVAL` | `1.0` | Seconds between watchdog scans. Each scan checks every worker and recovers any that have exceeded `WATCHDOG_TIMEOUT`. Lower values detect hangs faster but add a small recurring main-thread cost. |

!!! tip "Setting the timeout"
    `WATCHDOG_TIMEOUT` should be comfortably above the longest legitimate worker execution
    time you expect. If your most expensive worker function takes up to 500ms, set
    `WATCHDOG_TIMEOUT` to at least `2.0` seconds to avoid false recoveries. Use
    `report.Workers.AvgExecTime` from `Twin.Report()` to measure observed execution times
    before tuning this value.

---

### Health Status Thresholds

These constants define the numeric boundaries that determine whether each telemetry metric
is graded `"Healthy"`, `"Warm"`, or `"Overloaded"` in `Twin.Report()`. Crossing the `WARN`
boundary produces `"Warm"`; crossing the `CRIT` boundary produces `"Overloaded"`.

#### Pool Health

Thresholds are expressed as a ratio of free slots to total pool capacity. A ratio of `0.20`
means the pool is `"Overloaded"` when fewer than 20% of its slots are free.

| Constant | Default | Meaning |
| :--- | :--- | :--- |
| `POOL_WARN_RATIO` | `0.50` | A pool with fewer than 50% free slots is `"Warm"`. |
| `POOL_CRIT_RATIO` | `0.20` | A pool with fewer than 20% free slots is `"Overloaded"`. |

#### Queue Health

Thresholds are expressed as absolute peak queue depth over the sample window.

| Constant | Default | Meaning |
| :--- | :--- | :--- |
| `QUEUE_WARN_DEPTH` | `10` | A queue that reached a peak depth of 10 or more is `"Warm"`. |
| `QUEUE_CRIT_DEPTH` | `25` | A queue that reached a peak depth of 25 or more is `"Overloaded"`. |

#### Worker Execution Time Health

Thresholds are expressed in seconds of mean execution time per worker.

| Constant | Default | Meaning |
| :--- | :--- | :--- |
| `WORKER_WARN_EXEC` | `0.016` | A worker averaging 16ms or more per job is `"Warm"`. |
| `WORKER_CRIT_EXEC` | `0.030` | A worker averaging 30ms or more per job is `"Overloaded"`. |

#### Frame Governor Health

Thresholds are expressed as a fraction of sampled frames that exceeded the dispatch budget.

| Constant | Default | Meaning |
| :--- | :--- | :--- |
| `OVER_BUDGET_RATE_WARN` | `0.05` | Budget exceeded in 5% or more of sampled frames → `"Warm"`. |
| `OVER_BUDGET_RATE_CRIT` | `0.20` | Budget exceeded in 20% or more of sampled frames → `"Overloaded"`. |

Peak concurrent bulk job count:

| Constant | Default | Meaning |
| :--- | :--- | :--- |
| `ACTIVE_BULK_WARN` | `1` | One or more concurrent bulk jobs in flight → `"Warm"`. |
| `ACTIVE_BULK_CRIT` | `3` | Three or more concurrent bulk jobs in flight → `"Overloaded"`. |

#### Starvation Health

Thresholds are expressed as peak consecutive skip counts over the sample window.

| Constant | Default | Meaning |
| :--- | :--- | :--- |
| `BG_SKIP_WARN` | `20` | A background bulk job skipped 20 or more consecutive frames → `"Warm"`. |
| `BG_SKIP_CRITICAL` | `45` | A background bulk job skipped 45 or more consecutive frames → `"Overloaded"`. |
| `HEAVY_SKIP_WARN` | `5` | A heavy single job skipped 5 or more consecutive frames → `"Warm"`. |
| `HEAVY_SKIP_CRITICAL` | `8` | A heavy single job skipped 8 or more consecutive frames → `"Overloaded"`. |

#### Watchdog Intervention Health

| Constant | Default | Meaning |
| :--- | :--- | :--- |
| `WATCHDOG_INTERVENTIONS_WARN` | `1` | One or more watchdog recoveries in the sample window → `"Warm"`. |
| `WATCHDOG_INTERVENTIONS_CRITICAL` | `3` | Three or more watchdog recoveries in the sample window → `"Overloaded"`. |
