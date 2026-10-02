--!strict

--[[
    ===========================================================================
    MODULE/COMPONENT: UI_ComponentSDK.luau
    
    SCOPE: UI Component Library
    
    ROLE: A private toolkit of reusable React-Luau UI components (windows, 
          frames, buttons) used to construct the GUI_Builder interface.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UI_ComponentSDK Type Structures Section
----------------------------------------------------------
export type WindowProps = {
	Title: string?,
	TitleAlignment: Enum.TextXAlignment?,
	Size: any?,
	Position: any?,
	AnchorPoint: any?,
	ZIndex: number?,
	Visible: boolean?,
	OnDrag: ((UDim2) -> ())?,
	OnClose: (() -> ())?,
	Children: any?,
	children: any?,
}

export type PanelProps = {
	Size: UDim2?,
	Position: UDim2?,
	BackgroundColor3: Color3?,
	BackgroundTransparency: number?,
	AutomaticSize: Enum.AutomaticSize?,
	ZIndex: number?,
	Interactable: boolean?,
	Active: boolean?,
	Children: any?,
	children: any?,
}

export type TooltipWrapProps = {
	Text: string,
	Size: UDim2?,
	Position: UDim2?,
	TooltipSize: UDim2?,
	LayoutOrder: number?,
	ZIndex: number?,
	Children: any?,
	children: any?,
}

export type ColorPickerProps = {
	InitialColor: Color3?,
	ResetKey: string?,
	OnColorChanged: (Color3) -> (),
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
}

export type DropdownProps = {
	Options: { string },
	SelectedOption: string,
	OnSelect: (string) -> (),
	OnOpenChanged: ((boolean) -> ())?,
	Size: UDim2?,
	Position: UDim2?,
	LayoutOrder: number?,
	ZIndex: number?,
	BackgroundColor3: Color3?,
	FontPreview: boolean?,
}

export type TrackpadProps = {
	Size: UDim2,
	BackgroundColor3: Color3?,
	ShowTracker: boolean?,
	TrackerColor: Color3?,
	Sensitivity: number?,
	OnDragStart: (() -> ())?,
	OnDragDelta: (DeltaX: number, DeltaY: number) -> (),
	OnDragEnd: (() -> ())?,
	LayoutOrder: number?,
}

export type PrecisionDialProps = {
	Size: UDim2,
	Value: number,
	Step: number?,
	Axis: "X" | "Y",
	BackgroundColor3: Color3?,
	Sensitivity: number?,
	CursorIcon: string?,
	OnDragStart: (() -> ())?,
	OnDragDelta: (Delta: number) -> (),
	OnDragEnd: (() -> ())?,
	LayoutOrder: number?,
}

export type PropertiesCategoryProps = {
	Title: string,
	TextColor3: Color3?,
	LayoutOrder: number?,
	children: any?,
}

export type UI_ComponentSDK = {
	Trackpad: (Props: TrackpadProps) -> any,
	PrecisionDial: (Props: PrecisionDialProps) -> any,
	DraggableWindow: (Props: WindowProps) -> any,
	Panel: (Props: PanelProps) -> any,
	TooltipWrap: (Props: TooltipWrapProps) -> any,
	ColorPicker: (Props: ColorPickerProps) -> any,
	Dropdown: (Props: DropdownProps) -> any,
	PropertiesCategory: (Props: PropertiesCategoryProps) -> any,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UI_ComponentSDK Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.React_Lua.React)
local Assignment = require(script.Parent.Parent.Assignment.Assignment)
local DropdownOverlapping_Correctness = require(script.Parent.Dependencies.DropdownOverlapping_Correctness)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UI_ComponentSDK Imported Services Section
----------------------------------------------------------
local UserInputService: UserInputService = game:GetService("UserInputService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UI_ComponentSDK Internal States Section
----------------------------------------------------------
local UI_ComponentSDK = {}
local ActivePlugin: Plugin? = script:FindFirstAncestorWhichIsA("Plugin")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UI_ComponentSDK Local Function Section
----------------------------------------------------------
--[[
Breaks a tooltip string into multiple lines based on a maximum pixel width while preserving paragraph breaks.
]]
local function formatTooltipText(Text: string, MaxWidth: number): string
	local usableWidth = math.max(60, MaxWidth - 16)
	local maxChars = math.floor(usableWidth / 6.5) -- Approximate character width at size 12
	local paragraphs = string.split(Text, "\n")
	local formattedLines = {}

	for _, paragraph in ipairs(paragraphs) do
		if paragraph == "" then
			formattedLines[#formattedLines + 1] = ""

		else
			local words = string.split(paragraph, " ")
			local currentLine = ""

			for _, word in ipairs(words) do
				if word == "" then continue end

				if string.len(currentLine) + string.len(word) + 1 > maxChars then
					if string.len(currentLine) > 0 then
						formattedLines[#formattedLines + 1] = currentLine
						currentLine = word

					else
						-- Word itself is longer than maxChars
						formattedLines[#formattedLines + 1] = word
						currentLine = ""
					end

				else
					if string.len(currentLine) > 0 then
						currentLine = currentLine .. " " .. word

					else
						currentLine = word
					end
				end
			end

			if string.len(currentLine) > 0 then
				formattedLines[#formattedLines + 1] = currentLine
			end
		end
	end

	return table.concat(formattedLines, "\n")
end

--[[
Safely attempts to resolve an Enum.Font member from a string font name.

Params:
    FontName: string? -- Name of the font to resolve

Returns:
    Enum.Font? -- The resolved Enum.Font item, or nil if invalid
]]
local function resolveFontEnum(FontName: string?): Enum.Font?
	if not FontName or FontName == "" then
		return nil
	end

	local Success: boolean, FontItem: any = pcall(function()
		return (Enum.Font :: any)[FontName]
	end)

	if Success and FontItem then
		return FontItem :: Enum.Font
	end

	return nil
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UI_ComponentSDK Public APIs Section
----------------------------------------------------------
--[[
Creates a draggable window component that acts as a custom DockWidget replacement.

Params:
    Props: WindowProps -- Properties to configure the window

Returns:
    any -- A React element
]]
function UI_ComponentSDK.DraggableWindow(Props: WindowProps): any
	local Position, SetPosition = React.useBinding(Props.Position or UDim2.fromScale(0.5, 0.5))
	local IsDragging: boolean, SetIsDragging = React.useState(false)
	local DragStart: Vector2, SetDragStart = React.useState(Vector2.zero)
	local StartPosition: UDim2, SetStartPosition = React.useState(UDim2.fromScale(0, 0))

	-- Handles input began on the title bar
	local function onInputBegan(Rbx: Instance, Input: InputObject): ()
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			SetIsDragging(true)
			SetDragStart(Vector2.new(Input.Position.X, Input.Position.Y))
			SetStartPosition(Position:getValue())
		end
	end

	React.useEffect(function(): (() -> ())?
		if not IsDragging then
			return nil
		end

		local ChangedConnection: RBXScriptConnection = UserInputService.InputChanged:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				local Delta: Vector2 = Vector2.new(Input.Position.X, Input.Position.Y) - DragStart
				local NewPosition: UDim2 = UDim2.new(
					StartPosition.X.Scale, StartPosition.X.Offset + Delta.X,
					StartPosition.Y.Scale, StartPosition.Y.Offset + Delta.Y
				)

				SetPosition(NewPosition)

				if Props.OnDrag then
					Props.OnDrag(NewPosition)
				end
			end
		end)

		local EndedConnection: RBXScriptConnection = UserInputService.InputEnded:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				SetIsDragging(false)
			end
		end)

		return function(): ()
			ChangedConnection:Disconnect()
			EndedConnection:Disconnect()
		end
	end, { IsDragging, DragStart, StartPosition } :: { any })

	return React.createElement("Frame", {
		Size = Props.Size or UDim2.fromOffset(400, 300),
		Position = Position,
		AnchorPoint = Props.AnchorPoint or Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(35, 35, 35),
		BorderSizePixel = 0,
		ZIndex = Props.ZIndex or 1,
		Visible = if Props.Visible ~= nil then Props.Visible else true,
		Active = true,
	}, {
		WindowCorner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 6),
		}),

		TitleBar = React.createElement("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundColor3 = Color3.fromRGB(25, 25, 25),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Text = "",
			Active = true,
			ZIndex = 2,
			[React.Event.InputBegan] = onInputBegan,
		}, {
			TitleCorner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 6),
			}),

			BottomFiller = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 6),
				Position = UDim2.new(0, 0, 1, -6),
				BackgroundColor3 = Color3.fromRGB(25, 25, 25),
				BorderSizePixel = 0,
				ZIndex = 1,
			}),

			TitleText = React.createElement("TextLabel", {
				Size = UDim2.new(1, -60, 1, 0),
				Position = UDim2.fromOffset(10, 0),
				BackgroundTransparency = 1,
				Text = Props.Title or "Window",
				TextColor3 = Color3.fromRGB(220, 220, 220),
				Font = Enum.Font.GothamBold,
				TextXAlignment = Props.TitleAlignment or Enum.TextXAlignment.Left,
				TextSize = 14,
				ZIndex = 2,
			}),

			CloseButton = React.createElement("TextButton", {
				Size = UDim2.new(0, 30, 0, 30),
				Position = UDim2.new(1, -30, 0, 0),
				BackgroundTransparency = 1,
				Text = "X",
				TextColor3 = Color3.fromRGB(220, 100, 100),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				ZIndex = 2,

				[React.Event.Activated] = function(): ()
					if Props.OnClose then
						Props.OnClose()
					end
				end,
			}),

			Divider = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 1),
				Position = UDim2.new(0, 0, 1, -1),
				BackgroundColor3 = Color3.fromRGB(15, 15, 15),
				BorderSizePixel = 0,
				ZIndex = 3,
			}),
		}),

		Content = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 1, -30),
			Position = UDim2.fromOffset(0, 30),
			BackgroundTransparency = 1,
		}, Props.children or Props.Children),
	})
