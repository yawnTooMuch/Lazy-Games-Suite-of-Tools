--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Session_Controller.luau
    
    SCOPE: Plugin Session / Window State / Controller Pillar
    
    ROLE: General-purpose controller managing plugin session traffic,
          subscribing to Relay action signals (UpdateProviderPosition,
          ToggleProvider, ToggleRenderEngine), routing state updates to
          Backend Session_Logic, and firing state refresh notifications.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Controller Type Structures Section
----------------------------------------------------------
export type Session_Controller = {
	Init: () -> ()
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Controller Dependency Section
----------------------------------------------------------
local Session_Logic = require(script.Parent.Parent.Backend.Session_Logic)
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Controller Internal States Section
----------------------------------------------------------
local Session_Controller = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Controller Local Functions Section
----------------------------------------------------------
-- Closes all floating property editors.
local function closeFloatingEditors(): ()
	Relay.Create("CloseColorPicker"):Fire()
	Relay.Create("CloseGradientEditor"):Fire()
	Relay.Create("CloseTransparencyEditor"):Fire()
end

-- Handles updating the provider window position.
local function onUpdateProviderPosition(NewPosition: UDim2): ()
	Session_Logic.UpdateProviderPosition(NewPosition)
end

-- Handles toggling the provider window.
local function onToggleProvider(): ()
	Session_Logic.ToggleProvider()
	Relay.Create("SessionStateUpdated"):Fire()
end

-- Handles toggling the render engine (global eye / canvas visibility).
local function onToggleRenderEngine(): ()
	closeFloatingEditors()
	Session_Logic.ToggleRenderEngine()
	Relay.Create("SessionStateUpdated"):Fire()
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Controller Public APIs Section
----------------------------------------------------------
--[[
Initializes the session controller.

Params:
    None

Returns:
    None
]]
function Session_Controller.Init(): ()
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
-- Session_Controller Event Binding Section
----------------------------------------------------------
Relay.Create("UpdateProviderPosition"):Connect(onUpdateProviderPosition)
Relay.Create("ToggleProvider"):Connect(onToggleProvider)
Relay.Create("ToggleRenderEngine"):Connect(onToggleRenderEngine)

----------------------------------------------------------
return Session_Controller :: Session_Controller
----------------------------------------------------------