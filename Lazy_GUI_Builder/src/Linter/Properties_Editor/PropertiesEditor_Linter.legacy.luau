--!strict

local RunService: RunService = game:GetService("RunService")

if RunService:IsRunning() then
	return
end
--[[
    ===========================================================================
    MODULE/COMPONENT: PropertiesEditor_Linter.legacy.luau
    
    SCOPE: Correctness Linter Pillar
    
    ROLE: Validates user input from the Properties Editor to ensure safety,
          type correctness, and validity before routing to the Controller.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Linter Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.Parent.AppState)
local PropertyRegistry = require(script.Parent.Parent.Parent.PropertyRegistry)
local Assignment = require(script.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Linter Internal States Section
----------------------------------------------------------
local TypeValidatorSwitch = Assignment.Switch("PropertiesEditor_ValueTypeValidator")

local ASSET_PROPERTY_KEYS: { [string]: boolean } = {
	Image = true,
	HoverImage = true,
	PressedImage = true,
	TopImage = true,
	MidImage = true,
	BottomImage = true,
	Video = true,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Linter Local Function Section
----------------------------------------------------------

--[[
Sanitizes raw asset inputs, converting raw IDs, website URLs, and common typo schemes into valid rbxassetid URIs.

Params:
    RawInput: string -- The raw string entered by the user

Returns:
    string -- The formatted asset URI
]]
local function sanitizeAssetString(RawInput: string): string
	local Str: string = string.gsub(RawInput, "^%s*(.-)%s*$", "%1")
	
	if Str == "" then
		return ""
	end
	
	if string.sub(Str, 1, 11) == "rbxthumb://" or string.sub(Str, 1, 12) == "rbxassetid://" then
		return Str
	end
	
	if string.match(Str, "^%d+$") then
		return "rbxassetid://" .. Str
	end
	
	local TypoId: string? = string.match(Str, "^rbxasset://(%d+)$")
	
	if TypoId then
		return "rbxassetid://" .. TypoId
	end
	
	local UrlQueryId: string? = string.match(Str, "[?&]id=(%d+)")
	
	if UrlQueryId then
		return "rbxassetid://" .. UrlQueryId
	end
	
	local LibraryId: string? = string.match(Str, "roblox%.com/library/(%d+)")
	
	if LibraryId then
		return "rbxassetid://" .. LibraryId
	end
	
	local CatalogId: string? = string.match(Str, "roblox%.com/catalog/(%d+)")
	
	if CatalogId then
		return "rbxassetid://" .. CatalogId
	end
	
	return Str
end

-- Validates if a value is a number.
local function validateNumber(Value: any): boolean
	return type(Value) == "number" 
end

-- Validates if a value is a string.
local function validateString(Value: any): boolean
	return type(Value) == "string"
end

-- Validates if a value is a boolean.
local function validateBoolean(Value: any): boolean
	return type(Value) == "boolean" 
end

-- Validates if a value is a Color3.
local function validateColor3(Value: any): boolean
	return typeof(Value) == "Color3"
end

-- Validates if a value is a UDim2.
local function validateUDim2(Value: any): boolean 
	return typeof(Value) == "UDim2"
end

-- Validates if a value is a Vector2.
local function validateVector2(Value: any): boolean
	return typeof(Value) == "Vector2"
end

-- Validates if a value is a Vector3.
local function validateVector3(Value: any): boolean
	return typeof(Value) == "Vector3" 
end

-- Validates if a value is a UDim.
local function validateUDim(Value: any): boolean 
	return typeof(Value) == "UDim"
end

-- Validates if a value is an EnumItem.
local function validateEnum(Value: any): boolean
	return typeof(Value) == "EnumItem"
end

-- Validates if a value is a ColorSequence.
local function validateColorSequence(Value: any): boolean
	if typeof(Value) == "ColorSequence" then
		return #Value.Keypoints >= 2 and #Value.Keypoints <= 20
	end
	
	return false
end

-- Validates if a value is a NumberSequence.
local function validateNumberSequence(Value: any): boolean
	if typeof(Value) == "NumberSequence" then
		if #Value.Keypoints < 2 or #Value.Keypoints > 20 then
			return false
		end
		
		for _, Kp in ipairs(Value.Keypoints) do
			if Kp.Time < 0 or Kp.Time > 1 or Kp.Value < 0 or Kp.Value > 1 then
				return false
			end
		end
		
		return true
	end
	
	return false
end

-- Fires a generic error notification via Relay.
local function fireError(Message: string): ()
	Relay.Create("ShowNotification"):Fire({
		Message = Message,
		Type = "Error"
	})
end

-- Handles TogglePropertiesEditor_CL.
local function onTogglePropertiesEditorCL(): ()
	Relay.Create("TogglePropertiesEditor"):Fire()
end

-- Handles SetElementName_CL.
local function onSetElementNameCL(Payload: { Id: string, Name: string }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	if type(Payload.Name) ~= "string" or string.match(Payload.Name, "^%s*$") then
		fireError("Name Update Failed. Name Cannot Be Empty.")
		
		return
	end
	
	Relay.Create("SetElementName"):Fire(Payload)
end

-- Handles SetElementPosition_CL.
local function onSetElementPositionCL(Payload: { Id: string, Position: UDim2 }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	if typeof(Payload.Position) ~= "UDim2" then 
		fireError("Position Update Failed. Invalid Position Format.")
		
		return 
	end
	
	local PropDef
	
	for _, def in ipairs(PropertyRegistry.GetPropertiesForType(AppState.WorkspaceElements[Payload.Id].Type)) do
		if def.Name == "Position" then
			PropDef = def
			
			break
		end
	end
	
	if PropDef then
		local newXScale = Payload.Position.X.Scale
		local newYScale = Payload.Position.Y.Scale
		local newXOffset = Payload.Position.X.Offset
		local newYOffset = Payload.Position.Y.Offset
		
		if PropDef.Min ~= nil and PropDef.Max ~= nil then
			newXScale = math.clamp(newXScale, PropDef.Min, PropDef.Max)
			newYScale = math.clamp(newYScale, PropDef.Min, PropDef.Max)
		end
		
		if PropDef.OffsetMin ~= nil then
			newXOffset = math.max(PropDef.OffsetMin, newXOffset)
			newYOffset = math.max(PropDef.OffsetMin, newYOffset)
		end
		
		if PropDef.OffsetMax ~= nil then
			newXOffset = math.min(PropDef.OffsetMax, newXOffset)
			newYOffset = math.min(PropDef.OffsetMax, newYOffset)
		end
		
		Payload.Position = UDim2.new(newXScale, newXOffset, newYScale, newYOffset)
	end
	
	Relay.Create("SetElementPosition"):Fire({
		Id = Payload.Id, 
		Position = Payload.Position 
	})
end

-- Handles SetElementSize_CL.
local function onSetElementSizeCL(Payload: { Id: string, Size: UDim2 }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	if typeof(Payload.Size) ~= "UDim2" then 
		fireError("Size Update Failed. Invalid Size Format.")
		
		return 
	end

	local PropDef
	
	for _, def in ipairs(PropertyRegistry.GetPropertiesForType(AppState.WorkspaceElements[Payload.Id].Type)) do
		if def.Name == "Size" then
			PropDef = def
			
			break
		end
	end
	
	if PropDef then
		local newXScale = Payload.Size.X.Scale
		local newYScale = Payload.Size.Y.Scale
		local newXOffset = Payload.Size.X.Offset
		local newYOffset = Payload.Size.Y.Offset
		
		if PropDef.Min ~= nil and PropDef.Max ~= nil then
			newXScale = math.clamp(newXScale, PropDef.Min, PropDef.Max)
			newYScale = math.clamp(newYScale, PropDef.Min, PropDef.Max)
		end
		
		if PropDef.OffsetMin ~= nil then
			newXOffset = math.max(PropDef.OffsetMin, newXOffset)
			newYOffset = math.max(PropDef.OffsetMin, newYOffset)
		end
		
		if PropDef.OffsetMax ~= nil then
			newXOffset = math.min(PropDef.OffsetMax, newXOffset)
			newYOffset = math.min(PropDef.OffsetMax, newYOffset)
		end
		
		Payload.Size = UDim2.new(newXScale, newXOffset, newYScale, newYOffset)
	end
	
	Relay.Create("SetElementSize"):Fire({
		Id = Payload.Id,
		Size = Payload.Size
	})
end

-- Handles SetElementRotation_CL.
local function onSetElementRotationCL(Payload: { Id: string, Rotation: any }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	if type(Payload.Rotation) ~= "number" then 
		fireError("Rotation Update Failed. Invalid Number Format.")
		
		return 
	end

	Relay.Create("SetElementRotation"):Fire({
		Id = Payload.Id, 
		Rotation = Payload.Rotation 
	})
end

-- Handles SetElementVisible_CL.
local function onSetElementVisibleCL(Payload: { Id: string, Visible: boolean }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	if type(Payload.Visible) ~= "boolean" then return end
	
	Relay.Create("SetElementVisible"):Fire(Payload)
end

-- Handles SetElementProperty_CL.
local function onSetElementPropertyCL(Payload: { Id: string, Key: string, Value: any, ValueType: string }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	local ValidatorFunc = TypeValidatorSwitch:Match(Payload.ValueType)
	local IsValid = ValidatorFunc and ValidatorFunc(Payload.Value) or false
	
	if not IsValid then
		if Payload.ValueType == "boolean" or Payload.ValueType == "Enum" then return end
		
		fireError("Property Update Failed. Invalid Value Format For " .. Payload.Key .. ".")
		
		return
	end
	
	local PropDef
	
	for _, def in ipairs(PropertyRegistry.GetPropertiesForType(AppState.WorkspaceElements[Payload.Id].Type)) do
		if def.Name == Payload.Key then
			PropDef = def
			
			break
		end
	end
	
	if PropDef and Payload.ValueType == "number" then
		if PropDef.Min ~= nil and Payload.Value < PropDef.Min then
			Payload.Value = PropDef.Min
		end
		
		if PropDef.Max ~= nil and Payload.Value > PropDef.Max then
			Payload.Value = PropDef.Max
		end
	end

	if ASSET_PROPERTY_KEYS[Payload.Key] and type(Payload.Value) == "string" then
		Payload.Value = sanitizeAssetString(Payload.Value)
	end
	
	Relay.Create("SetElementProperty"):Fire({
		Id = Payload.Id,
		Key = Payload.Key,
		Value = Payload.Value,
	})
end

-- Handles AddModifier_CL.
local function onAddModifierCL(Payload: { Id: string, ModifierType: string }): ()
	local Element = AppState.WorkspaceElements[Payload.Id]
	
	if not Element then return end
	
	local IsValidMod = false
	
	for _, Mod: string in ipairs(PropertyRegistry.GetAvailableModifiers()) do
		if Mod == Payload.ModifierType then
			IsValidMod = true
			
			break
		end
	end
	
	if not IsValidMod then return end
	
	if not PropertyRegistry.AllowsMultipleInstances(Payload.ModifierType) then
		for Key: string, Value: any in Element.Properties do
			local RawType: string = (type(Value) == "table" and Value.Type) or Key
			local ModType: string = string.match(RawType, "^([%a%d]+)_") or RawType
			
			if type(Value) == "table" and Value.IsModifier and ModType == Payload.ModifierType then
				fireError("Add Modifier Failed. Modifier Already Attached.")
				
				return
			end
		end
		
	else
		local InstanceCount = 0
		
		for Key: string, Value: any in Element.Properties do
			local RawType: string = (type(Value) == "table" and Value.Type) or Key
			local ModType: string = string.match(RawType, "^([%a%d]+)_") or RawType
			
			if type(Value) == "table" and Value.IsModifier and ModType == Payload.ModifierType then
				InstanceCount += 1
			end
		end
		
		if InstanceCount >= 10 then
			fireError("Add Modifier Failed. Maximum Instance Limit Reached.")
			
			return
		end
	end
	
	if not PropertyRegistry.IsModifierCompatible(Payload.ModifierType, Element.Type) then
		fireError("Add Modifier Failed. " .. Payload.ModifierType .. " Is Incompatible With " .. Element.Type .. ".")
		
		return
	end
	
	local ConflictingMod: string? = PropertyRegistry.GetConflictingModifier(Payload.ModifierType, Element.Properties)
	
	if ConflictingMod then
		fireError("Add Modifier Failed. Cannot Combine " .. Payload.ModifierType .. " With " .. ConflictingMod .. ".")
		
		return
	end
	
	Relay.Create("AddModifier"):Fire(Payload)
end

-- Handles RemoveModifier_CL.
local function onRemoveModifierCL(Payload: { Id: string, ModifierKey: string }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	if not AppState.WorkspaceElements[Payload.Id].Properties[Payload.ModifierKey] then return end
	
	Relay.Create("RemoveModifier"):Fire(Payload)
end

-- Handles SetModifierProperty_CL.
local function onSetModifierPropertyCL(Payload: { Id: string, ModifierKey: string, Key: string, Value: any, ValueType: string }): ()
	if not AppState.WorkspaceElements[Payload.Id] then return end
	
	local ModifierBag = AppState.WorkspaceElements[Payload.Id].Properties[Payload.ModifierKey]
	
	if not ModifierBag or type(ModifierBag) ~= "table" or not ModifierBag.IsModifier then return end

	local ValidatorFunc = TypeValidatorSwitch:Match(Payload.ValueType)
	local IsValid = ValidatorFunc and ValidatorFunc(Payload.Value) or false
	
	if not IsValid then
		if Payload.ValueType == "boolean" or Payload.ValueType == "Enum" then return end
		
		fireError("Modifier Property Update Failed. Invalid Value Format For " .. Payload.Key .. ".")
		
		return
	end

	local ModType: string = ModifierBag.Type or Payload.ModifierKey
	local ModDefs: { any }? = PropertyRegistry.GetModifierProperties(ModType)
	local PropDef: any? = nil

	if ModDefs then
		for _, def in ipairs(ModDefs) do
			if def.Name == Payload.Key then
				PropDef = def
				
				break
			end
		end
	end

	-- Numerical Clamping based on PropertyDefinition Min / Max
	if Payload.ValueType == "number" then
		if PropDef then
			if PropDef.Min ~= nil and Payload.Value < PropDef.Min then
				Payload.Value = PropDef.Min
			end
			
			if PropDef.Max ~= nil and Payload.Value > PropDef.Max then
				Payload.Value = PropDef.Max
			end
		end

		-- Special Relational Constraints for UITextSizeConstraint
		if ModType == "UITextSizeConstraint" then
			if Payload.Key == "MinTextSize" then
				local CurrentMax: number = ModifierBag.Properties.MaxTextSize or 100
				
				if Payload.Value > CurrentMax then
					fireError("Modifier Property Update Failed. MinTextSize Cannot Exceed MaxTextSize.")
					
					return
				end
				
			elseif Payload.Key == "MaxTextSize" then
				local CurrentMin: number = ModifierBag.Properties.MinTextSize or 1
				
				if Payload.Value < CurrentMin then
					fireError("Modifier Property Update Failed. MaxTextSize Cannot Be Less Than MinTextSize.")
					
					return
				end
			end
		end
		
	elseif Payload.ValueType == "UDim" then
		if (ModType == "UICorner" and Payload.Key == "CornerRadius") or ((ModType == "UIListLayout" or ModType == "UIPageLayout") and Payload.Key == "Padding") then
			local Scale = math.max(0, (Payload.Value :: UDim).Scale)
			local Offset = math.max(0, (Payload.Value :: UDim).Offset)
			
			Payload.Value = UDim.new(Scale, Offset)
		end
		
	elseif Payload.ValueType == "UDim2" then
		if (ModType == "UIGridLayout" and (Payload.Key == "CellSize" or Payload.Key == "CellPadding")) or (ModType == "UITableLayout" and Payload.Key == "Padding") then
			local Val = Payload.Value :: UDim2
			local ScaleX = math.max(0, Val.X.Scale)
			local OffsetX = math.max(0, Val.X.Offset)
			local ScaleY = math.max(0, Val.Y.Scale)
			local OffsetY = math.max(0, Val.Y.Offset)
			
			Payload.Value = UDim2.new(ScaleX, OffsetX, ScaleY, OffsetY)
		end
		
	elseif Payload.ValueType == "Vector2" then
		if ModType == "UISizeConstraint" then
			local Val = Payload.Value :: Vector2
			
			if Payload.Key == "MinSize" then
				local ClampedX = math.max(0, Val.X)
				local ClampedY = math.max(0, Val.Y)
				local CurrentMax: Vector2 = ModifierBag.Properties.MaxSize or Vector2.new(99999, 99999)
				
				if ClampedX > CurrentMax.X or ClampedY > CurrentMax.Y then
					fireError("Modifier Property Update Failed. MinSize Cannot Exceed MaxSize.")
					
					return
				end
				
				Payload.Value = Vector2.new(ClampedX, ClampedY)
				
			elseif Payload.Key == "MaxSize" then
				local CurrentMin: Vector2 = ModifierBag.Properties.MinSize or Vector2.zero
				local ClampedX = math.max(CurrentMin.X, math.max(0, Val.X))
				local ClampedY = math.max(CurrentMin.Y, math.max(0, Val.Y))
				
				Payload.Value = Vector2.new(ClampedX, ClampedY)
			end
			
		elseif ModType == "UIGradient" and Payload.Key == "Offset" then
			local ClampedX = Payload.Value.X
			local ClampedY = Payload.Value.Y
			
			if PropDef and PropDef.Min ~= nil then
				ClampedX = math.max(PropDef.Min, ClampedX)
				ClampedY = math.max(PropDef.Min, ClampedY)
			end
			
			if PropDef and PropDef.Max ~= nil then
				ClampedX = math.min(PropDef.Max, ClampedX)
				ClampedY = math.min(PropDef.Max, ClampedY)
			end
			
			Payload.Value = Vector2.new(ClampedX, ClampedY)
		end
	end

	if ASSET_PROPERTY_KEYS[Payload.Key] and type(Payload.Value) == "string" then
		Payload.Value = sanitizeAssetString(Payload.Value)
	end
	
	Relay.Create("SetModifierProperty"):Fire({
		Id = Payload.Id,
		ModifierKey = Payload.ModifierKey,
		Key = Payload.Key,
		Value = Payload.Value,
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Linter Event Binding Section
----------------------------------------------------------
Relay.Create("TogglePropertiesEditor_CL"):Connect(onTogglePropertiesEditorCL)
Relay.Create("SetElementName_CL"):Connect(onSetElementNameCL)
Relay.Create("SetElementPosition_CL"):Connect(onSetElementPositionCL)
Relay.Create("SetElementSize_CL"):Connect(onSetElementSizeCL)
Relay.Create("SetElementRotation_CL"):Connect(onSetElementRotationCL)
Relay.Create("SetElementVisible_CL"):Connect(onSetElementVisibleCL)
Relay.Create("SetElementProperty_CL"):Connect(onSetElementPropertyCL)
Relay.Create("AddModifier_CL"):Connect(onAddModifierCL)
Relay.Create("RemoveModifier_CL"):Connect(onRemoveModifierCL)
Relay.Create("SetModifierProperty_CL"):Connect(onSetModifierPropertyCL)

TypeValidatorSwitch
	:Case("number"):Execute(validateNumber)
	:Case("string"):Execute(validateString)
	:Case("boolean"):Execute(validateBoolean)
	:Case("Color3"):Execute(validateColor3)
	:Case("UDim2"):Execute(validateUDim2)
	:Case("Vector2"):Execute(validateVector2)
	:Case("Vector3"):Execute(validateVector3)
	:Case("UDim"):Execute(validateUDim)
	:Case("Enum"):Execute(validateEnum)
	:Case("ColorSequence"):Execute(validateColorSequence)
	:Case("NumberSequence"):Execute(validateNumberSequence)