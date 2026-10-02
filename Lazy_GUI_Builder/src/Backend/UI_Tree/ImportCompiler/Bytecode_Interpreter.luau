--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Bytecode_Interpreter.luau
    
    SCOPE: UI Tree / Import Compiler
    
    ROLE: Executes BytecodeProgram instructions to reconstruct virtual DOM
          elements in AppState.WorkspaceElements under Append, Replace, or
          Replace_Selected import modes.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local Bytecode_Types = require(script.Parent.Parent.ExportCompiler.Bytecode_Types)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type ImportMode = "Append" | "Replace" | "Replace_Selected"
export type Bytecode_Interpreter = {
	Load: (Program: Bytecode_Types.BytecodeProgram, Mode: ImportMode) -> string?,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Imported Services Section
----------------------------------------------------------
local HttpService: HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.Parent.Parent.AppState)
local PropertyRegistry = require(script.Parent.Parent.Parent.Parent.PropertyRegistry)
local History_Logic = require(script.Parent.Parent.Parent.History_Logic)
local Assignment = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local Bytecode_Interpreter = {}
local TypeDeserializerSwitch = Assignment.Switch("BytecodeInterpreter_TypeDeserializer")
local RootPropertyApplierSwitch = Assignment.Switch("BytecodeInterpreter_RootPropertyApplier")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Functions Section
----------------------------------------------------------

