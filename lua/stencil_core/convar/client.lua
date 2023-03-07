--stencil core functions
function STENCIL_CORE:ConVarListen(name, identifier, callback, callback_now)
	local convar = self.ConVars[name]
	local listeners = self.ConVarListeners[name]
	listeners[identifier] = callback
	
	cvars.AddChangeCallback(convar:GetName(), function()
		if player.GetHumans()[1] then return message("Due to networking safety, this convar may only be changed when no clients are connected.") end
		
		for identifier, callback in pairs(listeners) do callback(convar) end
	end, "StencilCore")
	
	if callback_now then return callback(convar) end
end