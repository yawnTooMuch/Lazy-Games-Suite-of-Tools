--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ExportCompiler_Controller.luau
    
    SCOPE: UI Tree / Export Compiler
    
    ROLE: Local orchestrator for the export pipeline. Commands the Bytecode_Emitter
          to compile the visual tree into an intermediate opcode program, routes
          the bytecode to the target framework decompiler, passes generated code
          to the writer, and commands state and notification updates.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local Assignment = require(script.Parent.Parent.Parent.Parent.Extras.Assignment.Assignment)
local ExportDialog_Logic = require(script.Parent.Parent.Parent.Backend.UI_Tree.ExportDialog_Logic)
local Bytecode_Emitter = require(script.Parent.Parent.Parent.Backend.UI_Tree.ExportCompiler.Bytecode_Emitter)
local ReactLuau_Decompiler = require(script.Parent.Parent.Parent.Backend.UI_Tree.ExportCompiler.Frameworks.React_Luau.ReactLuau_Decompiler)
local ReactLuau_Writer = require(script.Parent.Parent.Parent.Backend.UI_Tree.ExportCompiler.Frameworks.React_Luau.ReactLuau_Writer)
local Bytecode_Types = require(script.Parent.Parent.Parent.Backend.UI_Tree.ExportCompiler.Bytecode_Types)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type ExportCompiler_Controller = {
	Init: () -> (),
}

type ExportPayload = {
	ComponentName: string,
	RootId: string,
	Framework: string,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local ExportCompiler_Controller = {}
local FrameworkRouterSwitch = Assignment.Switch("ExportCompiler_FrameworkRouter")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Function Section
----------------------------------------------------------

--[[
Handles toggling the export dialog visibility.
]]
local function onToggleExportDialog(): ()
	ExportDialog_Logic.ToggleVisibility()
	Relay.Create("SessionStateUpdated"):Fire()
end

--[[
Executes the React-Luau decompile and write pipeline for the compiled bytecode program.
]]
local function executeReactLuauPipeline(Program: any): ()
	local BytecodeProgram: Bytecode_Types.BytecodeProgram = Program
	local Sources = ReactLuau_Decompiler.Decompile(BytecodeProgram)
	
	ReactLuau_Writer.Write(BytecodeProgram.ComponentName, Sources.PassiveSource, Sources.ActiveSource)
end

--[[
Handles the validated export project action, orchestrating data flow between compiler,
framework decompiler, writer, and session state.
]]
local function onExportProject(Payload: ExportPayload): ()
	-- Retrieve existing bytecode program from previous exports (if present)
	local ExistingProgram: Bytecode_Types.BytecodeProgram? = nil
	
	if Payload.Framework == "React_Luau" then
		ExistingProgram = ReactLuau_Writer.GetExistingProgram(Payload.ComponentName)
	end

	-- Invocate Bytecode_Emitter to compile node tree into intermediate representation
	local Program: Bytecode_Types.BytecodeProgram = Bytecode_Emitter.Compile(Payload.ComponentName, Payload.RootId)

	-- Check for instruction changes and assign Build_Iteration
	local HasChanges: boolean = true

	if ExistingProgram then
		local IsEqual: boolean = Bytecode_Types.AreInstructionsEqual(Program.Instructions, ExistingProgram.Instructions)

		if IsEqual then
			Program.Build_Iteration = ExistingProgram.Build_Iteration or 1
			HasChanges = false
			
		else
			Program.Build_Iteration = (ExistingProgram.Build_Iteration or 1) + 1
			HasChanges = true
		end
		
	else
		Program.Build_Iteration = 1
		HasChanges = true
	end

	-- Route bytecode through framework router
	local PipelineFunc = FrameworkRouterSwitch:Match(Payload.Framework) :: ((Bytecode_Types.BytecodeProgram) -> ())?
	
	if PipelineFunc then
		PipelineFunc(Program)
	end

	-- Close the export dialog in AppState
	ExportDialog_Logic.SetVisible(false)

	-- Notify UI layer
	local NotificationMessage: string
	
	if HasChanges then
		NotificationMessage = string.format("Export Complete. Build Iteration %d. 2 Files Written to ServerStorage.Lazy_GUI_Builder_Outputs.%s.", Program.Build_Iteration, Payload.Framework)
		
	else
		NotificationMessage = string.format("Export Complete (No Changes). Build Iteration %d. Files Up To Date in ServerStorage.Lazy_GUI_Builder_Outputs.%s.", Program.Build_Iteration, Payload.Framework)
	end

	Relay.Create("ShowNotification"):Fire({
		Message = NotificationMessage,
		Type = "Success",
	})

	Relay.Create("ExportCompleted"):Fire()
	Relay.Create("SessionStateUpdated"):Fire()
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Architectural placeholder for controller initialization.

Params:
    None

Returns:
    None
]]
function ExportCompiler_Controller.Init(): ()
	--[[
		Placeholder Function:
		
		Because we use the static Event Binding pattern (Rule #13), all signal connections 
		are established natively at the bottom of the script the moment the module is 
		required. However, UITree_Controller or AppController uniformly invokes `.Init()` 
		during plugin startup. This function exists to satisfy that strict architectural 
		contract and provides a future-proof location for any deferred setup.
	]]
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Event Binding Section
----------------------------------------------------------
FrameworkRouterSwitch
	:Case("React_Luau"):Execute(executeReactLuauPipeline)

Relay.Create("ToggleExportDialog"):Connect(onToggleExportDialog)
Relay.Create("ExportProject"):Connect(onExportProject)

----------------------------------------------------------
return ExportCompiler_Controller :: ExportCompiler_Controller
----------------------------------------------------------