--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ColorPickerWindow_Component.luau
    
    SCOPE: Root UI Component
    
    ROLE: Renders the standalone floating Color Picker window mounted on the
          root viewport ScreenGui, with HSV canvas/slider, hex input, eyedropper
          screen sampling tool, preview swatch, and submit action.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ColorPickerWindow_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ColorPickerWindow_Component Imported Services Section
----------------------------------------------------------
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ColorPickerWindow_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the color picker floating window.

Params:
    None

Returns:
    any -- The color picker React fragment
]]
local function ColorPickerWindow_Component(): any
	local IsOpen, SetIsOpen = React.useState(false)
	local InitialColor, SetInitialColor = React.useState(Color3.new(1, 1, 1))
	local CallbackId, SetCallbackId = React.useState("")
	local ResetKey, SetResetKey = React.useState("")
	local SelectedColor, SetSelectedColor = React.useState(Color3.new(1, 1, 1))
	local IsDraggingDropper, SetIsDraggingDropper = React.useState(false)
	local DropperPosition, SetDropperPosition = React.useBinding(UDim2.fromOffset(0, 0))
	local DropperHoverPosition, SetDropperHoverPosition = React.useBinding(UDim2.fromOffset(0, 0))
	local DropperHoverSize, SetDropperHoverSize = React.useBinding(UDim2.fromOffset(0, 0))
	local DropperHoverVisible, SetDropperHoverVisible = React.useBinding(false)
	
	React.useEffect(function(): (() -> ())?
		if not IsDraggingDropper then return nil end
		
		local InitialMouse: Vector2 = UserInputService:GetMouseLocation()
		local MoveConnection: RBXScriptConnection
		local EndConnection: RBXScriptConnection
		
		local function getDropperTarget(MouseX: number, MouseY: number, IsShiftHeld: boolean): GuiObject?
			local MainWorkspace: ScreenGui? = CoreGui:FindFirstChild("Lazy_GUI_Builder_MainWorkspace") :: ScreenGui?
			
			if not MainWorkspace then return nil end
			
			local HitObjects: { GuiObject } = {}
			local RenderOrderMap: { [GuiObject]: number } = {}
			local CurrentRenderIndex: number = 0
			local BestHit: GuiObject? = nil
			local HighestRenderIndex: number = -1
			
			local function traverseNode(Node: Instance): ()
				local Children: { { Obj: Instance, Index: number, ZIndex: number } } = {}
				
				for Index: number, Child: Instance in ipairs(Node:GetChildren()) do
					local ZIndex: number = 1
					
					if Child:IsA("GuiObject") then
						ZIndex = (Child :: GuiObject).ZIndex
					end
					
					Children[#Children + 1] = { 
						Obj = Child, 
						Index = Index, 
						ZIndex = ZIndex,
					}
				end
				
				table.sort(Children, function(A: { Obj: Instance, Index: number, ZIndex: number }, B: { Obj: Instance, Index: number, ZIndex: number }): boolean
					if A.ZIndex == B.ZIndex then
						return A.Index < B.Index
					end
					
					return A.ZIndex < B.ZIndex
				end)
				
				for _, ChildData: { Obj: Instance, Index: number, ZIndex: number } in ipairs(Children) do
					if ChildData.Obj:IsA("GuiObject") then
						CurrentRenderIndex += 1
						RenderOrderMap[ChildData.Obj :: GuiObject] = CurrentRenderIndex
					end
					
					traverseNode(ChildData.Obj)
				end
			end
			
			for _, Element: Instance in ipairs(MainWorkspace:GetDescendants()) do
				if Element.Name == "GhostIcon" or Element.Name == "GhostDropper" or Element.Name == "ColorPicker_DropperHighlight" or Element.Name == "DropperHighlight" then
					continue
				end
				
				if Element:IsA("GuiObject") then
					local GuiElement: GuiObject = Element :: GuiObject
					
					if GuiElement.Visible then
						if MouseX >= GuiElement.AbsolutePosition.X and MouseX <= GuiElement.AbsolutePosition.X + GuiElement.AbsoluteSize.X and MouseY >= GuiElement.AbsolutePosition.Y and MouseY <= GuiElement.AbsolutePosition.Y + GuiElement.AbsoluteSize.Y then
							local IsClippedOrHidden: boolean = false
							local CurrentAncestor: Instance? = GuiElement.Parent
							local HasValidTarget: boolean = false
							
							while CurrentAncestor and CurrentAncestor:IsA("GuiObject") do
								local AncestorGui: GuiObject = CurrentAncestor :: GuiObject
								
								if not AncestorGui.Visible then
									IsClippedOrHidden = true
									
									break
								end
								
								if AncestorGui.ClipsDescendants then
									local CX: number = AncestorGui.AbsolutePosition.X
									local CY: number = AncestorGui.AbsolutePosition.Y
									local CW: number = AncestorGui.AbsoluteSize.X
									local CH: number = AncestorGui.AbsoluteSize.Y
									
									if MouseX < CX or MouseX > CX + CW or MouseY < CY or MouseY > CY + CH then
										IsClippedOrHidden = true
										
										break
									end
								end
								
								CurrentAncestor = AncestorGui.Parent
							end
							
							if IsClippedOrHidden then continue end
							
							if IsShiftHeld then
								if GuiElement:IsA("TextLabel") or GuiElement:IsA("TextButton") or GuiElement:IsA("TextBox") then
									local TextElement: TextLabel | TextButton | TextBox = GuiElement :: TextLabel | TextButton | TextBox
									
									if TextElement.TextTransparency < 1 then
										if TextElement.Text and TextElement.Text:gsub("%s", "") ~= "" then
											HasValidTarget = true
										end
									end
									
								elseif GuiElement:IsA("ImageLabel") or GuiElement:IsA("ImageButton") then
									local ImageElement: ImageLabel | ImageButton = GuiElement :: ImageLabel | ImageButton
									
									if ImageElement.ImageTransparency < 1 then
										if ImageElement.Image and ImageElement.Image:gsub("%s", "") ~= "" then
											HasValidTarget = true
										end
									end
								end
								
							else
								if GuiElement.BackgroundTransparency < 1 then
									HasValidTarget = true
									
								elseif GuiElement:IsA("ImageLabel") or GuiElement:IsA("ImageButton") then
									local ImageElement: ImageLabel | ImageButton = GuiElement :: ImageLabel | ImageButton
									
									if ImageElement.ImageTransparency < 1 then
										HasValidTarget = true
									end
								end
							end
							
							if HasValidTarget then
								HitObjects[#HitObjects + 1] = GuiElement
							end
						end
					end
				end
			end
			
			traverseNode(MainWorkspace)
			
			for _, Element: GuiObject in ipairs(HitObjects) do
				local RenderIndex: number = RenderOrderMap[Element] or -1
				
				if RenderIndex > HighestRenderIndex then
					HighestRenderIndex = RenderIndex
					BestHit = Element
				end
			end
			
			return BestHit
		end
		
		local function onInputChanged(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				local IsShiftHeld: boolean = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				local BestHit: GuiObject? = getDropperTarget(Input.Position.X, Input.Position.Y, IsShiftHeld)
				
				SetDropperPosition(UDim2.fromOffset(Input.Position.X, Input.Position.Y))
				
				if BestHit then
					SetDropperHoverPosition(UDim2.fromOffset(BestHit.AbsolutePosition.X, BestHit.AbsolutePosition.Y))
					SetDropperHoverSize(UDim2.fromOffset(BestHit.AbsoluteSize.X, BestHit.AbsoluteSize.Y))
					SetDropperHoverVisible(true)
					
				else
					SetDropperHoverVisible(false)
				end
			end
		end
		
		local function onInputEnded(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				local IsShiftHeld: boolean = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				local BestHit: GuiObject? = getDropperTarget(Input.Position.X, Input.Position.Y, IsShiftHeld)
				
				SetIsDraggingDropper(false)
				SetDropperHoverVisible(false)
				
				if BestHit then
					local PickedColor: Color3? = nil
					
					if IsShiftHeld then
						if BestHit:IsA("TextLabel") or BestHit:IsA("TextButton") or BestHit:IsA("TextBox") then
							local TextElement: TextLabel | TextButton | TextBox = BestHit :: TextLabel | TextButton | TextBox
							
							if TextElement.Text and TextElement.Text:gsub("%s", "") ~= "" then
								PickedColor = TextElement.TextColor3
							end
							
						elseif BestHit:IsA("ImageLabel") or BestHit:IsA("ImageButton") then
							local ImageElement: ImageLabel | ImageButton = BestHit :: ImageLabel | ImageButton
							
							if ImageElement.Image and ImageElement.Image:gsub("%s", "") ~= "" then
								PickedColor = ImageElement.ImageColor3
							end
						end
						
					else
						if BestHit.BackgroundTransparency < 1 then
							PickedColor = BestHit.BackgroundColor3
							
						elseif BestHit:IsA("ImageLabel") or BestHit:IsA("ImageButton") then
							local ImageElement: ImageLabel | ImageButton = BestHit :: ImageLabel | ImageButton
							
							PickedColor = ImageElement.ImageColor3
						end
					end
					
					if PickedColor then
						SetInitialColor(PickedColor)
						SetResetKey(HttpService:GenerateGUID(false))
					end
				end
			end
		end
		
		MoveConnection = UserInputService.InputChanged:Connect(onInputChanged)
		EndConnection = UserInputService.InputEnded:Connect(onInputEnded)
		
		SetDropperPosition(UDim2.fromOffset(InitialMouse.X, InitialMouse.Y - 36))
		
		return function(): ()
			MoveConnection:Disconnect()
			EndConnection:Disconnect()
		end
	end, {IsDraggingDropper} :: {any})
	
	React.useEffect(function(): (() -> ())?
		local OpenConnection: any
		local CloseConnection: any
		
		OpenConnection = Relay.Create("OpenColorPicker"):Connect(function(Data: { InitialColor: Color3, CallbackId: string }): ()
			SetInitialColor(Data.InitialColor)
			SetSelectedColor(Data.InitialColor)
			SetCallbackId(Data.CallbackId)
			SetResetKey(HttpService:GenerateGUID(false))
			SetIsOpen(true)
		end)
		
		CloseConnection = Relay.Create("CloseColorPicker"):Connect(function(Data: any): ()
			SetIsOpen(false)
		end)
		
		return function(): ()
			OpenConnection:Disconnect()
			CloseConnection:Disconnect()
		end
	end, {})
	
	return React.createElement(React.Fragment, nil, {
		ColorPicker_Window = React.createElement(UI_ComponentSDK.DraggableWindow, {
			Title = "Color Picker",
			TitleAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(360, 224),
			Visible = IsOpen,
			ZIndex = 100,
			
			OnClose = function(): ()
				Relay.Create("CloseColorPicker"):Fire({
					CallbackId = CallbackId,
				})
			end,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),
			
			ColorPicker = React.createElement(UI_ComponentSDK.ColorPicker, {
				InitialColor = InitialColor,
				ResetKey = ResetKey,
				Size = UDim2.new(1, 0, 1, -40),
				
				OnColorChanged = function(NewColor: Color3): ()
					SetSelectedColor(NewColor)
					
					if CallbackId ~= "" then
						Relay.Create("ColorPickerLiveUpdate"):Fire({
							CallbackId = CallbackId,
							Color = NewColor,
						})
					end
				end,
			}),
			
			PreviewFrame = React.createElement("Frame", {
				Size = UDim2.new(0, 60, 0, 30),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = SelectedColor,
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4),
				}),
				
				Stroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(60, 60, 60),
					Thickness = 1,
				}),
			}),
			
			SubmitButton = React.createElement("TextButton", {
				Size = UDim2.new(1, -110, 0, 30),
				Position = UDim2.new(0, 70, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.fromRGB(0, 160, 255),
				Text = "Confirm Color",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				BorderSizePixel = 0,
				
				[React.Event.Activated] = function(): ()
					if CallbackId ~= "" then
						Relay.Create("ColorPickerSubmitted"):Fire({
							CallbackId = CallbackId,
							Color = SelectedColor,
						})
					end
					
					SetIsOpen(false)
				end,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4),
				}),
			}),
			
			EyeDropperButton = React.createElement("TextButton", {
				Size = UDim2.new(0, 30, 0, 30),
				Position = UDim2.new(1, 0, 1, 0),
				AnchorPoint = Vector2.new(1, 1),
				BackgroundColor3 = Color3.fromRGB(45, 45, 45),
				Text = "🖍",
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.Gotham,
				TextSize = 14,
				BorderSizePixel = 0,
				
				[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						SetIsDraggingDropper(true)
					end
				end,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4),
				}),
				
				Stroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(60, 60, 60),
					Thickness = 1,
				}),
			}),
		}),
		
		GhostDropper = IsDraggingDropper and React.createElement("Frame", {
			Size = UDim2.fromOffset(30, 30),
			Position = DropperPosition,
			AnchorPoint = Vector2.new(0.2, 0.8),
			BackgroundTransparency = 1,
			ZIndex = 100000,
		}, {
			GhostIcon = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text = "🖍️",
				TextColor3 = Color3.new(1, 1, 1),
				Font = Enum.Font.Gotham,
				TextSize = 14,
			}),
		}),
		
		ColorPicker_DropperHighlight = React.createElement("Frame", {
			Position = DropperHoverPosition,
			Size = DropperHoverSize,
			Visible = DropperHoverVisible,
			BackgroundTransparency = 1,
			ZIndex = 100000,
		}, {
			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(0, 170, 255),
				Thickness = 2,
			}),
		}),
	})
end

----------------------------------------------------------
return ColorPickerWindow_Component
----------------------------------------------------------