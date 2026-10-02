--!strict
local RunService: RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end

--[[
    ===========================================================================
    MODULE/COMPONENT: ExportCompiler_Linter.legacy.luau
    
    SCOPE: UI Tree / Export Compiler
    
    ROLE: Validates export preconditions (selected root element, valid component
          name identifier) before forwarding actions to the controller.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ExportCompiler_Linter Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ExportCompiler_Linter Local Function Section
----------------------------------------------------------

--[[
Validates and toggles the export dialog visibility.
]]
local function onToggleExportDialog(): ()
	if AppState.SessionState.IsExportDialogVisible then
		Relay.Create("ToggleExportDialog"):Fire()
		
		return
	end

	local SelectedId: string? = AppState.SelectedElementId
	
	if not SelectedId or not AppState.WorkspaceElements[SelectedId] then
		Relay.Create("ShowNotification"):Fire({
			Message = "Export Failed. No Element Selected.",
			Type = "Error",
		})
		
		return
	end

	local SelectedElement: AppState.UIElement = AppState.WorkspaceElements[SelectedId]
	
	if SelectedElement.ParentId ~= nil then
		Relay.Create("ShowNotification"):Fire({
			Message = "Export Failed. Selected Element Must Be A Root Node.",
			Type = "Error",
		})
		
		return
	end

	Relay.Create("ToggleExportDialog"):Fire()
end

--[[
Validates export request parameters before routing to the controller.
]]
local function onExportProject(Payload: any): ()
	local ComponentName: string = ""
	local Framework: string? = nil

	if type(Payload) == "string" then
		ComponentName = Payload
		
	elseif type(Payload) == "table" then
		if type(Payload.ComponentName) == "string" then
			ComponentName = Payload.ComponentName
		end
		
		if type(Payload.Framework) == "string" then
			Framework = Payload.Framework
		end
	end

	-- Validate Framework selection
	if not Framework or string.len(Framework) == 0 then
		Relay.Create("ShowNotification"):Fire({
			Message = "Export Failed. No Framework Selected.",
			Type = "Error",
		})
		
		return
	end

	-- Validate ComponentName identifier
	if string.len(ComponentName) == 0 or not string.match(ComponentName, "^[%a_][%w_]*$") then
		Relay.Create("ShowNotification"):Fire({
			Message = "Export Failed. Component Name Must Be A Valid Identifier.",
			Type = "Error",
		})
		
		return
	end

	-- Validate SelectedElementId exists and is root
	local SelectedId: string? = AppState.SelectedElementId
	
	if not SelectedId or not AppState.WorkspaceElements[SelectedId] then
		Relay.Create("ShowNotification"):Fire({
			Message = "Export Failed. Target Root Element Not Found.",
			Type = "Error",
		})
		
		return
	end

	local SelectedElement: AppState.UIElement = AppState.WorkspaceElements[SelectedId]
	
	if SelectedElement.ParentId ~= nil then
		Relay.Create("ShowNotification"):Fire({
			Message = "Export Failed. Target Element Must Be A Root Node.",
			Type = "Error",
		})
		
		return
	end

	-- Fire action signal to Controller
	Relay.Create("ExportProject"):Fire({
		ComponentName = ComponentName,
		RootId = SelectedId,
		Framework = Framework,
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ExportCompiler_Linter Event Binding Section
----------------------------------------------------------
Relay.Create("ToggleExportDialog_CL"):Connect(onToggleExportDialog)
Relay.Create("ExportProject_CL"):Connect(onExportProject)