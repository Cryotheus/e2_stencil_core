--locals
local hook_aliases = {}
local hook_functions = {}
local parameterized_operations = {}

--enumerations missing on server side
STENCIL_NEVER = 1
STENCIL_LESS = 2
STENCIL_EQUAL = 3
STENCIL_LESSEQUAL = 4
STENCIL_GREATER = 5
STENCIL_NOTEQUAL = 6
STENCIL_GREATEREQUAL = 7
STENCIL_ALWAYS = 8

STENCIL_KEEP = 1
STENCIL_ZERO = 2
STENCIL_REPLACE = 3
STENCIL_INCRSAT = 4
STENCIL_DECRSAT = 5
STENCIL_INVERT = 6
STENCIL_INCR = 7
STENCIL_DECR = 8

--local tables
local hooks = {
	"PreDrawOpaqueRenderables",
	"PostDrawOpaqueRenderables",
	"PreDrawTranslucentRenderables",
	"PostDrawTranslucentRenderables",
}

local operations = {
	{"clear_stencil", "render.ClearStencil()"},
	{"clear", "render.ClearBuffersObeyStencil($.r, $.g, $.b)"},
	{"draw", "draw_entities($)"},
	{"enabled", "render.SetStencilEnable($)"},
	{"run", "render.PerformFullScreenStencilOperation()"},
	{"set_compare", "render.SetStencilCompareFunction($)"},
	{"set_fail_operation", "render.SetStencilFailOperation($)"},
	{"set_occluded_operation", "render.SetStencilZFailOperation($)"},
	{"set_pass_operation", "render.SetStencilPassOperation($)"},
	{"set_reference_value", "render.SetStencilReferenceValue($)"},
	{"set_test_mask", "render.SetStencilTestMask($)"},
	{"set_write_mask", "render.SetStencilWriteMask($)"},
}

local prefabs = {
	--fail prefabs
	{
		"fail", {}, {
			{"set_compare", STENCIL_EQUAL},
			{"set_fail_operation", STENCIL_REPLACE},
			
			{"draw", 1},
			
			{"set_compare", STENCIL_NOTEQUAL},
			
			{"draw", 2},
			
			--[[{"set_compare", STENCIL_EQUAL},
			{"set_pass_operation", STENCIL_KEEP},
			{"set_fail_operation", STENCIL_REPLACE},
			{"set_occluded_operation", STENCIL_KEEP},
			{"set_reference_value", 1},
			{"set_test_mask", 255},
			{"set_write_mask", 255},
			{"draw", 0},
			{"set_compare", STENCIL_NOTEQUAL},
			{"draw", 1},]]
		}
	},
	
	--occluded_fail
	{
		"occluded_fail", {}, {
			{"set_compare", STENCIL_ALWAYS},
			{"set_fail_operation", STENCIL_KEEP},
			{"set_occluded_operation", STENCIL_REPLACE},
			{"set_pass_operation", STENCIL_KEEP},
			{"set_reference_value", 1},
			{"set_test_mask", 255},
			{"set_write_mask", 255},
			
			{"draw", 1},
			
			{"set_compare", STENCIL_EQUAL},
			
			{"draw", 2},
		}
	},
	
	--pass
	{
		"pass", {}, {
			{"set_compare", STENCIL_NEVER},
			{"set_fail_operation", STENCIL_REPLACE},
			{"set_occluded_operation", STENCIL_KEEP},
			{"set_pass_operation", STENCIL_KEEP},
			{"set_reference_value", 1},
			{"set_test_mask", 255},
			{"set_write_mask", 255},
			
			{"draw", 1},
			
			{"set_compare", STENCIL_EQUAL},
			{"set_fail_operation", STENCIL_KEEP},
			{"set_pass_operation", STENCIL_REPLACE},
			
			{"draw", 2},
		}
	},
	
	--pass_cleared
	{
		"pass_cleared", {10}, {
			{"set_compare", STENCIL_ALWAYS},
			{"set_fail_operation", STENCIL_KEEP},
			{"set_occluded_operation", STENCIL_KEEP},
			{"set_pass_operation", STENCIL_REPLACE},
			{"set_reference_value", 1},
			{"set_test_mask", 255},
			{"set_write_mask", 255},
			
			{"draw", 1},
			
			{"set_compare", STENCIL_EQUAL},
			
			{"clear", Color(0, 0, 0)},
			{"draw", 2},
		}
	},
	
	--pass_twice
	{
		"pass_twice", {}, {
			{"set_compare", STENCIL_NEVER},
			{"set_fail_operation", STENCIL_INCR},
			{"set_occluded_operation", STENCIL_KEEP},
			{"set_pass_operation", STENCIL_KEEP},
			{"set_reference_value", 1},
			{"set_test_mask", 255},
			{"set_write_mask", 255},
			
			{"draw", 1},
			{"draw", 2},
			
			{"set_compare", STENCIL_EQUAL},
			{"set_fail_operation", STENCIL_KEEP},
			{"set_pass_operation", STENCIL_REPLACE},
			{"set_reference_value", 2},
			
			{"draw", 3},
		}
	},
	
	--pass_twice_both
	{
		"pass_twice_both", {}, {
			{"set_compare", STENCIL_NEVER},
			{"set_fail_operation", STENCIL_INCR},
			{"set_occluded_operation", STENCIL_KEEP},
			{"set_pass_operation", STENCIL_KEEP},
			{"set_reference_value", 1},
			{"set_test_mask", 255},
			{"set_write_mask", 255},
			
			{"draw", 1},
			{"draw", 2},
			
			{"set_compare", STENCIL_EQUAL},
			{"set_fail_operation", STENCIL_KEEP},
			{"set_pass_operation", STENCIL_REPLACE},
			
			{"draw", 3},
			
			{"set_reference_value", 2},
			
			{"draw", 4},
		}
	},
}

--post function setup
for index, pair in ipairs(operations) do --process the operations table
	local name, code = pair[1], pair[2]
	operations[index] = name
	operations[name] = code
	
	if string.find(code, "%$") then
		parameterized_operations[index] = true
		parameterized_operations[name] = true
	end
end

for index, hook_name in ipairs(hooks) do --process the hooks table
	local first = true
	local hook_alias = string.upper(string.gsub(hook_name, "%u%l+", function(matched)
		if first then
			first = false
			
			return matched
		end
		
		return matched[1]
	end))
	
	hook_aliases[index] = hook_alias
	hook_functions[hook_name] = {}
	hooks[hook_name] = index
end

--globals
STENCIL_CORE = STENCIL_CORE or {
	BlockedPlayers = {},
	BroadcastQueue = {},
	ConVarListeners = {},
	ConVars = {},
	HookAliases = hook_aliases,
	HookFunctions = hook_functions,
	Hooks = hooks,
	LoadedPlayers = {},
	LoadingPlayers = {},
	MaximumEntityCount = 8191 - game.MaxPlayers(),
	NetStencilEntitiesQueue = {},
	NetStencilQueue = {},
	Operations = operations,
	ParameterizedOperations = parameterized_operations,
	Prefabs = prefabs,
	Stencils = {},
	Version = "0.1.0",
}