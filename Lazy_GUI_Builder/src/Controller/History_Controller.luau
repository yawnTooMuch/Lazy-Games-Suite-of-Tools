--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: History_Controller.luau
    
    SCOPE: Root Controller
    
    ROLE: Routes undo and redo actions to the backend logic.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Controller Type Structures Section
----------------------------------------------------------
export type History_Controller = {
    Init: () -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Controller Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)
local History_Logic = require(script.Parent.Parent.Backend.History_Logic)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Controller Internal States Section
----------------------------------------------------------
local History_Controller = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Controller Local Function Section
----------------------------------------------------------
-- Closes all floating property editors.
local function closeFloatingEditors(): ()
    Relay.Create("CloseColorPicker"):Fire()
    Relay.Create("CloseGradientEditor"):Fire()
    Relay.Create("CloseTransparencyEditor"):Fire()
end

-- Refreshes the user interface after a history state change.
local function updateInterface(): ()
    Relay.Create("UITreeUpdated"):Fire()
    Relay.Create("WorkspaceElementsUpdated"):Fire()
    Relay.Create("ElementSelected"):Fire()
end

-- Handles the undo action.
local function handleUndo(): ()
    closeFloatingEditors()
    History_Logic.Undo()
    updateInterface()
end

-- Handles the redo action.
local function handleRedo(): ()
    closeFloatingEditors()
    History_Logic.Redo()
    updateInterface()
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Controller Public APIs Section
----------------------------------------------------------
--[[
Architectural placeholder for controller initialization.

Params:
    None

Returns:
    None
]]
function History_Controller.Init(): ()
	--[[
		Placeholder Function:
		
		Because we use the static Event Binding pattern (Rule #13), all signal connections 
		are established natively at the bottom of the script the moment the module is 
		required. However, the root AppController uniformly invokes `.Init()` on every 
		sub-controller during plugin startup. This function exists to satisfy that strict 
		architectural contract and provides a future-proof location for any deferred setup.
	]]
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- History_Controller Event Binding Section
----------------------------------------------------------
Relay.Create("Undo"):Connect(handleUndo)
Relay.Create("Redo"):Connect(handleRedo)

----------------------------------------------------------
return History_Controller :: History_Controller
----------------------------------------------------------