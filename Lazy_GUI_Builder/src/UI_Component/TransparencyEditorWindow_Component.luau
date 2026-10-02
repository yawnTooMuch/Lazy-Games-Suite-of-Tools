--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: TransparencyEditorWindow_Component.luau
    
    SCOPE: Root UI Component
    
    ROLE: Renders the standalone floating Transparency Editor window mounted 
          on the root viewport ScreenGui, with centered title, draggable keypoints,
          opacity slider, live preview swatch, and submit action.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- TransparencyEditorWindow_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- TransparencyEditorWindow_Component Imported Services Section
----------------------------------------------------------
local UserInputService: UserInputService = game:GetService("UserInputService")
local HttpService: HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- TransparencyEditorWindow_Component Local Functions Section
----------------------------------------------------------

-- Helper to clone a list of keypoints
local function cloneKeypoints(Keypoints: { NumberSequenceKeypoint }): { NumberSequenceKeypoint }
	local Cloned: { NumberSequenceKeypoint } = {}
	
	for _, Kp in ipairs(Keypoints) do
		Cloned[#Cloned + 1] = NumberSequenceKeypoint.new(Kp.Time, Kp.Value)
	end
	
	return Cloned
end

-- Helper to construct a valid NumberSequence from a list of keypoints
local function buildNumberSequence(Keypoints: { NumberSequenceKeypoint }): NumberSequence
	local Sorted = cloneKeypoints(Keypoints)
	
	table.sort(Sorted, function(a, b)
		return a.Time < b.Time
	end)
	
	-- Engine rules: first keypoint must be at 0, last keypoint must be at 1
	if #Sorted < 2 then
		return NumberSequence.new(0)
	end
	
	Sorted[1] = NumberSequenceKeypoint.new(0, Sorted[1].Value)
	Sorted[#Sorted] = NumberSequenceKeypoint.new(1, Sorted[#Sorted].Value)
	
	return NumberSequence.new(Sorted)
end

-- Interpolates a numeric value between keypoints at a given time
local function interpolateValue(Keypoints: { NumberSequenceKeypoint }, TargetTime: number): number
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
	
	return PrevKP.Value + (NextKP.Value - PrevKP.Value) * Alpha
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- TransparencyEditorWindow_Component Public APIs Section
----------------------------------------------------------

--[[
Renders the floating Transparency Editor window on the root ScreenGui.

Params:
    None

Returns:
    any -- React element
]]
local function TransparencyEditorWindow_Component(): any
	local DefaultSeq = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0)})
	local IsOpen: boolean, SetIsOpen = React.useState(false)
	local CallbackId: string, SetCallbackId = React.useState("")
	local WorkingKeypoints: { NumberSequenceKeypoint }, SetWorkingKeypoints = React.useState(cloneKeypoints(DefaultSeq.Keypoints))
	local SelectedIndex: number, SetSelectedIndex = React.useState(1)
	local TrackRef = React.useRef(nil :: GuiObject?)
	local SliderTrackRef = React.useRef(nil :: GuiObject?)
	local DraggingPinIndex: number?, SetDraggingPinIndex = React.useState(nil :: number?)
	local IsDraggingSlider: boolean, SetIsDraggingSlider = React.useState(false)

	-- Listen for Open/Close signals
	React.useEffect(function(): (() -> ())?
		local OpenConn = Relay.Create("OpenTransparencyEditor"):Connect(function(Data: any): ()
			local Seq: NumberSequence = Data.InitialNumberSequence or DefaultSeq
			
			SetCallbackId(Data.CallbackId or "")
			SetWorkingKeypoints(cloneKeypoints(Seq.Keypoints))
			SetSelectedIndex(1)
			SetIsOpen(true)
		end)
		
		local CloseConn = Relay.Create("CloseTransparencyEditor"):Connect(function(Data: any): ()
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
			Relay.Create("CloseTransparencyEditor"):Fire({
				CallbackId = CallbackId,
			})
		end
		
		SetIsOpen(false)
	end

	-- Handles confirming changes (Apply / Commit)
	local function handleApply(): ()
		local FinalSeq = buildNumberSequence(WorkingKeypoints)
		
		if CallbackId ~= "" then
			Relay.Create("TransparencyEditorSubmitted"):Fire({
				CallbackId = CallbackId,
				NumberSequence = FinalSeq,
			})
		end
		
		SetIsOpen(false)
	end

	-- Handles modifying transparency value of the selected keypoint
	local function handleTransparencyChanged(NewVal: number): ()
		local Updated = cloneKeypoints(WorkingKeypoints)
		
		if Updated[SelectedIndex] then
			Updated[SelectedIndex] = NumberSequenceKeypoint.new(Updated[SelectedIndex].Time, math.clamp(NewVal, 0, 1))
			SetWorkingKeypoints(Updated)

			if CallbackId ~= "" then
				Relay.Create("TransparencyEditorLiveUpdate"):Fire({
					CallbackId = CallbackId,
					NumberSequence = buildNumberSequence(Updated),
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
			
			local Updated = cloneKeypoints(WorkingKeypoints)
			
			Updated[#Updated + 1] = NumberSequenceKeypoint.new(RelX, interpolateValue(WorkingKeypoints, RelX))
			
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

			if CallbackId ~= "" then
				Relay.Create("TransparencyEditorLiveUpdate"):Fire({
					CallbackId = CallbackId,
					NumberSequence = buildNumberSequence(Updated),
				})
			end
		end
	end

	-- Handles deleting the selected keypoint
	local function handleDeleteSelected(): ()
		if #WorkingKeypoints <= 2 then return end
		
		if SelectedIndex == 1 or SelectedIndex == #WorkingKeypoints then return end -- Cannot delete edge endpoints
		
		local Updated: { NumberSequenceKeypoint } = {}
		
		for i, Kp in ipairs(WorkingKeypoints) do
			if i ~= SelectedIndex then
				Updated[#Updated + 1] = Kp
			end
		end
		
		SetWorkingKeypoints(Updated)
		SetSelectedIndex(math.max(1, SelectedIndex - 1))

		if CallbackId ~= "" then
			Relay.Create("TransparencyEditorLiveUpdate"):Fire({
				CallbackId = CallbackId,
				NumberSequence = buildNumberSequence(Updated),
			})
		end
	end

	-- Handles keypoint pin dragging
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
					RelX = math.clamp(RelX, 0.01, 0.99)
				end
				
				local Updated = cloneKeypoints(WorkingKeypoints)
				
				if Updated[DraggingPinIndex] then
					Updated[DraggingPinIndex] = NumberSequenceKeypoint.new(RelX, Updated[DraggingPinIndex].Value)
					SetWorkingKeypoints(Updated)

					if CallbackId ~= "" then
						Relay.Create("TransparencyEditorLiveUpdate"):Fire({
							CallbackId = CallbackId,
							NumberSequence = buildNumberSequence(Updated),
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

	-- Handles transparency slider mouse dragging
	React.useEffect(function(): (() -> ())?
		if not IsDraggingSlider or not IsOpen then return nil end
		
		local MoveConn = UserInputService.InputChanged:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement and SliderTrackRef.current then
				local RelX = math.clamp((Input.Position.X - SliderTrackRef.current.AbsolutePosition.X) / SliderTrackRef.current.AbsoluteSize.X, 0, 1)
				
				handleTransparencyChanged(RelX)
			end
		end)
		
		local ReleaseConn = UserInputService.InputEnded:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				SetIsDraggingSlider(false)
			end
		end)
		
		return function(): ()
			MoveConn:Disconnect()
			ReleaseConn:Disconnect()
		end
	end, { IsDraggingSlider, WorkingKeypoints, SelectedIndex, SliderTrackRef.current, IsOpen, CallbackId } :: { any })

	local CurrentWorkingSeq = buildNumberSequence(WorkingKeypoints)
	local SelectedKP: NumberSequenceKeypoint = WorkingKeypoints[SelectedIndex] or WorkingKeypoints[1]
	local PinElements: { [string]: any } = {} -- Build pin elements along the timeline
	
	for Index, Kp in ipairs(WorkingKeypoints) do
		local IsSelected = (Index == SelectedIndex)
		local Grayscale = 1 - Kp.Value
		
		PinElements["Pin_" .. tostring(Index)] = React.createElement("TextButton", {
			Size = UDim2.fromOffset(14, 18),
			Position = UDim2.new(Kp.Time, 0, 0, 0),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = Color3.new(Grayscale, Grayscale, Grayscale),
			Text = "",
			AutoButtonColor = false,
			ZIndex = IsSelected and 4 or 2,
			
			[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
				if Input.UserInputType == Enum.UserInputType.MouseButton1 then
					SetSelectedIndex(Index)
					
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
		TransparencyEditor_Window = React.createElement(UI_ComponentSDK.DraggableWindow, {
			Title = "Transparency Editor",
			TitleAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(300, 182),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			Visible = IsOpen,
			ZIndex = 100,
			OnClose = handleCancel,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 8),
				PaddingBottom = UDim.new(0, 8),
				PaddingLeft = UDim.new(0, 8),
				PaddingRight = UDim.new(0, 8),
			}),

			-- Top Timeline Bar Section
			TimelineSection = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 40),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
			}, {
				-- Checkerboard / Dark background for transparency visibility
				TrackBg = React.createElement("Frame", {
					Size = UDim2.new(1, -12, 0, 18),
					Position = UDim2.new(0.5, 0, 0, 0),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundColor3 = Color3.fromRGB(20, 20, 20),
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),
					
					-- Clickable Gradient Track (renders opacity ramp)
					Track = React.createElement("TextButton", {
						Size = UDim2.fromScale(1, 1),
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
							Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
							Transparency = CurrentWorkingSeq,
						}),
					}),
				}),

				-- Keypoint Pins Track
				PinsArea = React.createElement("Frame", {
					Size = UDim2.new(1, -12, 0, 18),
					Position = UDim2.new(0.5, 0, 0, 22),
					AnchorPoint = Vector2.new(0.5, 0),
					BackgroundTransparency = 1,
					ClipsDescendants = false,
				}, PinElements),
			}),

			-- Keypoint Controls Bar
			ControlsBar = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 24),
				Position = UDim2.new(0, 0, 0, 46),
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
					Size = UDim2.new(0, 75, 1, 0),
					BackgroundTransparency = 1,
					Text = string.format("Stop #%d of %d", SelectedIndex, #WorkingKeypoints),
					TextColor3 = Color3.fromRGB(200, 200, 200),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				-- Centered Time Controls Group (Ensures identical left & right gaps)
				TimeContainer = React.createElement("Frame", {
					Size = UDim2.fromOffset(78, 20),
					Position = UDim2.fromScale(0.5, 0.5),
					AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundTransparency = 1,
				}, {
					TimeLabel = React.createElement("TextLabel", {
						Size = UDim2.new(0, 32, 1, 0),
						Position = UDim2.new(0, 0, 0, 0),
						BackgroundTransparency = 1,
						Text = "Time:",
						TextColor3 = Color3.fromRGB(150, 150, 150),
						Font = Enum.Font.Gotham,
						TextSize = 11,
						TextXAlignment = Enum.TextXAlignment.Left,
					}),
					
					TimeInput = React.createElement("TextBox", {
						Size = UDim2.fromOffset(42, 18),
						Position = UDim2.new(1, 0, 0.5, 0),
						AnchorPoint = Vector2.new(1, 0.5),
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
								
								Updated[SelectedIndex] = NumberSequenceKeypoint.new(math.clamp(Num, 0.01, 0.99), Updated[SelectedIndex].Value)
								SetWorkingKeypoints(Updated)

								if CallbackId ~= "" then
									Relay.Create("TransparencyEditorLiveUpdate"):Fire({
										CallbackId = CallbackId,
										NumberSequence = buildNumberSequence(Updated),
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
				}),
				
				DeleteButton = (SelectedIndex ~= 1 and SelectedIndex ~= #WorkingKeypoints and #WorkingKeypoints > 2) and React.createElement("TextButton", {
					Size = UDim2.fromOffset(74, 18),
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

			-- Selected Stop Transparency Slider Section
			SliderSection = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 26),
				Position = UDim2.new(0, 0, 0, 76),
				BackgroundColor3 = Color3.fromRGB(35, 35, 35),
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),

				Padding = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0, 6),
					PaddingRight = UDim.new(0, 6),
				}),
				
				Label = React.createElement("TextLabel", {
					Size = UDim2.new(0, 80, 1, 0),
					Position = UDim2.new(0, 0, 0, 0),
					BackgroundTransparency = 1,
					Text = "Transparency:",
					TextColor3 = Color3.fromRGB(180, 180, 180),
					Font = Enum.Font.GothamBold,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				-- Horizontal Slider Track
				Track = React.createElement("TextButton", {
					Size = UDim2.new(1, -132, 0, 6),
					Position = UDim2.new(0, 84, 0.5, 0),
					AnchorPoint = Vector2.new(0, 0.5),
					BackgroundColor3 = Color3.fromRGB(20, 20, 20),
					Text = "",
					AutoButtonColor = false,
					ref = SliderTrackRef,
					
					[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
						if Input.UserInputType == Enum.UserInputType.MouseButton1 then
							SetIsDraggingSlider(true)

							local RelX = math.clamp((Input.Position.X - (Rbx :: GuiObject).AbsolutePosition.X) / (Rbx :: GuiObject).AbsoluteSize.X, 0, 1)
							
							handleTransparencyChanged(RelX)
						end
					end,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(1, 0),
					}),
					
					Fill = React.createElement("Frame", {
						Size = UDim2.fromScale(SelectedKP.Value, 1),
						BackgroundColor3 = Color3.fromRGB(0, 160, 255),
						BorderSizePixel = 0,
					}, {
						Corner = React.createElement("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
					}),
					
					Marker = React.createElement("Frame", {
						Size = UDim2.fromOffset(12, 12),
						Position = UDim2.new(SelectedKP.Value, 0, 0.5, 0),
						AnchorPoint = Vector2.new(0.5, 0.5),
						BackgroundColor3 = Color3.fromRGB(240, 240, 240),
						ZIndex = 2,
					}, {
						Corner = React.createElement("UICorner", {
							CornerRadius = UDim.new(1, 0),
						}),
						
						Stroke = React.createElement("UIStroke", {
							Color = Color3.fromRGB(40, 40, 40),
						}),
					}),
				}),

				-- Numeric input for Transparency
				ValueInput = React.createElement("TextBox", {
					Size = UDim2.fromOffset(42, 18),
					Position = UDim2.new(1, 0, 0.5, 0),
					AnchorPoint = Vector2.new(1, 0.5),
					BackgroundColor3 = Color3.fromRGB(20, 20, 20),
					Text = string.format("%.2f", SelectedKP.Value),
					TextColor3 = Color3.fromRGB(220, 220, 220),
					Font = Enum.Font.Gotham,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Center,
					ClearTextOnFocus = false,
					
					[React.Event.FocusLost] = function(Rbx: Instance): ()
						local Num = tonumber((Rbx :: TextBox).Text)
						
						if Num then
							handleTransparencyChanged(Num)
						end
						
						(Rbx :: TextBox).Text = string.format("%.2f", SelectedKP.Value)
					end,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 3),
					}),
				}),
			}),

			-- Bottom Action Bar: Preview Swatch (Left) | Confirm Button (Right)
			PreviewFrame = React.createElement("Frame", {
				Size = UDim2.new(0, 52, 0, 26),
				Position = UDim2.new(0, 0, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.fromRGB(20, 20, 20),
				BorderSizePixel = 0,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4),
				}),
				
				Stroke = React.createElement("UIStroke", {
					Color = Color3.fromRGB(60, 60, 60),
					Thickness = 1,
				}),
				
				Ramp = React.createElement("Frame", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				}, {
					Corner = React.createElement("UICorner", { 
						CornerRadius = UDim.new(0, 4),
					}),
					
					Gradient = React.createElement("UIGradient", {
						Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
						Transparency = CurrentWorkingSeq,
					}),
				}),
			}),
			
			SubmitButton = React.createElement("TextButton", {
				Size = UDim2.new(1, -58, 0, 26),
				Position = UDim2.new(0, 58, 1, 0),
				AnchorPoint = Vector2.new(0, 1),
				BackgroundColor3 = Color3.fromRGB(0, 160, 255),
				Text = "Confirm Transparency",
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				BorderSizePixel = 0,
				
				[React.Event.Activated] = handleApply,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4),
				}),
			}),
		}),
	})
end

----------------------------------------------------------
return TransparencyEditorWindow_Component
----------------------------------------------------------