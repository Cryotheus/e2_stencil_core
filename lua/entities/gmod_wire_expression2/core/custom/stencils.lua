--locals
local encode_digital_color, decode_digital_color = include("wire_stencil_core/includes/digital_color.lua")
local stencil_counts = {}
local stencil_enumerations = {
	ALWAYS = 8,
	DECR = 8,
	DECRSAT = 5,
	EQUAL = 3,
	GREATER = 5,
	GREATEREQUAL = 7,
	INCR = 7,
	INCRSAT = 4,
	INVERT = 6,
	LESS = 2,
	LESSEQUAL = 4,
	NEVER = 1,
	NOTEQUAL = 6,
	REPLACE = 3,
	KEEP = 1,
	ZERO = 2
}

local stencil_hooks = {
	"PostDrawOpaqueRenderables",
	"PostDrawTranslucentRenderables",
	"PreDrawOpaqueRenderables",
	"PreDrawTranslucentRenderables"
}

local stencil_hooks_amount = #stencil_hooks
local stencil_hooks_bits = math.ceil(math.log(stencil_hooks_amount, 2))
local stencil_operations = include("wire_stencil_core/includes/operations.lua")
local stencil_operations_amount = #stencil_operations
local stencil_operations_bits = math.ceil(math.log(stencil_operations_amount, 2))
local stencil_prefabs

----localized functions
	local fl_math_ceil = math.ceil
	local fl_math_log = math.log
	local fl_math_max = math.max
	local individual_sync

--local functions
local function bits(number) return fl_math_max(fl_math_ceil(fl_math_log(number, 2)), 1) end

local function bit_smart_write(value)
	local value_bits = bits(value)
	
	print("writing " .. value_bits .. " bits for a value of " .. value)
	
	net.WriteUInt(value_bits - 1, 5) --the amount of bits that the operation value is made of
	net.WriteUInt(value - 1, value_bits) --the value itself
end

local function create_stencil(context, stencil_index, stencil)
	local ply = context.player
	local stencil_count = stencil_counts[ply]
	
	context.stencils[stencil_index] = stencil
	
	if stencil_count then stencil_counts[ply] = stencil_count + 1
	else stencil_counts[ply] = 1 end
	
	individual_sync(context, stencil_index, stencil, true)
end

function individual_sync(context, stencil_index, stencil_update, full_sync, ply)
	--stencil_update can be the whole stencil or just values that need to change
	net.Start("wire_stencil_core_sync")
	net.WriteUInt(context.entity:EntIndex(), 13) --8191
	net.WriteUInt(stencil_index - 1, 16) --65536
	net.WriteBool(full_sync)
	
	local index_amount = #stencil_update
	local index_bits = bits(index_amount)
	
	--exposing bit_smart_write
	net.WriteUInt(index_bits - 1, 5)
	net.WriteUInt(index_amount - 1, index_bits)
	
	if full_sync then
		net.WriteUInt(stencil_update.hook - 1, stencil_hooks_bits) --the numerical hook id
		
		for index, operation_data in ipairs(stencil_update) do
			net.WriteUInt(operation_data[1] - 1, stencil_operations_bits) --the operation
			bit_smart_write(operation_data[2])
		end
	else
		local hook_changed = stencil_update.hook_changed or false
		
		if hook_changed then
			net.WriteBool(true)
			net.WriteUInt(stencil.hook - 1, stencil_hooks_bits) --the numerical hook id
		else net.WriteBool(false) end
		
		for index, operation_data in pairs(stencil_update) do
			if isnumber(index) then
				net.WriteUInt(operation_index - 1, stencil_operations_bits) --the operation
				net.WriteUInt(index - 1, index_bits) --the step or chonological placement of the operation
				bit_smart_write(operation_data[2])
			end
		end
	end
	
	if ply then net.Send(ply) else net.Broadcast() end
end

