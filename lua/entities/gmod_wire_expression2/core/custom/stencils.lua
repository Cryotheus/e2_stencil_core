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

local bits = include("wire_stencil_core/includes/bits.lua")
local stencil_hooks_amount = #stencil_hooks
local stencil_hooks_bits = bits(stencil_hooks_amount)
local stencil_operations = include("wire_stencil_core/includes/operations.lua")
local stencil_operations_amount = #stencil_operations
local stencil_operations_bits = bits(stencil_operations_amount)
local stencil_prefabs

local queue_individual_sync
local queue_removal_sync

----localized functions
	local fl_math_ceil = math.ceil
	local fl_math_log = math.log
	local fl_math_max = math.max
	local request_individual_sync
	local request_removal_sync
	local is_owner = E2Lib.isOwner --first argument is a table with a player and entity key, where player is the owner and entity is the chip; second argu

--local functions
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
	
	request_individual_sync(context, stencil_index, stencil, true)
end

local function initial_sync(ply)
	--when syncing, we use unsigned integers to refer to hooks and operations as it is a lot less network intensive than strings
	net.Start("wire_stencil_core_init")
	
	for operation_id, operation in ipairs(stencil_operations) do net.WriteString(operation) end
	
	--sync stencil hook ids
	net.WriteUInt(stencil_hooks_bits - 1, 5)
	net.WriteUInt(stencil_hooks_amount - 1, stencil_hooks_bits)
	
	for index, hook_event in ipairs(stencil_hooks) do net.WriteString(hook_event) end
	
	if ply then net.Send(ply) else net.Broadcast() end
end

local function remove_stencil(context, stencil_index, no_sync)
	local ply = context.player
	local stencil = context.stencils[stencil_index]
	
	if stencil then
		stencil_counts[ply] = stencil_counts[ply] - 1
		
		if stencil.entities then
			for layer, entities in pairs(stencil.entities) do
				for entity in pairs(entities) do
					--anything more?
					entity:RemoveCallOnRemove("wire_stencil_core")
				end
			end
		end
		
		context.stencils[stencil_index] = nil
		
		if no_sync then return end
		
		request_removal_sync(context, stencil_index)
	end
end

local function remove_stencils(context)
	for stencil_index, stencil in pairs(context.stencils) do remove_stencil(context, stencil_index, true) end
	
	request_removal_sync(context)
end

function request_individual_sync(context, stencil_index, stencil_update, full_sync)
	local chip = context.entity
	stencil_update.full_sync = full_sync or stencil_update.full_sync or nil
	
	if queue_individual_sync then
		local chip_syncs = queue_individual_sync[chip]
		 
		if chip_syncs then
			if full_sync then chip_syncs[stencil_index] = stencil_update
			else table.Merge(chip_syncs[stencil_index], stencil_update) end
		else queue_individual_sync[chip] = {[stencil_index] = stencil_update} end
	else queue_individual_sync = {[chip] = {[stencil_index] = stencil_update}} end
end

function request_removal_sync(context, stencil_index)
	local chip = context.entity
	
	if queue_removal_sync then
		local chip_syncs = queue_removal_sync[chip]
		
		if chip_syncs == false then return end
		
		if stencil_index then
			if chip_syncs then chip_syncs[stencil_index] = true
			else queue_removal_sync[chip] = {[stencil_index] = true} end
		else queue_removal_sync[chip] = false end
	else queue_removal_sync = {} end
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
	},
	
	{
		entities = {{}, {}},
		name = "DIFFER",
		hook = "PostDrawTranslucentRenderables",
		
		{"set_compare", STENCIL_EQUAL},
		{"set_fail_operation", STENCIL_REPLACE},
		{"set_pass_operation", STENCIL_KEEP},
		{"set_reference_value", 1},
		{"set_test_mask", 0xFF},
		{"set_write_mask", 0xFF},
		{"set_zfail_operation", STENCIL_KEEP},
		
		{"draw_entities", 1},
		
		{"set_compare", STENCIL_NOTEQUAL},
		
		{"draw_entities", 2}
	}
}

for operation_id, operation in ipairs(stencil_operations) do
	stencil_operations[operation] = operation_id
	
	E2Lib.registerConstant("_STENCILOP_" .. string.upper(operation), operation_id)
end