end

--[[
Creates a basic static container panel.

Params:
    Props: PanelProps -- Properties for the panel

Returns:
    any -- A React element
]]
function UI_ComponentSDK.Panel(Props: PanelProps): any
	return React.createElement("Frame", {
		Size = Props.Size or UDim2.fromScale(1, 1),
		Position = Props.Position or UDim2.fromScale(0, 0),
		BackgroundColor3 = Props.BackgroundColor3 or Color3.fromRGB(45, 45, 45),
		BackgroundTransparency = Props.BackgroundTransparency or 0,
		AutomaticSize = Props.AutomaticSize,
		ZIndex = Props.ZIndex or 1,
		Interactable = if Props.Interactable ~= nil then Props.Interactable else true,
		Active = if Props.Active ~= nil then Props.Active else false,
		BorderSizePixel = 0,
	}, Props.children or Props.Children)
end

--[[
Wraps a component to provide a dynamic floating tooltip on hover.

Params:
    Props: TooltipWrapProps -- Properties for the tooltip wrapper

Returns:
    any -- A React element
]]

function UI_ComponentSDK.TooltipWrap(Props: TooltipWrapProps): any
	local FormattedText = Props.Text or ""

	if Props.TooltipSize and Props.Text then
		FormattedText = formatTooltipText(Props.Text, Props.TooltipSize.X.Offset)
	end

	local IsHovered: boolean, SetIsHovered = React.useState(false)
	local TooltipAnchor, SetTooltipAnchor = React.useState(Vector2.new(0.5, 0))
	local TooltipPos, SetTooltipPos = React.useState(UDim2.new(0.5, 0, 1, 6))
	local HoverThread = React.useRef(nil :: Assignment.Handle?)
	local Children: any = Props.children or Props.Children
	local RenderChildren: any = {}
	local WrapRef = React.useRef(nil :: GuiObject?)

	-- Handles the mouse entering the component area
	local function onMouseEnter(): ()
		if HoverThread.current then
			Assignment.Cancel(HoverThread.current)
		end

		HoverThread.current = Assignment.Delay(1.5, function(): ()
			if WrapRef.current then
				local AbsX: number = WrapRef.current.AbsolutePosition.X
				local AbsY: number = WrapRef.current.AbsolutePosition.Y
				local AbsHeight: number = WrapRef.current.AbsoluteSize.Y
				local Gui: LayerCollector? = WrapRef.current:FindFirstAncestorWhichIsA("LayerCollector")
				local ScreenWidth: number = if Gui then Gui.AbsoluteSize.X else 800
				local ScreenHeight: number = if Gui then Gui.AbsoluteSize.Y else 600
				local EstimatedWidth: number = if Props.TooltipSize then Props.TooltipSize.X.Offset else 200
				local LineCount: number = select(2, string.gsub(FormattedText or "", "\n", "")) + 1
				local EstimatedHeight: number = 16 + (LineCount * 16)
				local AnchorX: number = 0.5
				local PosX: number = 0.5
				local AnchorY: number = 0
				local PosY: number = 1
				local OffsetY: number = 6

				if AbsX - (EstimatedWidth / 2) < 10 then
					AnchorX = 0
					PosX = 0

				elseif AbsX + (EstimatedWidth / 2) > ScreenWidth - 10 then
					AnchorX = 1
					PosX = 1
				end

				if (AbsY + AbsHeight + OffsetY + EstimatedHeight) > ScreenHeight - 10 then
					AnchorY = 1
					PosY = 0
					OffsetY = -6
				end

				SetTooltipAnchor(Vector2.new(AnchorX, AnchorY))
				SetTooltipPos(UDim2.new(PosX, 0, PosY, OffsetY))
			end

			SetIsHovered(true)
		end)
	end

	-- Handles the mouse leaving the component area
	local function onMouseLeave(): ()
		if HoverThread.current then
			Assignment.Cancel(HoverThread.current)
			HoverThread.current = nil
		end

		SetIsHovered(false)
	end

	React.useEffect(function(): (() -> ())?
		if IsHovered and WrapRef.current then
			DropdownOverlapping_Correctness.Correct(WrapRef.current)
		end

		return function(): ()
			if HoverThread.current then
				Assignment.Cancel(HoverThread.current)
			end

			if WrapRef.current then
				DropdownOverlapping_Correctness.Revert(WrapRef.current)
			end
		end
	end, {IsHovered, WrapRef.current} :: {any})

	if type(Children) == "table" then
		for Key: any, Element: any in Children do
			RenderChildren[Key] = Element
		end
	end

	RenderChildren["Tooltip"] = IsHovered and React.createElement("Frame", {
		Size = UDim2.fromOffset(0, 0),
		AutomaticSize = Enum.AutomaticSize.XY,
		Position = TooltipPos,
		AnchorPoint = TooltipAnchor,
		BackgroundColor3 = Color3.fromRGB(25, 25, 25),
		ZIndex = 1000,
	}, {
		Corner = React.createElement("UICorner", {
			CornerRadius = UDim.new(0, 4) 
		}),

		Stroke = React.createElement("UIStroke", { 
			Color = Color3.fromRGB(80, 80, 80)
		}),

		Padding = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 6),
			PaddingBottom = UDim.new(0, 6),
			PaddingLeft = UDim.new(0, 8),
			PaddingRight = UDim.new(0, 8),
		}),

		Label = React.createElement("TextLabel", {
			Size = UDim2.fromOffset(0, 0),
			AutomaticSize = Enum.AutomaticSize.XY,
			BackgroundTransparency = 1,
			Text = FormattedText,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			Font = Enum.Font.Gotham,
			TextSize = 12,
			TextWrapped = false,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = 1001,
		})
	}) or nil

	return React.createElement("Frame", {
		ref = WrapRef,
		Size = Props.Size or UDim2.fromScale(1, 1),
		Position = Props.Position,
		LayoutOrder = Props.LayoutOrder,
		BackgroundTransparency = 1,
		ZIndex = Props.ZIndex or 1,
		[React.Event.MouseEnter] = onMouseEnter,
		[React.Event.MouseLeave] = onMouseLeave,
	}, RenderChildren)
