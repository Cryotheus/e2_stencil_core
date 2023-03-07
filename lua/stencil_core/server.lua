--locals
local duplex_insert = STENCIL_CORE._DuplexInsert
local duplex_remove = STENCIL_CORE._DuplexRemove
local maximum_entities
local maximum_layer_entities
local maximum_stencils

--stencil core functions
function STENCIL_CORE:StencilAddEntity(chip_context, entity, stencil, layer_index)
	if stencil.EntityCount >= maximum_entities then return end
	
	local entity_layers = stencil.EntityLayers
	local entity_layer = entity_layers[layer_index]
	local old_count
	
	--prevent duplicate counting
	if entity_layer then
		if entity_layer[entity] then return end
		if entity_layer.Count >= maximum_layer_entities then return end
	else
		entity_layer = {entity, [entity] = 1, Count = 0}
		entity_layers[layer_index] = entity_layer
	end
	
	duplex_insert(entity_layer, entity)
	entity:CallOnRemove("StencilCore", function(entity) STENCIL_CORE:StencilRemoveEntity(chip_context, entity, stencil) end)
	self:NetQueueStencil(stencil, 2)
	self:StencilCountEntity(stencil, entity_layer, 1)
	
	return true
end

function STENCIL_CORE:StencilCountEntity(stencil, entity_layer, count)
	entity_layer.Count = entity_layer.Count + count
	stencil.EntityCount = stencil.EntityCount + count
end

function STENCIL_CORE:StencilCreate(chip_context, index, nil_instructions)
	local ply = chip_context.player
	
	if self.StencilCounter[ply] >= maximum_stencils then return end
	
	local chip = chip_context.entity
	local chip_stencils = self.Stencils[chip]
	
	if chip_stencils[index] then return end
	
	local stencil = {
		Chip = chip,
		ChipIndex = chip:EntIndex(),
		Enabled = false,
		EntityCount = 0,
		EntityLayers = {},
		Hook = "PreDrawTranslucentRenderables",
		Index = index,
		Instructions = not nil_instructions and {} or nil,
		Owner = ply,
		Parameters = {},
		Prefab = nil,
	}
	
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
	if self.Stencils[chip][index] then
		local ply = chip.context.player
		self.Stencils[chip][index] = nil
		self.StencilCounter[ply] = self.StencilCounter[ply] - 1
		
		self:NetQueueStencil(stencil, 1, true)
	end
end

function STENCIL_CORE:StencilEnable(stencil, enable)
	if stencil.Enabled == enable then return end
	
	stencil.Enabled = enable
	
	if enable then self:NetQueueStencil(stencil, 1)
	else
		stencil.Sent = false
		
		self:NetQueueStencil(stencil, 1, true)
	end
end

function STENCIL_CORE:StencilPurge(chip_context) --POST: we can optimize this
	local count = 0
	local ply = chip_context.player
	local stencils = self.Stencils[chip_context.entity]
	
	for index, stencil in pairs(stencils) do
		count = count + 1
		stencils[index] = nil
		
		self:NetQueueStencil(stencil, 1, true)
	end
	
	self.StencilCounter[ply] = self.StencilCounter[ply] - count
end

function STENCIL_CORE:StencilRemoveEntity(self, entity, stencil, layer_index)
	local entity_layers = stencil.EntityLayers
	
	if layer_index then
		local entity_layer = entity_layers[layer_index]
		
		if entity_layer[entity] then
			duplex_remove(entity_layer, entity)
			entity:RemoveCallOnRemove("StencilCore")
			self:NetQueueStencil(stencil, 2)
			self:StencilCountEntity(stencil, entity_layer, -1)
		end
		
		return
	end
	
	for layer_index, entity_layer in pairs(entity_layers) do if entity_layer[entity] then duplex_remove(entity_layer, entity) end end
end

--hooks
hook.Add("PlayerDisconnected", "StencilCore", function(ply) STENCIL_CORE.StencilCounter[ply] = nil end)
hook.Add("PlayerInitialSpawn", "StencilCore", function(ply) STENCIL_CORE.StencilCounter[ply] = 0 end)

--post
STENCIL_CORE:ConVarListen("entities", "Core", function(convar) maximum_entities = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("layer_entities", "Core", function(convar) maximum_layer_entities = convar:GetInt() end, true)
STENCIL_CORE:ConVarListen("maximum_stencils", "Core", function(convar) maximum_stencils = convar:GetInt() end, true)