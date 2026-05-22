# Assignment API Reference

This page documents every public function, method, and type surface exposed by the **Assignment** library.

---

## Class: Assignment

The top-level module table. All scheduling and pattern-matching functions are accessed directly on this table.

### Summary

**Pooled Family** — protect the server. These functions recycle execution resources, throttle heavy workloads automatically, and gracefully discard cancelled work before it ever runs.

| Name | Returns | Description |
|:---|:---|:---|
| **[Spawn](#spawn)** | `void` | Runs a function or thread immediately. |
| **[Defer](#defer)** | `Handle` | Queues work to run on the next available frame. Large backlogs are spread across frames automatically to protect frame time. |
| **[Delay](#delay)** | `Handle` | Schedules work to run after a set duration. Zero or negative durations queue on the next available frame. |

**Isolated Family** — exert absolute control. These functions bypass all throttles, give you a cancellation token (`thread`) to stop work at any time, and force the engine to prioritise your logic immediately.

| Name | Returns | Description |
|:---|:---|:---|
| **[SpawnIsolated](#spawnisolated)** | `thread` | Runs a function or thread immediately at full engine priority. Use for long-yielding work. |
| **[DeferIsolated](#deferisolated)** | `thread` | Queues work for the next available frame at full engine priority, bypassing frame-spread throttling. Use for long-yielding deferred work. |
| **[DelayIsolated](#delayisolated)** | `thread` | Schedules work after a set duration at full engine priority. Use for long-yielding delayed work. |

**Shared**

| Name | Returns | Description |
|:---|:---|:---|
| **[Wait](#wait)** | `number` | Pauses the current thread for a duration and returns the real elapsed time. |
| **[Repeat](#repeat)** | `Handle` | Calls a function repeatedly at a fixed interval, for a set number of iterations or indefinitely. |
| **[Cancel](#cancel)** | `void` | Stops a scheduled `Handle`, a cancellation `thread`, or a suspended `thread` from executing. |
| **[Migrate](#migrate)** | `void` | Hands all pending scheduled work to the engine's native scheduler. Server-only. |

**Pattern Matching**

| Name | Returns | Description |
|:---|:---|:---|
| **[Switch](#switch)** | `SwitchHandle` | Fetches or creates a named pattern-matching decision tree. |
| **[Op](#op)** | `{ [string]: Opcode }` | A frozen enum dictionary of engine instructions for use with `SwitchHandle:Case`. |

---

#### Spawn

```luau
Assignment.Spawn(Function: ((...any) -> ()) | thread, ...: any): ()
```

Runs a function or resumes a thread immediately.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Function` | `((...any) -> ()) | thread` | The function to call or thread to resume immediately. |
| `...` | `any` | Arguments forwarded to the function or thread. |

**Returns:** `void`

!!! info "Best For Short, Quick Work"
    The Pooled Family is designed for tasks that start and finish quickly, or yield only briefly. If your work will sleep for a long time — waiting on a DataStore, an HTTP request, or a multi-second loop — use `SpawnIsolated` instead. Long sleeps occupy the shared worker and force all other incoming short tasks to spin up their own resources rather than sharing the available one.

---

#### SpawnIsolated

```luau
Assignment.SpawnIsolated(Function: ((...any) -> ()) | thread, ...: any): thread
```

Runs a function or thread immediately at full engine priority, completely independent of the shared worker.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Function` | `((...any) -> ()) | thread` | The function to call or thread to resume immediately. |
| `...` | `any` | Arguments forwarded to the function or thread. |

**Returns:**

| Type | Description |
|:---|:---|
| `thread` | The dedicated thread. Pass to `Assignment.Cancel` to stop it. |

!!! info "The Isolated Family — Absolute Control"
    `SpawnIsolated`, `DeferIsolated`, and `DelayIsolated` all give work its own dedicated engine-managed thread. Think of it as hiring a specialist who operates entirely independently — your regular team is never occupied by this job, no matter how long it runs.

    Use any of them when work will yield for a meaningful amount of time. The Pooled Family shares one reusable worker: a long-sleeping task keeps that worker busy for the entire sleep, leaving short incoming tasks without a free worker to reuse. Isolated threads sidestep this — the shared worker stays free at all times, and the engine manages the dedicated thread on its own.

!!! warning "Isolated Threads Trade Safety for Control"
    Isolated threads are not covered by Assignment's automatic throttling or cleanup. They run immediately at full engine priority, are never spread across frames, and are not automatically discarded if they go unused. Only use them when the work genuinely requires it.

---

#### Defer

```luau
Assignment.Defer(Function: ((...any) -> ()) | thread, ...: any): Handle
```

Queues work to run on the next available frame.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Function` | `((...any) -> ()) | thread` | The function to call or thread to resume. |
| `...` | `any` | Arguments forwarded to the function or thread. |

**Returns:**

| Type | Description |
|:---|:---|
| `Handle` | A cancellable handle. Call `Handle:Break()` or pass it to `Assignment.Cancel()` to discard the work before it runs. |

!!! tip "Automatic Frame Spreading"
    Unlike the engine's native defer, which processes everything queued in one frame all at once, Assignment meters deferred work across frames. Deferring a large batch of calls in one frame will not spike your frame time.

---

#### DeferIsolated

```luau
Assignment.DeferIsolated(Function: ((...any) -> ()) | thread, ...: any): thread
```

Queues work to run on the next available frame at full engine priority.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Function` | `((...any) -> ()) | thread` | The function to call or thread to resume. |
| `...` | `any` | Arguments forwarded to the function or thread. |

**Returns:**

| Type | Description |
|:---|:---|
| `thread` | The dedicated thread. Pass to `Assignment.Cancel` to stop it. |

!!! info "When to Use"
    Use `DeferIsolated` when the work you want to run next frame will then sleep for a long time — for example, a batch of DataStore writes or a chain of HTTP calls. Queueing that kind of work through the standard `Defer` path would occupy the shared pool for the entire duration of those yields. See `SpawnIsolated` for the full explanation.

---

#### Delay

```luau
Assignment.Delay(Duration: number, Function: ((...any) -> ()) | thread, ...: any): Handle
```

Schedules work to run after a set number of seconds.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Duration` | `number` | Seconds to wait before running. |
| `Function` | `((...any) -> ()) | thread` | The function to call or thread to resume. |
| `...` | `any` | Arguments forwarded to the function or thread. |

**Returns:**

| Type | Description |
|:---|:---|
| `Handle` | A cancellable handle. Call `Handle:Break()` or pass it to `Assignment.Cancel()` to discard the work before it runs. |

!!! info "Zero and Negative Durations"
    Passing `0` or any negative number tells Assignment to run the work as soon as possible — on the next available frame, just like `Defer`. The returned `Handle` behaves identically regardless of which path was taken and is fully cancellable.

!!! tip "Timing Precision"
    Assignment fires delayed work as close to the requested time as the current frame rate allows. Very short durations may fire on the frame after the one they were scheduled in. For precise, immediate execution without any timing constraint, use `DelayIsolated`.

---

#### DelayIsolated

```luau
Assignment.DelayIsolated(Duration: number, Function: ((...any) -> ()) | thread, ...: any): thread
```

Schedules work to run after a set number of seconds at full engine priority.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Duration` | `number` | Seconds to wait before running. |
| `Function` | `((...any) -> ()) | thread` | The function to call or thread to resume. |
| `...` | `any` | Arguments forwarded to the function or thread. |

**Returns:**

| Type | Description |
|:---|:---|
| `thread` | The dedicated thread. Pass to `Assignment.Cancel` to stop it. |

!!! info "When to Use"
    Use `DelayIsolated` when the work that fires after the delay will then sleep for a long time — for example, an async multi-step workflow. Running that through the standard `Delay` path would occupy the shared pool for the duration of those yields. See `SpawnIsolated` for the full explanation.

---

#### Wait

```luau
Assignment.Wait(Duration: number?): number
```

Pauses the current thread for approximately the requested duration and returns how long it actually waited.

Passing zero, `nil`, or a negative value is valid: the thread pauses for the shortest possible time, resuming on the next frame.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Duration` | `number?` | Seconds to pause. |

**Returns:**

| Type | Description |
|:---|:---|
| `number` | The actual time elapsed since `Wait` was called, in seconds. |

!!! warning "This Function Yields"
    `Assignment.Wait` suspends the calling thread. Do not call it from a synchronous callback or any context that must return immediately, such as a signal handler.

!!! tip "The Returned Time Is Real, Not Requested"
    The return value reflects how long the thread actually slept, not the duration you asked for. Under heavy load the actual wait may exceed the requested duration. If you need precise elapsed time for animation or interpolation, measure with `os.clock()` directly.

!!! info "Zero, Nil, and Negative Values — Next Frame Yield"
    Passing `nil`, `0`, or any negative number is the lightest possible yield: the thread is paused for exactly one frame and then resumes. This is useful for letting other work run between steps of a long process without introducing a meaningful time delay.

---

#### Repeat

```luau
Assignment.Repeat(Count: number, Interval: number?, Function: (number, Handle, ...any) -> (), ...: any): Handle
```

Calls a function repeatedly at a fixed interval for a set number of iterations, or indefinitely when `Count` is `-1`. Each iteration receives the current iteration number (starting at 1), the loop's `Handle`, and any extra arguments you forward.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Count` | `number` | Number of times to call `Function`. Pass `-1` to loop forever. |
| `Interval` | `number?` | Seconds between calls. |
| `Function` | `(number, Handle, ...any) -> ()` | Called each iteration with the iteration number and the loop handle as the first two arguments. |
| `...` | `any` | Extra arguments forwarded to `Function` after the iteration number and handle. |

**Returns:**

| Type | Description |
|:---|:---|
| `Handle` | A cancellable handle. Call `Handle:Break()` or pass it to `Assignment.Cancel()` to stop the loop before it starts or mid-run. |

!!! warning "Yielding Inside the Callback Delays the Next Iteration"
    The loop pauses between iterations. If your callback also yields — for example, by calling `Assignment.Wait` itself — the next iteration is delayed by the full length of that yield on top of the configured interval.

!!! tip "Cancellation Is Immediate After the Current Callback"
    `Handle:Break()` is checked both before the callback runs and immediately after it returns. If you call `Break` from inside the callback, the loop exits before the next wait period — it does not wait out the remaining interval.

---

#### Cancel

```luau
Assignment.Cancel(Target: Handle | thread): ()
```

Stops a scheduled task from running. Accepts a `Handle` returned from any pooled call, a `thread` token returned from any isolated call, or a raw `thread` that is currently suspended inside `Assignment.Wait`.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Target` | `Handle | thread` | The handle or thread to cancel. Passing `nil` is safe and does nothing. |

**Returns:** `void`

!!! tip "Cancel and Break Are Equivalent for Handles"
    `Assignment.Cancel(handle)` and `handle:Break()` do exactly the same thing when passed a `Handle`. Use `Cancel` when your code may hold either a `Handle` or a raw `thread` — it handles both uniformly, making it the right choice for generic cleanup systems.

!!! info "Cancelling a Waiting Thread"
    If you hold a reference to a thread that is currently suspended inside `Assignment.Wait`, you can pass it directly to `Assignment.Cancel`. Assignment will locate its associated control token and discard the pending work the same way it would for a `Handle`.

---

#### Migrate

```luau
Assignment.Migrate(): ()
```

Signals Assignment to hand all pending scheduled work to the engine's native scheduler, preserving each task's remaining time. After migration, all Assignment functions continue to work as normal but route through the native scheduler.

This is called automatically when the server closes and requires no code from you. It is exposed as a manual call for controlled shutdown sequences.

**Parameters:** `void`

**Returns:** `void`

!!! note "Server Only"
    `Migrate` exists only on the server. The automatic shutdown binding is also server-only. Calling it on the client will error.

!!! warning "Cancellation Is No Longer Available After Migration"
    Once migration completes, Assignment's cancellation system is no longer active. Tasks that were not yet cancelled will run at their scheduled times and cannot be stopped by `Handle:Break()` or `Assignment.Cancel`.

---

#### Switch

```luau
Assignment.Switch(SwitchID: string): SwitchHandle
```

Fetches or creates a named pattern-matching decision tree. The first call with a given ID creates and stores the tree, every subsequent call with the same ID returns the exact same object from memory. This makes it safe to call `Assignment.Switch("MySwitch")` anywhere — including inside hot loops — without any allocation cost.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `SwitchID` | `string` | A unique name that identifies this decision tree across all scripts. |

**Returns:**

| Type | Description |
|:---|:---|
| `SwitchHandle` | The control handle for this switch tree. Use it to define rules (`:Case`, `:Execute`, `:Default`) during setup and evaluate them (`:Match`) at runtime. |

!!! tip "Define Rules Once, Evaluate Anywhere"
    Because each Switch is a global singleton identified by its string ID, you can define all the rules for `"MySwitch"` in one script and call `Assignment.Switch("MySwitch"):Match(...)` from any other script that needs the result. No reference passing required.

!!! info "Two Phases: Setup and Execution"
    A Switch has two distinct usage phases. During **Setup** (typically at game start or module load), you chain `:Case():Execute()` calls to compile rules into the decision tree. During **Execution** (typically each frame or on events), you call `:Match(...)` to evaluate the tree and get back the function that applies to the current state. These phases are intentionally separate — the rules are compiled once, not re-built on every match.

---

#### Op

```luau
Assignment.Op: { [string]: Opcode }
```

A frozen enum dictionary of engine instructions for use with `SwitchHandle:Case`. Each entry is an `Opcode` value that tells the pattern engine to apply a specific comparison rather than a direct equality check.

**Opcodes:**

| Name | Subjects Required | Matches When... |
|:---|:---|:---|
| `Assignment.Op.InRange` | `Min: number, Max: number` | The target number falls between `Min` and `Max`, inclusive. |
| `Assignment.Op.Type` | `typeName: string` | `typeof(target) == typeName`. |
| `Assignment.Op.IsA` | `className: string` | The target is a Roblox Instance and `target:IsA(className)` is true. Safely skipped if the target is not an Instance. |
| `Assignment.Op.NotEqual` | `value: any` | `target ~= value`. |
| `Assignment.Op.LessThan` | `value: number` | `target < value`. Safely skipped if either side is not a number. |
| `Assignment.Op.GreaterThan` | `value: number` | `target > value`. Safely skipped if either side is not a number. |
| `Assignment.Op.LessThanOrEqual` | `value: number` | `target <= value`. Safely skipped if either side is not a number. |
| `Assignment.Op.GreaterThanOrEqual` | `value: number` | `target >= value`. Safely skipped if either side is not a number. |
| `Assignment.Op.NoOp` | _(none)_ | Used as a payload in `:Execute()` to mark a path as intentionally empty, suppressing the Default fallback. |
| `Assignment.Op.AND` | _(none)_ | A structural suffix token. When placed as the **last argument** in a `:Case()` call, causes the next `:Case()` call to distribute its conditions across all existing pending path endpoints rather than starting new root branches. Enables compound `(A OR B) AND C` patterns. Takes no subject and performs no comparison. |

!!! warning "The JIT Compilation Law: Setup vs. Runtime"
    `Assignment.Switch` physically separates rule creation from rule evaluation. The arguments you pass into `:Case()` are permanently compiled into a static memory graph at system startup. They are **not** evaluated dynamically per frame.

    * **The "Snapshot" Misconception:** If you pass a dynamic variable (e.g., `Player.Health`) as a subject in `:Case()`, the engine permanently bakes in that exact value at that specific microsecond. It does not live-update. You must pass your static rules into `:Case()`, and pass your dynamic variables into `:Match()`.
    * **JIT Cache Bloat:** Never call `:Case()` dynamically inside a Heartbeat or event loop. Attempting to continuously expand the memory tree with dynamic variables will quickly trigger a fatal `MAX_SWITCH_MATH_BRANCHES` JIT Cache Bloat error and crash your system to prevent memory leaks.
    * **Strict Opcode Placement Rules:** 
        * **Structural & Math Opcodes** (e.g., `Op.AND`, `Op.LessThan`) are compiler instructions used strictly to shape the tree. They belong exclusively inside `:Case()` and will throw fatal errors if passed into `:Match()` or bound as payloads in `:Execute()`.
        * **The Terminator Exception:** The *only* exception is `Assignment.Op.NoOp`. This is a dedicated Execution Token. It cannot be used to shape the tree inside `:Case()`, and must strictly be bound as a payload inside `:Execute(Assignment.Op.NoOp)` to safely terminate a branch.

!!! info "InRange Takes Two Subjects"
    `Op.InRange` is the only opcode that consumes two subjects instead of one: `:Case(Assignment.Op.InRange, Min, Max, ...)`. All other comparison opcodes consume exactly one subject: `:Case(Assignment.Op.LessThan, 100, ...)`.

!!! info "AND is a Structural Token, Not a Comparison"
    `Op.AND` is unique: it takes no values and performs no math. Instead, it acts as a bridge. By placing it at the very end of a `:Case()`, you are telling the engine: *"Take the branches I just built, and apply my next condition to all of them."* This natively enables `(A OR B) AND C` logic, allowing multiple OR branches to share a single, nested AND condition without repeating yourself.

!!! danger "AND Placement Rules"
    Misusing `Op.AND` throws a hard error at setup time, never at runtime. The rules are:

    - `Op.AND` must always be the **last argument** in a `:Case()` call. Placing it anywhere else in the argument sequence is a hard error.
    - `Op.AND` cannot be the **sole argument** in a `:Case()` call. A preceding condition is required.
    - `Op.AND` cannot be passed as a payload to `:Execute()`. This is a hard error.
    - Calling `:Execute()` immediately after a `:Case()` that ended with `Op.AND` (a dangling AND) emits a **warning** and forcefully seals the state — the paths are still bound normally, but the trailing `Op.AND` should be removed.

---

## Class: Handle

A cancellation token returned by `Defer`, `Delay`, and `Repeat`. Holds a single cancellation flag and exposes one method.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Break](#break)** | `void` | Marks this handle as cancelled so its scheduled work is silently discarded. |

---

#### Break

```luau
Handle:Break(): ()
```

Marks this handle as cancelled. When the scheduled time arrives, Assignment sees the cancellation flag and silently discards the associated work without running it. For `Repeat` loops, the flag is checked both before the callback runs and immediately after, so the loop exits as soon as you call `Break`.

**Parameters:** `void`

**Returns:** `void`

!!! tip "Safe to Call More Than Once"
    Calling `Break` on an already-cancelled handle does nothing. There is no error and no state change — it is safe to call defensively without checking first.

---

## Class: SwitchHandle

The control object returned by `Assignment.Switch`. Used in two distinct phases: **Setup** (`:Case`, `:Execute`, `:Default`) to compile rules into the decision tree, and **Execution** (`:Match`) to evaluate the tree at runtime.

All builder methods return `self` and can be chained.

### Summary

| Name | Returns | Description |
|:---|:---|:---|
| **[Case](#case)** | `SwitchHandle` | Compiles one condition path into the decision tree. |
| **[Execute](#execute)** | `SwitchHandle` | Binds a function (or a NoOp instruction) to all preceding unbound `:Case` paths. |
| **[Default](#default)** | `SwitchHandle` | Sets the fallback function returned when no path matches. |
| **[Match](#match)** | `((...any) -> ())?` | Evaluates the decision tree and returns the matching function pointer. |

---

#### Case

```luau
SwitchHandle:Case(...: any): SwitchHandle
```

Compiles a sequence of conditions into the decision tree. Arguments are evaluated left-to-right, each one narrowing the path. Call `:Execute()` after one or more `:Case()` calls to bind a handler to the compiled path(s).

Each argument in the sequence is either a **literal value** (string, number, boolean) for an exact match, or an **Opcode instruction** followed by its subject(s).

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `...` | `any` | The condition sequence. Exact values are matched directly. Opcode values (from `Assignment.Op`) must be immediately followed by their required subject(s). |

**Returns:**

| Type | Description |
|:---|:---|
| `SwitchHandle` | Returns `self` for chaining. |

!!! danger "Throws"
    Throws an error if `Op.InRange` is not followed by two number subjects, or if any other Opcode is missing its subject. Also throws if the number of compiled branches for a single node exceeds the engine's internal limit. These errors exist to catch setup mistakes early — they will never fire if you use static constants.

!!! tip "OR Gate — Chain Multiple Cases Before Execute"
    Calling `:Case()` multiple times in a row without calling `:Execute()` in between queues all the resulting paths into a shared pending list. When you finally call `:Execute()`, the single handler is bound to every queued path simultaneously. This is the correct way to express "if A or B or C, do X":
    ```luau
    MySwitch
        :Case("Fire")
        :Case("Ice")
        :Case("Lightning")

        :Execute(handleElementalAttack)

    --[[
        Assignment Decision Tree Built:
        
        _Trie = {
	       ["Fire"] = { 
		     __EXECUTE = handleElementalAttack 
	       },
	
	       ["Ice"] = { 
		     __EXECUTE = handleElementalAttack 
	       },
	
	       ["Lightning"] = {
		     __EXECUTE = handleElementalAttack
	       }
        }

        ---------------------------------------------------------
        Native Equivalent:
        
        if Element == "Fire" or Element == "Ice" or Element == "Lightning" then
            handleElementalAttack()
        end
    ]]
    ```

!!! tip "AND Gate — Distribute a Shared Condition Across OR Branches"
    Placing `Assignment.Op.AND` as the **last argument** in a `:Case()` call switches the engine into continuation mode. To distribute a shared condition across multiple OR branches, you leave the initial OR branches open and only apply `Op.AND` to the **final** branch of the OR group. 
    
    The *next* `:Case()` call will then distribute its conditions mathematically across every currently pending path rather than adding new root branches. Combined with OR gates, this expresses "if (A or B) and C, do X" as a single binding — the shared condition is compiled only once:
    ```luau
    MySwitch
        -- The OR Stream (Parallel Branches)
        :Case("Fire") 
        :Case("Ice", Assignment.Op.AND)   -- Seals the OR stream! Queue contains [Fire, Ice]
        
        -- The AND Stream (Multiplexed to both Fire and Ice)
        :Case("Strong")                   -- Distributed to: (Fire->Strong) and (Ice->Strong)
        
        :Execute(handlePowerfulElement)

    --[[
        Assignment Decision Tree Built:
        
        _Trie = {
            ["Fire"] = {
                ["Strong"] = { 
                    __EXECUTE = handlePowerfulElement 
                }
            },

            ["Ice"] = {
                ["Strong"] = { 
                    __EXECUTE = handlePowerfulElement 
                }
            }
        }

        ---------------------------------------------------------
        Native Equivalent:
        
        if (Element == "Fire" or Element == "Ice") and Modifier == "Strong" then
            handlePowerfulElement()
        end
    ]]
    ```

!!! info "Prefix Sharing"
    If two rules share a common prefix — for example, both start with `Op.LessThan, 50` — Assignment automatically merges their shared portion into one node rather than duplicating it. This means overlapping rules cost no extra memory or evaluation time.

---

#### Execute

```luau
SwitchHandle:Execute(Payload: ((...any) -> ()) | Opcode): SwitchHandle
```

Binds a function to all paths queued by the preceding `:Case()` call(s). Clears the pending path queue so the next `:Case()` starts a fresh, independent rule.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Payload` | `((...any) -> ()) | Opcode` | The function to run when this path matches, or `Assignment.Op.NoOp` to intentionally mark the path as "do nothing." |

**Returns:**

| Type | Description |
|:---|:---|
| `SwitchHandle` | Returns `self` for chaining. |

!!! info "NoOp — Intentional Silence"
    Passing `Assignment.Op.NoOp` as the payload marks the path as an explicit no-op. When `:Match` reaches this path, it returns `nil` directly — it does **not** fall through to the Default function. This is the correct way to say "this state is known and should be ignored" as opposed to an unrecognised state that should invoke the fallback.

!!! warning "Dangling AND Emits a Warning"
    If `:Execute()` is called immediately after a `:Case()` that ended with `Assignment.Op.AND`, the engine emits a warning and forcefully seals the continuation state. The pending paths are still bound to the payload normally. Remove the trailing `Op.AND` from the preceding `:Case()` call if no further `:Case()` continuation was intended.

---

#### Default

```luau
SwitchHandle:Default(Payload: (...any) -> ()): SwitchHandle
```

Sets the fallback function returned by `:Match` whenever the provided arguments do not match any compiled path.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `Payload` | `(...any) -> ()` | The function to return when no path matches. |

**Returns:**

| Type | Description |
|:---|:---|
| `SwitchHandle` | Returns `self` for chaining. |

!!! info "NoOp Bypasses Default"
    If a path was compiled with `Assignment.Op.NoOp` as its payload, `:Match` returns `nil` for that path and never calls Default. Default is only invoked when no compiled path matches at all.

---

#### Match

```luau
SwitchHandle:Match(...: any): ((...any) -> ())?
```

Evaluates the compiled decision tree against the provided arguments from left to right and returns the matching function pointer. Returns `nil` if the matching path was bound with `Assignment.Op.NoOp`, or if no path matched and no Default was set.

**Parameters:**

| Name | Type | Description |
|:---|:---|:---|
| `...` | `any` | The runtime values to evaluate. Must correspond to the sequence structure defined during `:Case()` setup. |

**Returns:**

| Type | Description |
|:---|:---|
| `((...any) -> ())?` | The function bound to the matching path, the Default function if no path matched, or `nil` for a NoOp path or an unhandled no-default miss. |

!!! warning "Match Returns a Pointer — It Does Not Call the Function"
    `:Match` returns a function reference; it does not call it. You are responsible for calling the returned function with whatever arguments are appropriate. This design lets you inspect the result, pass it elsewhere, or discard it without it ever executing.
    ```luau
    -- Correct usage
    local handler = MySwitch:Match(currentState, currentValue)

    if handler then
        handler(target, context)
    end
    ```

!!! tip "Match Priority Order"
    When evaluating each step, Assignment tries routes in this order:
    
    1. **Exact match** — a direct lookup against compiled literal values. Fastest.
    2. **Range check** — evaluated only if `Op.InRange` was used for this step and the target is a number.
    3. **Opcode checks** — evaluated in the order the rules were compiled, stopping at the first match.
    
    If all three fail, the Default function is returned. Understanding this order lets you arrange rules so the most common cases hit the fastest path.

---

## Type: Opcode

```luau
export type Opcode = {
    IsAssignmentOpcode: boolean,
    Name: string,
}
```

An engine instruction used with `SwitchHandle:Case` to perform non-equality comparisons. All valid `Opcode` values are pre-defined in `Assignment.Op`. You should never construct an `Opcode` table manually.

---

## Type: SwitchHandle

```luau
export type SwitchHandle = {
    _IsContinuing: boolean,
    Case:    (self: SwitchHandle, ...any) -> SwitchHandle,
    Execute: (self: SwitchHandle, Payload: ((...any) -> ()) | Opcode) -> SwitchHandle,
    Default: (self: SwitchHandle, Payload: (...any) -> ()) -> SwitchHandle,
    Match:   (self: SwitchHandle, ...any) -> ((...any) -> ())?,
}
```

The public interface of a pattern-matching decision tree. See [Class: SwitchHandle](#class-switchhandle) for full documentation of each method.
