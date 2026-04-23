# Twin

**Type:** Framework  
_A parallel job scheduler for Roblox that distributes work across Actor-based workers, protecting the main thread from expensive computation._

[Distribution:](https://devforum.roblox.com/t/twin-parallel-job-scheduler/4591855) `https://devforum.roblox.com/t/twin-parallel-job-scheduler/4591855`

---

## Overview

Twin is a parallel execution framework for Roblox games. It solves a fundamental problem in
Roblox development: computationally expensive work — pathfinding, physics calculations, data
transformations, procedural generation — blocks the main thread and causes frame drops if run
inline. Twin moves that work off the main thread entirely, running it inside isolated parallel
workers, and delivers the result back to your code when it is ready.

Twin works on both the server and the client. On the server it spawns a small pool of parallel
workers sized for server workloads; on the client it spawns a larger pool tuned for the higher
job throughput typical of client-side simulation. In both environments the public API is
identical — the same three calls dispatch work regardless of which side your code runs on.

Twin replaces ad-hoc `task.spawn` patterns and manual Actor management. Rather than writing
boilerplate for every piece of parallel work — creating Actors, wiring BindableEvents, handling
errors, reassembling results — you call a single function, pass a module and a function name,
and receive the result in a callback. Twin handles everything in between: worker selection,
batching, result routing, error recovery, and priority ordering.

---

## External Dependencies

**Assignment** _(optional)_ — An external scheduler from the Lazy Games Suite of Tools. If
injected via `Twin.Inject`, Twin replaces its internal use of Roblox's `task` library with
the Assignment scheduler. This is entirely optional; Twin works fully without it and defaults
to the native `task` library when no injection is provided.

---

## Key Features

### Three Dispatch Modes

Twin exposes three ways to send work to parallel workers, each suited to a different problem
shape.

**Split** dispatches a single job — one function call with one payload — and delivers a single
result to your callback. Use it for isolated computations: one pathfind, one AI decision, one
heavy calculation. The callback fires in the same frame the worker finishes, with no extra
frame of delay.

**BulkSplit** is for fan-out workloads: you have a large list of items (hundreds of NPCs,
thousands of tiles, a full inventory snapshot) that all need the same operation applied. Twin
slices the list across every available worker automatically, runs all slices in parallel, and
reassembles the results in the original order before calling your callback. You get a single
result table back, indexed identically to the input list.

**Sequence** chains multiple Split jobs together in order. Each step receives the result of the
previous one, so you can build a pipeline — compute, then transform, then validate — without
nesting callbacks. If any step is cancelled, the entire chain stops cleanly.

### Priority Scheduling with Starvation Protection

Not all work is equally urgent. BulkSplit jobs accept a priority level — critical, normal, or
background — and Twin ensures critical work reaches workers before normal work, and normal
before background. Workers are never left idle waiting for high-priority work to clear; lower
priority jobs are periodically promoted to prevent them from waiting indefinitely, no matter
how busy the system is.

Single-job dispatch has its own two-tier system. Jobs marked as heavyweight wait until all bulk
work is complete before occupying a worker. Jobs marked as lightweight can run speculatively
alongside bulk work when the scheduler detects that a worker is running slow or a deadline is
approaching. Heavy jobs that have been waiting too long are automatically promoted to the light
lane so they are never stranded.

### Frame Budget Protection

Twin is designed to never ruin a frame. Dispatching work to workers costs a small amount of
main-thread time each frame. Twin tracks how much of that budget has been spent and stops
dispatching single jobs once the frame's allocation is consumed. Bulk batches are always
dispatched unconditionally — they are time-critical and the batches themselves do the heavy
work off-thread — but lightweight single-job dispatch is gated so a large backlog cannot cause
a frame spike on its own.

### Automatic Worker Recovery

If a parallel worker stops responding — due to an infinite loop, a deadlock, or any other
unrecoverable condition — Twin detects it automatically. A background scan checks every worker
on a regular interval. Any worker that has been running a single job for longer than the
configured timeout is declared unresponsive: it is freed, its in-flight job is re-queued for
another worker to pick up, and execution continues without any manual intervention. From your
code's perspective, the job simply takes a little longer; it is never silently dropped.

### Pooled Memory, No Allocation Overhead

Every internal object Twin uses — job descriptors, batch records, result buffers, queue nodes —
is pre-allocated at startup and recycled after each job completes. On the hot path, dispatching
and completing a job involves zero heap allocations. This matters in frames with many jobs: a
system that allocates per-job will eventually stall the garbage collector at the worst possible
moment.

### Structured Health Telemetry

When telemetry is enabled, Twin samples its own internal state every frame and accumulates
those samples in a rolling window. Calling `Twin.Report()` at any time returns a structured
snapshot: how full each internal pool is, how deep each queue has grown, how long each worker
is taking on average, what fraction of frames exceeded the budget, and whether any workers
needed recovery. Each metric carries a three-level health status — Healthy, Warm, or
Overloaded — and each group rolls up to a Green/Yellow/Red signal. The overall status is the
worst signal across all groups.

### Developer-Friendly Option Tables

All optional parameters are passed as tables with a four-underscore prefix on each key
(`____Weight`, `____Priority`, etc.). This prefix exists purely as a convenience: any Luau
language server will autocomplete the known keys when you type `____`, giving you a discoverable
options surface without needing to consult the documentation for every call. The prefix is
stripped automatically before the value is used.
