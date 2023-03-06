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
function STENCIL_CORE:OverrideEntityRender(entity)
	if entity:IsEntityProxyAlive() then
		if entity.RenderOverride == render_override then return end
		
		local old_render_override = entity.RenderOverrideX_StencilCore or entity.RenderOverride
		entity.RenderOverride = render_override
		entity.RenderOverrideX_StencilCore = old_render_override
	end
end

function STENCIL_CORE:RestoreEntityRender(entity)
	if entity:IsEntityProxyAlive() and entity.RenderOverride == render_override then
		--friend asked about this line when I was streaming in a discord call
		--so in case you don't know, the following is equivalent to:
		--entity.RenderOverride = entity.RenderOverrideX_StencilCore
		--entity.RenderOverrideX_StencilCore = nil
		--but done in a single line
		entity.RenderOverride, entity.RenderOverrideX_StencilCore = entity.RenderOverrideX_StencilCore
	end
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

function STENCIL_CORE:StencilCreate(chip, index, chip_index)
	local chip_index = chip_index or chip:IsEntityProxyAlive() and chip:EntIndex()
	local chip_stencils = stencils[chip]
	local stencil = {
		Chip = chip,
		ChipIndex = chip_index, --null entity safety
		EntityLayers = {},
		Hook = nil, --size hint
		Index = index,
		Owner = NULL, --size hint
		Parameters = {},
		Prefab = nil, --size hint
		Visible = false,
	}
	
	if not chip_stencils then
		stencils[chip] = {[index] = stencil}
		
		chip:CallOnRemove("StencilCore", function()
			timer.Simple(0, function()
				if chip:IsValid() then return end
				
				stencils[chip] = nil
			
				self:NetUnwatchEntityCreation(chip_index)
			end)
		end)
	else chip_stencils[index] = stencil end
	
	return stencil
end

function STENCIL_CORE:StencilDelete(chip, index)
	local chip_stencils = stencils[chip]
	
	if chip_stencils then
		local stencil = chip_stencils[index]
		stencil.Removed = true --for anything still holding a reference to the stencil
		chip_stencils[index] = nil
		
		--remove empty tables
		if not next(chip_stencils) then stencils[chip] = nil end
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