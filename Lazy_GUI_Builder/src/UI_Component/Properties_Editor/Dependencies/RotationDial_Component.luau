--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: RotationDial_Component.luau
    
    SCOPE: Feature UI Component Dependency
    
    ROLE: A composer component that arranges a single SDK PrecisionDial 
          and a settings button for modifying Rotation.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- RotationDial_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	CurrentRotation: number,
	OnRotationChange: (NewRotation: number) -> (),
	LayoutOrder: number?,
	LabelWidth: any,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- RotationDial_Component Dependency Section
----------------------------------------------------------
local AppState = require(script.Parent.Parent.Parent.Parent.Parent.src.AppState)
local React = require(script.Parent.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- RotationDial_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the Rotation Dial composed of a single PrecisionDial and Settings button.

Params:
    Props: Props -- Component props

Returns:
    any -- The RotationDial React component
]]
local function RotationDial_Component(Props: Props): any
	local StartRotationRef: any = React.useRef(Props.CurrentRotation)
	local ExactRotationRef: any = React.useRef(Props.CurrentRotation)

	-- Caches the starting rotation and exact offset when a drag session begins.
	local function handleDragStart(): ()
		StartRotationRef.current = Props.CurrentRotation
		ExactRotationRef.current = Props.CurrentRotation
	end

	-- Calculates and applies the new rotation based on the drag delta.
	local function handleDragDelta(DeltaX: number): ()
		local Multiplier: number = AppState.SessionState.RotationEditorSettings.DialSensitivity
		local EffectiveDelta: number = DeltaX * Multiplier
		local NewExact: number = ExactRotationRef.current + EffectiveDelta
		
		-- Optional: Keep within -360 to 360, or let it exceed. Rotation in Roblox can be anything, 
        -- but modulo 360 is common. Let's just let it act naturally like the other dials.
		ExactRotationRef.current = NewExact
		Props.OnRotationChange(math.round(NewExact))
	end

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 0, 24), -- 20px dial + 4px padding below
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
				FillDirection = Enum.FillDirection.Horizontal,
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 4),
			}),

			Dial = React.createElement(UI_ComponentSDK.PrecisionDial, {
				Size = UDim2.new(1, -24, 1, 0),
				Value = Props.CurrentRotation,
				Axis = "X",
				LayoutOrder = 1,
				
				OnDragStart = handleDragStart,
				OnDragDelta = handleDragDelta,
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
					Relay.Create("ToggleRotationSettings"):Fire()
				end,
			}, {
				Corner = React.createElement("UICorner", { 
					CornerRadius = UDim.new(0, 4),
				}),
			}),
		}),
	})
end

----------------------------------------------------------
return RotationDial_Component
----------------------------------------------------------