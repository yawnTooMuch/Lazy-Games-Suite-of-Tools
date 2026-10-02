--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: PropertyRow_Component.luau
    
    SCOPE: Feature UI Component
    
    ROLE: Renders a single property editing row tailored to its ValueType.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRow_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	Label: string,
	Description: string?,
	ValueType: string,
	CurrentValue: any,
	EnumType: string?,
	EnumOptions: { string }?,
	LayoutOrder: number,
	LabelWidth: any,
	IsModifier: boolean?,
	OnSubmit: (NewValue: any) -> (),
	OnPreview: ((PreviewValue: any) -> ())?,
	OnCommit: ((FinalValue: any, InitialValue: any) -> ())?,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRow_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local Assignment = require(script.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)
local Color3Editor_Component = require(script.Parent.Dependencies.Color3Editor_Component)
local UIGradientColorSequenceEditor_Component = require(script.Parent.Dependencies.UIGradientColorSequenceEditor_Component)
local UIGradientNumberSequenceEditor_Component = require(script.Parent.Dependencies.UIGradientNumberSequenceEditor_Component)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRow_Component Internal States Section
----------------------------------------------------------
local EditorSwitch = Assignment.Switch("PropertyRow_EditorRouter")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRow_Component Local Functions Section
----------------------------------------------------------

-- Helper to determine input field background color (lighter for standard properties, darker for modifier cards)
local function getFieldBackgroundColor(Props: Props): Color3
	if Props.IsModifier then
		return Color3.fromRGB(30, 30, 30)
		
	else
		return Color3.fromRGB(45, 45, 45)
	end
end

-- Renders a boolean toggle
local function renderBooleanEditor(Props: Props): any
	local FieldBg = if Props.IsModifier then Color3.fromRGB(30, 30, 30) else Color3.fromRGB(60, 60, 60)
	
	return React.createElement("TextButton", {
		Size = UDim2.fromOffset(20, 20),
		Position = UDim2.new(1, 0, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = Props.CurrentValue and Color3.fromRGB(0, 160, 255) or FieldBg,
		Text = Props.CurrentValue and "✓" or "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		
		[React.Event.Activated] = function(): ()
			Props.OnSubmit(not Props.CurrentValue)
		end,
	}, {
		Corner = React.createElement("UICorner", { 
			CornerRadius = UDim.new(0, 4) 
		}),
	})
end

-- Renders a text input field
local function renderTextEditor(Props: Props): any
	return React.createElement("TextBox", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = getFieldBackgroundColor(Props),
		Text = Props.CurrentValue ~= nil and tostring(Props.CurrentValue) or "",
		TextColor3 = Color3.fromRGB(220, 220, 220),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		ClearTextOnFocus = false,
		ClipsDescendants = true,
		
		[React.Event.FocusLost] = function(Rbx: Instance, EnterPressed: boolean): ()
			if Props.ValueType == "number" then
				local TextValue = (Rbx :: TextBox).Text
				local Num = tonumber(TextValue)
				
				;(Rbx :: TextBox).Text = Props.CurrentValue ~= nil and tostring(Props.CurrentValue) or ""
				
				if Num then
					Props.OnSubmit(Num)
					
				else
					Props.OnSubmit(TextValue)
				end
				
			else
				Props.OnSubmit((Rbx :: TextBox).Text)
			end
		end,
	}, {
		Padding = React.createElement("UIPadding", { 
			PaddingLeft = UDim.new(0, 6)
		}),
		
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 4)
		}),
	})
end

-- Renders a Color3 input field
local function renderColor3Editor(Props: Props): any
	return React.createElement(Color3Editor_Component, {
		CurrentValue = Props.CurrentValue,
		IsModifier = Props.IsModifier,
		OnSubmit = Props.OnSubmit,
		OnPreview = Props.OnPreview,
		OnCommit = Props.OnCommit,
	})
end