end

--[[
Renders an interactive ColorPicker component with HSV and RGB modes.

Params:
    Props: ColorPickerProps -- Properties for the color picker

Returns:
    any -- A React element
]]
function UI_ComponentSDK.ColorPicker(Props: ColorPickerProps): any
	local InitialH: number, InitialS: number, InitialV: number
	local Mode: string, SetMode = React.useState("HSV")
	local CurrentColor: Color3, SetCurrentColor = React.useState(Props.InitialColor or Color3.new(1, 1, 1))

	if Props.InitialColor then
		InitialH, InitialS, InitialV = Props.InitialColor:ToHSV()

	else
		InitialH, InitialS, InitialV = CurrentColor:ToHSV()
	end

	local Hue: number, SetHue = React.useState(InitialH)
	local Sat: number, SetSat = React.useState(InitialS)
	local Val: number, SetVal = React.useState(InitialV)

	-- Handles updating HSV based on an incoming external Color3
	local function setFromColor3(C: Color3): ()
		local H: number, S: number, V: number = C:ToHSV()

		if S == 0 then 
			H = Hue
		end

		SetHue(H)
		SetSat(S)
		SetVal(V)
	end

	-- Handles mode button rendering
	local function renderModeButton(TargetMode: string, Label: string): any
		return React.createElement("TextButton", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundColor3 = (Mode == TargetMode) and Color3.fromRGB(80, 80, 80) or Color3.fromRGB(45, 45, 45),
			Text = Label,
			TextColor3 = Color3.fromRGB(220, 220, 220),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			BorderSizePixel = 0,

			[React.Event.Activated] = function(): ()
				SetMode(TargetMode)
			end,
		}, {
			Corner = React.createElement("UICorner", { 
				CornerRadius = UDim.new(0, 4) 
			})
		})
	end

	-- Handles sidebar text input rendering
	local function renderSidebarInput(Label: string, Value: number, OnChange: (number) -> ()): any
		return React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 18),
			BackgroundTransparency = 1,
		}, {
			Title = React.createElement("TextLabel", {
				Size = UDim2.new(0, 15, 1, 0),
				BackgroundTransparency = 1,
				Text = Label,
				TextColor3 = Color3.fromRGB(220, 220, 220),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			Input = React.createElement("TextBox", {
				Size = UDim2.new(1, -15, 1, 0),
				Position = UDim2.new(0, 15, 0, 0),
				BackgroundColor3 = Color3.fromRGB(15, 15, 15),
				Text = tostring(math.round(Value * 255)),
				TextColor3 = Color3.fromRGB(220, 220, 220),
				Font = Enum.Font.Gotham,
				TextSize = 12,
				BorderSizePixel = 0,

				[React.Event.FocusLost] = function(Rbx: Instance, EnterPressed: boolean): ()
					local TextBox = Rbx :: TextBox
					local Num: number? = tonumber(TextBox.Text)

					if Num then
						Num = math.clamp(math.round(Num), 0, 255)
						OnChange(Num / 255)
					end

					TextBox.Text = tostring(math.round(Value * 255))
				end,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4)
				})
			})
		})
	end

	-- Handles RGB slider rendering
	local function renderRGB_Slider(Label: string, ChannelColor: Color3, Value: number, LayoutOrder: number, OnChange: (number) -> ()): any
		local function handleInput(Rbx: Instance, Input: InputObject): ()
			if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
				local AbsPos: Vector2 = (Rbx :: GuiObject).AbsolutePosition
				local AbsSize: Vector2 = (Rbx :: GuiObject).AbsoluteSize
				local RelX: number = math.clamp((Input.Position.X - AbsPos.X) / AbsSize.X, 0, 1)

				OnChange(RelX)
			end
		end

		return React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 26),
			BackgroundTransparency = 1,
			LayoutOrder = LayoutOrder,
		}, {
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(0, 15, 1, 0),
				BackgroundTransparency = 1,
				Text = Label,
				TextColor3 = Color3.fromRGB(180, 180, 180),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
			}),

			Track = React.createElement("TextButton", {
				Size = UDim2.new(1, -25, 0, 10),
				Position = UDim2.new(0, 25, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Color3.fromRGB(25, 25, 25),
				Text = "",
				AutoButtonColor = false,

				[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
					if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.MouseMovement then
						handleInput(Rbx, Input)
					end
				end,

				[React.Event.InputChanged] = function(Rbx: Instance, Input: InputObject): ()
					if Input.UserInputType == Enum.UserInputType.MouseMovement then
						handleInput(Rbx, Input)
					end
				end,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(1, 0) 
				}),

				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(Value, 1),
					BackgroundColor3 = ChannelColor,
					BorderSizePixel = 0,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(1, 0) 
					}),
				}),

				Marker = React.createElement("Frame", {
					Size = UDim2.fromOffset(14, 14),
					Position = UDim2.new(Value, 0, 0.5, 0),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = Color3.fromRGB(220, 220, 220),
					ZIndex = 2,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(1, 0)
					}),

					Stroke = React.createElement("UIStroke", { 
						Color = Color3.fromRGB(0, 0, 0)
					})
				})
			})
		})
	end

	-- Handles mouse input for the saturation/value map
	local function handleSVMapInput(Rbx: Instance, Input: InputObject): ()
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			local AbsPos: Vector2 = (Rbx :: GuiObject).AbsolutePosition
			local AbsSize: Vector2 = (Rbx :: GuiObject).AbsoluteSize
			local RelX: number = math.clamp((Input.Position.X - AbsPos.X) / AbsSize.X, 0, 1)
			local RelY: number = math.clamp((Input.Position.Y - AbsPos.Y) / AbsSize.Y, 0, 1)

			SetSat(RelX)
			SetVal(1 - RelY)
		end
	end

	-- Handles mouse input for the hue slider
	local function handleHueInput(Rbx: Instance, Input: InputObject): ()
		if UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
			local AbsPos: Vector2 = (Rbx :: GuiObject).AbsolutePosition
			local AbsSize: Vector2 = (Rbx :: GuiObject).AbsoluteSize
			local RelY: number = math.clamp((Input.Position.Y - AbsPos.Y) / AbsSize.Y, 0, 1)

			SetHue(1 - RelY)
		end
	end

	React.useEffect(function(): ()
		if Props.InitialColor then
			setFromColor3(Props.InitialColor)
		end
	end, {Props.ResetKey} :: {any})

	React.useEffect(function(): ()
		local NewColor = Color3.fromHSV(Hue, Sat, Val)

		SetCurrentColor(NewColor)

		if Props.OnColorChanged then
			Props.OnColorChanged(NewColor)
		end
	end, {Hue, Sat, Val})

	return React.createElement("Frame", {
		Size = Props.Size or UDim2.fromOffset(300, 200),
		Position = Props.Position or UDim2.fromScale(0, 0),
		AnchorPoint = Props.AnchorPoint or Vector2.new(0, 0),
		BackgroundColor3 = Color3.fromRGB(35, 35, 35),
		BorderSizePixel = 0,
	}, {
		Corner = React.createElement("UICorner", { 
			CornerRadius = UDim.new(0, 6)
		}),

		Sidebar = React.createElement("Frame", {
			Size = UDim2.new(0, 60, 1, 0),
			BackgroundColor3 = Color3.fromRGB(25, 25, 25),
			BorderSizePixel = 0,
		}, {
			Corner = React.createElement("UICorner", { 
				CornerRadius = UDim.new(0, 6) 
			}),

			Layout = React.createElement("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
			}),

			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 6),
				PaddingLeft = UDim.new(0, 5),
				PaddingRight = UDim.new(0, 5),
			}),

			HSVBtn = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				Btn = renderModeButton("HSV", "HSV")
			}),

			RGBBtn = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, {
				Btn = renderModeButton("RGB", "RGB")
			}),

			RInput = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				LayoutOrder = 3,
			}, {
				Input = renderSidebarInput("R", CurrentColor.R, function(Val: number): ()
					setFromColor3(Color3.new(Val, CurrentColor.G, CurrentColor.B))
				end)
			}),

			GInput = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				LayoutOrder = 4,
			}, {
				Input = renderSidebarInput("G", CurrentColor.G, function(Val: number): ()
					setFromColor3(Color3.new(CurrentColor.R, Val, CurrentColor.B))
				end)
			}),

			BInput = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 18),
				BackgroundTransparency = 1,
				LayoutOrder = 5,
			}, {
				Input = renderSidebarInput("B", CurrentColor.B, function(Val: number): ()
					setFromColor3(Color3.new(CurrentColor.R, CurrentColor.G, Val))
				end)
			}),

		}),

		Content = React.createElement("Frame", {
			Size = UDim2.new(1, -70, 1, 0),
			Position = UDim2.new(0, 70, 0, 0),
			BackgroundTransparency = 1,
		}, {
			HSVView = Mode == "HSV" and React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				SVMap = React.createElement("TextButton", {
					Size = UDim2.new(1, -40, 1, 0),
					BackgroundColor3 = Color3.fromHSV(Hue, 1, 1),
					Text = "",
					AutoButtonColor = false,

					[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
						if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.MouseMovement then
							handleSVMapInput(Rbx, Input)
						end
					end,

					[React.Event.InputChanged] = function(Rbx: Instance, Input: InputObject): ()
						if Input.UserInputType == Enum.UserInputType.MouseMovement then
							handleSVMapInput(Rbx, Input)
						end
					end,
				}, {
					WhiteGradient = React.createElement("UIGradient", {
						Color = ColorSequence.new(Color3.new(1, 1, 1)),
						Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)}),
						Rotation = 0,
					}),

					BlackOverlay = React.createElement("Frame", {
						Size = UDim2.fromScale(1, 1),
						BackgroundColor3 = Color3.new(0, 0, 0),
						BackgroundTransparency = 0,
						ZIndex = 2,
					}, {
						BlackGradient = React.createElement("UIGradient", {
							Color = ColorSequence.new(Color3.new(0, 0, 0)),
							Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)}),
							Rotation = 90,
						}),
					}),

					Marker = React.createElement("Frame", {
						Size = UDim2.fromOffset(10, 10),
						Position = UDim2.fromScale(Sat, 1 - Val),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.new(1, 1, 1),
						ZIndex = 3,
					}, {
						Corner = React.createElement("UICorner", { 
							CornerRadius = UDim.new(1, 0) 
						}),

						Stroke = React.createElement("UIStroke", {
							Color = Color3.new(0, 0, 0) 
						})
					})
				}),

				HueSlider = React.createElement("TextButton", {
					Size = UDim2.new(0, 30, 1, 0),
					Position = UDim2.new(1, -30, 0, 0),
					BackgroundColor3 = Color3.new(1, 1, 1),
					Text = "",
					AutoButtonColor = false,

					[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
						if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.MouseMovement then
							handleHueInput(Rbx, Input)
						end
					end,

					[React.Event.InputChanged] = function(Rbx: Instance, Input: InputObject): ()
						if Input.UserInputType == Enum.UserInputType.MouseMovement then
							handleHueInput(Rbx, Input)
						end
					end,
				}, {
					Gradient = React.createElement("UIGradient", {
						Color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.new(1, 0, 0)),
							ColorSequenceKeypoint.new(0.166, Color3.new(1, 0, 1)),
							ColorSequenceKeypoint.new(0.333, Color3.new(0, 0, 1)),
							ColorSequenceKeypoint.new(0.5, Color3.new(0, 1, 1)),
							ColorSequenceKeypoint.new(0.666, Color3.new(0, 1, 0)),
							ColorSequenceKeypoint.new(0.833, Color3.new(1, 1, 0)),
							ColorSequenceKeypoint.new(1, Color3.new(1, 0, 0))
						}),

						Rotation = 90,
					}),

					Marker = React.createElement("Frame", {
						Size = UDim2.new(1.2, 0, 0, 4),
						Position = UDim2.new(-0.1, 0, 1 - Hue, 0),
						AnchorPoint = Vector2.new(0, 0.5),
						BackgroundColor3 = Color3.new(1, 1, 1),
						BorderSizePixel = 1,
						BorderColor3 = Color3.new(0, 0, 0),
					})
				})
			}),

			RGBView = Mode == "RGB" and React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 10),
					VerticalAlignment = Enum.VerticalAlignment.Center,
				}),

				R = renderRGB_Slider("R", Color3.new(1, 0, 0), CurrentColor.R, 1, function(Val: number): ()
					setFromColor3(Color3.new(Val, CurrentColor.G, CurrentColor.B))
				end),

				G = renderRGB_Slider("G", Color3.new(0, 1, 0), CurrentColor.G, 2, function(Val: number): ()
					setFromColor3(Color3.new(CurrentColor.R, Val, CurrentColor.B))
				end),

				B = renderRGB_Slider("B", Color3.new(0, 0, 1), CurrentColor.B, 3, function(Val: number): ()
					setFromColor3(Color3.new(CurrentColor.R, CurrentColor.G, Val))
				end),
			})
		})
	})