for hook_id, hook_event in ipairs(stencil_hooks) do stencil_hooks[hook_event] = hook_id end

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

--e2functions which are fancy pre-processors
__e2setcost(5)
e2function number stencilAddEntity(number stencil_index, number entity_layer, entity entity)
	if stencil_index > 0 and stencil_index <= 65536 and entity_layer > 0 and IsValid(entity) and is_owner(self, entity) then
		entity_layer = math.Round(entity_layer)
		stencil_index = math.Round(stencil_index)
		stencil = self.stencils[stencil_index]
		
		if stencil and entity_layer <= #stencil.entities then
			local entities = stencil.entities[entity_layer]
			
			if entities then
				--don't actually add it again, but still return 1 to let them know it exists
				if entities[entity] then return 1 end
				
				entities[entity] = true
				
				entity:CallOnRemove("wire_stencil_core", function(dying_entity)
					entities[entity] = nil
					
					--sync function
				end)
				
				--sync function
				
				return 1
			end
		end
	end
	
	return 0
end

__e2setcost(10)
e2function number stencilCreate(number stencil_index, number prefab_enumeration)
	if stencil_index > 0 and stencil_index <= 65536 then
		stencil_index = math.Round(stencil_index)
		local prefab = stencil_prefabs[prefab_enumeration]
		
		if prefab then
			local stencils = self.stencils
			
			if stencils[stencil_index] then remove_stencil(self, stencil_index) end
			
			create_stencil(self, stencil_index, prefab)
			
			return 1
		end
	end
	
	return 0
end

e2function number stencilRemove(number stencil_index)
	
end

__e2setcost(5)
e2function number stencilRemoveEntity(number stencil_index, number entity_layer, entity entity)
	if stencil_index > 0 and stencil_index <= 65536 and entity_layer > 0 and IsValid(entity) and is_owner(self, entity) then
		entity_layer = math.Round(entity_layer)
		stencil_index = math.Round(stencil_index)
		stencil = self.stencils[stencil_index]
		
		if stencil and entity_layer <= #stencil.entities then
			local entities = stencil.entities[entity_layer]
			
			if entities and entities[entity] then
				entities[entity] = nil
				
				entity:RemoveCallOnRemove("wire_stencil_core")
				
				--sync function
				
				return 1
			end
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

hook.Add("Think", "wire_stencil_core_extension", function()
	--todo: cap the amount of syncs to do in one net message
	--note: net.BytesWritten(), two returns
	--maybe send multiple net messages, capping the amount that can be sent in a single tick too
	
	--todo: better bool stacking
	--let them know when we are syncing stencils from another chip instead of sending the chip index every time
	if queue_individual_sync then
		local passed = false
		
		net.Start("wire_stencil_core_sync")
		
		for chip, stencil_updates in pairs(queue_individual_sync) do
			for stencil_index, stencil_update in pairs(stencil_updates) do
				local filter = stencil_update.sync_filter
				local full_sync = stencil_update.full_sync
				stencil_update.full_sync = nil
				stencil_update.sync_filter = nil
				
				if passed then net.WriteBool(true)
				else passed = true end
				
				do --sync function
					--stencil_update can be the whole stencil or just values that need to change
					net.WriteUInt(chip:EntIndex(), 13) --8191
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
				end
				
				--goodber jojo
				queue_individual_sync[chip][stencil_index] = nil
			end
			
			queue_individual_sync[chip][stencil_index] = nil
		end
		
		net.Broadcast()
		
		if table.IsEmpty(queue_individual_sync) then queue_individual_sync = nil end
	end
	
	if queue_removal_sync then
		local passed_chip = false
		
		net.Start("wire_stencil_core_remove")
		
		for chip, stencils in pairs(queue_removal_sync) do
			if passed_chip then net.WriteBool(true)
			else passed_chip = true end
			
			net.WriteUInt(chip:EntIndex(), 13) --8191
			
			--remove all from this chip
			if stencils == false then net.WriteBool(true)
			else
				local passed_stencil = false
				
				net.WriteBool(false)
				
				for stencil_index in pairs(stencils) do
					if passed_stencil then net.WriteBool(true)
					else passed_stencil = true end
					
					net.WriteUInt(stencil_index - 1, 16)
				end
				
				net.WriteBool(false)
			end
		end
		
		net.Broadcast()
	end
end)