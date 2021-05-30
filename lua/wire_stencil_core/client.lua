local backup_data = WIRE_STENCIL_CORE.Backup --for autoreload
local encode_digital_color, decode_digital_color = include("wire_stencil_core/includes/digital_color.lua")
local local_player = LocalPlayer() --for reload, it won't actually return a valid player until InitPostEntity runs
local stencil_hooks = backup_data.stencil_hooks or {}
local stencil_hooks_amount = backup_data.stencil_hooks_amount
local stencil_hooks_bits = backup_data.stencil_hooks_bits
local stencil_operation_clear_obedient_id = backup_data.stencil_operation_clear_obedient_id
local stencil_operations = include("wire_stencil_core/includes/operations.lua")
local stencil_operations_amount = backup_data.stencil_operations_amount
local stencil_operations_bits = backup_data.stencil_operations_bits
local stencil_operations_solver = backup_data.stencil_operations_solver or {}
local stencil_repository = backup_data.stencil_repository or {}
backup_data = nil

--localized functions
	local fl_render_ClearStencil = render.ClearStencil
	local fl_render_SetStencilCompareFunction = render.SetStencilCompareFunction
	local fl_render_SetStencilEnable = render.SetStencilEnable
	local fl_render_SetStencilFailOperation = render.SetStencilFailOperation
	local fl_render_SetStencilPassOperation = render.SetStencilPassOperation
	local fl_render_SetStencilReferenceValue = render.SetStencilReferenceValue
	local fl_render_SetStencilTestMask = render.SetStencilTestMask
	local fl_render_SetStencilWriteMask = render.SetStencilWriteMask
	local fl_render_SetStencilZFailOperation = render.SetStencilZFailOperation

--local functions
local function bit_smart_read()
	local bits = net.ReadUInt(5) + 1
	local value = net.ReadUInt(bits) + 1
	
	--enforce overflow
	if value > 2 ^ bits then print("stencil core read overflow! " .. bits .. " bits with a value of " .. value .. ". this is probably a digital color with 0 in all positions.") return 0 end
	
	return value
end

local function construct_debug_switch()
	return {
		hooks = stencil_hooks,
		hooks_amount = stencil_hooks_amount,
		hooks_bits = stencil_hooks_bits,
		local_player = local_player,
		operation_clear_obedient_id = stencil_operation_clear_obedient_id,
		operations = stencil_operations,
		operations_amount = stencil_operations_amount,
		operations_bits = stencil_operations_bits,
		operations_solved = stencil_operations_solver,
		repository = stencil_repository,
	}
end

local function create_hook_tracker(chip_index, stencil_index, hook_event)
	local chip_hooks = stencil_hooks[chip_index]
	
	if chip_hooks then chip_hooks[stencil_index] = hook_event
	else stencil_hooks[chip_index] = {[stencil_index] = hook_event} end
end

local function draw_stencils(repository)
	for chip_index, stencils in pairs(repository) do
		--check if the owner is blocked
		if false then continue end
		
		for stencil_index, stencil in ipairs(stencils) do
			render.ClearStencil()
			render.SetStencilEnable(true)
			
			--run all the operations in order
			for index, operation_data in ipairs(stencil) do operation_data[1](operation_data[2], stencil) end
			
			render.SetStencilEnable(false)
		end
	end
end

local function remove_hook_tracker(chip_index, stencil_index)
	local chip_hooks = stencil_hooks[chip_index]
	
	if chip_hooks then
		local hook_event = chip_hooks[stencil_index]
		chip_hooks[stencil_index] = nil
		
		if table.IsEmpty(chip_hooks) then stencil_hooks[chip_index] = nil end
		
		return hook_event
	end
end

local function remove_stencil(chip_index, hook_event, stencil_index)
	if stencil_index then
		remove_hook_tracker(chip_index, stencil_index)
		
		stencil_repository[hook_event][chip_index][stencil_index] = nil
		
		--free the memory, because why not
		if table.IsEmpty(stencil_repository[hook_event][chip_index]) then stencil_repository[hook_event][chip_index] = nil end
	else
		if hook_event then
			for stencil_index, stencil in pairs(stencil_repository[hook_event][chip_index]) do remove_hook_tracker(chip_index, stencil_index) end
			
			stencil_repository[hook_event][chip_index] = nil
		else
			for hook_event, repository in pairs(stencil_repository) do stencil_repository[hook_event][chip_index] = nil end
			
			stencil_hooks[chip_index] = nil
		end
	end
end

local function transfer_hook_tracker(chip_index, stencil_index, hook_event)
	local old_hook_event = remove_hook_tracker()
	
	stencil_hooks[chip_index][stencil_index] = hook_event
	stencil_repository[hook_event][chip_index] = stencil_repository[old_hook_event][chip_index]
	stencil_repository[old_hook_event][chip_index] = nil
	
	return old_hook_event
end

--concommands
concommand.Add("stencil_debug", function(ply, command, arguments, arguments_string)
	if arguments then
		local first = arguments[1]
		
		if first then
			local switch_cases = construct_debug_switch()
			local switch_value = switch_cases[first]
			
			if switch_value then
				if istable(switch_value) then PrintTable(switch_value, 1)
				else print(switch_value) end
			else print("no case found") end
		else
			print("stencil_repository")
			PrintTable(stencil_repository, 1)
		end
	else
		print("stencil_repository")
		PrintTable(stencil_repository, 1)
	end
end, function(command, arguments_string)
	arguments_string = arguments_string == " " and "" or string.TrimLeft(arguments_string)
	local completes = {}
	
	for complete, switch_table in pairs(construct_debug_switch()) do if string.StartWith(complete, arguments_string) then table.insert(completes, "stencil_debug " .. complete) end end
	
	return completes
end, "Debugging function for Stencil Core 2.")

