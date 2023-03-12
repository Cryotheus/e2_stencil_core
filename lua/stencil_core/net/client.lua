include("includes/entity_proxy.lua")

--locals
local duplex_insert = STENCIL_CORE._DuplexInsert
local duplex_remove = STENCIL_CORE._DuplexRemove

--local functions
local function bits(decimal) return math.ceil(math.log(decimal, 2)) end
--local function stencil_equal(first, second) return first == second or (first.ChipIndex == second.ChipIndex and first.Index == second.Index) end

--post function setup
local bits_hooks = bits(#STENCIL_CORE.Hooks)
local bits_layer_entities
local bits_layers
local bits_maximum_stencil_index
local bits_prefabs = bits(#STENCIL_CORE.Prefabs)

--stencil core functions
function STENCIL_CORE:NetReadStencilIdentifier()
	local chip_proxy = entity_proxy.Read("StencilCore")
	local chip_stencils = self.Stencils[chip_proxy]
	local stencil_index = net.ReadUInt(bits_maximum_stencil_index)
	
	return chip_proxy, stencil_index, chip_stencils and chip_stencils[stencil_index]
end

function STENCIL_CORE:NetReadStencils()
	while net.ReadBool() do
		local chip_proxy, stencil_index, stencil = self:NetReadStencilIdentifier()
		
		if net.ReadBool() then --true: remove stencil
			self:StencilDelete(chip_proxy, stencil_index)
			
			if stencil then
				for layer_index, entity_layer in pairs(stencil.EntityLayers) do
					for index, proxy in ipairs(entity_layer) do
						proxy:DecrementEntityProxyReferenceCount()
						self:RestoreEntityRender(proxy)
					end
				end
			end
		else --false: update/create stencil
			if net.ReadBool() then --true: we have stencil data to read
				if not stencil then stencil = self:StencilCreate(chip_proxy, stencil_index) end
				
				stencil.Owner = net.ReadEntity() --reliable enough that we don't need a proxy
				stencil.Hook = self.Hooks[net.ReadUInt(bits_hooks) + 1]
				
				if net.ReadBool() then --prefab!
					local prefab_index = net.ReadUInt(bits_prefabs) + 1
					local prefab = self.Prefabs[prefab_index]
					
					stencil.Instructions = table.Copy(prefab[3])
					stencil.ParameterizedIndices = table.Copy(prefab[2])
					stencil.Prefab = prefab_index
					stencil.Visible = true
					
					self:CompileStencil(stencil)
				else error("Non-prefab stencils are not yet supported!") end
			end
			
			local entity_layers = stencil.EntityLayers
			
			if net.ReadBool() then
				while net.ReadBool() do
					local layer_index = net.ReadUInt(bits_layers) + 1
					local entity_layer = entity_layers[layer_index]
					
					if not entity_layer then
						entity_layer = {}
						entity_layers[layer_index] = entity_layer
					end
					
					--entities added
					for index = 1, net.ReadUInt(bits_layer_entities) do
						local proxy = entity_proxy.Read("StencilCore")
						
						duplex_insert(entity_layer, proxy)
						proxy:IncrementEntityProxyReferenceCount()
						self:OverrideEntityRender(proxy)
					end
					
					--entities removed
					for index = 1, net.ReadUInt(bits_layer_entities) do
						local proxy = entity_proxy.Read("StencilCore")
						
						duplex_remove(entity_layer, proxy)
						proxy:DecrementEntityProxyReferenceCount()
						self:RestoreEntityRender(proxy)
					end
				end
			else
				local removed_proxies = {}
				
				--remove all the proxies and record them
				for layer_index, entity_layer in pairs(entity_layers) do
					for index, proxy in ipairs(entity_layer) do
						entity_layer[index] = nil
						entity_layer[proxy] = nil
						removed_proxies[proxy] = true
					end
				end
				
				--insert proxies and undo the removal marking
				while net.ReadBool() do
					local layer_index = net.ReadUInt(bits_layers) + 1
					local entity_layer = entity_layers[layer_index]
					
					if not entity_layer then
						entity_layer = {}
						entity_layers[layer_index] = entity_layer
					end
					
					for index = 1, net.ReadUInt(bits_layer_entities) do
						local proxy = entity_proxy.Read("StencilCore")
						
						if removed_proxies[proxy] then removed_proxies[proxy] = nil
						else
							proxy:IncrementEntityProxyReferenceCount()
							self:OverrideEntityRender(proxy)
						end
						
						duplex_insert(entity_layer, proxy)
					end
				end
				
				--garbage collect the proxies
				for proxy in pairs(removed_proxies) do
					proxy:DecrementEntityProxyReferenceCount()
					self:RestoreEntityRender(proxy)
				end
			end
		end
	end
	
	self:QueueHookUpdate()
end

--net
net.Receive("StencilCore", function() STENCIL_CORE:NetReadStencils() end)

--post
STENCIL_CORE:ConVarListen("layer_entities", "Net", function(convar) bits_layer_entities = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("layers", "Net", function(convar) bits_layers = bits(convar:GetInt()) end, true)
STENCIL_CORE:ConVarListen("maximum_stencil_index", "Net", function(convar) bits_maximum_stencil_index = bits(convar:GetInt() + 1) end, true)