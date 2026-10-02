--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: UITree_Logic.luau
    
    SCOPE: UI Tree / Hierarchy Management / Database Writer
    
    ROLE: Core backend logic for the UI Tree feature, responsible for mutating
          AppState (selection, node reparenting, deletion, duplication,
          element visibility, node drag-and-drop state, and window position)
          while pushing snapshots to History_Logic for undo/redo operations.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Logic Type Structures Section
----------------------------------------------------------
export type UITree_Logic = {
	ToggleVisibility: () -> (),
	SelectElement: (Id: string) -> (),
	UpdatePosition: (NewPosition: UDim2) -> (),
	InitiateNodeDrag: (NodeId: string) -> (),
	SetNodeDragTarget: (TargetId: string?) -> (),
	CancelNodeDrag: () -> (),
	ReparentElement: (NodeId: string, TargetParentId: string?) -> (),
	ToggleElementVisibility: (NodeId: string) -> (),
	DeleteElement: (NodeId: string) -> (),
	SetNodeDragTrash: (IsHovering: boolean) -> (),
	SetNodeDragDuplicate: (IsHovering: boolean) -> (),
	DuplicateElement: (NodeId: string) -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Logic Imported Services Section
----------------------------------------------------------
local HttpService: HttpService = game:GetService("HttpService")
local Workspace: Workspace = game:GetService("Workspace")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Logic Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.Parent.AppState)
local History_Logic = require(script.Parent.Parent.History_Logic)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Logic Internal States Section
----------------------------------------------------------
local UITree_Logic = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Logic Public APIs Section
----------------------------------------------------------

--[[
Toggles the visibility of the UI tree.

Params:

Returns:
]]
function UITree_Logic.ToggleVisibility(): ()
	AppState.SessionState.IsUITreeVisible = not AppState.SessionState.IsUITreeVisible
end

--[[
Selects an element by its ID.

Params:
    Id: string -- The ID of the element to select

Returns:
]]
function UITree_Logic.SelectElement(Id: string): ()
	AppState.SelectedElementId = Id
end

--[[
Updates the position of the UI tree.

Params:
    NewPosition: UDim2 -- The new position

Returns:
]]
function UITree_Logic.UpdatePosition(NewPosition: UDim2): ()
	AppState.SessionState.UITreePosition = NewPosition
end

--[[
Initiates dragging of a UI tree node.

Params:
    NodeId: string -- The node being dragged

Returns:
]]
function UITree_Logic.InitiateNodeDrag(NodeId: string): ()
	AppState.UITreeDragState.IsDragging = true
	AppState.UITreeDragState.DraggedNodeId = NodeId
	AppState.UITreeDragState.HoveredTargetId = nil
end

--[[
Sets the target node for a drag drop operation.

Params:
    TargetId: string? -- The node being hovered

Returns:
]]
function UITree_Logic.SetNodeDragTarget(TargetId: string?): ()
	AppState.UITreeDragState.HoveredTargetId = TargetId
end

--[[
Cancels the current node drag operation.

Params:

Returns:
]]
function UITree_Logic.CancelNodeDrag(): ()
	AppState.UITreeDragState.IsDragging = false
	AppState.UITreeDragState.DraggedNodeId = nil
	AppState.UITreeDragState.HoveredTargetId = nil
	AppState.UITreeDragState.IsHoveringTrash = false
	AppState.UITreeDragState.IsHoveringDuplicate = false
end

--[[
Checks if an element has an active layout modifier that manages its children's positioning.

Params:
    Element: AppState.UIElement? -- The element to inspect

Returns:
    (string?, any?) -- The layout modifier class name and its properties table, or (nil, nil)
]]
local function getActiveLayoutModifier(Element: AppState.UIElement?): (string?, any?)
	if not Element then return nil, nil end

	for Key: string, Value: any in Element.Properties do
		if type(Value) == "table" and Value.IsModifier then
			local ModType: string = Value.Type or Key
			
			if ModType == "UIListLayout" or ModType == "UIGridLayout" or ModType == "UIPageLayout" or ModType == "UITableLayout" then
				return ModType, Value.Properties
			end
		end
	end

	return nil, nil
end

--[[
Retrieves the active camera viewport resolution, falling back to project metadata if unavailable.

Params:
    None

Returns:
    Vector2 -- The viewport resolution in pixels
]]
local function getViewportSize(): Vector2
	local camera: Camera? = Workspace.CurrentCamera
	
	if camera and camera.ViewportSize.X > 0 and camera.ViewportSize.Y > 0 then
		return camera.ViewportSize
	end
	
	return AppState.LiveProjectData.Metadata.CanvasSize