end

--[[
Creates a collapsible properties category component.

Params:
    Props: PropertiesCategoryProps -- Properties for the category

Returns:
    any -- A React element
]]
function UI_ComponentSDK.PropertiesCategory(Props: PropertiesCategoryProps): any
	local IsExpanded: boolean, SetIsExpanded = React.useState(true)
	local TextColor: Color3 = Props.TextColor3 or Color3.fromRGB(220, 220, 220)

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder = Props.LayoutOrder,
	}, {
		Header = React.createElement("TextButton", {
			Size = UDim2.new(1, 0, 0, 20),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,

			[React.Event.Activated] = function(): ()
				SetIsExpanded(not IsExpanded)
			end,
		}, {
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				VerticalAlignment = Enum.VerticalAlignment.Center,
			}),

			ToggleButton = React.createElement("TextLabel", {
				Size = UDim2.new(0, 20, 1, 0),
				BackgroundTransparency = 1,
				Text = IsExpanded and "\u{25BC}" or "\u{25B6}",
				TextColor3 = TextColor,
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				LayoutOrder = 1,
			}),

			Title = React.createElement("TextLabel", {
				Size = UDim2.new(1, -20, 1, 0),
				BackgroundTransparency = 1,
				Text = Props.Title,
				TextColor3 = TextColor,
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				LayoutOrder = 2,
			}),
		}),

		Content = React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			Position = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Visible = IsExpanded,
		}, Props.children),
	})
