--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: PropertiesEditor_Controller.luau
    
    SCOPE: Feature Controller Pillar
    
    ROLE: Routes trusted action signals from the Linter to the Backend, then
          fires notification signals to update the UI.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Controller Type Structures Section
----------------------------------------------------------
export type PropertiesEditor_Controller = {
	Init: () -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Controller Dependency Section
----------------------------------------------------------
local PropertiesEditor_Logic = require(script.Parent.Parent.Parent.Backend.Properties_Editor.PropertiesEditor_Logic)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local Assignment = require(script.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Controller Internal States Section
----------------------------------------------------------
local PropertiesEditor_Controller = {}
local AnchorPointVisualHandle: Assignment.Handle? = nil

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Controller Local Function Section
----------------------------------------------------------

--[[
Closes all floating property editors.
]]
local function closeFloatingEditors(): ()
	Relay.Create("CloseColorPicker"):Fire()
	Relay.Create("CloseGradientEditor"):Fire()
	Relay.Create("CloseTransparencyEditor"):Fire()
end

--[[
Handles toggling the properties editor visibility.
]]
local function onTogglePropertiesEditor(): ()
	closeFloatingEditors()
	PropertiesEditor_Logic.ToggleVisibility()
	Relay.Create("SessionStateUpdated"):Fire()
end

--[[
Handles setting an element's name.
]]
local function onSetElementName(Payload: { Id: string, Name: string }): ()
	PropertiesEditor_Logic.SetElementName(Payload.Id, Payload.Name)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
	Relay.Create("UITreeUpdated"):Fire()
end

--[[
Handles setting an element's position.
]]
local function onSetElementPosition(Payload: { Id: string, Position: UDim2, FromDial: boolean? }): ()
	if Payload.FromDial then
		PropertiesEditor_Logic.SetElementPositionFromDial(Payload.Id, Payload.Position)
		
	else
		PropertiesEditor_Logic.SetElementPosition(Payload.Id, Payload.Position)
	end
	
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles setting an element's size.
]]
local function onSetElementSize(Payload: { Id: string, Size: UDim2, FromDial: boolean? }): ()
	if Payload.FromDial then
		PropertiesEditor_Logic.SetElementSizeFromDial(Payload.Id, Payload.Size)
		
	else
		PropertiesEditor_Logic.SetElementSize(Payload.Id, Payload.Size)
	end
	
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles setting an element's visibility.
]]
local function onSetElementVisible(Payload: { Id: string, Visible: boolean }): ()
	closeFloatingEditors()
	PropertiesEditor_Logic.SetElementVisible(Payload.Id, Payload.Visible)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
	Relay.Create("UITreeUpdated"):Fire()
end

--[[
Handles setting an element's rotation.
]]
local function onSetElementRotation(Payload: { Id: string, Rotation: number, FromDial: boolean? }): ()
	if Payload.FromDial then
		PropertiesEditor_Logic.SetElementRotationFromDial(Payload.Id, Payload.Rotation)
		
	else
		PropertiesEditor_Logic.SetElementProperty(Payload.Id, "Rotation", Payload.Rotation)
	end
	
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles setting an element's property.
]]
local function onSetElementProperty(Payload: { Id: string, Key: string, Value: any }): ()
	if Payload.Key == "Visible" then
		closeFloatingEditors()
	end
	
	PropertiesEditor_Logic.SetElementProperty(Payload.Id, Payload.Key, Payload.Value)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles previewing an element's property.
]]
local function onPreviewElementProperty(Payload: { Id: string, Key: string, Value: any }): ()
	PropertiesEditor_Logic.PreviewElementProperty(Payload.Id, Payload.Key, Payload.Value)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles committing a previewed property.
]]
local function onCommitPreviewedProperty(Payload: { Id: string, Key: string, FinalValue: any, InitialValue: any }): ()
	PropertiesEditor_Logic.CommitPreviewedProperty(Payload.Id, Payload.Key, Payload.FinalValue, Payload.InitialValue)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles adding a modifier.
]]
local function onAddModifier(Payload: { Id: string, ModifierType: string }): ()
	PropertiesEditor_Logic.AddModifier(Payload.Id, Payload.ModifierType)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles removing a modifier.
]]
local function onRemoveModifier(Payload: { Id: string, ModifierKey: string }): ()
	closeFloatingEditors()
	PropertiesEditor_Logic.RemoveModifier(Payload.Id, Payload.ModifierKey)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles setting a modifier property.
]]
local function onSetModifierProperty(Payload: { Id: string, ModifierKey: string, Key: string, Value: any }): ()
	PropertiesEditor_Logic.SetModifierProperty(Payload.Id, Payload.ModifierKey, Payload.Key, Payload.Value)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles previewing a modifier's property.
]]
local function onPreviewModifierProperty(Payload: { Id: string, ModifierKey: string, Key: string, Value: any }): ()
	PropertiesEditor_Logic.PreviewModifierProperty(Payload.Id, Payload.ModifierKey, Payload.Key, Payload.Value)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles committing a previewed modifier property.
]]
local function onCommitPreviewedModifierProperty(Payload: { Id: string, ModifierKey: string, Key: string, FinalValue: any, InitialValue: any }): ()
	PropertiesEditor_Logic.CommitPreviewedModifierProperty(Payload.Id, Payload.ModifierKey, Payload.Key, Payload.FinalValue, Payload.InitialValue)
	Relay.Create("WorkspaceElementsUpdated"):Fire()