end

--[[
Calculates the relative offset from a parent's inner canvas origin to a child's top-left bounding corner.

Params:
    ChildId: string -- The child element ID
    ParentNode: AppState.UIElement -- The parent element struct
    ParentSize: Vector2 -- The parent's absolute dimensions

Returns:
    Vector2 -- The relative top-left offset
]]
local function getChildVisualRelativeOffset(ChildId: string, ParentNode: AppState.UIElement, ParentSize: Vector2): Vector2
	local ChildNode: AppState.UIElement? = AppState.WorkspaceElements[ChildId]
	
	if not ChildNode then return Vector2.zero end

	local LayoutType: string?, LayoutProps: any? = getActiveLayoutModifier(ParentNode)
	
	if LayoutType == "UIListLayout" then
		local FillDir = if LayoutProps and LayoutProps.FillDirection then LayoutProps.FillDirection else Enum.FillDirection.Vertical
		local PadUDim = if LayoutProps and LayoutProps.Padding then LayoutProps.Padding else UDim.new(0, 0)
		local PadX: number = ParentSize.X * PadUDim.Scale + PadUDim.Offset
		local PadY: number = ParentSize.Y * PadUDim.Scale + PadUDim.Offset
		local CurrentX = 0
		local CurrentY = 0

		for _, SiblingId: string in ipairs(ParentNode.Children) do
			if SiblingId == ChildId then
				break
			end
			
			local Sibling: AppState.UIElement? = AppState.WorkspaceElements[SiblingId]
			
			if Sibling and Sibling.Visible then
				local SibSizeX: number = ParentSize.X * Sibling.Size.X.Scale + Sibling.Size.X.Offset
				local SibSizeY: number = ParentSize.Y * Sibling.Size.Y.Scale + Sibling.Size.Y.Offset

				if FillDir == Enum.FillDirection.Horizontal or FillDir == "Horizontal" then
					CurrentX += SibSizeX + PadX
					
				else
					CurrentY += SibSizeY + PadY
				end
			end
		end

		return Vector2.new(CurrentX, CurrentY)

	elseif LayoutType == "UIGridLayout" then
		local CellUDim: UDim2 = if LayoutProps and LayoutProps.CellSize then LayoutProps.CellSize else UDim2.fromOffset(100, 100)
		local PadUDim: UDim2 = if LayoutProps and LayoutProps.CellPadding then LayoutProps.CellPadding else UDim2.fromOffset(5, 5)
		local MaxCells: number = if LayoutProps and LayoutProps.FillDirectionMaxCells then LayoutProps.FillDirectionMaxCells else 0
		local CellX: number = ParentSize.X * CellUDim.X.Scale + CellUDim.X.Offset
		local CellY: number = ParentSize.Y * CellUDim.Y.Scale + CellUDim.Y.Offset
		local PadX: number = ParentSize.X * PadUDim.X.Scale + PadUDim.X.Offset
		local PadY: number = ParentSize.Y * PadUDim.Y.Scale + PadUDim.Y.Offset
		local ChildIndex = 0

		for Idx: number, SiblingId: string in ipairs(ParentNode.Children) do
			if SiblingId == ChildId then
				ChildIndex = Idx - 1

				break
			end
		end

		local FillDir: any = if LayoutProps then LayoutProps.FillDirection else nil
		local IsVertical: boolean = FillDir == Enum.FillDirection.Vertical or FillDir == "Vertical"
		local EffectiveMaxCells: number = MaxCells

		if EffectiveMaxCells <= 0 then
			if IsVertical then
				local CellPlusPadY: number = CellY + PadY

				EffectiveMaxCells = if CellPlusPadY > 0 then math.max(1, math.floor((ParentSize.Y + PadY) / CellPlusPadY)) else 1

			else
				local CellPlusPadX: number = CellX + PadX

				EffectiveMaxCells = if CellPlusPadX > 0 then math.max(1, math.floor((ParentSize.X + PadX) / CellPlusPadX)) else 1
			end
		end

		local Col: number
		local Row: number

		if IsVertical then
			Row = ChildIndex % EffectiveMaxCells
			Col = math.floor(ChildIndex / EffectiveMaxCells)

		else
			Col = ChildIndex % EffectiveMaxCells
			Row = math.floor(ChildIndex / EffectiveMaxCells)
		end

		return Vector2.new(Col * (CellX + PadX), Row * (CellY + PadY))

	else
		-- Free-form positioning: calculate relative top-left by subtracting child's AnchorPoint offset
		local Anchor: any = ChildNode.Properties.AnchorPoint
		local AnchorPoint: Vector2 = if typeof(Anchor) == "Vector2" then Anchor else Vector2.new(0.5, 0.5)
		local PosX: number = ParentSize.X * ChildNode.Position.X.Scale + ChildNode.Position.X.Offset
		local PosY: number = ParentSize.Y * ChildNode.Position.Y.Scale + ChildNode.Position.Y.Offset
		local ChildSizeX: number = ParentSize.X * ChildNode.Size.X.Scale + ChildNode.Size.X.Offset
		local ChildSizeY: number = ParentSize.Y * ChildNode.Size.Y.Scale + ChildNode.Size.Y.Offset

		return Vector2.new(PosX - (ChildSizeX * AnchorPoint.X), PosY - (ChildSizeY * AnchorPoint.Y))
	end
