--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: UITree_Component.luau
    
    SCOPE: UI Tree / Feature UI Component
    
    ROLE: Renders the resizable, draggable UI Tree window, managing the
          hierarchical element tree display, node drag-and-drop ghost preview,
          trash/duplicate drop targets, and import/export dialog triggers.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	Visible: boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local UI_ComponentSDK = require(script.Parent.Parent.Parent.Parent.Extras.UI_ComponentSDK.UI_ComponentSDK)
local AppState = require(script.Parent.Parent.Parent.AppState)
local UITreeNode_Component = require(script.Parent.UITreeNode_Component)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Component Imported Services Section
----------------------------------------------------------
local UserInputService: UserInputService = game:GetService("UserInputService")
local TextService: TextService = game:GetService("TextService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITree_Component Public APIs Section
----------------------------------------------------------
--[[
Renders the UI Tree window and its children.

Params:
	Props: Props -- The properties for the component

Returns:
	any -- The rendered React element
]]
function UITree_Component(Props: Props): any
	local UpdateTick: number, SetUpdateTick = React.useState(0)
	local IsNodeDragging: boolean, SetIsNodeDragging = React.useState(false)
	local DraggedNodeId: string?, SetDraggedNodeId = React.useState(nil :: string?)
	local MousePosition, SetMousePosition = React.useBinding(UDim2.fromOffset(0, 0))
	local SelectedId: string?, SetSelectedId = React.useState(AppState.SelectedElementId)
	local WindowWidth, SetWindowWidth = React.useBinding(250)
	local IsResizing: boolean, SetIsResizing = React.useState(false)
	local ResizeStartMouseX: number, SetResizeStartMouseX = React.useState(0)
	local ResizeStartWidth: number, SetResizeStartWidth = React.useState(0)
	local MaxRequiredWidth: number = 250
	local RootNodeCount: number = 0
	local LayoutOrder: number = 1
	local RootNodes: { [string]: any } = {}
	local FragmentChildren: { [string]: any } = {}
	local CanUndo: boolean = #AppState.UndoStack > 0
	local CanRedo: boolean = #AppState.RedoStack > 0

	React.useEffect(function(): (() -> ())?
		Relay.Create("SessionStateUpdated"):Connect(function(): ()
			SetUpdateTick(function(Prev: number): number
				return Prev + 1
			end)
		end)

		Relay.Create("UITreeUpdated"):Connect(function(): ()
			SetUpdateTick(function(Prev: number): number
				return Prev + 1
			end)

			SetIsNodeDragging(AppState.UITreeDragState.IsDragging)
			SetDraggedNodeId(AppState.UITreeDragState.DraggedNodeId)
		end)

		Relay.Create("WorkspaceElementsUpdated"):Connect(function(): ()
			SetSelectedId(AppState.SelectedElementId)
			SetUpdateTick(function(Prev: number): number
				return Prev + 1
			end)
		end)

		Relay.Create("ElementSelected"):Connect(function(): ()
			SetSelectedId(AppState.SelectedElementId)
		end)

		return nil
	end, {})

	React.useEffect(function(): (() -> ())?
		if not IsNodeDragging then
			return nil
		end

		local MoveConnection: RBXScriptConnection
		local EndConnection: RBXScriptConnection
		local InitialMouse: Vector2 = UserInputService:GetMouseLocation()

		-- Handles mouse movement to update the drag position.
		local function onInputChanged(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				SetMousePosition(UDim2.fromOffset(Input.Position.X, Input.Position.Y))
			end
		end

		-- Handles input ended to finalize or cancel the drag operation.
		local function onInputEnded(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				if AppState.UITreeDragState.IsHoveringTrash and AppState.UITreeDragState.DraggedNodeId then
					Relay.Create("DeleteElement_CL"):Fire(AppState.UITreeDragState.DraggedNodeId)

				elseif AppState.UITreeDragState.IsHoveringDuplicate and AppState.UITreeDragState.DraggedNodeId then
					Relay.Create("DuplicateElement_CL"):Fire(AppState.UITreeDragState.DraggedNodeId)

				elseif AppState.UITreeDragState.DraggedNodeId then
					Relay.Create("ReparentElement_CL"):Fire(AppState.UITreeDragState.DraggedNodeId, AppState.UITreeDragState.HoveredTargetId)

				else
					Relay.Create("CancelNodeDrag_CL"):Fire()
				end
			end
		end

		MoveConnection = UserInputService.InputChanged:Connect(onInputChanged)
		EndConnection = UserInputService.InputEnded:Connect(onInputEnded)
		SetMousePosition(UDim2.fromOffset(InitialMouse.X, InitialMouse.Y - 36))

		return function(): ()
			MoveConnection:Disconnect()
			EndConnection:Disconnect()
		end
	end, { IsNodeDragging } :: { any })

	for Id: string, Element: AppState.UIElement in AppState.WorkspaceElements do
		local Depth: number = 0
		local Current: AppState.UIElement? = Element

		while Current and Current.ParentId do
			Depth += 1
			Current = AppState.WorkspaceElements[Current.ParentId]
		end

		local Text: string = Element.Name .. " (" .. Element.Type .. ")"
		local TextSize: Vector2 = TextService:GetTextSize(Text, 13, Enum.Font.Gotham, Vector2.new(10000, 10000))
		local NodeRequiredWidth: number = (Depth * 16) + TextSize.X + 70

		if NodeRequiredWidth > MaxRequiredWidth then
			MaxRequiredWidth = NodeRequiredWidth
		end
	end

	local MaxAllowedWidth: number = MaxRequiredWidth

	React.useEffect(function(): (() -> ())?
		if not IsResizing then
			return nil
		end

		local ChangedConn: RBXScriptConnection = UserInputService.InputChanged:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseMovement then
				local Delta: number = Input.Position.X - ResizeStartMouseX
				local NewWidth: number = math.clamp(ResizeStartWidth + Delta, 250, MaxAllowedWidth)
				
				SetWindowWidth(NewWidth)
			end
		end)

		local EndedConn: RBXScriptConnection = UserInputService.InputEnded:Connect(function(Input: InputObject): ()
			if Input.UserInputType == Enum.UserInputType.MouseButton1 then
				SetIsResizing(false)
			end
		end)

		return function(): ()
			ChangedConn:Disconnect()
			EndedConn:Disconnect()
		end
	end, { IsResizing, ResizeStartMouseX, ResizeStartWidth, MaxAllowedWidth } :: { any })

	RootNodes["Layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
	})

	RootNodes["Padding"] = React.createElement("UIPadding", {
		PaddingTop = UDim.new(0, 4),
		PaddingBottom = UDim.new(0, 2),
	})

	for Id: string, Element: AppState.UIElement in AppState.WorkspaceElements do
		if Element.ParentId == nil then
			RootNodeCount += 1
		end
	end

	for Id: string, Element: AppState.UIElement in AppState.WorkspaceElements do
		if Element.ParentId == nil then
			RootNodes[Id] = React.createElement(UITreeNode_Component, {
				NodeId = Id,
				Depth = 0,
				SelectedId = SelectedId,
				LayoutOrder = LayoutOrder,
				HasSiblings = (RootNodeCount > 1),
			})
			
			LayoutOrder += 1
		end
	end

	FragmentChildren["UITree_Window"] = React.createElement(UI_ComponentSDK.DraggableWindow, {
		Title = "UI Tree",
		TitleAlignment = Enum.TextXAlignment.Center,
		
		Size = WindowWidth:map(function(Width: number): UDim2
			return UDim2.fromOffset(math.min(Width, MaxAllowedWidth), 400) 
		end),
		
		Position = AppState.SessionState.UITreePosition,
		AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = 100,
		Visible = Props.Visible,

		OnDrag = function(NewPosition: UDim2): ()
			Relay.Create("UpdateUITreePosition"):Fire(NewPosition)
		end,

		OnClose = function(): ()
			Relay.Create("ToggleUITree_CL"):Fire()
		end,

		Children = {
			ContentContainer = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				Layout = React.createElement("UIListLayout", {
					SortOrder = Enum.SortOrder.LayoutOrder,
					FillDirection = Enum.FillDirection.Vertical,
				}),

				ToolbarRow = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 28),
					BackgroundTransparency = 1,
					LayoutOrder = 1,
				}, {
					RowLayout = React.createElement("UIListLayout", {
						SortOrder = Enum.SortOrder.LayoutOrder,
						FillDirection = Enum.FillDirection.Horizontal,
						HorizontalAlignment = Enum.HorizontalAlignment.Right,
						VerticalAlignment = Enum.VerticalAlignment.Center,
						Padding = UDim.new(0, 4),
					}),

					Padding = React.createElement("UIPadding", {
						PaddingRight = UDim.new(0, 8),
					}),

					DeselectWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Deselect",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 0,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.fromRGB(40, 40, 40),
							Text = "□",
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextSize = 16,

							[React.Event.Activated] = function(): ()
								Relay.Create("SelectElement_CL"):Fire(nil)
							end,
						})
					}),

					UndoWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Undo",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 1,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.fromRGB(40, 40, 40),
							Text = "↩",
							TextColor3 = if CanUndo then Color3.fromRGB(220, 220, 220) else Color3.fromRGB(90, 90, 90),
							TextSize = 16,
							AutoButtonColor = CanUndo,

							[React.Event.Activated] = function(): ()
								if CanUndo then
									Relay.Create("Undo_CL"):Fire()
								end
							end,
						})
					}),

					RedoWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Redo",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 2,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.fromRGB(40, 40, 40),
							Text = "↪",
							TextColor3 = if CanRedo then Color3.fromRGB(220, 220, 220) else Color3.fromRGB(90, 90, 90),
							TextSize = 16,
							AutoButtonColor = CanRedo,

							[React.Event.Activated] = function(): ()
								if CanRedo then
									Relay.Create("Redo_CL"):Fire()
								end
							end,
						})
					}),

					TrashWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Delete",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 3,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = AppState.UITreeDragState.IsHoveringTrash and Color3.fromRGB(180, 40, 40) or Color3.fromRGB(40, 40, 40),
							Text = "🗑️",
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextSize = 16,
							AutoButtonColor = false,

							[React.Event.MouseEnter] = function(): ()
								Relay.Create("SetNodeDragTrash_CL"):Fire(true)
							end,

							[React.Event.MouseLeave] = function(): ()
								Relay.Create("SetNodeDragTrash_CL"):Fire(false)
							end,
						})
					}),

					DuplicateWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Duplicate",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 4,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = AppState.UITreeDragState.IsHoveringDuplicate and Color3.fromRGB(40, 180, 40) or Color3.fromRGB(40, 40, 40),
							Text = "🗄️",
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextSize = 16,
							AutoButtonColor = false,

							[React.Event.MouseEnter] = function(): ()
								Relay.Create("SetNodeDragDuplicate_CL"):Fire(true)
							end,

							[React.Event.MouseLeave] = function(): ()
								Relay.Create("SetNodeDragDuplicate_CL"):Fire(false)
							end,
						})
					}),

					ExportWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Export Build",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 5,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.fromRGB(40, 40, 40),
							Text = "📤",
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextSize = 14,

							[React.Event.Activated] = function(): ()
								Relay.Create("ToggleExportDialog_CL"):Fire()
							end,
						})
					}),

					ImportWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Import Build",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 6,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.fromRGB(40, 40, 40),
							Text = "📥",
							TextColor3 = Color3.fromRGB(220, 220, 220),
							TextSize = 14,

							[React.Event.Activated] = function(): ()
								Relay.Create("ToggleImportDialog_CL"):Fire()
							end,
						})
					}),

					EyeWrap = React.createElement(UI_ComponentSDK.TooltipWrap, {
						Text = "Toggle All Visibility",
						Size = UDim2.fromOffset(24, 24),
						LayoutOrder = 7,
					}, {
						Btn = React.createElement("TextButton", {
							Size = UDim2.fromScale(1, 1),
							BackgroundColor3 = Color3.fromRGB(40, 40, 40),
							Text = AppState.SessionState.IsRenderEngineVisible and "◉" or "○",
							TextColor3 = AppState.SessionState.IsRenderEngineVisible and Color3.fromRGB(220, 220, 220) or Color3.fromRGB(80, 80, 80),
							TextSize = 16,

							[React.Event.Activated] = function(): ()
								Relay.Create("ToggleRenderEngine_CL"):Fire()
							end,
						})
					}),
				}),

				DividerLine = React.createElement("Frame", {
					Size = UDim2.new(1, 0, 0, 1),
					BackgroundColor3 = Color3.fromRGB(60, 60, 60),
					BorderSizePixel = 0,
					LayoutOrder = 2,
				}),

				TreeScroller = React.createElement("ScrollingFrame", {
					Size = UDim2.new(1, 0, 1, -29),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ScrollBarThickness = 4,
					CanvasSize = UDim2.fromScale(0, 0),
					AutomaticCanvasSize = Enum.AutomaticSize.Y,
					ScrollingDirection = Enum.ScrollingDirection.Y,
					LayoutOrder = 3,
				}, RootNodes),
			}),

			ResizerHandle = React.createElement("TextButton", {
				Size = UDim2.new(0, 10, 0, 40),
				Position = UDim2.new(1, 4, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = Color3.fromRGB(150, 150, 150),
				BackgroundTransparency = 0.5,
				Text = "",
				ZIndex = 10,

				[React.Event.InputBegan] = function(Rbx: Instance, Input: InputObject): ()
					if Input.UserInputType == Enum.UserInputType.MouseButton1 then
						SetIsResizing(true)
						SetResizeStartMouseX(Input.Position.X)
						SetResizeStartWidth(WindowWidth:getValue())
					end
				end,
			}, {
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(1, 0),
				}),
			}),
		},
	})

	if IsNodeDragging and DraggedNodeId then
		if AppState.WorkspaceElements[DraggedNodeId] then
			FragmentChildren["GhostNode"] = React.createElement("CanvasGroup", {
				Size = WindowWidth:map(function(Width: number): UDim2
					return UDim2.fromOffset(math.min(Width, MaxAllowedWidth), 0)
				end),
				
				AutomaticSize = Enum.AutomaticSize.Y,
				Position = MousePosition,
				BackgroundTransparency = 1,
				GroupTransparency = 0.2,
				Interactable = false,
				ZIndex = 10000,
			}, {
				Padding = React.createElement("UIPadding", {
					PaddingTop = UDim.new(0, 4),
					PaddingBottom = UDim.new(0, 4),
					PaddingLeft = UDim.new(0, 4),
					PaddingRight = UDim.new(0, 4),
				}),
				
				TreeContent = React.createElement(UITreeNode_Component, {
					NodeId = DraggedNodeId,
					Depth = 0,
					SelectedId = nil,
					IsGhost = true,
					LayoutOrder = 1,
				})
			})
		end
	end

	return React.createElement(React.Fragment, nil, FragmentChildren)
end

----------------------------------------------------------
return UITree_Component
----------------------------------------------------------