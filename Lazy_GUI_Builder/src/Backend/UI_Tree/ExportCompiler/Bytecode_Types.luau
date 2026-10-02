--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Bytecode_Types.luau
    
    SCOPE: UI Tree / Export Compiler / Bytecode
    
    ROLE: Defines the universal opcode instruction set and intermediate
          representation (BytecodeProgram) used across the export/import pipeline.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type OpenNodeInstruction = {
	Op: "OPEN_NODE",
	Id: string,
	Type: string,
	Name: string,
	Key: string,
}

export type SetPropInstruction = {
	Op: "SET_PROP",
	Key: string,
	SerializedValue: string,
	RawType: string,
}

export type AttachModifierInstruction = {
	Op: "ATTACH_MODIFIER",
	Type: string,
	Key: string,
	Properties: { [string]: string },
}

export type CloseNodeInstruction = {
	Op: "CLOSE_NODE",
	Id: string,
}

export type Instruction =
	| OpenNodeInstruction
	| SetPropInstruction
	| AttachModifierInstruction
	| CloseNodeInstruction

export type BytecodeProgram = {
	Version: number,
	Build_Iteration: number,
	RootId: string,
	ComponentName: string,
	Instructions: { Instruction },
}

export type Bytecode_Types = {
	Serialize: (Program: BytecodeProgram) -> string,
	Deserialize: (Encoded: string) -> BytecodeProgram?,
	AreInstructionsEqual: (InstListA: { Instruction }, InstListB: { Instruction }) -> boolean,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Imported Services Section
----------------------------------------------------------
local HttpService: HttpService = game:GetService("HttpService")

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local Bytecode_Types = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Local Functions Section
----------------------------------------------------------

--[[
Formats an individual opcode instruction into a clean, human-readable single-line JSON string.
]]
local function formatInstruction(Inst: Instruction): string
	if Inst.Op == "OPEN_NODE" then
		return string.format('{ "Op": "OPEN_NODE", "Id": %s, "Type": %s, "Name": %s, "Key": %s }', HttpService:JSONEncode(Inst.Id), HttpService:JSONEncode(Inst.Type), HttpService:JSONEncode(Inst.Name), HttpService:JSONEncode(Inst.Key))

	elseif Inst.Op == "SET_PROP" then
		return string.format('{ "Op": "SET_PROP", "Key": %s, "SerializedValue": %s, "RawType": %s }', HttpService:JSONEncode(Inst.Key), HttpService:JSONEncode(Inst.SerializedValue), HttpService:JSONEncode(Inst.RawType))

	elseif Inst.Op == "ATTACH_MODIFIER" then
		local PropPairs: { string } = {}
		local SortedKeys: { string } = {}

		for PropKey: string in Inst.Properties do
			SortedKeys[#SortedKeys + 1] = PropKey
		end
		
		table.sort(SortedKeys)

		for _, PropKey: string in ipairs(SortedKeys) do
			PropPairs[#PropPairs + 1] = string.format("%s: %s", HttpService:JSONEncode(PropKey), HttpService:JSONEncode(Inst.Properties[PropKey]))
		end

		local PropsBlock: string
		
		if #PropPairs == 0 then
			PropsBlock = "{}"
			
		else
			PropsBlock = "{ " .. table.concat(PropPairs, ", ") .. " }"
		end

		return string.format('{ "Op": "ATTACH_MODIFIER", "Type": %s, "Key": %s, "Properties": %s }', HttpService:JSONEncode(Inst.Type), HttpService:JSONEncode(Inst.Key), PropsBlock)

	elseif Inst.Op == "CLOSE_NODE" then
		return string.format('{ "Op": "CLOSE_NODE", "Id": %s }', HttpService:JSONEncode(Inst.Id))
	end

	return HttpService:JSONEncode(Inst)
end

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Serializes a BytecodeProgram into a formatted, human-readable JSON string representation.

Params:
    Program: BytecodeProgram -- The program to serialize

Returns:
    string -- The serialized, indented JSON string
]]
function Bytecode_Types.Serialize(Program: BytecodeProgram): string
	local FormattedInstructions: { string } = {}

	for _, Inst: Instruction in ipairs(Program.Instructions) do
		FormattedInstructions[#FormattedInstructions + 1] = "        " .. formatInstruction(Inst)
	end

	local InstructionsBlock: string
	
	if #FormattedInstructions == 0 then
		InstructionsBlock = "[]"
		
	else
		InstructionsBlock = "[\n" .. table.concat(FormattedInstructions, ",\n") .. "\n    ]"
	end

	local Lines: { string } = {
		"{",
		string.format('    "Version": %s,', HttpService:JSONEncode(Program.Version)),
		string.format('    "RootId": %s,', HttpService:JSONEncode(Program.RootId)),
		string.format('    "ComponentName": %s,', HttpService:JSONEncode(Program.ComponentName)),
		string.format('    "Build_Iteration": %d,', Program.Build_Iteration or 1),
		'    "Instructions": ' .. InstructionsBlock,
		"}",
	}

	return table.concat(Lines, "\n")
end

--[[
Deserializes an encoded string back into a BytecodeProgram table.

Params:
    Encoded: string -- The JSON string to decode

Returns:
    BytecodeProgram? -- The deserialized program, or nil if malformed
]]
function Bytecode_Types.Deserialize(Encoded: string): BytecodeProgram?
	local Success: boolean, Result: any = pcall(function(): any
		return HttpService:JSONDecode(Encoded)
	end)

	if Success and type(Result) == "table" then
		Result.Build_Iteration = Result.Build_Iteration or 1
		
		return Result :: BytecodeProgram
	end

	return nil
end

--[[
Compares two instruction lists deterministically to check if any opcodes,
properties, or node structures have changed.

Params:
    InstListA: { Instruction } -- First instruction list
    InstListB: { Instruction } -- Second instruction list

Returns:
    boolean -- True if both lists are identical
]]
function Bytecode_Types.AreInstructionsEqual(InstListA: { Instruction }, InstListB: { Instruction }): boolean
	if #InstListA ~= #InstListB then
		return false
	end

	for Index: number = 1, #InstListA do
		if formatInstruction(InstListA[Index]) ~= formatInstruction(InstListB[Index]) then
			return false
		end
	end

	return true
end

----------------------------------------------------------
return Bytecode_Types :: Bytecode_Types
----------------------------------------------------------