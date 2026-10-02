--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Workspace_Component.luau
    
    SCOPE: Render Engine / Workspace Canvas UI Component
    
    ROLE: Renders the full-screen interactive canvas workspace, projecting
          AppState.WorkspaceElements into declarative ReactRoblox GuiObjects,
          handling drop placement, element selection flashing, anchor point
          visualizers, and dragging ghost previews.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Workspace_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	Visible: boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Workspace_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.AppState)
local Assignment = require(script.Parent.Parent.Parent.Extras.Assignment.Assignment)
local AnchorPointVisual_Component = require(script.Parent.Properties_Editor.Dependencies.AnchorPointVisual_Component)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Workspace_Component Imported Services Section
----------------------------------------------------------
local UserInputService: UserInputService = game:GetService("UserInputService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Workspace_Component Internal States Section
----------------------------------------------------------
local ModifierFlashingSwitch = Assignment.Switch("Workspace_ModifierFlashing")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Workspace_Component Local Functions Section
----------------------------------------------------------

--[[
Flashes a UIStroke modifier during selection highlighting by inverting transparency and disabling if active.

Params:
    ModProps: { [string]: any } -- The cloned modifier properties table to mutate
    ValueProps: { [string]: any } -- The original modifier properties table

Returns:
    () -- No return value
]]
local function flashUIStroke(ModProps: { [string]: any }, ValueProps: { [string]: any }): ()
	local OrigEnabled: boolean = ValueProps.Enabled ~= false
	local OrigTrans: number = ValueProps.Transparency or 0

	if OrigEnabled then
		ModProps.Enabled = false
	end

	ModProps.Transparency = if OrigTrans >= 1 then 0 else 1
end

--[[
Flashes a UIGradient modifier during selection highlighting by disabling if active.

Params:
    ModProps: { [string]: any } -- The cloned modifier properties table to mutate
    ValueProps: { [string]: any } -- The original modifier properties table

Returns:
    () -- No return value
]]
local function flashUIGradient(ModProps: { [string]: any }, ValueProps: { [string]: any }): ()
	local OrigEnabled: boolean = ValueProps.Enabled ~= false

	if OrigEnabled then
		ModProps.Enabled = false
	end
end

--[[
Fallback flasher for generic modifiers with Enabled, Visible, or Transparency properties.

Params:
    ModProps: { [string]: any } -- The cloned modifier properties table to mutate
    ValueProps: { [string]: any } -- The original modifier properties table

Returns:
    () -- No return value
]]
local function flashGenericModifier(ModProps: { [string]: any }, ValueProps: { [string]: any }): ()
	if ModProps.Enabled ~= nil and ValueProps.Enabled ~= false then
		ModProps.Enabled = false
		
	elseif ModProps.Visible ~= nil and ValueProps.Visible ~= false then
		ModProps.Visible = false
		
	elseif ModProps.Transparency ~= nil and type(ModProps.Transparency) == "number" then
		local OrigTrans: number = ValueProps.Transparency or 0

		ModProps.Transparency = if OrigTrans >= 1 then 0 else 1
	end
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Workspace_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the invisible full-screen workspace and the virtual DOM elements.

Params:
    ComponentProps: Props -- React props

Returns:
    any -- A React element
]]
local function Workspace_Component(ComponentProps: Props): any
	local UpdateTick: number, SetUpdateTick = React.useState(0)
	local IsDragging: boolean, SetIsDragging = React.useState(false)
	local ElementType: string?, SetElementType = React.useState(nil :: string?)
	local SelectedId: string?, SetSelectedId = React.useState(AppState.SelectedElementId)
	local FlashAlternate: boolean, SetFlashAlternate = React.useState(false)
	local IsAnchorPointVisualVisible: boolean, SetIsAnchorPointVisualVisible = React.useState(AppState.SessionState.IsAnchorPointVisualVisible)
	local MousePos: any, SetMousePos: any = React.useBinding(UDim2.fromOffset(0, 0))
	local Children: { [string]: any } = {}

	React.useEffect(function(): (() -> ())?
		local ActiveFlashHandle: any = nil

		Relay.Create("WorkspaceElementsUpdated"):Connect(function(): ()
			SetSelectedId(AppState.SelectedElementId)
			SetUpdateTick(function(Prev: number): number
				return Prev + 1
			end)
		end)
		
		Relay.Create("SessionStateUpdated"):Connect(function(): ()
			SetIsAnchorPointVisualVisible(AppState.SessionState.IsAnchorPointVisualVisible)
		end)

		Relay.Create("ElementSelected"):Connect(function(): ()
			SetSelectedId(AppState.SelectedElementId)
			SetFlashAlternate(false)

			if ActiveFlashHandle then
				Assignment.Cancel(ActiveFlashHandle)
				ActiveFlashHandle = nil
			end

			if not AppState.SelectedElementId then
				return
			end

			ActiveFlashHandle = Assignment.Repeat(10, 0.2, function(Iteration: number): ()
				SetFlashAlternate(function(Prev: boolean): boolean
					return not Prev
				end)

				if Iteration == 10 then
					SetFlashAlternate(false)
					ActiveFlashHandle = nil
				end
			end)
		end)

		return function(): ()
			if ActiveFlashHandle then
				Assignment.Cancel(ActiveFlashHandle)
			end
		end
	end, {})

	React.useEffect(function(): (() -> ())?
		Relay.Create("DragStateChanged"):Connect(function(): ()
			SetIsDragging(AppState.DragState.IsDragging)
			SetElementType(AppState.DragState.ElementType)
		end)

		return nil
	end, {})

	React.useEffect(function(): (() -> ())?
		if not IsDragging then
			return nil
		end

		local MoveConnection: RBXScriptConnection
		local EndConnection: RBXScriptConnection
		local InitialMouse: Vector2 = UserInputService:GetMouseLocation()

		local function onInputChanged(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				SetMousePos(UDim2.fromOffset(Input.Position.X, Input.Position.Y))
			end
		end

		local function onInputEnded(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				Relay.Create("DropElement_CL"):Fire(MousePos:getValue())
			end
		end

		MoveConnection = UserInputService.InputChanged:Connect(onInputChanged)
		EndConnection = UserInputService.InputEnded:Connect(onInputEnded)
		SetMousePos(UDim2.fromOffset(InitialMouse.X, InitialMouse.Y - 36))

		return function(): ()
			MoveConnection:Disconnect()
			EndConnection:Disconnect()
		end
	end, { IsDragging } :: { any })

	-- Recursively builds the React component tree for a virtual element and its children.
	local function buildElementTree(ElementId: string): any
		local ElementData: AppState.UIElement? = AppState.WorkspaceElements[ElementId]
		
		if not ElementData then return nil end
		
		if not ElementData.Visible then return nil end

		local ElementChildren: { [string]: any } = {}
		
		for _, ChildId: string in ipairs(ElementData.Children) do
			ElementChildren[ChildId] = buildElementTree(ChildId)
		end

		local IsSelected: boolean = ElementId == SelectedId

		local Props: { [string]: any } = {
			Position = ElementData.Position,
			Size = ElementData.Size,
			Visible = ElementData.Visible,
		}
		
		for Key: string, Value: any in ElementData.Properties do
			if type(Value) == "table" and Value.IsModifier then
				-- It's a modifier (e.g. UIPadding or UIStroke_UUID), render as a child instead of a property
				local RawType: string = Value.Type or Key
				local ClassName: string = string.match(RawType, "^([%a%d]+)_") or RawType
				local ModProps: { [string]: any } = table.clone(Value.Properties)

				-- Sanitize deprecated SortOrder.Custom to LayoutOrder
				if ModProps.SortOrder and (ModProps.SortOrder == "Custom" or (typeof(ModProps.SortOrder) == "EnumItem" and ModProps.SortOrder.Name == "Custom")) then
					ModProps.SortOrder = Enum.SortOrder.LayoutOrder
					Value.Properties.SortOrder = Enum.SortOrder.LayoutOrder
				end

				-- Sanitize deprecated UIDragDetectorDragStyle.Custom to TranslatePlane
				if ModProps.DragStyle and (ModProps.DragStyle == "Custom" or (typeof(ModProps.DragStyle) == "EnumItem" and ModProps.DragStyle.Name == "Custom")) then
					ModProps.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
					Value.Properties.DragStyle = Enum.UIDragDetectorDragStyle.TranslatePlane
				end

				if IsSelected and FlashAlternate then
					local FlashFunc = ModifierFlashingSwitch:Match(ClassName) :: (({ [string]: any }, { [string]: any }) -> ())?
					
					if FlashFunc then
						FlashFunc(ModProps, Value.Properties)
					end
				end
				
				ElementChildren[Key] = React.createElement(ClassName, ModProps)
				
			elseif Key ~= "Position" and Key ~= "Size" and Key ~= "Visible" and Key ~= "Name" then
				-- It's a standard property (e.g. BackgroundColor3)
				Props[Key] = Value
			end
		end

		if IsSelected and FlashAlternate then
			local OrigBgTrans: number = Props.BackgroundTransparency or 0
			
			Props.BackgroundTransparency = if OrigBgTrans >= 1 then 0 else 1

			if Props.TextTransparency ~= nil then
				local OrigTextTrans: number = Props.TextTransparency or 0
				
				Props.TextTransparency = if OrigTextTrans >= 1 then 0 else 1
			end

			if Props.TextStrokeTransparency ~= nil then
				local OrigStrokeTrans: number = Props.TextStrokeTransparency or 0
				
				Props.TextStrokeTransparency = if OrigStrokeTrans >= 1 then 0 else 1
			end

			if Props.ImageTransparency ~= nil then
				local OrigImageTrans: number = Props.ImageTransparency or 0
				
				Props.ImageTransparency = if OrigImageTrans >= 1 then 0 else 1
			end

			if Props.ScrollBarImageTransparency ~= nil then
				local OrigScrollTrans: number = Props.ScrollBarImageTransparency or 0
				
				Props.ScrollBarImageTransparency = if OrigScrollTrans >= 1 then 0 else 1
			end

			if Props.GroupTransparency ~= nil then
				local OrigGroupTrans: number = Props.GroupTransparency or 0
				
				Props.GroupTransparency = if OrigGroupTrans >= 1 then 0 else 1
			end
		end
		
		if IsSelected and IsAnchorPointVisualVisible then
			ElementChildren["AnchorPointVisual"] = React.createElement(AnchorPointVisual_Component, {
				AnchorPoint = ElementData.Properties.AnchorPoint or Vector2.new(0.5, 0.5),
			})
		end

		return React.createElement(ElementData.Type, Props, ElementChildren)
	end

	for Id: string, ElementData: AppState.UIElement in AppState.WorkspaceElements do
		if ElementData.ParentId == nil then
			Children[Id] = buildElementTree(Id)
		end
	end

	if IsDragging and ElementType then
		Children["GhostElement"] = React.createElement(ElementType, {
			Position = MousePos,
			Size = UDim2.fromOffset(100, 100),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 0.5,
			BackgroundColor3 = Color3.fromRGB(100, 200, 100),
			ZIndex = 9999,
			Interactable = false,
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 1,
		Visible = ComponentProps.Visible,
	}, Children)
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Workspace_Component Event Binding Section
----------------------------------------------------------
ModifierFlashingSwitch
	:Case("UIStroke"):Execute(flashUIStroke)
	:Case("UIGradient"):Execute(flashUIGradient)
	
	-- Non-visual modifiers do not flash
	:Case("UICorner")
	:Case("UIPadding")
	:Case("UIListLayout")
	:Case("UIGridLayout")
	:Case("UIPageLayout")
	:Case("UIAspectRatioConstraint")
	:Case("UISizeConstraint")
	:Case("UITextSizeConstraint")
	:Case("UIScale")
	:Execute(Assignment.Op.NoOp)

	:Default(flashGenericModifier)

----------------------------------------------------------
return Workspace_Component
----------------------------------------------------------