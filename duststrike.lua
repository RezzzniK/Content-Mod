#version 2

function server.init()
	shared.roundTime = 120

	server.ctSpawn = FindLocation("ct_spawn", true)
	server.tSpawn = FindLocation("t_spawn", true)

	server.playerTeams = {}
	server.nextTeam = "ct"

	for _, player in ipairs(GetAllPlayers()) do
		server.assignTeamAndSpawn(player)
	end
end

function server.assignTeamAndSpawn(player)
	if server.playerTeams[player] ~= nil then
		return
	end

	local team = server.nextTeam
	server.playerTeams[player] = team

	if team == "ct" then
		server.nextTeam = "t"
	else
		server.nextTeam = "ct"
	end

	server.spawnTeamPlayer(player)
	ClientCall(player, "client.setTeam", team)
	DebugPrint(GetPlayerName(player) .. " joined " .. team)
end

function server.spawnTeamPlayer(player)
	local spawn = server.ctSpawn

	if server.playerTeams[player] == "t" then
		spawn = server.tSpawn
	end

	if spawn == 0 then
		DebugPrint("DustStrike error: spawn location not found")
		return
	end

	RespawnPlayerAtTransform(GetLocationTransform(spawn), player)
	SetPlayerHealth(1.0, player)
	SetPlayerRegenerationState(false, player)
end

function server.tick(dt)
	shared.roundTime = math.max(0, (shared.roundTime or 0) - dt)

	for _, player in ipairs(GetAddedPlayers()) do
		server.assignTeamAndSpawn(player)
	end
end

function client.init()
	client.team = client.team or "UNASSIGNED"
end

function client.setTeam(team)
	client.team = team
end

function client.draw()
	local timeLeft = shared.roundTime or 0
	local minutes = math.floor(timeLeft / 60)
	local seconds = math.floor(timeLeft % 60)

	UiPush()
		UiAlign("center middle")
		UiFont("regular.ttf", 32)
		UiTranslate(UiCenter(), 40)
		UiText(string.format("%02d:%02d", minutes, seconds))

		UiTranslate(0, 36)

		if client.team == "ct" then
			UiColor(0.3, 0.65, 1)
			UiText("CT TEAM")
		elseif client.team == "t" then
			UiColor(1, 0.55, 0.2)
			UiText("T TEAM")
		end
	UiPop()
end