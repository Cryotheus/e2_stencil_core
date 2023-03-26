include("includes/entity_proxy.lua")
util.AddNetworkString("StencilCore")

--locals
local await_load = {} --prevents a really complicated bug with duplicate networking
local duplex_insert = STENCIL_CORE._DuplexInsert
local duplex_remove = STENCIL_CORE._DuplexRemove
local loaded_players = STENCIL_CORE.LoadedPlayers --duplex!
local loading_players = STENCIL_CORE.LoadingPlayers
local player_queued_stencils = {}
local queued_stencils = {}

--lower = more biased to a full sync where 0 is always a full sync and math.huge is always a change sync
--POST: convar me maybe? (full_entity_sync_bias)
local full_entity_sync_bias = 0.9
local stop_net_message_at = 60000 --roughly 58.5kb

--local functions
local function bits(decimal) return math.ceil(math.log(decimal, 2)) end
local function stencil_equal(first, second) return first == second or (first.ChipIndex == second.ChipIndex and first.Index == second.Index) end

--post function setup
local bits_hooks = bits(#STENCIL_CORE.Hooks)
local bits_layer_entities
local bits_layers
local bits_maximum_stencil_index
--local bits_parameters = 0
local bits_prefabs = bits(#STENCIL_CORE.Prefabs)

--local functions
function player_attempt_load(ply) --delay the load until the server is no longer broadcasting updates (prevents duplicate networking)
	if queued_stencils[1] then return end
	
	await_load[ply] = nil
	player_queued_stencils[ply] = nil
		
	duplex_insert(loaded_players, ply)
	hook.Remove("Think", "StencilCoreNet" .. ply:EntIndex())
end

--stencil core functions
function STENCIL_CORE:NetQueueStencil(stencil, behavior)
	if next(loaded_players) then self:NetQueueStencilInternal(stencil, behavior, queued_stencils) end
	
	if next(loading_players) then
		for ply, status in pairs(loading_players) do
			--queue up more for players who have started the initial sync
			if not status then self:NetQueueStencilInternal(stencil, behavior, player_queued_stencils[ply], true) end
		end
	end
end

function STENCIL_CORE:NetQueueStencilInternal(stencil, behavior, queued_stencils, no_hook)
	local queue_length = #queued_stencils
	
	if behavior == false then
		for index = queue_length, 1, -1 do
			local queued_stencil = queued_stencils[index]
			
			if stencil_equal(queued_stencil, stencil) then
				if queued_stencil.NetRemove then return
				else table.remove(queued_stencils, index) end
			end
		end
		
		table.insert(queued_stencils, {
			ChipIndex = stencil.ChipIndex,
			EntityChanges = stencil.EntityChanges,
			EntityLayers = stencil.EntityLayers,
			Index = stencil.Index,
			NetRemove = true,
		})
	else
		if behavior then
			--behavior = true means to tell the client they need to create the stencil
			stencil.NetCreate = true
			
			for index = queue_length, 1, -1 do
				local queued_stencil = queued_stencils[index]
				
				if stencil_equal(queued_stencil, stencil) then
					if queued_stencil.NetRemove then break --we're deleting it, queue for creation
					elseif queued_stencil == stencil then return --it's already queued, we're good
					else error("this should never happen! a stencil attempted to queue when an equivalent stencil was already queued with a difference reference") end
				end
			end
		else
			for index = queue_length, 1, -1 do
				local queued_stencil = queued_stencils[index]
				
				if stencil_equal(queued_stencil, stencil) then
					if queued_stencil.NetRemove or queued_stencil == stencil then return
					else error("this should never happen! a stencil attempted to queue when an equivalent stencil was already queued with a difference reference") end
				end
			end
		end
		
		table.insert(queued_stencils, stencil)
	end
	
	if no_hook then return end
	
	if queue_length == 0 then
		hook.Add("Think", "StencilCoreNet", function()
			--remove the hook if we're done
			if self:NetThink(queued_stencils) then hook.Remove("Think", "StencilCoreNet") end
		end)
	end
end

function STENCIL_CORE:NetThink(queued_stencils, target)
	--if something changed and we're still hooked, destroy the hook
	if not queued_stencils[1] then
		if target then player_attempt_load(target) end
		
		return true
	end
	
	local allow_writing = not target --POST: optimize targetted messages
	local completed = 0
	local queue_length = #queued_stencils
	
	net.Start("StencilCore")
	
	for index, queued_stencil in ipairs(queued_stencils) do
		if net.BytesWritten() >= stop_net_message_at then break end
		
		net.WriteBool(true)
		self:NetWriteStencilIdentifier(queued_stencil)
		
		if queued_stencil.NetRemove then
			net.WriteBool(true)
			
			if allow_writing then
				for layer_index, entity_layer in pairs(queued_stencil.EntityLayers) do
					for index, proxy in ipairs(entity_layer) do
						--we still need to make sure the proxy gets removed, so decrement the reference count
						proxy:DecrementEntityProxyReferenceCount()
					end
				end
				
				for layer_index, entity_layer in pairs(queued_stencil.EntityChanges) do
					for proxy, added in pairs(entity_layer) do
						if not added then
							--we still need to make sure the proxy gets removed, so decrement the reference count
							proxy:DecrementEntityProxyReferenceCount()
						end
					end
				end
			end
		else
			net.WriteBool(false)
			
			if allow_writing then queued_stencil.NetSent = true end
			
			if queued_stencil.NetCreate then
				net.WriteBool(true)
				self:NetWriteStencilData(queued_stencil)
			else net.WriteBool(false) end
			
			--POST: write parameters
			
			local entity_changes = 0
			local entity_layers = queued_stencil.EntityLayers
			local entity_layers_changes = queued_stencil.EntityChanges
			local entities_added = {}
			local entities_removed = {}
			local total_entity_count = queued_stencil.EntityCount
			
			--first we need to count the changes (and prepare the lists)
			for layer_index, entity_layer in pairs(entity_layers) do
				local entity_layer_changes = entity_layers_changes[layer_index]
				
				if entity_layer_changes then
					local added_count = 0
					local entities_added_layer = {}
					local entities_removed_layer = {}
					local removed_count = 0
					
					for entity_proxy, added in pairs(entity_layer_changes) do
						if added then
							added_count = added_count + 1
							
							table.insert(entities_added_layer, entity_proxy)
						else
							removed_count = removed_count + 1
							
							table.insert(entities_removed_layer, entity_proxy)
						end
					end
					
					entities_added_layer.Count, entities_removed_layer.Count = added_count, removed_count
					entities_added[layer_index], entities_removed[layer_index] = entities_added_layer, entities_removed_layer
					entity_changes = entity_changes + added_count + removed_count
					
					if allow_writing then entity_layers_changes[layer_index] = nil end
				end
			end
			
			--the we do the actual writing
			if allow_writing and entity_changes < total_entity_count * full_entity_sync_bias then 
				net.WriteBool(true) --true: syncing with changes
				
				for layer_index, entity_layer in pairs(entity_layers) do
					local entities_added_layer = entities_added[layer_index]
					local entities_removed_layer = entities_removed[layer_index]
					
					if entities_added_layer and entities_removed_layer then
						net.WriteBool(true)
						net.WriteUInt(layer_index - 1, bits_layers)
						net.WriteUInt(entities_added_layer.Count, bits_layer_entities)
						
						for index, proxy in ipairs(entities_added_layer) do entity_proxy.Write(proxy) end
						
						net.WriteUInt(entities_removed_layer.Count, bits_layer_entities)
						
						for index, proxy in ipairs(entities_removed_layer) do
							entity_proxy.Write(proxy)
							
							--we still need to make sure the proxy gets removed, so decrement the reference count
							if allow_writing then proxy:DecrementEntityProxyReferenceCount() end
						end
					elseif allow_writing then entity_layers[layer_index] = nil end
				end
				
				--list ends here
				net.WriteBool(false)
			else --then we sync using changes if it will roughly write less to the net message
				net.WriteBool(false) --false: full sync
				
				--write entities
				for layer_index, entity_layer in pairs(entity_layers) do
					net.WriteBool(true)
					net.WriteUInt(layer_index - 1, bits_layers)
					net.WriteUInt(entity_layer.Count, bits_layer_entities)
					
					for index, proxy in ipairs(entity_layer) do entity_proxy.Write(proxy) end
				end
				
				--list ends here
				net.WriteBool(false)
				
				--garbage collection
				for layer_index, entity_layer in pairs(entities_removed) do
					--we still need to make sure the proxy gets removed, so decrement the reference count
					for index, proxy in ipairs(entity_layer) do if allow_writing then proxy:DecrementEntityProxyReferenceCount() end end
				end
			end
		end
		
		completed = completed + 1
		queued_stencils[index] = nil
	end
	
	net.WriteBool(false)
	
	--send the net message to the target or to all loaded players
	if target then net.Send(target)
	else
		local filter = RecipientFilter()
		
		for index, ply in ipairs(loaded_players) do filter:AddPlayer(ply) end
		
		net.Send(filter)
	end
	
	--faster dequeue
	for index = completed + 1, queue_length do queued_stencils[index - completed] = queued_stencils[index] end
	
	--if we have more to sync, keep the hook alive
	if queued_stencils[1] then return false end
	if target then player_attempt_load(target) end
	
	return true
end

function STENCIL_CORE:NetWriteStencilData(stencil)
	--POST: write stencil parameters
	net.WriteEntity(stencil.Owner)
	net.WriteUInt(self.Hooks[stencil.Hook] - 1, bits_hooks)
	
	if stencil.Prefab then
		net.WriteBool(true)
		net.WriteUInt(stencil.Prefab - 1, bits_prefabs)
	else
		--POST: write stencil instructions
		net.WriteBool(false)
	end 
end

function STENCIL_CORE:NetWriteStencilIdentifier(stencil)
	entity_proxy.Write(stencil.ChipIndex)
	net.WriteUInt(stencil.Index, bits_maximum_stencil_index)
end

--hook
hook.Add("PlayerDisconnected", "StencilCoreNet", function(ply)
	await_load[ply] = nil
	loading_players[ply] = nil
	
	if loaded_players[ply] then duplex_remove(loaded_players, ply) end
	
	hook.Remove("Think", "StencilCoreNet" .. ply:EntIndex())
end)

hook.Add("PlayerInitialSpawn", "StencilCoreNet", function(ply) loading_players[ply] = true end)

--net
hook.Add("SetupMove", "StencilCoreNet", function(ply, _move, command)
	if loading_players[ply] and not command:IsForced() then
		local identifier = "StencilCoreNet" .. ply:EntIndex()
		local queued_stencils = {}
		loading_players[ply] = false
		player_queued_stencils[ply] = queued_stencils
		
		for chip, chip_stencils in pairs(STENCIL_CORE.Stencils) do
			--queue up all the stencils
			for stencil_index, stencil in pairs(chip_stencils) do STENCIL_CORE:NetQueueStencilInternal(stencil, true, queued_stencils, true) end
		end
		
		hook.Add("Think", identifier, function()
			if STENCIL_CORE:NetThink(queued_stencils, ply, true) then
				await_load[ply] = true
				loading_players[ply] = nil
			end
		end)
	end
end)

--post
STENCIL_CORE:ConVarListen("layer_entities", "Net", function(convar) bits_layer_entities = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("layers", "Net", function(convar) bits_layers = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("maximum_stencil_index", "Net", function(convar) bits_maximum_stencil_index = bits(convar:GetInt() + 1) end, true)