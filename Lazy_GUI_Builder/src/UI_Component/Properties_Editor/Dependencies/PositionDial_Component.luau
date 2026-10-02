--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: PositionDial_Component.luau
    
    SCOPE: Feature UI Component Dependency
    
    ROLE: A composer component that arranges SDK Trackpad and PrecisionDial 
          widgets into a grid layout for visual UDim2 positioning.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PositionDial_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	CurrentPosition: UDim2,
	OnPositionChange: (NewPosition: UDim2) -> (),
	LayoutOrder: number?,
	LabelWidth: any,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PositionDial_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)
local AppState = require(script.Parent.Parent.Parent.Parent.Parent.src.AppState)
local Relay = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Relay.Relay)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PositionDial_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the Position Dial grid composed of Trackpad and Precision Dials.

Params:
    Props: Props -- Component props

Returns:
    any -- The PositionDial React component
]]
local function PositionDial_Component(Props: Props): any
	local StartPosRef = React.useRef(Props.CurrentPosition)
	local ExactOffsetRef = React.useRef(Vector2.new(Props.CurrentPosition.X.Offset, Props.CurrentPosition.Y.Offset))

	local function handleDragStart(): ()
		StartPosRef.current = Props.CurrentPosition
		ExactOffsetRef.current = Vector2.new(Props.CurrentPosition.X.Offset, Props.CurrentPosition.Y.Offset)
	end

	local function handleDragDelta(DeltaX: number, DeltaY: number, IsTrackpad: boolean?): ()
		local start = StartPosRef.current :: UDim2
		local Settings = AppState.SessionState.PositionEditorSettings
		
		local multiplierX = if IsTrackpad then Settings.TrackpadSensitivity else Settings.XDialSensitivity
		local multiplierY = if IsTrackpad then Settings.TrackpadSensitivity else Settings.YDialSensitivity
		
		local newExactX = (ExactOffsetRef.current :: Vector2).X + (DeltaX * multiplierX)
		local newExactY = (ExactOffsetRef.current :: Vector2).Y + (DeltaY * multiplierY)
		
		ExactOffsetRef.current = Vector2.new(newExactX, newExactY)
		Props.OnPositionChange(UDim2.new(start.X.Scale, math.round(newExactX), start.Y.Scale, math.round(newExactY)))
	end

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 124), -- 120px + 4px padding
		BackgroundTransparency = 1,
		LayoutOrder = Props.LayoutOrder,
	}, {
		EditorContainer = React.createElement("Frame", {
			Size = Props.LabelWidth:map(function(w: number): UDim2
				return UDim2.new(1, -(w + 3), 1, 0)
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

		-- Top Row: X Dial + Holder
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
				Value = Props.CurrentPosition.X.Offset,
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
				Text = "\u{2699}", -- Gear icon
				TextColor3 = Color3.fromRGB(180, 180, 180),
				TextSize = 14,
				Font = Enum.Font.Gotham,
				AutoButtonColor = true,
				
				[React.Event.Activated] = function()
					Relay.Create("TogglePositionSettings"):Fire()
				end,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4)
				})
			}),
		}),

		-- Bottom Row: Trackpad + Y Dial
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
				Value = Props.CurrentPosition.Y.Offset,
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
return PositionDial_Component
----------------------------------------------------------