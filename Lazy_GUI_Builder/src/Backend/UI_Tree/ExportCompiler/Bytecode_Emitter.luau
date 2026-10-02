--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Bytecode_Emitter.luau
    
    SCOPE: UI Tree / Export Compiler / Core Compiler
    
    ROLE: Traverses the visual tree from AppState.WorkspaceElements, applies
          dual-default property omission, serializes Roblox datatypes, and emits
          a deterministic, framework-agnostic BytecodeProgram opcode stream.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.Parent.Parent.AppState)
local PropertyRegistry = require(script.Parent.Parent.Parent.Parent.PropertyRegistry)
local Assignment = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)
local Bytecode_Types = require(script.Parent.Bytecode_Types)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type Bytecode_Emitter = {
	Compile: (ComponentName: string, RootId: string, BuildIteration: number?) -> Bytecode_Types.BytecodeProgram,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local Bytecode_Emitter = {}
local ValueSerializerSwitch = Assignment.Switch("ExportCompiler_ValueSerializer")

local ROBLOX_ENGINE_DEFAULTS: { [string]: any } = {
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 0, 0, 0),
	Size = UDim2.new(0, 0, 0, 0),
	Rotation = 0,
	AutomaticSize = Enum.AutomaticSize.None,
	SizeConstraint = Enum.SizeConstraint.RelativeXY,
	Visible = true,
	BackgroundColor3 = Color3.fromRGB(163, 162, 165),
	BackgroundTransparency = 0,
	BorderColor3 = Color3.fromRGB(27, 42, 53),
	BorderSizePixel = 0,
	BorderMode = Enum.BorderMode.Outline,
	ZIndex = 1,
	LayoutOrder = 0,
	ClipsDescendants = false,
	Active = false,
	Interactable = true,
	Selectable = false,
	SelectionGroup = false,
	Text = "Label",
	TextColor3 = Color3.fromRGB(27, 42, 53),
	TextTransparency = 0,
	TextSize = 8,
	Font = Enum.Font.SourceSans,
	TextXAlignment = Enum.TextXAlignment.Center,
	TextYAlignment = Enum.TextYAlignment.Center,
	TextWrapped = false,
	TextScaled = false,
	RichText = false,
	LineHeight = 1,
	MaxVisibleGraphemes = -1,
	TextStrokeColor3 = Color3.fromRGB(0, 0, 0),
	TextStrokeTransparency = 1,
	TextDirection = Enum.TextDirection.Auto,
	TextTruncate = Enum.TextTruncate.None,
	Image = "",
	ImageColor3 = Color3.fromRGB(255, 255, 255),
	ImageTransparency = 0,
	ScaleType = Enum.ScaleType.Stretch,
	ResampleMode = Enum.ResamplerMode.Default,
	AutoButtonColor = true,
	Modal = false,
	Selected = false,
	GroupTransparency = 0,
	GroupColor3 = Color3.fromRGB(255, 255, 255),
	ScrollingDirection = Enum.ScrollingDirection.XY,
	ScrollBarThickness = 12,
	ScrollingEnabled = true,
	CanvasSize = UDim2.new(0, 0, 2, 0),
	ScrollBarImageTransparency = 0,
	PlaceholderText = "",
	PlaceholderColor3 = Color3.fromRGB(178, 178, 178),
	ClearTextOnFocus = true,
	MultiLine = false,
	TextEditable = true,
	ShowNativeInput = true,
	Ambient = Color3.fromRGB(200, 200, 200),
	LightColor = Color3.fromRGB(140, 140, 140),
	LightDirection = Vector3.new(-1, -1, -1),
}

