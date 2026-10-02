--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Color3Editor_Component.luau
    
    SCOPE: Feature UI Component Dependency
    
    ROLE: Renders the Color3 swatch button and RGB text input in the property 
          row, communicates with ColorPickerWindow_Component via Relay, and 
          ensures complete unmount cleanup.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type Props = {
	CurrentValue: Color3?,
	IsModifier: boolean?,
	OnSubmit: (Color3) -> (),
	OnPreview: ((Color3) -> ())?,
	OnCommit: ((FinalColor: Color3, InitialColor: Color3) -> ())?,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Imported Services Section
----------------------------------------------------------
local HttpService: HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Relay.Relay)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Renders the Color3 swatch button and text input in the property row.

Params:
    Props: Props -- Component props

Returns:
    any -- React element
]]
local function Color3Editor_Component(Props: Props): any
	local Color: Color3 = Props.CurrentValue or Color3.new(1, 1, 1)
	local ActiveCallbackIdRef = React.useRef(nil :: string?)
	local CleanupRef = React.useRef(nil :: (() -> ())?)
	local FieldBg: Color3 = if Props.IsModifier then Color3.fromRGB(30, 30, 30) else Color3.fromRGB(45, 45, 45)

	-- Component unmount lifecycle hook
	React.useEffect(function(): (() -> ())?
		return function(): ()
			if ActiveCallbackIdRef.current then
				Relay.Create("CloseColorPicker"):Fire({
					CallbackId = ActiveCallbackIdRef.current,
				})
			end

			if CleanupRef.current then
				CleanupRef.current()
			end
		end
	end, {})

	local function handleOpenEditor(): ()
		-- Force-close any open color picker session first to revert previews
		Relay.Create("CloseColorPicker"):Fire()

		if CleanupRef.current then
			CleanupRef.current()
		end
		
		local SubmitConn: Relay.ConnectionObject? = nil
		local CloseConn: Relay.ConnectionObject? = nil
		local LiveConn: Relay.ConnectionObject? = nil
		local CallbackId = HttpService:GenerateGUID(false)
		
		ActiveCallbackIdRef.current = CallbackId

		local function cleanup(): ()
			if SubmitConn then
				SubmitConn:Disconnect()
				SubmitConn = nil
			end

			if CloseConn then
				CloseConn:Disconnect()
				CloseConn = nil
			end

			if LiveConn then
				LiveConn:Disconnect()
				LiveConn = nil
			end

			if ActiveCallbackIdRef.current == CallbackId then
				ActiveCallbackIdRef.current = nil
				CleanupRef.current = nil
			end
		end

		CleanupRef.current = cleanup

		LiveConn = Relay.Create("ColorPickerLiveUpdate"):Connect(function(Data: any): ()
			if Data.CallbackId == CallbackId and Props.OnPreview then
				Props.OnPreview(Data.Color)
			end
		end)

		SubmitConn = Relay.Create("ColorPickerSubmitted"):Connect(function(Data: any): ()
			if Data.CallbackId == CallbackId then
				if Props.OnCommit then
					Props.OnCommit(Data.Color, Color)
					
				else
					Props.OnSubmit(Data.Color)
				end

				cleanup()
			end
		end)

		CloseConn = Relay.Create("CloseColorPicker"):Connect(function(Data: any): ()
			if not Data or not Data.CallbackId or Data.CallbackId == CallbackId then
				if Props.OnPreview then
					Props.OnPreview(Color)
				end

				cleanup()
			end
		end)

		Relay.Create("OpenColorPicker"):Fire({
			InitialColor = Color,
			CallbackId = CallbackId,
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundTransparency = 1,
	}, {
		Swatch = React.createElement("TextButton", {
			Size = UDim2.fromOffset(20, 20),
			Position = UDim2.new(0, 0, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = Color,
			Text = "",
			AutoButtonColor = false,

			[React.Event.Activated] = handleOpenEditor,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),

			Stroke = React.createElement("UIStroke", {
				Color = Color3.fromRGB(80, 80, 80),
			}),
		}),

		Input = React.createElement("TextBox", {
			Size = UDim2.new(1, -24, 1, 0),
			Position = UDim2.new(0, 24, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = FieldBg,
			Text = string.format("%d, %d, %d", math.round(Color.R * 255), math.round(Color.G * 255), math.round(Color.B * 255)),
			TextColor3 = Color3.fromRGB(220, 220, 220),
			TextXAlignment = Enum.TextXAlignment.Center,
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			ClearTextOnFocus = false,
			ClipsDescendants = true,

			[React.Event.FocusLost] = function(Rbx: Instance): ()
				local R, G, B = string.match((Rbx :: TextBox).Text, "(%d+)%D+(%d+)%D+(%d+)")

				;(Rbx :: TextBox).Text = string.format("%d, %d, %d", math.round(Color.R * 255), math.round(Color.G * 255), math.round(Color.B * 255))

				if R and G and B then
					Props.OnSubmit(Color3.fromRGB(
						math.clamp(tonumber(R) or 255, 0, 255),
						math.clamp(tonumber(G) or 255, 0, 255),
						math.clamp(tonumber(B) or 255, 0, 255)
					))
				end
			end,
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}),
	})
end

----------------------------------------------------------
return Color3Editor_Component
----------------------------------------------------------