--[[
Deserializes a Color3 string representation into a native Color3 value.

Params:
    SerializedValue: string -- The serialized Color3 constructor expression

Returns:
    Color3? -- The parsed Color3 value, or nil if invalid
]]
local function deserializeColor3(SerializedValue: string): Color3?
	local RedStr, GreenStr, BlueStr = string.match(SerializedValue, "Color3%.fromRGB%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)")
	
	if RedStr and GreenStr and BlueStr then
		return Color3.fromRGB(tonumber(RedStr) or 0, tonumber(GreenStr) or 0, tonumber(BlueStr) or 0)
	end

	local NormRedStr, NormGreenStr, NormBlueStr = string.match(SerializedValue, "Color3%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if NormRedStr and NormGreenStr and NormBlueStr then
		return Color3.new(tonumber(NormRedStr) or 0, tonumber(NormGreenStr) or 0, tonumber(NormBlueStr) or 0)
	end

	return nil
end

--[[
Deserializes a UDim2 string representation into a native UDim2 value.

Params:
    SerializedValue: string -- The serialized UDim2 constructor expression

Returns:
    UDim2? -- The parsed UDim2 value, or nil if invalid
]]
local function deserializeUDim2(SerializedValue: string): UDim2?
	if SerializedValue == "UDim2.new()" then
		return UDim2.new()
	end

	local OffsetXStr, OffsetYStr = string.match(SerializedValue, "UDim2%.fromOffset%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if OffsetXStr and OffsetYStr then
		return UDim2.fromOffset(tonumber(OffsetXStr) or 0, tonumber(OffsetYStr) or 0)
	end

	local ScaleXStr, ScaleYStr = string.match(SerializedValue, "UDim2%.fromScale%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if ScaleXStr and ScaleYStr then
		return UDim2.fromScale(tonumber(ScaleXStr) or 0, tonumber(ScaleYStr) or 0)
	end

	local XScaleStr, XOffsetStr, YScaleStr, YOffsetStr = string.match(SerializedValue, "UDim2%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if XScaleStr and XOffsetStr and YScaleStr and YOffsetStr then
		return UDim2.new(tonumber(XScaleStr) or 0, tonumber(XOffsetStr) or 0, tonumber(YScaleStr) or 0, tonumber(YOffsetStr) or 0)
	end

	return nil
end

--[[
Deserializes a UDim string representation into a native UDim value.

Params:
    SerializedValue: string -- The serialized UDim constructor expression

Returns:
    UDim? -- The parsed UDim value, or nil if invalid
]]
local function deserializeUDim(SerializedValue: string): UDim?
	local ScaleStr, OffsetStr = string.match(SerializedValue, "UDim%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if ScaleStr and OffsetStr then
		return UDim.new(tonumber(ScaleStr) or 0, tonumber(OffsetStr) or 0)
	end

	return nil
end

--[[
Deserializes a Vector2 string representation into a native Vector2 value.

Params:
    SerializedValue: string -- The serialized Vector2 constructor expression

Returns:
    Vector2? -- The parsed Vector2 value, or nil if invalid
]]
local function deserializeVector2(SerializedValue: string): Vector2?
	if SerializedValue == "Vector2.zero" then
		return Vector2.zero
	end

	local XCoordStr, YCoordStr = string.match(SerializedValue, "Vector2%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if XCoordStr and YCoordStr then
		return Vector2.new(tonumber(XCoordStr) or 0, tonumber(YCoordStr) or 0)
	end

	return nil
end

--[[
Deserializes a Vector3 string representation into a native Vector3 value.

Params:
    SerializedValue: string -- The serialized Vector3 constructor expression

Returns:
    Vector3? -- The parsed Vector3 value, or nil if invalid
]]
local function deserializeVector3(SerializedValue: string): Vector3?
	if SerializedValue == "Vector3.zero" then
		return Vector3.zero
	end

	local XCoordStr, YCoordStr, ZCoordStr = string.match(SerializedValue, "Vector3%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if XCoordStr and YCoordStr and ZCoordStr then
		return Vector3.new(tonumber(XCoordStr) or 0, tonumber(YCoordStr) or 0, tonumber(ZCoordStr) or 0)
	end

	return nil
end

--[[
Deserializes a Rect string representation into a native Rect value.

Params:
    SerializedValue: string -- The serialized Rect constructor expression

Returns:
    Rect? -- The parsed Rect value, or nil if invalid
]]
local function deserializeRect(SerializedValue: string): Rect?
	local MinXStr, MinYStr, MaxXStr, MaxYStr = string.match(SerializedValue, "Rect%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if MinXStr and MinYStr and MaxXStr and MaxYStr then
		return Rect.new(tonumber(MinXStr) or 0, tonumber(MinYStr) or 0, tonumber(MaxXStr) or 0, tonumber(MaxYStr) or 0)
	end

	return nil
end

--[[
Deserializes a NumberRange string representation into a native NumberRange value.

Params:
    SerializedValue: string -- The serialized NumberRange constructor expression

Returns:
    NumberRange? -- The parsed NumberRange value, or nil if invalid
]]
local function deserializeNumberRange(SerializedValue: string): NumberRange?
	local MinBoundStr, MaxBoundStr = string.match(SerializedValue, "NumberRange%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)")
	
	if MinBoundStr and MaxBoundStr then
		return NumberRange.new(tonumber(MinBoundStr) or 0, tonumber(MaxBoundStr) or 0)
	end

	local SingleBoundStr = string.match(SerializedValue, "NumberRange%.new%(%s*([%d%.%-]+)%s*%)")
	
	if SingleBoundStr then
		return NumberRange.new(tonumber(SingleBoundStr) or 0)
	end

	return nil
end

--[[
Deserializes an EnumItem string representation into a native EnumItem.

Params:
    SerializedValue: string -- The serialized EnumItem expression (e.g. "Enum.Font.Gotham")

Returns:
    any -- The resolved EnumItem, or nil if invalid
]]
local function deserializeEnumItem(SerializedValue: string): any
	local EnumTypeName, EnumItemName = string.match(SerializedValue, "Enum%.([%w_]+)%.([%w_]+)")
	
	if EnumTypeName and EnumItemName then
		if EnumTypeName == "SortOrder" and EnumItemName == "Custom" then
			return Enum.SortOrder.LayoutOrder
			
		elseif EnumTypeName == "UIDragDetectorDragStyle" and EnumItemName == "Custom" then
			return Enum.UIDragDetectorDragStyle.TranslatePlane
		end

		local TargetEnumType = Enum[EnumTypeName]
		
		if TargetEnumType then
			local Success: boolean, Result: any = pcall(function()
				return TargetEnumType[EnumItemName]
			end)
			
			if Success and Result ~= nil then
				return Result
			end
		end
	end

	return nil
end

--[[
Deserializes a ColorSequence string representation into a native ColorSequence.

Params:
    SerializedValue: string -- The serialized ColorSequence constructor expression

Returns:
    ColorSequence? -- The parsed ColorSequence, or nil if invalid
]]
local function deserializeColorSequence(SerializedValue: string): ColorSequence?
	local Keypoints: { ColorSequenceKeypoint } = {}

	for TimeStr, RedStr, GreenStr, BlueStr in string.gmatch(SerializedValue, "ColorSequenceKeypoint%.new%(%s*([%d%.%-]+)%s*,%s*Color3%.fromRGB%(%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*%)%s*%)") do
		local TimeValue: number = tonumber(TimeStr) or 0
		local RedValue: number = tonumber(RedStr) or 0
		local GreenValue: number = tonumber(GreenStr) or 0
		local BlueValue: number = tonumber(BlueStr) or 0
		
		Keypoints[#Keypoints + 1] = ColorSequenceKeypoint.new(TimeValue, Color3.fromRGB(RedValue, GreenValue, BlueValue))
	end

	if #Keypoints >= 2 then
		return ColorSequence.new(Keypoints)
	end

	return nil
end

--[[
Deserializes a NumberSequence string representation into a native NumberSequence.

Params:
    SerializedValue: string -- The serialized NumberSequence constructor expression

Returns:
    NumberSequence? -- The parsed NumberSequence, or nil if invalid
]]
local function deserializeNumberSequence(SerializedValue: string): NumberSequence?
	local Keypoints: { NumberSequenceKeypoint } = {}

	for TimeStr, ValueStr, EnvelopeStr in string.gmatch(SerializedValue, "NumberSequenceKeypoint%.new%(%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*,%s*([%d%.%-]+)%s*%)") do
		local TimeValue: number = tonumber(TimeStr) or 0
		local NumberValue: number = tonumber(ValueStr) or 0
		local EnvelopeValue: number = tonumber(EnvelopeStr) or 0
		
		Keypoints[#Keypoints + 1] = NumberSequenceKeypoint.new(TimeValue, NumberValue, EnvelopeValue)
	end

	if #Keypoints >= 2 then
		return NumberSequence.new(Keypoints)
	end

	return nil
end

--[[
Deserializes a boolean string literal into a native boolean value.

Params:
    SerializedValue: string -- "true" or "false"

Returns:
    boolean -- The parsed boolean value
]]
local function deserializeBoolean(SerializedValue: string): boolean
	return SerializedValue == "true"
end

--[[
Deserializes a number string representation into a native number value.

Params:
    SerializedValue: string -- The serialized number string

Returns:
    number? -- The parsed number, or nil if conversion failed
]]
local function deserializeNumber(SerializedValue: string): number?
	return tonumber(SerializedValue)
end

--[[
Deserializes a string literal representation, unescaping quotes and control characters.

Params:
    SerializedValue: string -- The double-quoted and escaped string literal

Returns:
    string -- The unescaped string value
]]
local function deserializeString(SerializedValue: string): string
	if string.sub(SerializedValue, 1, 1) == '"' and string.sub(SerializedValue, -1) == '"' then
		local UnquotedContent: string = string.sub(SerializedValue, 2, -2)
		
		UnquotedContent = string.gsub(UnquotedContent, '\\"', '"')
		UnquotedContent = string.gsub(UnquotedContent, "\\n", "\n")
		UnquotedContent = string.gsub(UnquotedContent, "\\t", "\t")
		UnquotedContent = string.gsub(UnquotedContent, "\\r", "\r")
		UnquotedContent = string.gsub(UnquotedContent, "\\\\", "\\")
		
		return UnquotedContent
	end

	return SerializedValue
end

--[[
Infers the datatype and parses a serialized value string when RawType is not specified.

Params:
    SerializedValue: string -- The serialized value string

Returns:
    any -- The deserialized Roblox datatype or primitive value
]]
local function inferAndDeserialize(SerializedValue: string): any
	if string.sub(SerializedValue, 1, 1) == '"' and string.sub(SerializedValue, -1) == '"' then
		return deserializeString(SerializedValue)
		
	elseif SerializedValue == "true" or SerializedValue == "false" then
		return deserializeBoolean(SerializedValue)
	end

	local NumericValue: number? = tonumber(SerializedValue)
	
	if NumericValue ~= nil then
		return NumericValue
	end

	local TypePrefix: string? = string.match(SerializedValue, "^([%a%d]+)%.")
	
	if TypePrefix then
		local DeserializerFunc = TypeDeserializerSwitch:Match(TypePrefix) :: ((string) -> any)?
		
		if DeserializerFunc then
			local DeserializedResult = DeserializerFunc(SerializedValue)
			
			if DeserializedResult ~= nil then
				return DeserializedResult
			end
		end
	end

	return SerializedValue
end

--[[
Deserializes a serialized value using the type router or inference fallback.

Params:
    SerializedValue: string -- The serialized value string
    RawType: string? -- The optional explicit datatype name

Returns:
    any -- The deserialized Roblox datatype or primitive value
]]
local function deserializeValue(SerializedValue: string, RawType: string?): any
	if RawType then
		local DeserializerFunc = TypeDeserializerSwitch:Match(RawType) :: ((string) -> any)?
		
		if DeserializerFunc then
			local DeserializedResult = DeserializerFunc(SerializedValue)
			
			if DeserializedResult ~= nil then
				return DeserializedResult
			end
		end
	end

	return inferAndDeserialize(SerializedValue)
end

--[[
Applies the Position property directly to the UIElement root struct.

Params:
    Element: AppState.UIElement -- Target element
    _Key: string -- Property key
    Value: any -- The UDim2 position value

Returns:
    () -- No return value
]]
local function applyPosition(Element: AppState.UIElement, _Key: string, Value: any): ()
	Element.Position = Value :: UDim2
end

--[[
Applies the Size property directly to the UIElement root struct.

Params:
    Element: AppState.UIElement -- Target element
    _Key: string -- Property key
    Value: any -- The UDim2 size value

Returns:
    () -- No return value
]]
local function applySize(Element: AppState.UIElement, _Key: string, Value: any): ()
	Element.Size = Value :: UDim2
end

--[[
Applies the Visible property directly to the UIElement root struct.

Params:
    Element: AppState.UIElement -- Target element
    _Key: string -- Property key
    Value: any -- The boolean visibility value

Returns:
    () -- No return value
]]
local function applyVisible(Element: AppState.UIElement, _Key: string, Value: any): ()
	Element.Visible = Value :: boolean
end

--[[
Applies the Name property directly to the UIElement root struct.

Params:
    Element: AppState.UIElement -- Target element
    _Key: string -- Property key
    Value: any -- The string name value

Returns:
    () -- No return value
]]
local function applyName(Element: AppState.UIElement, _Key: string, Value: any): ()
	Element.Name = Value :: string
end

--[[
Applies a generic property directly to the UIElement Properties bag.

Params:
    Element: AppState.UIElement -- Target element
    Key: string -- Property key
    Value: any -- The property value

Returns:
    () -- No return value
]]
local function applyGenericProperty(Element: AppState.UIElement, Key: string, Value: any): ()
	Element.Properties[Key] = Value
end

--[[
Recursively collects a target element ID and all its descendant IDs into a set.

Params:
    TargetNodeId: string -- The root element ID to start collecting from
    CollectedIds: { [string]: boolean } -- The output set tracking all discovered element IDs

Returns:
    () -- No return value
]]
local function collectDescendants(TargetNodeId: string, CollectedIds: { [string]: boolean }): ()
	CollectedIds[TargetNodeId] = true
	
	local CurrentElement: AppState.UIElement? = AppState.WorkspaceElements[TargetNodeId]
	
	if CurrentElement then
		for _, ChildId: string in ipairs(CurrentElement.Children) do
			collectDescendants(ChildId, CollectedIds)
		end
	end
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Loads and executes a BytecodeProgram, reconstructing virtual DOM elements and inserting them into AppState.

Params:
    Program: Bytecode_Types.BytecodeProgram -- The deserialized bytecode program
    Mode: ImportMode -- "Append", "Replace", or "Replace_Selected"

Returns:
    string? -- The ID of the newly imported root element, or nil if loading failed
]]
function Bytecode_Interpreter.Load(Program: Bytecode_Types.BytecodeProgram, Mode: ImportMode): string?
	if not Program.Instructions or #Program.Instructions == 0 then
		return nil
	end

	local InstructionIdToElementId: { [string]: string } = {}
	local ImportedElements: { [string]: AppState.UIElement } = {}
	local NodeHierarchyStack: { AppState.UIElement } = {}
	local ImportedRootId: string? = nil

	-- Execute opcodes through stack traversal
	for _, Instruction: Bytecode_Types.Instruction in ipairs(Program.Instructions) do
		if Instruction.Op == "OPEN_NODE" then
			local NewElementId: string = HttpService:GenerateGUID(false)
			local DefaultProperties = PropertyRegistry.GetDefaultsForType(Instruction.Type)
			local ParentElement: AppState.UIElement? = if #NodeHierarchyStack > 0 then NodeHierarchyStack[#NodeHierarchyStack] else nil
			local NewElement: AppState.UIElement = {
				Id = NewElementId,
				Type = Instruction.Type,
				Name = Instruction.Name,
				ParentId = if ParentElement then ParentElement.Id else nil,
				Children = {},
				Properties = DefaultProperties,
				Position = UDim2.new(0, 0, 0, 0),
				Size = UDim2.fromOffset(100, 100),
				Visible = true,
			}

			if ParentElement then
				ParentElement.Children[#ParentElement.Children + 1] = NewElementId
				
			else
				ImportedRootId = NewElementId
			end
			
			InstructionIdToElementId[Instruction.Id] = NewElementId
			NodeHierarchyStack[#NodeHierarchyStack + 1] = NewElement
			ImportedElements[NewElementId] = NewElement

		elseif Instruction.Op == "SET_PROP" then
			local ActiveElement: AppState.UIElement? = if #NodeHierarchyStack > 0 then NodeHierarchyStack[#NodeHierarchyStack] else nil
			
			if ActiveElement then
				local ParsedValue: any = deserializeValue(Instruction.SerializedValue, Instruction.RawType)
				
				if ParsedValue ~= nil then
					local PropertyApplier = RootPropertyApplierSwitch:Match(Instruction.Key, typeof(ParsedValue)) :: ((AppState.UIElement, string, any) -> ())?
					
					if PropertyApplier then
						PropertyApplier(ActiveElement, Instruction.Key, ParsedValue)
					end
				end
			end

		elseif Instruction.Op == "ATTACH_MODIFIER" then
			local ActiveElement: AppState.UIElement? = if #NodeHierarchyStack > 0 then NodeHierarchyStack[#NodeHierarchyStack] else nil
			
			if ActiveElement then
				local ModifierType: string = string.match(Instruction.Type, "^([%a%d]+)_") or Instruction.Type
				local RegisteredModifierDefaults = PropertyRegistry.GetModifierDefaults(ModifierType)
				local ModifierContainer: { [string]: any }

				if RegisteredModifierDefaults then
					ModifierContainer = RegisteredModifierDefaults
					
				else
					ModifierContainer = {
						IsModifier = true,
						Type = ModifierType,
						Properties = {},
					}
				end

				ModifierContainer.Type = ModifierType
				ModifierContainer.Id = Instruction.Key

				for PropertyName: string, SerializedPropertyValue: string in Instruction.Properties do
					local ParsedModifierValue: any = deserializeValue(SerializedPropertyValue, nil)
					
					if ParsedModifierValue ~= nil then
						ModifierContainer.Properties[PropertyName] = ParsedModifierValue
					end
				end

				ActiveElement.Properties[Instruction.Key] = ModifierContainer
			end

		elseif Instruction.Op == "CLOSE_NODE" then
			if #NodeHierarchyStack > 0 then
				NodeHierarchyStack[#NodeHierarchyStack] = nil
			end
		end
	end

	if not ImportedRootId or not ImportedElements[ImportedRootId] then
		return nil
	end

	-- Commit state according to selected ImportMode
	if Mode == "Replace" then
		History_Logic.PushSnapshot()

		-- Wipe existing elements
		for ExistingElementId: string in AppState.WorkspaceElements do
			AppState.WorkspaceElements[ExistingElementId] = nil
		end

		AppState.SessionState.PositionDialTracker.ElementId = nil
		AppState.SessionState.PositionDialTracker.OriginalPosition = nil
		AppState.SessionState.SizeDialTracker.ElementId = nil
		AppState.SessionState.SizeDialTracker.OriginalSize = nil
		AppState.SessionState.RotationDialTracker.ElementId = nil
		AppState.SessionState.RotationDialTracker.OriginalRotation = nil

		-- Insert imported elements
		ImportedElements[ImportedRootId].ParentId = nil
		
		for ElementId: string, ElementData: AppState.UIElement in ImportedElements do
			AppState.WorkspaceElements[ElementId] = ElementData
		end

		AppState.SelectedElementId = ImportedRootId

	elseif Mode == "Append" then
		History_Logic.PushSnapshot()
		ImportedElements[ImportedRootId].ParentId = nil
		
		for ElementId: string, ElementData: AppState.UIElement in ImportedElements do
			AppState.WorkspaceElements[ElementId] = ElementData
		end

		AppState.SelectedElementId = ImportedRootId

	elseif Mode == "Replace_Selected" then
		local SelectedTargetId: string? = AppState.SelectedElementId
		
		if not SelectedTargetId or not AppState.WorkspaceElements[SelectedTargetId] then
			return nil
		end

		local TargetElement: AppState.UIElement = AppState.WorkspaceElements[SelectedTargetId]
		local TargetParentId: string? = TargetElement.ParentId

		History_Logic.PushSnapshot()

		-- Collect target and all its descendants to remove
		local DescendantIdsToRemove: { [string]: boolean } = {}
		
		collectDescendants(SelectedTargetId, DescendantIdsToRemove)

		-- Splice into parent's Children array
		if TargetParentId then
			local ParentElement: AppState.UIElement? = AppState.WorkspaceElements[TargetParentId]
			
			if ParentElement then
				local NewChildren: { string } = {}
				
				for _, ChildId: string in ipairs(ParentElement.Children) do
					if ChildId == SelectedTargetId then
						NewChildren[#NewChildren + 1] = ImportedRootId
						
					else
						NewChildren[#NewChildren + 1] = ChildId
					end
				end
				
				ParentElement.Children = NewChildren
			end
			
			ImportedElements[ImportedRootId].ParentId = TargetParentId
			
		else
			ImportedElements[ImportedRootId].ParentId = nil
		end

		-- Remove target tree
		for ElementIdToRemove: string in DescendantIdsToRemove do
			if AppState.SessionState.PositionDialTracker.ElementId == ElementIdToRemove then
				AppState.SessionState.PositionDialTracker.ElementId = nil
				AppState.SessionState.PositionDialTracker.OriginalPosition = nil
			end
			
			if AppState.SessionState.SizeDialTracker.ElementId == ElementIdToRemove then
				AppState.SessionState.SizeDialTracker.ElementId = nil
				AppState.SessionState.SizeDialTracker.OriginalSize = nil
			end
			
			if AppState.SessionState.RotationDialTracker.ElementId == ElementIdToRemove then
				AppState.SessionState.RotationDialTracker.ElementId = nil
				AppState.SessionState.RotationDialTracker.OriginalRotation = nil
			end
			
			AppState.WorkspaceElements[ElementIdToRemove] = nil
		end

		-- Insert imported elements
		for ElementId: string, ElementData: AppState.UIElement in ImportedElements do
			AppState.WorkspaceElements[ElementId] = ElementData
		end

		AppState.SelectedElementId = ImportedRootId
	end

	return ImportedRootId
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Event Binding Section
----------------------------------------------------------
TypeDeserializerSwitch
	:Case("Color3"):Execute(deserializeColor3)
	:Case("UDim2"):Execute(deserializeUDim2)
	:Case("UDim"):Execute(deserializeUDim)
	:Case("Vector2"):Execute(deserializeVector2)
	:Case("Vector3"):Execute(deserializeVector3)
	:Case("Rect"):Execute(deserializeRect)
	:Case("NumberRange"):Execute(deserializeNumberRange)
	:Case("EnumItem"):Case("Enum"):Execute(deserializeEnumItem)
	:Case("ColorSequence"):Execute(deserializeColorSequence)
	:Case("NumberSequence"):Execute(deserializeNumberSequence)
	:Case("boolean"):Execute(deserializeBoolean)
	:Case("number"):Execute(deserializeNumber)
	:Case("string"):Execute(deserializeString)

RootPropertyApplierSwitch
	:Case("Position", Assignment.Op.AND)
	:Case("UDim2")
	:Execute(applyPosition)

	:Case("Size", Assignment.Op.AND)
	:Case("UDim2")
	:Execute(applySize)

	:Case("Visible", Assignment.Op.AND)
	:Case("boolean")
	:Execute(applyVisible)

	:Case("Name", Assignment.Op.AND)
	:Case("string")
	:Execute(applyName)

	:Default(applyGenericProperty)

----------------------------------------------------------
return Bytecode_Interpreter :: Bytecode_Interpreter
----------------------------------------------------------