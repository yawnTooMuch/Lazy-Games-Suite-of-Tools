--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: History_Logic.luau
    
    SCOPE: Root Backend Logic
    
    ROLE: Manages the undo/redo snapshot system and deep cloning.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Logic Type Structures Section
----------------------------------------------------------
export type History_Logic = {
	PushSnapshot: () -> (),
	Undo: () -> (),
	Redo: () -> (),
	DeepCloneElements: (Elements: { [string]: any }) -> { [string]: any },
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Logic Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Logic Internal States Section
----------------------------------------------------------
local History_Logic = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Logic Local Function Section
----------------------------------------------------------
-- Deeply clones a generic table.
local function deepCloneTable(Target: { [any]: any }): { [any]: any }
	local Result: { [any]: any } = {}
	
	for Key, Value in Target do
		if type(Value) == "table" then
			Result[Key] = deepCloneTable(Value)
			
		else
			Result[Key] = Value
		end
	end
	
	return Result
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Logic Public APIs Section
----------------------------------------------------------

--[[
Deep clones the WorkspaceElements dictionary.

Params:
    Elements: { [string]: AppState.UIElement } -- The elements to clone

Returns:
    { [string]: AppState.UIElement } -- The cloned dictionary
]]
function History_Logic.DeepCloneElements(Elements: { [string]: AppState.UIElement }): { [string]: AppState.UIElement }
	return deepCloneTable(Elements :: { [any]: any }) :: { [string]: AppState.UIElement }
end

local MAX_HISTORY_CAP = 1000

--[[
Creates a snapshot of the current state and pushes it to the UndoStack.
Clears the RedoStack.

Params:
    None

Returns:
    None
]]
function History_Logic.PushSnapshot(): ()
	local Snapshot: AppState.HistoryRecord = {
		WorkspaceElements = History_Logic.DeepCloneElements(AppState.WorkspaceElements),
		SelectedElementId = AppState.SelectedElementId,
		PreviousRedoStack = if #AppState.RedoStack > 0 then table.clone(AppState.RedoStack) else nil,
	}

	AppState.UndoStack[#AppState.UndoStack + 1] = Snapshot
	
	-- Cap the history to prevent memory leaks during long sessions
	if #AppState.UndoStack > MAX_HISTORY_CAP then
		local TrimmedStack: { AppState.HistoryRecord } = {}
		local StartIndex: number = #AppState.UndoStack - MAX_HISTORY_CAP + 1
		
		for Index = StartIndex, #AppState.UndoStack do
			TrimmedStack[#TrimmedStack + 1] = AppState.UndoStack[Index]
		end
		
		AppState.UndoStack = TrimmedStack
	end
	
	AppState.RedoStack = {}
end

--[[
Restores the previous state from the UndoStack.

Params:
    None

Returns:
    None
]]
function History_Logic.Undo(): ()
	if #AppState.UndoStack == 0 then return end

	local CurrentState: AppState.HistoryRecord = {
		WorkspaceElements = History_Logic.DeepCloneElements(AppState.WorkspaceElements),
		SelectedElementId = AppState.SelectedElementId,
	}
	
	local PreviousState: AppState.HistoryRecord = AppState.UndoStack[#AppState.UndoStack]
	
	AppState.UndoStack[#AppState.UndoStack] = nil
	AppState.WorkspaceElements = History_Logic.DeepCloneElements(PreviousState.WorkspaceElements)
	AppState.SelectedElementId = PreviousState.SelectedElementId

	-- Sanitize SelectedElementId: ensure restored selection actually exists in workspace
	if AppState.SelectedElementId and not AppState.WorkspaceElements[AppState.SelectedElementId] then
		AppState.SelectedElementId = nil
	end

	-- Restore previous redo branch if an undone branch was temporarily sidelined by an action
	if PreviousState.PreviousRedoStack and #PreviousState.PreviousRedoStack > 0 then
		AppState.RedoStack = table.clone(PreviousState.PreviousRedoStack)
		AppState.RedoStack[#AppState.RedoStack + 1] = CurrentState
		
	else
		AppState.RedoStack[#AppState.RedoStack + 1] = CurrentState
	end
end

--[[
Restores the next state from the RedoStack.

Params:
    None

Returns:
    None
]]
function History_Logic.Redo(): ()
	if #AppState.RedoStack == 0 then return end

	local CurrentState: AppState.HistoryRecord = {
		WorkspaceElements = History_Logic.DeepCloneElements(AppState.WorkspaceElements),
		SelectedElementId = AppState.SelectedElementId,
	}
	
	local NextState: AppState.HistoryRecord = AppState.RedoStack[#AppState.RedoStack]
	
	AppState.UndoStack[#AppState.UndoStack + 1] = CurrentState
	AppState.RedoStack[#AppState.RedoStack] = nil
	AppState.WorkspaceElements = History_Logic.DeepCloneElements(NextState.WorkspaceElements)
	AppState.SelectedElementId = NextState.SelectedElementId

	-- Sanitize SelectedElementId: ensure restored selection actually exists in workspace
	if AppState.SelectedElementId and not AppState.WorkspaceElements[AppState.SelectedElementId] then
		AppState.SelectedElementId = nil
	end
end

----------------------------------------------------------
return History_Logic :: History_Logic
----------------------------------------------------------