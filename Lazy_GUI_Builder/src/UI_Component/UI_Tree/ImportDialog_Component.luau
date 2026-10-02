--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ImportDialog_Component.luau
    
    SCOPE: UI Tree / Import Compiler
    
    ROLE: Modal dialog that displays the active Roblox Studio selection, provides
          mode selection (Append, Replace_Selected, Replace), and triggers
          the import pipeline.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type Props = {
	Visible: boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Imported Services Section
----------------------------------------------------------
local Selection: Selection = game:GetService("Selection")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)
local AppState = require(script.Parent.Parent.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Renders the import dialog modal window.

Params:
    Props: Props -- Component properties

Returns:
    any -- Rendered React element
]]
local function ImportDialog_Component(Props: Props): any
	local SelectedMode: string, SetSelectedMode = React.useState("Append")
	
	local StudioSelection: Instance?, SetStudioSelection = React.useState(function(): Instance?
		local Selected = Selection:Get()
		
		return Selected[1]
	end)
	
	local UpdateTick: number, SetUpdateTick = React.useState(0)

	-- Sync Studio selection actively
	React.useEffect(function(): () -> ()
		local SelectionConn = Selection.SelectionChanged:Connect(function(): ()
			local Current = Selection:Get()
			
			SetStudioSelection(Current[1])
		end)

		local Current = Selection:Get()
		
		SetStudioSelection(Current[1])

		return function(): ()
			SelectionConn:Disconnect()
		end
	end, { Props.Visible } :: { any })

	-- Listen for UI Tree selection updates to re-render context
	React.useEffect(function(): ()
		local Signal = Relay.Create("ElementSelected"):Connect(function(): ()
			SetUpdateTick(function(Prev: number): number
				return Prev + 1
			end)
		end)

		return function(): ()
			Signal:Disconnect()
		end
	end, {})

	local SelectedTreeId: string? = AppState.SelectedElementId
	local SelectedTreeElement: AppState.UIElement? = SelectedTreeId and AppState.WorkspaceElements[SelectedTreeId] or nil
	local HasUITreeSelection: boolean = SelectedTreeElement ~= nil

	-- Determine selection status and label
	local SelectionTitle: string = "None"
	local SelectionKind: string = "No Selection"
	local KindBgColor: Color3 = Color3.fromRGB(60, 60, 60)
	local KindTextColor: Color3 = Color3.fromRGB(180, 180, 180)
	local IsSupportedSource: boolean = false

	if StudioSelection then
		SelectionTitle = StudioSelection.Name
		
		if StudioSelection:IsA("ModuleScript") then
			SelectionKind = "ModuleScript"
			KindBgColor = Color3.fromRGB(30, 70, 140)
			KindTextColor = Color3.fromRGB(160, 200, 255)
			IsSupportedSource = true
			
		elseif StudioSelection:IsA("GuiObject") or StudioSelection:IsA("ScreenGui") or StudioSelection:IsA("LayerCollector") then
			SelectionKind = StudioSelection.ClassName
			KindBgColor = Color3.fromRGB(20, 100, 60)
			KindTextColor = Color3.fromRGB(160, 255, 200)
			IsSupportedSource = true
			
		else
			SelectionKind = StudioSelection.ClassName
			KindBgColor = Color3.fromRGB(120, 50, 30)
			KindTextColor = Color3.fromRGB(255, 180, 160)
			IsSupportedSource = false
		end
	end

	-- Determine mode suitability
	local CanImport: boolean = IsSupportedSource
	
	if SelectedMode == "Replace_Selected" and not HasUITreeSelection then
		CanImport = false
	end

	-- Mode description helper
	local ModeDescription: string
	local ModeDescColor: Color3 = Color3.fromRGB(180, 180, 180)

	if SelectedMode == "Append" then
		ModeDescription = "Adds the imported hierarchy as a new root node on the canvas."
		
	elseif SelectedMode == "Replace_Selected" then
		if HasUITreeSelection and SelectedTreeElement then
			ModeDescription = string.format("Replaces '%s' and all of its descendants with the imported hierarchy.", SelectedTreeElement.Name)
			ModeDescColor = Color3.fromRGB(140, 220, 255)
			
		else
			ModeDescription = "\u{26A0} Requires an element selected in the UI Tree to replace."
			ModeDescColor = Color3.fromRGB(255, 160, 120)
		end
		
	else
		ModeDescription = "\u{26A0} Wipes the entire canvas and replaces it with the imported hierarchy."
		ModeDescColor = Color3.fromRGB(255, 180, 120)
	end

	return React.createElement(UI_ComponentSDK.DraggableWindow, {
		Title = "Import Build",
		TitleAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(345, 236),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 500,
		Visible = Props.Visible,

		OnClose = function(): ()
			Relay.Create("ToggleImportDialog_CL"):Fire()
		end,

		Children = {
			Content = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 12),
					PaddingLeft = UDim.new(0, 12),
					PaddingRight = UDim.new(0, 12),
				}),

				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 8),
				}),

				-- Studio Selection Header
				SourceHeader = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundTransparency = 1,
					Text = "Studio Explorer Selection:",
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextSize = 12,
					Font = Enum.Font.GothamBold,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 1,
				}),

				-- Source Instance Box
				SourceCard = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 36),
					BackgroundColor3 = Color3.fromRGB(30, 30, 30),
					BorderSizePixel = 0,
					LayoutOrder = 2,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),

					Padding = React.createElement("UIPadding", {
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),

					Layout = React.createElement("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Horizontal,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					}),

					KindBadge = React.createElement("Frame", {
						Size = UDim2.fromOffset(80, 22),
						BackgroundColor3 = KindBgColor,
						BorderSizePixel = 0,
						LayoutOrder = 1,
					}, {
						Corner = React.createElement("UICorner", {
							CornerRadius = UDim.new(0, 3),
						}),

						Label = React.createElement("TextLabel", {
							Size = UDim2.fromScale(1, 1),
							BackgroundTransparency = 1,
							Text = SelectionKind,
							TextColor3 = KindTextColor,
							TextSize = 10,
							Font = Enum.Font.Code,
							TextXAlignment = Enum.TextXAlignment.Center,
							TextYAlignment = Enum.TextYAlignment.Center,
						}),
					}),

					SourceName = React.createElement("TextLabel", {
						Size = UDim2.new(1, -90, 1, 0),
						BackgroundTransparency = 1,
						Text = SelectionTitle,
						TextColor3 = if StudioSelection then Color3.fromRGB(240, 240, 240) else Color3.fromRGB(120, 120, 120),
						TextSize = 12,
						Font = Enum.Font.GothamMedium,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextTruncate = Enum.TextTruncate.AtEnd,
						LayoutOrder = 2,
					}),
				}),

				-- Import Mode Header
				ModeHeader = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundTransparency = 1,
					Text = "Import Mode:",
					TextColor3 = Color3.fromRGB(200, 200, 200),
					TextSize = 12,
					Font = Enum.Font.GothamBold,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 3,
				}),

				-- Mode Segmented Buttons
				ModeButtonRow = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,
					LayoutOrder = 4,
				}, {
					Layout = React.createElement("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Horizontal,
						Padding = UDim.new(0, 6),
					}),

					AppendBtn = React.createElement("TextButton", {
						Size = UDim2.new(1/3, -4, 1, 0),
						BackgroundColor3 = if SelectedMode == "Append" then Color3.fromRGB(0, 120, 65) else Color3.fromRGB(40, 40, 40),
						Text = "Append",
						TextColor3 = if SelectedMode == "Append" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(180, 180, 180),
						TextSize = 10,
						Font = Enum.Font.GothamBold,
						BorderSizePixel = 0,
						LayoutOrder = 1,

						[React.Event.Activated] = function(): ()
							SetSelectedMode("Append")
						end,
					}, {
						Corner = React.createElement("UICorner", { 
							CornerRadius = UDim.new(0, 4) 
						}),
					}),

					ReplaceSelectedBtn = React.createElement("TextButton", {
						Size = UDim2.new(1/3, -4, 1, 0),
						BackgroundColor3 = if SelectedMode == "Replace_Selected" then Color3.fromRGB(0, 120, 65) else Color3.fromRGB(40, 40, 40),
						Text = "Replace Selected",
						TextColor3 = if SelectedMode == "Replace_Selected" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(180, 180, 180),
						TextSize = 10,
						Font = Enum.Font.GothamBold,
						BorderSizePixel = 0,
						LayoutOrder = 2,

						[React.Event.Activated] = function(): ()
							SetSelectedMode("Replace_Selected")
						end,
					}, {
						Corner = React.createElement("UICorner", {
							CornerRadius = UDim.new(0, 4) 
						}),
					}),

					ReplaceCanvasBtn = React.createElement("TextButton", {
						Size = UDim2.new(1/3, -4, 1, 0),
						BackgroundColor3 = if SelectedMode == "Replace" then Color3.fromRGB(160, 60, 40) else Color3.fromRGB(40, 40, 40),
						Text = "Replace All",
						TextColor3 = if SelectedMode == "Replace" then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(180, 180, 180),
						TextSize = 10,
						Font = Enum.Font.GothamBold,
						BorderSizePixel = 0,
						LayoutOrder = 3,

						[React.Event.Activated] = function(): ()
							SetSelectedMode("Replace")
						end,
					}, {
						Corner = React.createElement("UICorner", { 
							CornerRadius = UDim.new(0, 4)
						}),
					}),
				}),

				-- Mode Description Note
				ModeDescLabel = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 24),
					BackgroundTransparency = 1,
					Text = ModeDescription,
					TextColor3 = ModeDescColor,
					TextSize = 10,
					Font = Enum.Font.Code,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					LayoutOrder = 5,
				}),

				-- Bottom Action Row
				ActionRow = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,
					LayoutOrder = 6,
				}, {
					CreditsLabel = React.createElement("TextLabel", {
						Size = UDim2.new(1, -128, 1, 0),
						Position = UDim2.fromOffset(0, 0),
						BackgroundTransparency = 1,
						Text = "Gui Builder by BedQuest/yawnTooMuch",
						TextColor3 = Color3.fromRGB(110, 110, 110),
						TextSize = 8,
						Font = Enum.Font.GothamMedium,
						TextXAlignment = Enum.TextXAlignment.Left,
						TextYAlignment = Enum.TextYAlignment.Bottom,
					}),

					ImportBtn = React.createElement("TextButton", {
						Size = UDim2.fromOffset(120, 28),
						Position = UDim2.new(1, 0, 0, 0),
						AnchorPoint = Vector2.new(1, 0),
						BackgroundColor3 = if CanImport then Color3.fromRGB(0, 160, 255) else Color3.fromRGB(50, 50, 50),
						Text = "Import",
						TextColor3 = if CanImport then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(140, 140, 140),
						TextSize = 12,
						Font = Enum.Font.GothamBold,
						AutoButtonColor = CanImport,
						BorderSizePixel = 0,

						[React.Event.Activated] = function(): ()
							if not CanImport or not StudioSelection then
								return
							end

							Relay.Create("ImportProject_CL"):Fire({
								TargetInstance = StudioSelection,
								Mode = SelectedMode,
							})
						end,
					}, {
						Corner = React.createElement("UICorner", {
							CornerRadius = UDim.new(0, 4)
						}),
					}),
				}),
			}),
		},
	})
end

----------------------------------------------------------
return ImportDialog_Component
----------------------------------------------------------