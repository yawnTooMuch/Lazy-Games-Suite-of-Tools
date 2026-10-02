--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ExportDialog_Component.luau
    
    SCOPE: UI Tree / Export Compiler
    
    ROLE: Modal dialog that prompts the user for the component export name
          and triggers the compilation pipeline.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ExportDialog_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	Visible: boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ExportDialog_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)
local AppState = require(script.Parent.Parent.Parent.AppState)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- ExportDialog_Component Public APIs Section
----------------------------------------------------------

--[[
Renders the export dialog modal window.

Params:
    Props: Props -- Component properties

Returns:
    any -- Rendered React element
]]
local function ExportDialog_Component(Props: Props): any
	local ComponentName: string, SetComponentName = React.useState("MyUI")
	local SelectedFramework: string?, SetSelectedFramework = React.useState("React_Luau" :: string?)
	local IsReactLuau: boolean = SelectedFramework == "React_Luau"

	-- Update default name whenever dialog becomes visible
	React.useEffect(function(): ()
		if Props.Visible then
			local DefaultName: string = "MyUI"
			local SelectedId: string? = AppState.SelectedElementId

			if SelectedId and AppState.WorkspaceElements[SelectedId] then
				local RawName: string = AppState.WorkspaceElements[SelectedId].Name
				local Sanitized: string = RawName:gsub("[^%w_]", "_")
				
				if string.match(Sanitized, "^%d") then
					Sanitized = "_" .. Sanitized
				end
				
				if #Sanitized > 0 then
					DefaultName = Sanitized
				end
			end

			SetComponentName(DefaultName)
		end
	end, { Props.Visible } :: { any })


	local SelectedId: string? = AppState.SelectedElementId
	local SelectedElement: AppState.UIElement? = SelectedId and AppState.WorkspaceElements[SelectedId] or nil
	local TargetLabel: string = SelectedElement and (SelectedElement.Name .. " (" .. SelectedElement.Type .. ")") or "None"

	return React.createElement(UI_ComponentSDK.DraggableWindow, {
		Title = "Export Build",
		TitleAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromOffset(320, 210),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 500,
		Visible = Props.Visible,

		OnClose = function(): ()
			Relay.Create("ToggleExportDialog_CL"):Fire()
		end,

		Children = {
			Content = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 10),
					PaddingBottom = UDim.new(0, 10),
					PaddingLeft = UDim.new(0, 10),
					PaddingRight = UDim.new(0, 10),
				}),

				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					FillDirection = Enum.FillDirection.Vertical,
					Padding = UDim.new(0, 6),
				}),

				-- Target Element Info
				TargetInfoRow = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 16),
					BackgroundTransparency = 1,
					Text = "Target Root: " .. TargetLabel,
					TextColor3 = Color3.fromRGB(180, 180, 180),
					TextSize = 12,
					Font = Enum.Font.GothamMedium,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 1,
				}),

				-- Component Name Label
				NameLabel = React.createElement("TextLabel", {
					Size = UDim2.new(1, 0, 0, 14),
					BackgroundTransparency = 1,
					Text = "Component Name (Identifier):",
					TextColor3 = Color3.fromRGB(220, 220, 220),
					TextSize = 12,
					Font = Enum.Font.GothamBold,
					TextXAlignment = Enum.TextXAlignment.Left,
					LayoutOrder = 2,
				}),

				-- Component Name Input Box
				InputContainer = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundColor3 = Color3.fromRGB(30, 30, 30),
					BorderSizePixel = 0,
					LayoutOrder = 3,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),

					Padding = React.createElement("UIPadding", {
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),

					TextBox = React.createElement("TextBox", {
						Size = UDim2.fromScale(1, 1),
						BackgroundTransparency = 1,
						Text = ComponentName,
						PlaceholderText = "e.g. MyUI",
						TextColor3 = Color3.fromRGB(255, 255, 255),
						PlaceholderColor3 = Color3.fromRGB(120, 120, 120),
						TextSize = 13,
						Font = Enum.Font.Gotham,
						TextXAlignment = Enum.TextXAlignment.Left,
						ClearTextOnFocus = false,

						[React.Change.Text] = function(Rbx: TextBox): ()
							SetComponentName(Rbx.Text)
						end,

						[React.Event.FocusLost] = function(Rbx: TextBox): ()
							SetComponentName(Rbx.Text)
						end,
					}),
				}),

				-- Destination Info Box
				DestinationInfo = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 48),
					BackgroundColor3 = Color3.fromRGB(35, 35, 35),
					BorderSizePixel = 0,
					LayoutOrder = 4,
				}, {
					Corner = React.createElement("UICorner", {
						CornerRadius = UDim.new(0, 4),
					}),

					Padding = React.createElement("UIPadding", {
						PaddingTop = UDim.new(0, 5),
						PaddingBottom = UDim.new(0, 5),
						PaddingLeft = UDim.new(0, 8),
						PaddingRight = UDim.new(0, 8),
					}),

					List = React.createElement("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Vertical,
						Padding = UDim.new(0, 2),
					}),

					DestTitle = React.createElement("TextLabel", {
						Size = UDim2.new(1, 0, 0, 12),
						BackgroundTransparency = 1,
						Text = if SelectedFramework then "ServerStorage/Lazy_GUI_Builder_Outputs/" .. SelectedFramework .. ":" else "",
						TextColor3 = Color3.fromRGB(160, 160, 160),
						TextSize = 10,
						Font = Enum.Font.GothamBold,
						TextXAlignment = Enum.TextXAlignment.Left,
						LayoutOrder = 1,
					}),

					PassiveLine = React.createElement("TextLabel", {
						Size = UDim2.new(1, 0, 0, 11),
						BackgroundTransparency = 1,
						Text = if SelectedFramework == "React_Luau" then "  • Passive: " .. ComponentName .. "_Component" elseif SelectedFramework then "  • Output:  " .. ComponentName else "",
						TextColor3 = Color3.fromRGB(140, 200, 255),
						TextSize = 10,
						Font = Enum.Font.Code,
						TextXAlignment = Enum.TextXAlignment.Left,
						Visible = SelectedFramework ~= nil,
						LayoutOrder = 2,
					}),

					ActiveLine = React.createElement("TextLabel", {
						Size = UDim2.new(1, 0, 0, 11),
						BackgroundTransparency = 1,
						Text = if SelectedFramework == "React_Luau" then "  • Active:  " .. ComponentName .. "_GUI" else "",
						TextColor3 = Color3.fromRGB(140, 255, 180),
						TextSize = 10,
						Font = Enum.Font.Code,
						TextXAlignment = Enum.TextXAlignment.Left,
						Visible = SelectedFramework == "React_Luau",
						LayoutOrder = 3,
					}),
				}),

				-- Button Row
				ButtonRow = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,
					LayoutOrder = 5,
				}, {
					RowLayout = React.createElement("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Left,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 8),
					}),

					FrameworkSelector = React.createElement("TextButton", {
						Size = UDim2.new(1, -93, 1, 0),
						BackgroundTransparency = 1,
						Text = "",
						AutoButtonColor = false,
						BorderSizePixel = 0,
						LayoutOrder = 1,

						[React.Event.Activated] = function(): ()
							if SelectedFramework == "React_Luau" then
								SetSelectedFramework(nil)
								
							else
								SetSelectedFramework("React_Luau")
							end
						end,
					}, {
						Corner = React.createElement("UICorner", {
							CornerRadius = UDim.new(0, 4),
						}),

						Stroke = React.createElement("UIStroke", {
							Color = Color3.fromRGB(120, 120, 120),
							Thickness = 1,
							ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
						}),

						Padding = React.createElement("UIPadding", {
							PaddingLeft = UDim.new(0, 8),
							PaddingRight = UDim.new(0, 8),
						}),

						RowLayout = React.createElement("UIListLayout", {
							SortOrder = Enum.SortOrder.LayoutOrder,
							FillDirection = Enum.FillDirection.Horizontal,
							VerticalAlignment = Enum.VerticalAlignment.Center,
							Padding = UDim.new(0, 6),
						}),

						CheckboxBox = React.createElement("Frame", {
							Size = UDim2.fromOffset(15, 15),
							BackgroundColor3 = IsReactLuau and Color3.fromRGB(0, 140, 70) or Color3.fromRGB(35, 35, 35),
							BorderSizePixel = 0,
							LayoutOrder = 1,
						}, {
							Corner = React.createElement("UICorner", {
								CornerRadius = UDim.new(0, 3),
							}),

							Stroke = React.createElement("UIStroke", {
								Color = IsReactLuau and Color3.fromRGB(0, 180, 90) or Color3.fromRGB(90, 90, 90),
								Thickness = 1,
								ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
							}),

							Checkmark = React.createElement("TextLabel", {
								Size = UDim2.fromScale(1, 1),
								BackgroundTransparency = 1,
								Text = IsReactLuau and "\u{2713}" or "",
								TextColor3 = Color3.fromRGB(255, 255, 255),
								TextSize = 11,
								Font = Enum.Font.GothamBold,
								TextXAlignment = Enum.TextXAlignment.Center,
								TextYAlignment = Enum.TextYAlignment.Center,
							}),
						}),

						FrameworkLabel = React.createElement("TextLabel", {
							Size = UDim2.new(1, -24, 1, 0),
							BackgroundTransparency = 1,
							Text = "React-Luau",
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextSize = 11,
							Font = Enum.Font.GothamMedium,
							TextXAlignment = Enum.TextXAlignment.Left,
							LayoutOrder = 2,
						}),
					}),

					ExportBtn = React.createElement("TextButton", {
						Size = UDim2.fromOffset(85, 28),
						BackgroundColor3 = if SelectedFramework then Color3.fromRGB(0, 140, 70) else Color3.fromRGB(50, 50, 50),
						Text = "Export",
						TextColor3 = if SelectedFramework then Color3.fromRGB(255, 255, 255) else Color3.fromRGB(150, 150, 150),
						TextSize = 12,
						Font = Enum.Font.GothamBold,
						AutoButtonColor = SelectedFramework ~= nil,
						LayoutOrder = 2,

						[React.Event.Activated] = function(): ()
							if not SelectedFramework then
								return
							end

							Relay.Create("ExportProject_CL"):Fire({
								ComponentName = ComponentName,
								Framework = SelectedFramework,
							})
						end,
					}, {
						Corner = React.createElement("UICorner", {
							CornerRadius = UDim.new(0, 4),
						}),
					}),
				}),
			}),
		},
	})
end

----------------------------------------------------------
return ExportDialog_Component
----------------------------------------------------------