--!strict

local RunService: RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

--[[
    ===========================================================================
    MODULE/COMPONENT: UITree_Linter.legacy.luau
    
    SCOPE: UI Tree / Input Sanitization / Correctness Linter Pillar
    
    ROLE: Intercepts raw user interaction signals (_CL) from the UI Tree
          component, validates element selection, node reparenting, deletion,
          duplication, and visibility preconditions, blasting error notifications
          on failure or forwarding validated action signals to UITree_Controller.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Linter Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Linter Local Function Section
----------------------------------------------------------

--[[
Handles the toggle action for the UI Tree window visibility.
]]
local function onToggleUITree(): ()
	Relay.Create("ToggleUITree"):Fire()
end

--[[
Validates and routes an element selection request.
]]
local function onSelectElement(Id: string?): ()
	
	if Id == nil then
		Relay.Create("SelectElement"):Fire(nil)
		
	elseif type(Id) == "string" and AppState.WorkspaceElements[Id] then
		Relay.Create("SelectElement"):Fire(Id)
		
	else
		Relay.Create("ShowNotification"):Fire({
			Message = "Element Selection Failed. Invalid Resolved ID.",
			Type = "Error"
		})
	end
end

--[[
Validates and initiates a drag operation for a specific node.
]]
local function onInitiateNodeDrag(NodeId: string): ()
	if type(NodeId) == "string" and AppState.WorkspaceElements[NodeId] then
		Relay.Create("InitiateNodeDrag"):Fire(NodeId)
		
	else
		Relay.Create("ShowNotification"):Fire({
			Message = "Initiated Drag Failed. Invalid Resolved ID.",
			Type = "Error"
		})
	end
end

--[[
Validates and sets the target node for a drag operation.
]]
local function onSetNodeDragTarget(TargetId: string?): ()
	if TargetId == nil then
		Relay.Create("SetNodeDragTarget"):Fire(nil)
		
	elseif type(TargetId) == "string" and AppState.WorkspaceElements[TargetId] then
		Relay.Create("SetNodeDragTarget"):Fire(TargetId)
	end
end

--[[
Routes the cancellation of a drag operation.
]]
local function onCancelNodeDrag(): ()
	Relay.Create("CancelNodeDrag"):Fire()
end

--[[
Validates and routes a reparenting request, checking for cyclic dependencies.
]]
local function onReparentElement(NodeId: string, TargetParentId: string?): ()
	if type(NodeId) ~= "string" or not AppState.WorkspaceElements[NodeId] then
		Relay.Create("ShowNotification"):Fire({
			Message = "Node Reparenting Failed. Invalid Resolved Source/Target ID.",
			Type = "Error"
		})
		
		Relay.Create("CancelNodeDrag"):Fire()
		
		return
	end

	if TargetParentId ~= nil then
		if type(TargetParentId) ~= "string" or not AppState.WorkspaceElements[TargetParentId] then
			Relay.Create("ShowNotification"):Fire({
				Message = "Node Reparenting Failed. Invalid Resolved Source/Target ID.",
				Type = "Error"
			})
			
			Relay.Create("CancelNodeDrag"):Fire()
			
			return
		end
	end

	if NodeId == TargetParentId then
		Relay.Create("ShowNotification"):Fire({
			Message = "Node Reparenting Failed. Invalid Target Node.",
			Type = "Error"
		})
		
		Relay.Create("CancelNodeDrag"):Fire()
		
		return
	end

	local CurrentParentId = TargetParentId
	
	while CurrentParentId ~= nil do
		if CurrentParentId == NodeId then
			Relay.Create("ShowNotification"):Fire({
				Message = "Node Reparenting Failed. Invalid Target Node.",
				Type = "Error"
			})
			
			Relay.Create("CancelNodeDrag"):Fire()
			
			return
		end
		
		CurrentParentId = AppState.WorkspaceElements[CurrentParentId] and AppState.WorkspaceElements[CurrentParentId].ParentId or nil
	end

	Relay.Create("ReparentElement"):Fire(NodeId, TargetParentId)
end

--[[
Validates and routes a visibility toggle request, ensuring ancestors are visible.
]]
local function onToggleElementVisibility(NodeId: string): ()
	if type(NodeId) == "string" and AppState.WorkspaceElements[NodeId] then
		local CurrentAncestorId = AppState.WorkspaceElements[NodeId].ParentId
		
		while CurrentAncestorId ~= nil do
			local Ancestor = AppState.WorkspaceElements[CurrentAncestorId]
			
			if Ancestor and not Ancestor.Visible then
				Relay.Create("ShowNotification"):Fire({
					Message = "Visibility Toggling Failed. Parent Node Currently Hidden.",
					Type = "Error"
				})
				
				return
			end
			
			CurrentAncestorId = Ancestor and Ancestor.ParentId or nil
		end
		
		Relay.Create("ToggleElementVisibility"):Fire(NodeId)
		
	else
		Relay.Create("ShowNotification"):Fire({
			Message = "Visibility Toggling Failed. Invalid Resolved ID.",
			Type = "Error"
		})
	end
end

--[[
Validates and routes an element deletion request.
]]
local function onDeleteElement(NodeId: string): ()
	if type(NodeId) == "string" and AppState.WorkspaceElements[NodeId] then
		Relay.Create("DeleteElement"):Fire(NodeId)
		
	else
		Relay.Create("ShowNotification"):Fire({
			Message = "Initiated Deletion Failed. Invalid Resolved Target ID.",
			Type = "Error"
		})
		
		Relay.Create("CancelNodeDrag"):Fire()
	end
end

--[[
Updates the drag state to indicate whether the user is hovering over the trash bin.
]]
local function onSetNodeDragTrash(IsHovering: boolean): ()
	if type(IsHovering) == "boolean" and AppState.UITreeDragState.IsDragging then
		Relay.Create("SetNodeDragTrash"):Fire(IsHovering)
	end
end

--[[
Updates the drag state to indicate whether the user is hovering over the duplicate button.
]]
local function onSetNodeDragDuplicate(IsHovering: boolean): ()
	if type(IsHovering) == "boolean" and AppState.UITreeDragState.IsDragging then
		Relay.Create("SetNodeDragDuplicate"):Fire(IsHovering)
	end
end

--[[
Validates and routes an element duplication request.
]]
local function onDuplicateElement(NodeId: string): ()
	if type(NodeId) == "string" and AppState.WorkspaceElements[NodeId] then
		Relay.Create("DuplicateElement"):Fire(NodeId)
		
	else
		Relay.Create("ShowNotification"):Fire({
			Message = "Initiated Duplication Failed. Invalid Resolved Source ID.",
			Type = "Error"
		})
		
		Relay.Create("CancelNodeDrag"):Fire()
	end
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Linter Event Binding Section
----------------------------------------------------------
Relay.Create("ToggleUITree_CL"):Connect(onToggleUITree)
Relay.Create("SelectElement_CL"):Connect(onSelectElement)
Relay.Create("InitiateNodeDrag_CL"):Connect(onInitiateNodeDrag)
Relay.Create("SetNodeDragTarget_CL"):Connect(onSetNodeDragTarget)
Relay.Create("CancelNodeDrag_CL"):Connect(onCancelNodeDrag)
Relay.Create("ReparentElement_CL"):Connect(onReparentElement)
Relay.Create("ToggleElementVisibility_CL"):Connect(onToggleElementVisibility)
Relay.Create("DeleteElement_CL"):Connect(onDeleteElement)
Relay.Create("SetNodeDragTrash_CL"):Connect(onSetNodeDragTrash)
Relay.Create("SetNodeDragDuplicate_CL"):Connect(onSetNodeDragDuplicate)
Relay.Create("DuplicateElement_CL"):Connect(onDuplicateElement)