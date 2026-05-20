# Assignment

**Type:** Singleton Library  

_**Assignment** is a high-performance, drop-in replacement for Roblox’s native task library and sequential `if/elseif` chains. Engineered specifically for scale, it combines high-frequency event scheduling, system frame-time protection, and a zero-allocation JIT pattern-matching engine (`.Switch()`) to maximize CPU efficiency and memory management._

---

## Overview

Assignment is a drop-in replacement for Roblox's native `task` library. It exposes the same operations — `Spawn`, `Defer`, `Delay`, `Wait`, and `Repeat` — but adds two things the native library does not provide: first-class cancellation on every scheduled call, and a safe shutdown pathway that preserves in-flight work when a server closes.

The library's scheduling functions are split into two families that serve different purposes.

The **Pooled Family** (`Spawn`, `Defer`, `Delay`) is designed to protect your server. These functions share a pool of reusable threads, throttle large backlogs automatically to prevent frame spikes, recycle memory between calls, and silently discard work that has been cancelled before it runs.

The **Isolated Family** (`SpawnIsolated`, `DeferIsolated`, `DelayIsolated`) is designed for absolute control. These functions bypass the shared pool and run their work in a dedicated engine-managed thread. They give you a `thread` reference you can cancel at any time, skip all throttling so the engine prioritises your logic immediately, and are the right tool for work that will sleep for a long time or involve repeated slow yields.

In addition to scheduling, Assignment ships a **Pattern Matching Engine** (`Assignment.Switch`, `Assignment.Op`). It lets you define multi-condition routing rules once at startup and evaluate them continuously inside your heartbeat loops at near-zero cost, replacing long if/elseif chains with a pre-compiled decision tree.

---

## External Dependencies

**RunService** — Drives the scheduler's per-frame tick. Required at load time. No other external dependencies.

---

## Key Features

### The Pooled Family — Safety and Efficiency

Think of the pooled family like a staffing agency with one available worker. When you call `Spawn`, `Defer`, or `Delay`, you hand a job to that worker. The moment the job finishes the worker is immediately available for the next one. Because the same worker is reused for every short job, there is no overhead from hiring a new one each time.

If the worker is busy when a new job arrives — because a previous job is sleeping mid-yield — the agency hires a temporary replacement just for that job. This is fine for brief yields, but if the worker stays busy for a long time (for example, sleeping for 30 seconds waiting on a DataStore), many temporary replacements accumulate and start to cost real memory. That is the signal to use an Isolated variant instead.

The pooled family also throttles deferred work automatically. If many jobs are queued in the same frame, Assignment spreads them across several frames rather than processing everything at once, keeping frame times stable.

### The Isolated Family — Absolute Control

The isolated family bypasses the shared pool entirely and hands work straight to the engine. Each isolated call gets its own dedicated thread, like hiring a specialist who works completely independently of your regular staff.

Use isolated variants when work will sleep for a meaningful amount of time — DataStore calls, HTTP requests, loops with multi-second intervals. Keeping that kind of work out of the shared pool means short jobs always find a free worker waiting for them.

Isolated calls return a raw `thread` reference rather than a `Handle`. You can stop that thread at any time by passing it to `Assignment.Cancel`.

### Cancellable Handles

Every call in the pooled family returns a `Handle`. Call `Handle:Break()` before the work runs and Assignment will silently skip and discard it — no errors, no side effects. The cancellation check happens at the moment the scheduled time arrives, so calling `Break` at any point up until then is guaranteed to stop execution.

For isolated threads, pass the returned `thread` to `Assignment.Cancel` for the same effect. You can also pass any `thread` that is currently suspended inside `Assignment.Wait` — Assignment finds its associated control token and cancels it the same way.

### Smart Wait — Works Anywhere

`Assignment.Wait` is context-aware. In a pooled thread it pauses execution entirely within Assignment's scheduling and wakes the thread at the right time. In an isolated thread it defers to the engine's own wait mechanism. You never need to choose between the two — use `Assignment.Wait` everywhere inside Assignment-managed code and the right behaviour happens automatically.

Passing zero, `nil`, or a negative value to `Wait` is valid and means "pause for the shortest possible time" — the thread yields just until the next frame and then continues.

### Pattern Matching Engine — Zero-Cost State Routing

`Assignment.Switch` lets you build a named decision tree once and evaluate it continuously without any allocation or repeated branching overhead.

Think of it like a compiled rulebook. During setup — at game start or module load — you write down every rule: "if the weapon type is `Sword` and the state is `Attacking`, call this function." Assignment pre-compiles those rules into a single in-memory lookup structure. At runtime, in your heartbeat loop, you pass in the current values and Assignment traverses the compiled structure to return the matching function. Because the structure is already built, the per-call cost is a handful of table lookups regardless of how many rules you have defined.

Rules support exact value matching, numeric range checks, type checks, inequality comparisons, and OR gates (multiple conditions sharing a single handler). All rules for a given Switch share one singleton in memory — you can define rules in one script and evaluate them from any other script just by using the same ID.

### Graceful Server Shutdown

When a server closes, Assignment automatically hands all pending scheduled work to the engine's native scheduler with each task's remaining time intact. Nothing in flight is lost. This happens automatically and requires no code on your part.

### Periodic Cleanup

Assignment periodically scans all scheduled work and quietly discards anything that has been cancelled but has not yet reached its scheduled time. This ensures that cancelled-but-waiting tasks do not accumulate in memory over a long server session.
