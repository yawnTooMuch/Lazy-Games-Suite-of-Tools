--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: UITreeNode_Component.luau
    
    SCOPE: UI Tree / Hierarchy Node UI Component
    
    ROLE: Renders an individual node item within the UI Tree hierarchy,
          supporting recursive child nesting, node expansion/collapsing,
          selection highlight, visibility toggling, and drag-and-drop interactions.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITreeNode_Component Type Structures Section
----------------------------------------------------------
export type Props = {
	NodeId: string,
	Depth: number,
	SelectedId: string?,
	LayoutOrder: number?,
	IsGhost: boolean?,
	HasSiblings: boolean?,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITreeNode_Component Dependency Section
----------------------------------------------------------
local React = require(script.Parent.Parent.Parent.Parent.Extras.React_Lua.React)
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local AppState = require(script.Parent.Parent.Parent.AppState)
local Assignment = require(script.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- UITreeNode_Component Public APIs Section
----------------------------------------------------------
--[[
Renders a node in the UI tree.

Params:
	Props: Props -- The properties for the component

Returns:
	any -- The rendered React element
]]
function UITreeNode_Component(Props: Props): any
	local Node: AppState.UIElement? = AppState.WorkspaceElements[Props.NodeId]

	if not Node then return nil end

	local HasChildren: boolean = Node.Children and #Node.Children > 0
	local IsRoot: boolean = (Props.Depth == 0)
	local HasSiblings: boolean = Props.HasSiblings or false
	local ShouldSpawnBox: boolean = IsRoot or (not HasSiblings)
	local IsExpanded: boolean, SetIsExpanded = React.useState(true)
	local ContentHeight, SetContentHeight = React.useBinding(24)
	local SiblingHeight, SetSiblingHeight = React.useBinding(0)
	local IsSelected: boolean = Props.SelectedId == Props.NodeId
	local IsDraggingMe: boolean = AppState.UITreeDragState.IsDragging and AppState.UITreeDragState.DraggedNodeId == Props.NodeId
	local IsHoveredTarget: boolean = AppState.UITreeDragState.IsDragging and AppState.UITreeDragState.HoveredTargetId == Props.NodeId
	local DragTimer = React.useRef(nil :: Assignment.Handle?)
	local HoverTimer = React.useRef(nil :: Assignment.Handle?)
	local BackgroundColor: Color3 = Color3.fromRGB(0, 0, 0)
	local Transparency: number = 1
	local ChildComponents: { [string]: any } = {}
	local IsValidSelection: boolean = IsSelected and not AppState.UITreeDragState.IsDragging
	local ShouldShowGlow: boolean = IsValidSelection or IsHoveredTarget
	local GlowColor: Color3 = Color3.fromRGB(0, 170, 255)
	
	if IsHoveredTarget then
		GlowColor = Color3.fromRGB(100, 150, 200)
	end

	-- Handles input began events to initiate node dragging after a delay.
	local function onInputBegan(Rbx: Instance, Input: InputObject): ()
		if Props.IsGhost then return end
		
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if DragTimer.current then
				Assignment.Cancel(DragTimer.current)
			end
			
			DragTimer.current = Assignment.Delay(1, function(): ()
				Relay.Create("InitiateNodeDrag_CL"):Fire(Props.NodeId)
			end)
		end
	end

	-- Handles input ended events to cancel drag initiation.
	local function onInputEnded(Rbx: Instance, Input: InputObject): ()
		if Props.IsGhost then return end
		
		if Input.UserInputType == Enum.UserInputType.MouseButton1 then
			if DragTimer.current then
				Assignment.Cancel(DragTimer.current)
				DragTimer.current = nil
			end
		end
	end

	-- Handles mouse enter events to set the node as a drag target.
	local function onMouseEnter(): ()
		if Props.IsGhost then return end
		
		if AppState.UITreeDragState.IsDragging and AppState.UITreeDragState.DraggedNodeId ~= Props.NodeId then
			if HoverTimer.current then
				Assignment.Cancel(HoverTimer.current)
			end
			
			HoverTimer.current = Assignment.Delay(0.5, function(): ()
				Relay.Create("SetNodeDragTarget_CL"):Fire(Props.NodeId)
			end)
		end
	end

	-- Handles mouse leave events to clear the node as a drag target.
	local function onMouseLeave(): ()
		if Props.IsGhost then return end
		
		if HoverTimer.current then
			Assignment.Cancel(HoverTimer.current)
			HoverTimer.current = nil
		end
		
		if AppState.UITreeDragState.IsDragging and AppState.UITreeDragState.HoveredTargetId == Props.NodeId then
			Relay.Create("SetNodeDragTarget_CL"):Fire(nil)
		end
	end

	if Props.IsGhost then
		Transparency = 1
	end

	if IsExpanded and HasChildren then
		local ChildNodes: { [string]: any } = {}
		
		ChildNodes["Layout"] = React.createElement("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
		})

		for Index: number, ChildId: string in ipairs(Node.Children) do
			ChildNodes[ChildId] = React.createElement(UITreeNode_Component, {
				NodeId = ChildId,
				Depth = Props.Depth + 1,
				SelectedId = Props.SelectedId,
				LayoutOrder = Index,
				IsGhost = Props.IsGhost,
				HasSiblings = (#Node.Children > 1),
			})
		end
		
		if #Node.Children > 1 then
			ChildComponents["VisualBox"] = React.createElement("Frame", {
				Size = SiblingHeight:map(function(Height: number): UDim2
					return UDim2.new(1, -((Props.Depth + 1) * 16) - 34, 0, Height)
				end),
				
				Position = UDim2.new(0, ((Props.Depth + 1) * 16) + 2, 0, 0),
				BackgroundColor3 = Color3.fromRGB(255, 255, 255),
				BackgroundTransparency = 1,
				ZIndex = 0,
			}, {
				Border = React.createElement("UIStroke", {
					Color = Color3.fromRGB(100, 100, 100),
					Thickness = 1,
					Transparency = 0.4,
				}),
				
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			})
		end
		
		ChildNodes["Padding"] = React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 2),
			PaddingBottom = UDim.new(0, 2),
		})
		
		ChildComponents["Content"] = React.createElement("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			
			[React.Change.AbsoluteSize] = function(Rbx: Frame)
				SetSiblingHeight(Rbx.AbsoluteSize.Y)
			end,
		}, ChildNodes)
	end

	return React.createElement("Frame", {
		AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, 0, 0, 0),
		BackgroundTransparency = 1,
		LayoutOrder = Props.LayoutOrder or 0,
	}, {
		OuterPadding = IsRoot and React.createElement("UIPadding", {
			PaddingTop = UDim.new(0, 4),
		}) or nil,
		
		NodeBox = ShouldSpawnBox and React.createElement("Frame", {
			Size = ContentHeight:map(function(Height: number): UDim2
				return UDim2.new(1, -(Props.Depth * 16) - 34, 0, Height)
			end),
			
			Position = UDim2.new(0, (Props.Depth * 16) + 2, 0, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ZIndex = 0,
		}, {
			Border = React.createElement("UIStroke", {
				Color = Color3.fromRGB(100, 100, 100),
				Thickness = 1,
				Transparency = 0.4,
			}),
			
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}) or nil,
		
		DragGlowBox = IsDraggingMe and React.createElement("Frame", {
			Size = ContentHeight:map(function(Height: number): UDim2
				return UDim2.new(1, -(Props.Depth * 16) - 34, 0, Height)
			end),
			
			Position = UDim2.new(0, (Props.Depth * 16) + 2, 0, 0),
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BackgroundTransparency = 1,
			ZIndex = 2,
		}, {
			Border = React.createElement("UIStroke", {
				Color = Color3.fromRGB(150, 150, 150),
				Thickness = 1.5,
				Transparency = 0,
			}),
			
			Corner = React.createElement("UICorner", {
				CornerRadius = UDim.new(0, 4),
			}),
		}) or nil,
		
		Content = React.createElement("Frame", {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			
			[React.Change.AbsoluteSize] = function(Rbx: Frame)
				SetContentHeight(Rbx.AbsoluteSize.Y)
			end,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingTop = UDim.new(0, 2),
				PaddingBottom = UDim.new(0, 2),
			}),
			
			Layout = React.createElement("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
			}),
		
		Row = React.createElement("TextButton", {
			LayoutOrder = 1,
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundColor3 = BackgroundColor,
			BackgroundTransparency = Transparency,
			BorderSizePixel = 0,
			Text = "",
			
			[React.Event.Activated] = function(): ()
				if Props.IsGhost then return end
				Relay.Create("SelectElement_CL"):Fire(Props.NodeId)
			end,
			
			[React.Event.InputBegan] = onInputBegan :: any,
			[React.Event.InputEnded] = onInputEnded :: any,
			[React.Event.MouseEnter] = onMouseEnter,
			[React.Event.MouseLeave] = onMouseLeave,
		}, {
			Padding = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, (Props.Depth * 16) + 2),
				PaddingRight = UDim.new(0, 8),
			}),
			
			SelectionGlow = ShouldShowGlow and React.createElement("Frame", {
				Size = UDim2.new(1, -26, 1, 0),
				Position = UDim2.new(0, 0, 0, 0),
				BackgroundTransparency = 1,
				ZIndex = 0,
			}, {
				Stroke = React.createElement("UIStroke", {
					Color = GlowColor,
					Thickness = 1.5,
				}),
				
				Corner = React.createElement("UICorner", {
					CornerRadius = UDim.new(0, 4),
				}),
			}) or nil,
			
			ToggleBtn = HasChildren and React.createElement("TextButton", {
				Size = UDim2.new(0, 16, 0, 16),
				Position = UDim2.new(0, 2, 0.5, 0),
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundTransparency = 1,
				Text = IsExpanded and "\u{25BC}" or "\u{25B6}",
				Font = Enum.Font.Gotham,
				TextSize = 15,
				TextColor3 = Color3.fromRGB(200, 200, 200),
				
				[React.Event.Activated] = function(): ()
					SetIsExpanded(not IsExpanded)
				end,
				
			}) or nil,
			
			Label = React.createElement("TextLabel", {
				Size = UDim2.new(1, -48, 1, 0),
				Position = UDim2.new(0, 24, 0, 0),
				BackgroundTransparency = 1,
				Text = Node.Name .. " (" .. Node.Type .. ")",
				TextColor3 = Color3.fromRGB(220, 220, 220),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Font = Enum.Font.Gotham,
				TextSize = 13,
			}),
			
			EyeToggle = (not Props.IsGhost) and React.createElement("TextButton", {
				Size = UDim2.fromOffset(20, 20),
				Position = UDim2.new(1, -2, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 1,
				Text = Node.Visible and "◉" or "○",
				TextColor3 = Node.Visible and Color3.fromRGB(220, 220, 220) or Color3.fromRGB(80, 80, 80),
				TextSize = 16,
				
				[React.Event.Activated] = function(): ()
					Relay.Create("ToggleElementVisibility_CL"):Fire(Props.NodeId)
				end,
			}) or nil,
		}),
		
		ChildrenContainer = HasChildren and React.createElement("Frame", {
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			BackgroundTransparency = 1,
			Visible = IsExpanded,
		}, ChildComponents) or nil,
		}),
	})
end

----------------------------------------------------------
return UITreeNode_Component
----------------------------------------------------------