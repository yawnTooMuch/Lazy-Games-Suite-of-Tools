--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: MasterRoot_Component.luau
    
    SCOPE: Root UI Component / Signal Lifecycle Owner
    
    ROLE: Permanent root of the plugin's React component tree. Owns and protects
          the global Relay signal registry from premature teardown, and renders
          all top-level feature windows, floating editors, and dialogs.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- MasterRoot_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.AppState)
local ElementProvider_Component = require(script.Parent.Elements_Provider.ElementProvider_Component)
local UITree_Component = require(script.Parent.UI_Tree.UITree_Component)
local Workspace_Component = require(script.Parent.Workspace_Component)
local ColorPickerWindow_Component = require(script.Parent.ColorPickerWindow_Component)
local GradientEditorWindow_Component = require(script.Parent.GradientEditorWindow_Component)
local TransparencyEditorWindow_Component = require(script.Parent.TransparencyEditorWindow_Component)
local PositionSettings_Component = require(script.Parent.Properties_Editor.Dependencies.PositionSettings_Component)
local SizeSettings_Component = require(script.Parent.Properties_Editor.Dependencies.SizeSettings_Component)
local RotationSettings_Component = require(script.Parent.Properties_Editor.Dependencies.RotationSettings_Component)
local NotificationCenter_Component = require(script.Parent.NotificationCenter_Component)
local ExportDialog_Component = require(script.Parent.UI_Tree.ExportDialog_Component)
local ImportDialog_Component = require(script.Parent.UI_Tree.ImportDialog_Component)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- MasterRoot_Component Public APIs Section
----------------------------------------------------------
--[[
The absolute root of the React tree. It stays permanently mounted 
to own and protect the Relay signals array from being destroyed.
Conditionally renders the floating UI or canvas based on AppState.

Params:
    None

Returns:
    any -- The root fragment component
]]
local function MasterRoot(): any
	local UpdateState: boolean, SetUpdateState = React.useState(false)

	React.useEffect(function(): (() -> ())?
		local Signals: { Relay.SignalObject } = {
			Relay.Create("UpdateProviderPosition"),
			Relay.Create("UpdateUITreePosition"),
			Relay.Create("InitiateNodeDrag_CL"),
			Relay.Create("InitiateNodeDrag"),
			Relay.Create("SetNodeDragTarget_CL"),
			Relay.Create("SetNodeDragTarget"),
			Relay.Create("CancelNodeDrag_CL"),
			Relay.Create("CancelNodeDrag"),
			Relay.Create("ReparentElement_CL"),
			Relay.Create("ReparentElement"),
			Relay.Create("InitiateDrag_CL"),
			Relay.Create("InitiateDrag"),
			Relay.Create("DropElement_CL"),
			Relay.Create("DropElement"),
			Relay.Create("WorkspaceElementsUpdated"),
			Relay.Create("DragStateChanged"),
			Relay.Create("ToggleProvider_CL"),
			Relay.Create("ToggleProvider"),
			Relay.Create("ToggleRenderEngine_CL"),
			Relay.Create("ToggleRenderEngine"),
			Relay.Create("ToggleUITree_CL"),
			Relay.Create("ToggleUITree"),
			Relay.Create("SelectElement_CL"),
			Relay.Create("SelectElement"),
			Relay.Create("ElementSelected"),
			Relay.Create("SessionStateUpdated"),
			Relay.Create("UITreeUpdated"),
			Relay.Create("ToggleElementVisibility_CL"),
			Relay.Create("ToggleElementVisibility"),
			Relay.Create("DeleteElement_CL"),
			Relay.Create("DeleteElement"),
			Relay.Create("SetNodeDragTrash_CL"),
			Relay.Create("SetNodeDragTrash"),
			Relay.Create("SetNodeDragDuplicate_CL"),
			Relay.Create("SetNodeDragDuplicate"),
			Relay.Create("DuplicateElement_CL"),
			Relay.Create("DuplicateElement"),
			Relay.Create("Undo_CL"),
			Relay.Create("Undo"),
			Relay.Create("Redo_CL"),
			Relay.Create("Redo"),
			Relay.Create("OpenColorPicker"),
			Relay.Create("CloseColorPicker"),
			Relay.Create("ColorPickerLiveUpdate"),
			Relay.Create("ColorPickerSubmitted"),
			Relay.Create("OpenGradientEditor"),
			Relay.Create("CloseGradientEditor"),
			Relay.Create("GradientEditorLiveUpdate"),
			Relay.Create("GradientEditorSubmitted"),
			Relay.Create("OpenTransparencyEditor"),
			Relay.Create("CloseTransparencyEditor"),
			Relay.Create("TransparencyEditorLiveUpdate"),
			Relay.Create("TransparencyEditorSubmitted"),
			Relay.Create("TogglePropertiesEditor_CL"),
			Relay.Create("TogglePropertiesEditor"),
			Relay.Create("SetElementName_CL"),
			Relay.Create("SetElementName"),
			Relay.Create("SetElementPosition_CL"),
			Relay.Create("SetElementPosition"),
			Relay.Create("SetElementSize_CL"),
			Relay.Create("SetElementSize"),
			Relay.Create("SetElementRotation_CL"),
			Relay.Create("SetElementRotation"),
			Relay.Create("SetElementVisible_CL"),
			Relay.Create("SetElementVisible"),
			Relay.Create("SetElementProperty_CL"),
			Relay.Create("SetElementProperty"),
			Relay.Create("TogglePositionSettings"),
			Relay.Create("UpdatePositionEditorSettings"),
			Relay.Create("ToggleSizeSettings"),
			Relay.Create("UpdateSizeEditorSettings"),
			Relay.Create("PreviewElementProperty"),
			Relay.Create("CommitPreviewedProperty"),
			Relay.Create("AddModifier_CL"),
			Relay.Create("AddModifier"),
			Relay.Create("RemoveModifier_CL"),
			Relay.Create("RemoveModifier"),
			Relay.Create("SetModifierProperty_CL"),
			Relay.Create("SetModifierProperty"),
			Relay.Create("PreviewModifierProperty"),
			Relay.Create("CommitPreviewedModifierProperty"),
			Relay.Create("SetAnchorPointVisualVisible"),
			Relay.Create("ToggleRotationSettings"),
			Relay.Create("UpdateRotationEditorSettings"),
			Relay.Create("ShowNotification"),
			Relay.Create("ToggleExportDialog_CL"),
			Relay.Create("ToggleExportDialog"),
			Relay.Create("ExportProject_CL"),
			Relay.Create("ExportProject"),
			Relay.Create("ExportCompleted"),
			Relay.Create("ToggleImportDialog_CL"),
			Relay.Create("ToggleImportDialog"),
			Relay.Create("ImportProject_CL"),
			Relay.Create("ImportProject"),
			Relay.Create("ImportCompleted"),
		}

		Relay.Create("SessionStateUpdated"):Connect(function(): ()
			SetUpdateState(function(Prev: boolean): boolean
				return not Prev
			end)
		end)
		
		return function(): ()
			for _, Signal: Relay.SignalObject in ipairs(Signals) do
				Signal:Destroy()
			end
			
			table.clear(Signals)
		end
	end, {})

	return React.createElement(React.Fragment, nil, {
		ElementProvider = React.createElement(ElementProvider_Component, {
			Visible = AppState.SessionState.IsProviderVisible,
		}),
		
		WorkspaceCanvas = React.createElement(Workspace_Component, {
			Visible = AppState.SessionState.IsRenderEngineVisible,
		}),
		
		UITree = React.createElement(UITree_Component, {
			Visible = AppState.SessionState.IsUITreeVisible,
		}),
		
		ColorPickerWindow = React.createElement(ColorPickerWindow_Component, {}),
		
		GradientEditorWindow = React.createElement(GradientEditorWindow_Component, {}),
		
		TransparencyEditorWindow = React.createElement(TransparencyEditorWindow_Component, {}),
		
		PositionSettingsModal = React.createElement(PositionSettings_Component, {
			Visible = AppState.SessionState.IsPositionSettingsVisible,
			Settings = AppState.SessionState.PositionEditorSettings,
		}),
		
		SizeSettingsModal = React.createElement(SizeSettings_Component, {
			Visible = AppState.SessionState.IsSizeSettingsVisible,
			Settings = AppState.SessionState.SizeEditorSettings,
		}),
		
		RotationSettingsModal = React.createElement(RotationSettings_Component, {
			Visible = AppState.SessionState.IsRotationSettingsVisible,
			Settings = AppState.SessionState.RotationEditorSettings,
		}),
		
		NotificationCenter = React.createElement(NotificationCenter_Component, {}),

		ExportDialog = React.createElement(ExportDialog_Component, {
			Visible = AppState.SessionState.IsExportDialogVisible,
		}),

		ImportDialog = React.createElement(ImportDialog_Component, {
			Visible = AppState.SessionState.IsImportDialogVisible,
		}),
	})
end

----------------------------------------------------------
return MasterRoot
----------------------------------------------------------