local MODIFIER_ROBLOX_DEFAULTS: { [string]: { [string]: any } } = {
	UICorner = {
		CornerRadius = UDim.new(0, 8),
	},
	
	UIStroke = {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Color = Color3.fromRGB(0, 0, 0),
		Enabled = true,
		LineJoinMode = Enum.LineJoinMode.Round,
		Thickness = 1,
		Transparency = 0,
	},
	
	UIPadding = {
		PaddingBottom = UDim.new(0, 0),
		PaddingLeft = UDim.new(0, 0),
		PaddingRight = UDim.new(0, 0),
		PaddingTop = UDim.new(0, 0),
	},
	
	UIAspectRatioConstraint = {
		AspectRatio = 1,
		AspectType = Enum.AspectType.FitWithinMaxSize,
		DominantAxis = Enum.DominantAxis.Width,
	},
	
	UIScale = {
		Scale = 1,
	},
	
	UIListLayout = {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
		SortOrder = Enum.SortOrder.Name,
		Padding = UDim.new(0, 0),
	},
	
	UIGridLayout = {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.Name,
		CellSize = UDim2.new(0, 100, 0, 100),
		CellPadding = UDim2.new(0, 5, 0, 5),
		StartCorner = Enum.StartCorner.TopLeft,
	},
}