-- Renders a UDim2 input field
local function renderUDim2Editor(Props: Props): any
	local Val: UDim2 = Props.CurrentValue or UDim2.new(0, 0, 0, 0)
	local FieldBg = getFieldBackgroundColor(Props)
	
	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
		
		XScale = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_X Scale",
			LayoutOrder = 1,
			Size = UDim2.new(0.25, -3, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold, 
			TextSize = 12, 
			Text = tostring(math.round(Val.X.Scale * 1000)/1000),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.X.Scale * 1000) / 1000) 
				
				if Num then
					Props.OnSubmit(UDim2.new(Num, Val.X.Offset, Val.Y.Scale, Val.Y.Offset)) 
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
		
		XOffset = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_X Offset",
			LayoutOrder = 2,
			Size = UDim2.new(0.25, -3, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1), 
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold, 
			TextSize = 12, 
			Text = tostring(Val.X.Offset),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(Val.X.Offset) 
				
				if Num then
					Props.OnSubmit(UDim2.new(Val.X.Scale, math.round(Num), Val.Y.Scale, Val.Y.Offset)) 
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
		
		YScale = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_Y Scale",
			LayoutOrder = 3,
			Size = UDim2.new(0.25, -3, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1), 
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold, 
			TextSize = 12,
			Text = tostring(math.round(Val.Y.Scale * 1000)/1000),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.Y.Scale * 1000) / 1000)
				
				if Num then
					Props.OnSubmit(UDim2.new(Val.X.Scale, Val.X.Offset, Num, Val.Y.Offset)) 
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
		
		YOffset = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_Y Offset",
			LayoutOrder = 4,
			Size = UDim2.new(0.25, -3, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FieldBg, 
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center, 
			Font = Enum.Font.GothamBold,
			TextSize = 12, 
			Text = tostring(Val.Y.Offset),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(Val.Y.Offset) 
				
				if Num then
					Props.OnSubmit(UDim2.new(Val.X.Scale, Val.X.Offset, Val.Y.Scale, math.round(Num)))
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
	})
end

-- Renders a UDim input field
local function renderUDimEditor(Props: Props): any
	local Val: UDim = Props.CurrentValue or UDim.new(0, 0)
	local FieldBg = getFieldBackgroundColor(Props)
	
	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", { 
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4)
		}),
		
		Scale = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_Scale",
			LayoutOrder = 1,
			Size = UDim2.new(0.5, -2, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1), 
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center, 
			Font = Enum.Font.GothamBold, 
			TextSize = 12, 
			Text = tostring(math.round(Val.Scale * 1000)/1000),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.Scale * 1000) / 1000) 
				
				if Num then 
					Props.OnSubmit(UDim.new(Num, Val.Offset))
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
		
		Offset = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_Offset",
			LayoutOrder = 2,
			Size = UDim2.new(0.5, -2, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1), 
			BackgroundColor3 = FieldBg, 
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center, 
			Font = Enum.Font.GothamBold, 
			TextSize = 12, 
			Text = tostring(Val.Offset),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(Val.Offset)
				
				if Num then 
					Props.OnSubmit(UDim.new(Val.Scale, math.round(Num))) 
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
	})
end

-- Renders a Vector2 input field
local function renderVector2Editor(Props: Props): any
	local Val: Vector2 = Props.CurrentValue or Vector2.new(0, 0)
	local FieldBg = getFieldBackgroundColor(Props)
	
	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4)
		}),
		
		X = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_X",
			LayoutOrder = 1,
			Size = UDim2.new(0.5, -2, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold,
			TextSize = 12, 
			Text = tostring(math.round(Val.X * 1000)/1000), 
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.Focused] = (function(): ()
				if Props.Label == "AnchorPoint" then
					Relay.Create("SetAnchorPointVisualVisible"):Fire(true)
				end
			end :: any),
			
			[React.Event.FocusLost] = (function(Rbx: Instance): ()
				if Props.Label == "AnchorPoint" then
					Relay.Create("SetAnchorPointVisualVisible"):Fire(false)
				end
				
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.X * 1000) / 1000) 
				
				if Num then
					Props.OnSubmit(Vector2.new(Num, Val.Y))
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end :: any),
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
		
		Y = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_Y",
			LayoutOrder = 2,
			Size = UDim2.new(0.5, -2, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold, 
			TextSize = 12, 
			Text = tostring(math.round(Val.Y * 1000)/1000),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.Focused] = (function(): ()
				if Props.Label == "AnchorPoint" then
					Relay.Create("SetAnchorPointVisualVisible"):Fire(true)
				end
			end :: any),
			
			[React.Event.FocusLost] = (function(Rbx: Instance): ()
				if Props.Label == "AnchorPoint" then
					Relay.Create("SetAnchorPointVisualVisible"):Fire(false)
				end
				
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.Y * 1000) / 1000) 
				
				if Num then 
					Props.OnSubmit(Vector2.new(Val.X, Num))
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end :: any),
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
	})
