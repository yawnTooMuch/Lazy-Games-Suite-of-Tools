--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: UIGradientColorSequenceEditor_Component.luau
    
    SCOPE: Feature UI Component Dependency
    
    ROLE: Renders the ColorSequence swatch button in the property row and 
          communicates with the root GradientEditorWindow_Component via Relay.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type Props = {
	CurrentValue: ColorSequence?,
	OnSubmit: (ColorSequence) -> (),
	OnPreview: ((ColorSequence) -> ())?,
	OnCommit: ((FinalSequence: ColorSequence, InitialSequence: ColorSequence) -> ())?,
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
Renders the ColorSequence swatch button in the property row.

Params:
    Props: Props -- Component props

Returns:
    any -- React element
]]
local function UIGradientColorSequenceEditor_Component(Props: Props): any
	local DefaultSeq = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(100, 100, 100))
	local ActiveSeq: ColorSequence = Props.CurrentValue or DefaultSeq
	local ActiveCallbackIdRef = React.useRef(nil :: string?)
	local CleanupRef = React.useRef(nil :: (() -> ())?)

	-- Component unmount lifecycle hook
	React.useEffect(function(): (() -> ())?
		return function(): ()
			if ActiveCallbackIdRef.current then
				Relay.Create("CloseGradientEditor"):Fire({
					CallbackId = ActiveCallbackIdRef.current,
				})
			end

			if CleanupRef.current then
				CleanupRef.current()
			end
		end
	end, {})

	local function handleOpenEditor(): ()
		-- Force-close any open gradient editor session first to revert previews
		Relay.Create("CloseGradientEditor"):Fire()

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

		LiveConn = Relay.Create("GradientEditorLiveUpdate"):Connect(function(Data: any): ()
			if Data.CallbackId == CallbackId and Props.OnPreview then
				Props.OnPreview(Data.ColorSequence)
			end
		end)

		SubmitConn = Relay.Create("GradientEditorSubmitted"):Connect(function(Data: any): ()
			if Data.CallbackId == CallbackId then
				if Props.OnCommit then
					Props.OnCommit(Data.ColorSequence, ActiveSeq)
					
				else
					Props.OnSubmit(Data.ColorSequence)
				end
				
				cleanup()
			end
		end)

		CloseConn = Relay.Create("CloseGradientEditor"):Connect(function(Data: any): ()
			if not Data or not Data.CallbackId or Data.CallbackId == CallbackId then
				if Props.OnPreview then
					Props.OnPreview(ActiveSeq)
				end
				
				cleanup()
			end
		end)

		Relay.Create("OpenGradientEditor"):Fire({
			InitialColorSequence = ActiveSeq,
			CallbackId = CallbackId,
		})
	end

	return React.createElement("TextButton", {
		Size = UDim2.new(1, 0, 1, -4),
		Position = UDim2.new(0, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
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
		
		Gradient = React.createElement("UIGradient", {
			Color = ActiveSeq,
		}),
	})
end

----------------------------------------------------------
return UIGradientColorSequenceEditor_Component
----------------------------------------------------------