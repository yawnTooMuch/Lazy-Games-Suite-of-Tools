--!strict

local RunService: RunService = game:GetService("RunService")

if not plugin or RunService:IsRunning() then
	return
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Main.plugin Configuration Section
----------------------------------------------------------
local TOOLBAR_NAME: string = "Lazy GUI Builder"

local PROVIDER_BUTTON_NAME: string = "Elements Provider"
local PROVIDER_BUTTON_TOOLTIP: string = "Toggle Elements Provider"
local PROVIDER_BUTTON_ICON: string = "rbxassetid://135104246336731"

local UITREE_BUTTON_NAME: string = "UI Tree"
local UITREE_BUTTON_TOOLTIP: string = "Toggle UI Tree"
local UITREE_BUTTON_ICON: string = "rbxassetid://90082614226520"

local PROPED_BUTTON_NAME: string = "Properties Editor"
local PROPED_BUTTON_TOOLTIP: string = "Toggle Properties Editor"
local PROPED_BUTTON_ICON: string = "rbxassetid://124640247622188"

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Main.plugin Dependency Section
----------------------------------------------------------
local AppController = require(script.Parent.AppController)
local Assignment = require(script.Parent.Parent.Extras.Assignment.Assignment)
local Relay = require(script.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Main.plugin Internal States Section
----------------------------------------------------------
local Toolbar: PluginToolbar = plugin:CreateToolbar(TOOLBAR_NAME)
local ProviderButton: PluginToolbarButton = Toolbar:CreateButton(PROVIDER_BUTTON_NAME, PROVIDER_BUTTON_TOOLTIP, PROVIDER_BUTTON_ICON)
local UITreeButton: PluginToolbarButton = Toolbar:CreateButton(UITREE_BUTTON_NAME, UITREE_BUTTON_TOOLTIP, UITREE_BUTTON_ICON)
local PropEdButton: PluginToolbarButton = Toolbar:CreateButton(PROPED_BUTTON_NAME, PROPED_BUTTON_TOOLTIP, PROPED_BUTTON_ICON)

local PropEdWidgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Right,
	false, -- Initially disabled
	false,
	300, -- Default Width
	400, -- Default Height
	250, -- Min Width
	200  -- Min Height
)

local PropEdWidget = plugin:CreateDockWidgetPluginGuiAsync("GUIBuilder_PropertiesEditor", PropEdWidgetInfo)

PropEdWidget.Title = "Properties Editor"
PropEdWidget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Main.plugin Local Function Section
----------------------------------------------------------
-- Fires ToggleProvider_CL signal
local function onProviderButtonClicked(): ()
    Relay.Create("ToggleProvider_CL"):Fire()
end

-- Fires ToggleUITree_CL signal
local function onUITreeButtonClicked(): ()
    Relay.Create("ToggleUITree_CL"):Fire()
end

-- Fires TogglePropertiesEditor_CL signal
local function onPropEdButtonClicked(): ()
	Relay.Create("TogglePropertiesEditor_CL"):Fire()
end

-- Fires when the plugin unloads to clean up resources
local function onPluginUnloaded(): ()
    if AppController and type(AppController.Unmount) == "function" then
        AppController.Unmount()
	end
	
	warn("[Lazy GUI Builder] Unloading Plugin! Running strict cleanup.")
end

-- Sync ribbon buttons with the session state updates
local function onSessionStateUpdated(): ()
    ProviderButton:SetActive(AppState.SessionState.IsProviderVisible)
    UITreeButton:SetActive(AppState.SessionState.IsUITreeVisible)
	PropEdButton:SetActive(AppState.SessionState.IsPropertiesEditorVisible)
	PropEdWidget.Enabled = AppState.SessionState.IsPropertiesEditorVisible
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Main.plugin Event Binding Section
----------------------------------------------------------
ProviderButton.Click:Connect(onProviderButtonClicked)
UITreeButton.Click:Connect(onUITreeButtonClicked)
PropEdButton.Click:Connect(onPropEdButtonClicked)

PropEdWidget:GetPropertyChangedSignal("Enabled"):Connect(function()
	-- If the user clicks the X on the widget itself
	if not PropEdWidget.Enabled and AppState.SessionState.IsPropertiesEditorVisible then
		Relay.Create("TogglePropertiesEditor_CL"):Fire()
	end
end)

plugin.Unloading:Connect(onPluginUnloaded)
Relay.Create("SessionStateUpdated"):Connect(onSessionStateUpdated)
Relay.Inject("Assignment", Assignment)

if AppController and type(AppController.Init) == "function" then
    -- Immediately boot the plugin to establish the background MasterRoot and signals.
	AppController.Init(plugin, PropEdWidget)
	print("[Lazy GUI Builder] Booting Plugin...")
end