--[[
	00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
	000 Relay - Signal Library					 							  					                     000
	000 Version: 1.0.2 Stable Release												  				                 000
	000 Platform: Roblox													  					                     000
	000 License: Apache 2.0												  	  					                     000
	000																		  					                     000
	000																		  					                     000
	000 Maintainer/Developer: BedQuest (@yawnTooMuch)						  					                     000
	000 Roblox DevForum Account: https://devforum.roblox.com/u/yawntoomuch/summary    			                     000
	000 Roblox Resource DevForum Page: https://devforum.roblox.com/t/relay-cross-script-signal-communication/4586113 000
	000 Github Repo: https://github.com/yawnTooMuch/Lazy-Games-Suite-of-Tools/tree/Relay_ReadOnly                    000
	000 Documentation: https://yawntoomuch.github.io/Lazy-Games-Suite-of-Tools/utilities/relay/                      000
	00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
]]

--!strict
--!native
--!optimize 2

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Relay Configuration Section
----------------------------------------------------------

local ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE: boolean = game:GetService("RunService"):IsStudio() -- Enables parameter validation in Studio only

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Relay Type Structures Section
----------------------------------------------------------

-- This is the lightweight token returned to a script whenever it listens to a signal (via :Connect() or :Once()). It acts as a localized controller for a specific Relay Object.
export type ConnectionObject = {
	_cancelled: boolean,		-- This acts as the immediate kill-switch for the connection. The engine checks this every :Fire() call.
	_callback: (...any) -> (),	-- This holds the actual function pointer that the developer passed into :Connect() or :Once().
	_signal: SignalObject,		-- This is a strong reference back to the master SignalObject that created this connection.

	Disconnect: (self: ConnectionObject) -> (),
	IsConnected: (self: ConnectionObject) -> boolean,
	BindTo: (self: ConnectionObject, TieTarget: any) -> ConnectionObject,
}

-- This is a strictly-typed, "read-only" view of a signal. Used to safely expose listening methods to external scripts without granting them permission to Fire or Destroy the signal.
export type ListenerSignal<T...> = {
	Connect: (self: ListenerSignal<T...>, Callback: (T...) -> ()) -> ConnectionObject,
	Once: (self: ListenerSignal<T...>, Callback: (T...) -> ()) -> ConnectionObject,
	Wait: (self: ListenerSignal<T...>) -> T...,
}

-- It is used exclusively for the Signal.Signals.OnAbandoned event.
export type OnAbbandonedSignal = {
	Connect: (self: OnAbbandonedSignal, Callback: (...any) -> ()) -> ConnectionObject,
	Once: (self: OnAbbandonedSignal, Callback: (...any) -> ()) -> ConnectionObject,
	Wait: (self: OnAbbandonedSignal) -> ...any,
}