end

--[[
Creates a dropdown menu component.

Params:
    Props: DropdownProps -- Properties for the dropdown

Returns:
    any -- A React element
]]
function UI_ComponentSDK.Dropdown(Props: DropdownProps): any
	local IsOpen: boolean, SetIsOpen = React.useState(false)
	local HoveredIndex: number?, SetHoveredIndex = React.useState(nil :: number?)
	local SpawnUpwards: boolean, SetSpawnUpwards = React.useState(false)
	local ButtonRef = React.useRef(nil :: GuiObject?)
	local OptionCount = #Props.Options
	local MenuHeight = math.min(OptionCount, 10) * 30
	local IsHoveringMenu: boolean, SetIsHoveringMenu = React.useState(false)
	local MenuRef = React.useRef(nil :: GuiObject?)

	React.useEffect(function(): ()
		if not IsOpen then
			SetHoveredIndex(nil)
		end
	end, {IsOpen} :: {any})

	React.useEffect(function(): (() -> ())?
		local ParentScroller: ScrollingFrame? = nil

		if IsOpen and IsHoveringMenu and MenuRef.current then
			ParentScroller = MenuRef.current:FindFirstAncestorOfClass("ScrollingFrame")

			if ParentScroller then
				ParentScroller.ScrollingEnabled = false
			end
		end

		return function()
			if ParentScroller then
				ParentScroller.ScrollingEnabled = true
			end
		end
	end, {IsOpen, IsHoveringMenu, MenuRef.current} :: {any})

	React.useEffect(function(): (() -> ())?
		if IsOpen and ButtonRef.current then
			DropdownOverlapping_Correctness.Correct(ButtonRef.current)
		end

		return function()
			if ButtonRef.current then
				DropdownOverlapping_Correctness.Revert(ButtonRef.current)
			end
		end
	end, {IsOpen, ButtonRef.current} :: {any})

	-- Handles the opening and closing of the dropdown menu
	local function handleToggle(Rbx: Instance): ()
		if not IsOpen then
			local GuiObj = Rbx :: GuiObject
			local Root = GuiObj:FindFirstAncestorOfClass("ScrollingFrame") or GuiObj:FindFirstAncestorOfClass("PluginGui") or GuiObj:FindFirstAncestorOfClass("ScreenGui")
			local WinHeight = Root and (Root :: GuiBase2d).AbsoluteSize.Y or 1000
			local BtnBottom = GuiObj.AbsolutePosition.Y + GuiObj.AbsoluteSize.Y

			if BtnBottom + MenuHeight + 4 > WinHeight then
				SetSpawnUpwards(true)

			else
				SetSpawnUpwards(false)
			end
		end

		local NextState = not IsOpen

		SetIsOpen(NextState)

		if Props.OnOpenChanged then
			Props.OnOpenChanged(NextState)
		end
	end

	local OptionElements: { [string]: any } = {}

	OptionElements["Layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 0),
	})

	for Index, OptionValue in ipairs(Props.Options) do
		local IsHovered = HoveredIndex == Index
		local OptionFont = if (Props.FontPreview and IsHovered) then (resolveFontEnum(OptionValue) or Enum.Font.Gotham) else Enum.Font.Gotham

		OptionElements["Option_" .. tostring(Index)] = React.createElement("TextButton", {
			Size = UDim2.new(1, 0, 0, 30),
			BackgroundTransparency = IsHovered and 0 or 1,
			BackgroundColor3 = Color3.fromRGB(80, 80, 80),
			Text = tostring(OptionValue),
			TextColor3 = IsHovered and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(220, 220, 220),
			Font = OptionFont,
			TextSize = (Props.FontPreview and IsHovered) and 14 or 12,
			LayoutOrder = Index,
			ZIndex = (Props.ZIndex or 1) + 11,
			BorderSizePixel = 0,

			[React.Event.MouseEnter] = function(): ()
				SetHoveredIndex(Index)
			end,

			[React.Event.MouseLeave] = function(): ()
				SetHoveredIndex(function(PrevIndex: number?): number?
					return if PrevIndex == Index then nil else PrevIndex
				end)
			end,

			[React.Event.Activated] = function(): ()
				if Props.OnSelect then
					Props.OnSelect(OptionValue)
				end

				SetIsOpen(false)

				if Props.OnOpenChanged then
					Props.OnOpenChanged(false)
				end
			end,
		})
	end

	return React.createElement("Frame", {
		Size = Props.Size or UDim2.new(1, 0, 0, 30),
		Position = Props.Position,
		LayoutOrder = Props.LayoutOrder,
		BackgroundTransparency = 1,
		ZIndex = Props.ZIndex or 1,
	}, {
		-- Main Toggle Button
		SourceButton = React.createElement("TextButton", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Props.BackgroundColor3 or Color3.fromRGB(45, 45, 45),
			Text = Props.SelectedOption or "Select...",
			TextColor3 = Color3.fromRGB(220, 220, 220),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			ZIndex = Props.ZIndex or 1,
			BorderSizePixel = 0,
			ref = ButtonRef,

			[React.Event.Activated] = handleToggle,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),

			Icon = React.createElement("TextLabel", {
				Size = UDim2.new(0, 20, 1, 0),
				Position = UDim2.new(1, -25, 0, 0),
				BackgroundTransparency = 1,
				Text = IsOpen and "\u{25B2}" or "\u{25BC}",
				TextColor3 = Color3.fromRGB(150, 150, 150),
				Font = Enum.Font.Gotham,
				TextSize = 10,
				ZIndex = (Props.ZIndex or 1) + 1,
			}),
		}),

		-- Dropdown Menu Container
		Menu = IsOpen and React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, MenuHeight),
			Position = SpawnUpwards and UDim2.new(0, 0, 0, -MenuHeight - 4) or UDim2.new(0, 0, 1, 4),
			BackgroundColor3 = Props.BackgroundColor3 or Color3.fromRGB(45, 45, 45),
			ZIndex = (Props.ZIndex or 1) + 10,
			BorderSizePixel = 0,
			ref = MenuRef,

			[React.Event.MouseEnter] = function(): ()
				SetIsHoveringMenu(true)
			end,

			[React.Event.MouseLeave] = function(): ()
				SetIsHoveringMenu(false)
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),

			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(100, 100, 100),
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
				Thickness = 1,
			}),

			ItemsWrapper = React.createElement("ScrollingFrame", {
				Size = UDim2.fromScale(1, 1),
				Position = UDim2.fromScale(0, 0),
				BackgroundTransparency = 1,
				ClipsDescendants = true,
				CanvasSize = UDim2.new(0, 0, 0, OptionCount * 30),
				ScrollBarThickness = 0,
				BorderSizePixel = 0,
				ScrollingDirection = Enum.ScrollingDirection.Y,
			}, OptionElements),
		}) or nil,
	})
