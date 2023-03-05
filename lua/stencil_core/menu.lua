--locals
local blocked_players = STENCIL_CORE.BlockedPlayers

--stencil core functions
function STENCIL_CORE:MenuInit(form)
	local online_players_sizer
	
	form:Button("Refresh List").DoClick = function(self) online_players_sizer:Refresh() end
	form:Button("Clear All Blocks").DoClick = function(self) STENCIL_CORE:BlockPromptClear() end
	
	do --blocks category
		local category = vgui.Create("DCollapsibleCategory", form)
		
		form:AddItem(category)
		category:SetLabel("Block Players")
		
		do --online players
			online_players_sizer = vgui.Create("DSizeToContents", category)
			
			function online_players_sizer:PerformLayout(width, height) self:SizeToChildren(false, true) end
			
			function online_players_sizer:Refresh()
				local local_player = LocalPlayer()
				
				self:Clear()
				
				for index, ply in ipairs(player.GetHumans()) do
					if ply ~= local_player then
						local check_box = vgui.Create("DCheckBoxLabel", self)
						
						check_box:SetChecked(blocked_players)
						check_box:SetText(ply:GetName() .. " (" .. ply:SteamID() .. ")")
						
						function check_box:OnChange(value)
							if value then STENCIL_CORE:BlockAdd(ply)
							else STENCIL_CORE:BlockRemove(ply) end
						end
					end
				end
			end
		end
	end
end

--hooks
hook.Add("PopulateToolMenu", "StencilCore", function()
	spawnmenu.AddToolMenuOption("Utilities", "User", "StencilCoreBlock", "[E2] Stencil Core", "", "", function(form)
		form:ClearControls()
		STENCIL_CORE:MenuInit(form)
	end)
end)