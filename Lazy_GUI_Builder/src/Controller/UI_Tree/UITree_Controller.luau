--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: UITree_Controller.luau
    
    SCOPE: UI Tree / Flow Routing / Controller Pillar
    
    ROLE: Sub-controller orchestrating traffic for the UI Tree feature,
          subscribing to Relay action signals, delegating mutations to
          Backend UITree_Logic, initializing nested child controllers
          (ExportCompiler_Controller, ImportCompiler_Controller), and
          dispatching UI refresh signals.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Controller Type Structures Section
----------------------------------------------------------
export type UITree_Controller = {
	Init: () -> ()
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Controller Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local UITree_Logic = require(script.Parent.Parent.Parent.Backend.UI_Tree.UITree_Logic)
local ExportCompiler_Controller = require(script.Parent.ExportCompiler_Controller)
local ImportCompiler_Controller = require(script.Parent.ImportCompiler_Controller)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Controller Internal States Section
----------------------------------------------------------
local UITree_Controller = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Controller Local Function Section
----------------------------------------------------------

--[[
Handles toggling the UI Tree visibility.
]]
local function onToggleUITree(): ()
	UITree_Logic.ToggleVisibility()
	Relay.Create("SessionStateUpdated"):Fire()
end

-- Closes all floating property editors.
local function closeFloatingEditors(): ()
	Relay.Create("CloseColorPicker"):Fire()
	Relay.Create("CloseGradientEditor"):Fire()
	Relay.Create("CloseTransparencyEditor"):Fire()
end

--[[
Handles element selection.
]]
local function onSelectElement(Id: string): ()
	closeFloatingEditors()
	UITree_Logic.SelectElement(Id)
	Relay.Create("ElementSelected"):Fire()
end

--[[
Handles updating the UI Tree position.
]]
local function onUpdateUITreePosition(NewPosition: UDim2): ()
	UITree_Logic.UpdatePosition(NewPosition)
end

--[[
Handles initiating a node drag.
]]
local function onInitiateNodeDrag(NodeId: string): ()
	UITree_Logic.InitiateNodeDrag(NodeId)
	Relay.Create("UITreeUpdated"):Fire()
end

--[[
Handles setting the drag target.
]]
local function onSetNodeDragTarget(TargetId: string?): ()
	UITree_Logic.SetNodeDragTarget(TargetId)
	Relay.Create("UITreeUpdated"):Fire()
end

--[[
Handles canceling a node drag.
]]
local function onCancelNodeDrag(): ()
	UITree_Logic.CancelNodeDrag()
	Relay.Create("UITreeUpdated"):Fire()
end

--[[
Handles reparenting an element.
]]
local function onReparentElement(NodeId: string, TargetParentId: string?): ()
	UITree_Logic.ReparentElement(NodeId, TargetParentId)
	Relay.Create("UITreeUpdated"):Fire()
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles toggling element visibility.
]]
local function onToggleElementVisibility(NodeId: string): ()
	closeFloatingEditors()
	UITree_Logic.ToggleElementVisibility(NodeId)
	Relay.Create("UITreeUpdated"):Fire()
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles deleting an element.
]]
local function onDeleteElement(NodeId: string): ()
	closeFloatingEditors()
	UITree_Logic.DeleteElement(NodeId)
	Relay.Create("UITreeUpdated"):Fire()
	Relay.Create("WorkspaceElementsUpdated"):Fire()
	Relay.Create("ElementSelected"):Fire()
end

--[[
Handles hover state for the trash bin.
]]
local function onSetNodeDragTrash(IsHovering: boolean): ()
	UITree_Logic.SetNodeDragTrash(IsHovering)
	Relay.Create("UITreeUpdated"):Fire()
end

--[[
Handles hover state for the duplicate button.
]]
local function onSetNodeDragDuplicate(IsHovering: boolean): ()
	UITree_Logic.SetNodeDragDuplicate(IsHovering)
	Relay.Create("UITreeUpdated"):Fire()
end

--[[
Handles duplicating an element.
]]
local function onDuplicateElement(NodeId: string): ()
	UITree_Logic.DuplicateElement(NodeId)
	Relay.Create("UITreeUpdated"):Fire()
	Relay.Create("WorkspaceElementsUpdated"):Fire()
	Relay.Create("ElementSelected"):Fire()
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Controller Public APIs Section
----------------------------------------------------------

--[[
Architectural placeholder for controller initialization.

Params:
    None

Returns:
    None
]]
function UITree_Controller.Init(): ()
	ExportCompiler_Controller.Init()
	ImportCompiler_Controller.Init()
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Controller Event Binding Section
----------------------------------------------------------
Relay.Create("ToggleUITree"):Connect(onToggleUITree)
Relay.Create("SelectElement"):Connect(onSelectElement)
Relay.Create("UpdateUITreePosition"):Connect(onUpdateUITreePosition)
Relay.Create("InitiateNodeDrag"):Connect(onInitiateNodeDrag)
Relay.Create("SetNodeDragTarget"):Connect(onSetNodeDragTarget)
Relay.Create("CancelNodeDrag"):Connect(onCancelNodeDrag)
Relay.Create("ReparentElement"):Connect(onReparentElement)
Relay.Create("ToggleElementVisibility"):Connect(onToggleElementVisibility)
Relay.Create("DeleteElement"):Connect(onDeleteElement)
Relay.Create("SetNodeDragTrash"):Connect(onSetNodeDragTrash)
Relay.Create("SetNodeDragDuplicate"):Connect(onSetNodeDragDuplicate)
Relay.Create("DuplicateElement"):Connect(onDuplicateElement)

----------------------------------------------------------
return UITree_Controller :: UITree_Controller
----------------------------------------------------------