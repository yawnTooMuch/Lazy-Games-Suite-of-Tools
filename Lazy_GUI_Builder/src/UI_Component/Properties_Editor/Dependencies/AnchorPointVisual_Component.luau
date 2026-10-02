--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: AnchorPointVisual_Component.luau
    
    SCOPE: Workspace
    
    ROLE: A visual indicator that renders a dark 1.5px square with a white border
          over the exact anchor point of the selected element.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- AnchorPointVisual_Component Type Structures Section
----------------------------------------------------------
export type Props = {
    AnchorPoint: Vector2,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- AnchorPointVisual_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Parent.Extras.React_Lua.React)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- AnchorPointVisual_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the AnchorPointVisual indicator.

Params:
    Props: Props -- Component props

Returns:
    any -- The AnchorPointVisual React component
]]
local function AnchorPointVisual_Component(Props: Props): any
    return React.createElement("Frame", {
        Size = UDim2.fromOffset(3, 3),
        Position = UDim2.fromScale(Props.AnchorPoint.X, Props.AnchorPoint.Y),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(20, 20, 20),
        ZIndex = 99999,
    }, {
        Stroke = React.createElement("UIStroke", {
            Color = Color3.fromRGB(255, 255, 255),
            Thickness = 1.5,
        }),
    })
end

----------------------------------------------------------
return AnchorPointVisual_Component
----------------------------------------------------------