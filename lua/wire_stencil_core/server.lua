resource.AddSingleFile("resource/localization/en/wire_stencil_core.properties")
util.AddNetworkString("wire_stencil_core_entity")
util.AddNetworkString("wire_stencil_core_init")
util.AddNetworkString("wire_stencil_core_remove")
util.AddNetworkString("wire_stencil_core_sync")

--locals
local loading_cheaters = {}
local loading_players = {}
local load_time = 30
local sv_allowcslua = GetConVar("sv_allowcslua")

--local functions

--commands
concommand.Add("stencil_init", function(ply)
	if IsValid(ply) then hook.Call("WireStencilCoreInitialSync", WIRE_STENCIL_CORE, ply)
	else hook.Call("WireStencilCoreInitialSync", WIRE_STENCIL_CORE) end
end, nil, "Force the initial sync to transpire.")

--hooks
hook.Add("PlayerDisconnected", "wire_stencil_core", function(ply)
	loading_cheaters[ply] = nil
	loading_players[ply] = nil
end)

hook.Add("PlayerInitialSpawn", "wire_stencil_core", function(ply) loading_players[ply] = ply:TimeConnected() end)

hook.Add("Tick", "wire_stencil_core", function()
	for ply, time_spawned in pairs(loading_players) do
		if time_spawned and ply:TimeConnected() - time_spawned > load_time then
			MsgC(color_red, "A player (" .. tostring(ply) .. ") has exceeded " .. load_time .. " (took " .. ply:TimeConnected() - time_spawned .. ") seconds of spawn time and has yet to send the proper net message. Emulating a response.\n")
			
			loading_players[ply] = false
			
			hook.Call("WireStencilCoreInitialSync", WIRE_STENCIL_CORE, ply, true)
		end
	end
end)

--net
net.Receive("wire_stencil_core_init", function(length, ply)
	--sync player
	if loading_players[ply] == nil then
		--if the server allows client side Lua, the obviously they can do this
		if sv_allowcslua:GetBool() then return end
		
		if loading_cheaters[ply] then
			if loading_cheaters[ply] > 100 then
				loading_cheaters[ply] = nil
				
				ply:Kick("Kicked for flooding stencil core initialization net messages.\nThank you for using Stencil Core 2\nSincerely yours, Cryotheum\n<3")
				MsgC(color_red, "\n!!!\nKicking hacker (", ply, ") for attempting to flood stencil core.\n!!!\n\n")
			else loading_cheaters[ply] = loading_cheaters[ply] + 1 end
		else
			loading_cheaters[ply] = 1
			
			MsgC(color_red, "\n!!!\nA player (", ply, ") tried to send a load net message but has yet to be spawned! It is possible that they are hacking (yes hacking, not cheating).\n!!!\n\n")
		end
	else
		if loading_players[ply] == false then MsgC(color_red, "A player (" .. tostring(ply) .. ") had a belated load net message, an emulated one has been made.\n", color_white, "The above message is not an error, but a sign that clients are taking too long to load your server's content.\n") end
		
		loading_players[ply] = nil
		
		hook.Call("WireStencilCoreInitialSync", WIRE_STENCIL_CORE, ply)
	end
end)