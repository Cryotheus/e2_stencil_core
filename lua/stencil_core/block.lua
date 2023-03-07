--locals
local blocked_players = STENCIL_CORE.BlockedPlayers
local player_query

--local functions
local function block_player(ply, save)
	if isentity(ply) then
		blocked_players[ply] = true
		
		ply:CallOnRemove("StencilCoreBlock", function()
			timer.Simple(0, function()
				if ply:IsValid() then return end
				
				blocked_players[ply] = nil
			end)
		end)
		
		STENCIL_CORE:QueueHookUpdate()
	end
	
	if save then player_query(ply, "insert or ignore into `stencil_core_blocks` (`steam_id`) values(%s)") end
end

function player_query(ply, query)
	local steam_id = isentity(ply) and ply:SteamID64() or isstring(ply) and ply
	
	if not steam_id then return end
	
	return sql.Query(string.format(query, sql.SQLStr(steam_id)))
end

local function unblock_player(ply, save)
	if isentity(ply) then
		blocked_players[ply] = nil
		
		ply:RemoveCallOnRemove("StencilCoreBlock")
		STENCIL_CORE:QueueHookUpdate()
	end
	
	if save then player_query(ply, "delete from `stencil_core_blocks` where `steam_id` = %s") end
end

--stencil core functions
function STENCIL_CORE:BlockAdd(ply) block_player(ply, true) end

function STENCIL_CORE:BlockClear()
	for ply in pairs(blocked_players) do unblock_player(ply) end
	
	hook.Call("StencilCoreBlockClear", self)
	sql.Query("drop * from `stencil_core_blocks`")
end

function STENCIL_CORE:BlockLoad()
	sql.Begin()
	
	for index, ply in ipairs(player.GetHumans()) do
		--I hate SQL
		--I was seriously thinking about use flat files for this
		if player_query(ply, "select 1 from `stencil_core_blocks` where `steam_id` = %s") then block_player(ply) end
	end
	
	sql.Commit()
end

function STENCIL_CORE:BlockPromptClear()
	Derma_Query(
		"Clear blocked players database, including the offline players?",
		"Stencil Core - Confirmation",
		"Yes", function() STENCIL_CORE:BlockClear() end,
		"No"
	)
end

function STENCIL_CORE:BlockRemove(ply) unblock_player(ply, true) end

function STENCIL_CORE:BlockSave()
	sql.Begin()
	
	--we pass the steam id instead of the ply to prevent redundant function creation
	for ply in pairs(blocked_players) do block_player(ply:SteamID64(), true) end
	
	sql.Commit()
end

--hooks
hook.Add("InitPostEntity", "StencilCoreBlock", function() STENCIL_CORE:BlockLoad() end)

--post
sql.Query("create table if not exists `stencil_core_blocks` (`steam_id` unsigned big int not null, primary key (`steam_id`))")