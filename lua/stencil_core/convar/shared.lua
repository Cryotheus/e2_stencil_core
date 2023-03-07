--local functions
local function create_convar(name, ...)
	local convar = CreateConVar("wire_expression2_stencils_" .. name, ...)
	STENCIL_CORE.ConVars[name] = convar
	STENCIL_CORE.ConVarListeners[name] = STENCIL_CORE.ConVarListeners[name] or {}
	
	return convar
end

--post --TODO: implement entity limits!
create_convar("entities", "1024", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The maximum amount of entities a client may add to a stencil.", 2, STENCIL_CORE.MaximumEntityCount)
create_convar("layer_entities", "256", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The maximum amount of entities a client may put into a single stencil.", 1, STENCIL_CORE.MaximumEntityCount)
create_convar("layers", "8", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The maximum amount of entity layers a client may create for their stencils.", 2, 65536)
create_convar("maximum_instructions", "16", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The maximum amount of instructions a client may use to make a stencil. Prefabs will always ignore this value.", 1, 65536)
create_convar("maximum_stencil_index", "65535", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The highest index a stencil may be assigned to.", 0, 65535)
create_convar("maximum_stencils", "256", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The maximum amount of stencils a client may create.", 1, 256)