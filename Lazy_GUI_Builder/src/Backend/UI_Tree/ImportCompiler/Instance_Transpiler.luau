--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Instance_Transpiler.luau
    
    SCOPE: UI Tree / Import Compiler
    
    ROLE: Crawls a native Roblox Studio Instance hierarchy (ScreenGui, Frame, etc.)
          and converts it directly into a standard BytecodeProgram opcode stream.
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
export type Instance_Transpiler = {
	Transpile: (RootInstance: Instance) -> Bytecode_Types.BytecodeProgram?,
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
local PropertyRegistry = require(script.Parent.Parent.Parent.Parent.PropertyRegistry)
local Assignment = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local Instance_Transpiler = {}
local ValueSerializerSwitch = Assignment.Switch("InstanceTranspiler_ValueSerializer")

local SUPPORTED_ELEMENT_TYPES: { [string]: boolean } = {
	Frame = true,
	TextLabel = true,
	TextButton = true,
	TextBox = true,
	ImageLabel = true,
	ImageButton = true,
	ScrollingFrame = true,
	CanvasGroup = true,
	VideoFrame = true,
	ViewportFrame = true,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Functions Section
----------------------------------------------------------

local function serializeColor3(Value: any): string
	local R: number = math.round(Value.R * 255)
	local G: number = math.round(Value.G * 255)
	local B: number = math.round(Value.B * 255)
	
	return string.format("Color3.fromRGB(%d, %d, %d)", R, G, B)
end

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

local function serializeUDim(Value: any): string
	return string.format("UDim.new(%s, %s)", tostring(Value.Scale), tostring(Value.Offset))
end

local function serializeVector2(Value: any): string
	return string.format("Vector2.new(%s, %s)", tostring(Value.X), tostring(Value.Y))
end

local function serializeVector3(Value: any): string
	return string.format("Vector3.new(%s, %s, %s)", tostring(Value.X), tostring(Value.Y), tostring(Value.Z))
end

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

local function serializeNumberSequence(Value: any): string
	local KpStrings: { string } = {}
	
	for _, Kp in ipairs(Value.Keypoints) do
		KpStrings[#KpStrings + 1] = string.format("NumberSequenceKeypoint.new(%s, %s, %s)", tostring(Kp.Time), tostring(Kp.Value), tostring(Kp.Envelope))
	end
	
	return string.format("NumberSequence.new({ %s })", table.concat(KpStrings, ", "))
end

local function serializeBoolean(Value: any): string
	return Value and "true" or "false"
end

local function serializeNumber(Value: any): string
	return tostring(Value)
end

local function serializeString(Value: any): string
	local Escaped: string = Value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\t", "\\t"):gsub("\r", "\\r")
	
	return '"' .. Escaped .. '"'
end

local function serializeDefault(Value: any): string
	return tostring(Value)
end

local function serializeValue(Value: any): string
	local SerializerFunc = ValueSerializerSwitch:Match(typeof(Value)) :: ((any) -> string)?
	
	if SerializerFunc then
		return SerializerFunc(Value)
	end
	
	return tostring(Value)
end

--[[
Recursively crawls a GuiObject instance and emits Bytecode instructions.
]]
local function crawlInstance(Target: GuiObject, AssignedKey: string, Instructions: { Bytecode_Types.Instruction }): ()
	local ElementType: string = Target.ClassName
	
	if not SUPPORTED_ELEMENT_TYPES[ElementType] then
		return
	end

	local NodeId: string = HttpService:GenerateGUID(false)

	-- OPEN_NODE
	Instructions[#Instructions + 1] = {
		Op = "OPEN_NODE",
		Id = NodeId,
		Type = ElementType,
		Name = Target.Name,
		Key = AssignedKey,
	}

	-- Emit properties registered in PropertyRegistry
	local RegisteredProps = PropertyRegistry.GetPropertiesForType(ElementType)
	
	for _, PropDef in ipairs(RegisteredProps) do
		local PropName: string = PropDef.Name
		local Success: boolean, CurrentVal: any = pcall(function(): any
			return (Target :: any)[PropName]
		end)

		if Success and CurrentVal ~= nil then
			Instructions[#Instructions + 1] = {
				Op = "SET_PROP",
				Key = PropName,
				SerializedValue = serializeValue(CurrentVal),
				RawType = typeof(CurrentVal),
			}
		end
	end

	-- Emit Modifiers & Children
	local ChildrenInstances = Target:GetChildren()
	local ChildNameCounts: { [string]: number } = {}

	for _, Child in ipairs(ChildrenInstances) do
		local ModProps = PropertyRegistry.GetModifierProperties(Child.ClassName)
		
		if ModProps then
			-- It is a modifier (e.g. UICorner, UIStroke, UIPadding)
			local SerializedModProps: { [string]: string } = {}
			
			for _, MPropDef in ipairs(ModProps) do
				local Success: boolean, MVal: any = pcall(function(): any
					return (Child :: any)[MPropDef.Name]
				end)
				
				if Success and MVal ~= nil then
					SerializedModProps[MPropDef.Name] = serializeValue(MVal)
				end
			end

			Instructions[#Instructions + 1] = {
				Op = "ATTACH_MODIFIER",
				Type = Child.ClassName,
				Key = Child.Name,
				Properties = SerializedModProps,
			}
			
		elseif Child:IsA("GuiObject") and SUPPORTED_ELEMENT_TYPES[Child.ClassName] then
			-- It is a child GuiObject
			local BaseName: string = Child.Name
			local Occurrence: number = (ChildNameCounts[BaseName] or 0) + 1
			local DeduplicatedKey: string = (Occurrence == 1) and BaseName or (BaseName .. "_" .. tostring(Occurrence))
			
			ChildNameCounts[BaseName] = Occurrence
			crawlInstance(Child, DeduplicatedKey, Instructions)
		end
	end

	-- CLOSE_NODE
	Instructions[#Instructions + 1] = {
		Op = "CLOSE_NODE",
		Id = NodeId,
	}
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Transpiles a selected native Roblox instance (or child GuiObject) into a BytecodeProgram.

Params:
    RootInstance: Instance -- The native Studio instance selected in Explorer

Returns:
    Bytecode_Types.BytecodeProgram? -- The generated bytecode program, or nil if unconvertible
]]
function Instance_Transpiler.Transpile(RootInstance: Instance): Bytecode_Types.BytecodeProgram?
	local TargetGuiObject: GuiObject? = nil

	if RootInstance:IsA("GuiObject") and SUPPORTED_ELEMENT_TYPES[RootInstance.ClassName] then
		TargetGuiObject = RootInstance :: GuiObject
		
	elseif RootInstance:IsA("ScreenGui") or RootInstance:IsA("Folder") then
		for _, Child in ipairs(RootInstance:GetChildren()) do
			if Child:IsA("GuiObject") and SUPPORTED_ELEMENT_TYPES[Child.ClassName] then
				TargetGuiObject = Child :: GuiObject
				
				break
			end
		end
	end

	if not TargetGuiObject then
		return nil
	end

	local Instructions: { Bytecode_Types.Instruction } = {}
	local RootGUID: string = HttpService:GenerateGUID(false)

	crawlInstance(TargetGuiObject, TargetGuiObject.Name, Instructions)

	return {
		Version = 1,
		Build_Iteration = 1,
		RootId = RootGUID,
		ComponentName = TargetGuiObject.Name,
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
return Instance_Transpiler :: Instance_Transpiler
----------------------------------------------------------