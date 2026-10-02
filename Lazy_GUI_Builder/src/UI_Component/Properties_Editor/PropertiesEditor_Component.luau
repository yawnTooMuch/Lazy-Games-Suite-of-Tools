--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: PropertiesEditor_Component.luau
    
    SCOPE: Feature UI Component
    
    ROLE: Renders the Properties Editor docked widget, reading from AppState
          and delegating rendering of individual properties to PropertyRow.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.Parent.AppState)
local PropertyRegistry = require(script.Parent.Parent.Parent.PropertyRegistry)
local PropertyRow_Component = require(script.Parent.PropertyRow_Component)
local PositionDial_Component = require(script.Parent.Dependencies.PositionDial_Component)
local SizeDial_Component = require(script.Parent.Dependencies.SizeDial_Component)
local RotationDial_Component = require(script.Parent.Dependencies.RotationDial_Component)
local Assignment = require(script.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Component Internal States Section
----------------------------------------------------------
local PropertySubmitSwitch = Assignment.Switch("PropertiesEditor_SubmitRouter")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Component Local Functions Section
----------------------------------------------------------

-- One-line summary
local function handleSubmitName(Id: string, Value: any, _PropDef: any): ()
	Relay.Create("SetElementName_CL"):Fire({
		Id = Id,
		Name = Value 
	})
end

-- One-line summary
local function handleSubmitPosition(Id: string, Value: any, _PropDef: any): ()
	Relay.Create("SetElementPosition_CL"):Fire({
		Id = Id, 
		Position = Value 
	})
end

-- One-line summary
local function handleSubmitSize(Id: string, Value: any, _PropDef: any): ()
	Relay.Create("SetElementSize_CL"):Fire({
		Id = Id,
		Size = Value 
	})
end

-- One-line summary
local function handleSubmitRotation(Id: string, Value: any, _PropDef: any): ()
	Relay.Create("SetElementRotation_CL"):Fire({
		Id = Id,
		Rotation = Value 
	})
end

-- One-line summary
local function handleSubmitVisible(Id: string, Value: any, _PropDef: any): ()
	Relay.Create("SetElementVisible_CL"):Fire({ 
		Id = Id, 
		Visible = Value 
	})
end

-- One-line summary
local function handleSubmitDefault(Id: string, Value: any, PropDef: any): ()
	Relay.Create("SetElementProperty_CL"):Fire({
		Id = Id, 
		Key = PropDef.Name, 
		Value = Value, 
		ValueType = PropDef.ValueType
	})
end


-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the properties editor window.

Params:
    None

Returns:
    any -- The properties editor React component
]]
local function PropertiesEditor_Component(): any
	local UpdateTick: number, SetUpdateTick = React.useState(0)
	local SelectedId: string? = AppState.SelectedElementId
	local SelectedElement: AppState.UIElement? = SelectedId and AppState.WorkspaceElements[SelectedId] or nil

	-- Splitter Drag State
	local LabelWidth: any, SetLabelWidth: any = React.useBinding(110)
	local IsResizing: boolean, SetIsResizing = React.useState(false)
	local ResizeStartX: number, SetResizeStartX = React.useState(0)
	local ResizeStartWidth: number, SetResizeStartWidth = React.useState(0)
	
	React.useEffect(function(): (() -> ())?
		Relay.Create("WorkspaceElementsUpdated"):Connect(function(): ()
			SetUpdateTick(function(Prev: number): number
				return Prev + 1 
			end)
		end)
		
		Relay.Create("ElementSelected"):Connect(function(): ()
			SetUpdateTick(function(Prev: number): number 
				return Prev + 1 
			end)
		end)
		
		return nil
	end, {})

	if not SelectedElement then
		return React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(30, 30, 30),
			BorderSizePixel = 0,
		}, {
			Msg = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "No Element Selected.",
				TextColor3 = Color3.fromRGB(150, 150, 150),
				Font = Enum.Font.Gotham,
				TextSize = 14,
			})
		})
	end

	-- Build Categories
	local Categories: { [string]: { PropertyRegistry.PropertyDefinition } } = {}
	local CategoryOrder: { string } = { "Identity", "Transform", "Appearance", "Text", "Image", "Scrolling", "Video", "Viewport", "Behavior" }
	local PropDefs = PropertyRegistry.GetPropertiesForType(SelectedElement.Type)
	local RenderedCategories: { [string]: any } = {}
	local LayoutOrder = 1
	
	for _, PropDef in ipairs(PropDefs) do
		if not Categories[PropDef.Category] then
			Categories[PropDef.Category] = {}
		end
		
		Categories[PropDef.Category][#Categories[PropDef.Category] + 1] = PropDef
	end
	
	RenderedCategories["Layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	})
	
	RenderedCategories["Padding"] = React.createElement("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 20),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	})
	
	local StandardCategories: { [string]: any } = {}
	local StandardLayoutOrder = 1
	
	StandardCategories["Layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 10),
	})
	
	for _, CatName in ipairs(CategoryOrder) do
		local CatProps = Categories[CatName]
		
		if CatProps and #CatProps > 0 then
			local RowElements: { [string]: any } = {}
			local RowOrder = 1
			
			RowElements["Layout"] = React.createElement("UIListLayout", { 
				SortOrder = Enum.SortOrder.LayoutOrder,
			})
			
			for _, PropDef in ipairs(CatProps) do
				local CurrentValue = SelectedElement.Properties[PropDef.Name]
				
				if PropDef.Name == "Name" then
					CurrentValue = SelectedElement.Name
				end
				
				if PropDef.Name == "Position" then 
					CurrentValue = SelectedElement.Position 
				end
				
				if PropDef.Name == "Size" then
					CurrentValue = SelectedElement.Size
				end
				
				if PropDef.Name == "Visible" then 
					CurrentValue = SelectedElement.Visible 
				end
				
				if CurrentValue == nil then
					CurrentValue = PropDef.Default
				end
				
				RowElements[PropDef.Name] = React.createElement(PropertyRow_Component, {
					Label = PropDef.Name,
					Description = PropDef.Description,
					ValueType = PropDef.ValueType,
					CurrentValue = CurrentValue,
					EnumType = PropDef.EnumType,
					EnumOptions = PropDef.EnumOptions,
					LayoutOrder = RowOrder,
					LabelWidth = LabelWidth,
					
					OnPreview = if PropDef.ValueType == "Color3" then -- True
						function(PreviewValue: any): ()
							Relay.Create("PreviewElementProperty"):Fire({
								Id = SelectedElement.Id,
								Key = PropDef.Name,
								Value = PreviewValue,
							})
						end
						
					else -- False
						nil,

					OnCommit = if PropDef.ValueType == "Color3" then -- True
						function(FinalValue: any, InitialValue: any): ()
							Relay.Create("CommitPreviewedProperty"):Fire({
								Id = SelectedElement.Id,
								Key = PropDef.Name,
								FinalValue = FinalValue,
								InitialValue = InitialValue,
							})
						end
						
					else -- False
						nil,
					
					OnSubmit = function(NewValue: any): ()
						local RouterFunc = PropertySubmitSwitch:Match(PropDef.Name)
						
						if RouterFunc then
							RouterFunc(SelectedElement.Id, NewValue, PropDef)
						end
					end,
				})
				
				RowOrder += 1
				
				if PropDef.Name == "Position" then
					RowElements["PositionDial"] = React.createElement(PositionDial_Component, {
						CurrentPosition = CurrentValue,
						LayoutOrder = RowOrder,
						LabelWidth = LabelWidth,
						
						OnPositionChange = function(NewPosition: UDim2): ()
							Relay.Create("SetElementPosition"):Fire({
								Id = SelectedElement.Id,
								Position = NewPosition,
								FromDial = true,
							})
						end,
					})
					
					RowOrder += 1
				end

				if PropDef.Name == "Size" then
					RowElements["SizeDial"] = React.createElement(SizeDial_Component, {
						CurrentSize = CurrentValue,
						LayoutOrder = RowOrder,
						LabelWidth = LabelWidth,
						
						OnSizeChange = function(NewSize: UDim2): ()
							Relay.Create("SetElementSize"):Fire({
								Id = SelectedElement.Id,
								Size = NewSize,
								FromDial = true,
							})
						end,
					})
					
					RowOrder += 1
				end

				if PropDef.Name == "Rotation" then
					RowElements["RotationDial"] = React.createElement(RotationDial_Component, {
						CurrentRotation = CurrentValue,
						LayoutOrder = RowOrder,
						LabelWidth = LabelWidth,
						
						OnRotationChange = function(NewRotation: number): ()
							Relay.Create("SetElementRotation"):Fire({
								Id = SelectedElement.Id,
								Rotation = NewRotation,
								FromDial = true,
							})
						end,
					})
					
					RowOrder += 1
				end
			end
			
			StandardCategories["Cat_" .. CatName] = React.createElement(UI_ComponentSDK.PropertiesCategory, {
				Title = CatName,
				LayoutOrder = StandardLayoutOrder,
			}, RowElements)
			
			StandardLayoutOrder += 1
		end
	end
	
	RenderedCategories["Cat_StandardWrapper"] = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = LayoutOrder,
	}, {
		List = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, StandardCategories),
		
		Line = React.createElement("Frame", {
			Size = UDim2.new(0, 1, 1, 0),
			
			Position = LabelWidth:map(function(w: number): UDim2
				return UDim2.new(0, w, 0, 0)
			end),
			
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = IsResizing and Color3.fromRGB(90, 110, 255) or Color3.fromRGB(150, 150, 150),
			BackgroundTransparency = IsResizing and 0 or 0.5,
			BorderSizePixel = 0,
			ZIndex = 50,
		}),
		
		SplitterHandle = React.createElement("TextButton", {
			Size = UDim2.new(0, 8, 1, 0),
			
			Position = LabelWidth:map(function(w: number): UDim2 
				return UDim2.new(0, w, 0, 0) 
			end),
			
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 100,
			
			[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					SetIsResizing(true)
					SetResizeStartX(Input.Position.X)
					SetResizeStartWidth(LabelWidth:getValue())
				end
			end,
		}),
	})
	
	LayoutOrder += 1
	
	local ModifierElements: { [string]: any } = {}
	local ModOrder = 1
	
	ModifierElements["Layout"] = React.createElement("UIListLayout", { 
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4) 
	})
	
	-- Count instances per modifier type for numbering (e.g. "UIStroke (1)", "UIStroke (2)")
	local TypeInstanceTotals: { [string]: number } = {}
	
	for _, ModBag in SelectedElement.Properties do
		if type(ModBag) == "table" and ModBag.IsModifier then
			local RawType: string = ModBag.Type or "Modifier"
			local ModType: string = string.match(RawType, "^([%a%d]+)_") or RawType
			
			TypeInstanceTotals[ModType] = (TypeInstanceTotals[ModType] or 0) + 1
		end
	end

	local TypeInstanceCurrent: { [string]: number } = {}

	for Key, ModBag in SelectedElement.Properties do
		if type(ModBag) == "table" and ModBag.IsModifier then
			local RawType: string = ModBag.Type or Key
			local ModType: string = string.match(RawType, "^([%a%d]+)_") or RawType
			local ModDefs = PropertyRegistry.GetModifierProperties(ModType)
			
			if ModDefs then
				TypeInstanceCurrent[ModType] = (TypeInstanceCurrent[ModType] or 0) + 1
				
				local DisplayName = if (TypeInstanceTotals[ModType] or 0) > 1 then string.format("%s (%d)", ModType, TypeInstanceCurrent[ModType]) else ModType
				local ModRows: { [string]: any } = {}
				local SubRowOrder = 1
				
				ModRows["Layout"] = React.createElement("UIListLayout", { 
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 2)
				})
				
				for _, ModPropDef in ipairs(ModDefs) do
					ModRows[ModPropDef.Name] = React.createElement(PropertyRow_Component, {
						Label = ModPropDef.Name,
						Description = ModPropDef.Description,
						ValueType = ModPropDef.ValueType,
						CurrentValue = ModBag.Properties[ModPropDef.Name],
						EnumType = ModPropDef.EnumType,
						EnumOptions = ModPropDef.EnumOptions,
						LayoutOrder = SubRowOrder,
						LabelWidth = LabelWidth,
						IsModifier = true,
						
						OnPreview = if ModPropDef.ValueType == "Color3" or ModPropDef.ValueType == "ColorSequence" or ModPropDef.ValueType == "NumberSequence" then -- True
							function(PreviewValue: any): ()
								Relay.Create("PreviewModifierProperty"):Fire({
									Id = SelectedElement.Id,
									ModifierKey = Key,
									Key = ModPropDef.Name,
									Value = PreviewValue,
								})
							end
						else -- False
							nil,

						OnCommit = if ModPropDef.ValueType == "Color3" or ModPropDef.ValueType == "ColorSequence" or ModPropDef.ValueType == "NumberSequence" then -- True
							function(FinalValue: any, InitialValue: any): ()
								Relay.Create("CommitPreviewedModifierProperty"):Fire({
									Id = SelectedElement.Id,
									ModifierKey = Key,
									Key = ModPropDef.Name,
									FinalValue = FinalValue,
									InitialValue = InitialValue,
								})
							end
						else -- False
							nil,

						OnSubmit = function(NewValue: any): ()
							Relay.Create("SetModifierProperty_CL"):Fire({ 
								Id = SelectedElement.Id,
								ModifierKey = Key,
								Key = ModPropDef.Name, 
								Value = NewValue,
								ValueType = ModPropDef.ValueType
							})
						end,
					})
					
					SubRowOrder += 1
				end
				
				ModifierElements["Mod_" .. Key] = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
					BackgroundColor3 = Color3.fromRGB(45, 45, 45),
					LayoutOrder = ModOrder,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4)
					}),
					
					Padding = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0,4), 
						PaddingBottom = UDim.new(0,4), 
						PaddingLeft = UDim.new(0,4),
						PaddingRight = UDim.new(0,4) 
					}),
					
					Header = React.createElement("Frame", {
						Size = UDim2.new(1, 0, 0, 20),
						BackgroundTransparency = 1,
					}, {
						Title = React.createElement("TextLabel", {
							Size = UDim2.new(1, -30, 1, 0),
							BackgroundTransparency = 1,
							Text = " ■ " .. DisplayName,
							TextColor3 = Color3.fromRGB(150, 200, 255),
							TextXAlignment = Enum.TextXAlignment.Left,
							Font = Enum.Font.GothamBold,
							TextSize = 14,
						}),
						
						Trash = React.createElement("TextButton", {
							Size = UDim2.fromOffset(20, 20),
							Position = UDim2.new(1, 0, 0, 0),
							AnchorPoint = Vector2.new(1, 0),
							BackgroundColor3 = Color3.fromRGB(180, 50, 50),
							Text = "X",
							TextColor3 = Color3.fromRGB(255, 255, 255),
							TextXAlignment = Enum.TextXAlignment.Center,
							TextYAlignment = Enum.TextYAlignment.Center,
							Font = Enum.Font.GothamBold,
							TextSize = 14,
							
							[React.Event.Activated] = function(): ()
								Relay.Create("RemoveModifier_CL"):Fire({
									Id = SelectedElement.Id,
									ModifierKey = Key,
								})
							end,
							
						}, {
							Corner = React.createElement("UICorner", { 
								CornerRadius = UDim.new(0, 4)
							}),
							
							UIPadding = React.createElement("UIPadding", {
								PaddingRight = UDim.new(0.1, 0),
							})
						})
					}),
					
					Content = React.createElement("Frame", {
						Size = UDim2.new(1, 0, 0, 0),
						Position = UDim2.fromOffset(0, 24),
						AutomaticSize = Enum.AutomaticSize.Y,
						BackgroundTransparency = 1,
					}, ModRows),
				})
				
				ModOrder += 1
			end
		end
	end
	
	RenderedCategories["Cat_Modifiers_Divider"] = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 4),
		BackgroundTransparency = 1,
		LayoutOrder = LayoutOrder,
	}, {
		Line1 = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.fromRGB(80, 80, 80),
			BorderSizePixel = 0,
		}),
		
		Line2 = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 1),
			Position = UDim2.fromOffset(0, 3),
			BackgroundColor3 = Color3.fromRGB(80, 80, 80),
			BorderSizePixel = 0,
		})
	})
	
	-- Filter compatible and unattached modifiers for the Add Modifier dropdown
	local AvailableOptions: { string } = {}

	for _, ModName: string in ipairs(PropertyRegistry.GetCompatibleModifiersForType(SelectedElement.Type)) do
		local AllowsMultiple: boolean = PropertyRegistry.AllowsMultipleInstances(ModName)
		local AlreadyAttached = false
		local InstanceCount = 0

		for Key: string, ModBag: any in SelectedElement.Properties do
			local ModType: string = (type(ModBag) == "table" and ModBag.Type) or Key
			
			if type(ModBag) == "table" and ModBag.IsModifier and ModType == ModName then
				AlreadyAttached = true
				InstanceCount += 1
			end
		end

		local HasConflict: boolean = PropertyRegistry.GetConflictingModifier(ModName, SelectedElement.Properties) ~= nil
		local UnderInstanceCap: boolean = not AllowsMultiple or InstanceCount < 5

		if (AllowsMultiple or not AlreadyAttached) and not HasConflict and UnderInstanceCap then
			AvailableOptions[#AvailableOptions + 1] = ModName
		end
	end

	local ModifierChildren: { [string]: any } = {}
	
	ModifierChildren["Layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	})
	
	ModifierChildren["AddDropdown"] = if #AvailableOptions > 0 then
		React.createElement(UI_ComponentSDK.Dropdown, {
			Options = AvailableOptions,
			SelectedOption = "+ Add Modifier",
			Size = UDim2.new(1, 0, 0, 24),
			LayoutOrder = 1,
			ZIndex = 5,
			
			OnSelect = function(SelectedModifier: string): ()
				Relay.Create("AddModifier_CL"):Fire({
					Id = SelectedElement.Id,
					ModifierType = SelectedModifier,
				})
			end,
		})
		
	else
		React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = "No Additional Modifiers Available.",
			TextColor3 = Color3.fromRGB(130, 130, 130),
			Font = Enum.Font.Gotham,
			TextSize = 12,
			LayoutOrder = 1,
		})
	
	ModifierChildren["CardsContainer"] = React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = 2,
	}, ModifierElements)

	RenderedCategories["Cat_Modifiers"] = React.createElement(UI_ComponentSDK.PropertiesCategory, {
		Title = "Modifiers",
		TextColor3 = Color3.fromRGB(255, 180, 80),
		LayoutOrder = LayoutOrder,
	}, ModifierChildren)
	
	local Scroller = React.createElement("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, RenderedCategories)

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Scroller = Scroller,
		DragCapture = IsResizing and React.createElement("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 9999,
			
			[React.Event.InputChanged] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseMovement then
					local Delta = Input.Position.X - ResizeStartX
					
					SetLabelWidth(math.clamp(ResizeStartWidth + Delta, 80, 220))
				end
			end,
			
			[React.Event.InputEnded] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					SetIsResizing(false)
				end
			end,
		}) or nil,
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertiesEditor_Component Event Binding Section
----------------------------------------------------------
PropertySubmitSwitch
	:Case("Name"):Execute(handleSubmitName)
	:Case("Position"):Execute(handleSubmitPosition)
	:Case("Size"):Execute(handleSubmitSize)
	:Case("Rotation"):Execute(handleSubmitRotation)
	:Case("Visible"):Execute(handleSubmitVisible)
	:Default(handleSubmitDefault)

----------------------------------------------------------
return PropertiesEditor_Component
----------------------------------------------------------