--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: PositionSettings_Component.luau
    
    SCOPE: Properties Editor
    
    ROLE: A floating modal that allows configuring sensitivity for position dials and trackpad.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PositionSettings_Component Type Structures Section
----------------------------------------------------------
export type Props = {
    Settings: {
        TrackpadSensitivity: number,
        XDialSensitivity: number,
        YDialSensitivity: number,
	},
	
    Visible: boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PositionSettings_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)
local Relay = require(script.Parent.Parent.Parent.Parent.Parent.Extras.Relay.Relay)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PositionSettings_Component Local Function Section
----------------------------------------------------------

--[[
Creates a labeled input field row.
]]
local function renderSettingRow(Label: string, CurrentValue: number, SetValue: (number) -> (), Min: number, Max: number, LayoutOrder: number): any
    local TextValue, SetTextValue = React.useState(tostring(CurrentValue))

    return React.createElement("Frame", {
        Size = UDim2.new(1, 0, 0, 45),
        BackgroundTransparency = 1,
        LayoutOrder = LayoutOrder,
    }, {
        Layout = React.createElement("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 4),
        }),
        
        TextLabel = React.createElement("TextLabel", {
            Size = UDim2.new(1, 0, 0, 14),
            BackgroundTransparency = 1,
            Text = Label .. string.format(" (Min: %s - Max: %s)", tostring(Min), tostring(Max)),
            TextColor3 = Color3.fromRGB(180, 180, 180),
            TextXAlignment = Enum.TextXAlignment.Center,
            Font = Enum.Font.Gotham,
            TextSize = 11,
            LayoutOrder = 1,
        }),
        
        InputBox = React.createElement("TextBox", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundColor3 = Color3.fromRGB(35, 35, 35),
            TextColor3 = Color3.new(1, 1, 1),
            Text = TextValue,
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            ClearTextOnFocus = false,
            ClipsDescendants = true,
            LayoutOrder = 2,
            
            [React.Event.FocusLost] = function(Rbx: Instance): ()
				local Num = tonumber((Rbx :: TextBox).Text)
				
                if Num then
					local Clamped = math.clamp(Num, Min, Max)
					
                    SetValue(Clamped)
					SetTextValue(tostring(Clamped))
					
                else
					(Rbx :: TextBox).Text = TextValue
                end
            end,
            
            [React.Change.Text] = function(Rbx: Instance): ()
                SetTextValue((Rbx :: TextBox).Text)
            end,
        }, {
            Corner = React.createElement("UICorner", {
                CornerRadius = UDim.new(0, 4)
			}),
        })
    })
end

--[[
The PositionSettings_Component function.
]]
local function PositionSettings_Component(Props: Props): any
    if not Props.Visible then
        return nil
    end

    local Trackpad, SetTrackpad = React.useState(Props.Settings.TrackpadSensitivity)
    local XDial, SetXDial = React.useState(Props.Settings.XDialSensitivity)
    local YDial, SetYDial = React.useState(Props.Settings.YDialSensitivity)

    -- Reset local state if external settings prop updates
    React.useEffect(function(): ()
        SetTrackpad(Props.Settings.TrackpadSensitivity)
        SetXDial(Props.Settings.XDialSensitivity)
        SetYDial(Props.Settings.YDialSensitivity)
    end, { Props.Settings } :: { any })

    return React.createElement(UI_ComponentSDK.Panel, {
        Size = UDim2.fromOffset(250, 0),
        Position = UDim2.fromScale(0.45, 0.3),
        BackgroundColor3 = Color3.fromRGB(45, 45, 45),
        AutomaticSize = Enum.AutomaticSize.Y,
        ZIndex = 100,
        Active = true,
    }, {
        Layout = React.createElement("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 10),
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
        }),
        
        Padding = React.createElement("UIPadding", {
            PaddingTop = UDim.new(0, 15),
            PaddingBottom = UDim.new(0, 20),
            PaddingLeft = UDim.new(0, 15),
            PaddingRight = UDim.new(0, 15),
        }),
        
        Title = React.createElement("TextLabel", {
            Size = UDim2.new(1, 0, 0, 20),
            BackgroundTransparency = 1,
            Text = "Position Editor Settings",
            TextColor3 = Color3.new(1, 1, 1),
            Font = Enum.Font.GothamBold,
            TextSize = 14,
            LayoutOrder = 1,
        }),
        
        Divider = React.createElement("Frame", {
            Size = UDim2.new(1, 0, 0, 1),
            BackgroundColor3 = Color3.fromRGB(80, 80, 80),
            BorderSizePixel = 0,
            LayoutOrder = 2,
        }),

        TrackpadRow = renderSettingRow("Trackpad Sensitivity", Trackpad, SetTrackpad, 1, 10, 4),
        XDialRow = renderSettingRow("X Dial Sensitivity", XDial, SetXDial, 0.5, 5, 5),
        YDialRow = renderSettingRow("Y Dial Sensitivity", YDial, SetYDial, 0.5, 5, 6),

        BottomActions = React.createElement("Frame", {
            Size = UDim2.new(1, 0, 0, 24),
            BackgroundTransparency = 1,
            LayoutOrder = 8,
        }, {
            ConfirmBtn = React.createElement("TextButton", {
                Size = UDim2.new(1, 0, 1, 0),
                BackgroundColor3 = Color3.fromRGB(0, 120, 215),
                Text = "Confirm",
                TextColor3 = Color3.new(1, 1, 1),
                Font = Enum.Font.GothamBold,
                TextSize = 12,
                AutoButtonColor = true,
                
                [React.Event.Activated] = function()
                    Relay.Create("UpdatePositionEditorSettings"):Fire({
                        TrackpadSensitivity = Trackpad,
                        XDialSensitivity = XDial,
                        YDialSensitivity = YDial,
                    })
                end,
            }, {
                Corner = React.createElement("UICorner", {
                    CornerRadius = UDim.new(0, 4)
                })
            })
        })
    })
end

----------------------------------------------------------
return PositionSettings_Component
----------------------------------------------------------