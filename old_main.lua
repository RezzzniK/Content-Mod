#version 2 

#include "script/common.lua"
#include "common.lua"
#include "game.lua"
#include "script/toolutilities.lua"
#include "script/include/player.lua"

pDisableTools = GetBoolParam("disabletools", false)
pBaseTools = GetBoolParam("basetools", false)
gCustomToolsChecked = false

valuableSound = nil
allToolsCheck = nil


function server.init()
	local levelId = GetString("game.levelid")
	shared.enableValuables = not string.find(levelId, "sandbox") and not string.find(levelId, "ch_")

	shared.roundTime = 120
	shared.roundState = "playing"
	shared.roundWinner = ""
	shared.restartTime = 0

	server.ctSpawn = FindLocation("ct_spawn", true)
	server.tSpawn = FindLocation("t_spawn", true)
	server.playerTeams = {}
	server.nextTeam = "ct"

	if server.ctSpawn == 0 then
		DebugPrint("ERROR: Location with tag ct_spawn not found")
	end
	if server.tSpawn == 0 then
		DebugPrint("ERROR: Location with tag t_spawn not found")
	end	
	initValuables()

	--Just to make sure the base tools are always available except for tutorial hub
	SetBool("savegame.tool.sledge.enabled", true, true)
	SetBool("savegame.tool.spraycan.enabled", true, true)
	SetBool("savegame.tool.extinguisher.enabled", true, true)

	--Check if playing campaign level
	local id = GetString("game.levelid")
	local isMod = HasKey("game.mod")
	local campaign = gMissions[id] ~= nil or (string.sub(id, 1, 3) == "hub" and not isMod and not string.find(id, "sandbox"))
	if campaign then
		SetString("game.quicksavename", "quicksavecampaign")
	else
		SetString("game.quicksavename", "quicksave")
	end

	if gMissions[id] then
		SetInt("level.missionsScoreSum", getLevelScore(gMissions[id].level))
	end
	syncActivities(id, true, false)
	---syncModActivities()
	if isMod then
		local modId = GetString("game.mod")
		if modId == "dlc-artvandals" then
			SetPresence("dlc_artvandals")
		else
			SetPresence("mod")
		end
	else
		SetPresence(id)
	end

	server.defaultTools = {}
	if pBaseTools then
		server.defaultTools["sledge"] = { enabled = true }
		server.defaultTools["spraycan"] = { enabled = true }
		server.defaultTools["extinguisher"] = { enabled = true }
	else
		if not pDisableTools then
			local id = GetString("game.levelid")
			local isCampaign = gMissions[id] ~= nil or (string.sub(id, 1, 3) == "hub")

			if isCampaign or not IsMultiplayer() then
				server.defaultTools = setupToolsAmmoScaling(gTools, gMissions, false)
			else
				server.defaultTools = setupToolsUpgradedFully()
			end
		end
	end
end

function server.setDefaultToolsForPlayer(player)
	for toolId,preset in pairs(server.defaultTools) do
		SetToolEnabled(toolId, preset.enabled, player)
		if preset.enabled and preset.ammo then
			SetToolAmmo(toolId, preset.ammo, player)
		end
	end
end

function server.handleCommand(cmd)
	if cmd == "quickload" then
		--After quickload, make sure valuables are consistent with savegame
		initValuables()
	end
end