end

--[[
Recursively calculates:
1. The absolute top-left position of the element's bounding box on the screen
2. The absolute size of the element on the screen
3. The absolute inner origin for its children (accounting for CanvasPosition and UIPadding)

Params:
    NodeId: string? -- The element ID (or nil for the root screen container)

Returns:
    (Vector2, Vector2, Vector2) -- TopLeft, Size, and InnerOrigin
]]
local function getElementMetrics(NodeId: string?): (Vector2, Vector2, Vector2)
	-- Root screen container
	if not NodeId then
		return Vector2.zero, getViewportSize(), Vector2.zero
	end

	local Node: AppState.UIElement? = AppState.WorkspaceElements[NodeId]
	
	if not Node then
		return Vector2.zero, Vector2.zero, Vector2.zero
	end

	-- Get parent metrics
	local _, ParentSize: Vector2, ParentInnerOrigin: Vector2 = getElementMetrics(Node.ParentId)

	-- Calculate node size
	local ParentNode: AppState.UIElement? = if Node.ParentId then AppState.WorkspaceElements[Node.ParentId] else nil
	local LayoutType: string?, LayoutProps: any? = getActiveLayoutModifier(ParentNode)
	local NodeSize: Vector2

	if LayoutType == "UIGridLayout" and LayoutProps and LayoutProps.CellSize then
		NodeSize = Vector2.new(ParentSize.X * LayoutProps.CellSize.X.Scale + LayoutProps.CellSize.X.Offset, ParentSize.Y * LayoutProps.CellSize.Y.Scale + LayoutProps.CellSize.Y.Offset)
		
	else
		NodeSize = Vector2.new(ParentSize.X * Node.Size.X.Scale + Node.Size.X.Offset, ParentSize.Y * Node.Size.Y.Scale + Node.Size.Y.Offset)
	end

	-- Calculate node top-left corner on screen
	local NodeTopLeft: Vector2
	
	if ParentNode then
		NodeTopLeft = ParentInnerOrigin + getChildVisualRelativeOffset(NodeId, ParentNode, ParentSize)
		
	else
		-- Root element (parent is Screen)
		local Anchor: any = Node.Properties.AnchorPoint
		local AnchorPoint: Vector2 = if typeof(Anchor) == "Vector2" then Anchor else Vector2.new(0.5, 0.5)
		local PosX: number = ParentSize.X * Node.Position.X.Scale + Node.Position.X.Offset
		local PosY: number = ParentSize.Y * Node.Position.Y.Scale + Node.Position.Y.Offset
		
		NodeTopLeft = Vector2.new(PosX - (NodeSize.X * AnchorPoint.X), PosY - (NodeSize.Y * AnchorPoint.Y))
	end

	-- Inner origin for this node's children
	local InnerOrigin: Vector2 = NodeTopLeft

	-- Account for ScrollingFrame CanvasPosition
	if Node.Type == "ScrollingFrame" and typeof(Node.Properties.CanvasPosition) == "Vector2" then
		InnerOrigin = InnerOrigin - Node.Properties.CanvasPosition
	end

	-- Account for UIPadding modifier if present
	local Padding: any = Node.Properties.UIPadding
	
	if type(Padding) == "table" and Padding.IsModifier and Padding.Properties then
		local PadLeft: any = Padding.Properties.PaddingLeft
		local PadTop: any = Padding.Properties.PaddingTop
		local PadX: number = if typeof(PadLeft) == "UDim" then (NodeSize.X * PadLeft.Scale + PadLeft.Offset) else 0
		local PadY: number = if typeof(PadTop) == "UDim" then (NodeSize.Y * PadTop.Scale + PadTop.Offset) else 0
		
		InnerOrigin = InnerOrigin + Vector2.new(PadX, PadY)
	end

	return NodeTopLeft, NodeSize, InnerOrigin
