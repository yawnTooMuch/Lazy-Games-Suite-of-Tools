--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: PropertyRegistry.luau
    
    SCOPE: Root Module
    
    ROLE: Central registry defining which properties each UI element and 
          modifier supports, including types, defaults, and clamps.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRegistry Type Structures Section
----------------------------------------------------------
export type PropertyDefinition = {
    Name: string,
    Category: string,
    ValueType: string,
    Default: any,
    Description: string?,
    EnumType: string?,
    EnumOptions: { string }?,
    Min: number?,
    Max: number?,
    OffsetMin: number?,
    OffsetMax: number?,
}

export type PropertyRegistry = {
	GetPropertiesForType: (ClassName: string) -> { PropertyDefinition },
	GetDefaultsForType: (ClassName: string) -> { [string]: any },
	GetModifierProperties: (ModifierType: string) -> { PropertyDefinition }?,
	GetModifierDefaults: (ModifierType: string) -> { [string]: any }?,
	GetAvailableModifiers: () -> { string },
	IsModifierCompatible: (ModifierType: string, ElementType: string) -> boolean,
	GetConflictingModifier: (ModifierType: string, ExistingProperties: { [string]: any }) -> string?,
	GetCompatibleModifiersForType: (ElementType: string) -> { string },
	AllowsMultipleInstances: (ModifierType: string) -> boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRegistry Internal States Section
----------------------------------------------------------
local PropertyRegistry = {}

local Traits: { [string]: { PropertyDefinition } } = {
	Base = {
		{ 
			Name = "Name",
			Description = "The unique identifier name of the element.",
			Category = "Identity",
			ValueType = "string",
			Default = "" 
		},
		
		{ 
			Name = "Position",
			Description = "The 2D coordinate where the element is rendered relative to its parent.",
			Category = "Transform",
			ValueType = "UDim2",
			Default = UDim2.fromOffset(0, 0),
			Min = 0,
			Max = 1
		},
		
		{ 
			Name = "Size",
			Description = "The 2D dimensions of the element.",
			Category = "Transform", 
			ValueType = "UDim2",
			Default = UDim2.fromOffset(100, 100),
			Min = 0,
			Max = 1,
			OffsetMin = 1
		},
		
		{ 
			Name = "AnchorPoint",
			Description = "The origin point used for calculating Position and Size (0 to 1).",
			Category = "Transform",
			ValueType = "Vector2",
			Default = Vector2.new(0.5, 0.5)
		},
		
		{ 
			Name = "Rotation",
			Description = "The rotation angle of the element in degrees.", 
			Category = "Transform", 
			ValueType = "number",
			Default = 0 
		},
		
		{
			Name = "AutomaticSize",
			Description = "Automatically resizes the element based on its content.",
			Category = "Transform",
			ValueType = "Enum",
			EnumType = "AutomaticSize",
			EnumOptions = { "None", "X", "Y", "XY" },
			Default = Enum.AutomaticSize.None
		},
		
		{
			Name = "SizeConstraint",
			Description = "Constrains how the UI scales relative to its parent.",
			Category = "Transform",
			ValueType = "Enum",
			EnumType = "SizeConstraint",
			EnumOptions = { "RelativeXY", "RelativeXX", "RelativeYY" },
			Default = Enum.SizeConstraint.RelativeXY
		},
		
		{ 
			Name = "Visible",
			Description = "Toggles whether the element is rendered on screen.",
			Category = "Appearance",
			ValueType = "boolean",
			Default = true
		},
		
		{ 
			Name = "BackgroundColor3",
			Description = "The background color of the element.", 
			Category = "Appearance",
			ValueType = "Color3",
			Default = Color3.fromRGB(200, 200, 200)
		},
		
		{ 
			Name = "BackgroundTransparency",
			Description = "The opacity of the element's background (0 = Solid, 1 = Invisible).", 
			Category = "Appearance", 
			ValueType = "number", 
			Default = 0,
			Min = 0,
			Max = 1 
		},
		
		{
			Name = "BorderColor3",
			Description = "The color of the element's border.", 
			Category = "Appearance",
			ValueType = "Color3", 
			Default = Color3.fromRGB(50, 50, 50)
		},
		
		{ 
			Name = "BorderSizePixel",
			Description = "The thickness of the element's border in pixels.",
			Category = "Appearance",
			ValueType = "number",
			Default = 1,
			Min = 0
		},
		
		{
			Name = "BorderMode",
			Description = "Determines how the border is drawn relative to the element's bounds.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "BorderMode",
			EnumOptions = { "Outline", "Middle", "Inset" },
			Default = Enum.BorderMode.Outline
		},
		
		{ 
			Name = "ZIndex",
			Description = "The rendering order of the element. Higher values render on top.",
			Category = "Appearance",
			ValueType = "number",
			Default = 1 
		},
		
		{ 
			Name = "LayoutOrder",
			Description = "The sorting order of this element when placed inside a UIListLayout or UIGridLayout.",
			Category = "Appearance",
			ValueType = "number",
			Default = 0 
		},
		
		{
			Name = "ClipsDescendants",
			Description = "Clips any child elements that render outside this element's bounds.", 
			Category = "Appearance", 
			ValueType = "boolean",
			Default = false 
		},
		
		{
			Name = "Active",
			Description = "Determines if the element sinks input events.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = false
		},
		
		{
			Name = "Interactable",
			Description = "Determines if the element can be interacted with.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = true
		},
		
		{
			Name = "Selectable",
			Description = "Determines whether the element can be focused and selected during navigation.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = false
		},
		
		{
			Name = "SelectionGroup",
			Description = "Determines whether the element acts as an isolated navigation group container.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = false
		},
	},
	
	Frame = {
		{
			Name = "Style",
			Description = "Defines a preset visual style and border skin for the frame.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "FrameStyle",
			EnumOptions = { "Custom", "ChatBlue", "RobloxSquare", "RobloxRound", "ChatGreen", "ChatRed", "DropShadow" },
			Default = Enum.FrameStyle.Custom
		},
	},
	
	Text = {
		{
			Name = "Text",
			Description = "The text content displayed by the element.",
			Category = "Text", 
			ValueType = "string",
		},
		
		{
			Name = "TextColor3",
			Description = "The color of the text.", 
			Category = "Text", 
			ValueType = "Color3",
			Default = Color3.fromRGB(0, 0, 0) 
		},
		
		{ 
			Name = "TextTransparency",
			Description = "The opacity of the text (0 = Solid, 1 = Invisible).",
			Category = "Text", 
			ValueType = "number",
			Default = 0,
			Min = 0,
			Max = 1 
		},
		
		{ 
			Name = "TextSize",
			Description = "The font size of the text.",
			Category = "Text", 
			ValueType = "number",
			Default = 14,
			Min = 1,
			Max = 100
		},
		
		{ 
			Name = "Font",
			Description = "The font face used to render the text.",
			Category = "Text",
			ValueType = "Enum",
			EnumType = "Font",
			EnumOptions = { "Legacy", "Arial", "ArialBold", "SourceSans", "SourceSansBold", "SourceSansLight", "SourceSansItalic", "Bodoni", "Garamond", "Cartoon", "Code", "Highway", "SciFi", "Arcade", "Fantasy", "Antique", "SourceSansSemibold", "Gotham", "GothamMedium", "GothamBold", "GothamBlack", "AmaticSC", "Bangers", "Creepster", "DenkOne", "Fondamento", "FredokaOne", "GrenzeGotisch", "IndieFlower", "JosefinSans", "Jura", "Kalam", "LuckiestGuy", "Merriweather", "Michroma", "Nunito", "Oswald", "PatrickHand", "PermanentMarker", "Roboto", "RobotoCondensed", "RobotoMono", "Sarpanch", "SpecialElite", "TitilliumWeb", "Ubuntu", "BuilderSans", "BuilderSansMedium", "BuilderSansBold", "BuilderSansExtraBold", "Arimo", "ArimoBold", "Unknown" },
			Default = Enum.Font.Gotham 
		},
		
		{ 
			Name = "TextXAlignment",
			Description = "Horizontal alignment of the text.",
			Category = "Text",
			ValueType = "Enum",
			EnumType = "TextXAlignment",
			EnumOptions = { "Left", "Right", "Center" },
			Default = Enum.TextXAlignment.Center 
		},
		
		{
			Name = "TextYAlignment",
			Description = "Vertical alignment of the text.", 
			Category = "Text", 
			ValueType = "Enum", 
			EnumType = "TextYAlignment",
			EnumOptions = { "Top", "Center", "Bottom" },
			Default = Enum.TextYAlignment.Center
		},
		
		{ 
			Name = "TextWrapped",
			Description = "Wraps text to the next line if it exceeds the element's width.", 
			Category = "Text", 
			ValueType = "boolean",
			Default = false
		},
		
		{ 
			Name = "TextScaled",
			Description = "Automatically scales the text to fit within the element's bounds.", 
			Category = "Text",
			ValueType = "boolean",
			Default = false 
		},
		
		{
			Name = "RichText",
			Description = "Enables HTML-like tags for styling specific parts of the text.",
			Category = "Text",
			ValueType = "boolean",
			Default = false
		},
		
		{
			Name = "LineHeight",
			Description = "Sets the line spacing multiplier between lines of wrapped or multi-line text.",
			Category = "Text",
			ValueType = "number",
			Default = 1,
			Min = 0
		},
		
		{
			Name = "MaxVisibleGraphemes",
			Description = "Limits the total number of characters displayed on screen.",
			Category = "Text",
			ValueType = "number",
			Default = -1,
			Min = -1
		},
		
		{
			Name = "TextStrokeColor3",
			Description = "The color of the outline stroke rendered around the text.",
			Category = "Text",
			ValueType = "Color3",
			Default = Color3.fromRGB(0, 0, 0)
		},
		
		{
			Name = "TextStrokeTransparency",
			Description = "The opacity of the text outline stroke (0 = Solid, 1 = Invisible).",
			Category = "Text",
			ValueType = "number",
			Default = 1,
			Min = 0,
			Max = 1
		},
		
		{
			Name = "TextDirection",
			Description = "Controls the reading layout flow direction of the text.",
			Category = "Text",
			ValueType = "Enum",
			EnumType = "TextDirection",
			EnumOptions = { "Auto", "LeftToRight", "RightToLeft" },
			Default = Enum.TextDirection.Auto
		},
		
		{
			Name = "TextTruncate",
			Description = "Determines how text that overflows the container bounds is truncated.",
			Category = "Text",
			ValueType = "Enum",
			EnumType = "TextTruncate",
			EnumOptions = { "None", "AtEnd", "SplitWord" },
			Default = Enum.TextTruncate.None
		},
	},
	
	TextBox = {
		{ 
			Name = "PlaceholderText",
			Description = "The hint text displayed inside the text box when empty and not focused.",
			Category = "Text",
			ValueType = "string", 
		},
		
		{ 
			Name = "PlaceholderColor3", 
			Description = "The color of the placeholder hint text.",
			Category = "Text",
			ValueType = "Color3",
			Default = Color3.fromRGB(178, 178, 178) 
		},
		
		{ 
			Name = "ClearTextOnFocus",
			Description = "Clears existing text when the user focuses the input field.",
			Category = "Text",
			ValueType = "boolean", 
			Default = true 
		},
		
		{ 
			Name = "MultiLine", 
			Description = "Allows the input field to accept newlines and span multiple lines.",
			Category = "Text",
			ValueType = "boolean",
			Default = false 
		},
		
		{
			Name = "TextEditable",
			Description = "Determines whether the user is permitted to edit the text inside the box.",
			Category = "Text",
			ValueType = "boolean",
			Default = true
		},
		
		{
			Name = "ShowNativeInput",
			Description = "Determines whether mobile devices use their native keyboard overlay when focused.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = true
		},
	},
	
	Image = {
		{
			Name = "Image",
			Description = "The asset ID of the image to display.", 
			Category = "Image",
			ValueType = "string",
			Default = ""
		},
		
		{ 
			Name = "ImageColor3",
			Description = "The tint color applied to the image.", 
			Category = "Image",
			ValueType = "Color3", 
			Default = Color3.fromRGB(255, 255, 255) 
		},
		
		{ 
			Name = "ImageTransparency",
			Description = "The opacity of the image (0 = Solid, 1 = Invisible).",
			Category = "Image", 
			ValueType = "number", 
			Default = 0,
			Min = 0, 
			Max = 1 
		},
		
		{
			Name = "ScaleType",
			Description = "Determines how the image scales to fit the element's bounds.",
			Category = "Image", 
			ValueType = "Enum",
			EnumType = "ScaleType",
			EnumOptions = { "Stretch", "Slice", "Tile", "Fit", "Crop" },
			Default = Enum.ScaleType.Stretch 
		},
		
		{
			Name = "ResampleMode",
			Description = "Specifies the texture sampling and filtering algorithm applied when scaling the image.",
			Category = "Image",
			ValueType = "Enum",
			EnumType = "ResamplerMode",
			EnumOptions = { "Default", "Pixelated" },
			Default = Enum.ResamplerMode.Default
		},
		
		{
			Name = "ImageRectOffset",
			Description = "The X and Y offset of the image's source rect.",
			Category = "Image",
			ValueType = "Vector2",
			Default = Vector2.new(0, 0)
		},
		
		{
			Name = "ImageRectSize",
			Description = "The width and height of the image's source rect.",
			Category = "Image",
			ValueType = "Vector2",
			Default = Vector2.new(0, 0)
		},
		
		{
			Name = "TileSize",
			Description = "The dimensions of each repeating image tile when ScaleType is set to Tile.",
			Category = "Image",
			ValueType = "UDim2",
			Default = UDim2.fromOffset(100, 100)
		},
		
		{
			Name = "SliceScale",
			Description = "The scale factor of the 9-slice border corners when ScaleType is set to Slice.",
			Category = "Image",
			ValueType = "number",
			Default = 1,
			Min = 0
		},
	},
	
	Button = {
		{ 
			Name = "AutoButtonColor",
			Description = "Automatically darkens the button when hovered or pressed.", 
			Category = "Behavior",
			ValueType = "boolean", 
			Default = true 
		},
		
		{
			Name = "Modal",
			Description = "Forces the mouse cursor to remain unlocked and visible on screen while the button is visible.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = false
		},
		
		{
			Name = "Selected",
			Description = "Determines whether the button is currently in an active or toggled selected state.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = false
		},
		
		{
			Name = "Style",
			Description = "Applies a preset visual styling and click animation to the button.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "ButtonStyle",
			EnumOptions = { "Custom", "RobloxButtonDefault", "RobloxButton", "RobloxRoundButton", "RobloxRoundDefaultButton", "RobloxRoundDropdownButton" },
			Default = Enum.ButtonStyle.Custom
		},
	},
	
	ImageButton = {
		{
			Name = "HoverImage",
			Description = "The asset ID of the image displayed when the mouse cursor hovers over the button.",
			Category = "Image",
			ValueType = "string",
			Default = ""
		},
		
		{
			Name = "PressedImage",
			Description = "The asset ID of the image displayed while the button is actively pressed.",
			Category = "Image",
			ValueType = "string",
			Default = ""
		},
	},
	
	Scrolling = {
		{
			Name = "CanvasSize",
			Description = "The total scrollable area of the canvas.", 
			Category = "Scrolling", 
			ValueType = "UDim2", 
			Default = UDim2.fromOffset(0, 0)
		},
		
		{ 
			Name = "CanvasPosition",
			Description = "The current scroll position of the canvas.",
			Category = "Scrolling", 
			ValueType = "Vector2",
			Default = Vector2.new(0, 0) 
		},
		
		{ 
			Name = "ScrollBarThickness",
			Description = "The thickness of the scroll bar in pixels.",
			Category = "Scrolling", 
			ValueType = "number", 
			Default = 12,
			Min = 0 
		},
		
		{ 
			Name = "ScrollingDirection",
			Description = "The allowed axis for scrolling (X, Y, or XY).",
			Category = "Scrolling",
			ValueType = "Enum", 
			EnumType = "ScrollingDirection",
			EnumOptions = { "X", "Y", "XY" },
			Default = Enum.ScrollingDirection.XY 
		},
		
		{
			Name = "AutomaticCanvasSize",
			Description = "Automatically resizes the canvas based on its content.",
			Category = "Scrolling",
			ValueType = "Enum",
			EnumType = "AutomaticSize",
			EnumOptions = { "None", "X", "Y", "XY" },
			Default = Enum.AutomaticSize.None
		},
		
		{
			Name = "ScrollingEnabled",
			Description = "Determines whether user input is allowed to scroll the canvas.",
			Category = "Scrolling",
			ValueType = "boolean",
			Default = true
		},
		
		{
			Name = "ElasticBehavior",
			Description = "Controls the rubber-band elastic bounce effect when scrolling past canvas edges.",
			Category = "Scrolling",
			ValueType = "Enum",
			EnumType = "ElasticBehavior",
			EnumOptions = { "WhenScrollable", "Always", "Never" },
			Default = Enum.ElasticBehavior.WhenScrollable
		},
		
		{
			Name = "HorizontalScrollBarInset",
			Description = "Determines whether the horizontal scrollbar displaces the inner canvas area or overlaps it.",
			Category = "Scrolling",
			ValueType = "Enum",
			EnumType = "ScrollBarInset",
			EnumOptions = { "None", "ScrollBar", "Always" },
			Default = Enum.ScrollBarInset.None
		},
		
		{
			Name = "VerticalScrollBarInset",
			Description = "Determines whether the vertical scrollbar displaces the inner canvas area or overlaps it.",
			Category = "Scrolling",
			ValueType = "Enum",
			EnumType = "ScrollBarInset",
			EnumOptions = { "None", "ScrollBar", "Always" },
			Default = Enum.ScrollBarInset.None
		},
		
		{
			Name = "VerticalScrollBarPosition",
			Description = "Determines which side of the frame the vertical scrollbar appears on.",
			Category = "Scrolling",
			ValueType = "Enum",
			EnumType = "VerticalScrollBarPosition",
			EnumOptions = { "Right", "Left" },
			Default = Enum.VerticalScrollBarPosition.Right
		},
		
		{
			Name = "ScrollBarImageColor3",
			Description = "The color of the scroll bar.",
			Category = "Scrolling",
			ValueType = "Color3",
			Default = Color3.fromRGB(0, 0, 0)
		},
		
		{
			Name = "ScrollBarImageTransparency",
			Description = "The opacity of the scroll bar.",
			Category = "Scrolling",
			ValueType = "number",
			Default = 0,
			Min = 0,
			Max = 1
		},
		
		{
			Name = "TopImage",
			Description = "The asset ID for the top or left end-cap image of the scrollbar thumb.",
			Category = "Scrolling",
			ValueType = "string",
			Default = "rbxasset://textures/ui/Scroll/scroll-top.png"
		},
		
		{
			Name = "MidImage",
			Description = "The asset ID for the middle segment image of the scrollbar thumb.",
			Category = "Scrolling",
			ValueType = "string",
			Default = "rbxasset://textures/ui/Scroll/scroll-middle.png"
		},
		
		{
			Name = "BottomImage",
			Description = "The asset ID for the bottom or right end-cap image of the scrollbar thumb.",
			Category = "Scrolling",
			ValueType = "string",
			Default = "rbxasset://textures/ui/Scroll/scroll-bottom.png"
		},
	},
	
	CanvasGroup = {
		{
			Name = "GroupColor3",
			Description = "Applies a unified color tint across the entire group and its children.",
			Category = "Appearance",
			ValueType = "Color3", 
			Default = Color3.fromRGB(255, 255, 255) 
		},
		
		{ 
			Name = "GroupTransparency",
			Description = "The opacity of the group and all descendants rendered as a single composited layer (0 = Solid, 1 = Invisible).",
			Category = "Appearance",
			ValueType = "number", 
			Default = 0,
			Min = 0,
			Max = 1 
		},
	},
	
	Video = {
		{
			Name = "Video",
			Description = "The asset ID of the video resource to load and display.",
			Category = "Video", 
			ValueType = "string",
			Default = "" 
		},
		
		{ 
			Name = "Playing",
			Description = "Controls whether video playback is currently active.",
			Category = "Video", 
			ValueType = "boolean",
			Default = false 
		},
		
		{ 
			Name = "Looped", 
			Description = "Determines whether the video automatically repeats playback when finished.",
			Category = "Video",
			ValueType = "boolean",
			Default = false 
		},
		
		{ 
			Name = "Volume", 
			Description = "The playback audio volume level of the video.",
			Category = "Video",
			ValueType = "number",
			Default = 1, 
			Min = 0, 
			Max = 10
		},
		
		{
			Name = "TimePosition",
			Description = "The current video playback position in seconds.",
			Category = "Video",
			ValueType = "number",
			Default = 0,
			Min = 0
		},
		
		{
			Name = "RollOffMode",
			Description = "Specifies the 3D audio distance attenuation curve for video playback.",
			Category = "Video",
			ValueType = "Enum",
			EnumType = "RollOffMode",
			EnumOptions = { "Inverse", "Linear", "LinearSquare", "InverseTapered" },
			Default = Enum.RollOffMode.Inverse
		},
		
		{
			Name = "RollOffMinDistance",
			Description = "The minimum 3D distance threshold where audio volume begins to drop off.",
			Category = "Video",
			ValueType = "number",
			Default = 1,
			Min = 0
		},
		
		{
			Name = "RollOffMaxDistance",
			Description = "The maximum 3D distance beyond which video audio is no longer audible.",
			Category = "Video",
			ValueType = "number",
			Default = 10000,
			Min = 0
		},
	},
	
	Viewport = {
		{
			Name = "Ambient", 
			Description = "The ambient background light color applied to 3D objects in the viewport.",
			Category = "Viewport", 
			ValueType = "Color3", 
			Default = Color3.fromRGB(200, 200, 200)
		},
		
		{ 
			Name = "LightColor",
			Description = "The color of the directional light source in the viewport.",
			Category = "Viewport",
			ValueType = "Color3", 
			Default = Color3.fromRGB(140, 140, 140) 
		},
		
		{ 
			Name = "LightDirection",
			Description = "The 3D direction vector of the light source in the viewport.",
			Category = "Viewport", 
			ValueType = "Vector3",
			Default = Vector3.new(-1, -1, -1)
		},
		
		{
			Name = "ImageColor3",
			Description = "The tint color applied to the image.",
			Category = "Viewport",
			ValueType = "Color3",
			Default = Color3.fromRGB(255, 255, 255)
		},
		
		{
			Name = "ImageTransparency",
			Description = "The opacity of the image (0 = Solid, 1 = Invisible).",
			Category = "Viewport",
			ValueType = "number",
			Default = 0,
			Min = 0,
			Max = 1
		},
	},
}

local ElementTraitMap: { [string]: { string } } = {
	Frame = { "Base", "Frame" },
	TextLabel = { "Base", "Text" },
	TextButton = { "Base", "Text", "Button" },
	TextBox = { "Base", "Text", "TextBox" },
	ImageLabel = { "Base", "Image" },
	ImageButton = { "Base", "Image", "Button", "ImageButton" },
	ScrollingFrame = { "Base", "Scrolling" },
	CanvasGroup = { "Base", "CanvasGroup" },
	VideoFrame = { "Base", "Video" },
	ViewportFrame = { "Base", "Viewport" },
}

local Modifiers: { [string]: { PropertyDefinition } } = {
	UICorner = {
		{ 
			Name = "CornerRadius",
			Description = "The radius of the rounded corners.", 
			Category = "Appearance",
			ValueType = "UDim",
			Default = UDim.new(0, 8)
		},
	},
	
	UIPadding = {
		{ 
			Name = "PaddingTop",
			Description = "Empty space inside the top edge.",
			Category = "Layout", 
			ValueType = "UDim",
			Default = UDim.new(0, 0) 
		},
		
		{
			Name = "PaddingBottom",
			Description = "Empty space inside the bottom edge.",
			Category = "Layout",
			ValueType = "UDim", 
			Default = UDim.new(0, 0) 
		},
		
		{
			Name = "PaddingLeft",
			Description = "Empty space inside the left edge.", 
			Category = "Layout",
			ValueType = "UDim", 
			Default = UDim.new(0, 0)
		},
		
		{ 
			Name = "PaddingRight",
			Description = "Empty space inside the right edge.", 
			Category = "Layout", 
			ValueType = "UDim",
			Default = UDim.new(0, 0) 
		},
	},
	
	UIStroke = {
		{
			Name = "Enabled",
			Description = "Determines whether the stroke modifier is actively applied.",
			Category = "Appearance",
			ValueType = "boolean",
			Default = true,
		},
		
		{
			Name = "Color",
			Description = "The color of the UI stroke.",
			Category = "Appearance",
			ValueType = "Color3", 
			Default = Color3.fromRGB(0, 0, 0) 
		},
		
		{ 
			Name = "Thickness",
			Description = "The thickness of the UI stroke in pixels.", 
			Category = "Appearance",
			ValueType = "number",
			Default = 1, 
			Min = 0
		},
		
		{ 
			Name = "Transparency",
			Description = "The opacity of the UI stroke.", 
			Category = "Appearance",
			ValueType = "number", 
			Default = 0,
			Min = 0, 
			Max = 1 
		},
		
		{
			Name = "ApplyStrokeMode",
			Description = "Determines if the stroke is applied to the text or the border.", 
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "ApplyStrokeMode", 
			EnumOptions = { "Contextual", "Border" },
			Default = Enum.ApplyStrokeMode.Contextual
		},
		
		{
			Name = "LineJoinMode",
			Description = "How the corners of the stroke are rendered.", 
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "LineJoinMode", 
			EnumOptions = { "Round", "Bevel", "Miter" },
			Default = Enum.LineJoinMode.Round
		},
	},
	
	UIAspectRatioConstraint = {
		{ 
			Name = "AspectRatio", 
			Description = "Determines the width-to-height ratio to enforce on the parent element regardless of its base size.",
			Category = "Layout", 
			ValueType = "number", 
			Default = 1,
			Min = 0.001 
		},
		
		{ 
			Name = "DominantAxis", 
			Description = "Specifies which axis takes priority when recalculating dimensions if the element exceeds its container.",
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "DominantAxis", 
			EnumOptions = { "Width", "Height" },
			Default = Enum.DominantAxis.Width
		},
		
		{ 
			Name = "AspectType",
			Description = "Controls how maximum bounds are calculated, either within the element's own dimensions or scaling with the parent container.",
			Category = "Layout", 
			ValueType = "Enum",
			EnumType = "AspectType",
			EnumOptions = { "FitWithinMaxSize", "ScaleWithParentSize" },
			Default = Enum.AspectType.FitWithinMaxSize 
		},
	},
	
	UIListLayout = {
		{
			Name = "FillDirection",
			Description = "The direction in which children are laid out.",
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "FillDirection",
			EnumOptions = { "Vertical", "Horizontal" },
			Default = Enum.FillDirection.Vertical 
		},
		
		{ 
			Name = "HorizontalAlignment",
			Description = "The horizontal alignment of laid out children.", 
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "HorizontalAlignment",
			EnumOptions = { "Left", "Center", "Right" },
			Default = Enum.HorizontalAlignment.Left 
		},
		
		{ 
			Name = "VerticalAlignment",
			Description = "The vertical alignment of laid out children.",
			Category = "Layout",
			ValueType = "Enum", 
			EnumType = "VerticalAlignment",
			EnumOptions = { "Top", "Center", "Bottom" },
			Default = Enum.VerticalAlignment.Top 
		},
		
		{ 
			Name = "Padding",
			Description = "The spacing between laid out children.", 
			Category = "Layout", 
			ValueType = "UDim",
			Default = UDim.new(0, 0) 
		},
		
		{ 
			Name = "SortOrder",
			Description = "How children are sorted (LayoutOrder or Name).",
			Category = "Layout", 
			ValueType = "Enum",
			EnumType = "SortOrder", 
			EnumOptions = { "LayoutOrder", "Name" },
			Default = Enum.SortOrder.LayoutOrder 
		},
		
		{
			Name = "Wraps",
			Description = "Determines whether children wrap onto multiple lines when exceeding container dimensions.",
			Category = "Layout",
			ValueType = "boolean",
			Default = false,
		},
		
		{
			Name = "HorizontalFlex",
			Description = "Controls horizontal flex distribution across the layout axis.",
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "UIFlexAlignment",
			EnumOptions = { "None", "Fill", "SpaceAround", "SpaceBetween", "SpaceEvenly" },
			Default = Enum.UIFlexAlignment.None,
		},
		
		{
			Name = "VerticalFlex",
			Description = "Controls vertical flex distribution across the layout axis.",
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "UIFlexAlignment",
			EnumOptions = { "None", "Fill", "SpaceAround", "SpaceBetween", "SpaceEvenly" },
			Default = Enum.UIFlexAlignment.None,
		},
		
		{
			Name = "ItemLineAlignment",
			Description = "Controls cross-axis alignment for wrapped items in multi-line layouts.",
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "ItemLineAlignment",
			EnumOptions = { "Automatic", "Start", "Center", "End", "Stretch" },
			Default = Enum.ItemLineAlignment.Automatic,
		},
	},
	
	UIGridLayout = {
		{
			Name = "CellPadding",
			Description = "The spacing between grid cells.",
			Category = "Layout",
			ValueType = "UDim2",
			Default = UDim2.fromOffset(5, 5)
		},
		
		{
			Name = "CellSize",
			Description = "The fixed size of each grid cell.",
			Category = "Layout",
			ValueType = "UDim2",
			Default = UDim2.fromOffset(100, 100)
		},
		
		{
			Name = "FillDirection",
			Description = "The direction in which children are laid out.",
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "FillDirection",
			EnumOptions = { "Horizontal", "Vertical" },
			Default = Enum.FillDirection.Horizontal 
		},
		
		{
			Name = "FillDirectionMaxCells",
			Description = "Sets the maximum number of grid cells placed along the primary fill axis before breaking into a new row or column.",
			Category = "Layout",
			ValueType = "number",
			Default = 0,
			Min = 0
		},
		
		{ 
			Name = "HorizontalAlignment",
			Description = "The horizontal alignment of laid out children.", 
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "HorizontalAlignment",
			EnumOptions = { "Left", "Center", "Right" },
			Default = Enum.HorizontalAlignment.Left 
		},
		
		{ 
			Name = "VerticalAlignment",
			Description = "The vertical alignment of laid out children.",
			Category = "Layout",
			ValueType = "Enum", 
			EnumType = "VerticalAlignment",
			EnumOptions = { "Top", "Center", "Bottom" },
			Default = Enum.VerticalAlignment.Top 
		},
		
		{ 
			Name = "SortOrder",
			Description = "How children are sorted (LayoutOrder or Name).",
			Category = "Layout", 
			ValueType = "Enum",
			EnumType = "SortOrder", 
			EnumOptions = { "LayoutOrder", "Name" },
			Default = Enum.SortOrder.LayoutOrder 
		},
		
		{
			Name = "StartCorner",
			Description = "The corner where the grid layout begins.",
			Category = "Layout",
			ValueType = "Enum",
			EnumType = "StartCorner",
			EnumOptions = { "TopLeft", "TopRight", "BottomLeft", "BottomRight" },
			Default = Enum.StartCorner.TopLeft
		},
	},
	
	UIGradient = {
		{
			Name = "Enabled",
			Description = "Determines whether the gradient modifier is actively applied.",
			Category = "Appearance",
			ValueType = "boolean",
			Default = true,
		},
		
		{
			Name = "Color",
			Description = "The color sequence defining the gradient stops.",
			Category = "Appearance",
			ValueType = "ColorSequence",
			Default = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(100, 100, 100)),
		},
		
		{
			Name = "Transparency",
			Description = "The transparency sequence defining the opacity ramp.",
			Category = "Appearance",
			ValueType = "NumberSequence",
			Default = NumberSequence.new(0),
		},
		
		{
			Name = "Offset",
			Description = "Determines the scalar translation offset of the gradient relative to the parent element.",
			Category = "Appearance",
			ValueType = "Vector2",
			Default = Vector2.new(0, 0),
			Min = -1,
			Max = 1,
		},
		
		{
			Name = "Rotation",
			Description = "The rotation angle of the element in degrees.",
			Category = "Appearance",
			ValueType = "number",
			Default = 0,
		},
	},
	
	UIScale = {
		{
			Name = "Scale",
			Description = "Acts as a direct numerical scaling multiplier applied to the parent element's dimensions.",
			Category = "Transform",
			ValueType = "number",
			Default = 1,
			Min = 0.001
		},
	},
	
	UISizeConstraint = {
		{
			Name = "MaxSize",
			Description = "The maximum allowed width and height in pixels the parent element can reach.",
			Category = "Transform",
			ValueType = "Vector2",
			Default = Vector2.new(99999, 99999)
		},
		
		{
			Name = "MinSize",
			Description = "The minimum allowed width and height in pixels below which the parent element cannot shrink.",
			Category = "Transform",
			ValueType = "Vector2",
			Default = Vector2.new(0, 0)
		},
	},
	
	UITextSizeConstraint = {
		{
			Name = "MaxTextSize",
			Description = "Sets the upper font size limit for rendered text when TextScaled is enabled.",
			Category = "Transform",
			ValueType = "number",
			Default = 100,
			Min = 1
		},
		
		{
			Name = "MinTextSize",
			Description = "Sets the lower font size limit for rendered text when TextScaled is enabled to prevent text from becoming unreadable.",
			Category = "Transform",
			ValueType = "number",
			Default = 1,
			Min = 1
		},
	},

	UIFlexItem = {
		{
			Name = "FlexMode",
			Description = "Defines how the object responds to available space within the flex line.",
			Category = "Transform",
			ValueType = "Enum",
			EnumType = "UIFlexMode",
			EnumOptions = { "None", "Fill", "Grow", "Shrink", "Custom" },
			Default = Enum.UIFlexMode.None,
		},
		
		{
			Name = "GrowRatio",
			Description = "Determines how much the object grows relative to other flex items when extra space is available.",
			Category = "Transform",
			ValueType = "number",
			Default = 0,
			Min = 0,
		},
		
		{
			Name = "ShrinkRatio",
			Description = "Determines how much the object shrinks relative to other flex items when the line overflows.",
			Category = "Transform",
			ValueType = "number",
			Default = 0,
			Min = 0,
		},
		
		{
			Name = "ItemLineAlignment",
			Description = "Controls the cross-axis alignment of this specific GuiObject within its flex line.",
			Category = "Transform",
			ValueType = "Enum",
			EnumType = "ItemLineAlignment",
			EnumOptions = { "Automatic", "Start", "Center", "End", "Stretch" },
			Default = Enum.ItemLineAlignment.Automatic,
		},
	},

	UIPageLayout = {
		{
			Name = "Animated",
			Description = "Determines if transitions between pages are animated.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = true,
		},
		
		{
			Name = "Circular",
			Description = "If enabled, navigating past the last page wraps around to the first page.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = false,
		},
		
		{
			Name = "FillDirection",
			Description = "Defines the axis along which pages are positioned.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "FillDirection",
			EnumOptions = { "Horizontal", "Vertical" },
			Default = Enum.FillDirection.Horizontal,
		},
		
		{
			Name = "HorizontalAlignment",
			Description = "Controls the horizontal alignment of the pages.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "HorizontalAlignment",
			EnumOptions = { "Left", "Center", "Right" },
			Default = Enum.HorizontalAlignment.Center,
		},
		
		{
			Name = "VerticalAlignment",
			Description = "Controls the vertical alignment of the pages.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "VerticalAlignment",
			EnumOptions = { "Top", "Center", "Bottom" },
			Default = Enum.VerticalAlignment.Center,
		},
		
		{
			Name = "SortOrder",
			Description = "Determines the sequence in which the pages are arranged.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "SortOrder",
			EnumOptions = { "LayoutOrder", "Name" },
			Default = Enum.SortOrder.LayoutOrder,
		},
		
		{
			Name = "Padding",
			Description = "The amount of space between adjacent pages.",
			Category = "Appearance",
			ValueType = "UDim",
			Default = UDim.new(0, 0),
		},
		
		{
			Name = "TweenTime",
			Description = "The duration in seconds for the animation transition between pages.",
			Category = "Behavior",
			ValueType = "number",
			Default = 0.5,
			Min = 0,
		},
		
		{
			Name = "EasingDirection",
			Description = "Defines the direction of the easing curve.",
			Category = "Behavior",
			ValueType = "Enum",
			EnumType = "EasingDirection",
			EnumOptions = { "In", "Out", "InOut" },
			Default = Enum.EasingDirection.Out,
		},
		
		{
			Name = "EasingStyle",
			Description = "Sets the style of the easing animation curve.",
			Category = "Behavior",
			ValueType = "Enum",
			EnumType = "EasingStyle",
			EnumOptions = { "Linear", "Sine", "Back", "Quad", "Quart", "Quint", "Bounce", "Elastic", "Exponential", "Circular", "Cubic" },
			Default = Enum.EasingStyle.Sine,
		},
		
		{
			Name = "ScrollWheelInputEnabled",
			Description = "Whether mouse scroll wheel input can trigger page changes.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = true,
		},
		
		{
			Name = "TouchInputEnabled",
			Description = "Whether touch swipe input can trigger page changes.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = true,
		},
		
		{
			Name = "GamepadInputEnabled",
			Description = "Whether gamepad bumper inputs can trigger page changes.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = true,
		},
	},

	UITableLayout = {
		{
			Name = "MajorAxis",
			Description = "Determines whether sibling elements are primarily treated as rows or columns.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "TableMajorAxis",
			EnumOptions = { "RowMajor", "ColumnMajor" },
			Default = Enum.TableMajorAxis.RowMajor,
		},
		
		{
			Name = "FillDirection",
			Description = "Determines whether table cells fill horizontally or vertically.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "FillDirection",
			EnumOptions = { "Horizontal", "Vertical" },
			Default = Enum.FillDirection.Horizontal,
		},
		
		{
			Name = "HorizontalAlignment",
			Description = "Aligns content within the table cells horizontally.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "HorizontalAlignment",
			EnumOptions = { "Left", "Center", "Right" },
			Default = Enum.HorizontalAlignment.Center,
		},
		
		{
			Name = "VerticalAlignment",
			Description = "Aligns content within the table cells vertically.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "VerticalAlignment",
			EnumOptions = { "Top", "Center", "Bottom" },
			Default = Enum.VerticalAlignment.Center,
		},
		
		{
			Name = "SortOrder",
			Description = "Determines the order in which elements are laid out.",
			Category = "Appearance",
			ValueType = "Enum",
			EnumType = "SortOrder",
			EnumOptions = { "LayoutOrder", "Name" },
			Default = Enum.SortOrder.LayoutOrder,
		},
		
		{
			Name = "FillEmptySpaceColumns",
			Description = "When enabled, expands cell widths to fill available container space.",
			Category = "Appearance",
			ValueType = "boolean",
			Default = false,
		},
		
		{
			Name = "FillEmptySpaceRows",
			Description = "When enabled, expands cell heights to fill available container space.",
			Category = "Appearance",
			ValueType = "boolean",
			Default = false,
		},
		
		{
			Name = "Padding",
			Description = "Empty spacing between table cells.",
			Category = "Appearance",
			ValueType = "UDim2",
			Default = UDim2.new(0, 0, 0, 0),
		},
	},

	UIDragDetector = {
		{
			Name = "Enabled",
			Description = "Determines whether the drag detector is active and responds to user input.",
			Category = "Behavior",
			ValueType = "boolean",
			Default = true,
		},
		
		{
			Name = "DragStyle",
			Description = "Defines how the UI element moves when dragged.",
			Category = "Behavior",
			ValueType = "Enum",
			EnumType = "UIDragDetectorDragStyle",
			EnumOptions = { "TranslatePlane", "TranslateLine", "Rotate", "Scriptable" },
			Default = Enum.UIDragDetectorDragStyle.TranslatePlane,
		},
		
		{
			Name = "ResponseStyle",
			Description = "Determines how the GuiObject visually responds to drag motion.",
			Category = "Behavior",
			ValueType = "Enum",
			EnumType = "UIDragDetectorResponseStyle",
			EnumOptions = { "Offset", "Scale" },
			Default = Enum.UIDragDetectorResponseStyle.Offset,
		},
		
		{
			Name = "DragRelativity",
			Description = "Determines the coordinate relativity for drag motion calculation.",
			Category = "Behavior",
			ValueType = "Enum",
			EnumType = "UIDragDetectorDragRelativity",
			EnumOptions = { "Relative", "Absolute" },
			Default = Enum.UIDragDetectorDragRelativity.Relative,
		},
	},
}

