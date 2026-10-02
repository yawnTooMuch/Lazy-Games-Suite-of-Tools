--!strict

--[[
    ===========================================================================
    MODULE/COMPONENT: DropdownOverlapping_Correctness.luau
    SCOPE: UI Component SDK
    ROLE: Imperative DOM manipulator to fix Roblox ZIndex clipping issues for Dropdowns.
    ===========================================================================
]]

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- DropdownOverlapping_Correctness Type Structures Section
----------------------------------------------------------
export type DropdownOverlapping_Correctness = {
	Correct: (RootInstance: Instance) -> (),
	Revert: (RootInstance: Instance) -> (),
}

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- DropdownOverlapping_Correctness Internal States Section
----------------------------------------------------------
local DropdownOverlapping_Correctness = {}
local CachedZIndex = setmetatable({}, { 
	__mode = "k" 
}) :: { [Instance]: number }

-------------------------------------------------------------------------------------------------------------
--#########################################################################################################--
-------------------------------------------------------------------------------------------------------------
----------------------------------------------------------
-- DropdownOverlapping_Correctness Public APIs Section
----------------------------------------------------------

--[[
Walks up the DOM tree from the RootInstance and sets the ZIndex of all 
GuiObject ancestors to a highly elevated value to prevent clipping.
Caches the original values to restore later.

Params:
    RootInstance: Instance -- The base GuiObject of the Dropdown

Returns:
    None
]]
function DropdownOverlapping_Correctness.Correct(RootInstance: Instance): ()
	local Current: Instance? = RootInstance
	
	while Current do
		if Current:IsA("GuiObject") then
			-- Cache original ZIndex only if not already cached
			if CachedZIndex[Current] == nil then
				CachedZIndex[Current] = Current.ZIndex
			end
			
			Current.ZIndex = 1000
		end
		
		Current = Current.Parent
		
		if Current and (Current:IsA("LayerCollector") or Current:IsA("ScreenGui") or Current:IsA("PluginGui")) then
			break
		end
	end
end

--[[
Restores the cached ZIndex of all ancestors of RootInstance.

Params:
    RootInstance: Instance -- The base GuiObject of the Dropdown

Returns:
    None
]]
function DropdownOverlapping_Correctness.Revert(RootInstance: Instance): ()
	local Current: Instance? = RootInstance
	
	while Current do
		if Current:IsA("GuiObject") then
			local OriginalZIndex: number? = CachedZIndex[Current]
			
			if OriginalZIndex ~= nil then
				Current.ZIndex = OriginalZIndex
				CachedZIndex[Current] = nil
			end
		end
		
		Current = Current.Parent
		
		if Current and (Current:IsA("LayerCollector") or Current:IsA("ScreenGui") or Current:IsA("PluginGui")) then
			break
		end
	end
end

return DropdownOverlapping_Correctness :: DropdownOverlapping_Correctness