local function initial_sync(ply)
	--when syncing, we use unsigned integers to refer to hooks and operations as it is a lot less network intensive than strings
	net.Start("wire_stencil_core_init")
	
	--sync stencil operation ids
	net.WriteUInt(stencil_operations_bits - 1, 5)
	net.WriteUInt(stencil_operations_amount - 1, stencil_operations_bits)
	
	for operation_id, operation in ipairs(stencil_operations) do net.WriteString(operation) end
	
	--sync stencil hook ids
	net.WriteUInt(stencil_hooks_bits - 1, 5)
	net.WriteUInt(stencil_hooks_amount - 1, stencil_hooks_bits)
	
	for index, hook_event in ipairs(stencil_hooks) do net.WriteString(hook_event) end
	
	if ply then net.Send(ply) else net.Broadcast() end
end

local function removal_sync(chip_index, stencil_index)
	net.Start("wire_stencil_core_remove")
	net.WriteUInt(chip_index, 13) --8191
	
	if stencil_index then 
		net.WriteBool(false)
		net.WriteUInt(stencil_index - 1, 16)
	else net.WriteBool(true) end
	
	net.Broadcast()
end

local function remove_stencil(context, stencil_index, no_sync)
	local ply = context.player
	local stencil = context.stencils[stencil_index]
	
	if stencil then
		stencil_counts[ply] = stencil_counts[ply] - 1
		
		if stencil.entities then
			for layer, entities in pairs(stencil.entities) do
				for entity in pairs(entities) do
					--do what ever was needed to all the entities
					--probably remove a CallOnRemove
				end
			end
		end
		
		context.stencils[stencil_index] = nil
		
		if no_sync then return end
		
		removal_sync(context.entity:EntIndex(), stencil_index)
	end
end

local function remove_stencils(context)
	for stencil_index, stencil in pairs(context.stencils) do remove_stencil(context, stencil_index, true) end
	
	removal_sync(context.entity:EntIndex())
end

--globals
function WIRE_STENCIL_CORE:WireStencilCoreInitialSync(...) initial_sync(...) end

--post function setup
E2Lib.RegisterExtension("stencils", true, "Allows E2 to create and manipulate intangible stencils. Stencils can be used to control rendering with specified entities.")

for enumeration, value in pairs(stencil_enumerations) do
	--create the enums serverside
	_G["STENCIL_" .. enumeration] = value
	
	E2Lib.registerConstant("_STENCIL_" .. enumeration, value)
end

--we need the server side enums before we create the prefabs
--[[
	"clear",
	"clear_obedient",
	"draw_quad",
	"draw_entities",
	"set_compare",
	"set_fail_operation",
	"set_pass_operation",
	"set_reference_value",
	"set_test_mask",
	"set_write_mask",
	"set_zfail_operation"
]]

stencil_prefabs = {
	{
		entities = {{}, {}}, --don't create entity layers automatically
		name = "MATCH",
		hook = "PostDrawTranslucentRenderables",
		
		--operations are the numerical indices
		{"set_compare", STENCIL_ALWAYS},
		{"set_fail_operation", STENCIL_KEEP},
		{"set_pass_operation", STENCIL_REPLACE},
		{"set_reference_value", 1},
		{"set_test_mask", 0xFF},
		{"set_write_mask", 0xFF},
		{"set_zfail_operation", STENCIL_KEEP},
		
		{"draw_entities", 1},
		
		{"set_compare", STENCIL_EQUAL},
		{"clear_obedient", color_black},
		
		{"draw_entities", 2}
	}
}

for operation_id, operation in ipairs(stencil_operations) do
	stencil_operations[operation] = operation_id
	
	E2Lib.registerConstant("_STENCILOP_" .. string.upper(operation), operation_id)
end

for hook_id, hook_event in ipairs(stencil_hooks) do stencil_hooks[hook_event] = hook_id end

print("stencil_prefabs before")
PrintTable(stencil_prefabs, 1)

