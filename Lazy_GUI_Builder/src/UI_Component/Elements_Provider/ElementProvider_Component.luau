--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ElementProvider_Component.luau
    
    SCOPE: Elements Provider / Feature UI Component
    
    ROLE: Renders the resizable, draggable Elements Provider palette window,
          displaying selectable UI element types and initiating drag-and-drop
          workflows via InitiateDrag_CL.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ElementProvider_Component Type Structures Section
----------------------------------------------------------
export type ComponentProps = {
	Visible: boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ElementProvider_Component Dependency Section
----------------------------------------------------------
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)
local React = require(script.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ElementProvider_Component Imported Services Section
----------------------------------------------------------
local UserInputService: UserInputService = game:GetService("UserInputService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ElementProvider_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the ElementProvider component palette.

Params:
    Props: ComponentProps -- The properties for the component

Returns:
    ReactElement -- The rendered component
]]
local function ElementProvider_Component(Props: ComponentProps): any
	local ElementsList: { string } = { "Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "CanvasGroup", "VideoFrame", "ViewportFrame" }
	local MaxAllowedWidth: number = (#ElementsList * 120) + 10
	local WindowWidth: number, SetWindowWidth = React.useState(130)
	local IsResizing: boolean, SetIsResizing = React.useState(false)
	local ResizeStartMouseX: number, SetResizeStartMouseX = React.useState(0)
	local ResizeStartWidth: number, SetResizeStartWidth = React.useState(0)

	local ElementButtons: { [string]: any } = {
		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 10),
			PaddingBottom = UDim.new(0, 12),
			PaddingLeft = UDim.new(0, 10),
			PaddingRight = UDim.new(0, 10),
		}),
		
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 10),
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Top,
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	React.useEffect(function(): (() -> ())?
		if not IsResizing then
			return nil
		end

		local ChangedConn: RBXScriptConnection = UserInputService.InputChanged:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				local Delta: number = Input.Position.X - ResizeStartMouseX
				local NewWidth: number = math.clamp(ResizeStartWidth + Delta, 130, MaxAllowedWidth)

				SetWindowWidth(NewWidth)
			end
		end)

		local EndedConn: RBXScriptConnection = UserInputService.InputEnded:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				SetIsResizing(false)
			end
		end)

		return function(): ()
			ChangedConn:Disconnect()
			EndedConn:Disconnect()
		end
	end, { IsResizing, ResizeStartMouseX, ResizeStartWidth } :: { any })

	for Index: number, ElementType: string in ipairs(ElementsList) do
		ElementButtons[ElementType] = React.createElement("TextButton", {
			LayoutOrder = Index,
			Size = UDim2.fromOffset(110, 80),
			BackgroundColor3 = Color3.fromRGB(50, 50, 50),
			Text = ElementType,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			AutoButtonColor = true,
			
			[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					Relay.Create("InitiateDrag_CL"):Fire(ElementType)
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),
		})
	end

	return React.createElement(UI_ComponentSDK.DraggableWindow, {
		Title = WindowWidth < 200 and "Elements" or "Elements Provider",
		Size = UDim2.fromOffset(WindowWidth, 132), 
		Position = AppState.SessionState.ProviderPosition,
		AnchorPoint = Vector2.new(0, 0.5), -- Locks the left edge so resizing perfectly tracks the cursor
		ZIndex = 100,
		Visible = Props.Visible,
		TitleAlignment = Enum.TextXAlignment.Center,
		
		OnDrag = function(NewPosition: UDim2): ()
			Relay.Create("UpdateProviderPosition"):Fire(NewPosition)
		end,
		
		OnClose = function(): ()
			Relay.Create("ToggleProvider_CL"):Fire()
		end,
		
		Children = {
			PaletteScroller = React.createElement("ScrollingFrame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 2,
				CanvasSize = UDim2.fromOffset(MaxAllowedWidth, 0),
				ScrollingDirection = Enum.ScrollingDirection.X,
			}, ElementButtons),

			ResizerHandle = React.createElement("TextButton", {
				Size = UDim2.new(0, 10, 0, 40),
				Position = UDim2.new(1, 4, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Color3.fromRGB(150, 150, 150),
				BackgroundTransparency = 0.5,
				Text = "",
				ZIndex = 10,
				
				[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						SetIsResizing(true)
						SetResizeStartMouseX(Input.Position.X)
						SetResizeStartWidth(WindowWidth)
					end
				end,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		},
	})
end

----------------------------------------------------------
return ElementProvider_Component
----------------------------------------------------------