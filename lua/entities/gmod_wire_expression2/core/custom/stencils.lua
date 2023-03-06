--locals
local convar_entities
local convar_layer_entities
local convar_layers
local convar_maximum_instructions
local convar_maximum_stencil_index
local convar_maximum_stencils
local hooks = STENCIL_CORE.Hooks
local hooks_count = #hooks
local stencil_repo = STENCIL_CORE.Stencils

--local tables
local stencil_globals = {
	"NEVER", --comparisons
	"LESS",
	"EQUAL",
	"LESSEQUAL",
	"GREATER",
	"NOTEQUAL",
	"GREATEREQUAL",
	"ALWAYS",
	
	"KEEP", --operations
	"ZERO",
	"REPLACE",
	"INCRSAT",
	"DECRSAT",
	"INVERT",
	"INCR",
	"DECR"
}

--local functions
local function authorized(context, entity)
	if entity:IsPlayer() then
		local ply = context.player
		
		return entity == ply or E2Lib.isFriend(entity, ply)
	end
	
	--global alias of E2Lib.isOwner
	return isOwner(context, entity)
end

local function get_hologram(context, index)
	local holograms = context.data.holos
	
	if holograms then
		local hologram = holograms[math.floor(index)]
		
		return hologram and hologram.ent
	end
end

local function valid_in_range(number, minimum, maximum) return number == number and number <= maximum and number >= minimum and math.floor(number) end
local function valid_stencil_index(number) return number == number and number <= convar_maximum_stencil_index and number >= 0 and math.floor(number) end

--post function setup
E2Lib.RegisterExtension("stencils", true, "Allows users to render entities with stencils to create fancy (and possibly headache inducing) visuals.")
__e2setcost(10)

--e2 functions
e2function void stencilAddEntity(number stencil_index, number layer_index, entity entity)
	local stencil_index = valid_stencil_index(stencil_index)
	local layer_index = valid_in_range(layer_index, 1, convar_layers)
	
	if stencil_index and layer_index then
		local stencil = stencil_repo[self.entity][stencil_index]
		
		--we only need to do isOwner for this one function out of all that exist for this core
		--you should always be able to remove entities from your stencils anyways
		if stencil and entity:IsValid() and authorized(self, entity) then STENCIL_CORE:StencilAddEntity(self, entity, stencil, layer_index) end
	end
end

e2function void stencilAddEntity(number stencil_index, number layer_index, number hologram_index)
	local stencil_index = valid_stencil_index(stencil_index)
	local layer_index = valid_in_range(layer_index, 1, convar_layers)
	
	if stencil_index and layer_index then
		local hologram = get_hologram(self, hologram_index)
		local stencil = stencil_repo[self.entity][stencil_index]
		
		if stencil and hologram then STENCIL_CORE:StencilAddEntity(self, hologram, stencil, layer_index) end
	end
end

e2function void stencilCompile(number stencil_index) error("Don't use this yet, it's not ready. Use stencilCreate instead.") end

e2function void stencilCreate(number stencil_index, number prefab_enum)
	local stencil_index = valid_stencil_index(stencil_index)
	
	if stencil_index then STENCIL_CORE:StencilEnable(STENCIL_CORE:StencilCreatePrefabricated(self, stencil_index, math.floor(prefab_enum), true), true) end
end

e2function void stencilDelete(number stencil_index) STENCIL_CORE:StencilDelete(self.entity, stencil_index) end

e2function void stencilEnable(number stencil_index, number visibility)
	local stencil_index = valid_stencil_index(stencil_index)
		
	if stencil_index then STENCIL_CORE:StencilEnable(stencil, visibility ~= 0) end
end

e2function void stencilHook(number stencil_index, number hook_enum)
	local hook_enum = valid_in_range(hook_enum, 1, hooks_count)
	local stencil_index = valid_stencil_index(stencil_index)

	if stencil_index and hook_enum then
		local stencil = stencil_repo[self.entity][stencil_index]
		
		if not stencil or stencil.Sent then return end
		
		stencil.Hook = hooks[hook_enum]
	end
end

e2function void stencilPurge() STENCIL_CORE:StencilPurge(self.entity) end

e2function void stencilRemoveEntity(number stencil_index, entity entity)
	local stencil_index = valid_stencil_index(stencil_index)
	
	if stencil_index then
		local stencil = stencil_repo[self.entity][stencil_index]
		
		if stencil and entity:IsValid() then STENCIL_CORE:StencilRemoveEntity(self, entity, stencil) end
	end
end

e2function void stencilRemoveEntity(number stencil_index, number layer_index, entity entity)
	local stencil_index = valid_stencil_index(stencil_index)
	local layer_index = valid_in_range(layer_index, 1, convar_layers)
	
	if stencil_index and layer_index then
		local stencil = stencil_repo[self.entity][stencil_index]
		
		if stencil and entity:IsValid() then STENCIL_CORE:StencilRemoveEntity(self, entity, stencil, layer_index) end
	end
end

e2function void stencilRemoveEntity(number stencil_index, number hologram_index)
	local stencil_index = valid_stencil_index(stencil_index)
	
	if stencil_index then
		local hologram = get_hologram(self, hologram_index)
		local stencil = stencil_repo[self.entity][stencil_index]
		
		if stencil and IsValid(hologram) then STENCIL_CORE:StencilRemoveEntity(self, hologram, stencil) end
	end
end

e2function void stencilRemoveEntity(number stencil_index, number layer_index, number hologram_index)
	local stencil_index = valid_stencil_index(stencil_index)
	local layer_index = valid_in_range(layer_index, 1, convar_layers)
	
	if stencil_index and layer_index then
		local hologram = get_hologram(self, hologram_index)
		local stencil = stencil_repo[self.entity][stencil_index]
		
		if stencil and IsValid(hologram) then STENCIL_CORE:StencilRemoveEntity(self, hologram, stencil, layer_index) end
	end
end

--callbacks
registerCallback("construct",
	function(self)
		local entity = self.entity
		stencil_repo[entity] = {}
	end
)

registerCallback("destruct",
	function(self)
		local chip = self.entity
		
		--could make a micro optimization here... we're not gonna talk about it though
		STENCIL_CORE:StencilPurge(chip)
		
		stencil_repo[chip] = nil
	end
)

--convars
STENCIL_CORE:ConVarListen("entities", "StencilCoreE2", function(convar) convar_entities = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("layer_entities", "StencilCoreE2", function(convar) convar_layer_entities = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("layers", "StencilCoreE2", function(convar) convar_layers = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("maximum_instructions", "StencilCoreE2", function(convar) convar_maximum_instructions = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("maximum_stencil_index", "StencilCoreE2", function(convar) convar_maximum_stencil_index = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("maximum_stencils", "StencilCoreE2", function(convar) convar_maximum_stencils = convar:GetInt() end, true)

--post
for index, hook_alias in ipairs(STENCIL_CORE.HookAliases) do E2Lib.registerConstant("_STENCILHOOK_" .. hook_alias, index) end
for index, name in ipairs(stencil_globals) do E2Lib.registerConstant("_STENCIL_" .. name, index) end
for index, prefab in ipairs(STENCIL_CORE.Prefabs) do E2Lib.registerConstant("_STENCILPREFAB_" .. string.upper(prefab[1]), index) end