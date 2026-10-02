--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: ReactLuau_Decompiler.luau
    
    SCOPE: UI Tree / Export Compiler / Frameworks / React_Luau
    
    ROLE: Ingests a BytecodeProgram intermediate representation and decompiles it
          into idiomatic, production-ready React-Luau passive and active source files.
          Embeds the bytecode header for future 100% lossless re-importing.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local ReactLuau_Decompiler = {}
local Bytecode_Types = require(script.Parent.Parent.Parent.Bytecode_Types)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type DecompileResult = {
	PassiveSource: string,
	ActiveSource: string,
}

export type ReactLuau_Decompiler = {
	Decompile: (Program: Bytecode_Types.BytecodeProgram) -> DecompileResult,
}

type ASTModifier = {
	Key: string,
	Type: string,
	Properties: { [string]: string },
}

type ASTNode = {
	Id: string,
	Type: string,
	Name: string,
	Key: string,
	Props: { { Key: string, Value: string } },
	Modifiers: { ASTModifier },
	Children: { ASTNode },
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Functions Section
----------------------------------------------------------

--[[
Formats a Luau table key as a bare identifier or bracketed string literal.
]]
local function formatTableKey(Key: string): string
	if string.match(Key, "^[%a_][%w_]*$") then
		return Key
		
	else
		local Escaped: string = Key:gsub("\\", "\\\\"):gsub('"', '\\"')
		
		return string.format('["%s"]', Escaped)
	end
end

--[[
Reconstructs an AST node tree from a linear BytecodeProgram opcode stream.
]]
local function buildASTFromBytecode(Program: Bytecode_Types.BytecodeProgram): ASTNode?
	local Stack: { ASTNode } = {}
	local RootNode: ASTNode? = nil

	for _, Inst: Bytecode_Types.Instruction in ipairs(Program.Instructions) do
		if Inst.Op == "OPEN_NODE" then
			local Node: ASTNode = {
				Id = Inst.Id,
				Type = Inst.Type,
				Name = Inst.Name,
				Key = Inst.Key,
				Props = {},
				Modifiers = {},
				Children = {},
			}

			Stack[#Stack + 1] = Node

		elseif Inst.Op == "SET_PROP" then
			local CurrentNode: ASTNode? = Stack[#Stack]
			
			if CurrentNode then
				CurrentNode.Props[#CurrentNode.Props + 1] = {
					Key = Inst.Key,
					Value = Inst.SerializedValue,
				}
			end

		elseif Inst.Op == "ATTACH_MODIFIER" then
			local CurrentNode: ASTNode? = Stack[#Stack]
			
			if CurrentNode then
				CurrentNode.Modifiers[#CurrentNode.Modifiers + 1] = {
					Key = Inst.Key,
					Type = Inst.Type,
					Properties = Inst.Properties,
				}
			end

		elseif Inst.Op == "CLOSE_NODE" then
			local ClosedNode: ASTNode? = Stack[#Stack]
			
			Stack[#Stack] = nil

			if #Stack > 0 then
				local ParentNode: ASTNode = Stack[#Stack]
				
				if ClosedNode then
					ParentNode.Children[#ParentNode.Children + 1] = ClosedNode
				end
				
			else
				RootNode = ClosedNode
			end
		end
	end

	return RootNode
end

--[[
Recursively renders an ASTNode into React.createElement(...) Luau source code.
]]
local function renderNodeTreeCode(Node: ASTNode, IndentLevel: number): string
	local Indent: string = string.rep("    ", IndentLevel)
	local InnerIndent: string = string.rep("    ", IndentLevel + 1)
	local PropLines: { string } = {}

	for _, Prop in ipairs(Node.Props) do
		PropLines[#PropLines + 1] = InnerIndent .. formatTableKey(Prop.Key) .. " = " .. Prop.Value .. ","
	end

	local ChildEntries: { { Key: string, Code: string } } = {}

	-- Modifiers first
	for _, Mod: ASTModifier in ipairs(Node.Modifiers) do
		local ModPropLines: { string } = {}
		local SortedModPropKeys: { string } = {}

		for PKey: string in Mod.Properties do
			SortedModPropKeys[#SortedModPropKeys + 1] = PKey
		end
		
		table.sort(SortedModPropKeys)

		local ModInnerIndent: string = string.rep("    ", IndentLevel + 2)
		
		for _, PKey: string in ipairs(SortedModPropKeys) do
			ModPropLines[#ModPropLines + 1] = ModInnerIndent .. formatTableKey(PKey) .. " = " .. Mod.Properties[PKey] .. ","
		end

		local ModCode: string
		
		if #ModPropLines == 0 then
			ModCode = string.format('React.createElement("%s")', Mod.Type)
			
		else
			ModCode = string.format('React.createElement("%s", {\n%s\n%s})', Mod.Type, table.concat(ModPropLines, "\n"), InnerIndent)
		end

		ChildEntries[#ChildEntries + 1] = {
			Key = Mod.Key,
			Code = ModCode,
		}
	end

	-- Child nodes second
	for _, ChildNode: ASTNode in ipairs(Node.Children) do
		local ChildCode: string = renderNodeTreeCode(ChildNode, IndentLevel + 1)
		
		ChildEntries[#ChildEntries + 1] = {
			Key = ChildNode.Key,
			Code = ChildCode,
		}
	end

	-- Construct React.createElement call
	local HasProps: boolean = #PropLines > 0
	local HasChildren: boolean = #ChildEntries > 0

	if not HasProps and not HasChildren then
		return string.format('React.createElement("%s")', Node.Type)
	end

	local PropsArg: string
	
	if HasProps then
		PropsArg = string.format("{\n%s\n%s}", table.concat(PropLines, "\n"), Indent)
		
	else
		PropsArg = "nil"
	end

	if not HasChildren then
		return string.format('React.createElement("%s", %s)', Node.Type, PropsArg)
	end

	-- Format children table with empty lines between siblings
	local ChildrenCodeLines: { string } = {}
	
	for _, Child in ipairs(ChildEntries) do
		local ChildKeyFormatted: string = formatTableKey(Child.Key)
		local TrimmedCode: string = Child.Code:gsub("^%s+", "")
		
		ChildrenCodeLines[#ChildrenCodeLines + 1] = InnerIndent .. ChildKeyFormatted .. " = " .. TrimmedCode .. ","
	end

	local ChildrenBlock: string = table.concat(ChildrenCodeLines, "\n\n")

	return string.format('React.createElement("%s", %s, {\n%s\n%s})', Node.Type, PropsArg, ChildrenBlock, Indent)
end

--[[
Generates the passive React component source code.
]]
local function generatePassiveSource(Program: Bytecode_Types.BytecodeProgram, RootNode: ASTNode): string
	local ComponentName: string = Program.ComponentName
	local TreeCode: string = renderNodeTreeCode(RootNode, 1)
	local SerializedBytecode: string = Bytecode_Types.Serialize(Program)

	local Lines: { string } = {
		"--!strict",
		"--[[",
		"    ===========================================================================",
		"    Generated by GUI Builder",
		string.format("    Component: %s_Component", ComponentName),
		string.format("    Build Iteration: %d", Program.Build_Iteration or 1),
		"    ===========================================================================",
		"]]",
		"",
		"local React = require(--[[ PATH_TO_REACT ]])",
		"",
		"-------------------------------------------------------------------------------------------------------------",
		"--#########################################################################################################--",
		"-------------------------------------------------------------------------------------------------------------",
		"----------------------------------------------------------",
		"-- Type Structures Section",
		"----------------------------------------------------------",
		string.format("export type %sProps = {", ComponentName),
		"    Visible: boolean?,",
		"}",
		"",
		"-------------------------------------------------------------------------------------------------------------",
		"--#########################################################################################################--",
		"-------------------------------------------------------------------------------------------------------------",
		"----------------------------------------------------------",
		"-- Internal Component Section",
		"----------------------------------------------------------",
		"--[[",
		string.format("\tComponent: %s_Component", ComponentName),
		"",
		"\tParams:",
		string.format("\t    Props: %sProps -- Component properties", ComponentName),
		"",
		"\tReturns:",
		"\t    any -- Rendered React element",
		"]]",
		string.format("local function %s_Component(Props: %sProps?): any", ComponentName, ComponentName),
		string.format("    return %s", TreeCode),
		"end",
		"",
		"----------------------------------------------------------",
		string.format("return %s_Component", ComponentName),
		"----------------------------------------------------------",
		"",
		"--[[ @GUI_BUILDER_BYTECODE",
		SerializedBytecode,
		"]]",
		"",
	}

	return table.concat(Lines, "\n")
end

--[[
Generates the active standalone runnable GUI source code.
]]
local function generateActiveSource(Program: Bytecode_Types.BytecodeProgram, RootNode: ASTNode): string
	local ComponentName: string = Program.ComponentName
	local TreeCode: string = renderNodeTreeCode(RootNode, 1)
	local SerializedBytecode: string = Bytecode_Types.Serialize(Program)

	local Lines: { string } = {
		"--!strict",
		"--[[",
		"    ===========================================================================",
		"    Generated by GUI Builder",
		string.format("    Component: %s_GUI", ComponentName),
		string.format("    Build Iteration: %d", Program.Build_Iteration or 1),
		"    ===========================================================================",
		"]]",
		"",
		"local React = require(--[[ PATH_TO_REACT ]])",
		"local ReactRoblox = require(--[[ PATH_TO_REACT_ROBLOX ]])",
		'local Players: Players = game:GetService("Players")',
		"",
		"-------------------------------------------------------------------------------------------------------------",
		"--#########################################################################################################--",
		"-------------------------------------------------------------------------------------------------------------",
		"----------------------------------------------------------",
		"-- Type Structures Section",
		"----------------------------------------------------------",
		string.format("export type %s_GUI = {", ComponentName),
		"    Mount: () -> (),",
		"    Unmount: () -> (),",
		"    Visible: (IsVisible: boolean) -> (),",
		"}",
		"",
		"-------------------------------------------------------------------------------------------------------------",
		"--#########################################################################################################--",
		"-------------------------------------------------------------------------------------------------------------",
		"----------------------------------------------------------",
		"-- Internal Component Section",
		"----------------------------------------------------------",
		string.format("local function %s_Component(): any", ComponentName),
		string.format("    return %s", TreeCode),
		"end",
		"",
		"-------------------------------------------------------------------------------------------------------------",
		"--#########################################################################################################--",
		"-------------------------------------------------------------------------------------------------------------",
		"----------------------------------------------------------",
		"-- Internal States Section",
		"----------------------------------------------------------",
		string.format("local %s_GUI = {}", ComponentName),
		"local Root: any = nil",
		"local Host: ScreenGui? = nil",
		"",
		"-------------------------------------------------------------------------------------------------------------",
		"--#########################################################################################################--",
		"-------------------------------------------------------------------------------------------------------------",
		"----------------------------------------------------------",
		"-- Public APIs Section",
		"----------------------------------------------------------",
		"--[[",
		"\tMounts and renders the GUI onto the local player's screen.",
		"",
		"\tReturns:",
		"\t    () -- No return value",
		"]]",
		string.format("function %s_GUI.Mount(): ()", ComponentName),
		"    if Root then return end",
		"",
		'    local PlayerGui: PlayerGui = (Players.LocalPlayer :: Player):WaitForChild("PlayerGui") :: PlayerGui',
		"",
		'	Host = Instance.new("ScreenGui")',
		"	",
		"	if Host  then",
		string.format('		Host.Name = "%s"', ComponentName),
		"		Host.ZIndexBehavior = Enum.ZIndexBehavior.Sibling",
		"		Host.ResetOnSpawn = false",
		"		Host.IgnoreGuiInset = true",
		"		Host.Parent = PlayerGui",
		"	end",
		"",
		"    Root = ReactRoblox.createRoot(Host :: ScreenGui)",
		string.format("    Root:render(React.createElement(%s_Component))", ComponentName),
		"end",
		"",
		"--[[",
		"\tUnmounts and destroys the GUI from the local player's screen.",
		"",
		"\tReturns:",
		"\t    () -- No return value",
		"]]",
		string.format("function %s_GUI.Unmount(): ()", ComponentName),
		"    if Root then",
		"        Root:unmount()",
		"        Root = nil",
		"    end",
		"",
		"    if Host then",
		"        Host:Destroy()",
		"        Host = nil",
		"    end",
		"end",
		"",
		"--[[",
		"\tToggles the visibility of the GUI without unmounting.",
		"",
		"\tParams:",
		"\t    IsVisible: boolean -- Whether the GUI should be visible",
		"",
		"\tReturns:",
		"\t    () -- No return value",
		"]]",
		string.format("function %s_GUI.Visible(IsVisible: boolean): ()", ComponentName),
		"    if Host then",
		"        Host.Enabled = IsVisible",
		"    end",
		"end",
		"",
		"----------------------------------------------------------",
		string.format("return %s_GUI :: %s_GUI", ComponentName, ComponentName),
		"----------------------------------------------------------",
		"",
		"--[[ @GUI_BUILDER_BYTECODE",
		SerializedBytecode,
		"]]",
		"",
	}

	return table.concat(Lines, "\n")
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Decompiles a BytecodeProgram into React-Luau passive and active source code strings.

Params:
    Program: Bytecode_Types.BytecodeProgram -- The bytecode intermediate representation

Returns:
    DecompileResult -- Table containing PassiveSource and ActiveSource
]]
function ReactLuau_Decompiler.Decompile(Program: Bytecode_Types.BytecodeProgram): DecompileResult
	local RootNode: ASTNode? = buildASTFromBytecode(Program)
	
	if not RootNode then
		error("ReactLuau_Decompiler: Failed to reconstruct AST from BytecodeProgram")
	end

	return {
		PassiveSource = generatePassiveSource(Program, RootNode),
		ActiveSource = generateActiveSource(Program, RootNode),
	}
end

----------------------------------------------------------
return ReactLuau_Decompiler :: ReactLuau_Decompiler
----------------------------------------------------------