end

--[[
Handles toggling the position settings modal.
]]
local function onTogglePositionSettings(): ()
	PropertiesEditor_Logic.TogglePositionSettings()
	Relay.Create("SessionStateUpdated"):Fire()
end

--[[
Handles updating the position settings.
]]
local function onUpdatePositionEditorSettings(Settings: {TrackpadSensitivity: number, XDialSensitivity: number, YDialSensitivity: number}): ()
	PropertiesEditor_Logic.UpdatePositionEditorSettings(Settings)
	Relay.Create("SessionStateUpdated"):Fire()
	Relay.Create("ShowNotification"):Fire({
		Message = "Position Settings Updated Successfully!",
		Type = "Success",
	})
end

--[[
Handles toggling the size settings modal.
]]
local function onToggleSizeSettings(): ()
	PropertiesEditor_Logic.ToggleSizeSettings()
	Relay.Create("SessionStateUpdated"):Fire()
end

--[[
Handles updating the size settings.
]]
local function onUpdateSizeEditorSettings(Settings: {TrackpadSensitivity: number, WidthDialSensitivity: number, HeightDialSensitivity: number}): ()
	PropertiesEditor_Logic.UpdateSizeEditorSettings(Settings)
	Relay.Create("SessionStateUpdated"):Fire()
	Relay.Create("ShowNotification"):Fire({
		Message = "Size Settings Updated Successfully!",
		Type = "Success",
	})
end

--[[
Handles anchor point visual visibility toggling.
]]
local function onSetAnchorPointVisualVisible(Visible: boolean): ()
    if AnchorPointVisualHandle then
        Assignment.Cancel(AnchorPointVisualHandle)
        AnchorPointVisualHandle = nil
    end

    if Visible then
        PropertiesEditor_Logic.SetAnchorPointVisualVisible(true)
		Relay.Create("SessionStateUpdated"):Fire()
		
    else
        AnchorPointVisualHandle = Assignment.Delay(3, function()
            PropertiesEditor_Logic.SetAnchorPointVisualVisible(false)
            Relay.Create("SessionStateUpdated"):Fire()
            AnchorPointVisualHandle = nil
        end)
    end
end


--[[
Handles toggling the rotation settings modal.
]]
local function onToggleRotationSettings(): ()
	PropertiesEditor_Logic.ToggleRotationSettings()
	Relay.Create("SessionStateUpdated"):Fire()
end

--[[
Handles updating the rotation settings.
]]
local function onUpdateRotationEditorSettings(Settings: {DialSensitivity: number}): ()
	PropertiesEditor_Logic.UpdateRotationEditorSettings(Settings)
	Relay.Create("SessionStateUpdated"):Fire()
	Relay.Create("ShowNotification"):Fire({
		Message = "Rotation Settings Updated Successfully!",
		Type = "Success",
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Controller Public APIs Section
----------------------------------------------------------

--[[
Architectural placeholder for controller initialization.

Params:
    None

Returns:
    None
]]
function PropertiesEditor_Controller.Init(): ()
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
-- PropertiesEditor_Controller Event Binding Section
----------------------------------------------------------
Relay.Create("TogglePropertiesEditor"):Connect(onTogglePropertiesEditor)
Relay.Create("SetElementName"):Connect(onSetElementName)
Relay.Create("SetElementPosition"):Connect(onSetElementPosition)
Relay.Create("SetElementSize"):Connect(onSetElementSize)
Relay.Create("SetElementRotation"):Connect(onSetElementRotation)
Relay.Create("SetElementVisible"):Connect(onSetElementVisible)
Relay.Create("SetElementProperty"):Connect(onSetElementProperty)
Relay.Create("PreviewElementProperty"):Connect(onPreviewElementProperty)
Relay.Create("CommitPreviewedProperty"):Connect(onCommitPreviewedProperty)
Relay.Create("AddModifier"):Connect(onAddModifier)
Relay.Create("RemoveModifier"):Connect(onRemoveModifier)
Relay.Create("SetModifierProperty"):Connect(onSetModifierProperty)
Relay.Create("PreviewModifierProperty"):Connect(onPreviewModifierProperty)
Relay.Create("CommitPreviewedModifierProperty"):Connect(onCommitPreviewedModifierProperty)
Relay.Create("TogglePositionSettings"):Connect(onTogglePositionSettings)
Relay.Create("UpdatePositionEditorSettings"):Connect(onUpdatePositionEditorSettings)
Relay.Create("ToggleSizeSettings"):Connect(onToggleSizeSettings)
Relay.Create("UpdateSizeEditorSettings"):Connect(onUpdateSizeEditorSettings)
Relay.Create("SetAnchorPointVisualVisible"):Connect(onSetAnchorPointVisualVisible)
Relay.Create("ToggleRotationSettings"):Connect(onToggleRotationSettings)
Relay.Create("UpdateRotationEditorSettings"):Connect(onUpdateRotationEditorSettings)

----------------------------------------------------------
return PropertiesEditor_Controller :: PropertiesEditor_Controller
----------------------------------------------------------