-- This exposes the full suite of administrative APIs within Relay.
export type SignalObject = {
	_id: string,							-- The unique string used to register this signal in the global SignalRegistry (e.g., "MyRelay"). The signal keeps a record of its own ID so that when :Destroy() is called, it knows exactly which key to erase from the global dictionary.
	_connections: { ConnectionObject },		-- The raw, flat array that stores every connection bound to this signal. When :Fire() is called, the engine iterates through this exact array to trigger the callbacks.
	_waitThreads: { thread },				-- When a developer calls Signal:Wait(), their script's coroutine yields and is pushed into this array. The next time the signal fires, the engine iterates through this array, resumes every sleeping threads.
	_cancelled: boolean,					-- This acts as the immediate kill-switch for the connection. The engine checks this every :Fire() call.
	_liveCount: number,						-- An integer that strictly tracks exactly how many valid, uncancelled connections currently exist.
	_firingDepth: number,					-- When :Fire() begins iterating through the _connections array, it adds +1 to this depth. If a connection disconnects during that loop, the depth is > 0, so the engine just flags the connection as cancelled but leaves the array untouched.

	Signals: { OnAbandoned: OnAbbandonedSignal },

	Connect: (self: SignalObject, Callback: (...any) -> ()) -> ConnectionObject,
	Once: (self: SignalObject, Callback: (...any) -> ()) -> ConnectionObject,
	Wait: (self: SignalObject) -> ...any,
	Fire: (self: SignalObject, ...any) -> (),
	DisconnectAll: (self: SignalObject) -> (),
	GetConnectionCount: (self: SignalObject) -> number,
	Destroy: (self: SignalObject) -> (),
	BindTo: (self: SignalObject, TieTarget: any) -> SignalObject,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Relay Internal States Section
----------------------------------------------------------

local Relay = {}
local ReaperModule: any = nil -- The injected Reaper module reference will be stored here.

-- The dynamic task scheduler
local Scheduler = {
	Spawn = task.spawn,
	Defer = task.defer,
	Delay = task.delay,
	Wait = task.wait,
	Cancel = task.cancel,
}

-- The global dictionary that holds all created signals by string ID.
local SignalRegistry: { [string]: SignalObject } = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Relay Local Function Section
----------------------------------------------------------

-- Severs this connection from its parent signal; idempotent and safe to call mid-fire.
local function connectionDisconnect(Self: ConnectionObject): ()
	-- If it's already cancelled, abort instantly to prevent double-subtracting from the live count.
	if Self._cancelled then return end

	-- Instantly neutralize the connection. Even if the parent signal is currently looping, it will see this flag and skip execution.
	Self._cancelled = true

	local ParentSignal = (Self :: any)._signal :: SignalObject?

	if ParentSignal then
		-- Update the master registry count
		ParentSignal._liveCount -= 1

		-- If this was the absolute last connection listening to the signal, trigger the .OnAbandoned sub-signal.
		if ParentSignal._liveCount == 0 then

			-- Only clear the array if the signal is NOT currently looping through it (firing depth is 0).
			if ParentSignal._firingDepth == 0 then
				table.clear(ParentSignal._connections)
			end

			-- Trigger the automatic 'OnAbandoned' sub-signal to alert external scripts that all listeners have disconnected.
			local SubSignals = ParentSignal.Signals

			if SubSignals and SubSignals.OnAbandoned then
				(SubSignals.OnAbandoned :: any):Fire()
			end
		end
	end

	-- Sever strong function/table references so the Luau Garbage Collector can consume the developer's payload and prevent memory leaks.
	(Self :: any)._signal = nil
	(Self :: any)._callback = nil
end

-- Returns whether this connection is currently active and has not been disconnected or cancelled.
local function connectionIsConnected(Self: ConnectionObject): boolean
	return not Self._cancelled
end

-- Binds this connection's lifetime to a Reaper-tracked target, disconnecting it automatically when the target is destroyed.
local function connectionBindTo(Self: ConnectionObject, TieTarget: any): ConnectionObject
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if not ReaperModule then
			error("[Relay] BindTo Error: You must inject the 'Reaper' module via Relay.Inject() before using :BindTo().\n" .. debug.traceback(), 2)
		end

		if TieTarget == nil then
			error("[Relay] BindTo Error: TieTarget cannot be nil.\n" .. debug.traceback(), 2)
		end
	end

	-- If this connection is already severed, bypass the tracking logic entirely to save CPU cycles.
	if Self._cancelled then return Self end

	-- Route the physical object into Reaper to acquire a lifecycle tracker.
	local TargetTracker = ReaperModule.Track(TieTarget)

	-- Chain this specific connection to the tracker. When the TieTarget is destroyed, Reaper will automatically call clean this signal.
	TargetTracker:Chain(Self)

	-- Return the object to allow method chaining.
	return Self
end

-- Constructs a new connection object for a given signal and callback; binds methods statically to avoid per-connection closure allocation.
local function makeConnection(ParentSignal: SignalObject, Callback: (...any) -> ()): ConnectionObject
	-- Static Method Binding and State Initialization
	local Connection: ConnectionObject = {
		-- The default lifecycle state.
		_cancelled = false,

		-- Bind the methods directly to the static local functions. This prevents the GC from choking on thousands of identical closure allocations.
		Disconnect = connectionDisconnect,
		IsConnected = connectionIsConnected,
		BindTo = connectionBindTo,
	} :: any

	-- Cache the developer's execution payload.
	Connection._callback = Callback

	-- Cache the strong reference to the master signal so the connection knows where to check when :Disconnect() is called.
	Connection._signal = ParentSignal

	return Connection
end

-- Registers a persistent callback that executes each time the signal fires; appends via direct array indexing rather than table.insert().
local function signalConnect(Self: SignalObject, Callback: (...any) -> ()): ConnectionObject
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if type(Callback) ~= "function" then
			error("[Relay] Connect Error: 'Callback' must be a function.\n" .. debug.traceback(), 2)
		end

		if Self._cancelled then
			error("[Relay] Connect Error: Cannot connect to a destroyed signal.\n" .. debug.traceback(), 2)
		end
	end

	local Connection = makeConnection(Self, Callback)
	local Connections = Self._connections

	-- O(1) append: map the connection directly to the end of the array, which is measurably faster than table.insert() in Luau.
	Connections[#Connections + 1] = Connection

	-- Update the active listener count to keep the abandonment tracker accurate.
	Self._liveCount += 1

	return Connection
end

-- Registers a one-shot callback that disconnects itself before executing on the next fire.
local function signalOnce(Self: SignalObject, Callback: (...any) -> ()): ConnectionObject
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if type(Callback) ~= "function" then
			error("[Relay] Once Error: 'Callback' must be a function.\n" .. debug.traceback(), 2)
		end

		if Self._cancelled then
			error("[Relay] Once Error: Cannot connect to a destroyed signal.\n" .. debug.traceback(), 2)
		end
	end

	-- Pre-declare the pointer. If we didn't do this, the anonymous function below would not be able to reference it.
	local Connection: ConnectionObject

	-- Wrap the developer's callback inside a custom teardown function and route it into the standard connection pipeline.
	Connection = signalConnect(Self, function(...: any)

		-- Instantly sever the link to the signal. We do this BEFORE the callback so that if the callback yields or crashes, this listener is already dead and won't accidentally fire twice.
		Connection:Disconnect()

		-- Execute the developer's actual payload with the forwarded arguments.
		Callback(...)
	end)

	return Connection
end

-- Yields the calling coroutine until the signal fires, then returns the fired arguments.
local function signalWait(Self: SignalObject): ...any
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if Self._cancelled then
			error("[Relay] Wait Error: Cannot wait on a destroyed signal.\n" .. debug.traceback(), 2)
		end
	end

	-- Capture the exact memory pointer of the thread that called this function.
	local CurrentThread = coroutine.running()
	local WaitThreads = Self._waitThreads

	-- Safely save the thread pointer into the waiting queue.
	WaitThreads[#WaitThreads + 1] = CurrentThread

	return coroutine.yield() -- Instantly suspend the thread.
end

-- Resumes all yielded Wait threads and executes all live connection callbacks asynchronously.
local function signalFire(Self: SignalObject, ...: any): ()
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if Self._cancelled then
			error("[Relay] Fire Error: Cannot fire a destroyed signal.\n" .. debug.traceback(), 2)
		end
	end

	----------------------------------------------------------------------
	-- PHASE 1: RESUME WAITING THREADS
	----------------------------------------------------------------------

	local WaitCount = #Self._waitThreads

	if WaitCount > 0 then
		local CurrentWaiters = Self._waitThreads

		-- Instantly swap the wait queue with a new table BEFORE resuming the threads. This prevents "Recursive Deadlocks" where a thread wakes up, immediately calls :Wait() again, and gets stuck in an infinite loop inside this exact phase.
		Self._waitThreads = {}

		for Index = 1, WaitCount do
			local WaitThread = CurrentWaiters[Index]

			-- The Dead Thread Guard: if a script externally cancelled the waiting thread (via task.cancel if not using the Assignment library override), attempting to spawn it will throw a fatal engine error. Verify the thread is actively suspended before awaking it.
			if coroutine.status(WaitThread) == "suspended" then
				Scheduler.Spawn(WaitThread, ...)
			end
		end
	end

	----------------------------------------------------------------------
	-- PHASE 2: EXECUTE CALLBACKS
	----------------------------------------------------------------------

	local Connections = Self._connections
	local ActiveCount = #Connections

	-- Lock the array compaction by incrementing the depth. This signals to any :Disconnect() calls that they are not allowed to delete array entries right now.
	Self._firingDepth += 1

	for Index = 1, ActiveCount do
		local Connection = Connections[Index]

		-- Safely ignore connections that were cancelled mid-loop.
		if Connection and not Connection._cancelled then
			local Callback = (Connection :: any)._callback

			if Callback then
				-- Execute asynchronously to ensure one crashing callback doesn't halt the rest of the listeners in this loop.
				Scheduler.Spawn(Callback, ...)
			end
		end
	end

	-- Unlock the array compaction. The loop is finished reading.
	Self._firingDepth -= 1

	----------------------------------------------------------------------
	-- PHASE 3: ARRAY COMPACTION (The O(N) Shifting Phase)
	----------------------------------------------------------------------

	-- If no other nested Fire calls are actively iterating this array, safely sweep and compress dead connections.
	if Self._firingDepth == 0 then
		local WriteIndex = 0
		local TotalCount = #Connections

		for Index = 1, TotalCount do
			local Connection = Connections[Index]

			-- If the connection is alive, shift it strictly to the left to fill the gaps left by cancelled connections.
			if not Connection._cancelled then
				WriteIndex += 1
				Connections[WriteIndex] = Connection
			end
		end

		-- Nullify the trailing dead pointers explicitly. This allows the Luau Garbage Collector to clean them up and frees up memory.
		for Index = WriteIndex + 1, TotalCount do
			Connections[Index] = nil :: any
		end
	end

	-- Array compaction batches removal to the end of the fire loop instead of calling table.remove() per-disconnect: this avoids O(N) mid-loop shifting, the "skipped listener" bug that shifting causes during forward iteration, and unpredictable mid-loop memory churn.
end

-- Immediately cancels all active connections on this signal and fires the OnAbandoned sub-signal.
local function signalDisconnectAll(Self: SignalObject): ()
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if Self._cancelled then
			error("[Relay] DisconnectAll Error: Cannot disconnect from a destroyed signal.\n" .. debug.traceback(), 2)
		end
	end

	-- Iterate over the raw array to sever the strong references held by each connection.
	for _, Connection in ipairs(Self._connections) do
		if not Connection._cancelled then
			Connection._cancelled = true

			-- Freeing the memory payload manually prevents the Garbage Collector from having to trace complex circular references.
			(Connection :: any)._signal = nil
			(Connection :: any)._callback = nil
		end
	end

	-- Instantly empty the array. If a Fire loop is currently running, its cached length will now point to empty nil slots, safely terminating pending executions.
	table.clear(Self._connections)

	-- Reset the master active listener count to absolute zero.
	Self._liveCount = 0

	local SubSignals = Self.Signals

	-- Execute a Fire call to the sub-signal to alert external scripts that every listener was just wiped.
	if SubSignals and SubSignals.OnAbandoned then
		(SubSignals.OnAbandoned :: any):Fire()
	end
end

-- Returns the count of live, non-cancelled connections currently listening to this signal.
local function signalGetConnectionCount(Self: SignalObject): number
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if Self._cancelled then
			error("[Relay] GetConnectionCount Error: Cannot count connections on a destroyed signal.\n" .. debug.traceback(), 2)
		end
	end

	return Self._liveCount
end

-- Permanently destroys the signal, cancels all connections, resumes any yielded Wait threads with no arguments, and removes it from the global registry.
local function signalDestroy(Self: SignalObject): ()
	-- If the signal is already dead, abort instantly to prevent double-execution.
	if Self._cancelled then return end

	-- The Master Lock: Instantly neutralize the signal.
	Self._cancelled = true

	-- Forcefully sever all active connections and nullify their payloads.
	for _, Connection in ipairs(Self._connections) do
		if not Connection._cancelled then
			Connection._cancelled = true
			(Connection :: any)._signal = nil
			(Connection :: any)._callback = nil
		end
	end

	table.clear(Self._connections)

	-- Iterate through any coroutines currently yielded via Signal:Wait() and force them to resume.
	for _, WaitThread in ipairs(Self._waitThreads) do

		-- The Dead Thread Guard: if a script externally cancelled the waiting thread (via task.cancel if not using the Assignment library override), attempting to spawn it will throw a fatal engine error. Verify the thread is actively suspended before awaking it.
		if coroutine.status(WaitThread) == "suspended" then
			Scheduler.Spawn(WaitThread)
		end
	end

	table.clear(Self._waitThreads)

	local SubSignals = Self.Signals

	if SubSignals and SubSignals.OnAbandoned then
		-- Alert external scripts that the signal has died and the listener pool is empty.
		(SubSignals.OnAbandoned :: any):Fire()

		-- Use the Defer buffer to destroy the sub-signal on the VERY NEXT frame if using Assignment or at the end of the resumption cycle. If destroyed it instantly here, the Fire() call above might crash any listeners currently trying to read it.
		Scheduler.Defer(function()
			(SubSignals.OnAbandoned :: any):Destroy()
		end)
	end

	-- Remove the master pointer from the weak registry, officially handing the object over to the Luau Garbage Collector.
	SignalRegistry[Self._id] = nil
end

-- Binds this signal's lifetime to a Reaper-tracked target, destroying the signal automatically when the target is destroyed.
local function signalBindTo(Self: SignalObject, TieTarget: any): SignalObject
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if not ReaperModule then
			error("[Relay] BindTo Error: You must inject the 'Reaper' module via Relay.Inject() before using :BindTo().\n" .. debug.traceback(), 2)
		end

		if TieTarget == nil then
			error("[Relay] BindTo Error: Bindable target cannot be nil.\n" .. debug.traceback(), 2)
		end
	end

	-- If this signal is already dead, bypass the tracking logic entirely to save CPU cycles.
	if Self._cancelled then return Self end

	-- Route the physical object into Reaper to acquire a lifecycle tracker.
	local TargetTracker = ReaperModule.Track(TieTarget)

	-- Chain this entire master signal to the tracker. When the TieTarget is destroyed, Reaper will automatically clean this object.
	TargetTracker:Chain(Self)

	-- Return the object to allow fluent method chaining.
	return Self
end

-- Constructs a new SignalObject; IsInternal prevents recursive sub-signal creation when building the OnAbandoned child signal.
local function buildSignal(SignalID: string, IsInternal: boolean?): SignalObject
	-- Allocate the raw memory footprint for the new event emitter.
	local NewSignal: SignalObject = {
		_id = SignalID,
		_connections = {},
		_waitThreads = {},

		-- Master state locks for the Lazy Array Compaction system.
		_cancelled = false,
		_liveCount = 0,
		_firingDepth = 0,
		Signals = nil :: any,

		-- Flat-table method binding for extreme lookup speed.
		Connect = signalConnect,
		Once = signalOnce,
		Wait = signalWait,
		Fire = signalFire,
		DisconnectAll = signalDisconnectAll,
		GetConnectionCount = signalGetConnectionCount,
		Destroy = signalDestroy,
		BindTo = signalBindTo,
	}

	-- Only generate sub-signals if this is a primary, developer-facing object.
	if not IsInternal then
		NewSignal.Signals = {
			-- Fires automatically whenever a signal's connection count drops to zero. Useful for cleaning up high-level systems that no longer have active listeners.
			OnAbandoned = buildSignal(SignalID .. "_Abandoned", true) :: any, -- Construct the sub-signal and explicitly flag it as Internal to trip the recursive guard.
		}
	end

	return NewSignal -- Return the completed SignalObject
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Relay Public APIs Section
----------------------------------------------------------

--[[
	Creates a new signal for the given ID, or returns the existing signal if one is already registered under that ID.

	Params:
	    SignalID: string -- A unique non-empty string identifier for the signal.

	Returns:
	    SignalObject -- The newly created signal, or the existing registered signal if SignalID is already in use.
]]
function Relay.Create(SignalID: string): SignalObject
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if type(SignalID) ~= "string" or SignalID == "" then
			error("[Relay] Create Error: 'SignalID' must be a non-empty string.\n" .. debug.traceback(), 2)
		end
	end

	-- Look into the global dictionary for an existing signal with this exact ID.
	local Existing = SignalRegistry[SignalID]

	-- If it already exists, instantly return the cached memory pointer. This is the secret to global, cross-script event communication.
	if Existing then
		return Existing
	end

	-- If it does not exist, trigger the master factory to allocate a fresh footprint.
	local NewSignal = buildSignal(SignalID)

	-- Store the new signal in the global registry so future scripts can discover it.
	SignalRegistry[SignalID] = NewSignal

	return NewSignal
end

--[[
	Returns whether a signal with the given ID currently exists in the active registry.

	Params:
	    SignalID: string -- The signal ID to check for an active registration.

	Returns:
	    boolean -- true if a live signal is registered under this ID, false otherwise.
]]
function Relay.Exists(SignalID: string): boolean
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if type(SignalID) ~= "string" or SignalID == "" then
			error("[Relay] Exists Error: 'SignalID' must be a non-empty string.\n" .. debug.traceback(), 2)
		end
	end

	return SignalRegistry[SignalID] ~= nil
end

--[[
	Injects an external library within the Lazy Games Suite of Tools environment. Currently supports the "Assignment" and "Reaper" libraries/frameworks.

	Params:
	    ModuleName        : string -- The name of the ModuleScript file.
	    ModuleTableObject : any    -- The required module table/object to inject.

	Returns:
	    nil
]]
function Relay.Inject(ModuleName: string, ModuleTableObject: any): ()
	if ENABLE_STRICT_API_PARAMETER_CHECKER_POLICE then
		if type(ModuleName) ~= "string" or ModuleName == "" then
			error("[Relay] Inject Error: 'ModuleName' must be a non-empty string.")
		end

		if type(ModuleTableObject) ~= "table" then
			error("[Relay] Inject Error: 'ModuleTableObject' must be a table.")
		end
	end

	if ModuleName == "Assignment" then
		Scheduler.Spawn = ModuleTableObject.Spawn or task.spawn
		Scheduler.Defer = ModuleTableObject.Defer or task.defer
		Scheduler.Delay = ModuleTableObject.Delay or task.delay
		Scheduler.Wait = ModuleTableObject.Wait or task.wait
		Scheduler.Cancel = ModuleTableObject.Cancel or task.cancel

	elseif ModuleName == "Reaper" then
		ReaperModule = ModuleTableObject
	end
end

--[[
	Returns a summary of the current signal registry state.

	Params:
		nil

	Returns:
	    { ActiveSignals: number, TotalConnections: number, SignalDetails: { [string]: number } } -- A dictionary containing active signal counts and connection tallies.
]]
function Relay.GetDiagnostics(): { ActiveSignals: number, TotalConnections: number, SignalDetails: { [string]: number } }
	local activeCount = 0
	local totalConnections = 0
	local details = {}

	for id, signalObj in SignalRegistry do
		activeCount += 1
		
		local conns = signalObj:GetConnectionCount()
		
		totalConnections += conns
		details[id] = conns
	end

	return {
		ActiveSignals = activeCount,
		TotalConnections = totalConnections,
		SignalDetails = details,
	}
end

-------------------------------------------------------------------------------------------------------------
return Relay
-------------------------------------------------------------------------------------------------------------