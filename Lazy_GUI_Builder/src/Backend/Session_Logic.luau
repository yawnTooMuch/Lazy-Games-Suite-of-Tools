--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Session_Logic.luau
    
    SCOPE: Plugin Session / Window State / Database Writer
    
    ROLE: General backend logic responsible for mutating AppState session
          records, including Elements Provider window coordinates and
          visibility toggles for the provider and render engine widgets.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Logic Type Structures Section
----------------------------------------------------------
export type SessionLogic = {
	UpdateProviderPosition: (NewPosition: UDim2) -> (),
	ToggleProvider: () -> (),
	ToggleRenderEngine: () -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Logic Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Logic Internal States Section
----------------------------------------------------------
local SessionLogic = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Logic Public APIs Section
----------------------------------------------------------
--[[
Updates the Provider UI window position in the session state.
 
Params:
    NewPosition: UDim2 -- The new position for the window
 
Returns:
    () -- No return value
]]
function SessionLogic.UpdateProviderPosition(NewPosition: UDim2): ()
	AppState.SessionState.ProviderPosition = NewPosition
end

--[[
Toggles the visibility of the provider widget in the session state.
 
Returns:
    () -- No return value
]]
function SessionLogic.ToggleProvider(): ()
	AppState.SessionState.IsProviderVisible = not AppState.SessionState.IsProviderVisible
end

--[[
Toggles the visibility of the render engine widget in the session state.
 
Returns:
    () -- No return value
]]
function SessionLogic.ToggleRenderEngine(): ()
	AppState.SessionState.IsRenderEngineVisible = not AppState.SessionState.IsRenderEngineVisible
end

----------------------------------------------------------
return SessionLogic :: SessionLogic
----------------------------------------------------------