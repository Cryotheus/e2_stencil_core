local local_player = LocalPlayer() --for reload, it won't actually return a valid player until InitPostEntity runs

hook.Add("InitPostEntity", "e2_stencil_core", function()
	local_player = LocalPlayer()
	
	net.Start("e2_stencil_core_init")
	net.SendToServer()
end)