--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ImportCompiler_Controller.luau
    
    SCOPE: UI Tree / Import Compiler
    
    ROLE: Local orchestrator for the import pipeline. Directs extraction of
          bytecode from ModuleScripts or transpilation of native Roblox Studio
          instances, commands Bytecode_Interpreter to reconstruct the virtual
          DOM, and fires state synchronization signals.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
local Bytecode_Types = require(script.Parent.Parent.Parent.Backend.UI_Tree.ExportCompiler.Bytecode_Types)

export type ImportCompiler_Controller = {
	Init: () -> (),
}

type ImportPayload = {
	TargetInstance: Instance,
	Mode: "Append" | "Replace" | "Replace_Selected",
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local Relay = require(script.Parent.Parent.Parent.Parent.Extras.Relay.Relay)
local ImportDialog_Logic = require(script.Parent.Parent.Parent.Backend.UI_Tree.ImportDialog_Logic)
local Bytecode_Reader = require(script.Parent.Parent.Parent.Backend.UI_Tree.ImportCompiler.Bytecode_Reader)
local Instance_Transpiler = require(script.Parent.Parent.Parent.Backend.UI_Tree.ImportCompiler.Instance_Transpiler)
local Bytecode_Interpreter = require(script.Parent.Parent.Parent.Backend.UI_Tree.ImportCompiler.Bytecode_Interpreter)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local ImportCompiler_Controller = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Function Section
----------------------------------------------------------

--[[
Handles toggling the import dialog visibility.
]]
local function onToggleImportDialog(): ()
	ImportDialog_Logic.ToggleVisibility()
	Relay.Create("SessionStateUpdated"):Fire()
end

--[[
Handles the validated import project action, orchestrating data extraction, transpilation,
loading into AppState, and firing state synchronization signals.
]]
local function onImportProject(Payload: ImportPayload): ()
	local Program: Bytecode_Types.BytecodeProgram? = nil

	if Payload.TargetInstance:IsA("ModuleScript") then
		Program = Bytecode_Reader.ExtractFromSource(Payload.TargetInstance.Source)
		
	else
		Program = Instance_Transpiler.Transpile(Payload.TargetInstance)
	end

	if not Program then
		return
	end

	local ImportedRootId: string? = Bytecode_Interpreter.Load(Program, Payload.Mode)
	
	if not ImportedRootId then
		return
	end

	-- Close dialog
	ImportDialog_Logic.SetVisible(false)

	-- Synchronize all layers
	Relay.Create("WorkspaceElementsUpdated"):Fire()
	Relay.Create("UITreeUpdated"):Fire()
	Relay.Create("ElementSelected"):Fire(ImportedRootId)
	Relay.Create("SessionStateUpdated"):Fire()
	Relay.Create("ImportCompleted"):Fire(ImportedRootId)
	Relay.Create("ShowNotification"):Fire({
		Message = string.format("Import Complete. Hierarchy Loaded In %s Mode.", Payload.Mode),
		Type = "Success",
	})
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Architectural lifecycle hook for the sub-controller.

Params:
    None

Returns:
    None
]]
function ImportCompiler_Controller.Init(): ()
	-- Architectural placeholder for root orchestrator initialization
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Event Binding Section
----------------------------------------------------------
Relay.Create("ToggleImportDialog"):Connect(onToggleImportDialog)
Relay.Create("ImportProject"):Connect(onImportProject)

----------------------------------------------------------
return ImportCompiler_Controller :: ImportCompiler_Controller
----------------------------------------------------------