--hooks
hook.Add("InitPostEntity", "wire_stencil_core", function()
	local_player = LocalPlayer()
	
	net.Start("wire_stencil_core_init")
	net.SendToServer()
end)

hook.Remove("PostDrawTranslucentRenderables", "wire_stencil_core")

net.Receive("wire_stencil_core_init", function()
	stencil_operations_bits = net.ReadUInt(5) + 1
	stencil_operations_amount = net.ReadUInt(stencil_operations_bits) + 1
	
	for index = 1, stencil_operations_amount do
		local operation = net.ReadString()
		
		--special handling here, may make this modular in the future instead of a single special case
		if operation == "clear_obedient" then stencil_operation_clear_obedient_id = index end
		
		stencil_operations[index] = stencil_operations[operation]
		stencil_operations_solver[index] = operation
		stencil_operations_solver[operation] = index
	end
	
	stencil_hooks_bits = net.ReadUInt(5) + 1
	stencil_hooks_amount = net.ReadUInt(stencil_hooks_bits) + 1
	
	for index = 1, stencil_hooks_amount do
		local hook_event = net.ReadString()
		
		stencil_hooks[hook_event] = index
		stencil_hooks[index] = hook_event
		stencil_repository[hook_event] = {}
		
		hook.Add(hook_event, "wire_stencil_core_render", function(depth, sky)
			if sky then return end
			
			draw_stencils(stencil_repository[hook_event])
		end)
	end
	
	WIRE_STENCIL_CORE.Backup = {
		stencil_hooks = stencil_hooks,
		stencil_hooks_amount = stencil_hooks_amount,
		stencil_hooks_bits = stencil_hooks_bits,
		stencil_operation_clear_obedient_id = stencil_operation_clear_obedient_id,
		stencil_operations = stencil_operations,
		stencil_operations_amount = stencil_operations_amount,
		stencil_operations_bits = stencil_operations_bits,
		stencil_operations_solver = stencil_operations_solver,
		stencil_repository = stencil_repository
	}
end)

net.Receive("wire_stencil_core_remove", function()
	local chip_index = net.ReadUInt(13) --8191
	local remove_all = net.ReadBool()
	
	print("got a wire_stencil_core_remove with chip_index " .. tostring(chip_index) .. " and a remove_all of " .. tostring(remove_all))
	
	if remove_all then remove_stencil(chip_index)
	else
		local stencil_index = net.ReadUInt(16) + 1 --65536
		
		remove_stencil(chip_index, stencil_index)
	end
end)

net.Receive("wire_stencil_core_sync", function()
	local chip_index = net.ReadUInt(13) --8191
	local stencil_index = net.ReadUInt(16) + 1 --65536
	local full_sync = net.ReadBool()
	local index_bits = net.ReadUInt(5) + 1
	local operation_count = net.ReadUInt(index_bits) + 1
	
	if full_sync then
		local hook_event = stencil_hooks[net.ReadUInt(stencil_hooks_bits) + 1]
		local old_hook_event = stencil_hooks[chip_index]
		local repository = stencil_repository[hook_event]
		local stencil = {hook = hook_event}
		
		print("full sync with the hook " .. hook_event .. " and the old hook " .. tostring(old_hook_event))
		print("our repository is " .. tostring(repository))
		
		--if there was an old hook, remove it
		if old_hook_event then remove_hook_tracker(chip_index, stencil_index) end
		
		--slap the operations into the stencil table
		for index = 1, operation_count do
			local operation_index = net.ReadUInt(stencil_operations_bits) + 1
			
			print("got operation_index of " .. operation_index)
			
			--specific case for the clear_obedient operation where we have to convert it to a color; this will probably be made modular in the future
			if operation_index == stencil_operation_clear_obedient_id then stencil[index] = {stencil_operations[operation_index], Color(decode_digital_color(bit_smart_read()))}
			else stencil[index] = {stencil_operations[operation_index], bit_smart_read()} end
		end
		
		--finaly create the stencil table in the repository
		if repository[chip_index] then repository[chip_index][stencil_index] = stencil
		else repository[chip_index] = {[stencil_index] = stencil} end
	else
		local hook_changed = net.ReadBool()
		local hook_event
		local old_hook_event = stencil_hooks[chip_index][stencil_index]
		
		--move the stencil around as needed if the hook changes
		if hook_changed then
			hook_event = stencil_hooks[net.ReadUInt(stencil_hooks_bits) + 1]
			
			transfer_hook_tracker(chip_index, stencil_index, hook_event)
		else hook_event = old_hook_event end
		
		local repository = stencil_repository[hook_event]
		local stencil = repository[chip_index][stencil_index]
		
		--update the changed steps
		for index = 1, operation_count do
			local operation_index = net.ReadUInt(stencil_operations_bits) + 1
			local step = net.ReadUInt(index_bits) + 1
			
			--specific case for the clear_obedient operation where we have to convert it to a color; this will probably be made modular in the future
			if operation_index == stencil_operation_clear_obedient_id then stencil[step] = {stencil_operations[operation_index], Color(decode_digital_color(bit_smart_read()))}
			else stencil[step] = {stencil_operations[operation_index], bit_smart_read()} end
		end
	end
end)