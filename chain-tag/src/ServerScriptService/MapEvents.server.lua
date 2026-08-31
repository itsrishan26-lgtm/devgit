--[[
	MapEvents  -  Script  (a normal Script, NOT a LocalScript)
	WHERE IT GOES: ServerScriptService > MapEvents

	The three things that make the map itself worth moving around in.

	  PICKUPS   glowing crystals scattered on the ground. Runners get stamina
	            and a speed burst, seekers get a smaller burst. Both sides
	            want them, so they turn into contested ground.
	  BEACON    a marked circle that moves every 35 seconds and pays runners
	            points for standing in it. Stops the round turning into
	            hiding in a corner, and tells seekers where to go.
	  RESCUE    stand next to somebody on the end of a chain long enough and
	            you break them out. Gives runners something to do besides run.

	Nothing in here needs you to mark or tag anything in your map. Every
	position is found at runtime by raycasting straight down and checking the
	ground is flat enough to stand on, inside Config.Map.Radius of
	Config.Map.Center.

	If this script errors or you delete it, the core game carries on without
	it - none of the round logic depends on anything here.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local sharedModule = ReplicatedStorage:FindFirstChild("ChainTagShared")
if not sharedModule then
	error("[ChainTag] ReplicatedStorage.ChainTagShared is missing (README step 2).")
end

local Shared = require(sharedModule)
local Config = Shared.Config

local folder = Instance.new("Folder")
folder.Name = "ChainTagMap"
folder.Parent = workspace

--------------------------------------------------------------------------
-- Finding somewhere to put things
--------------------------------------------------------------------------

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

local function refreshGroundFilter()
	local ignore = { folder }
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	groundParams.FilterDescendantsInstances = ignore
end

-- Picks a random spot on walkable ground, keeping clear of anything in
-- `taken`. Returns nil if the map is so cluttered it cannot find one.
local function findGroundPoint(taken)
	refreshGroundFilter()
	local map = Config.Map
	local spacingSquared = map.MinSpacing * map.MinSpacing

	for _ = 1, 40 do
		local angle = math.random() * math.pi * 2
		local distance = math.sqrt(math.random()) * map.Radius
		local origin = map.Center
			+ Vector3.new(math.cos(angle) * distance, map.ScanHeight, math.sin(angle) * distance)

		local hit = workspace:Raycast(origin, Vector3.new(0, -map.ScanHeight * 2, 0), groundParams)
		if hit and hit.Normal.Y >= map.MinGroundNormal then
			local clear = true
			for _, other in ipairs(taken or {}) do
				local offset = other - hit.Position
				if offset:Dot(offset) < spacingSquared then
					clear = false
					break
				end
			end
			if clear then
				return hit.Position
			end
		end
	end
	return nil
end

--------------------------------------------------------------------------
-- Pickups
--------------------------------------------------------------------------

local pickups = {}   -- { part = Part, takenAt = number? }

local function makePickup()
	local part = Instance.new("Part")
	part.Name = "EnergyCrystal"
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1              -- stays hidden until it is placed
	part.Position = Vector3.new(0, -500, 0)
	part.Parent = folder

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Parent = part

	-- ChainVisuals spins and bobs anything carrying this tag, on each
	-- client, so the server never replicates an animation.
	CollectionService:AddTag(part, "ChainTagPickup")
	return part
end

local function takenPositions()
	local list = {}
	for _, pickup in ipairs(pickups) do
		if not pickup.takenAt then
			table.insert(list, pickup.part.Position)
		end
	end
	return list
end

local function placePickup(pickup)
	local point = findGroundPoint(takenPositions())
	if not point then
		-- Nowhere clear to put it this time. Sit out another respawn rather
		-- than re-scanning the map every tenth of a second.
		pickup.takenAt = os.clock()
		return false
	end

	-- Every crystal rolls its own rarity when it lands, so the ladder is
	-- re-rolled all round rather than fixed at the start.
	local rarity = Shared.rollRarity()
	pickup.rarity = rarity

	local part = pickup.part
	local resting = point + Vector3.new(0, Config.Pickups.Hover, 0)
	part.Size = Vector3.new(rarity.size, rarity.size, rarity.size)
	part.Color = rarity.color
	part.Position = resting
	part.Transparency = 0
	-- ChainVisuals reads these to bob, spin and colour it on each client.
	part:SetAttribute("Base", resting)
	part:SetAttribute("Rarity", rarity.name)
	part:SetAttribute("Spin", rarity.spin)

	local light = part:FindFirstChildOfClass("PointLight")
	if light then
		light.Color = rarity.color
		light.Range = rarity.light
		light.Enabled = true
	end

	pickup.takenAt = nil

	if rarity.announce then
		-- The top of the ladder is a server-wide event, not just a better
		-- drop. Everybody hears about it and races for it.
		Shared.toast("A " .. string.upper(tostring(rarity.name)) .. " crystal landed in the park", "legendary")
	end
	return true
end

local function hidePickup(pickup)
	pickup.takenAt = os.clock()
	pickup.part.Transparency = 1
	pickup.part.Position = Vector3.new(0, -500, 0)
	local light = pickup.part:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = false
	end
end

-- Counts each burst so a second pickup cannot have its speed wiped early by
-- the first one's timer running out.
local burstToken = {}

local function grantPickup(player, rarity)
	local seeker = Shared.isSeeker(player)
	local bonus = rarity.speed * (seeker and Config.Pickups.SeekerScale or 1)

	local token = (burstToken[player] or 0) + 1
	burstToken[player] = token

	player:SetAttribute("SpeedBonus", bonus)
	-- Sprint (on the client) tops the bar up whenever this counter changes,
	-- by whatever amount this rarity is worth.
	player:SetAttribute("StaminaGrantAmount", rarity.stamina)
	player:SetAttribute("StaminaGrant", (player:GetAttribute("StaminaGrant") or 0) + 1)

	-- The orbiting aura every client draws around them for the duration.
	player:SetAttribute("AuraRarity", rarity.name)
	player:SetAttribute("AuraUntil", workspace:GetServerTimeNow() + rarity.duration)

	if rarity.points > 0 then
		Shared.addStat(player, "Points", rarity.points)
	end

	task.delay(rarity.duration, function()
		if player.Parent and burstToken[player] == token then
			player:SetAttribute("SpeedBonus", 0)
		end
	end)

	if rarity.announce then
		Shared.toast(player.Name .. " grabbed the " .. string.upper(tostring(rarity.name)) .. " crystal", "legendary")
	end
end

local function spawnPickups()
	if not Config.Pickups.Enabled then
		return
	end
	for index = 1, Config.Pickups.Count do
		local pickup = pickups[index]
		if not pickup then
			pickup = { part = makePickup() }
			pickups[index] = pickup
		end
		placePickup(pickup)
	end
end

local function updatePickups()
	local radiusSquared = Config.Pickups.Radius * Config.Pickups.Radius

	for _, pickup in ipairs(pickups) do
		if pickup.takenAt then
			if os.clock() - pickup.takenAt >= Config.Pickups.RespawnTime then
				placePickup(pickup)
			end
		else
			for _, player in ipairs(Players:GetPlayers()) do
				if Shared.inRound(player) then
					local root = Shared.getRoot(player)
					if root then
						local offset = root.Position - pickup.part.Position
						if offset:Dot(offset) <= radiusSquared then
							local rarity = pickup.rarity or Config.Rarities[1]
							local where = pickup.part.Position
							grantPickup(player, rarity)
							hidePickup(pickup)
							-- Everyone sees the burst; only the person who
							-- took it gets the card on their screen.
							Shared.Remotes.Collect:FireAllClients(where, rarity.name, player.UserId)
							break
						end
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Beacon
--------------------------------------------------------------------------

local beaconRing, beaconPillar
local beaconMovesAt = 0
local beaconPointTimer = 0

local function makeBeacon()
	local radius = Config.Beacon.Radius

	beaconRing = Instance.new("Part")
	beaconRing.Name = "BeaconRing"
	beaconRing.Shape = Enum.PartType.Cylinder
	beaconRing.Size = Vector3.new(0.4, radius * 2, radius * 2)
	beaconRing.Color = Config.Beacon.Color
	beaconRing.Material = Enum.Material.Neon
	beaconRing.Transparency = 0.65
	beaconRing.Anchored = true
	beaconRing.CanCollide = false
	beaconRing.CanQuery = false
	beaconRing.CanTouch = false
	beaconRing.CastShadow = false
	beaconRing.Parent = folder

	beaconPillar = Instance.new("Part")
	beaconPillar.Name = "BeaconPillar"
	beaconPillar.Shape = Enum.PartType.Cylinder
	beaconPillar.Size = Vector3.new(140, 7, 7)
	beaconPillar.Color = Config.Beacon.Color
	beaconPillar.Material = Enum.Material.Neon
	beaconPillar.Transparency = 0.86
	beaconPillar.Anchored = true
	beaconPillar.CanCollide = false
	beaconPillar.CanQuery = false
	beaconPillar.CanTouch = false
	beaconPillar.CastShadow = false
	beaconPillar.Parent = folder

	CollectionService:AddTag(beaconRing, "ChainTagBeacon")
end

local function moveBeacon()
	if not (beaconRing and beaconPillar) then
		return
	end
	local point = findGroundPoint(takenPositions())
	if not point then
		beaconMovesAt = os.clock() + 3   -- back off instead of hammering raycasts
		return
	end

	-- A Cylinder part points down its X axis, so both of these are turned
	-- a quarter turn to stand the right way up.
	local upright = CFrame.Angles(0, 0, math.pi * 0.5)
	beaconRing.CFrame = CFrame.new(point + Vector3.new(0, 0.3, 0)) * upright
	beaconPillar.CFrame = CFrame.new(point + Vector3.new(0, 70, 0)) * upright

	Shared.setState("BeaconPosition", point)
	Shared.setState("BeaconActive", true)
	beaconMovesAt = os.clock() + Config.Beacon.MoveEvery
	Shared.toast("A beacon lit up - runners score while they stand in it", "beacon")
end

local function hideBeacon()
	Shared.setState("BeaconActive", false)
	if beaconRing then
		beaconRing.CFrame = CFrame.new(0, -500, 0)
	end
	if beaconPillar then
		beaconPillar.CFrame = CFrame.new(0, -500, 0)
	end
end

local function updateBeacon(deltaTime)
	if not Config.Beacon.Enabled then
		return
	end
	if os.clock() >= beaconMovesAt then
		moveBeacon()
		return
	end
	if not Shared.getState("BeaconActive") then
		return
	end

	-- Points tick once a second for every runner standing inside.
	beaconPointTimer += deltaTime
	if beaconPointTimer < 1 then
		return
	end
	beaconPointTimer -= 1

	local centre = beaconRing.Position
	local radiusSquared = Config.Beacon.Radius * Config.Beacon.Radius
	for _, player in ipairs(Players:GetPlayers()) do
		if Shared.inRound(player) and not Shared.isSeeker(player) then
			local root = Shared.getRoot(player)
			if root then
				local offset = Vector3.new(root.Position.X - centre.X, 0, root.Position.Z - centre.Z)
				if offset:Dot(offset) <= radiusSquared then
					Shared.addStat(player, "Points", Config.Beacon.PointsPerSecond)
					player:SetAttribute("InBeacon", true)
				else
					player:SetAttribute("InBeacon", false)
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Rescue
--------------------------------------------------------------------------

local rescueProgress = {}   -- [rescuer] = { target = player, held = seconds }

local function clearRescue(rescuer)
	if rescueProgress[rescuer] then
		local previous = rescueProgress[rescuer].target
		if previous and previous.Parent then
			previous:SetAttribute("BeingRescued", false)
		end
		rescueProgress[rescuer] = nil
	end
	rescuer:SetAttribute("RescueProgress", 0)
	rescuer:SetAttribute("RescueTargetId", 0)
end

-- Only the far end of a chain can be freed: if somebody is chained to them,
-- breaking the link would orphan whoever is behind them.
local function isChainEnd(player)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other:GetAttribute("ChainedTo") == player.UserId then
			return false
		end
	end
	return true
end

local function canBeFreed(player)
	if not (Shared.inRound(player) and Shared.isSeeker(player)) then
		return false
	end
	if player:GetAttribute("CaughtThisRound") ~= true then
		return false   -- the original seeker was never a prisoner
	end
	if Config.Rescue.OncePerPlayer and player:GetAttribute("Rescued") == true then
		return false
	end
	if player:GetAttribute("Frozen") == true then
		return false   -- mid catch countdown
	end
	return isChainEnd(player)
end

local function freePlayer(target, rescuer)
	target:SetAttribute("IsSeeker", false)
	target:SetAttribute("ChainedTo", nil)
	target:SetAttribute("Rescued", true)
	target:SetAttribute("BeingRescued", false)
	target:SetAttribute("Immune", true)

	local runnerTeam = Teams:FindFirstChild("Runners")
	if runnerTeam then
		target.Team = runnerTeam
	end
	Shared.applyBaseSpeed(target)

	task.delay(Config.Rescue.Immunity, function()
		if target.Parent then
			target:SetAttribute("Immune", false)
		end
	end)

	Shared.addStat(rescuer, "Points", Config.Rescue.Points)
	Shared.addStat(rescuer, "Rescues", 1)
	Shared.toast(rescuer.Name .. " broke " .. target.Name .. " out of the chain", "rescue")
end

local function updateRescues(deltaTime)
	if not Config.Rescue.Enabled then
		return
	end
	if Config.Rescue.BlockedInEndgame and Shared.getState("EndgameReveal") then
		for rescuer in pairs(rescueProgress) do
			clearRescue(rescuer)
		end
		return
	end

	local radiusSquared = Config.Rescue.Radius * Config.Rescue.Radius

	for _, rescuer in ipairs(Players:GetPlayers()) do
		local working = false

		if Shared.inRound(rescuer) and not Shared.isSeeker(rescuer) then
			local rescuerRoot = Shared.getRoot(rescuer)
			if rescuerRoot then
				-- Stay on the same prisoner if they are still in range,
				-- otherwise pick the nearest one that qualifies.
				local current = rescueProgress[rescuer] and rescueProgress[rescuer].target
				local target, bestDistance = nil, math.huge

				for _, candidate in ipairs(Players:GetPlayers()) do
					if canBeFreed(candidate) then
						local candidateRoot = Shared.getRoot(candidate)
						if candidateRoot then
							local offset = candidateRoot.Position - rescuerRoot.Position
							local distance = offset:Dot(offset)
							if distance <= radiusSquared and (distance < bestDistance or candidate == current) then
								if candidate == current then
									target, bestDistance = candidate, -1
								else
									target, bestDistance = candidate, distance
								end
							end
						end
					end
				end

				if target then
					working = true
					local entry = rescueProgress[rescuer]
					if not entry or entry.target ~= target then
						if entry and entry.target and entry.target.Parent then
							entry.target:SetAttribute("BeingRescued", false)
						end
						entry = { target = target, held = 0 }
						rescueProgress[rescuer] = entry
					end

					entry.held += deltaTime
					target:SetAttribute("BeingRescued", true)
					rescuer:SetAttribute("RescueTargetId", target.UserId)
					rescuer:SetAttribute("RescueProgress",
						math.clamp(entry.held / Config.Rescue.HoldTime, 0, 1))

					if entry.held >= Config.Rescue.HoldTime then
						freePlayer(target, rescuer)
						clearRescue(rescuer)
					end
				end
			end
		end

		if not working and rescueProgress[rescuer] then
			clearRescue(rescuer)
		end
	end
end

--------------------------------------------------------------------------
-- Round hook-up
--------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(player)
	rescueProgress[player] = nil
	burstToken[player] = nil
end)

local function startRound()
	spawnPickups()
	if Config.Beacon.Enabled then
		if not beaconRing then
			makeBeacon()
		end
		hideBeacon()
		beaconMovesAt = os.clock() + Config.Beacon.StartAfter
	end
end

local function stopRound()
	for _, pickup in ipairs(pickups) do
		hidePickup(pickup)
		pickup.takenAt = nil
	end
	hideBeacon()
	for rescuer in pairs(rescueProgress) do
		clearRescue(rescuer)
	end
	for _, player in ipairs(Players:GetPlayers()) do
		player:SetAttribute("InBeacon", false)
		player:SetAttribute("SpeedBonus", 0)
		player:SetAttribute("AuraUntil", 0)
	end
end

task.spawn(function()
	local running = false
	local last = os.clock()

	while true do
		task.wait(0.1)
		local now = os.clock()
		local deltaTime = now - last
		last = now

		if Shared.getState("Phase") == "Round" then
			if not running then
				running = true
				startRound()
			end
			updatePickups()
			updateBeacon(deltaTime)
			updateRescues(deltaTime)
		elseif running then
			running = false
			stopRound()
		end
	end
end)

print("[ChainTag] MapEvents running. Pickups: " .. tostring(Config.Pickups.Enabled) ..
	", beacon: " .. tostring(Config.Beacon.Enabled) ..
	", rescue: " .. tostring(Config.Rescue.Enabled))
