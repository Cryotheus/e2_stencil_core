--locals
local blocked_players = STENCIL_CORE.BlockedPlayers

--stencil core functions
function STENCIL_CORE:MenuInit(form)
	
	
	do --blocked players list
		local category = vgui.Create("DCollapsibleCategory", form)
		
		category:SetLabel("Block Players")
		form:AddItem(category)
		
		do --clear button
			local button = vgui.Create("DButton", category)
			
			button:Dock(TOP)
			button:DockMargin(0, 5, 0, 0)
			button:SetText("Clear All Blocks")
			
			function button:DoClick() STENCIL_CORE:BlockPromptClear() end
		end
		
		do --refresh button
			local button = vgui.Create("DButton", category)
			
			button:Dock(TOP)
			button:DockMargin(0, 5, 0, 3)
			button:SetText("Refresh List")
			
			function button:DoClick() category:RefreshPlayers() end
		end
		
		function category:RefreshPlayers()
			local children = self:GetChildren()
			local local_player = LocalPlayer()
			
			--iterate backwards to remove children without skipping panels
			for index = #children, 1, -1 do
				local panel = children[index]
				
				if panel:GetName() == "DCheckBoxLabel" then panel:Remove() end
			end
			
			for index, ply in ipairs(player.GetHumans()) do
				local check_box = vgui.Create("DCheckBoxLabel", self)
				local steam_id64 = ply:SteamID64()
				
				check_box:Dock(TOP)
				check_box:DockMargin(0, 2, 0, 0)
				check_box:SetChecked(blocked_players[ply])
				check_box:SetDark(true)
				check_box:SetText(ply:GetName() .. " (" .. ply:SteamID() .. ")")
				
				function check_box:OnChange(value)
					if value then STENCIL_CORE:BlockAdd(ply:IsValid() and ply or steam_id64)
					else STENCIL_CORE:BlockRemove(ply:IsValid() and ply or steam_id64) end
				end
			end
		end
		
		category:RefreshPlayers()
		hook.Add("StencilCoreBlockClear", category, category.RefreshPlayers)
	end
end

--hooks
hook.Add("PopulateToolMenu", "StencilCore", function()
	spawnmenu.AddToolMenuOption("Utilities", "User", "StencilCoreBlock", "[E2] Stencil Core", "", "", function(form)
		form:ClearControls()
		STENCIL_CORE:MenuInit(form)
	end)
end)