--!strict
--[[
    ===========================================================================
    MODULE/COMPONENT: Bytecode_Reader.luau
    
    SCOPE: UI Tree / Import Compiler
    
    ROLE: Scans Luau source code for embedded @GUI_BUILDER_BYTECODE metadata blocks
          and deserializes them into validated BytecodeProgram structures.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Dependency Section
----------------------------------------------------------
local Bytecode_Types = require(script.Parent.Parent.ExportCompiler.Bytecode_Types)

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Type Structures Section
----------------------------------------------------------
export type Bytecode_Reader = {
	ExtractFromSource: (Source: string) -> Bytecode_Types.BytecodeProgram?,
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Internal States Section
----------------------------------------------------------
local Bytecode_Reader = {}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- Public APIs Section
----------------------------------------------------------

--[[
Extracts and deserializes an embedded BytecodeProgram from a script's source text.

Params:
    Source: string -- The full source text of the target ModuleScript

Returns:
    Bytecode_Types.BytecodeProgram? -- The deserialized bytecode program, or nil if not found / invalid
]]
function Bytecode_Reader.ExtractFromSource(Source: string): Bytecode_Types.BytecodeProgram?
	-- Match either --[[ @GUI_BUILDER_BYTECODE ... ]] or --[=[ @GUI_BUILDER_BYTECODE ... ]=]
	local ExtractedJSON: string? = string.match(Source, "%-%-%[=*%[%s*@GUI_BUILDER_BYTECODE%s*(.-)%s*%]=*%]")
	
	if not ExtractedJSON or string.len(ExtractedJSON) == 0 then
		return nil
	end

	return Bytecode_Types.Deserialize(ExtractedJSON)
end

----------------------------------------------------------
return Bytecode_Reader :: Bytecode_Reader
----------------------------------------------------------