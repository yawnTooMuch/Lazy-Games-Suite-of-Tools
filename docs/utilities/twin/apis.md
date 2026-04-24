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
    The results table passed to your callback is a pooled buffer that Twin recycles
    immediately after your callback returns. Storing the table reference — assigning it to a
    module-level variable, inserting it into another table, capturing it in a closure — will
    cause that variable to be silently overwritten by a future job's results. Copy any values
    you need before the callback exits.

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

!!! warning "Step Errors Stop the Chain"
    If a dynamic payload function throws an error, the chain halts at that step and the final
    callback never fires. Errors inside the worker functions are caught and logged, and the
    step's result is set to `nil`, but the chain continues. Only payload function errors stop
    the chain entirely.

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
    ____Module       : ModuleScript?,
    ____FunctionName : string?,
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
