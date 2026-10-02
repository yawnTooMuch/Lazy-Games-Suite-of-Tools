--!strict

local RunService: RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end
-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Linter Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Linter Local Function Section
----------------------------------------------------------
-- Currently no strict validation needed to toggle a window, but this pipeline is established for future constraints.
local function onToggleProviderCl(): ()
    Relay.Create("ToggleProvider"):Fire()
end

-- Validates toggle render engine requests
local function onToggleRenderEngineCl(): ()
    Relay.Create("ToggleRenderEngine"):Fire()
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Session_Linter Event Binding Section
----------------------------------------------------------
Relay.Create("ToggleProvider_CL"):Connect(onToggleProviderCl)
Relay.Create("ToggleRenderEngine_CL"):Connect(onToggleRenderEngineCl)