--locals
local blocked_players = STENCIL_CORE.BlockedPlayers

--local functions
local function render_override(self, flags)
	if StencilCoreTypicalRender then return end
	
	self:DrawModel(flags)
end

--globals
StencilCoreTypicalRender = true

--stencil core functions
function STENCIL_CORE:OverrideEntityRender(entity)
	if entity.RenderOverride == render_override then return end
	
	local old_render_override = entity.RenderOverrideX_StencilCore or entity.RenderOverride
	entity.RenderOverride = render_override
	entity.RenderOverrideX_StencilCore = old_render_override
end

function STENCIL_CORE:RestoreEntityRender(entity)
	if entity.RenderOverride == render_override then
		entity.RenderOverride = entity.RenderOverrideX_StencilCore
		entity.RenderOverrideX_StencilCore = nil
	end
end

function STENCIL_CORE:QueueHookUpdate()
	if self.HookUpdateQueued then return end
	
	self.HookUpdateQueued = true
	
	hook.Add("Think", "StencilCoreHookUpdate", function()
		self.HookUpdateQueued = nil
		
		hook.Remove("Think", "StencilCoreHookUpdate")
		self:UpdateHooks()
	end)
end

function STENCIL_CORE:StencilCreate(chip, index)
	local chip_stencils = self.Stencils[chip]
	local stencil = {
		Chip = chip,
		EntityLayers = {},
		Index = index,
		Owner = nil, --size hint
		Parameters = {},
		Prefab = nil, --size hint
		Visible = true,
	}
	
	if not chip_stencils then self.Stencils[chip] = {[index] = stencil}
	else chip_stencils[index] = stencil end
	
	return stencil
end

function STENCIL_CORE:StencilDelete(chip, index)
	local chip_stencils = self.Stencils[chip]
	
	if chip_stencils then
		chip_stencils[index] = nil
		
		if not next(chip_stencils) then self.Stencils[chip] = nil end
	end
end

function STENCIL_CORE:UpdateHooks()
	--POST: optimize me!
	local hook_functions = self.HookFunctions
	local hook_table = hook.GetTable()
	
	--empty the existing tables, maintaining the table references
	for hook_name, render_functions in pairs(hook_functions) do table.Empty(render_functions) end
	
	--build the render function list
	for chip, chip_stencils in pairs(self.Stencils) do
		for index, stencil in pairs(chip_stencils) do
			if blocked_players[stencil.Owner] then --I would put continue here but it's broken, so I'm using `if then <empty> elseif <code> end` instead
			elseif stencil.Visible then
				local render_function = stencil.RenderFunction
				
				if render_function then table.insert(hook_functions[hook_name], render_function) end
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
		elseif hook_table[hook_name].StencilCoreRender then hook.Remove(hook_name, "StencilCoreRender") end
	end
end