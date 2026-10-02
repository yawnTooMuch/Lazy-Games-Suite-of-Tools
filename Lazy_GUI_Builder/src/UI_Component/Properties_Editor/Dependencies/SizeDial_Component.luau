--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: SizeDial_Component.luau
    
    SCOPE: Feature UI Component Dependency
    
    ROLE: A composer component that arranges SDK Trackpad and PrecisionDial 
          widgets into a grid layout for visual UDim2 sizing (Offset only).
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- SizeDial_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	CurrentSize: UDim2,
	OnSizeChange: (NewSize: UDim2) -> (),
	LayoutOrder: number?,
	LabelWidth: any,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- SizeDial_Component Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.Parent.Parent.Parent.src.AppState)
local React = require(script.Parent.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- SizeDial_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the Size Dial grid composed of Trackpad and Precision Dials.

Params:
    Props: Props -- Component props

Returns:
    any -- The SizeDial React component
]]
local function SizeDial_Component(Props: Props): any
	local StartSizeRef: any = React.useRef(Props.CurrentSize)
	local ExactOffsetRef: any = React.useRef(Vector2.new(Props.CurrentSize.X.Offset, Props.CurrentSize.Y.Offset))

	--[[
	Caches the starting size and exact offset when a drag session begins.
	]]
	local function handleDragStart(): ()
		StartSizeRef.current = Props.CurrentSize
		ExactOffsetRef.current = Vector2.new(Props.CurrentSize.X.Offset, Props.CurrentSize.Y.Offset)
	end

	--[[
	Calculates and applies the new size based on the drag delta.
	]]
	local function handleDragDelta(DeltaX: number, DeltaY: number, IsTrackpad: boolean?): ()
		local Start: UDim2 = StartSizeRef.current
		local Settings: AppState.SizeEditorSettings = AppState.SessionState.SizeEditorSettings
		
		local MultiplierX: number = if IsTrackpad then Settings.TrackpadSensitivity else Settings.WidthDialSensitivity
		local MultiplierY: number = if IsTrackpad then Settings.TrackpadSensitivity else Settings.HeightDialSensitivity
		
		local EffectiveDeltaX: number = DeltaX * MultiplierX
		local EffectiveDeltaY: number = DeltaY * MultiplierY
		
		local NewExactX: number = math.max(1, ExactOffsetRef.current.X + EffectiveDeltaX)
		local NewExactY: number = math.max(1, ExactOffsetRef.current.Y + EffectiveDeltaY)
		
		ExactOffsetRef.current = Vector2.new(NewExactX, NewExactY)
		Props.OnSizeChange(UDim2.new(Start.X.Scale, math.round(NewExactX), Start.Y.Scale, math.round(NewExactY)))
	end

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 124),
		BackgroundTransparency = 1,
		LayoutOrder = Props.LayoutOrder,
	}, {
		EditorContainer = React.createElement("Frame", {
			Size = Props.LabelWidth:map(function(Width: number): UDim2
				return UDim2.new(1, -(Width + 3), 1, 0)
			end),
			
			Position = UDim2.new(1, 0, 0, 0),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingBottom = UDim.new(0, 4),
			}),
		
			Layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Vertical,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),

			TopRow = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 20),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),

				XDial = React.createElement(UI_ComponentSDK.PrecisionDial, {
					Size = UDim2.new(1, -24, 1, 0),
					Value = Props.CurrentSize.X.Offset,
					Axis = "X",
					LayoutOrder = 1,
					
					OnDragStart = handleDragStart,
					OnDragDelta = function(Delta: number): ()
						handleDragDelta(Delta, 0, false)
					end,
				}),

				Holder = React.createElement("TextButton", {
					Size = UDim2.new(0, 20, 1, 0),
					BackgroundColor3 = Color3.fromRGB(35, 35, 35),
					LayoutOrder = 2,
					Text = "\u{2699}",
					TextColor3 = Color3.fromRGB(180, 180, 180),
					TextSize = 14,
					Font = Enum.Font.Gotham,
					AutoButtonColor = true,
					
					[React.Event.Activated] = function(): ()
						Relay.Create("ToggleSizeSettings"):Fire()
					end,
				}, {
					Corner = React.createElement("UICorner", { 
						CornerRadius = UDim.new(0, 4),
					}),
				}),
			}),

			BottomRow = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 100),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder = Enum.SortOrder.LayoutOrder,
					Padding = UDim.new(0, 4),
				}),

				Trackpad = React.createElement(UI_ComponentSDK.Trackpad, {
					Size = UDim2.new(1, -24, 1, 0),
					LayoutOrder = 1,
					
					OnDragStart = handleDragStart,
					OnDragDelta = function(DeltaX: number, DeltaY: number): ()
						handleDragDelta(DeltaX, DeltaY, true)
					end,
				}),

				YDial = React.createElement(UI_ComponentSDK.PrecisionDial, {
					Size = UDim2.new(0, 20, 1, 0),
					Value = Props.CurrentSize.Y.Offset,
					Axis = "Y",
					LayoutOrder = 2,
					
					OnDragStart = handleDragStart,
					OnDragDelta = function(Delta: number): ()
						handleDragDelta(0, Delta, false)
					end,
				}),
			}),
		}),
	})
end

----------------------------------------------------------
return SizeDial_Component
----------------------------------------------------------