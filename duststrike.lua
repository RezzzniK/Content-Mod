#version 2

function server.init()
	shared.roundTime = 120
end

function server.tick(dt)
	shared.roundTime = math.max(0, (shared.roundTime or 0) - dt)
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
	UiPop()
end