--!strict

local RunService: RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

--[[
    ===========================================================================
    MODULE/COMPONENT: Drag_Linter.legacy.luau
    
    SCOPE: Correctness Linter Pillar
    
    ROLE: Validates all drag-and-drop user intents (Initiate, Drop) to ensure
          data integrity before letting it reach the Backend.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Linter Configuration Section
----------------------------------------------------------
local VALID_ELEMENTS: { [string]: boolean } = {
    Frame = true,
    TextLabel = true,
    TextButton = true,
    TextBox = true,
    ImageLabel = true,
    ImageButton = true,
    ScrollingFrame = true,
    CanvasGroup = true,
    VideoFrame = true,
    ViewportFrame = true,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Linter Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Drag_Linter Event Binding Section
----------------------------------------------------------
Relay.Create("InitiateDrag_CL"):Connect(function(ElementType: string): ()
    if type(ElementType) == "string" and VALID_ELEMENTS[ElementType] then
		Relay.Create("InitiateDrag"):Fire(ElementType)
		
    else
		Relay.Create("ShowNotification"):Fire({
			Message = "Initiated Drag Failed. Invalid Element Type.",
			Type = "Error"
		})
    end
end)

Relay.Create("DropElement_CL"):Connect(function(Position: UDim2): ()
    if typeof(Position) == "UDim2" then
		Relay.Create("DropElement"):Fire(Position)
		
    else
		Relay.Create("ShowNotification"):Fire({
			Message = "Element Drop Failed. Invalid Target Position.",
			Type = "Error"
		})
    end
end)