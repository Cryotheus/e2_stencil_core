--locals
local duplex_insert = STENCIL_CORE._DuplexInsert
local duplex_remove = STENCIL_CORE._DuplexRemove
local maximum_entities
local maximum_layer_entities
local maximum_stencils

--local function
local function set_entity_change(entity_layer_changes, proxy, added)
	local current = entity_layer_changes[proxy]
	
	if current == nil then entity_layer_changes[proxy] = added
	elseif current ~= added then entity_layer_changes[proxy] = nil end
end

--stencil core functions
function STENCIL_CORE:StencilAddEntity(entity, stencil, layer_index)
	local proxy = entity_proxy.Get("StencilCore", entity)
	
	if stencil.EntityCount >= maximum_entities then return end
	
	local entity_layers = stencil.EntityLayers
	local entity_layer = entity_layers[layer_index]
	
	--prevent duplicate counting
	if entity_layer then
		if entity_layer[proxy] then return end
		if entity_layer.Count >= maximum_layer_entities then return end
	else
		entity_layer = {proxy, [proxy] = 1, Count = 0}
		entity_layers[layer_index] = entity_layer
	end
	
	duplex_insert(entity_layer, proxy)
	proxy:IncrementEntityProxyReferenceCount() --we decrement in net/server.lua
	self:NetQueueStencil(stencil)
	self:StencilCountEntity(stencil, entity_layer, 1)
	self:StencilEntityChanged(proxy, stencil, layer_index, true)
	
	function proxy:OnProxiedEntityRemove() STENCIL_CORE:StencilRemoveEntity(self, stencil) end
	
	return true
end

function STENCIL_CORE:StencilEntityChanged(proxy, stencil, layer_index, added)
	local entity_layers_changes = stencil.EntityChanges
	local entity_layer_changes = entity_layers_changes[layer_index]
	
	if not entity_layer_changes then
		entity_layer_changes = {}
		entity_layers_changes[layer_index] = entity_layer_changes
	end
	
	set_entity_change(entity_layer_changes, proxy, added)
end

function STENCIL_CORE:StencilCountEntity(stencil, entity_layer, count)
	entity_layer.Count = entity_layer.Count + count
	stencil.EntityCount = stencil.EntityCount + count
end

function STENCIL_CORE:StencilCreate(chip_context, index, nil_instructions)
	local ply = chip_context.player
	
	if self.StencilCounter[ply] >= maximum_stencils then return end
	
	local stencils = self.Stencils
	local chip = chip_context.entity
	local chip_stencils = stencils[chip]
	local existing_stencil = chip_stencils[index]
	
	if existing_stencil then return existing_stencil end
	
	local stencil = {
		Chip = chip,
		ChipIndex = chip:EntIndex(),
		Enabled = false,
		EntityCount = 0,
		EntityChanges = {},
		EntityLayers = {},
		Hook = "PreDrawTranslucentRenderables",
		Index = index,
		Instructions = not nil_instructions and {} or nil,
		Owner = ply,
		Parameters = {},
		Prefab = nil,
	}
	
	--[[
	if not next(chip_stencils) then
		chip:CallOnRemove("StencilCore", function()
			if stencils[chip] then
				stencils[chip] = nil
				
				self:StencilPurge(chip_context)
			end
		end)
	end --]]
	
	chip_stencils[index] = stencil
	self.StencilCounter[ply] = self.StencilCounter[ply] + 1
	
	return stencil
end

function STENCIL_CORE:StencilCreatePrefabricated(chip_context, index, prefab_index)
	local prefab = self.Prefabs[prefab_index]
	
	--prevent invalid prefabs
	if not prefab then return end
	
	local stencil = self:StencilCreate(chip_context, index, true)
	
	--we can fail at creating a stencil if one already exists for the chip, or we hit our limit
	if not stencil then return end
	
	--stencil.Instructions = table.Copy(prefab[2]) --no need to send instructions, the client already has them
	stencil.Prefab = prefab_index
	
	return stencil
end

function STENCIL_CORE:StencilDelete(chip, index)
	local chip_stencils = self.Stencils[chip]
	local stencil = chip_stencils[index]
	
	if stencil then
		local ply = chip.context.player
		chip_stencils[index] = nil
		stencil.Removed = true
		self.StencilCounter[ply] = self.StencilCounter[ply] - 1
		
		self:NetQueueStencil(stencil, false)
	end
end

function STENCIL_CORE:StencilEnable(stencil, enable)
	if stencil.Enabled == enable then return end
	
	stencil.Enabled = enable
	
	if enable then self:NetQueueStencil(stencil, true)
	else
		stencil.NetSent = false
		
		self:NetQueueStencil(stencil, false)
	end
end

function STENCIL_CORE:StencilPurge(chip_context) --POST: we can optimize this
	local count = 0
	local ply = chip_context.player
	local stencils = self.Stencils[chip_context.entity]
	
	for index, stencil in pairs(stencils) do
		count = count + 1
		stencils[index] = nil
		
		self:NetQueueStencil(stencil, false)
	end
	
	self.StencilCounter[ply] = self.StencilCounter[ply] - count
end

function STENCIL_CORE:StencilRemoveEntity(entity, stencil, layer_index)
	local proxy = entity_proxy.GetExisting("StencilCore", entity)
	
	--all stencil entities are proxied, so if this entity isn't proxied then it doesn't need to be removed
	if not proxy then return end
	
	local entity_layers = stencil.EntityLayers
	
	if layer_index then --removing entity from specific layer
		local entity_layer = entity_layers[layer_index]
		
		if entity_layer[proxy] then
			--remove callback
			proxy.OnProxiedEntityRemove = nil
			
			duplex_remove(entity_layer, proxy)
			self:NetQueueStencil(stencil)
			self:StencilCountEntity(stencil, entity_layer, -1)
			self:StencilEntityChanged(proxy, stencil, layer_index, false)
		end
		
		return
	end
	
	--removing entity from all layers
	local need_queue = false
	
	for layer_index, entity_layer in pairs(entity_layers) do
		if entity_layer[proxy] then
			need_queue = true
			
			duplex_remove(entity_layer, proxy)
			self:StencilCountEntity(stencil, entity_layer, -1)
			self:StencilEntityChanged(proxy, stencil, layer_index, false)
		end
	end
	
	if need_queue then self:NetQueueStencil(stencil) end
end

--hooks
hook.Add("PlayerDisconnected", "StencilCore", function(ply)
	STENCIL_CORE.StencilCounter[ply] = nil
	
	--remove stencils for all their chips
	--I don't care if they should stay, I don't want to deal with something as nightmarish as this
	for chip in pairs(STENCIL_CORE.Stencils) do
		local chip_context = chip.context
		
		if chip_context.player == ply then STENCIL_CORE:StencilPurge(chip_context) end
	end
end)

hook.Add("PlayerInitialSpawn", "StencilCore", function(ply) STENCIL_CORE.StencilCounter[ply] = 0 end)

--post
STENCIL_CORE:ConVarListen("entities", "Core", function(convar) maximum_entities = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("layer_entities", "Core", function(convar) maximum_layer_entities = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("maximum_stencils", "Core", function(convar) maximum_stencils = convar:GetInt() end, true)