end

-- Renders a Vector3 input field
local function renderVector3Editor(Props: Props): any
	local Val: Vector3 = Props.CurrentValue or Vector3.new(0, 0, 0)
	local FieldBg = getFieldBackgroundColor(Props)
	
	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4)
		}),
		
		X = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_X",
			LayoutOrder = 1,
			Size = UDim2.new(0.333, -2, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold,
			TextSize = 12, 
			Text = tostring(math.round(Val.X * 1000)/1000), 
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.X * 1000) / 1000) 
				
				if Num then
					Props.OnSubmit(Vector3.new(Num, Val.Y, Val.Z))
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
		
		Y = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_Y",
			LayoutOrder = 2,
			Size = UDim2.new(0.334, -4, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold, 
			TextSize = 12, 
			Text = tostring(math.round(Val.Y * 1000)/1000),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.Y * 1000) / 1000) 
				
				if Num then 
					Props.OnSubmit(Vector3.new(Val.X, Num, Val.Z))
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
		
		Z = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = Props.Label .. "_Z",
			LayoutOrder = 3,
			Size = UDim2.new(0.333, -2, 1, 0),
		}, {
			Input = React.createElement("TextBox", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = FieldBg,
			TextColor3 = Color3.new(1,1,1),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold, 
			TextSize = 12, 
			Text = tostring(math.round(Val.Z * 1000)/1000),
			ClearTextOnFocus = false,
			ClipsDescendants = true,
			
			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)

				;(Rbx :: TextBox).Text = tostring(math.round(Val.Z * 1000) / 1000) 
				
				if Num then 
					Props.OnSubmit(Vector3.new(Val.X, Val.Y, Num))
					
				else
					Props.OnSubmit((Rbx :: TextBox).Text)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4)
			})
		})
		}),
	})
end

-- Renders an Enum input field
local function renderEnumEditor(Props: Props): any
	local FieldBg = getFieldBackgroundColor(Props)
	
	if Props.EnumOptions then
		return React.createElement(UI_ComponentSDK.Dropdown, {
			Options = Props.EnumOptions,
			SelectedOption = Props.CurrentValue and Props.CurrentValue.Name or "",
			Size = UDim2.new(1, 0, 1, -4),
			Position = UDim2.new(0, 0, 0, 2),
			BackgroundColor3 = FieldBg,
			FontPreview = Props.EnumType == "Font",
			
			OnSelect = function(OptionName: string): ()
				if Props.EnumType then
					if Enum[Props.EnumType] then
						for _, EnumItem in ipairs(Enum[Props.EnumType]:GetEnumItems()) do
							if EnumItem.Name == OptionName then
								Props.OnSubmit(EnumItem)
								
								return
							end
						end
					end
				end
			end,
		})
	end
	
	-- Fallback to old text-box for missing enum definitions
	return React.createElement("TextBox", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = FieldBg,
		Text = Props.CurrentValue and Props.CurrentValue.Name or "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextXAlignment = Enum.TextXAlignment.Center,
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		ClearTextOnFocus = true,
		ClipsDescendants = true,
		PlaceholderText = "Type enum name...",
		
		[React.Event.FocusLost] = function(Rbx: Instance, EnterPressed: boolean): ()
			if Props.EnumType then
				if Enum[Props.EnumType] then
					for _, EnumItem in ipairs(Enum[Props.EnumType]:GetEnumItems()) do
						if string.lower(EnumItem.Name) == string.lower((Rbx :: TextBox).Text) then
							Props.OnSubmit(EnumItem)
							
							return
						end
					end
				end
			end
			
			(Rbx :: TextBox).Text = Props.CurrentValue and Props.CurrentValue.Name or ""
		end,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 4) 
		}),
	})
