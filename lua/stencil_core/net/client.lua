include("includes/entity_proxy.lua")

--locals
local bits_layer_entities, bits_layers, bits_maximum_stencil_index
local color_dark_red = Color(192, 0, 0)
local color_red = Color(224, 0, 0)
--local duplex_set = STENCIL_CORE._DuplexSet
--local duplex_unset = STENCIL_CORE._DuplexUnset
local entity_creation_time = 2 --how long do we watch for entity creation? (in seconds)
local entity_watch = STENCIL_CORE.NetEntityWatch

--local tables
local net_methods = {"NetReadStencils", "NetReadStencilsEntities"}

--local functions
local function bits(decimal) return math.ceil(math.log(decimal, 2)) end

local function create_watched_entity(entity_index, remove_timer)
	local data = entity_watch[entity_index]
	local entity = Entity(entity_index)
	local proxy = data[1]
	entity_watch[entity_index] = nil
	
	--call the callbacks
	for index, callback in ipairs(data[2]) do callback(proxy, entity) end
	
	if remove_timer then timer.Remove("StencilCoreNetEntity" .. entity_index) end
	if next(entity_watch) then return entity end
	
	hook.Remove("OnEntityCreated", "StencilCoreNet")
	
	return entity
end

local function entity_watch_hook(entity)
	--we don't need to check validity because there is no possible way for map entities to be created after this hook is added
	local entity_index = entity:EntIndex()
	
	if entity_watch[entity_index] then STENCIL_CORE:NetWatchEntityCreated(entity_index) end
end

local function read_entity(callback)
	local entity_index = net.ReadUInt(13)
	local entity = Entity(entity_index)
	
	if entity:IsValid() then return entity, entity_index end
	
	return STENCIL_CORE:NetWatchEntityCreation(entity_index, callback), entity_index
end

local function replace_entity_proxy(stencil, proxy, entity)
	if stencil.Removed then return end
	
	local entity_layers = stencil.EntityLayers
	
	for layer_index, entity_layer in pairs(entity_layers) do
		local index = entity_layer[proxy]
		
		if index then
			--duplex_set(entity_layer, index, entity)
			entity_layer[entity] = index
			entity_layer[index] = entity
			entity_layer[proxy] = nil
		end
	end
end

--post function setup
local bits_prefabs = bits(#STENCIL_CORE.Prefabs)

--globals
STENCIL_CORE.NetHookBits = bits(#STENCIL_CORE.Hooks)

--stencil core functions
function STENCIL_CORE:NetReadParameters() return {} end --TODO: implement me!

function STENCIL_CORE:NetReadStencilIdentifier()
	local stencils = self.Stencils
	local index = net.ReadUInt(bits_maximum_stencil_index)
	local chip, chip_index = read_entity(
		function(proxy, entity)
			local chip_stencils = stencils[proxy]
			
			if not chip_stencils then return end
			
			stencils[entity] = chip_stencils
			stencils[proxy] = nil
			
			--change the chip proxy into a real entity
			for index, stencil in pairs(chip_stencils) do stencil.Chip = entity end
		end)
	local chip_stencils = self.Stencils[chip]
	
	return chip_stencils and chip_stencils[index], chip, index, chip_index
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
		
		error("unimplemented") --TODO: implement me!
	end
end

function STENCIL_CORE:NetReadStencils()
	local deletions = false
	
	repeat
		--get some useful information
		local stencil, chip, index, chip_index = self:NetReadStencilIdentifier()
		
		if net.ReadBool() then --true if we are deleting the stencil
			self:StencilDelete(chip, index, chip_index)
			self:NetUnwatchEntityCreation(chip_index)
			--if not IsEntity(chip) or chip:IsValid() then self:StencilDelete(chip, index, chip_index)
			--else deletions = true end
		else --otherwise create the stencil if it doesn't exist and update it
			if not stencil then stencil = self:StencilCreate(chip, index, chip_index) end
			
			self:NetReadStencilData(stencil)
		end
	until not net.ReadBool() --repeat until there's no more stencils to read
	
	self:QueueHookUpdate()
	
	--[[
	if deletions then --HACK: native entity networking is trash, does anyone have a solution?
		local stencils = self.Stencils
		
		for chip, chip_stencils in pairs(stencils) do
			if IsEntity(chip) and not chip:IsValid() then
				stencils[chip] = nil
				
				--for anything still holding a reference to the stencil
				for index, stencil in pairs(chip_stencils) do stencil.Removed = true end
			end
		end
	end]]
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
			
			--easy scoping to give replace_entity_proxy access to the stencil
			local function replace_proxy(proxy, entity)
				replace_entity_proxy(stencil, proxy, entity)
				self:OverrideEntityRender(entity)
			end
			
			--create missing entity layers
			if not entity_layer then
				entity_layer = {}
				entity_layers[layer_index] = entity_layer
			end
			
			--add the entities and ensure they have the render override
			for index = 1, entity_count do
				local entity = read_entity(replace_proxy)
				duplicated[entity] = true
				
				--duplex_set(entity_layer, index, entity)
				entity_layer[entity] = index
				entity_layer[index] = entity
				
				self:OverrideEntityRender(entity)
			end
			
			--remove the entities that are no longer part of the stencil, and the empty entity layers
			for index = entity_count + 1, #entity_layer do
				entity = entity_layer[index]
				
				--duplex_unset(entity_layer, index)
				entity_layer[entity] = nil
				entity_layer[index] = nil
				
				if not duplicated[entity] then self:RestoreEntityRender(entity) end
				if not entity_layer[1] then entity_layers[layer_index] = nil end
			end
		end
	until not net.ReadBool() --repeat until there's no more stencils to update
	
	self:QueueHookUpdate()
end

function STENCIL_CORE:NetWatchEntityCreated(entity_index) create_watched_entity(entity_index, true) end

function STENCIL_CORE:NetWatchEntityCreation(entity_index, callback)
	--HACK: native entity networking is trash, does anyone have a solution?
	--data
	--	proxy
	--	callbacks
	--	expire function
	local data = entity_watch[entity_index]
	local expire_function, proxy
	
	--start the hook if it hasn't been started yet
	if not next(entity_watch) then hook.Add("OnEntityCreated", "StencilCoreNet", entity_watch_hook) end
	
	--attempt to maintain the proxy
	if data then
		expire_function = data[3]
		proxy = data[1]
		
		table.insert(data[2], callback)
	else
		function expire_function()
			if create_watched_entity(entity_index):IsValid() then return end
			
			MsgC(color_dark_red, "[Stencil Core]: ", color_red, "Entity creation timed out for entity #" .. entity_index .. "!\n")
		end
		
		proxy = newproxy()
		entity_watch[entity_index] = {proxy, {callback}, expire_function}
	end
	
	timer.Create("StencilCoreNetEntity" .. entity_index, entity_creation_time, 1, expire_function)
	
	return proxy
end

function STENCIL_CORE:NetUnwatchEntityCreation(entity_index)
	--we check before removing the hook because some hook modules may error when we remove a non-existent hook
	local hook_table = hook.GetTable().OnEntityCreated
	entity_watch[entity_index] = nil
	
	timer.Remove("StencilCoreNetEntity" .. entity_index)
	
	if next(entity_watch) then return end
	if hook_table and hook_table.StencilCoreNet then hook.Remove("OnEntityCreated", "StencilCoreNet") end
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