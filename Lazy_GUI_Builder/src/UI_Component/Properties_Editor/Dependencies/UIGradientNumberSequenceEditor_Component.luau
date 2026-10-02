--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: UIGradientNumberSequenceEditor_Component.luau
    
    SCOPE: Feature UI Component Dependency
    
    ROLE: Renders the NumberSequence swatch button in the property row and 
          communicates with the root TransparencyEditorWindow_Component via Relay.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type Props = {
	CurrentValue: NumberSequence?,
	OnSubmit: (NumberSequence) -> (),
	OnPreview: ((NumberSequence) -> ())?,
	OnCommit: ((FinalSequence: NumberSequence, InitialSequence: NumberSequence) -> ())?,
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
Renders the NumberSequence opacity swatch button in the property row.

Params:
    Props: Props -- Component props

Returns:
    any -- React element
]]
local function UIGradientNumberSequenceEditor_Component(Props: Props): any
	local DefaultSeq = NumberSequence.new(0)
	local ActiveSeq: NumberSequence = Props.CurrentValue or DefaultSeq
	local ActiveCallbackIdRef = React.useRef(nil :: string?)
	local CleanupRef = React.useRef(nil :: (() -> ())?)

	-- Component unmount lifecycle hook
	React.useEffect(function(): (() -> ())?
		return function(): ()
			if ActiveCallbackIdRef.current then
				Relay.Create("CloseTransparencyEditor"):Fire({
					CallbackId = ActiveCallbackIdRef.current,
				})
			end

			if CleanupRef.current then
				CleanupRef.current()
			end
		end
	end, {})

	local function handleOpenEditor(): ()
		-- Force-close any open transparency editor session first to revert previews
		Relay.Create("CloseTransparencyEditor"):Fire()

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

		LiveConn = Relay.Create("TransparencyEditorLiveUpdate"):Connect(function(Data: any): ()
			if Data.CallbackId == CallbackId and Props.OnPreview then
				Props.OnPreview(Data.NumberSequence)
			end
		end)

		SubmitConn = Relay.Create("TransparencyEditorSubmitted"):Connect(function(Data: any): ()
			if Data.CallbackId == CallbackId then
				if Props.OnCommit then
					Props.OnCommit(Data.NumberSequence, ActiveSeq)
					
				else
					Props.OnSubmit(Data.NumberSequence)
				end
				
				cleanup()
			end
		end)

		CloseConn = Relay.Create("CloseTransparencyEditor"):Connect(function(Data: any): ()
			if not Data or not Data.CallbackId or Data.CallbackId == CallbackId then
				if Props.OnPreview then
					Props.OnPreview(ActiveSeq)
				end
				
				cleanup()
			end
		end)

		Relay.Create("OpenTransparencyEditor"):Fire({
			InitialNumberSequence = ActiveSeq,
			CallbackId = CallbackId,
		})
	end

	return React.createElement("TextButton", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(20, 20, 20),
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
		
		Ramp = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		}, {
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
			
			Gradient = React.createElement("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
				Transparency = ActiveSeq,
			}),
		}),
	})
end

----------------------------------------------------------
return UIGradientNumberSequenceEditor_Component
----------------------------------------------------------