local ModifierElementRestrictions: { [string]: { Allowed: { string }?, Disallowed: { string }? } } = {
	UITextSizeConstraint = {
		Allowed = { "TextLabel", "TextButton", "TextBox" },
	},
	
	UICorner = {
		Disallowed = { "ScrollingFrame" },
	},
	
	UIGradient = {
		Disallowed = { "ScrollingFrame", "TextBox" },
	},

	UIPageLayout = {
		Disallowed = { "ScrollingFrame" },
	},
}

local ModifierExclusivityGroups: { [string]: string } = {
	UIListLayout = "UILayout",
	UIGridLayout = "UILayout",
	UIPageLayout = "UILayout",
	UITableLayout = "UILayout",
}

local ModifierConflictPairs: { [string]: { [string]: boolean } } = {
	UIFlexItem = {
		UIPageLayout = true,
		UIGridLayout = true,
		UITableLayout = true,
	},
	
	UIPageLayout = {
		UIFlexItem = true,
	},
	
	UIGridLayout = {
		UIFlexItem = true,
	},
	
	UITableLayout = {
		UIFlexItem = true,
	},
}

local MultiInstanceModifiers: { [string]: boolean } = {
	UIStroke = true,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- PropertyRegistry Public APIs Section
----------------------------------------------------------

--[[
Returns the merged list of all applicable properties for a given element class.

Params:
    ClassName: string -- The element type (e.g., "TextButton")

Returns:
    { PropertyDefinition } -- The ordered list of property definitions
]]
function PropertyRegistry.GetPropertiesForType(ClassName: string): { PropertyDefinition }
	local Properties: { PropertyDefinition } = {}
	local ActiveTraits: { string }? = ElementTraitMap[ClassName]
	
	if not ActiveTraits then
		return Properties
	end
	
	for _, TraitName: string in ipairs(ActiveTraits) do
		if Traits[TraitName] then
			for _, Property: PropertyDefinition in ipairs(Traits[TraitName]) do
				Properties[#Properties + 1] = Property
			end
		end
	end
	
	return Properties
end

--[[
Returns a dictionary of default property values for a new element.

Params:
    ClassName: string -- The element type

Returns:
    { [string]: any } -- Dictionary mapping property name to default value
]]
function PropertyRegistry.GetDefaultsForType(ClassName: string): { [string]: any }
	local Defaults: { [string]: any } = {}
	local PropertyDefinitions: { PropertyDefinition } = PropertyRegistry.GetPropertiesForType(ClassName)
	
	for _, Property: PropertyDefinition in ipairs(PropertyDefinitions) do
		-- Core structural fields (Name, Position, Size, Visible) are stored at the root of the AppState.UIElement struct,
		-- so we explicitly exclude them from the internal Properties dictionary to prevent layout clobbering in the UI pipeline.
		if Property.Name ~= "Name" and Property.Name ~= "Position" and Property.Name ~= "Size" and Property.Name ~= "Visible" then
			Defaults[Property.Name] = Property.Default
		end
	end

	if ClassName == "ScrollingFrame" or ClassName == "CanvasGroup" then
		Defaults.ClipsDescendants = true
	end
	
	return Defaults
end

--[[
Returns the property definitions for a specific modifier.

Params:
    ModifierType: string -- The class name of the modifier (e.g. "UIPadding")

Returns:
    { PropertyDefinition }? -- The list of properties, or nil if invalid
]]
function PropertyRegistry.GetModifierProperties(ModifierType: string): { PropertyDefinition }?
	return Modifiers[ModifierType]
end

--[[
Returns the default dictionary for a newly inserted modifier, including the IsModifier flag and Type.

Params:
    ModifierType: string -- The modifier type

Returns:
    { [string]: any }? -- The default state dictionary for the modifier, or nil if invalid
]]
function PropertyRegistry.GetModifierDefaults(ModifierType: string): { [string]: any }?
	local ModifierProperties: { PropertyDefinition }? = Modifiers[ModifierType]
	local Defaults: { [string]: any }
	
	if not ModifierProperties then return nil end
	
	Defaults = {}
	
	for _, Property: PropertyDefinition in ipairs(ModifierProperties) do
		Defaults[Property.Name] = Property.Default
	end
	
	if ModifierType == "UIGradient" then
		Defaults.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(50, 50, 50))
	end
	
	return {
		IsModifier = true,
		Type = ModifierType,
		Properties = Defaults,
	}
end

--[[
Retrieves the list of all valid modifier types.

Params:
    None

Returns:
    { string } -- Array of modifier class names
]]
function PropertyRegistry.GetAvailableModifiers(): { string }
	local ModifierList: { string } = {}
	
	for ModifierName: string in Modifiers do
		ModifierList[#ModifierList + 1] = ModifierName
	end
	
	table.sort(ModifierList)
	
	return ModifierList
end

--[[
Checks if a modifier is compatible with a given element class name.

Params:
    ModifierType: string -- The modifier class name (e.g., "UICorner")
    ElementType: string -- The target element class name (e.g., "ScrollingFrame")

Returns:
    boolean -- True if compatible, false otherwise
]]
function PropertyRegistry.IsModifierCompatible(ModifierType: string, ElementType: string): boolean
	local Restriction = ModifierElementRestrictions[ModifierType]
	
	if not Restriction then
		return true
	end

	if Restriction.Allowed then
		for _, AllowedType: string in ipairs(Restriction.Allowed) do
			if AllowedType == ElementType then
				return true
			end
		end
		
		return false
	end

	if Restriction.Disallowed then
		for _, DisallowedType: string in ipairs(Restriction.Disallowed) do
			if DisallowedType == ElementType then
				return false
			end
		end
		
		return true
	end

	return true
end

--[[
Checks if a modifier conflicts with any currently attached modifiers on an element.

Params:
    ModifierType: string -- The modifier being added
    ExistingProperties: { [string]: any } -- The element's current Properties dictionary

Returns:
    string? -- The name of the conflicting modifier, or nil if no conflict
]]
function PropertyRegistry.GetConflictingModifier(ModifierType: string, ExistingProperties: { [string]: any }): string?
	local TargetGroup: string? = ModifierExclusivityGroups[ModifierType]
	local PairConflicts: { [string]: boolean }? = ModifierConflictPairs[ModifierType]
	
	if not TargetGroup and not PairConflicts then
		return nil
	end

	for Key: string, Value: any in ExistingProperties do
		local RawType: string = (type(Value) == "table" and Value.Type) or Key
		local ModType: string = string.match(RawType, "^([%a%d]+)_") or RawType
		
		if type(Value) == "table" and Value.IsModifier and ModType ~= ModifierType then
			if PairConflicts and PairConflicts[ModType] then
				return ModType
			end

			if TargetGroup and ModifierExclusivityGroups[ModType] == TargetGroup then
				return ModType
			end
		end
	end

	return nil
end

--[[
Returns the list of available modifiers filtered by compatibility with the specified element type.

Params:
    ElementType: string -- The target element class name

Returns:
    { string } -- Sorted array of compatible modifier class names
]]
function PropertyRegistry.GetCompatibleModifiersForType(ElementType: string): { string }
	local CompatibleList: { string } = {}

	for _, ModName: string in ipairs(PropertyRegistry.GetAvailableModifiers()) do
		if PropertyRegistry.IsModifierCompatible(ModName, ElementType) then
			CompatibleList[#CompatibleList + 1] = ModName
		end
	end

	return CompatibleList
end

--[[
Checks whether a modifier type permits multiple instances on a single element.

Params:
    ModifierType: string -- The modifier class name

Returns:
    boolean -- True if multiple instances are allowed
]]
function PropertyRegistry.AllowsMultipleInstances(ModifierType: string): boolean
	return MultiInstanceModifiers[ModifierType] == true
end

----------------------------------------------------------
return PropertyRegistry :: PropertyRegistry
----------------------------------------------------------