end

--[[
Renders a 2D trackpad widget for capturing X and Y pointer deltas.

Params:
    Props: TrackpadProps -- Component props

Returns:
    any -- A React element
]]
function UI_ComponentSDK.Trackpad(Props: TrackpadProps): any
	local IsDragging, SetIsDragging = React.useBinding(false)
	local StartMousePos, SetStartMousePos = React.useBinding(Vector2.zero)
	local TrackerPos, SetTrackerPos = React.useBinding(UDim2.fromOffset(0, 0))

	local function onInputBegan(Rbx: Instance, Input: InputObject): ()
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			local absPos = (Rbx :: GuiObject).AbsolutePosition

			SetIsDragging(true)
			SetStartMousePos(Vector2.new(Input.Position.X, Input.Position.Y))
			SetTrackerPos(UDim2.fromOffset(Input.Position.X - absPos.X, Input.Position.Y - absPos.Y))

			if Props.OnDragStart then
				Props.OnDragStart()
			end
		end
	end

	local function onInputEnded(Rbx: Instance, Input: InputObject): ()
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			SetIsDragging(false)

			if Props.OnDragEnd then
				Props.OnDragEnd()
			end
		end
	end

	return React.createElement("Frame", {
		Size = Props.Size,
		BackgroundColor3 = Props.BackgroundColor3 or Color3.fromRGB(35, 35, 35),
		LayoutOrder = Props.LayoutOrder,
		Active = true,

		[React.Event.InputBegan] = onInputBegan,

		[React.Event.InputEnded] = onInputEnded,
	}, {
		Corner = React.createElement("UICorner", { 
			CornerRadius = UDim.new(0, 4) 
		}),

		Tracker = React.createElement("Frame", {
			Size = UDim2.fromOffset(8, 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = TrackerPos,
			BackgroundColor3 = Props.TrackerColor or Color3.fromRGB(255, 60, 60),
			Visible = if Props.ShowTracker ~= false then IsDragging else false,
			ZIndex = 2,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(1, 0)
			})
		}),

		DragOverlay = React.createElement("TextButton", {
			Visible = IsDragging,
			Size = UDim2.fromScale(100, 100),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 9999,

			[React.Event.InputChanged] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseMovement then
					local padAbsPos = (Rbx.Parent :: GuiObject).AbsolutePosition
					local padAbsSize = (Rbx.Parent :: GuiObject).AbsoluteSize

					local clampedX = math.clamp(Input.Position.X, padAbsPos.X, padAbsPos.X + padAbsSize.X)
					local clampedY = math.clamp(Input.Position.Y, padAbsPos.Y, padAbsPos.Y + padAbsSize.Y)

					local mouse = Vector2.new(clampedX, clampedY)
					local delta = (mouse - StartMousePos:getValue()) * (Props.Sensitivity or 1)

					SetTrackerPos(UDim2.fromOffset(mouse.X - padAbsPos.X, mouse.Y - padAbsPos.Y))
					Props.OnDragDelta(delta.X, delta.Y)
					SetStartMousePos(mouse)
				end
			end,
		})
	})
