--!strict
-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- AppController Type Structures Section
----------------------------------------------------------
export type AppController = {
	Init: (PluginReference: Plugin, PropEdWidget: DockWidgetPluginGui) -> (),
	Unmount: () -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- AppController Dependency Section
----------------------------------------------------------
local UIComponent_Linker = require(script.Parent.UIComponent_Linker)
local Session_Controller = require(script.Parent.Controller.Session_Controller)
local Drag_Controller = require(script.Parent.Controller.Elements_Provider.Drag_Controller)
local UITree_Controller = require(script.Parent.Controller.UI_Tree.UITree_Controller)
local History_Controller = require(script.Parent.Controller.History_Controller)

local PropertiesEditor_Controller = require(script.Parent.Controller.Properties_Editor.PropertiesEditor_Controller)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- AppController Internal States Section
----------------------------------------------------------
local AppController = {}
local MasterPlugin: Plugin? = nil

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------

----------------------------------------------------------
-- AppController Public APIs Section
----------------------------------------------------------

--[[
Initializes the AppController and its sub-controllers.

Params:
    PluginReference: Plugin -- The master plugin reference
    PropEdWidget: DockWidgetPluginGui -- The widget for properties editor
    
Returns:
    () -- None
]]
function AppController.Init(PluginReference: Plugin, PropEdWidget: DockWidgetPluginGui): ()
	MasterPlugin = PluginReference

	Session_Controller.Init()
	Drag_Controller.Init()
	UITree_Controller.Init()
	History_Controller.Init()
	PropertiesEditor_Controller.Init()

	-- Unconditionally mount the MasterRoot once on boot
	UIComponent_Linker.Mount(PluginReference, PropEdWidget)
end

--[[
Unmounts the UI and cleans up the AppController state.

Params:
    None
    
Returns:
    () -- None
]]
function AppController.Unmount(): ()
	UIComponent_Linker.Unmount()
	MasterPlugin = nil
end

----------------------------------------------------------
return AppController :: AppController
----------------------------------------------------------