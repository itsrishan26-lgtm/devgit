--[[
	GameSetup  -  Script  (a normal Script, NOT a LocalScript)
	WHERE IT GOES: ServerScriptService > GameSetup

	The round loop and the single source of truth for who is what.

	  Waiting  ->  Intermission  ->  Starting  ->  Round  ->  Results  ->  repeat

	  Waiting       not enough players yet
	  Intermission  everyone is a runner in the lobby, next round counting down
	  Starting      roles handed out, seekers frozen so runners can scatter
	  Round         the hunt; ends early the moment the last runner is caught
	  Results       win/lose banner and points

	It also owns: teams, leaderstats, saved stats, spawning, and the startup
	check that tells you in the Output window if the place is wired up wrong.

	CatchDetection does the tagging. It talks to this script only through
	player attributes and ChainTagState, so neither script can break the other.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local DataStoreService = game:GetService("DataStoreService")
local StarterPack = game:GetService("StarterPack")
local StarterPlayer = game:GetService("StarterPlayer")

local sharedModule = ReplicatedStorage:FindFirstChild("ChainTagShared")
if not sharedModule then
	error("[ChainTag] ReplicatedStorage.ChainTagShared is missing. " ..
		"Add the ChainTagConfig and ChainTagShared ModuleScripts first (README step 2).")
end

local Shared = require(sharedModule)
local Config = Shared.Config

--------------------------------------------------------------------------
-- Startup check: shout about the things that silently break a place
--------------------------------------------------------------------------

local BAD_SOUND_IDS = { ["rbxassetid://5028439856"] = true }

local function makeFallbackSpawn(name, position, color)
	local pad = Instance.new("SpawnLocation")
	pad.Name = name
	pad.Size = Vector3.new(12, 1, 12)
	pad.Anchored = true
	pad.CanCollide = true
	pad.Enabled = false      -- this script does the spawning, not Roblox
	pad.Neutral = true
	pad.BrickColor = color
	pad.Material = Enum.Material.SmoothPlastic
	pad.Position = position
	pad.Parent = workspace
	return pad
end

local function validateSetup()
	-- 1. Spawn pads. Names must match Workspace exactly, space included.
	for _, entry in ipairs({
		{ name = Config.SeekerSpawnName, position = Vector3.new(-60, 0.5, 0), color = BrickColor.new("Bright red") },
		{ name = Config.RunnerSpawnName, position = Vector3.new(60, 0.5, 0), color = BrickColor.new("Bright blue") },
	}) do
		local pad = Shared.findSpawn(entry.name)
		if not pad then
			warn(string.format(
				"[ChainTag] No part named \"%s\" in Workspace, so a temporary pad was made at %s. " ..
				"Rename your real SpawnLocation to \"%s\" (exact spelling and spaces) and this stops happening.",
				entry.name, tostring(entry.position), entry.name))
			makeFallbackSpawn(entry.name, entry.position, entry.color)
		elseif pad:IsA("SpawnLocation") and pad.Enabled then
			pad.Enabled = false
			warn(string.format("[ChainTag] \"%s\" had Enabled ticked on. Turned it off so the round script controls spawning.", entry.name))
		end
	end

	-- 2. Anything in StarterPack ends up in every player's Backpack. A stray
	--    script there is the classic source of "attempt to index nil".
	for _, item in ipairs(StarterPack:GetChildren()) do
		if item:IsA("BaseScript") then
			warn(string.format("[ChainTag] StarterPack contains a script called \"%s\". " ..
				"It runs in every player's Backpack. Delete it unless you know you need it.", item.Name))
		end
	end

	-- 3. The client scripts. A missing one shows up as "nothing on screen"
	--    with no error anywhere, so it is worth saying out loud.
	local scripts = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if not scripts then
		warn("[ChainTag] StarterPlayer has no StarterPlayerScripts folder. None of the HUD can run.")
	else
		if scripts:FindFirstChild("CatchCountdownUI") then
			warn("[ChainTag] StarterPlayerScripts.CatchCountdownUI is the old HUD and is now built into ChainTagUI. Delete it.")
		end
		for _, name in ipairs({ "Sprint", "ChainTagUI", "ChainVisuals", "ScoreboardUI", "AbilityBar" }) do
			local found = scripts:FindFirstChild(name)
			if not found then
				warn(string.format("[ChainTag] StarterPlayerScripts.%s is missing - add it as a LocalScript " ..
					"(README step 4). Without it that part of the screen simply will not appear.", name))
			elseif not found:IsA("LocalScript") then
				warn(string.format("[ChainTag] StarterPlayerScripts.%s is a %s. It has to be a LocalScript, " ..
					"or a Script with RunContext set to Client.", name, found.ClassName))
			end
		end
	end

	-- 4. Private sound ids fail with "not authorized" and are easy to miss.
	local scanned = 0
	for _, root in ipairs({ workspace, StarterPack, StarterPlayer, ReplicatedStorage, game:GetService("Lighting"), game:GetService("SoundService") }) do
		for _, item in ipairs(root:GetDescendants()) do
			scanned += 1
			if scanned > 200000 then
				break
			end
			if item:IsA("Sound") and BAD_SOUND_IDS[item.SoundId] then
				warn(string.format("[ChainTag] Sound \"%s\" at %s uses a private asset id (%s) that will not play. Replace it.",
					item.Name, item:GetFullName(), item.SoundId))
			end
		end
	end
end

validateSetup()

Players.RespawnTime = Config.RespawnTime

--------------------------------------------------------------------------
-- Teams (purely cosmetic: it colours names and groups the player list)
--------------------------------------------------------------------------

local function ensureTeam(name, brickColor)
	local team = Teams:FindFirstChild(name)
	if not team then
		team = Instance.new("Team")
		team.Name = name
		team.Parent = Teams
	end
	team.AutoAssignable = false   -- this script hands out teams, not Roblox
	team.TeamColor = brickColor
	return team
end

local seekerTeam = ensureTeam("Seekers", BrickColor.new("Bright red"))
local runnerTeam = ensureTeam("Runners", BrickColor.new("Bright blue"))

--------------------------------------------------------------------------
-- Saved stats
--------------------------------------------------------------------------

local STAT_KEYS = { "Points", "Catches", "Wins", "Survivals", "RoundsPlayed" }
local LEADERSTAT_KEYS = { Points = true, Catches = true }

local statStore
local statsWorking = Config.SaveStats
if Config.SaveStats then
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		statStore = result
	else
		statsWorking = false
		warn("[ChainTag] Stats will not save this session: " .. tostring(result))
	end
end

local savesInFlight = 0

local function readStat(player, key)
	if LEADERSTAT_KEYS[key] then
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild(key)
		return value and value.Value or 0
	end
	return player:GetAttribute(key) or 0
end

local function writeStat(player, key, amount)
	if LEADERSTAT_KEYS[key] then
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild(key)
		if value then
			value.Value = amount
		end
	else
		player:SetAttribute(key, amount)
	end
end

local function setupStats(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"

	local points = Instance.new("IntValue")
	points.Name = "Points"
	points.Parent = stats

	local catches = Instance.new("IntValue")
	catches.Name = "Catches"
	catches.Parent = stats

	stats.Parent = player

	for _, key in ipairs(STAT_KEYS) do
		if not LEADERSTAT_KEYS[key] then
			player:SetAttribute(key, 0)
		end
	end
end

local function loadStats(player)
	if not (statStore and statsWorking) then
		return
	end
	local key = "Player_" .. player.UserId
	local data, ok
	for attempt = 1, 3 do
		ok, data = pcall(function()
			return statStore:GetAsync(key)
		end)
		if ok then
			break
		end
		-- "Studio access to APIs is not allowed" is a setting, not a hiccup.
		-- Retrying it just fills the Output window with red.
		-- Roblox words this two different ways depending on where it is
		-- raised, so match both rather than only the enum-looking one.
		local reason = tostring(data)
		if string.find(reason, "StudioAccessToApis")
			or string.find(reason, "Studio access to APIs")
		then
			statsWorking = false
			warn("[ChainTag] Stats will not save in Studio until you tick " ..
				"File > Game Settings > Security > Enable Studio Access to API Services. " ..
				"This does not affect a published game.")
			return
		end
		task.wait(2 ^ attempt)
	end
	if not ok then
		statsWorking = false
		warn("[ChainTag] Could not read saved stats (turning saving off for this session): " .. tostring(data))
		return
	end
	if type(data) ~= "table" or not player.Parent then
		return
	end
	for _, statKey in ipairs(STAT_KEYS) do
		if type(data[statKey]) == "number" then
			writeStat(player, statKey, data[statKey])
		end
	end
end

local function saveStats(player)
	if not (statStore and statsWorking) then
		return
	end
	local payload = {}
	for _, key in ipairs(STAT_KEYS) do
		payload[key] = readStat(player, key)
	end

	savesInFlight += 1
	local ok, err
	for attempt = 1, 3 do
		ok, err = pcall(function()
			statStore:SetAsync("Player_" .. player.UserId, payload)
		end)
		if ok then
			break
		end
		task.wait(2 ^ attempt)
	end
	if not ok then
		warn("[ChainTag] Could not save stats for " .. player.Name .. ": " .. tostring(err))
	end
	savesInFlight -= 1
end

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(saveStats, player)
	end
	local deadline = os.clock() + 20
	while savesInFlight > 0 and os.clock() < deadline do
		task.wait(0.1)
	end
end)

--------------------------------------------------------------------------
-- Roles and spawning
--------------------------------------------------------------------------

local spawnSlot = {}       -- [player] = stable ring slot, so respawns do not stack
local lastSeekerUserId = 0

local function setRole(player, isSeeker, inRound)
	player:SetAttribute("IsSeeker", isSeeker and true or false)
	player:SetAttribute("InRound", inRound and true or false)
	if not isSeeker then
		player:SetAttribute("ChainedTo", nil)
	end
	player.Team = isSeeker and seekerTeam or runnerTeam
	Shared.applyBaseSpeed(player)
end

local function spawnPadFor(player)
	local phase = Shared.getState("Phase")
	local hunting = (phase == "Starting" or phase == "Round")
	if hunting and Shared.inRound(player) and Shared.isSeeker(player) then
		return Shared.findSpawn(Config.SeekerSpawnName)
	end
	return Shared.findSpawn(Config.RunnerSpawnName)
end

local function placePlayer(player)
	local pad = spawnPadFor(player)
	if pad then
		Shared.teleportTo(player, pad, spawnSlot[player] or 1)
	end
end

local function onCharacterAdded(player, character)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and root) then
		return
	end
	Shared.clearLegacyChain(character)

	-- Let Roblox finish its own spawn placement before we override it.
	task.wait(0.1)
	if not (character.Parent and player.Parent) then
		return
	end

	placePlayer(player)

	-- Someone who respawns mid head-start must still be held still.
	local frozen = Shared.getState("Phase") == "Starting"
		and Shared.isSeeker(player)
		and Shared.inRound(player)
	Shared.setFrozen(player, frozen)
end

local function onPlayerAdded(player)
	setupStats(player)
	player:SetAttribute("IsSeeker", false)
	player:SetAttribute("ChainedTo", nil)

	-- Anyone who arrives mid-round watches this one out, then joins the next.
	local phase = Shared.getState("Phase")
	local midRound = (phase == "Starting" or phase == "Round")
	player:SetAttribute("InRound", not midRound)
	player.Team = runnerTeam

	task.spawn(loadStats, player)

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end

	if midRound then
		Shared.toast(player.Name .. " joins next round", "info")
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	spawnSlot[player] = nil
	task.spawn(saveStats, player)
end)

