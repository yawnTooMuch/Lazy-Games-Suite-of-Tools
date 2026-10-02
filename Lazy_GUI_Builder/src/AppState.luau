--!strict
-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- AppState Type Structures Section
----------------------------------------------------------
export type NodeProperties = {
    [string]: any,
}

export type GUINode = {
    Id: string,
    ClassName: string,
    Name: string,
    Properties: NodeProperties,
    Children: { GUINode },
}

export type ProjectMetadata = {
    ProjectName: string,
    CanvasSize: Vector2,
    GridSnap: boolean,
    GridSize: number,
}

export type BuilderSchema = {
    Metadata: ProjectMetadata,
    Tree: { GUINode },
}

export type HistoryRecord = {
	WorkspaceElements: { [string]: UIElement },
	SelectedElementId: string?,
	PreviousRedoStack: { HistoryRecord }?,
}

export type PositionEditorSettings = {
	TrackpadSensitivity: number,
	XDialSensitivity: number,
	YDialSensitivity: number,
}

export type SizeEditorSettings = {
	TrackpadSensitivity: number,
	WidthDialSensitivity: number,
	HeightDialSensitivity: number,
}

export type RotationEditorSettings = {
	DialSensitivity: number,
}

export type SizeDialTracker = {
	OriginalSize: UDim2?,
	ElementId: string?,
}

export type PositionDialTracker = {
	OriginalPosition: UDim2?,
	ElementId: string?,
}

export type RotationDialTracker = {
	OriginalRotation: number?,
	ElementId: string?,
}

export type SessionState = {
    IsProviderVisible: boolean,
    IsRenderEngineVisible: boolean,
    IsUITreeVisible: boolean,
    IsPropertiesEditorVisible: boolean,
    IsExportDialogVisible: boolean,
    IsImportDialogVisible: boolean,
    ProviderPosition: UDim2,
    UITreePosition: UDim2,
    IsPositionSettingsVisible: boolean,
    PositionEditorSettings: PositionEditorSettings,
	IsSizeSettingsVisible: boolean,
	SizeEditorSettings: SizeEditorSettings,
	SizeDialTracker: SizeDialTracker,
	PositionDialTracker: PositionDialTracker,
	IsAnchorPointVisualVisible: boolean,
	IsRotationSettingsVisible: boolean,
	RotationEditorSettings: RotationEditorSettings,
	RotationDialTracker: RotationDialTracker,
}

export type DragState = {
    IsDragging: boolean,
    ElementType: string?,
}

export type UIElement = {
	Id: string,
	Type: string,
	Name: string,
	ParentId: string?,
	Children: { string },
	Properties: { [string]: any },
	Position: UDim2,
	Size: UDim2,
	Visible: boolean,
}

export type UITreeDragState = {
	IsDragging: boolean,
	DraggedNodeId: string?,
	HoveredTargetId: string?,
	IsHoveringTrash: boolean,
	IsHoveringDuplicate: boolean,
}

export type AppState = {
    TargetScreenGui: ScreenGui?,
    SessionState: SessionState,
    DragState: DragState,
	UITreeDragState: UITreeDragState,
	
    WorkspaceElements: {
        [string]: UIElement,
	},
	
    SelectedElementId: string?,
    SelectedNodes: { string },
    HoveredNode: string?,
    LiveProjectData: BuilderSchema,
    UndoStack: { HistoryRecord },
    RedoStack: { HistoryRecord },
    Clipboard: { GUINode },
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- AppState Internal States Section
----------------------------------------------------------
local AppState: AppState = {
    TargetScreenGui = nil,
    SessionState = {
        IsProviderVisible = false,
        IsRenderEngineVisible = true,
        IsUITreeVisible = false,
        IsPropertiesEditorVisible = false,
        IsExportDialogVisible = false,
        IsImportDialogVisible = false,
        ProviderPosition = UDim2.new(0.5, -65, 0.5, 0),
	    UITreePosition = UDim2.fromScale(0.5, 0.5),
		IsPositionSettingsVisible = false,
		
	    PositionEditorSettings = {
	        TrackpadSensitivity = 1,
	        XDialSensitivity = 1,
	        YDialSensitivity = 1,
		},
		
		IsSizeSettingsVisible = false,
		
		SizeEditorSettings = {
			TrackpadSensitivity = 1,
			WidthDialSensitivity = 1,
			HeightDialSensitivity = 1,
		},
		
		SizeDialTracker = {
			OriginalSize = nil,
			ElementId = nil,
		},
		
		PositionDialTracker = {
			OriginalPosition = nil,
			ElementId = nil,
		},
		
		IsAnchorPointVisualVisible = false,
		IsRotationSettingsVisible = false,
		
		RotationEditorSettings = {
			DialSensitivity = 1,
		},
		
		RotationDialTracker = {
			OriginalRotation = nil,
			ElementId = nil,
		},
	},
	
    DragState = {
        IsDragging = false,
        ElementType = nil,
	},
	
    UITreeDragState = {
        IsDragging = false,
        DraggedNodeId = nil,
        HoveredTargetId = nil,
        IsHoveringTrash = false,
        IsHoveringDuplicate = false,
	},
	
    WorkspaceElements = {},
    SelectedElementId = nil,
    SelectedNodes = {},
	HoveredNode = nil,
	
    LiveProjectData = {
        Metadata = {
            ProjectName = "New_GUI",
            CanvasSize = Vector2.new(1920, 1080),
            GridSnap = false,
            GridSize = 10,
		},
		
		Tree = {},
	},
	
    UndoStack = {},
    RedoStack = {},
    Clipboard = {},
}

----------------------------------------------------------
return AppState :: AppState
----------------------------------------------------------