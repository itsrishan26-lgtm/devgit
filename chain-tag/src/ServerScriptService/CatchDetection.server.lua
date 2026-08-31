--[[
	CatchDetection  —  Script  (a normal Script, NOT a LocalScript)
	WHERE IT GOES: ServerScriptService > CatchDetection

	Turns "a seeker got close to a runner" into a catch.

	WHY NOT .Touched
	The old version listened to Touched on character parts. Touched misses fast
	passes, fires dozens of times for one bump, and happily fires through thin
	walls. This checks the distance between root parts ten times a second and
	confirms with one raycast, so a tag lands when it looks like it should and
	never twice.

	Catches only happen while ChainTagState.Phase is "Round", so nobody can be
	tagged in the lobby or during the seekers' head start.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local sharedModule = ReplicatedStorage:FindFirstChild("ChainTagShared")
if not sharedModule then
	error("[ChainTag] ReplicatedStorage.ChainTagShared is missing (README step 2).")
end

local Shared = require(sharedModule)
local Config = Shared.Config

local pendingCatch = {}   -- [player] = true while their catch countdown plays
local nextCatchAt = {}    -- [player] = os.clock() a seeker may tag again
local catchSlot = 0       -- keeps the two teleported players off each other's heads

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true
-- Leaves, flowers and other CanCollide-off decor should never block a tag.
pcall(function()
	rayParams.RespectCanCollide = true
end)

Players.PlayerRemoving:Connect(function(player)
	pendingCatch[player] = nil
	nextCatchAt[player] = nil
end)

local function bumpCatchesInProgress(delta)
	local current = Shared.getState("CatchesInProgress") or 0
	Shared.setState("CatchesInProgress", math.max(0, current + delta))
end

local function characterFilter()
	local list = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	return list
end

local function canSee(fromRoot, toRoot, filter)
	if not Config.RequireLineOfSight then
		return true
	end
	rayParams.FilterDescendantsInstances = filter
	local origin = fromRoot.Position
	local hit = workspace:Raycast(origin, toRoot.Position - origin, rayParams)
	return hit == nil
end

local function seekerSpawn()
	return Shared.findSpawn(Config.SeekerSpawnName)
end

-- Everyone joined to this player by the chain, following it in both
-- directions. Used so a catch pulls the whole chain home instead of ripping
-- the catcher away from the people already attached to them.
local function chainGroup(startPlayer)
	local byUserId = {}
	for _, player in ipairs(Players:GetPlayers()) do
		byUserId[player.UserId] = player
	end

	local found = { [startPlayer] = true }
	local queue = { startPlayer }
	while #queue > 0 do
		local current = table.remove(queue)
		local parent = byUserId[current:GetAttribute("ChainedTo") or 0]
		if parent and not found[parent] then
			found[parent] = true
			table.insert(queue, parent)
		end
		for _, player in ipairs(Players:GetPlayers()) do
			if not found[player] and player:GetAttribute("ChainedTo") == current.UserId then
				found[player] = true
				table.insert(queue, player)
			end
		end
	end

	local list = {}
	for player in pairs(found) do
		table.insert(list, player)
	end
	return list
end

local function doCatch(catcher, victim)
	if pendingCatch[victim] or Shared.isSeeker(victim) then
		return
	end

	pendingCatch[victim] = true
	bumpCatchesInProgress(1)

	-- Flip the role immediately so nobody else can tag the same runner.
	victim:SetAttribute("IsSeeker", true)
	victim:SetAttribute("ChainedTo", catcher.UserId)
	-- Marks them as a prisoner rather than the original seeker, which is
	-- what makes them eligible to be broken out again (see MapEvents).
	victim:SetAttribute("CaughtThisRound", true)
	victim:SetAttribute("BeingRescued", false)
	local seekerTeam = Teams:FindFirstChild("Seekers")
	if seekerTeam then
		victim.Team = seekerTeam
	end

	nextCatchAt[catcher] = os.clock() + Config.CatchCooldown
	Shared.addStat(catcher, "Points", Config.Points.Catch)
	Shared.addStat(catcher, "Catches", 1)

	-- The pair always freezes for the countdown. If catches send people back
	-- to base, the rest of their chain freezes and travels with them - being
	-- dragged home is the cost the seeker team pays for every catch, and it
	-- hands the runners a breather.
	local held = Config.TeleportOnCatch and chainGroup(catcher) or { catcher, victim }
	for _, player in ipairs(held) do
		Shared.setFrozen(player, true)
		Shared.setAnchored(player, true)
	end

	Shared.Remotes.CatchCountdown:FireAllClients(
		catcher.Name, victim.Name, Config.CatchCountdown, catcher.UserId, victim.UserId)
	Shared.toast(catcher.Name .. " chained " .. victim.Name, "catch")
	Shared.log(catcher.Name, "caught", victim.Name)

	-- Sit out the countdown in slices so a player leaving does not strand us.
	local finishAt = os.clock() + Config.CatchCountdown
	while os.clock() < finishAt do
		task.wait(0.1)
		if not (catcher.Parent and victim.Parent) then
			break
		end
	end

	local pad = seekerSpawn()
	local stillHunting = Shared.getState("Phase") == "Round"
	for _, player in ipairs(held) do
		if player.Parent then
			catchSlot += 1
			if Config.TeleportOnCatch and pad and stillHunting then
				Shared.teleportTo(player, pad, (catchSlot % Config.SpawnSlotsPerRing) + 1)
			end
			Shared.setAnchored(player, false)
			Shared.setFrozen(player, false)
		end
	end

	pendingCatch[victim] = nil
	bumpCatchesInProgress(-1)
end

--------------------------------------------------------------------------
-- The 10 Hz sweep
--------------------------------------------------------------------------

task.spawn(function()
	while true do
		task.wait(Config.CatchTickRate)

		if Shared.getState("Phase") ~= "Round" then
			continue
		end

		local seekers, runners = {}, {}
		for _, player in ipairs(Players:GetPlayers()) do
			if Shared.inRound(player) and not pendingCatch[player] then
				local root = Shared.getRoot(player)
				if root and player:GetAttribute("Frozen") ~= true then
					if Shared.isSeeker(player) then
						if (nextCatchAt[player] or 0) <= os.clock() then
							table.insert(seekers, { player = player, root = root })
						end
					elseif player:GetAttribute("Immune") ~= true then
						-- Someone just broken out of the chain is briefly
						-- untouchable, so they are not instantly re-tagged.
						table.insert(runners, { player = player, root = root })
					end
				end
			end
		end

		if #seekers == 0 or #runners == 0 then
			continue
		end

		local filter = characterFilter()
		local radiusSquared = Config.CatchRadius * Config.CatchRadius

		for _, seeker in ipairs(seekers) do
			for _, runner in ipairs(runners) do
				if not pendingCatch[runner.player] then
					local offset = seeker.root.Position - runner.root.Position
					if offset:Dot(offset) <= radiusSquared
						and canSee(seeker.root, runner.root, filter)
					then
						task.spawn(doCatch, seeker.player, runner.player)
						break   -- one catch per seeker per tick
					end
				end
			end
		end
	end
end)

print("[ChainTag] CatchDetection running. Tag range " .. Config.CatchRadius .. " studs.")