local PROPERTY_SORT_ORDER: { [string]: number } = {
	-- Transform
	AnchorPoint = 1,
	Position = 2,
	Size = 3,
	Rotation = 4,
	AutomaticSize = 5,
	SizeConstraint = 6,

	-- Appearance
	BackgroundColor3 = 10,
	BackgroundTransparency = 11,
	BorderColor3 = 12,
	BorderSizePixel = 13,
	BorderMode = 14,

	-- Text
	Text = 20,
	TextColor3 = 21,
	TextTransparency = 22,
	TextSize = 23,
	Font = 24,
	TextXAlignment = 25,
	TextYAlignment = 26,
	TextWrapped = 27,
	TextScaled = 28,
	RichText = 29,
	LineHeight = 30,
	MaxVisibleGraphemes = 31,
	TextStrokeColor3 = 32,
	TextStrokeTransparency = 33,
	TextDirection = 34,
	TextTruncate = 35,

	-- Text Input
	PlaceholderText = 40,
	PlaceholderColor3 = 41,
	ClearTextOnFocus = 42,
	MultiLine = 43,
	TextEditable = 44,
	ShowNativeInput = 45,

	-- Image
	Image = 50,
	ImageColor3 = 51,
	ImageTransparency = 52,
	ScaleType = 53,
	ResampleMode = 54,
	ImageRectOffset = 55,
	ImageRectSize = 56,
	TileSize = 57,
	SliceScale = 58,

	-- Scrolling
	CanvasSize = 60,
	CanvasPosition = 61,
	AutomaticCanvasSize = 62,
	ScrollingDirection = 63,
	ScrollBarThickness = 64,
	ScrollingEnabled = 65,
	ElasticBehavior = 66,
	HorizontalScrollBarInset = 67,
	VerticalScrollBarInset = 68,
	VerticalScrollBarPosition = 69,
	ScrollBarImageColor3 = 70,
	ScrollBarImageTransparency = 71,
	TopImage = 72,
	MidImage = 73,
	BottomImage = 74,

	-- Behavior
	Active = 80,
	Interactable = 81,
	Selectable = 82,
	SelectionGroup = 83,
	ClipsDescendants = 84,
	ZIndex = 85,
	LayoutOrder = 86,
	Visible = 87,

	-- Button
	AutoButtonColor = 90,
	Modal = 91,
	Selected = 92,
	Style = 93,
	HoverImage = 94,
	PressedImage = 95,

	-- CanvasGroup / Video / Viewport
	GroupColor3 = 100,
	GroupTransparency = 101,
	Video = 102,
	Playing = 103,
	Looped = 104,
	Volume = 105,
	TimePosition = 106,
	RollOffMode = 107,
	RollOffMinDistance = 108,
	RollOffMaxDistance = 109,
	Ambient = 110,
	LightColor = 111,
	LightDirection = 112,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Functions Section
----------------------------------------------------------

--[[
Checks equality between two values, accounting for Color3 float rounding.
]]
local function isValueEqual(Val1: any, Val2: any): boolean
	if typeof(Val1) ~= typeof(Val2) then
		return false
	end

	if typeof(Val1) == "Color3" then
		local R1: number = math.round(Val1.R * 255)
		local G1: number = math.round(Val1.G * 255)
		local B1: number = math.round(Val1.B * 255)

		local R2: number = math.round(Val2.R * 255)
		local G2: number = math.round(Val2.G * 255)
		local B2: number = math.round(Val2.B * 255)

		return R1 == R2 and G1 == G2 and B1 == B2
	end

	return Val1 == Val2
end

--[[
Determines whether a property can be safely omitted from bytecode generation.
A property is omitted ONLY if both Roblox engine defaults and GUI Builder defaults
are defined and identical, AND the current value matches that shared default.
]]
local function shouldOmitProperty(RobloxDefault: any, GUIBuilderDefault: any, CurrentValue: any): boolean
	if RobloxDefault == nil or GUIBuilderDefault == nil then
		return false
	end

	if not isValueEqual(RobloxDefault, GUIBuilderDefault) then
		return false
	end

	return isValueEqual(CurrentValue, RobloxDefault)
end

--[[
Serializes a Color3 value into Color3.fromRGB constructor code.
]]
local function serializeColor3(Value: any): string
	local R: number = math.round(Value.R * 255)
	local G: number = math.round(Value.G * 255)
	local B: number = math.round(Value.B * 255)

	return string.format("Color3.fromRGB(%d, %d, %d)", R, G, B)
end

--[[
Serializes a UDim2 value into concise UDim2 constructor code.
]]
local function serializeUDim2(Value: any): string
	local XScale: number = Value.X.Scale
	local XOffset: number = Value.X.Offset
	local YScale: number = Value.Y.Scale
	local YOffset: number = Value.Y.Offset

	if XScale == 0 and YScale == 0 then
		if XOffset == 0 and YOffset == 0 then
			return "UDim2.new()"
		end

		return string.format("UDim2.fromOffset(%s, %s)", tostring(XOffset), tostring(YOffset))
		
	elseif XOffset == 0 and YOffset == 0 then
		return string.format("UDim2.fromScale(%s, %s)", tostring(XScale), tostring(YScale))
		
	else
		return string.format("UDim2.new(%s, %s, %s, %s)", tostring(XScale), tostring(XOffset), tostring(YScale), tostring(YOffset))
	end
end

--[[
Serializes a UDim value into UDim.new constructor code.
]]
local function serializeUDim(Value: any): string
	return string.format("UDim.new(%s, %s)", tostring(Value.Scale), tostring(Value.Offset))
end

--[[
Serializes a Vector2 value into Vector2.new constructor code.
]]
local function serializeVector2(Value: any): string
	return string.format("Vector2.new(%s, %s)", tostring(Value.X), tostring(Value.Y))
end

--[[
Serializes a Vector3 value into Vector3.new constructor code.
]]
local function serializeVector3(Value: any): string
	return string.format("Vector3.new(%s, %s, %s)", tostring(Value.X), tostring(Value.Y), tostring(Value.Z))
end

--[[
Serializes an EnumItem or Enum into its identifier string.
]]
local function serializeEnumItem(Value: any): string
	if typeof(Value) == "EnumItem" then
		if Value.EnumType == Enum.SortOrder and Value.Name == "Custom" then
			return "Enum.SortOrder.LayoutOrder"
			
		elseif tostring(Value.EnumType) == "Enum.UIDragDetectorDragStyle" and Value.Name == "Custom" then
			return "Enum.UIDragDetectorDragStyle.TranslatePlane"
		end
	end

	return tostring(Value)
end

--[[
Serializes a ColorSequence value into ColorSequence.new constructor code.
]]
local function serializeColorSequence(Value: any): string
	local KpStrings: { string } = {}

	for _, Kp in ipairs(Value.Keypoints) do
		local R: number = math.round(Kp.Value.R * 255)
		local G: number = math.round(Kp.Value.G * 255)
		local B: number = math.round(Kp.Value.B * 255)

		KpStrings[#KpStrings + 1] = string.format("ColorSequenceKeypoint.new(%s, Color3.fromRGB(%d, %d, %d))", tostring(Kp.Time), R, G, B)
	end

	return string.format("ColorSequence.new({ %s })", table.concat(KpStrings, ", "))
end

--[[
Serializes a NumberSequence value into NumberSequence.new constructor code.
]]
local function serializeNumberSequence(Value: any): string
	local KpStrings: { string } = {}

	for _, Kp in ipairs(Value.Keypoints) do
		KpStrings[#KpStrings + 1] = string.format("NumberSequenceKeypoint.new(%s, %s, %s)", tostring(Kp.Time), tostring(Kp.Value), tostring(Kp.Envelope))
	end

	return string.format("NumberSequence.new({ %s })", table.concat(KpStrings, ", "))
end

--[[
Serializes a boolean value into a string literal.
]]
local function serializeBoolean(Value: any): string
	return Value and "true" or "false"
end

--[[
Serializes a number value into a string literal.
]]
local function serializeNumber(Value: any): string
	return tostring(Value)
end

--[[
Serializes a string value into an escaped, double-quoted Luau string literal.
]]
local function serializeString(Value: any): string
	local Escaped: string = Value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r")

	return '"' .. Escaped .. '"'
end

--[[
Fallback serializer for unhandled types.
]]
local function serializeDefault(Value: any): string
	return tostring(Value)
end

--[[
Serializes a Roblox datatype or Luau primitive using the Assignment.Switch router.
]]
local function serializeValue(Value: any): string
	local SerializerFunc = ValueSerializerSwitch:Match(typeof(Value)) :: ((any) -> string)?

	if SerializerFunc then
		return SerializerFunc(Value)
	end

	return tostring(Value)
end

--[[
Recursively crawls a UIElement and emits intermediate bytecode instructions.
]]
local function emitElement(ElementId: string, AssignedKey: string, Instructions: { Bytecode_Types.Instruction }): ()
	local Element: AppState.UIElement? = AppState.WorkspaceElements[ElementId]
	
	if not Element then
		return
	end

	-- OPEN_NODE
	Instructions[#Instructions + 1] = {
		Op = "OPEN_NODE",
		Id = Element.Id,
		Type = Element.Type,
		Name = Element.Name,
		Key = AssignedKey,
	}

	-- Extract and emit standard properties (filtering out modifiers and engine/default duplicates)
	local StandardProps: { [string]: any } = {}
	local Modifiers: { { Key: string, Value: any } } = {}

	for Key: string, Val: any in Element.Properties do
		if type(Val) == "table" and Val.IsModifier == true then
			Modifiers[#Modifiers + 1] = {
				Key = Key, 
				Value = Val 
			}
			
		else
			StandardProps[Key] = Val
		end
	end

	-- Ensure base properties are present
	StandardProps["Position"] = Element.Position
	StandardProps["Size"] = Element.Size
	StandardProps["Visible"] = Element.Visible

	local Gui_BuilderDefaults: { [string]: any } = PropertyRegistry.GetDefaultsForType(Element.Type)
	local SortedPropKeys: { string } = {}

	for PropKey: string, PropVal: any in StandardProps do
		local RobloxDef: any = ROBLOX_ENGINE_DEFAULTS[PropKey]
		local Gui_BuilderDef: any = Gui_BuilderDefaults[PropKey]

		if not shouldOmitProperty(RobloxDef, Gui_BuilderDef, PropVal) then
			SortedPropKeys[#SortedPropKeys + 1] = PropKey
		end
	end

	table.sort(SortedPropKeys, function(A: string, B: string): boolean
		local OrderA: number = PROPERTY_SORT_ORDER[A] or 999
		local OrderB: number = PROPERTY_SORT_ORDER[B] or 999

		if OrderA ~= OrderB then
			return OrderA < OrderB
		end

		return A < B
	end)

	for _, PropKey: string in ipairs(SortedPropKeys) do
		Instructions[#Instructions + 1] = {
			Op = "SET_PROP",
			Key = PropKey,
			SerializedValue = serializeValue(StandardProps[PropKey]),
			RawType = typeof(StandardProps[PropKey]),
		}
	end

	-- Extract and emit modifiers (with deduplicated keys if multiple exist)
	table.sort(Modifiers, function(A, B): boolean
		return A.Key < B.Key
	end)

	local ModifierTypeTotals: { [string]: number } = {}
	
	for _, Mod in ipairs(Modifiers) do
		local ModType: string = (type(Mod.Value) == "table" and Mod.Value.Type) or string.match(Mod.Key, "^([%a%d]+)_") or Mod.Key
		
		ModifierTypeTotals[ModType] = (ModifierTypeTotals[ModType] or 0) + 1
	end

	local ModifierTypeCounters: { [string]: number } = {}
	
	for _, Mod in ipairs(Modifiers) do
		local ModType: string = (type(Mod.Value) == "table" and Mod.Value.Type) or string.match(Mod.Key, "^([%a%d]+)_") or Mod.Key
		local ModKey: string = ModType
		local TotalCount: number = ModifierTypeTotals[ModType] or 0

		if TotalCount > 1 then
			local CurrentNum: number = (ModifierTypeCounters[ModType] or 0) + 1
			
			ModifierTypeCounters[ModType] = CurrentNum
			ModKey = ModType .. "_" .. tostring(CurrentNum)
		end

		local ModProps: { [string]: any } = Mod.Value.Properties or {}
		local ModRobloxDefaults: { [string]: any }? = MODIFIER_ROBLOX_DEFAULTS[ModType]
		local ModGui_BuilderDefaultsBag: { [string]: any }? = PropertyRegistry.GetModifierDefaults(ModType)
		local ModGui_BuilderDefaults: { [string]: any } = (ModGui_BuilderDefaultsBag and ModGui_BuilderDefaultsBag.Properties) or {}
		local SerializedModProps: { [string]: string } = {}

		for PKey: string, PVal: any in ModProps do
			local RobloxDef: any = ModRobloxDefaults and ModRobloxDefaults[PKey]

			if not shouldOmitProperty(RobloxDef, ModGui_BuilderDefaults[PKey], PVal) then
				SerializedModProps[PKey] = serializeValue(PVal)
			end
		end

		Instructions[#Instructions + 1] = {
			Op = "ATTACH_MODIFIER",
			Type = ModType,
			Key = ModKey,
			Properties = SerializedModProps,
		}
	end

	-- Crawl child elements in tree order with deduplicated sibling keys
	local ChildNameCounts: { [string]: number } = {}
	
	for _, ChildId: string in ipairs(Element.Children) do
		local ChildElement: AppState.UIElement? = AppState.WorkspaceElements[ChildId]
		
		if ChildElement then
			local BaseName: string = ChildElement.Name
			local Occurrence: number = (ChildNameCounts[BaseName] or 0) + 1
			local DeduplicatedKey: string = (Occurrence == 1) and BaseName or (BaseName .. "_" .. tostring(Occurrence))
			
			ChildNameCounts[BaseName] = Occurrence
			emitElement(ChildId, DeduplicatedKey, Instructions)
		end
	end

	-- CLOSE_NODE
	Instructions[#Instructions + 1] = {
		Op = "CLOSE_NODE",
		Id = Element.Id,
	}
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Compiles the visual node tree starting at RootId into a complete BytecodeProgram.

Params:
    ComponentName: string -- The component name identifier
    RootId: string -- The GUID of the root element to compile
    BuildIteration: number? -- The build iteration count (defaults to 1)

Returns:
    Bytecode_Types.BytecodeProgram -- The compiled opcode instruction stream
]]
function Bytecode_Emitter.Compile(ComponentName: string, RootId: string, BuildIteration: number?): Bytecode_Types.BytecodeProgram
	local Instructions: { Bytecode_Types.Instruction } = {}

	emitElement(RootId, ComponentName, Instructions)

	return {
		Version = 1,
		Build_Iteration = BuildIteration or 1,
		RootId = RootId,
		ComponentName = ComponentName,
		Instructions = Instructions,
	}
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Event Binding Section
----------------------------------------------------------
ValueSerializerSwitch
	:Case("Color3"):Execute(serializeColor3)
	:Case("UDim2"):Execute(serializeUDim2)
	:Case("UDim"):Execute(serializeUDim)
	:Case("Vector2"):Execute(serializeVector2)
	:Case("Vector3"):Execute(serializeVector3)
	:Case("EnumItem"):Case("Enum"):Execute(serializeEnumItem)
	:Case("ColorSequence"):Execute(serializeColorSequence)
	:Case("NumberSequence"):Execute(serializeNumberSequence)
	:Case("boolean"):Execute(serializeBoolean)
	:Case("number"):Execute(serializeNumber)
	:Case("string"):Execute(serializeString)
	:Default(serializeDefault)

----------------------------------------------------------
return Bytecode_Emitter :: Bytecode_Emitter
----------------------------------------------------------