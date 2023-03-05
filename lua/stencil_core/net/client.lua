--locals
local bits_layer_entities
local bits_layers
local bits_maximum_stencil_index

--local tables
local net_methods = {"NetReadStencils", "NetReadStencilsEntities"}

--local functions
local function bits(decimal) return math.ceil(math.log(decimal, 2)) end

--post function setup
local bits_prefabs = bits(#STENCIL_CORE.Prefabs)

--globals
STENCIL_CORE.NetHookBits = bits(#STENCIL_CORE.Hooks)

--stencil core functions
function STENCIL_CORE:NetReadParameters() return {} end --TODO: implement me!

function STENCIL_CORE:NetReadStencilIdentifier()
	local index = net.ReadUInt(bits_maximum_stencil_index)
	local chip = net.ReadEntity()
	local chip_stencils = self.Stencils[chip]
	
	return chip_stencils and chip_stencils[index], chip, index
end

function STENCIL_CORE:NetReadStencilData(stencil)
	stencil.Owner = net.ReadEntity()
	stencil.Parameters = self:NetReadParameters()
	stencil.Hook = self.Hooks[net.ReadUInt(self.NetHookBits) + 1]
	
	if net.ReadBool() then
		local prefab_index = net.ReadUInt(bits_prefabs) + 1
		
		if stencil.Compiled then return end
		
		local prefab = self.Prefabs[prefab_index]
		
		stencil.ParameterizedIndices = table.Copy(prefab[2])
		stencil.Prefab = prefab_index
		stencil.Instructions = table.Copy(prefab[3])
		
		self:CompileStencil(stencil)
	else
		stencil.Prefab = nil
		
		error("unimplemented") --TODO: implement me!
	end
end

function STENCIL_CORE:NetReadStencils()
	local deletions = false
	
	repeat
		local stencil, chip, index = self:NetReadStencilIdentifier()
		
		if net.ReadBool() then deletions = true --self:StencilDelete(chip, index)
		else
			if not stencil then stencil = self:StencilCreate(chip, index) end
			
			self:NetReadStencilData(stencil)
		end
	until not net.ReadBool()
	
	if deletions then --can't we id entities properly gmod?
		--(this is a hack to "fix" idiotic entity networking)
		local stencils = self.Stencils
		
		for chip, chip_stencils in pairs(stencils) do if not chip:IsValid() then stencils[chip] = nil end end
	end
end

function STENCIL_CORE:NetReadStencilsEntities()
	print("NetReadStencilsEntities")
	
	repeat
		local stencil, chip, index = self:NetReadStencilIdentifier()
		local entity_layers = stencil.EntityLayers
		
		print(stencil, chip, index)
		
		for index = 1, net.ReadUInt(bits_layers) do
			local layer_index = net.ReadUInt(bits_layers) + 1
			local duplicated = {}
			local entity_count = net.ReadUInt(bits_layer_entities)
			local entity_layer = entity_layers[layer_index]
			
			print(index, entity_count)
			
			if not entity_layer then
				entity_layer = {}
				entity_layers[layer_index] = entity_layer
			end
			
			--add the entities and ensure they have the render override
			for index = 1, entity_count do
				local entity = net.ReadEntity()
				duplicated[entity] = true
				entity_layer[index] = entity
				
				self:OverrideEntityRender(entity)
			end
			
			--remove the entities that are no longer part of the stencil
			for index = entity_count + 1, #entity_layer do
				entity = entity_layer[index]
				entity_layer[index] = nil
				
				if not duplicated[entity] then self:RestoreEntityRender(entity) end
			end
		end
	until not net.ReadBool()
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