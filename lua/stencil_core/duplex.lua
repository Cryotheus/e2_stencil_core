--https://github.com/Cryotheus/pyrition_2/blob/1f21810108408f951151b919a8891392f80b61aa/lua/pyrition/duplex.lua
--locals
local duplex_set

--local functions
local function duplex_inherit_entry(target, source, index)
	if isnumber(index) then return duplex_set(target, index, source[index]) end
	
	return duplex_set(target, source[index], index)
end

local function duplex_destroy(duplex) --turn a duplex into a list
	for index, value in ipairs(duplex) do duplex[value] = nil end
	
	return duplex
end

local function duplex_extract(duplex) --get a list from a duplex
	local copy = {}
	
	for index, value in ipairs(duplex) do copy[index] = value end
	
	return copy
end

local function duplex_insert(duplex, value, set_value)
	if isnumber(value) then return duplex_set(duplex, value, set_value) end
	
	if duplex[value] == nil then
		local index = table.insert(duplex, value)
		duplex[value] = index
		
		return index
	end
	
	return false
end

local function duplex_is_fooplex(duplex) --check duplex for "holes"
	local count = table.Count(duplex)
	
	--quick check by comparing counts
	if count ~= #duplex * 2 then return true end
	
	--slower check by
	for index = 1, count * 0.5 do if duplex[index] == nil then return true end end
	
	return false
end

local function duplex_make(duplex, modify)
	local duplex = modify and duplex or table.Copy(duplex)
	
	for index, value in ipairs(duplex) do duplex[value] = index end
	
	return duplex
end

local function duplex_make_fooplex(duplex, modify)
	local duplex = modify and duplex or table.Copy(duplex)
	
	for index, value in pairs(duplex) do if isnumber(index) then duplex[value] = index end end
	
	return duplex
end

local function duplex_remove(duplex, index)
	local value
	
	if index then
		if isnumber(index) then value = duplex[index]
		else value, index = index, duplex[index] end
	else index = #duplex end
	
	if index and value then
		table.remove(duplex, index)
		
		duplex[value] = nil
		
		--update the following values
		for march = index, #duplex do
			local indexed_value = duplex[march]
			
			duplex[indexed_value] = march
		end
		
		return value
	end
	
	return nil
end

function duplex_set(duplex, position, value)
	assert(isnumber(position), "ID10T-8: Attempt to set a non-numerical " .. type(position) .. " index in duplex.")
	assert(value ~= nil, "ID10T-9: Attempt to set a nil value in duplex. Use STENCIL_CORE._DuplexUnset instead.")
	
	local old_index = duplex[value]
	
	if old_index then
		duplex[old_index] = nil
		duplex[value] = nil
	end
	
	if duplex[position] then duplex[position] = nil end
	
	duplex[value] = position
	duplex[position] = value
	
	return position
end

local function duplex_sort(duplex, sorter)
	local list = duplex_extract(duplex)
	
	table.sort(list, sorter)
	
	for index, value in ipairs(list) do
		duplex[index] = value
		duplex[value] = index
	end
	
	return duplex, list
end

local function duplex_unset(duplex, index)
	local value = duplex[index]
	duplex[index] = nil
	
	if value then duplex[value] = nil end
	
	return isnumber(index) and index or value 
end

--globals
STENCIL_CORE._DuplexDestroy = duplex_destroy
STENCIL_CORE._DuplexExtract = duplex_extract
STENCIL_CORE._DuplexInheritEntry = duplex_inherit_entry
STENCIL_CORE._DuplexInsert = duplex_insert
STENCIL_CORE._DuplexIsFooplex = duplex_is_fooplex
STENCIL_CORE._DuplexMake = duplex_make
STENCIL_CORE._DuplexMakeFooplex = duplex_make_fooplex
STENCIL_CORE._DuplexRemove = duplex_remove
STENCIL_CORE._DuplexSet = duplex_set
STENCIL_CORE._DuplexSort = duplex_sort
STENCIL_CORE._DuplexUnset = duplex_unset

--[[ copy paste this in your locals header

local duplex_destroy = STENCIL_CORE._DuplexDestroy
local duplex_extract = STENCIL_CORE._DuplexExtract
local duplex_inherit_entry = STENCIL_CORE._DuplexInheritEntry
local duplex_insert = STENCIL_CORE._DuplexInsert
local duplex_is_fooplex = STENCIL_CORE._DuplexIsFooplex
local duplex_make = STENCIL_CORE._DuplexMake
local duplex_make_fooplex = STENCIL_CORE._DuplexMakeFooplex
local duplex_remove = STENCIL_CORE._DuplexRemove
local duplex_set = STENCIL_CORE._DuplexSet
local duplex_sort = STENCIL_CORE._DuplexSort
local duplex_unset = STENCIL_CORE._DuplexUnset

]]