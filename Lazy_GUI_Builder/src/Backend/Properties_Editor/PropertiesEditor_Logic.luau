--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: PropertiesEditor_Logic.luau
    
    SCOPE: Feature Backend Logic
    
    ROLE: Manages all mutating operations triggered by the Properties Editor,
          pushing history snapshots before applying changes.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Logic Type Structures Section
----------------------------------------------------------
export type PropertiesEditor_Logic = {
	ToggleVisibility: () -> (),
	SetElementName: (Id: string, Name: string) -> (),
	SetElementPosition: (Id: string, Position: UDim2) -> (),
	SetElementPositionFromDial: (Id: string, Position: UDim2) -> (),
	SetElementSize: (Id: string, Size: UDim2) -> (),
	SetElementSizeFromDial: (Id: string, Size: UDim2) -> (),
	SetElementVisible: (Id: string, Visible: boolean) -> (),
	SetElementProperty: (Id: string, Key: string, Value: any) -> (),
	PreviewElementProperty: (Id: string, Key: string, Value: any) -> (),
	CommitPreviewedProperty: (Id: string, Key: string, FinalValue: any, InitialValue: any) -> (),
	AddModifier: (Id: string, ModifierType: string) -> (),
	RemoveModifier: (Id: string, ModifierKey: string) -> (),
	SetModifierProperty: (Id: string, ModifierKey: string, Key: string, Value: any) -> (),
	PreviewModifierProperty: (Id: string, ModifierKey: string, Key: string, Value: any) -> (),
	CommitPreviewedModifierProperty: (Id: string, ModifierKey: string, Key: string, FinalValue: any, InitialValue: any) -> (),
	TogglePositionSettings: () -> (),
	UpdatePositionEditorSettings: (Settings: {TrackpadSensitivity: number, XDialSensitivity: number, YDialSensitivity: number}) -> (),
	ToggleSizeSettings: () -> (),
	UpdateSizeEditorSettings: (Settings: {TrackpadSensitivity: number, WidthDialSensitivity: number, HeightDialSensitivity: number}) -> (),
	SetAnchorPointVisualVisible: (Visible: boolean) -> (),
	ToggleRotationSettings: () -> (),
	UpdateRotationEditorSettings: (Settings: {DialSensitivity: number}) -> (),
	SetElementRotationFromDial: (TargetId: string, Rotation: number) -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Logic Imported Services Section
----------------------------------------------------------
local HttpService: HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Logic Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.Parent.AppState)
local History_Logic = require(script.Parent.Parent.History_Logic)
local PropertyRegistry = require(script.Parent.Parent.Parent.PropertyRegistry)
local Assignment = require(script.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Logic Internal States Section
----------------------------------------------------------
local PropertiesEditor_Logic = {}
local SizeDialDebounceHandle: Assignment.Handle? = nil
local PositionDialDebounceHandle: Assignment.Handle? = nil

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Logic Local Function Section
----------------------------------------------------------

-- Recursively applies visibility state to children
local function cascadeVisibility(ElementId: string, IsVisible: boolean): ()
	local Element = AppState.WorkspaceElements[ElementId]
	
	if not Element then return end
	
	Element.Visible = IsVisible
	
	for _, ChildId: string in ipairs(Element.Children) do
		cascadeVisibility(ChildId, IsVisible)
	end
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Logic Public APIs Section
----------------------------------------------------------

--[[
Toggles the visibility of the Properties Editor widget.

Returns:
    None
]]
function PropertiesEditor_Logic.ToggleVisibility(): ()
	AppState.SessionState.IsPropertiesEditorVisible = not AppState.SessionState.IsPropertiesEditorVisible
end

--[[
Sets the Name of an element.

Params:
    Id: string -- The element ID
    Name: string -- The new name

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementName(Id: string, Name: string): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	History_Logic.PushSnapshot()
	AppState.WorkspaceElements[Id].Name = Name
end

--[[
Sets the Position of an element.

Params:
    Id: string -- The element ID
    Position: UDim2 -- The new position

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementPosition(Id: string, Position: UDim2): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	History_Logic.PushSnapshot()
	AppState.WorkspaceElements[Id].Position = Position
end

--[[
Sets the Size of an element.

Params:
    Id: string -- The element ID
    Size: UDim2 -- The new size

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementSize(Id: string, Size: UDim2): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	History_Logic.PushSnapshot()
	AppState.WorkspaceElements[Id].Size = Size
end

--[[
Sets the Position of an element from the position dial with debounced history.

Params:
    Id: string -- The element ID
    Position: UDim2 -- The new position

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementPositionFromDial(Id: string, Position: UDim2): ()
    if not AppState.WorkspaceElements[Id] then return end

    local Tracker = AppState.SessionState.PositionDialTracker

    -- First delta of this drag session: capture original position
    if Tracker.OriginalPosition == nil then
        Tracker.OriginalPosition = AppState.WorkspaceElements[Id].Position
        Tracker.ElementId = Id
    end

    -- Mutate immediately for real-time canvas rendering (NO history push)
    AppState.WorkspaceElements[Id].Position = Position

    -- Cancel previous debounce, schedule fresh 0.5s window
    if PositionDialDebounceHandle then
        Assignment.Cancel(PositionDialDebounceHandle)
    end

    PositionDialDebounceHandle = Assignment.Delay(0.5, function()
		if not AppState.WorkspaceElements[Id] then
			Tracker.OriginalPosition = nil
			Tracker.ElementId = nil
			PositionDialDebounceHandle = nil
			
			return
		end

		local FinalPosition = AppState.WorkspaceElements[Id].Position
		
        -- Sleight-of-hand: revert → snapshot → reapply
		AppState.WorkspaceElements[Id].Position = Tracker.OriginalPosition :: UDim2
        History_Logic.PushSnapshot()
		AppState.WorkspaceElements[Id].Position = FinalPosition

        -- Clear tracker
        Tracker.OriginalPosition = nil
        Tracker.ElementId = nil
        PositionDialDebounceHandle = nil
    end)
end

--[[
Sets the Size of an element from the size dial with debounced history.

Params:
    Id: string -- The element ID
    Size: UDim2 -- The new size

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementSizeFromDial(Id: string, Size: UDim2): ()
    if not AppState.WorkspaceElements[Id] then return end

    local Tracker = AppState.SessionState.SizeDialTracker

    -- First delta of this drag session: capture original size
    if Tracker.OriginalSize == nil then
        Tracker.OriginalSize = AppState.WorkspaceElements[Id].Size
        Tracker.ElementId = Id
    end

    -- Mutate immediately for real-time canvas rendering (NO history push)
    AppState.WorkspaceElements[Id].Size = Size

    -- Cancel previous debounce, schedule fresh 0.5s window
    if SizeDialDebounceHandle then
        Assignment.Cancel(SizeDialDebounceHandle)
    end

    SizeDialDebounceHandle = Assignment.Delay(0.5, function()
		if not AppState.WorkspaceElements[Id] then
			Tracker.OriginalSize = nil
			Tracker.ElementId = nil
			SizeDialDebounceHandle = nil
			
			return
		end

		local FinalSize = AppState.WorkspaceElements[Id].Size
		
        -- Sleight-of-hand: revert → snapshot → reapply
		AppState.WorkspaceElements[Id].Size = Tracker.OriginalSize :: UDim2
        History_Logic.PushSnapshot()
		AppState.WorkspaceElements[Id].Size = FinalSize

        -- Clear tracker
        Tracker.OriginalSize = nil
        Tracker.ElementId = nil
        SizeDialDebounceHandle = nil
    end)
end

--[[
Sets the Visibility of an element, cascading to its children.

Params:
    Id: string -- The element ID
    Visible: boolean -- The new visibility state

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementVisible(Id: string, Visible: boolean): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	History_Logic.PushSnapshot()
	cascadeVisibility(Id, Visible)
end

--[[
Sets a property on an element's Properties bag.

Params:
    Id: string -- The element ID
    Key: string -- The property key
    Value: any -- The property value (genuinely dynamic property type)

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementProperty(Id: string, Key: string, Value: any): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	History_Logic.PushSnapshot()
	AppState.WorkspaceElements[Id].Properties[Key] = Value
end

--[[
Sets a property on an element's Properties bag without pushing a snapshot, for real-time previews.

Params:
    Id: string -- The element ID
    Key: string -- The property key
    Value: any -- The property value (genuinely dynamic property type)

Returns:
    None
]]
function PropertiesEditor_Logic.PreviewElementProperty(Id: string, Key: string, Value: any): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	AppState.WorkspaceElements[Id].Properties[Key] = Value
end

--[[
Commits a previewed property to history, temporarily reverting to InitialValue to construct the snapshot.

Params:
    Id: string -- The element ID
    Key: string -- The property key
    FinalValue: any -- The final submitted value (genuinely dynamic property type)
    InitialValue: any -- The initial value before previewing began (genuinely dynamic property type)

Returns:
    None
]]
function PropertiesEditor_Logic.CommitPreviewedProperty(Id: string, Key: string, FinalValue: any, InitialValue: any): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	--[[
		Undo History Sleight-of-Hand:
		
		During a live preview, AppState is updated instantly without pushing to history.
		By the time this commit runs, AppState is already set to the new color. If we 
		snapshotted now, Undo would just revert "Red back to Red". To fix this, we 
		temporarily revert the state to the original color, force the history system to 
		take its snapshot, and then instantly snap the state forward to the final color.
	]]
	
	AppState.WorkspaceElements[Id].Properties[Key] = InitialValue
	History_Logic.PushSnapshot()
	AppState.WorkspaceElements[Id].Properties[Key] = FinalValue
end

--[[
Adds a modifier to an element's Properties bag, populated with defaults.

Params:
    Id: string -- The element ID
    ModifierType: string -- The modifier type

Returns:
    None
]]
function PropertiesEditor_Logic.AddModifier(Id: string, ModifierType: string): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	local Defaults: any = PropertyRegistry.GetModifierDefaults(ModifierType)
	
	if not Defaults then return end
	
	local ModifierKey: string = if PropertyRegistry.AllowsMultipleInstances(ModifierType) then ModifierType .. "_" .. HttpService:GenerateGUID(false):sub(1, 6) else ModifierType
	
	if Defaults and Defaults.Properties then
		local SortVal = Defaults.Properties.SortOrder
		
		if SortVal == "Custom" or (typeof(SortVal) == "EnumItem" and SortVal.Name == "Custom") then
			Defaults.Properties.SortOrder = Enum.SortOrder.LayoutOrder
		end
		
		local DragVal = Defaults.Properties.DragStyle
		
		if DragVal == "Custom" or (typeof(DragVal) == "EnumItem" and DragVal.Name == "Custom") then
			Defaults.Properties.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
		end
	end

	Defaults.Id = ModifierKey
	History_Logic.PushSnapshot()
	AppState.WorkspaceElements[Id].Properties[ModifierKey] = Defaults
end

--[[
Removes a modifier from an element's Properties bag.

Params:
    Id: string -- The element ID
    ModifierKey: string -- The modifier unique key

Returns:
    None
]]
function PropertiesEditor_Logic.RemoveModifier(Id: string, ModifierKey: string): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	History_Logic.PushSnapshot()
	AppState.WorkspaceElements[Id].Properties[ModifierKey] = nil
end

--[[
Sets a specific nested property inside a modifier.

Params:
    Id: string -- The element ID
    ModifierKey: string -- The modifier unique key
    Key: string -- The property key inside the modifier
    Value: any -- The new value (genuinely dynamic property type)

Returns:
    None
]]
function PropertiesEditor_Logic.SetModifierProperty(Id: string, ModifierKey: string, Key: string, Value: any): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	local ModifierBag: any = AppState.WorkspaceElements[Id].Properties[ModifierKey]
	
	if type(ModifierBag) == "table" and ModifierBag.IsModifier then
		if Key == "SortOrder" and (Value == "Custom" or (typeof(Value) == "EnumItem" and Value.Name == "Custom")) then
			Value = Enum.SortOrder.LayoutOrder
			
		elseif Key == "DragStyle" and (Value == "Custom" or (typeof(Value) == "EnumItem" and Value.Name == "Custom")) then
			Value = Enum.UIDragDetectorDragStyle.TranslatePlane
		end

		History_Logic.PushSnapshot()
		ModifierBag.Properties[Key] = Value
	end
end

--[[
Sets a property on a modifier's Properties bag without pushing a snapshot, for real-time previews.

Params:
    Id: string -- The element ID
    ModifierKey: string -- The modifier unique key
    Key: string -- The property key inside the modifier
    Value: any -- The property value (genuinely dynamic property type)

Returns:
    None
]]
function PropertiesEditor_Logic.PreviewModifierProperty(Id: string, ModifierKey: string, Key: string, Value: any): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	local ModifierBag: any = AppState.WorkspaceElements[Id].Properties[ModifierKey]
	
	if type(ModifierBag) == "table" and ModifierBag.IsModifier then
		if Key == "SortOrder" and (Value == "Custom" or (typeof(Value) == "EnumItem" and Value.Name == "Custom")) then
			Value = Enum.SortOrder.LayoutOrder
			
		elseif Key == "DragStyle" and (Value == "Custom" or (typeof(Value) == "EnumItem" and Value.Name == "Custom")) then
			Value = Enum.UIDragDetectorDragStyle.TranslatePlane
		end

		ModifierBag.Properties[Key] = Value
	end
end

--[[
Commits a previewed modifier property to history, temporarily reverting to InitialValue to construct the snapshot.

Params:
    Id: string -- The element ID
    ModifierKey: string -- The modifier unique key
    Key: string -- The property key inside the modifier
    FinalValue: any -- The final submitted value (genuinely dynamic property type)
    InitialValue: any -- The initial value before previewing began (genuinely dynamic property type)

Returns:
    None
]]
function PropertiesEditor_Logic.CommitPreviewedModifierProperty(Id: string, ModifierKey: string, Key: string, FinalValue: any, InitialValue: any): ()
	if not AppState.WorkspaceElements[Id] then return end
	
	local ModifierBag: any = AppState.WorkspaceElements[Id].Properties[ModifierKey]
	
	if type(ModifierBag) == "table" and ModifierBag.IsModifier then
		ModifierBag.Properties[Key] = InitialValue
		History_Logic.PushSnapshot()
		ModifierBag.Properties[Key] = FinalValue
	end
end

--[[
Toggles the visibility of the position editor settings modal.

Returns:
    None
]]
function PropertiesEditor_Logic.TogglePositionSettings(): ()
    AppState.SessionState.IsPositionSettingsVisible = not AppState.SessionState.IsPositionSettingsVisible
end

--[[
Updates the position editor sensitivities.

Params:
    Settings: {TrackpadSensitivity: number, XDialSensitivity: number, YDialSensitivity: number} -- The new settings

Returns:
    None
]]
function PropertiesEditor_Logic.UpdatePositionEditorSettings(Settings: {TrackpadSensitivity: number, XDialSensitivity: number, YDialSensitivity: number}): ()
    AppState.SessionState.PositionEditorSettings = Settings
    AppState.SessionState.IsPositionSettingsVisible = false -- Close modal on confirm
end

--[[
Toggles the visibility of the size editor settings modal.

Returns:
    None
]]
function PropertiesEditor_Logic.ToggleSizeSettings(): ()
    AppState.SessionState.IsSizeSettingsVisible = not AppState.SessionState.IsSizeSettingsVisible
end

--[[
Updates the size editor sensitivities.

Params:
    Settings: {TrackpadSensitivity: number, WidthDialSensitivity: number, HeightDialSensitivity: number} -- The new settings

Returns:
    None
]]
function PropertiesEditor_Logic.UpdateSizeEditorSettings(Settings: {TrackpadSensitivity: number, WidthDialSensitivity: number, HeightDialSensitivity: number}): ()
    AppState.SessionState.SizeEditorSettings = Settings
    AppState.SessionState.IsSizeSettingsVisible = false -- Close modal on confirm
end

--[[
Sets the visibility of the Anchor Point Visual indicator.

Params:
    Visible: boolean -- True to show, false to hide

Returns:
    None
]]
function PropertiesEditor_Logic.SetAnchorPointVisualVisible(Visible: boolean): ()
    AppState.SessionState.IsAnchorPointVisualVisible = Visible
end

--[[
Toggles the rotation settings modal.

Params:
    None

Returns:
    None
]]
function PropertiesEditor_Logic.ToggleRotationSettings(): ()
    AppState.SessionState.IsRotationSettingsVisible = not AppState.SessionState.IsRotationSettingsVisible
end

--[[
Updates the rotation editor sensitivities.

Params:
    Settings: {DialSensitivity: number} -- The new settings

Returns:
    None
]]
function PropertiesEditor_Logic.UpdateRotationEditorSettings(Settings: {DialSensitivity: number}): ()
    AppState.SessionState.RotationEditorSettings = Settings
    AppState.SessionState.IsRotationSettingsVisible = false -- Close modal on confirm
end

local RotationDialDebounceHandle: any = nil

--[[
Sets an element's rotation explicitly from a dial interaction. Debounces the undo stack push.

Params:
    TargetId: string -- Target ID
    Rotation: number -- The new Rotation

Returns:
    None
]]
function PropertiesEditor_Logic.SetElementRotationFromDial(Id: string, Rotation: number): ()
    if not AppState.WorkspaceElements[Id] then return end

    local Tracker = AppState.SessionState.RotationDialTracker

    -- First delta of this drag session: capture original rotation
    if Tracker.OriginalRotation == nil then
        Tracker.OriginalRotation = AppState.WorkspaceElements[Id].Properties.Rotation or 0
        Tracker.ElementId = Id
    end

    -- Mutate immediately for real-time canvas rendering (NO history push)
    AppState.WorkspaceElements[Id].Properties.Rotation = Rotation

    -- Cancel previous debounce, schedule fresh 0.5s window
    if RotationDialDebounceHandle then
        Assignment.Cancel(RotationDialDebounceHandle)
    end

    RotationDialDebounceHandle = Assignment.Delay(0.5, function()
		if not AppState.WorkspaceElements[Id] then
			Tracker.OriginalRotation = nil
			Tracker.ElementId = nil
			RotationDialDebounceHandle = nil
			
			return
		end

		local FinalRotation = AppState.WorkspaceElements[Id].Properties.Rotation
		
        -- Sleight-of-hand: revert → snapshot → reapply
		AppState.WorkspaceElements[Id].Properties.Rotation = Tracker.OriginalRotation :: number
        History_Logic.PushSnapshot()
		AppState.WorkspaceElements[Id].Properties.Rotation = FinalRotation

        -- Clear tracker
        Tracker.OriginalRotation = nil
        Tracker.ElementId = nil
        RotationDialDebounceHandle = nil
    end)
end

----------------------------------------------------------
return PropertiesEditor_Logic :: PropertiesEditor_Logic
----------------------------------------------------------