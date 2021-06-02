--I am a faithful believer of DRY (Don't Repeat Yourself!)
--that's why we create a prefix system
local function_descriptions = {
	["stencilAddEntity"] =	0,
	["stencilCreate"] =	0,
	["stencilRemove"] =	0,
	["stencilRemoveEntity"] =	0,
}

--1: YES.

local prefixes = {[0] = ""}
local translate = include("wire_stencil_core/includes/translate.lua")
local wip_tag = translate("wire_stencil_core.e2helper.wip.tag")

--cache them so we don't have to translate them for every entry
for index = 1, 1 do prefixes[index] = translate("wire_stencil_core.e2helper." .. index) end

--negative if they are wip
--bool if they have a special WIP message
for name, data in pairs(function_descriptions) do
	local method
	local parsed = string.Replace(name, ":", ".")
	local wip
	local wip_prefix
	
	if istable(data) then
		method = math.abs(data[1])
		wip = data[1] < 0
		wip_prefix = data[2]
	else
		method = math.abs(data)
		wip = data < 0
	end
	
	E2Helper.Descriptions[name] = translate(wip and "wire_stencil_core.e2helper.wip" or "wire_stencil_core.e2helper", {
		description = translate("wire_stencil_core.e2." .. parsed),
		prefix = prefixes[method],
		wip = wip_prefix and translate("wire_stencil_core.e2helper.wip.prefixed", {
			text = translate("wire_stencil_core.e2_wip." .. parsed),
			wip = wip_tag
		}) or wip and wip_tag or nil
	})
end

--clean up! probably don't need to do this, lua's gc is smart
function_descriptions = nil