end

-- Renders a ColorSequence input field
local function renderColorSequenceEditor(Props: Props): any
	return React.createElement(UIGradientColorSequenceEditor_Component, {
		CurrentValue = Props.CurrentValue,
		OnSubmit = Props.OnSubmit,
		OnPreview = Props.OnPreview,
		OnCommit = Props.OnCommit,
	})
end

-- Renders a NumberSequence input field
local function renderNumberSequenceEditor(Props: Props): any
	return React.createElement(UIGradientNumberSequenceEditor_Component, {
		CurrentValue = Props.CurrentValue,
		OnSubmit = Props.OnSubmit,
		OnPreview = Props.OnPreview,
		OnCommit = Props.OnCommit,
	})
end

--[[
Renders the appropriate editor based on the property's ValueType.

Params:
    Props: Props -- Component props
    RouterFunc: any -- The router function for the ValueType

Returns:
    any -- The editor React component
]]
local function renderEditor(Props: Props, RouterFunc: any): any
	if RouterFunc then
		return RouterFunc(Props)
	end
	
	-- Fallback empty
	return React.createElement("Frame", { 
		Size = UDim2.fromScale(1, 1), 
		BackgroundTransparency = 1 
	})
end


-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRow_Component Public APIs Section
----------------------------------------------------------

--[[
Renders a single property row.

Params:
    Props: Props -- Component props

Returns:
    any -- The property row React component
]]
local function PropertyRow_Component(Props: Props): any
	local RouterFunc = EditorSwitch:Match(Props.ValueType)
	local TooltipText = if Props.Description and Props.Description ~= "" then Props.Label .. ":\n\n" .. Props.Description else Props.Label

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = Props.LayoutOrder,
	}, {
		Label = React.createElement(UI_ComponentSDK.TooltipWrap, {
			Text = TooltipText,
			TooltipSize = UDim2.fromOffset(200, 0),
			
			Size = Props.LabelWidth:map(function(w: number): UDim2
				return UDim2.new(0, w - 3, 1, 0)
			end),
			
			ZIndex = 10,
		}, {
			TextLabel = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = Props.Label,
				TextColor3 = Color3.fromRGB(180, 180, 180),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Font = Enum.Font.Gotham,
				TextSize = 11,
			})
		}),
		
		EditorContainer = React.createElement("Frame", {
			Size = Props.LabelWidth:map(function(w: number): UDim2
				return UDim2.new(1, -(w + 3), 1, 0) 
			end),
			
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			Editor = renderEditor(Props, RouterFunc),
		})
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRow_Component Event Binding Section
----------------------------------------------------------
EditorSwitch
	:Case("boolean"):Execute(renderBooleanEditor)
	:Case("number"):Execute(renderTextEditor)
	:Case("string"):Execute(renderTextEditor)
	:Case("Color3"):Execute(renderColor3Editor)
	:Case("UDim2"):Execute(renderUDim2Editor)
	:Case("UDim"):Execute(renderUDimEditor)
	:Case("Vector2"):Execute(renderVector2Editor)
	:Case("Vector3"):Execute(renderVector3Editor)
	:Case("Enum"):Execute(renderEnumEditor)
	:Case("ColorSequence"):Execute(renderColorSequenceEditor)
	:Case("NumberSequence"):Execute(renderNumberSequenceEditor)

----------------------------------------------------------
return PropertyRow_Component
----------------------------------------------------------