function initValuables()
	if shared.enableValuables then
		valuables = FindBodies("valuable", true)
		local valueMin = 10000
		local valueMax = 0
		local valueTotal = 0
		for i=1,#valuables do
			local id = GetTagValue(valuables[i], "valuable")
			local v = tonumber(GetTagValue(valuables[i], "value"))
			valueMin = math.min(valueMin, v)
			valueMax = math.max(valueMax, v)
			valueTotal = valueTotal + v
			if GetBool("savegame.valuable."..id) then
				Delete(valuables[i])
			end
		end
		--print(#valuables .. " valuables worth $" .. valueTotal ..  " ($" .. valueMin .. "-$" .. valueMax .. ")")
		valuables = FindBodies("valuable", true)
		for i=1,#valuables do
			SetTag(valuables[i], "interact", "loc@GRAB_VALUABLE")
		end
	else
		local v = FindBodies("valuable", true)
		for i=1,#v do
			RemoveTag(v[i], "valuable")
			RemoveTag(v[i], "value")
		end
	end
end

function server.respawnTeamPlayer(player)
	local team = server.playerTeams[player]
	local spawn = 0

	if team == "ct" then
		spawn = server.ctSpawn
	elseif team == "t" then
		spawn = server.tSpawn
	end

	if spawn ~= 0 then
		RespawnPlayerAtTransform(
			GetLocationTransform(spawn),
			player
		)

		SetPlayerHealth(1.0, player)
		SetPlayerRegenerationState(false, player)
	end
end

function server.assignTeamAndSpawn(player)
	local team = server.nextTeam
	server.playerTeams[player] = team

	if team == "ct" then
		server.nextTeam = "t"
	else
		server.nextTeam = "ct"
	end

	ClientCall(0, "client.setTeam", player, team)
	server.respawnTeamPlayer(player)

	DebugPrint(GetPlayerName(player) .. " joined team " .. team)
end 

function server.startRound()
	shared.roundTime = 120
	shared.restartTime = 0
	shared.roundState = "playing"

	for player in Players() do
		server.respawnTeamPlayer(player)
	end

	DebugPrint("New round started")
end
function server.endRound(winner)
	if shared.roundState ~= "playing" then
		return
	end

	shared.roundState = "round_end"
	shared.roundWinner = winner
	shared.restartTime = 3

	DebugPrint("Round winner: " .. winner)
end

function server.checkTeamWin()
	local ctAlive = 0
	local tAlive = 0
	local ctPlayers = 0
	local tPlayers = 0

	for player in Players() do
		local team = server.playerTeams[player]
		local alive = GetPlayerHealth(player) > 0

		if team == "ct" then
			ctPlayers = ctPlayers + 1
			if alive then
				ctAlive = ctAlive + 1
			else
				DisablePlayerInput(player)
			end
		elseif team == "t" then
			tPlayers = tPlayers + 1
			if alive then
				tAlive = tAlive + 1
			else
				DisablePlayerInput(player)
			end
		end
	end
	-- Победу проверяем, только если в обеих командах есть игроки
	if ctPlayers > 0 and tPlayers > 0 then
		if ctAlive == 0 then
			server.endRound("t")
		elseif tAlive == 0 then
			server.endRound("ct")
		end
	end	
end

function server.tick(dt)
	for p in Players() do
		if server.playerTeams[p] == nil then
			server.setDefaultToolsForPlayer(p)

			if IsToolEnabled("sledge", p) then
				SetPlayerTool("sledge", p)
			end

			server.assignTeamAndSpawn(p)
		end
	end

	--Check if we're in sandbox mode and all tools should be onlocked
	--This cannot be done in init, since we don't know the init order
	if not allToolsCheck then
		if GetBool("level.sandbox") and GetBool("level.unlimitedammo") and GetInt("options.game.sandbox.unlocktools") == 1 then
			for id,tool in pairs(gTools) do
				SetBool("game.tool."..id..".enabled", true, true)
			end
		end
		allToolsCheck = true
	end

	-- check custom tools on first tick after all mods inited
	if not gCustomToolsChecked then
		gCustomToolsChecked = true
		---syncCustomToolsActivities()
	end

	--Handle valuables
	if shared.enableValuables then
		for p in Players() do
			local interactPressed = InputPressed("interact", p)
			local interactBody = GetPlayerInteractBody(p)
			for i=1, #valuables do
				local s = valuables[i]
				if s ~= 0 and IsHandleValid(s) then
					--Remove if broken
					if IsBodyBroken(s) then
						RemoveTag(s, "valuable")
						RemoveTag(s, "interact")
						valuables[i] = 0
					end

					--Set text when language changed
					if interactBody == s then
						SetTag(s, "interact", "loc@GRAB_VALUABLE")
					end

					--Clear if interacted
					if interactBody == s and interactPressed then
						local id = GetTagValue(s, "valuable")
						SetBool("savegame.valuable."..id, true);
						local value = tonumber(GetTagValue(s, "value"))
						if not value then value = 0 end
						SetInt("savegame.cash", GetInt("savegame.cash") + value)
						local msg = GetTranslatedStringByKey("UI_HUD_NOTE_PICKED_UP," .. GetDescription(s) .. "," .. value)
						ClientCall(0, "client.pickup", msg, p)
						Delete(s)
					end
				end
			end
		end
	end
	if shared.roundState == "playing" then
		shared.roundTime = math.max(0, shared.roundTime - dt)

		if shared.roundTime <= 0 then
			server.endRound("draw")
		else
			server.checkTeamWin()
		end

	elseif shared.roundState == "round_end" then
		for player in Players() do
			DisablePlayerInput(player)
		end

		shared.restartTime = math.max(0, shared.restartTime - dt)

		if shared.restartTime <= 0 then
			server.startRound()
		end
	end
end

----------------------------------------------------------------------------------------------------------

function client.init()
	client.localTeam = ""
	if shared.enableValuables then
		valuables = FindBodies("valuable", true)
		valuableAlpha = {}
		valuableSound = LoadSound("valuable.ogg")
	end
end

function client.setTeam(player, team)
	if IsPlayerLocal(player) then
		client.localTeam = team
	end
end

function client.pickup(msg, p)
	if not IsPlayerLocal(p) then
		msg = GetPlayerName(p) .. " " .. msg
	end
	SetString("hud.notification", msg)
	PlaySound(valuableSound, GetCameraTransform().pos, 1.0, false)
end


function client.tick(dt)
	if shared.enableValuables then
		for p in Players() do
			for i=1, #valuables do
				local s = valuables[i]
				if s ~= 0 and IsHandleValid(s) then
					--Outline and picking info
					if IsBodyVisible(s, 6) then
						if valuableAlpha[s] == nil then
							valuableAlpha[s] = 1
						end
					else
						valuableAlpha[s] = nil
					end
					if valuableAlpha[s] then
						valuableAlpha[s] = valuableAlpha[s] - GetTimeStep()*2
						if valuableAlpha[s] > 0 then
							DrawBodyHighlight(s, valuableAlpha[s])
						end
					end
				end
			end
		end
	end
end

function client.draw()
	UiPush()
		UiAlign("center middle")
		UiFont("regular.ttf", 32)
		UiTranslate(UiCenter(), 40)

		local timeLeft = shared.roundTime or 0
		local minutes = math.floor(timeLeft / 60)
		local seconds = math.floor(timeLeft % 60)

		UiText(string.format("%02d:%02d", minutes, seconds))

		UiTranslate(0, 40)

		if client.localTeam == "ct" then
			UiColor(0.3, 0.6, 1.0)
			UiText("TEAM: CT")
		elseif client.localTeam == "t" then
			UiColor(1.0, 0.65, 0.2)
			UiText("TEAM: T")
		end
		if shared.roundState == "round_end" then
			UiTranslate(0, 40)
			UiColor(1, 1, 1)

			local result = "DRAW"
			if shared.roundWinner == "ct" then
				result = "CT WIN"
			elseif shared.roundWinner == "t" then
				result = "T WIN"
			end

			UiText(result)

			UiTranslate(0, 40)
			UiText(
				"NEW ROUND IN " ..
				math.ceil(shared.restartTime or 0)
			)
		end
	UiPop()
end