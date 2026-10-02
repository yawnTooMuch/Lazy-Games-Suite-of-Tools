--!strict
local RunService: RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

--[[
    ===========================================================================
    MODULE/COMPONENT: ImportCompiler_Linter.legacy.luau
    
    SCOPE: UI Tree / Import Compiler
    
    ROLE: Validates import preconditions (valid Studio instance selection,
          ModuleScript bytecode presence or supported GuiObject hierarchy,
          and UI Tree selection for Replace_Selected mode) before routing
          to the controller.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.Parent.AppState)
local Bytecode_Reader = require(script.Parent.Parent.Parent.Backend.UI_Tree.ImportCompiler.Bytecode_Reader)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Function Section
----------------------------------------------------------

--[[
Validates and toggles the import dialog visibility.
]]
local function onToggleImportDialog(): ()
	Relay.Create("ToggleImportDialog"):Fire()
end

--[[
Validates an import project request payload before routing to the controller.
]]
local function onImportProject(Payload: any): ()
	if type(Payload) ~= "table" then
		Relay.Create("ShowNotification"):Fire({
			Message = "Import Failed. Invalid Request Payload.",
			Type = "Error",
		})
		
		return
	end

	local Mode: any = Payload.Mode
	
	if Mode ~= "Append" and Mode ~= "Replace" and Mode ~= "Replace_Selected" then
		Relay.Create("ShowNotification"):Fire({
			Message = "Import Failed. Invalid Import Mode.",
			Type = "Error",
		})
		
		return
	end

	local TargetInstance: any = Payload.TargetInstance
	
	if not TargetInstance or typeof(TargetInstance) ~= "Instance" then
		Relay.Create("ShowNotification"):Fire({
			Message = "Import Failed. No Studio Object Selected.",
			Type = "Error",
		})
		
		return
	end

	-- Validate source capability
	if TargetInstance:IsA("ModuleScript") then
		local Program = Bytecode_Reader.ExtractFromSource((TargetInstance :: ModuleScript).Source)
		
		if not Program then
			Relay.Create("ShowNotification"):Fire({
				Message = "Import Failed. ModuleScript Contains No GUI Builder Bytecode.",
				Type = "Error",
			})
			
			return
		end
		
	elseif not TargetInstance:IsA("GuiObject") and not TargetInstance:IsA("ScreenGui") and not TargetInstance:IsA("LayerCollector") then
		Relay.Create("ShowNotification"):Fire({
			Message = "Import Failed. Selected Object Is Not A Supported GUI Object Or Exported ModuleScript.",
			Type = "Error",
		})
		
		return
	end

	-- Validate mode requirements
	if Mode == "Replace_Selected" then
		local SelectedId: string? = AppState.SelectedElementId
		
		if not SelectedId or not AppState.WorkspaceElements[SelectedId] then
			Relay.Create("ShowNotification"):Fire({
				Message = "Import Failed. No Target Element Selected In UI Tree.",
				Type = "Error",
			})
			
			return
		end
	end

	-- All preconditions satisfied: forward to Controller
	Relay.Create("ImportProject"):Fire({
		TargetInstance = TargetInstance,
		Mode = Mode,
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Event Binding Section
----------------------------------------------------------
Relay.Create("ToggleImportDialog_CL"):Connect(onToggleImportDialog)
Relay.Create("ImportProject_CL"):Connect(onImportProject)