--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: NotificationCenter_Component.luau
    
    SCOPE: Root UI Component / Toast Notification Overlay
    
    ROLE: Listens to ShowNotification Relay signals and renders animated,
          stacked toast notification cards (success, warning, error) with
          smooth tween transitions and automatic timed dismissals.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- NotificationCenter_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Extras.Relay.Relay)
local Assignment = require(script.Parent.Parent.Parent.Extras.Assignment.Assignment)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- NotificationCenter_Component Imported Services Section
----------------------------------------------------------
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- NotificationCenter_Component Internal Types
----------------------------------------------------------
type NotificationData = {
	Id: string,
	Message: string,
	Type: string,
	CreatedAt: number,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- NotificationCenter_Component Helper Components
----------------------------------------------------------

--[[
A single notification item that manages its own entrance/exit tweening.
]]
local function NotificationItem(Props: { Data: NotificationData, Index: number, OnComplete: (string) -> () }): any
	local CanvasGroupRef = React.useRef(nil :: CanvasGroup?)

	-- Effect 1: Handle sliding to the correct index position dynamically
	React.useEffect(function(): (() -> ())?
		if CanvasGroupRef.current then
			local TargetY = 20 + (Props.Index * 50)
			local InInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			local InTween = TweenService:Create(CanvasGroupRef.current, InInfo, {
				Position = UDim2.new(0.5, 0, 0, TargetY),
				GroupTransparency = 0,
			})
			
			InTween:Play()
		end
		
		return nil
	end, { Props.Index } :: { any })

	-- Effect 2: Independent death timer that starts exactly once on mount
	React.useEffect(function(): (() -> ())?
		local IsActive = true
		
		-- Schedule animation out after 1.5 seconds
		Assignment.Delay(1.5, function(): ()
			if not IsActive then return end
			
			if CanvasGroupRef.current then
				-- Grab current physical position to smoothly drop down from its active slot
				local CurrentPos = CanvasGroupRef.current.Position
				local OutInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				local OutTween = TweenService:Create(CanvasGroupRef.current, OutInfo, {
					Position = UDim2.new(CurrentPos.X.Scale, CurrentPos.X.Offset, CurrentPos.Y.Scale, CurrentPos.Y.Offset + 30),
					GroupTransparency = 1,
				})
				
				OutTween:Play()
				
				OutTween.Completed:Connect(function(): ()
					if IsActive then
						Props.OnComplete(Props.Data.Id)
					end
				end)
			end
		end)
		
		return function(): ()
			IsActive = false
		end
	end, {} :: { any })

	local BgColor = Props.Data.Type == "Error" and Color3.fromRGB(220, 60, 60) or Color3.fromRGB(60, 220, 60)

	-- We use CanvasGroup to easily tween all transparencies (Background, UIStroke, Text) at once.
	return React.createElement("CanvasGroup", {
		ref = CanvasGroupRef,
		Size = UDim2.new(0, 330, 0, 40),
		Position = UDim2.new(0.5, 0, 0, -50), -- Start offscreen
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = BgColor,
		GroupTransparency = 1, -- Start invisible
		BorderSizePixel = 0,
		ZIndex = 10000 - Props.Index, -- Newer notifications stack above older ones
	}, {
		Corner = React.createElement("UICorner", { 
			CornerRadius = UDim.new(0, 6) 
		}),
		
		Stroke = React.createElement("UIStroke", {
			Color = Color3.fromRGB(25, 25, 25),
			Thickness = 1,
		}),
		
		TextLabel = React.createElement("TextLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Text = Props.Data.Message,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextWrapped = true,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 5),
				PaddingRight = UDim.new(0, 5),
			}),
		}),
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- NotificationCenter_Component Public APIs Section
----------------------------------------------------------
--[[
The container component that listens for Relay signals and stacks incoming notifications.
]]
local function NotificationCenter_Component(): any
	local Notifications: { NotificationData }, SetNotifications = React.useState({} :: { NotificationData })

	React.useEffect(function(): (() -> ())?
		Relay.Create("ShowNotification"):Connect(function(Payload: { Message: string, Type: string }): ()
			SetNotifications(function(Prev: { NotificationData }): { NotificationData }
				local NewNotification: NotificationData = {
					Id = HttpService:GenerateGUID(false),
					Message = Payload.Message,
					Type = Payload.Type,
					CreatedAt = os.clock(),
				}
				
				-- Prepend new notification so it appears at Index 0
				local NewArray: { NotificationData } = { NewNotification }
				
				for _, Notif in ipairs(Prev) do
					NewArray[#NewArray + 1] = Notif
				end
				
				return NewArray
			end)
		end)

		return nil
	end, {})

	local function removeNotification(Id: string): ()
		SetNotifications(function(Prev: { NotificationData }): { NotificationData }
			local NewArray: { NotificationData } = {}
			
			for _, Notif in ipairs(Prev) do
				if Notif.Id ~= Id then
					NewArray[#NewArray + 1] = Notif
				end
			end
			
			return NewArray
		end)
	end

	local Children: { [string]: any } = {}
	
	for Index, Notif in ipairs(Notifications) do
		-- Index is 1-based, we want 0-based for offset logic
		Children[Notif.Id] = React.createElement(NotificationItem, {
			Data = Notif,
			Index = Index - 1,
			OnComplete = removeNotification,
		})
	end

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = 10000,
		Interactable = false, -- Click-through
	}, Children)
end

----------------------------------------------------------
return NotificationCenter_Component
----------------------------------------------------------