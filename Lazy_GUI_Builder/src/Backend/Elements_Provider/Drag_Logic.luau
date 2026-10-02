--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Drag_Logic.luau
    
    SCOPE: Backend (Logic Pillar)
    
    ROLE: Sole writer to AppState. Handles mutations related to element dragging
          and registering new dropped virtual elements into the DOM.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Logic Type Structures Section
----------------------------------------------------------
export type Drag_Logic = {
	InitiateDrag: (ElementType: string) -> (),
	DropElement: (Position: UDim2) -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Logic Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.Parent.AppState)
local History_Logic = require(script.Parent.Parent.History_Logic)
local PropertyRegistry = require(script.Parent.Parent.Parent.PropertyRegistry)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Logic Imported Services Section
----------------------------------------------------------
local HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Logic Internal States Section
----------------------------------------------------------
local Drag_Logic = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Logic Public APIs Section
----------------------------------------------------------
--[[
Initiates a dragging state in the AppState memory.

Params:
    ElementType: string -- The type of element being dragged

Returns:
    nil -- No return value
]]
function Drag_Logic.InitiateDrag(ElementType: string): ()
	AppState.DragState.IsDragging = true
	AppState.DragState.ElementType = ElementType
end

--[[
Consumes the active drag state and registers a new virtual element into memory.

Params:
    Position: UDim2 -- The drop position

Returns:
    nil -- No return value
]]
function Drag_Logic.DropElement(Position: UDim2): ()
	if not AppState.DragState.IsDragging or not AppState.DragState.ElementType then
		return
	end

	local ElementId: string = HttpService:GenerateGUID(false)

	History_Logic.PushSnapshot()
	
	-- Register into the Virtual DOM
	AppState.WorkspaceElements[ElementId] = {
		Id = ElementId,
		Type = AppState.DragState.ElementType,
		Name = AppState.DragState.ElementType,
		ParentId = nil,
		Children = {},
		Properties = PropertyRegistry.GetDefaultsForType(AppState.DragState.ElementType),
		Position = Position,
		Size = UDim2.fromOffset(100, 100), -- Default spawned size
		Visible = true,
	}

	-- Reset Drag State
	AppState.DragState.IsDragging = false
	AppState.DragState.ElementType = nil
end

----------------------------------------------------------
return Drag_Logic :: Drag_Logic
----------------------------------------------------------