--------------------------------------------------------------------------
-- Counting who is left
--------------------------------------------------------------------------

local function participants()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if Shared.inRound(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function countRoles()
	local seekers, runners = {}, {}
	for _, player in ipairs(participants()) do
		if Shared.isSeeker(player) then
			table.insert(seekers, player)
		else
			table.insert(runners, player)
		end
	end
	return seekers, runners
end

local function publishCounts()
	local seekers, runners = countRoles()
	Shared.setState("RunnersLeft", #runners)
	-- Rescues put runners back in play, so the round total can grow.
	if #runners > (Shared.getState("TotalRunners") or 0) then
		Shared.setState("TotalRunners", #runners)
	end
	Shared.setState("SeekerCount", #seekers)
	if Config.LastRunnerBeacon and #runners == 1 then
		Shared.setState("LastRunnerUserId", runners[1].UserId)
	else
		Shared.setState("LastRunnerUserId", 0)
	end
	return seekers, runners
end

--------------------------------------------------------------------------
-- Phase helpers
--------------------------------------------------------------------------

local function setPhase(name, duration)
	Shared.setState("Phase", name)
	Shared.setState("PhaseEndsAt", duration and (workspace:GetServerTimeNow() + duration) or 0)
	Shared.log("phase ->", name)
end

-- Waits out the current phase. Returns false early if keepGoing() says stop.
local function waitPhase(keepGoing)
	while Shared.timeLeft() > 0 do
		task.wait(0.1)
		if keepGoing and not keepGoing() then
			return false
		end
	end
	return true
end

local ROUND_ATTRIBUTES = {
	CaughtThisRound = false,
	Rescued = false,
	Immune = false,
	BeingRescued = false,
	InBeacon = false,
	RescueProgress = 0,
	RescueTargetId = 0,
	SpeedBonus = 0,
}

local function resetEveryone()
	for _, player in ipairs(Players:GetPlayers()) do
		setRole(player, false, true)
		Shared.setAnchored(player, false)
		Shared.setFrozen(player, false)
		for key, value in pairs(ROUND_ATTRIBUTES) do
			player:SetAttribute(key, value)
		end
	end
	Shared.setState("EndgameReveal", false)
	Shared.setState("LastRunnerUserId", 0)
	Shared.setState("CatchesInProgress", 0)
	Shared.setState("SoloPractice", false)
	Shared.setState("Winner", "")
	Shared.setState("ResultText", "")
	publishCounts()
end

local function sendEveryoneToLobby()
	local index = 0
	local pad = Shared.findSpawn(Config.RunnerSpawnName)
	for _, player in ipairs(Players:GetPlayers()) do
		index += 1
		spawnSlot[player] = index
		if pad then
			Shared.teleportTo(player, pad, index)
		end
	end
end

--------------------------------------------------------------------------
-- Results
--------------------------------------------------------------------------

local function nameList(players, limit)
	local names = {}
	for i, player in ipairs(players) do
		if i > limit then
			table.insert(names, string.format("and %d more", #players - limit))
			break
		end
		table.insert(names, player.Name)
	end
	return table.concat(names, ", ")
end

local function awardAndAnnounce(winner, survivors, seekers)
	if winner == "Seekers" then
		for _, player in ipairs(seekers) do
			Shared.addStat(player, "Points", Config.Points.SeekerWin)
			Shared.addStat(player, "Wins", 1)
		end
		Shared.setState("ResultText", "Every runner was chained.")
	elseif winner == "Runners" then
		for _, player in ipairs(survivors) do
			Shared.addStat(player, "Points", Config.Points.Survive)
			Shared.addStat(player, "Wins", 1)
			Shared.addStat(player, "Survivals", 1)
		end
		if #survivors > 0 then
			Shared.setState("ResultText", string.format("%s made it: %s",
				#survivors == 1 and "One runner" or (#survivors .. " runners"),
				nameList(survivors, 3)))
		else
			Shared.setState("ResultText", "The runners held out.")
		end
	else
		Shared.setState("ResultText", "Round ended early.")
	end
	Shared.setState("Winner", winner)
end

--------------------------------------------------------------------------
-- The round loop
--------------------------------------------------------------------------

local function pickSeeker(candidates)
	-- Prefer somebody who was not the seeker last round, and who is alive.
	local alive, fresh = {}, {}
	for _, player in ipairs(candidates) do
		if Shared.getRoot(player) then
			table.insert(alive, player)
			if player.UserId ~= lastSeekerUserId then
				table.insert(fresh, player)
			end
		end
	end
	local pool = #fresh > 0 and fresh or alive
	if #pool == 0 then
		return nil
	end
	return pool[math.random(1, #pool)]
end

local function runHunt()
	local revealed = false
	while Shared.timeLeft() > 0 do
		task.wait(0.1)
		local seekers, runners = publishCounts()

		if #seekers + #runners < 2 then
			return "None"
		end

		-- The whole seeker team quit: hand the job to a random runner.
		if #seekers == 0 then
			local replacement = pickSeeker(runners)
			if not replacement then
				return "None"
			end
			setRole(replacement, true, true)
			lastSeekerUserId = replacement.UserId
			Shared.toast(replacement.Name .. " is the new seeker", "seeker")
			publishCounts()
		end

		-- Wait for any catch countdown to finish so the last tag plays out.
		if #runners == 0 and (Shared.getState("CatchesInProgress") or 0) <= 0 then
			return "Seekers"
		end

		if not revealed and Shared.timeLeft() <= Config.EndgameRevealAt and #runners > 0 then
			revealed = true
			Shared.setState("EndgameReveal", true)
			Shared.toast("Runners are exposed for the last " .. Config.EndgameRevealAt .. " seconds", "warn")
		end
	end
	return "Runners"
end

local function playRound()
	local roster = Players:GetPlayers()
	if #roster < Config.MinPlayers then
		return
	end

	-- Everyone present is in; latecomers get InRound = false until next round.
	for index, player in ipairs(roster) do
		spawnSlot[player] = index
		setRole(player, false, true)
	end

	local solo = #roster < 2
	Shared.setState("SoloPractice", solo)
	Shared.setState("Winner", "")
	Shared.setState("ResultText", "")

	local seeker
	if not solo then
		seeker = pickSeeker(roster)
		if not seeker then
			return  -- nobody has a character yet; try again next cycle
		end
		setRole(seeker, true, true)
		lastSeekerUserId = seeker.UserId
	end

	Shared.setState("TotalRunners", #roster - (seeker and 1 or 0))
	publishCounts()

	-- Send everyone to their pad before the head start begins.
	local seekerPad = Shared.findSpawn(Config.SeekerSpawnName)
	local runnerPad = Shared.findSpawn(Config.RunnerSpawnName)
	local seekerIndex, runnerIndex = 0, 0
	for _, player in ipairs(roster) do
		if Shared.isSeeker(player) then
			seekerIndex += 1
			spawnSlot[player] = seekerIndex
			if seekerPad then
				Shared.teleportTo(player, seekerPad, seekerIndex)
			end
		else
			runnerIndex += 1
			spawnSlot[player] = runnerIndex
			if runnerPad then
				Shared.teleportTo(player, runnerPad, runnerIndex)
			end
		end
	end

	-- HEAD START -----------------------------------------------------------
	setPhase("Starting", Config.HeadStart)
	if seeker then
		Shared.setFrozen(seeker, true)
		Shared.toast(seeker.Name .. " is the seeker", "seeker")
	else
		Shared.toast("Solo practice round - add a second player for a real round", "info")
	end
	waitPhase(function()
		return #Players:GetPlayers() > 0
	end)
	if seeker then
		Shared.setFrozen(seeker, false)
	end

	-- THE HUNT -------------------------------------------------------------
	setPhase("Round", Config.RoundLength)
	_G.GameActive = true      -- kept for older scripts that still read this flag
	local winner
	if solo then
		-- Practice round: no seeker, no win condition. It ends the moment a
		-- second player shows up, so the next cycle is a real round.
		waitPhase(function()
			return #Players:GetPlayers() < 2
		end)
		winner = "None"
	else
		winner = runHunt()
	end
	_G.GameActive = false

	-- RESULTS --------------------------------------------------------------
	local seekers, runners = countRoles()
	for _, player in ipairs(participants()) do
		Shared.addStat(player, "RoundsPlayed", 1)
		Shared.setFrozen(player, false)
		Shared.setAnchored(player, false)
	end
	Shared.setState("EndgameReveal", false)
	Shared.setState("LastRunnerUserId", 0)

	awardAndAnnounce(winner, runners, seekers)
	if solo then
		Shared.setState("ResultText", "Practice round over - a second player starts a real one.")
	end
	setPhase("Results", Config.ResultsTime)
	task.wait(Config.ResultsTime)
end

task.spawn(function()
	-- Give the other scripts and the first player a moment to load in.
	task.wait(2)
	while true do
		resetEveryone()
		sendEveryoneToLobby()

		if #Players:GetPlayers() < Config.MinPlayers then
			setPhase("Waiting", nil)
			Shared.setState("PlayersNeeded", Config.MinPlayers)
			while #Players:GetPlayers() < Config.MinPlayers do
				task.wait(0.5)
			end
		end

		setPhase("Intermission", Config.Intermission)
		local enough = waitPhase(function()
			return #Players:GetPlayers() >= Config.MinPlayers
		end)

		if enough then
			playRound()
		end
		task.wait(0.5)
	end
end)

print("[ChainTag] GameSetup running. Round length " .. Config.RoundLength ..
	"s, " .. Config.MinPlayers .. " player(s) needed.")
