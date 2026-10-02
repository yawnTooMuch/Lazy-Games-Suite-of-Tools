--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ReactLuau_Writer.luau
    
    SCOPE: UI Tree / Export Compiler / Frameworks / React_Luau
    
    ROLE: Responsible for packaging and writing React-Luau generated sources
          into ServerStorage.Lazy_GUI_Builder_Outputs.React_Luau ModuleScripts.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local Bytecode_Types = require(script.Parent.Parent.Parent.Bytecode_Types)
local Bytecode_Reader = require(script.Parent.Parent.Parent.Parent.ImportCompiler.Bytecode_Reader)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type ReactLuau_Writer = {
	Write: (ComponentName: string, PassiveSource: string, ActiveSource: string) -> (),
	GetExistingProgram: (ComponentName: string) -> Bytecode_Types.BytecodeProgram?,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Imported Services Section
----------------------------------------------------------
local ServerStorage: ServerStorage = game:GetService("ServerStorage")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local ReactLuau_Writer = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Writes both the passive component and active standalone GUI ModuleScripts into ServerStorage.

Params:
    ComponentName: string -- The base component identifier
    PassiveSource: string -- The generated passive component source code
    ActiveSource: string -- The generated active standalone GUI source code

Returns:
    () -- No return value
]]
function ReactLuau_Writer.Write(ComponentName: string, PassiveSource: string, ActiveSource: string): ()
	-- Find or create root outputs folder in ServerStorage
	local OutputsFolder: Instance? = ServerStorage:FindFirstChild("Lazy_GUI_Builder_Outputs")
	
	if not OutputsFolder then
		local NewFolder: Folder = Instance.new("Folder")
		
		NewFolder.Name = "Lazy_GUI_Builder_Outputs"
		NewFolder.Parent = ServerStorage
		OutputsFolder = NewFolder
	end

	-- Find or create React_Luau framework folder
	local FrameworkFolder: Instance? = (OutputsFolder :: Folder):FindFirstChild("React_Luau")
	
	if not FrameworkFolder then
		local NewFolder: Folder = Instance.new("Folder")
		
		NewFolder.Name = "React_Luau"
		NewFolder.Parent = OutputsFolder
		FrameworkFolder = NewFolder
	end

	-- Find or create Passive_React_Components folder
	local PassiveFolder: Instance? = (FrameworkFolder :: Folder):FindFirstChild("Passive_Components")
	
	if not PassiveFolder then
		local NewFolder: Folder = Instance.new("Folder")
		
		NewFolder.Name = "Passive_Components"
		NewFolder.Parent = FrameworkFolder
		PassiveFolder = NewFolder
	end

	-- Find or create Active_Standalone_React_GUIs folder
	local ActiveFolder: Instance? = (FrameworkFolder :: Folder):FindFirstChild("Active_Standalone_GUIs")
	
	if not ActiveFolder then
		local NewFolder: Folder = Instance.new("Folder")
		
		NewFolder.Name = "Active_Standalone_GUIs"
		NewFolder.Parent = FrameworkFolder
		ActiveFolder = NewFolder
	end

	-- Create or update passive ModuleScript
	local PassiveModuleName: string = ComponentName .. "_Component"
	local PassiveModule: Instance? = (PassiveFolder :: Folder):FindFirstChild(PassiveModuleName)

	if not PassiveModule or not PassiveModule:IsA("ModuleScript") then
		if PassiveModule then
			PassiveModule:Destroy()
		end

		local NewModule: ModuleScript = Instance.new("ModuleScript")
		
		NewModule.Name = PassiveModuleName
		NewModule.Parent = PassiveFolder
		PassiveModule = NewModule
	end

	(PassiveModule :: ModuleScript).Source = PassiveSource

	-- Create or update active ModuleScript
	local ActiveModuleName: string = ComponentName .. "_GUI"
	local ActiveModule: Instance? = (ActiveFolder :: Folder):FindFirstChild(ActiveModuleName)

	if not ActiveModule or not ActiveModule:IsA("ModuleScript") then
		if ActiveModule then
			ActiveModule:Destroy()
		end

		local NewModule: ModuleScript = Instance.new("ModuleScript")
		
		NewModule.Name = ActiveModuleName
		NewModule.Parent = ActiveFolder
		ActiveModule = NewModule
	end

	(ActiveModule :: ModuleScript).Source = ActiveSource
end

--[[
Retrieves the existing BytecodeProgram embedded within the target component's ModuleScript in ServerStorage, if present.

Params:
    ComponentName: string -- The component identifier

Returns:
    Bytecode_Types.BytecodeProgram? -- The extracted program, or nil if not found
]]
function ReactLuau_Writer.GetExistingProgram(ComponentName: string): Bytecode_Types.BytecodeProgram?
	local OutputsFolder: Instance? = ServerStorage:FindFirstChild("Lazy_GUI_Builder_Outputs")
	
	if not OutputsFolder then
		return nil
	end

	local FrameworkFolder: Instance? = (OutputsFolder :: Folder):FindFirstChild("React_Luau")
	
	if not FrameworkFolder then
		return nil
	end

	local ActiveFolder: Instance? = (FrameworkFolder :: Folder):FindFirstChild("Active_Standalone_GUIs")
	
	if ActiveFolder then
		local ActiveModuleName: string = ComponentName .. "_GUI"
		local ActiveModule: Instance? = (ActiveFolder :: Folder):FindFirstChild(ActiveModuleName)
		
		if ActiveModule and ActiveModule:IsA("ModuleScript") then
			return Bytecode_Reader.ExtractFromSource((ActiveModule :: ModuleScript).Source)
		end
	end

	local PassiveFolder: Instance? = (FrameworkFolder :: Folder):FindFirstChild("Passive_Components")
	
	if PassiveFolder then
		local PassiveModuleName: string = ComponentName .. "_Component"
		local PassiveModule: Instance? = (PassiveFolder :: Folder):FindFirstChild(PassiveModuleName)
		
		if PassiveModule and PassiveModule:IsA("ModuleScript") then
			return Bytecode_Reader.ExtractFromSource((PassiveModule :: ModuleScript).Source)
		end
	end

	return nil
end

----------------------------------------------------------
return ReactLuau_Writer :: ReactLuau_Writer
----------------------------------------------------------