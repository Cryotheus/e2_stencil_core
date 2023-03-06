include("includes/entity_proxy.lua")
util.AddNetworkString("stencil_core")

--locals
local loaded_players = STENCIL_CORE.LoadedPlayers
local loading_players = STENCIL_CORE.LoadingPlayers
local network_think_methods = {"NetWriteStencils", "NetWriteStencilsEntities"}
local maximum_net_size = 60000 --just shy of 64KB, the maximum size of a net message

--local functions
local function bits(decimal) return math.ceil(math.log(decimal, 2)) end

--post function setup
local bits_layer_entities
local bits_layers
local bits_maximum_stencil_index
local bits_parameters = 0
local bits_prefabs = bits(#STENCIL_CORE.Prefabs)

--globals
STENCIL_CORE.NetHookBits = bits(#STENCIL_CORE.Hooks)

--stencil core functions
function STENCIL_CORE:NetPlayerLoad(ply)
	if loading_players[ply] then
		loaded_players[ply] = true
		loading_players[ply] = nil
		
		STENCIL_CORE:NetSendStencils(ply)
	end
end

function STENCIL_CORE:NetQueueStencil(stencil, method, deletion)
	--method is a number representing what we are sending
	--1: stencil data
	--2: stencil entities
	local chip = stencil.Chip
	local identifier = "StencilCoreNet" .. method
	local index = stencil.Index
	local queue = method == 1 and self.NetStencilQueue or self.NetStencilEntitiesQueue
	
	if deletion then --delete stencil on client
		for index = #queue, 1, -1 do
			local queued_stencil = queue[index]
			
			if queued_stencil.Chip == chip and queued_stencil.Index == index then
				--don't make another delete stencil if there's already one queued
				if queued_stencil.Delete then return end
				
				--remove any other stencil updates from the queue
				table.remove(queue, index)
			end
		end
		
		--a discounted stencil for the sole purpose of deleting the client-side copy
		table.insert(queue, {
			Chip = chip,
			ChipIndex = stencil.ChipIndex,
			Delete = true,
			Index = index,
		})
	else --update stencil on client
		for index, queued_stencil in ipairs(queue) do
			--this works with stencils that have the exact same chip and stencil index
			--this is due to the fact that tables use a different reference when we create a new stencil
			if queued_stencil == stencil then return end
		end
		
		table.insert(queue, stencil)
	end
	
	--start running the queue
	if queue[2] then return end
	
	hook.Add("Think", identifier, function() if self:NetThink(queue, method) then hook.Remove("Think", identifier) end end)
end

function STENCIL_CORE:NetSendStencils(ply)
	local player_index = ply:EntIndex()
	local identifier_1 = "StencilCoreNet1_" .. player_index
	local identifier_2 = "StencilCoreNet2_" .. player_index
	local queue = {}
	
	for chip, chip_stencils in pairs(self.Stencils) do
		--POST: optimize me!
		for index, stencil in pairs(chip_stencils) do
			if stencil.Sent then table.insert(queue, stencil) end
		end
	end
	
	--don't make an empty queue
	if not queue[1] then return end
	
	hook.Add("Think", identifier_1, function() if self:NetThink(queue, 1, ply) then hook.Remove("Think", identifier_1) end end)
	hook.Add("Think", identifier_2, function() if self:NetThink(queue, 2, ply) then hook.Remove("Think", identifier_2) end end)
end

function STENCIL_CORE:NetThink(queue, method, recipient)
	net.Start("stencil_core")
	net.WriteUInt(method - 1, 1)
	
	--how to confuse glua noobs, this:
	local completed = self[network_think_methods[method]](self, queue, not recipient)
	
	--tell the client there is no more to read
	net.WriteBool(false)
	
	if recipient then net.Send(recipient)
	else --send to players who 
		recipient = RecipientFilter()
		
		for index, ply in ipairs(player.GetHumans()) do if loaded_players[ply] then recipient:AddPlayer(ply) end end
		
		net.Send(recipient)
	end
	
	--simulatanously remove the completed stencils from the queue and shift the remaining stencils to the front of the queue
	for index = completed + 1, #queue do queue[index - completed], queue[index] = queue[index], nil end
	
	--return true if we are done
	return not queue[1]
end

function STENCIL_CORE:NetWriteEntityLayer(layer)
	net.WriteUInt(#layer, bits_layer_entities)
	
	for index, entity in ipairs(layer) do entity_proxy.Write(entity:EntIndex()) end
end

function STENCIL_CORE:NetWriteInstructions(stencil) end --POST: implement me!
function STENCIL_CORE:NetWriteParameters(parameters) end --POST: implement me!

function STENCIL_CORE:NetWriteStencilData(stencil)
	net.WriteEntity(stencil.Owner)
	self:NetWriteParameters(stencil.Parameters)
	net.WriteUInt(self.Hooks[stencil.Hook] - 1, self.NetHookBits)
	net.WriteBool(stencil.Prefab and true or false)
	
	if stencil.Prefab then net.WriteUInt(stencil.Prefab - 1, bits_prefabs)
	else error("unimplemented") end --POST: implement me!
end

function STENCIL_CORE:NetWriteStencilIdentifier(stencil)
	net.WriteUInt(stencil.Index, bits_maximum_stencil_index)
	entity_proxy.Write(stencil.ChipIndex)
end

function STENCIL_CORE:NetWriteStencils(queue, broadcast)
	local completed = 0
	local passed = false
	
	for index, stencil in ipairs(queue) do
		if net.BytesWritten() > maximum_net_size then break end
		
		--we only write a true if there's more for the client to read
		if passed then net.WriteBool(true)
		else passed = true end
		
		self:NetWriteStencilIdentifier(stencil)
		
		if stencil.Delete then net.WriteBool(true)
		else
			net.WriteBool(false) --don't delete!
			self:NetWriteStencilData(stencil)
			
			if broadcast then stencil.Sent = true end
		end
		
		completed = index
		queue[index] = nil
	end
	
	return completed
end

function STENCIL_CORE:NetWriteStencilsEntities(queue)
	local completed = 0
	local passed = false
	
	for index, stencil in ipairs(queue) do
		if net.BytesWritten() > maximum_net_size then break end
		
		--we only write a true if there's more for the client to read
		if passed then net.WriteBool(true)
		else passed = true end
		
		local entity_layers = stencil.EntityLayers
		--[[local entity_layers_update = stencil.EntityLayersUpdate
		
		if entity_layers_update then
			stencil.EntityLayersUpdate = nil
			
			if stencil.EntityCount <= stencil.EntityUpdateCount then entity_layers = entity_layers_update end
		end]]
		
		self:NetWriteStencilIdentifier(stencil)
		net.WriteUInt(table.Count(entity_layers), bits_layers)
	
		for index, entity_layer in pairs(entity_layers) do
			net.WriteUInt(index - 1, bits_layers)
			self:NetWriteEntityLayer(entity_layer)
		end
		
		completed = index
		queue[index] = nil
	end
	
	return completed
end

--hooks
hook.Add("PlayerDisconnected", "StencilCore", function(ply)
	local player_index = ply:EntIndex()
	loaded_players[ply] = nil
	loading_players[ply] = nil
	
	hook.Remove("Think", "StencilCoreNet1_" .. player_index)
	hook.Remove("Think", "StencilCoreNet2_" .. player_index)
end)

hook.Add("PlayerInitialSpawn", "StencilCore", function(ply) loading_players[ply] = true end)

--net
net.Receive("stencil_core", function(length, ply) STENCIL_CORE:NetPlayerLoad(ply) end)

--post
STENCIL_CORE:ConVarListen("layer_entities", "Net", function(convar) bits_layer_entities = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("layers", "Net", function(convar) bits_layers = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("maximum_stencil_index", "Net", function(convar) bits_maximum_stencil_index = bits(convar:GetInt() + 1) end, true)