include("includes/entity_proxy.lua")

--locals
local bits_layer_entities, bits_layers, bits_maximum_stencil_index
--local duplex_set = STENCIL_CORE._DuplexSet
--local duplex_unset = STENCIL_CORE._DuplexUnset

--local tables
local net_methods = {"NetReadStencils", "NetReadStencilsEntities"}

--local functions
local function bits(decimal) return math.ceil(math.log(decimal, 2)) end

--post function setup
local bits_prefabs = bits(#STENCIL_CORE.Prefabs)

--globals
STENCIL_CORE.NetHookBits = bits(#STENCIL_CORE.Hooks)

--stencil core functions
function STENCIL_CORE:NetReadParameters() return {} end --POST: implement me!

function STENCIL_CORE:NetReadStencilIdentifier()
	local index = net.ReadUInt(bits_maximum_stencil_index)
	local chip = entity_proxy.Read()
	local chip_stencils = self.Stencils[chip]
	
	return chip_stencils and chip_stencils[index], chip, index, chip:EntIndex()
end

function STENCIL_CORE:NetReadStencilData(stencil)
	stencil.Owner = net.ReadEntity() --players are reliable enough, so we can use the native function instead of our own
	stencil.Parameters = self:NetReadParameters()
	stencil.Hook = self.Hooks[net.ReadUInt(self.NetHookBits) + 1]
	
	if net.ReadBool() then
		local prefab_index = net.ReadUInt(bits_prefabs) + 1
		
		if stencil.Compiled then return end
		
		local prefab = self.Prefabs[prefab_index]
		
		stencil.ParameterizedIndices = table.Copy(prefab[2])
		stencil.Prefab = prefab_index
		stencil.Instructions = table.Copy(prefab[3])
		stencil.Visible = true
		
		self:CompileStencil(stencil)
	else
		stencil.Prefab = nil
		
		error("unimplemented") --POST: implement me!
	end
end

function STENCIL_CORE:NetReadStencils()
	repeat
		--get some useful information
		local stencil, chip, index, chip_index = self:NetReadStencilIdentifier()
		
		if net.ReadBool() then --true if we are deleting the stencil
			self:StencilDelete(chip, index, chip_index)
			--if not isentity(chip) or chip:IsValid() then self:StencilDelete(chip, index, chip_index)
			--else deletions = true end
		else --otherwise create the stencil if it doesn't exist and update it
			if not stencil then stencil = self:StencilCreate(chip, index, chip_index) end
			
			self:NetReadStencilData(stencil)
		end
	until not net.ReadBool() --repeat until there's no more stencils to read
	
	self:QueueHookUpdate()
end

function STENCIL_CORE:NetReadStencilsEntities()
	repeat
		--get some useful information
		local stencil, chip, index, chip_index = self:NetReadStencilIdentifier()
		
		--dag nabbit
		if not stencil then stencil = self:StencilCreate(chip, index, chip_index) end
		
		local entity_layers = stencil.EntityLayers
		
		for index = 1, net.ReadUInt(bits_layers) do
			local layer_index = net.ReadUInt(bits_layers) + 1
			local duplicated = {}
			local entity_count = net.ReadUInt(bits_layer_entities)
			local entity_layer = entity_layers[layer_index]
			
			--create missing entity layers
			if not entity_layer then
				entity_layer = {}
				entity_layers[layer_index] = entity_layer
			end
			
			--add the entities and ensure they have the render override
			for index = 1, entity_count do
				local entity = entity_proxy.Read()
				duplicated[entity] = true
				entity_layer[entity] = index --duplex_set(entity_layer, index, entity)
				entity_layer[index] = entity
				
				self:OverrideEntityRender(entity)
			end
			
			--remove the entities that are no longer part of the stencil, and the empty entity layers
			for index = entity_count + 1, #entity_layer do
				entity = entity_layer[index]
				entity_layer[entity] = nil --duplex_unset(entity_layer, index)
				entity_layer[index] = nil
				
				if not duplicated[entity] then self:RestoreEntityRender(entity) end
				if not entity_layer[1] then entity_layers[layer_index] = nil end
			end
		end
	until not net.ReadBool() --repeat until there's no more stencils to update
	
	self:QueueHookUpdate()
end

--hooks
hook.Add("InitPostEntity", "StencilCoreNet", function()
	net.Start("stencil_core")
	net.SendToServer()
end)

--net
net.Receive("stencil_core", function() STENCIL_CORE[net_methods[net.ReadUInt(1) + 1]](STENCIL_CORE) end)

--post
STENCIL_CORE:ConVarListen("layer_entities", "Net", function(convar) bits_layer_entities = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("layers", "Net", function(convar) bits_layers = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("maximum_stencil_index", "Net", function(convar) bits_maximum_stencil_index = bits(convar:GetInt() + 1) end, true)