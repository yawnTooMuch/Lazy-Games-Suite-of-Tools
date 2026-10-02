--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: GradientEditorWindow_Component.luau
    
    SCOPE: Root UI Component
    
    ROLE: Renders the standalone floating Gradient Editor window mounted 
          on the root viewport ScreenGui, with centered title, embedded 
          ColorPicker, eyedropper, preview swatch, and submit action.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- GradientEditorWindow_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- GradientEditorWindow_Component Imported Services Section
----------------------------------------------------------
local UserInputService: UserInputService = game:GetService("UserInputService")
local HttpService: HttpService = game:GetService("HttpService")
local CoreGui: CoreGui = game:GetService("CoreGui")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- GradientEditorWindow_Component Local Functions Section
----------------------------------------------------------

-- Helper to clone a list of keypoints
local function cloneKeypoints(Keypoints: { ColorSequenceKeypoint }): { ColorSequenceKeypoint }
	local Cloned: { ColorSequenceKeypoint } = {}
	
	for _, Kp in ipairs(Keypoints) do
		Cloned[#Cloned + 1] = ColorSequenceKeypoint.new(Kp.Time, Kp.Value)
	end
	
	return Cloned
end

-- Helper to construct a valid ColorSequence from a list of keypoints
local function buildColorSequence(Keypoints: { ColorSequenceKeypoint }): ColorSequence
	local Sorted = cloneKeypoints(Keypoints)
	
	table.sort(Sorted, function(a, b)
		return a.Time < b.Time
	end)
	
	-- Engine rules: first keypoint must be at 0, last keypoint must be at 1
	if #Sorted < 2 then
		return ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(100, 100, 100))
	end
	
	Sorted[1] = ColorSequenceKeypoint.new(0, Sorted[1].Value)
	Sorted[#Sorted] = ColorSequenceKeypoint.new(1, Sorted[#Sorted].Value)
	
	return ColorSequence.new(Sorted)
end

-- Interpolates a color between keypoints at a given time
local function interpolateColor(Keypoints: { ColorSequenceKeypoint }, TargetTime: number): Color3
	local PrevKP = Keypoints[1]
	local NextKP = Keypoints[#Keypoints]
	
	for i = 1, #Keypoints - 1 do
		if Keypoints[i].Time <= TargetTime and Keypoints[i + 1].Time >= TargetTime then
			PrevKP = Keypoints[i]
			NextKP = Keypoints[i + 1]
			
			break
		end
	end
	
	local Span = NextKP.Time - PrevKP.Time
	
	if Span <= 0 then
		return PrevKP.Value
	end
	
	local Alpha = (TargetTime - PrevKP.Time) / Span
	
	return PrevKP.Value:Lerp(NextKP.Value, Alpha)
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- GradientEditorWindow_Component Public APIs Section
----------------------------------------------------------

--[[
Renders the floating Gradient Editor window on the root ScreenGui.

Params:
    None

Returns:
    any -- React element
]]
local function GradientEditorWindow_Component(): any
	local DefaultSeq = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(100, 100, 100))
	local IsOpen: boolean, SetIsOpen = React.useState(false)
	local CallbackId: string, SetCallbackId = React.useState("")
	local ResetKey: string, SetResetKey = React.useState("")
	local WorkingKeypoints: { ColorSequenceKeypoint }, SetWorkingKeypoints = React.useState(cloneKeypoints(DefaultSeq.Keypoints))
	local SelectedIndex: number, SetSelectedIndex = React.useState(1)
	local TrackRef = React.useRef(nil :: GuiObject?)
	local DraggingPinIndex: number?, SetDraggingPinIndex = React.useState(nil :: number?)

	-- Eyedropper state
	local IsDraggingDropper: boolean, SetIsDraggingDropper = React.useState(false)
	local DropperPosition, SetDropperPosition = React.useBinding(UDim2.fromOffset(0, 0))
	local DropperHoverPosition, SetDropperHoverPosition = React.useBinding(UDim2.fromOffset(0, 0))
	local DropperHoverSize, SetDropperHoverSize = React.useBinding(UDim2.fromOffset(0, 0))
	local DropperHoverVisible, SetDropperHoverVisible = React.useBinding(false)

	-- Eyedropper drag & sampling handler
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
				if Element.Name == "GhostIcon" or Element.Name == "GhostDropper" or Element.Name == "GradientEditor_DropperHighlight" or Element.Name == "DropperHighlight" then
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
						local Updated = cloneKeypoints(WorkingKeypoints)
						
						if Updated[SelectedIndex] then
							Updated[SelectedIndex] = ColorSequenceKeypoint.new(Updated[SelectedIndex].Time, PickedColor)
							SetWorkingKeypoints(Updated)
							SetResetKey(HttpService:GenerateGUID(false))
							
							if CallbackId ~= "" then
								Relay.Create("GradientEditorLiveUpdate"):Fire({
									CallbackId = CallbackId,
									ColorSequence = buildColorSequence(Updated),
								})
							end
						end
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
	end, { IsDraggingDropper, WorkingKeypoints, SelectedIndex, CallbackId } :: { any })

	-- Listen for Open/Close signals
	React.useEffect(function(): (() -> ())?
		local OpenConn = Relay.Create("OpenGradientEditor"):Connect(function(Data: any): ()
			local Seq: ColorSequence = Data.InitialColorSequence or DefaultSeq
			
			SetCallbackId(Data.CallbackId or "")
			SetWorkingKeypoints(cloneKeypoints(Seq.Keypoints))
			SetSelectedIndex(1)
			SetResetKey(HttpService:GenerateGUID(false))
			SetIsOpen(true)
		end)
		
		local CloseConn = Relay.Create("CloseGradientEditor"):Connect(function(Data: any): ()
			if not Data or not Data.CallbackId or Data.CallbackId == CallbackId then
				SetIsOpen(false)
			end
		end)
		
		return function(): ()
			OpenConn:Disconnect()
			CloseConn:Disconnect()
		end
	end, { CallbackId } :: { any })

	-- Handles closing without saving (Cancel / Revert)
	local function handleCancel(): ()
		if CallbackId ~= "" then
			Relay.Create("CloseGradientEditor"):Fire({
				CallbackId = CallbackId,
			})
		end
		
		SetIsOpen(false)
	end

	-- Handles confirming changes (Apply / Commit)
	local function handleApply(): ()
		if CallbackId ~= "" then
			Relay.Create("GradientEditorSubmitted"):Fire({
				CallbackId = CallbackId,
				ColorSequence = buildColorSequence(WorkingKeypoints),
			})
		end
		
		SetIsOpen(false)
	end

	-- Handles color modification from embedded ColorPicker for the selected keypoint
	local function handleColorChanged(NewColor: Color3): ()
		local Updated = cloneKeypoints(WorkingKeypoints)
		
		if Updated[SelectedIndex] then
			Updated[SelectedIndex] = ColorSequenceKeypoint.new(Updated[SelectedIndex].Time, NewColor)
			SetWorkingKeypoints(Updated)
			
			if CallbackId ~= "" then
				Relay.Create("GradientEditorLiveUpdate"):Fire({
					CallbackId = CallbackId,
					ColorSequence = buildColorSequence(Updated),
				})
			end
		end
	end

	-- Handles adding a keypoint along the timeline track
	local function handleTrackClick(Rbx: Instance, Input: InputObject): ()
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if #WorkingKeypoints >= 20 then return end
			
			local RelX = math.clamp((Input.Position.X - (Rbx :: GuiObject).AbsolutePosition.X) / (Rbx :: GuiObject).AbsoluteSize.X, 0, 1)
			
			-- Disallow duplicate keypoint exactly at 0 or 1
			if RelX <= 0.02 or RelX >= 0.98 then return end
			
			local LerpedColor = interpolateColor(WorkingKeypoints, RelX)
			local Updated = cloneKeypoints(WorkingKeypoints)
			
			Updated[#Updated + 1] = ColorSequenceKeypoint.new(RelX, LerpedColor)
			
			table.sort(Updated, function(a, b)
				return a.Time < b.Time
			end)
			
			-- Find index of the newly added keypoint
			local NewIndex = 1
			
			for i, Kp in ipairs(Updated) do
				if math.abs(Kp.Time - RelX) < 0.001 then
					NewIndex = i
					
					break
				end
			end
			
			SetWorkingKeypoints(Updated)
			SetSelectedIndex(NewIndex)
			SetResetKey(HttpService:GenerateGUID(false))

			if CallbackId ~= "" then
				Relay.Create("GradientEditorLiveUpdate"):Fire({
					CallbackId = CallbackId,
					ColorSequence = buildColorSequence(Updated),
				})
			end
		end
	end

	-- Handles deleting the selected keypoint
	local function handleDeleteSelected(): ()
		if #WorkingKeypoints <= 2 then return end
		
		if SelectedIndex == 1 or SelectedIndex == #WorkingKeypoints then return end -- Cannot delete edge endpoints
		
		local Updated: { ColorSequenceKeypoint } = {}
		
		for i, Kp in ipairs(WorkingKeypoints) do
			if i ~= SelectedIndex then
				Updated[#Updated + 1] = Kp
			end
		end
		
		SetWorkingKeypoints(Updated)
		SetSelectedIndex(math.max(1, SelectedIndex - 1))
		SetResetKey(HttpService:GenerateGUID(false))

		if CallbackId ~= "" then
			Relay.Create("GradientEditorLiveUpdate"):Fire({
				CallbackId = CallbackId,
				ColorSequence = buildColorSequence(Updated),
			})
		end
	end

	-- Handles keypoint dragging movement
	React.useEffect(function(): (() -> ())?
		if DraggingPinIndex == nil or not IsOpen then return nil end
		
		local MoveConn = UserInputService.InputChanged:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement and TrackRef.current then
				local RelX = math.clamp((Input.Position.X - TrackRef.current.AbsolutePosition.X) / TrackRef.current.AbsoluteSize.X, 0, 1)
				
				-- Edge keypoints are locked to 0 and 1
				if DraggingPinIndex == 1 then
					RelX = 0
					
				elseif DraggingPinIndex == #WorkingKeypoints then
					RelX = 1
					
				else
					-- Keep keypoint strictly between 0.01 and 0.99
					RelX = math.clamp(RelX, 0.01, 0.99)
				end
				
				local Updated = cloneKeypoints(WorkingKeypoints)
				
				if Updated[DraggingPinIndex] then
					Updated[DraggingPinIndex] = ColorSequenceKeypoint.new(RelX, Updated[DraggingPinIndex].Value)
					SetWorkingKeypoints(Updated)
					
					if CallbackId ~= "" then
						Relay.Create("GradientEditorLiveUpdate"):Fire({
							CallbackId = CallbackId,
							ColorSequence = buildColorSequence(Updated),
						})
					end
				end
			end
		end)
		
		local ReleaseConn = UserInputService.InputEnded:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				SetDraggingPinIndex(nil)
			end
		end)
		
		return function(): ()
			MoveConn:Disconnect()
			ReleaseConn:Disconnect()
		end
	end, { DraggingPinIndex, WorkingKeypoints, TrackRef.current, IsOpen, CallbackId } :: { any })

	local CurrentWorkingSeq = buildColorSequence(WorkingKeypoints)
	local SelectedKP: ColorSequenceKeypoint = WorkingKeypoints[SelectedIndex] or WorkingKeypoints[1]
	local PinElements: { [string]: any } = {} -- Build pin elements along the timeline
	
	for Index, Kp in ipairs(WorkingKeypoints) do
		local IsSelected = (Index == SelectedIndex)
		
		PinElements["Pin_" .. tostring(Index)] = React.createElement("TextButton", {
			Size = UDim2.fromOffset(14, 18),
			Position = UDim2.new(Kp.Time, 0, 0, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Kp.Value,
			Text = "",
			AutoButtonColor = false,
			ZIndex = IsSelected and 4 or 2,
			
			[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					SetSelectedIndex(Index)
					SetResetKey(HttpService:GenerateGUID(false))
					
					if Index ~= 1 and Index ~= #WorkingKeypoints then
						SetDraggingPinIndex(Index)
					end
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 3),
			}),
			
			Stroke = React.createElement("UIStroke", {
				Color = IsSelected and Color3.fromRGB(0, 170, 255) or Color3.fromRGB(180, 180, 180),
				Thickness = IsSelected and 2 or 1,
			}),
		})
	end

	return React.createElement(React.Fragment, nil, {
		GradientEditor_Window = React.createElement(UI_ComponentSDK.DraggableWindow, {
			Title = "Gradient Editor",
			TitleAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(360, 308),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = IsOpen,
			ZIndex = 100,
			OnClose = handleCancel,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 10),
				PaddingBottom = UDim.new(0, 10),
				PaddingLeft = UDim.new(0, 10),
				PaddingRight = UDim.new(0, 10),
			}),

			-- Top Timeline Bar Section
			TimelineSection = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 46),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
			}, {
				-- Clickable Gradient Track
				Track = React.createElement("TextButton", {
					Size = UDim2.new(1, -16, 0, 20),
					Position = UDim2.new(0.5, 0, 0, 0),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
					Text = "",
					AutoButtonColor = false,
					ref = TrackRef,
					
					[React.Event.InputBegan] = handleTrackClick,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),
					
					Stroke = React.createElement("UIStroke", {
						Color = Color3.fromRGB(60, 60, 60),
					}),
					
					Gradient = React.createElement("UIGradient", {
						Color = CurrentWorkingSeq,
					}),
				}),

				-- Keypoint Pins Track
				PinsArea = React.createElement("Frame", {
					Size = UDim2.new(1, -16, 0, 20),
					Position = UDim2.new(0.5, 0, 0, 24),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundTransparency = 1,
					ClipsDescendants = false,
				}, PinElements),
			}),

			-- Keypoint Controls Bar
			ControlsBar = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 52),
				BackgroundColor3 = Color3.fromRGB(40, 40, 40),
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
				
				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
				}),
				
				Info = React.createElement("TextLabel", {
					Size = UDim2.new(0, 80, 1, 0),
					BackgroundTransparency = 1,
					Text = string.format("Stop #%d of %d", SelectedIndex, #WorkingKeypoints),
					TextColor3 = Color3.fromRGB(200, 200, 200),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),
				
				TimeLabel = React.createElement("TextLabel", {
					Size = UDim2.new(0, 40, 1, 0),
					Position = UDim2.new(0, 85, 0, 0),
					BackgroundTransparency = 1,
					Text = "Time:",
					TextColor3 = Color3.fromRGB(150, 150, 150),
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),
				
				TimeInput = React.createElement("TextBox", {
					Size = UDim2.fromOffset(50, 18),
					Position = UDim2.new(0, 130, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundColor3 = Color3.fromRGB(25, 25, 25),
					Text = string.format("%.2f", SelectedKP.Time),
					TextColor3 = Color3.fromRGB(220, 220, 220),
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Center,
					ClearTextOnFocus = false,
					
					[React.Event.FocusLost] = function(Rbx: Instance): ()
						local Num = tonumber((Rbx :: TextBox).Text)
						
						if Num and SelectedIndex ~= 1 and SelectedIndex ~= #WorkingKeypoints then
							local Updated = cloneKeypoints(WorkingKeypoints)
							
							Updated[SelectedIndex] = ColorSequenceKeypoint.new(math.clamp(Num, 0.01, 0.99), Updated[SelectedIndex].Value)
							SetWorkingKeypoints(Updated)
							
							if CallbackId ~= "" then
								Relay.Create("GradientEditorLiveUpdate"):Fire({
									CallbackId = CallbackId,
									ColorSequence = buildColorSequence(Updated),
								})
							end
						end
						
						(Rbx :: TextBox).Text = string.format("%.2f", SelectedKP.Time)
					end,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 3),
					}),
				}),
				
				DeleteButton = (SelectedIndex ~= 1 and SelectedIndex ~= #WorkingKeypoints and #WorkingKeypoints > 2) and React.createElement("TextButton", {
					Size = UDim2.fromOffset(80, 18),
					Position = UDim2.new(1, 0, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					BackgroundColor3 = Color3.fromRGB(160, 50, 50),
					Text = "Delete Stop",
					TextColor3 = Color3.fromRGB(255, 255, 255),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					
					[React.Event.Activated] = handleDeleteSelected,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 3),
					}),
				}),
			}),

			-- Embedded ColorPicker for Selected Stop (Flat baseline with Sidebar, SV Pad, and Hue Bar at 134px height)
			ColorPickerWrap = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 134),
				Position = UDim2.new(0, 0, 0, 82),
				BackgroundTransparency = 1,
			}, {
				Picker = React.createElement(UI_ComponentSDK.ColorPicker, {
					InitialColor = SelectedKP.Value,
					ResetKey = ResetKey,
					Size = UDim2.new(1, 0, 1, 0),
					OnColorChanged = handleColorChanged,
				}),
			}),

			-- Bottom Action Bar: Preview Swatch (Left) | Confirm Gradient (Middle) | Eyedropper (Right)
			PreviewFrame = React.createElement("Frame", {
				Size = UDim2.new(0, 60, 0, 30),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4),
				}),
				
				Stroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(60, 60, 60),
					Thickness = 1,
				}),
				
				Gradient = React.createElement("UIGradient", {
					Color = CurrentWorkingSeq,
				}),
			}),
			
			SubmitButton = React.createElement("TextButton", {
				Size = UDim2.new(1, -110, 0, 30),
				Position = UDim2.new(0, 70, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.fromRGB(0, 160, 255),
				Text = "Confirm Gradient",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextSize = 14,
				BorderSizePixel = 0,
				
				[React.Event.Activated] = handleApply,
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

		-- Eyedropper Ghost & Highlight Overlays
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
		
		GradientEditor_DropperHighlight = React.createElement("Frame", {
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
return GradientEditorWindow_Component
----------------------------------------------------------