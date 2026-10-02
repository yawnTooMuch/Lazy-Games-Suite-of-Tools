--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Drag_Controller.luau
    
    SCOPE: Elements Provider / Drag and Drop / Controller Pillar
    
    ROLE: Intermediary controller connecting Relay action signals (InitiateDrag,
          DropElement) to Backend Drag_Logic, and firing state change signals
          (DragStateChanged, WorkspaceElementsUpdated) to trigger UI re-renders.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Controller Type Structures Section
----------------------------------------------------------
export type Drag_Controller = {
	Init: () -> ()
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Controller Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local Drag_Logic = require(script.Parent.Parent.Parent.Backend.Elements_Provider.Drag_Logic)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Controller Internal States Section
----------------------------------------------------------
local Drag_Controller = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Controller Local Function Section
----------------------------------------------------------
-- Handles the initiation of an element drag.
local function onInitiateDrag(ElementType: string): ()
	Drag_Logic.InitiateDrag(ElementType)
	Relay.Create("DragStateChanged"):Fire()
end

-- Handles dropping an element at a position.
local function onDropElement(Position: UDim2): ()
	Drag_Logic.DropElement(Position)
	Relay.Create("DragStateChanged"):Fire()
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Controller Public APIs Section
----------------------------------------------------------
--[[
Initializes the Drag_Controller by connecting Relay listeners.

Params:
    None

Returns:
    nil
]]
function Drag_Controller.Init(): ()
	Relay.Create("InitiateDrag"):Connect(onInitiateDrag)
	Relay.Create("DropElement"):Connect(onDropElement)
end

----------------------------------------------------------
return Drag_Controller :: Drag_Controller
----------------------------------------------------------