end

--[[
Renders a 1D precision dial widget for capturing stepped pointer deltas.

Params:
    Props: PrecisionDialProps -- Component props

Returns:
    any -- A React element
]]
function UI_ComponentSDK.PrecisionDial(Props: PrecisionDialProps): any
	local IsDragging, SetIsDragging = React.useBinding(false)
	local StartMousePos, SetStartMousePos = React.useBinding(Vector2.zero)
	local ScrollOffset, SetScrollOffset = React.useBinding(0)

	React.useEffect(function(): ()
		local sensitivity = Props.Sensitivity or 0.25
		local cycleLength = 20
		local visualOffset = (Props.Value / sensitivity) % cycleLength

		SetScrollOffset(visualOffset)
	end, { Props.Value } :: { any })

	local function onInputBegan(Rbx: Instance, Input: InputObject): ()
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			SetIsDragging(true)
			SetStartMousePos(Vector2.new(Input.Position.X, Input.Position.Y))

			if ActivePlugin then
				ActivePlugin:GetMouse().Icon = Props.CursorIcon or "rbxasset://SystemCursors/ClosedHand"
			end

			if Props.OnDragStart then
				Props.OnDragStart()
			end
		end
	end

	local function onInputEnded(Rbx: Instance, Input: InputObject): ()
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			SetIsDragging(false)

			if ActivePlugin then
				ActivePlugin:GetMouse().Icon = ""
			end

			if Props.OnDragEnd then
				Props.OnDragEnd()
			end
		end
	end

	local Grooves: { [string]: any } = {}
	local TICK_COUNT = 31

	Grooves["Layout"] = React.createElement("UIListLayout", {
		FillDirection = Props.Axis == "X" and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 10),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	for i = 1, TICK_COUNT do
		local IsLong = i % 2 == 1

		if Props.Axis == "X" then
			Grooves["Tick_" .. i] = React.createElement("Frame", {
				Size = UDim2.new(0, 2, IsLong and 0.7 or 0.4, 0),
				BackgroundColor3 = Color3.fromRGB(80, 80, 80),
				BorderSizePixel = 0,
				LayoutOrder = i,
			})

		else
			Grooves["Tick_" .. i] = React.createElement("Frame", {
				Size = UDim2.new(IsLong and 0.7 or 0.4, 0, 0, 2),
				BackgroundColor3 = Color3.fromRGB(80, 80, 80),
				BorderSizePixel = 0,
				LayoutOrder = i,
			})
		end
	end

	return React.createElement("Frame", {
		Size = Props.Size,
		BackgroundColor3 = Props.BackgroundColor3 or Color3.fromRGB(45, 45, 45),
		LayoutOrder = Props.LayoutOrder,
		Active = true,
		ClipsDescendants = true,

		[React.Event.InputBegan] = onInputBegan,

		[React.Event.InputEnded] = onInputEnded,
	}, {
		Corner = React.createElement("UICorner", { 
			CornerRadius = UDim.new(0, 4)
		}),

		GroovesContainer = React.createElement("Frame", {
			Size = Props.Axis == "X" and UDim2.new(1, 80, 1, 0) or UDim2.new(1, 0, 1, 80),

			Position = ScrollOffset:map(function(offset: number): UDim2
				if Props.Axis == "X" then
					return UDim2.new(0.5, offset, 0.5, 0)

				else
					return UDim2.new(0.5, 0, 0.5, offset)
				end
			end),

			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			ZIndex = 1,
		}, Grooves),

		DragOverlay = React.createElement("TextButton", {
			Visible = IsDragging,
			Size = UDim2.fromScale(100, 100),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			Text = "",
			ZIndex = 9999,

			[React.Event.InputChanged] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseMovement then
					local mouse = Vector2.new(Input.Position.X, Input.Position.Y)
					local rawDelta = (mouse - StartMousePos:getValue()) * (Props.Sensitivity or 0.25)
					local step = Props.Step or 1

					if Props.Axis == "X" then
						if math.abs(rawDelta.X) >= step then
							local steps = math.floor(math.abs(rawDelta.X) / step)
							local deltaSign = math.sign(rawDelta.X)
							local totalStepDelta = steps * step * deltaSign
							local pixelStep = totalStepDelta / (Props.Sensitivity or 0.25)

							Props.OnDragDelta(totalStepDelta)
							SetStartMousePos(Vector2.new(StartMousePos:getValue().X + pixelStep, StartMousePos:getValue().Y))
						end

					else
						if math.abs(rawDelta.Y) >= step then
							local steps = math.floor(math.abs(rawDelta.Y) / step)
							local deltaSign = math.sign(rawDelta.Y)
							local totalStepDelta = steps * step * deltaSign
							local pixelStep = totalStepDelta / (Props.Sensitivity or 0.25)

							Props.OnDragDelta(totalStepDelta)
							SetStartMousePos(Vector2.new(StartMousePos:getValue().X, StartMousePos:getValue().Y + pixelStep))
						end
					end
				end
			end,
		})
	})
end

----------------------------------------------------------
return UI_ComponentSDK :: UI_ComponentSDK
----------------------------------------------------------