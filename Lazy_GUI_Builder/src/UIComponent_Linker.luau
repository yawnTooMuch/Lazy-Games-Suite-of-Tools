--!strict
-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- UIComponent_Linker Type Structures Section
----------------------------------------------------------
export type UIComponent_Linker = {
	Mount: (PluginReference: Plugin, PropEdWidget: DockWidgetPluginGui) -> (),
	Unmount: () -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- UIComponent_Linker Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Extras.React_Lua.React)
local ReactRoblox = require(script.Parent.Parent.Extras.React_Lua.ReactRoblox)
local MasterRoot_Component = require(script.Parent.UI_Component.MasterRoot_Component)
local PropertiesEditor_Component = require(script.Parent.UI_Component.Properties_Editor.PropertiesEditor_Component)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UIComponent_Linker Imported Services Section
----------------------------------------------------------
local CoreGui = game:GetService("CoreGui")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UIComponent_Linker Internal States Section
----------------------------------------------------------
local UIComponent_Linker = {}
local RootHandle: ReactRoblox.RootType? = nil
local ScreenGuiInstance: ScreenGui? = nil
local PropEdRootHandle: ReactRoblox.RootType? = nil

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UIComponent_Linker Public APIs Section
----------------------------------------------------------
--[[
Mounts the MasterRoot React component into CoreGui and the PropertiesEditor into its Widget.

Params:
    PluginReference: Plugin -- The plugin instance
    PropEdWidget: DockWidgetPluginGui -- The plugin widget for properties

Returns:
    () -- No return value
]]
function UIComponent_Linker.Mount(PluginReference: Plugin, PropEdWidget: DockWidgetPluginGui): ()
	local AppRoot = React.createElement(MasterRoot_Component)

	if not ScreenGuiInstance then
		local newGui = Instance.new("ScreenGui")
		
		newGui.Name = "Lazy_GUI_Builder_MainWorkspace"
		newGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		newGui.IgnoreGuiInset = true
		newGui.Parent = CoreGui
		ScreenGuiInstance = newGui
	end

	if not RootHandle then
		RootHandle = ReactRoblox.createRoot(ScreenGuiInstance :: ScreenGui)
	end

	if RootHandle then
		RootHandle:render(AppRoot)
	end
	
	if not PropEdRootHandle then
		PropEdRootHandle = ReactRoblox.createRoot(PropEdWidget)
	end
	
	if PropEdRootHandle then
		PropEdRootHandle:render(React.createElement(PropertiesEditor_Component))
	end
end

--[[
Unmounts the React components and destroys the ScreenGui.

Params:
    None

Returns:
    () -- No return value
]]
function UIComponent_Linker.Unmount(): ()
	if RootHandle then
		RootHandle:unmount()
		RootHandle = nil
	end

	if PropEdRootHandle then
		PropEdRootHandle:unmount()
		PropEdRootHandle = nil
	end

	if ScreenGuiInstance then
		ScreenGuiInstance:Destroy()
		ScreenGuiInstance = nil
	end
end

----------------------------------------------------------
return UIComponent_Linker :: UIComponent_Linker
----------------------------------------------------------