for prefab_index, stencil_prefab in ipairs(stencil_prefabs) do
	local hook_event = stencil_prefab.hook
	
	E2Lib.registerConstant("_STENCILPREFAB_" .. stencil_prefab.name, prefab_index)
	
	--convert operations into their numerical operation_id
	--and also convert values like colors into digital colors
	for index, operation_data in ipairs(stencil_prefab) do
		local operation = operation_data[1]
		local value = operation_data[2]
		
		if IsColor(value) then operation_data[2] = encode_digital_color(value) end
		if isstring(operation) then operation_data[1] = stencil_operations[operation] end
	end
	
	--convert the hook into its numerical proponent
	if isstring(hook_event) then stencil_prefab.hook = stencil_hooks[hook_event] end
end

print("stencil_prefabs after")
PrintTable(stencil_prefabs, 1)

--e2functions which are fancy pre-processors
__e2setcost(3)
e2function number stencilCreate(number index, number prefab_enumeration)
	if index > 0 and index <= 65536 then
		index = math.Round(index)
		local prefab = stencil_prefabs[prefab_enumeration]
		
		if prefab then
			local stencils = self.stencils
			
			if stencils[index] then remove_stencil(self, index) end
			
			create_stencil(self, index, prefab)
			
			return 1
		end
	end
	
	return 0
end

--call backs
registerCallback("construct", function(self)
	self.stencils = {}
	
	--[[
		CollisionData:
				DeltaTime       =       0
				HitEntity       =       [NULL Entity]
				HitNormal:
						1       =       0
						2       =       0
						3       =       0
				HitPos:
						1       =       0
						2       =       0
						3       =       0
				OurEntity       =       [NULL Entity]
				OurOldVelocity:
						1       =       0
						2       =       0
						3       =       0
				Speed   =       0
				TheirOldVelocity:
						1       =       0
						2       =       0
						3       =       0
				Valid   =       false
		GlobalScope:
				lookup:
				vclk:
		Scope:
				lookup:
				vclk:
		ScopeID =       0
		Scopes:
				0:
						lookup:
						vclk:
		cameras:
		data:
				EGP:
						RunOnEGP:
						UpdatesNeeded:
				changed:
				constraintUndos =       true
				datasignal:
						groups:
						scope   =       0
				dmgtriggerbyall =       false
				dmgtriggerents:
				effect_burst    =       4
				find:
						bl_class:
						bl_entity:
						bl_model:
						bl_owner:
						filter_default  =       function: 0x29ff4800
						wl_class:
						wl_entity:
						wl_model:
						wl_owner:
				findcount       =       10
				findlist:
				findnext        =       0
				gvars:
						group   =       default
						shared  =       0
				holo:
						nextBurst       =       108.68499755859
						nextSpawn       =       99.684997558594
						remainingSpawns =       80
				holos:
				poseParamCount  =       0
				posesToSend:
				propSpawnEffect =       true
				propSpawnUndo   =       true
				rangerpersist   =       false
				signalgroup     =       default
				sound_data:
						burst   =       8
						count   =       0
						sounds:
				spawnedProps:
				timer:
						timerid =       0
						timers:
		entity  =       Entity [128][gmod_wire_expression2]
		funcs:
		funcs_ret:
				holo(nevvav)    =
				holo(nevvavs)   =
				holo(nevvavss)  =
				holo(nevvaxv4)  =
				holo(nevvaxv4s) =
				holo(nevvaxv4ss)        =
				holo(nnvvav)    =
				holo(nnvvavs)   =
				holo(nnvvavss)  =
				holo(nnvvaxv4)  =
				holo(nnvvaxv4s) =
				holo(nnvvaxv4ss)        =
		includes:
		lights:
		player  =       Player [1][Cryotheum]
		prf     =       0
		prfbench        =       0
		prfcount        =       0
		strfunc_cache:
		time    =       0
		timebench       =       0
		triggercache:
		uid     =       1621977092
		vclk:
	]]
end)

registerCallback("destruct", function(self) remove_stencils(self) end)

--hooks
hook.Add("PlayerDisconnected", "wire_stencil_core_extension", function(ply) stencil_counts[ply] = nil end)