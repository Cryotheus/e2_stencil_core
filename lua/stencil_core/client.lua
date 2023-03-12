--locals
local blocked_players = STENCIL_CORE.BlockedPlayers
local stencils = STENCIL_CORE.Stencils

--local functions
local function render_override(entity, flags)
	if StencilCoreTypicalRender then return end
	
	entity:DrawModel(flags)
end

--globals
StencilCoreTypicalRender = true

--stencil core functions
function STENCIL_CORE:OverrideEntityRender(proxy)
	if proxy.RenderOverride == render_override then return end
	
	local old_render_override = proxy.RenderOverrideX_StencilCore or proxy.RenderOverride
	proxy.RenderOverride = render_override
	proxy.RenderOverrideX_StencilCore = old_render_override
end

function STENCIL_CORE:QueueHookUpdate()
	if self.HookUpdateQueued then return end
	
	self.HookUpdateQueued = true
	
	hook.Add("Think", "PreRender", function()
		self.HookUpdateQueued = nil
		
		hook.Remove("Think", "PreRender")
		self:UpdateHooks()
	end)
end

function STENCIL_CORE:RestoreEntityRender(proxy)
	if proxy.RenderOverride == render_override then
		--friend asked about this line when I was streaming in a discord call
		--so in case you don't know, the following is equivalent to:
		--proxy.RenderOverride = proxy.RenderOverrideX_StencilCore
		--proxy.RenderOverrideX_StencilCore = nil
		--but done in a single line
		proxy.RenderOverride, proxy.RenderOverrideX_StencilCore = proxy.RenderOverrideX_StencilCore
	end
end

function STENCIL_CORE:StencilCreate(chip_proxy, stencil_index)
	local chip_stencils = stencils[chip_proxy]
	local stencil = {
		Chip = chip_proxy,
		ChipIndex = chip_proxy:EntIndex(), --null entity safety
		EntityLayers = {},
		Hook = nil, --size hint
		Index = stencil_index,
		Owner = NULL, --size hint
		Parameters = {},
		Prefab = nil, --size hint
		Visible = false,
	}
	
	if not chip_stencils then
		chip_stencils = {[stencil_index] = stencil}
		stencils[chip_proxy] = chip_stencils
		
		--[[function chip_proxy:OnProxiedEntityRemove()
			if stencils[self] then STENCIL_CORE:StencilDelete(self) end
			
			return true
		end]]
	else chip_stencils[stencil_index] = stencil end
	
	return stencil
end

function STENCIL_CORE:StencilDelete(chip_proxy, stencil_index)
	local chip_stencils = stencils[chip_proxy]
	
	if not chip_stencils then return end
	
	self:StencilDeleteInternal(chip_proxy, chip_stencils, stencil_index)
	--if stencil_index then self:StencilDeleteInternal(chip_proxy, chip_stencils, stencil_index)
	--else for stencil_index in pairs(chip_stencils) do self:StencilDeleteInternal(chip_proxy, chip_stencils, stencil_index) end end
end

function STENCIL_CORE:StencilDeleteInternal(chip_proxy, chip_stencils, stencil_index)
	local stencil = chip_stencils[stencil_index]
	chip_stencils[stencil_index] = nil
	stencil.Removed = true --for anything still holding a reference to the stencil
	
	--remove empty tables
	if not next(chip_stencils) then
		stencils[chip_proxy] = nil
		
		--unregister the EntityProxy of the chip (do this, or get memory leaks!)
		chip_proxy:Destroy()
	end
end

function STENCIL_CORE:UpdateHooks()
	--POST: optimize me!
	local hook_functions = self.HookFunctions
	local hook_table = hook.GetTable()
	
	--empty the existing tables, maintaining the table references
	for hook_name, render_functions in pairs(hook_functions) do table.Empty(render_functions) end
	
	--build the render function list
	for chip, chip_stencils in pairs(stencils) do
		for index, stencil in pairs(chip_stencils) do
			if blocked_players[stencil.Owner] then --I would put continue here but it's broken, so I'm using `if then <empty> elseif <code> end` instead
			elseif stencil.Visible then
				local render_function = stencil.RenderFunction
				
				if render_function then table.insert(hook_functions[stencil.Hook], render_function) end
			end
		end
	end
	
	--create or remove the hooks
	--we check before removing because some hook modules may error when we remove a non-existent hook
	for hook_name, render_functions in pairs(hook_functions) do
		if render_functions[1] then
			hook.Add(hook_name, "StencilCoreRender", function()
				StencilCoreTypicalRender = false
				
				for index, render_function in ipairs(render_functions) do
					--we could also bake this...
					render_function()
				end
				
				StencilCoreTypicalRender = true
			end)
		elseif hook_table[hook_name] and hook_table[hook_name].StencilCoreRender then hook.Remove(hook_name, "StencilCoreRender") end
	end
end