end

--[[
Reparents a node to a new parent node with layout-aware position preservation.

Params:
    NodeId: string -- The node to reparent
    TargetParentId: string? -- The new parent node (or nil for root)

Returns:
    () -- No return value
]]
function UITree_Logic.ReparentElement(NodeId: string, TargetParentId: string?): ()
	History_Logic.PushSnapshot()

	local Node: AppState.UIElement? = AppState.WorkspaceElements[NodeId]
	
	if not Node then return end

	-- Capture the element's current absolute top-left and size on screen before mutating parent
	local CurrentTopLeft: Vector2, CurrentSize: Vector2 = getElementMetrics(NodeId)

	-- Remove from old parent
	if Node.ParentId then
		local OldParent: AppState.UIElement? = AppState.WorkspaceElements[Node.ParentId]
		
		if OldParent then
			local NewChildren: { string } = {}
			
			for _, ChildId: string in ipairs(OldParent.Children) do
				if ChildId ~= NodeId then
					NewChildren[#NewChildren + 1] = ChildId
				end
			end
			
			OldParent.Children = NewChildren
		end
	end

	-- Set new parent
	Node.ParentId = TargetParentId

	-- Add to new parent
	local NewParent: AppState.UIElement? = if TargetParentId then AppState.WorkspaceElements[TargetParentId] else nil
	
	if NewParent then
		NewParent.Children[#NewParent.Children + 1] = NodeId
	end

	-- Check if the target parent has an active layout modifier (UIListLayout, UIGridLayout, etc.)
	if getActiveLayoutModifier(NewParent) then
		-- In Roblox, layout modifiers completely control child positioning.
		-- Reset Position to (0, 0) so the Properties Editor does not display stale arbitrary offsets.
		Node.Position = UDim2.fromOffset(0, 0)

		if NewParent then
			Node.Properties.LayoutOrder = #NewParent.Children
		end
		
	else
		-- Target parent allows free-form positioning (no layout modifier).
		-- Calculate the new parent's inner origin:
		local _, _, NewParentInnerOrigin: Vector2 = getElementMetrics(TargetParentId)

		-- Get Node's AnchorPoint
		local AnchorPoint: Vector2 = if typeof(Node.Properties.AnchorPoint) == "Vector2" then Node.Properties.AnchorPoint else Vector2.new(0.5, 0.5)

		-- Calculate screen position of Node's AnchorPoint
		local AnchorScreenX: number = CurrentTopLeft.X + (CurrentSize.X * AnchorPoint.X)
		local AnchorScreenY: number = CurrentTopLeft.Y + (CurrentSize.Y * AnchorPoint.Y)

		-- Relative offset from new parent's inner origin
		local RelX: number = AnchorScreenX - NewParentInnerOrigin.X
		local RelY: number = AnchorScreenY - NewParentInnerOrigin.Y

		-- Maintain exact visual screen position with zero drift
		Node.Position = UDim2.fromOffset(math.round(RelX), math.round(RelY))
	end

	-- Cleanup state
	UITree_Logic.CancelNodeDrag()
end

--[[
Toggles visibility for an element and cascades to its children.

Params:
    NodeId: string -- The node to toggle

Returns:
]]
function UITree_Logic.ToggleElementVisibility(NodeId: string): ()
	local Node = AppState.WorkspaceElements[NodeId]
	
	if not Node then return end

	History_Logic.PushSnapshot()

	local NewVisibility = not Node.Visible
	
	local function cascadeVisibility(CurrentId: string): ()
		local CurrentNode = AppState.WorkspaceElements[CurrentId]
		
		if CurrentNode then
			CurrentNode.Visible = NewVisibility
			
			for _, ChildId in ipairs(CurrentNode.Children) do
				cascadeVisibility(ChildId)
			end
		end
	end

	cascadeVisibility(NodeId)
end

--[[
Deletes an element and all its descendants.

Params:
    NodeId: string -- The node to delete

Returns:
]]
function UITree_Logic.DeleteElement(NodeId: string): ()
	local Node = AppState.WorkspaceElements[NodeId]
	
	if not Node then return end

	History_Logic.PushSnapshot()

	-- Remove from parent
	if Node.ParentId then
		local ParentNode = AppState.WorkspaceElements[Node.ParentId]
		
		if ParentNode then
			local NewChildren: { string } = {}
			
			for _, ChildId in ipairs(ParentNode.Children) do
				if ChildId ~= NodeId then
					NewChildren[#NewChildren + 1] = ChildId
				end
			end
			
			ParentNode.Children = NewChildren
		end
	end

	local function cascadeDelete(CurrentId: string): ()
		local CurrentNode = AppState.WorkspaceElements[CurrentId]
		
		if CurrentNode then
			for _, ChildId in ipairs(CurrentNode.Children) do
				cascadeDelete(ChildId)
			end
			
			AppState.WorkspaceElements[CurrentId] = nil

			-- Clear selection if deleting selected element
			if AppState.SelectedElementId == CurrentId then
				AppState.SelectedElementId = nil
			end

			-- Clear active dial trackers if referencing this deleted element
			if AppState.SessionState.PositionDialTracker.ElementId == CurrentId then
				AppState.SessionState.PositionDialTracker.ElementId = nil
				AppState.SessionState.PositionDialTracker.OriginalPosition = nil
			end
			
			if AppState.SessionState.SizeDialTracker.ElementId == CurrentId then
				AppState.SessionState.SizeDialTracker.ElementId = nil
				AppState.SessionState.SizeDialTracker.OriginalSize = nil
			end
			
			if AppState.SessionState.RotationDialTracker.ElementId == CurrentId then
				AppState.SessionState.RotationDialTracker.ElementId = nil
				AppState.SessionState.RotationDialTracker.OriginalRotation = nil
			end
		end
	end

	cascadeDelete(NodeId)
	UITree_Logic.CancelNodeDrag()
end

--[[
Sets whether the node drag operation is hovering over the trash.

Params:
    IsHovering: boolean -- Whether the mouse is hovering the trash button

Returns:
]]
function UITree_Logic.SetNodeDragTrash(IsHovering: boolean): ()
	AppState.UITreeDragState.IsHoveringTrash = IsHovering
end

--[[
Sets whether the node drag operation is hovering over the duplicate button.

Params:
    IsHovering: boolean -- Whether the mouse is hovering the duplicate button

Returns:
]]
function UITree_Logic.SetNodeDragDuplicate(IsHovering: boolean): ()
	AppState.UITreeDragState.IsHoveringDuplicate = IsHovering
end

-- Deeply clones a table structure to ensure independent memory references.
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

--[[
Duplicates an element and all its descendants to the root level.

Params:
    NodeId: string -- The node to duplicate

Returns:
]]
function UITree_Logic.DuplicateElement(NodeId: string): ()
	local OriginalNode = AppState.WorkspaceElements[NodeId]
	
	if not OriginalNode then return end

	History_Logic.PushSnapshot()

	local function cloneNode(CurrentId: string, NewParentId: string?, IsRoot: boolean): string?
		local NodeToClone = AppState.WorkspaceElements[CurrentId]
		
		if not NodeToClone then return nil end

		local NewId = HttpService:GenerateGUID(false)
		local PropertiesCopy = deepCloneTable(NodeToClone.Properties)
		local NewName = NodeToClone.Name .. "_Copy"
		
		local ClonedNode: AppState.UIElement = {
			Id = NewId,
			Type = NodeToClone.Type,
			Name = NewName,
			ParentId = NewParentId,
			Children = {},
			Properties = PropertiesCopy,
			Position = NodeToClone.Position,
			Size = NodeToClone.Size,
			Visible = NodeToClone.Visible,
		}
		
		AppState.WorkspaceElements[NewId] = ClonedNode
		
		for _, ChildId in ipairs(NodeToClone.Children) do
			local ClonedChildId = cloneNode(ChildId, NewId, false)
			
			if ClonedChildId then
				ClonedNode.Children[#ClonedNode.Children + 1] = ClonedChildId
			end
		end
		
		return NewId
	end

	local NewRootId = cloneNode(NodeId, nil, true)
	
	if NewRootId then
		AppState.SelectedElementId = NewRootId
	end
	
	UITree_Logic.CancelNodeDrag()
end

----------------------------------------------------------
return UITree_Logic :: UITree_Logic
----------------------------------------------------------