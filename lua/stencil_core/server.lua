--locals
local duplex_insert = STENCIL_CORE._DuplexInsert
local duplex_remove = STENCIL_CORE._DuplexRemove

--stencil core functions
function STENCIL_CORE:StencilAddEntity(chip_context, entity, stencil, layer_index)
	local entity_layers = stencil.EntityLayers
	local entity_layer = entity_layers[layer_index]
	
	entity:CallOnRemove("StencilCore", function(entity) STENCIL_CORE:StencilRemoveEntity(chip_context, entity, stencil) end)
	STENCIL_CORE:NetQueueStencil(stencil, 2)
	
	if not entity_layer then
		entity_layers[layer_index] = {entity, [entity] = 1}
		
		return
	end
	
	duplex_insert(entity_layer, entity)
end

function STENCIL_CORE:StencilCreate(chip_context, index, nil_instructions)
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
		Owner = chip_context.player,
		Parameters = {},
		Prefab = nil,
	}
	
	chip_stencils[index] = stencil
	
	return stencil
end

function STENCIL_CORE:StencilCreatePrefabricated(chip_context, index, prefab_index)
	local prefab = self.Prefabs[prefab_index]
	
	--prevent invalid prefabs
	if not prefab then return end
	
	local stencil = self:StencilCreate(chip_context, index, true)
	
	--we can fail at creating a stencil if one already exists for the chip
	if not stencil then return end
	
	--stencil.Instructions = table.Copy(prefab[2]) --no need to send instructions, the client already has them
	stencil.Prefab = prefab_index
	
	return stencil
end

function STENCIL_CORE:StencilDelete(chip, index)
	if self.Stencils[chip][index] then
		self.Stencils[chip][index] = nil
		
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

function STENCIL_CORE:StencilPurge(chip) --POST: we can optimize this
	local stencils = self.Stencils[chip]
	
	for index, stencil in pairs(stencils) do
		stencils[index] = nil
		
		self:NetQueueStencil(stencil, 1, true)
	end
end

function STENCIL_CORE:StencilRemoveEntity(self, entity, stencil, layer_index)
	local entity_layers = stencil.EntityLayers
	
	if layer_index then
		local entity_layer = entity_layers[layer_index]
		
		duplex_remove(entity_layer, entity)
		entity:RemoveCallOnRemove("StencilCore")
		self:NetQueueStencil(stencil, 2)
		
		return
	end
	
	for layer_index, entity_layer in pairs(entity_layers) do if entity_layer[entity] then duplex_remove(entity_layer, entity) end end
end