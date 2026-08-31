--[[
	ChainVisuals  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > ChainVisuals

	Draws the chain, outlines the people who matter, and works out how much the
	chain is holding you back.

	ABOUT THE CHAIN
	The old version welded real parts with RopeConstraints between two players.
	Roblox gives each player physics ownership of their own character, so a
	rope between two of them is a tug of war between two computers - which is
	where the jostling and the occasional launch into orbit came from.

	Here the chain is drawn locally (nothing is welded to anyone, no physics at
	all) and the "pull" is done by slowing both ends down as they drift apart.
	It reads the same, it never flings anyone, and it costs the server nothing.

	Everything this script writes is local to your own client:
	  CT_ChainSlow   walk speed multiplier, read by the Sprint script
	  CT_ChainTaut   true when the chain is stretched, read by ChainTagUI
	  CT_Danger      0..1 how close the nearest seeker is, read by ChainTagUI
--]]

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config
local State = Shared.State
local ChainConfig = Config.Chain

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

if not State then
	error("[ChainTag] ChainTagState is missing. Check that ServerScriptService.GameSetup exists and is enabled.")
end

local folder = Instance.new("Folder")
folder.Name = "ChainTagVisuals"   -- created on this client only
folder.Parent = workspace

--------------------------------------------------------------------------
-- Chain parts
--------------------------------------------------------------------------

local links = {}     -- [player] = { parts = {...}, shown = bool }

local function makeLinkPart()
	local part = Instance.new("Part")
	part.Name = "ChainLink"
	part.Size = ChainConfig.LinkSize
	part.Color = ChainConfig.Color
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = folder
	return part
end

local function getLinkSet(owner)
	local set = links[owner]
	local wanted = Shared.quality().chainLinks
	if set and #set.parts ~= wanted then
		-- Quality changed under us; rebuild at the new link count.
		for _, part in ipairs(set.parts) do
			part:Destroy()
		end
		set = nil
		links[owner] = nil
	end
	if not set then
		local parts = {}
		for index = 1, wanted do
			parts[index] = makeLinkPart()
		end
		set = { parts = parts, shown = true }
		links[owner] = set
	end
	return set
end

local function setLinkSetShown(set, shown)
	if set.shown == shown then
		return
	end
	set.shown = shown
	for _, part in ipairs(set.parts) do
		part.Parent = shown and folder or nil
	end
end

local function dropLinkSet(owner)
	local set = links[owner]
	if not set then
		return
	end
	for _, part in ipairs(set.parts) do
		part:Destroy()
	end
	links[owner] = nil
end

local function anchorPoint(root)
	-- Roughly waist height, so the chain hangs off the body and not the neck.
	return root.CFrame:PointToWorldSpace(Vector3.new(0, -0.6, 0))
end

local function drawChain(set, fromPosition, toPosition, color)
	local count = #set.parts
	local sag = ChainConfig.Sag
	local step = 1 / (count + 1)

	local function samplePoint(t)
		return fromPosition:Lerp(toPosition, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
	end

	for index, part in ipairs(set.parts) do
		if part.Color ~= color then
			part.Color = color
		end
		local t = index * step
		local position = samplePoint(t)
		local ahead = samplePoint(math.min(1, t + step))
		if (ahead - position).Magnitude < 0.01 then
			part.CFrame = CFrame.new(position)
		else
			-- Every other link is rolled 90 degrees, the way real chain sits.
			part.CFrame = CFrame.lookAt(position, ahead)
				* CFrame.Angles(0, 0, index % 2 == 0 and math.pi * 0.5 or 0)
		end
	end
end

--------------------------------------------------------------------------
-- Highlights and the last-runner marker
--------------------------------------------------------------------------

local highlights = {}   -- [player] = Highlight
local faded = {}        -- [player] = true while Vanish is fading them for us

local function setHighlight(target, color, alwaysOnTop)
	local highlight = highlights[target]
	if not highlight then
		highlight = Instance.new("Highlight")
		highlight.Name = "ChainTagHighlight"
		highlight.FillTransparency = 0.75
		highlight.OutlineTransparency = 0
		highlight.Parent = folder
		highlights[target] = highlight
	end
	highlight.Adornee = target.Character
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.DepthMode = alwaysOnTop and Enum.HighlightDepthMode.AlwaysOnTop
		or Enum.HighlightDepthMode.Occluded
	highlight.Enabled = target.Character ~= nil
end

local function clearHighlight(target)
	local highlight = highlights[target]
	if highlight then
		highlight:Destroy()
		highlights[target] = nil
	end
end

local beacon = Instance.new("BillboardGui")
beacon.Name = "LastRunnerBeacon"
beacon.Size = UDim2.fromOffset(150, 26)
beacon.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
beacon.AlwaysOnTop = true
beacon.Enabled = false
beacon.Parent = folder

local beaconLabel = Instance.new("TextLabel")
beaconLabel.BackgroundTransparency = 1
beaconLabel.Size = UDim2.fromScale(1, 1)
beaconLabel.Font = Enum.Font.GothamBlack
beaconLabel.Text = "LAST RUNNER"
beaconLabel.TextColor3 = Config.Colors.Warn
beaconLabel.TextSize = 15
beaconLabel.TextStrokeTransparency = 0.4
beaconLabel.Parent = beacon

--------------------------------------------------------------------------
-- Collection burst
-- Built out of plain neon parts and thrown away by Debris. No texture to
-- load, so there is nothing here that can fail with a red error.
--------------------------------------------------------------------------

local function newEffectPart(size, color)
	local part = Instance.new("Part")
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = folder
	return part
end

local function spawnBurst(position, rarity)
	if not Shared.quality().burst then
		return   -- Low draws the pickup and the sound, but not the confetti
	end
	local life = Config.Aura.BurstTime

	-- A flat ring that pushes outwards and fades.
	local ring = newEffectPart(Vector3.new(0.4, 2, 2), rarity.color)
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi * 0.5)
	ring.Transparency = 0.2
	TweenService:Create(ring, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, rarity.size * 9, rarity.size * 9),
		Transparency = 1,
	}):Play()
	Debris:AddItem(ring, life + 0.1)

	-- Shards thrown outwards. Rarer crystals throw more of them.
	local shards = Config.Aura.BurstShards + math.floor(rarity.size * 2)
	for index = 1, shards do
		local angle = (index / shards) * math.pi * 2
		local shard = newEffectPart(Vector3.new(0.35, 0.35, 0.9), rarity.color)
		shard.CFrame = CFrame.new(position)
		local away = Vector3.new(math.cos(angle), 0.55, math.sin(angle)) * Config.Aura.BurstSpread
		TweenService:Create(shard, TweenInfo.new(life, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(position + away) * CFrame.Angles(angle, angle, 0),
			Transparency = 1,
			Size = Vector3.new(0.05, 0.05, 0.2),
		}):Play()
		Debris:AddItem(shard, life + 0.1)
	end
end

Shared.Remotes.Collect.OnClientEvent:Connect(function(position, rarityName)
	spawnBurst(position, Shared.rarity(rarityName))
end)

--------------------------------------------------------------------------
-- Auras: the ring of orbs that spins around somebody, either because they
-- just took a crystal or because they bought one in the store.
--------------------------------------------------------------------------

local auras = {}   -- [player] = { orbs, color, style, styleName, hidden }

local function isHidden(other)
	-- Vanish only hides the character itself. The aura and the trail are
	-- separate parts, so without this they would keep drawing a neat little
	-- marker over the exact spot a "hidden" player is standing.
	return other ~= player
		and (other:GetAttribute("VanishUntil") or 0) > workspace:GetServerTimeNow()
end

-- What aura this player should be wearing right now, if any: the one their
-- last crystal gave them, otherwise whatever they bought.
local function auraFor(other)
	if isHidden(other) then
		return nil
	end
	if (other:GetAttribute("AuraUntil") or 0) > workspace:GetServerTimeNow() then
		local rarity = Shared.rarity(other:GetAttribute("AuraRarity"))
		return rarity.color, rarity.aura or "Ring"
	end
	local bought = Shared.equipped(other, "Aura")
	if bought then
		return bought.color, bought.style or "Ring"
	end
	return nil
end

local function clearAura(other)
	local set = auras[other]
	if not set then
		return
	end
	for _, orb in ipairs(set.orbs) do
		orb:Destroy()
	end
	auras[other] = nil
end

local function buildAura(other, color, styleName)
	clearAura(other)

	local style = Shared.auraStyle(styleName)
	local scale = Shared.quality().auraScale
	local count = math.max(2, math.floor(style.orbs * scale + 0.5))

	local orbs = {}
	for index = 1, count do
		local size = Config.Aura.OrbSize * (style.size or 1)
		orbs[index] = newEffectPart(Vector3.new(size, size, size), color)
		orbs[index].Shape = Enum.PartType.Ball
	end
	if style.core then
		local size = Config.Aura.OrbSize * 1.5
		local core = newEffectPart(Vector3.new(size, size, size), color)
		core.Shape = Enum.PartType.Ball
		table.insert(orbs, core)
	end

	auras[other] = {
		orbs = orbs,
		color = color,
		style = style,
		styleName = styleName,
		hasCore = style.core == true,
		hidden = false,
	}
end

-- Runs on the slow tick: decides who should have an aura, what shape it is,
-- and whether they are close enough to be worth drawing at all.
local function refreshAuras(cameraPosition)
	local cullSquared = Shared.quality().auraDistance ^ 2

	for _, other in ipairs(Players:GetPlayers()) do
		local color, styleName = auraFor(other)
		local root = color and Shared.getRoot(other) or nil

		if not root then
			if auras[other] then
				clearAura(other)
			end
		else
			local set = auras[other]
			if not set or set.styleName ~= styleName then
				buildAura(other, color, styleName)
				set = auras[other]
			elseif set.color ~= color then
				set.color = color
				for _, orb in ipairs(set.orbs) do
					orb.Color = color
				end
			end

			-- Far away auras stop being drawn rather than being destroyed,
			-- so walking in and out of range does not churn parts.
			local offset = root.Position - cameraPosition
			local shouldHide = offset:Dot(offset) > cullSquared
			if shouldHide ~= set.hidden then
				set.hidden = shouldHide
				for _, orb in ipairs(set.orbs) do
					-- Not `shouldHide and nil or folder`: in Lua that always
					-- lands on folder, because the middle term is nil.
					if shouldHide then
						orb.Parent = nil
					else
						orb.Parent = folder
					end
				end
			end
		end
	end
end

-- Runs every frame, and does nothing but move parts that already exist.
local function positionAuras(clock)
	for other, set in pairs(auras) do
		if not set.hidden then
			local root = Shared.getRoot(other)
			if root then
				local style = set.style
				local count = #set.orbs
				local orbiting = set.hasCore and count - 1 or count
				local radius = style.radius or Config.Aura.Radius
				local baseHeight = style.height or Config.Aura.Height
				local rings = style.rings or 1

				for index, orb in ipairs(set.orbs) do
					if set.hasCore and index == count then
						-- The core sits above the head and breathes.
						orb.CFrame = CFrame.new(root.Position
							+ Vector3.new(0, baseHeight + 0.7 + math.sin(clock * 2.4) * 0.18, 0))
					else
						-- Odd rings turn the other way, which is what makes
						-- the Epic aura read as two rings and not six orbs.
						local ring = (index - 1) % rings
						local spin = style.spin * (ring % 2 == 0 and 1 or -1)
						local angle = clock * spin + (index / orbiting) * math.pi * 2
						orb.CFrame = CFrame.new(root.Position + Vector3.new(
							math.cos(angle) * radius,
							baseHeight + ring * 1.15 + math.sin(clock * 2 + index) * style.drift,
							math.sin(angle) * radius))
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------
-- Store cosmetics: trails and titles
--------------------------------------------------------------------------

local trails = {}   -- [player] = Trail

local function refreshTrail(other)
	local item = Shared.equipped(other, "Trail")
	local root = Shared.getRoot(other)
	local existing = trails[other]

	if not (item and root) then
		if existing then
			existing:Destroy()
			trails[other] = nil
		end
		return
	end

	-- Compare against the *current* root: after a respawn the old trail is
	-- still parented to the previous character's root, which is not nil.
	if not (existing and existing.Parent == root) then
		if existing then
			existing:Destroy()
		end
		local top = Instance.new("Attachment")
		top.Name = "CT_TrailTop"
		top.Position = Vector3.new(0, 0.8, 0)
		top.Parent = root

		local bottom = Instance.new("Attachment")
		bottom.Name = "CT_TrailBottom"
		bottom.Position = Vector3.new(0, -0.8, 0)
		bottom.Parent = root

		existing = Instance.new("Trail")
		existing.Attachment0 = top
		existing.Attachment1 = bottom
		existing.Lifetime = 0.45
		existing.LightEmission = 1
		existing.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
		existing.Parent = root
		trails[other] = existing
	end
	existing.Color = ColorSequence.new(item.color)
end

-- Other people's sprint key presses are not replicated, but their speed is,
-- so the trail keys off how fast they are actually moving.
local function updateTrails()
	for other, trail in pairs(trails) do
		local root = Shared.getRoot(other)
		trail.Enabled = root ~= nil
			and not isHidden(other)
			and root.AssemblyLinearVelocity.Magnitude > 19
	end
end

local titles = {}   -- [player] = BillboardGui

local function refreshTitle(other)
	local item = Shared.quality().titles and Shared.equipped(other, "Title") or nil
	local head = other.Character and other.Character:FindFirstChild("Head")
	local existing = titles[other]

	if not (item and head) then
		if existing then
			existing:Destroy()
			titles[other] = nil
		end
		return
	end

	if not (existing and existing.Parent) then
		existing = Instance.new("BillboardGui")
		existing.Name = "CT_Title"
		existing.Size = UDim2.fromOffset(150, 20)
		existing.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
		existing.AlwaysOnTop = false
		existing.MaxDistance = 90
		existing.Parent = folder

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 13
		label.TextStrokeTransparency = 0.4
		label.Parent = existing
		titles[other] = existing
	end

	existing.Adornee = head
	local label = existing:FindFirstChild("Label")
	if label then
		label.Text = item.text or item.name
		label.TextColor3 = item.color or Config.Colors.Neutral
	end
end

--------------------------------------------------------------------------
-- Who is chained to whom (rebuilt a few times a second, not every frame)
--------------------------------------------------------------------------

local pairsList = {}       -- { { owner = player, partner = player } }
local chainNeighbours = {} -- players chained to the local player

local function playerFromUserId(userId)
	if not userId or userId == 0 then
		return nil
	end
	for _, other in ipairs(Players:GetPlayers()) do
		if other.UserId == userId then
			return other
		end
	end
	return nil
end

local function rebuildRelationships()
	local phase = State:GetAttribute("Phase")
	-- Results is included so the chain and outlines stay up under the banner.
	local hunting = (phase == "Round" or phase == "Starting" or phase == "Results")
	local reveal = State:GetAttribute("EndgameReveal") == true
	local lastRunnerId = State:GetAttribute("LastRunnerUserId") or 0
	local localIsSeeker = Shared.isSeeker(player)
	-- Radar is our own ability, so it only ever lights runners up for us.
	local radar = localIsSeeker
		and (player:GetAttribute("RadarUntil") or 0) > workspace:GetServerTimeNow()

	table.clear(pairsList)
	table.clear(chainNeighbours)

	local seen = {}
	local beaconTarget

	for _, other in ipairs(Players:GetPlayers()) do
		local partner = playerFromUserId(other:GetAttribute("ChainedTo"))
		local inRound = Shared.inRound(other)

		-- Chain pairs
		if ChainConfig.Mode ~= "Off" and hunting and inRound and partner and partner ~= other then
			table.insert(pairsList, { owner = other, partner = partner })
			seen[other] = true
			if other == player then
				table.insert(chainNeighbours, partner)
			elseif partner == player then
				table.insert(chainNeighbours, other)
			end
		end

		-- Outlines
		if not hunting or not inRound or not other.Character then
			clearHighlight(other)
		elseif (other:GetAttribute("VanishUntil") or 0) > workspace:GetServerTimeNow() then
			-- Faded out. This is what makes Vanish the answer to Radar: a
			-- runner who timed it right is not on the sweep.
			clearHighlight(other)
		elseif other:GetAttribute("Immune") == true then
			-- Just broken out of the chain and briefly untouchable.
			setHighlight(other, Config.Colors.Good, true)
		elseif Shared.isSeeker(other) then
			setHighlight(other, Config.Colors.Seeker, false)
		elseif lastRunnerId == other.UserId and Config.LastRunnerBeacon then
			setHighlight(other, Config.Colors.Warn, true)
			beaconTarget = other
		elseif (reveal or radar) and localIsSeeker then
			setHighlight(other, Config.Colors.Runner, true)
		else
			clearHighlight(other)
		end
	end

	for owner in pairs(links) do
		if not seen[owner] then
			dropLinkSet(owner)
		end
	end

	local head = beaconTarget and beaconTarget.Character
		and beaconTarget.Character:FindFirstChild("Head")
	beacon.Adornee = head
	beacon.Enabled = head ~= nil

	-- Store cosmetics only change when somebody buys or equips something,
	-- so they are rebuilt here rather than every frame.
	for _, other in ipairs(Players:GetPlayers()) do
		refreshTrail(other)
		refreshTitle(other)
	end
end

Players.PlayerRemoving:Connect(function(leaving)
	dropLinkSet(leaving)
	clearHighlight(leaving)
	faded[leaving] = nil
	clearAura(leaving)
	if trails[leaving] then
		trails[leaving]:Destroy()
		trails[leaving] = nil
	end
	if titles[leaving] then
		titles[leaving]:Destroy()
		titles[leaving] = nil
	end
end)

--------------------------------------------------------------------------
-- Map props (spawned by MapEvents, animated here so the server never has
-- to replicate a spinning part sixty times a second)
--------------------------------------------------------------------------

local pickupParts = {}
local beaconParts = {}

local function refreshProps()
	pickupParts = CollectionService:GetTagged("ChainTagPickup")
	beaconParts = CollectionService:GetTagged("ChainTagBeacon")
end

task.spawn(function()
	while true do
		rebuildRelationships()
		refreshProps()
		task.wait(0.25)
	end
end)

--------------------------------------------------------------------------
-- Vanish
-- LocalTransparencyModifier only affects what this client draws, so fading
-- somebody out here changes nothing about where they actually are - they
-- can still be tagged while faded. Original transparencies are remembered
-- so a fade can be undone exactly, including on the face decal.
--------------------------------------------------------------------------

local originalCover = setmetatable({}, { __mode = "k" })   -- [decal] = transparency

local function setFade(character, amount)
	if not character then
		return
	end
	for _, item in ipairs(character:GetDescendants()) do
		if item:IsA("BasePart") then
			item.LocalTransparencyModifier = amount
		elseif item:IsA("Decal") or item:IsA("Texture") then
			if originalCover[item] == nil then
				originalCover[item] = item.Transparency
			end
			item.Transparency = amount > 0 and 1 or originalCover[item]
		end
	end
end

-- Walks a character's descendants, so it runs on the slow tick rather than
-- every frame. Re-applying while hidden is deliberate: it catches parts that
-- load in late, like accessories.
local function updateVanish()
	for _, other in ipairs(Players:GetPlayers()) do
		-- Never fade yourself out: you would lose track of your own
		-- character. The HUD tells you instead.
		local hide = isHidden(other) and other.Character ~= nil

		if hide then
			setFade(other.Character, Config.Abilities.Vanish.Transparency)
			faded[other] = true
		elseif faded[other] then
			setFade(other.Character, 0)
			faded[other] = nil
		end
	end
end

--------------------------------------------------------------------------
-- Per frame work
--------------------------------------------------------------------------

local function setLocalAttribute(name, value, epsilon)
	local current = player:GetAttribute(name)
	if epsilon and type(current) == "number" and type(value) == "number" then
		if math.abs(current - value) < epsilon then
			return
		end
	elseif current == value then
		return
	end
	player:SetAttribute(name, value)
end

-- Nearest seeker, for the edge glow and the heartbeat. Scans every player,
-- so it lives on the slow tick.
local function updateDanger()
	local danger = 0
	if Shared.getState("Phase") == "Round"
		and Shared.inRound(player)
		and not Shared.isSeeker(player)
	then
		local myRoot = Shared.getRoot(player)
		if myRoot then
			local nearest = math.huge
			for _, other in ipairs(Players:GetPlayers()) do
				if Shared.isSeeker(other) and Shared.inRound(other) then
					local otherRoot = Shared.getRoot(other)
					if otherRoot then
						nearest = math.min(nearest, (otherRoot.Position - myRoot.Position).Magnitude)
					end
				end
			end
			if nearest < Config.DangerRadius then
				local closeness = 1 - (nearest / Config.DangerRadius)
				danger = closeness * closeness   -- only really bites up close
			end
		end
	end
	setLocalAttribute("CT_Danger", danger, 0.02)
end

-- Everything that scans every player, or walks a character's descendants,
-- runs on this tick instead of every frame. Ten times a second is far more
-- often than any of it can actually be noticed, and it is six times less
-- work than the frame loop was doing before.
local SLOW_TICK = 0.1
local slowTimer = 0

RunService.RenderStepped:Connect(function(deltaTime)
	local clock = os.clock()
	local cameraPosition = camera.CFrame.Position
	local quality = Shared.quality()

	slowTimer -= deltaTime
	if slowTimer <= 0 then
		slowTimer = SLOW_TICK
		updateVanish()
		refreshAuras(cameraPosition)
		updateTrails()
		updateDanger()
	end

	-- Crystals spin and bob around the resting spot the server stamped on
	-- them. A hidden one sits at y = -500 and is skipped.
	for _, part in ipairs(pickupParts) do
		local base = part:GetAttribute("Base")
		if base and part.Transparency < 1 then
			local spin = part:GetAttribute("Spin") or 1.6
			part.CFrame = CFrame.new(base + Vector3.new(0, math.sin(clock * 2) * 0.4, 0))
				* CFrame.Angles(0.4, clock * spin, 0)
		end
	end

	-- The beacon ring breathes so it reads as live from across the park.
	for _, part in ipairs(beaconParts) do
		part.Transparency = 0.55 + math.sin(clock * 2.4) * 0.12
	end

	positionAuras(clock)

	-- Chains: draw the ones close enough to matter, park the rest.
	local renderDistanceSquared = quality.chainDistance * quality.chainDistance
	for _, link in ipairs(pairsList) do
		local ownerRoot = Shared.getRoot(link.owner)
		local partnerRoot = Shared.getRoot(link.partner)
		local set = getLinkSet(link.owner)

		if ownerRoot and partnerRoot then
			local from = anchorPoint(ownerRoot)
			local to = anchorPoint(partnerRoot)
			local offset = from - cameraPosition
			if offset:Dot(offset) <= renderDistanceSquared then
				setLinkSetShown(set, true)
				local bought = Shared.equipped(link.owner, "Chain")
				drawChain(set, from, to, bought and bought.color or ChainConfig.Color)
			else
				setLinkSetShown(set, false)
			end
		else
			setLinkSetShown(set, false)
		end
	end

	-- The leash is the one thing that has to be per frame: it feeds your
	-- walk speed, and at 10 Hz you would feel it stepping.
	local slow, taut = 1, false
	if ChainConfig.Mode == "Leash" and #chainNeighbours > 0 then
		local myRoot = Shared.getRoot(player)
		if myRoot then
			local worst = 0
			for _, neighbour in ipairs(chainNeighbours) do
				local otherRoot = Shared.getRoot(neighbour)
				if otherRoot then
					worst = math.max(worst, (otherRoot.Position - myRoot.Position).Magnitude)
				end
			end
			if worst > ChainConfig.SlowStart then
				local span = math.max(0.01, ChainConfig.MaxDistance - ChainConfig.SlowStart)
				local stretch = math.clamp((worst - ChainConfig.SlowStart) / span, 0, 1)
				slow = 1 - stretch * (1 - ChainConfig.MinSpeedFactor)
				taut = stretch >= 0.95
			end
		end
	end
	setLocalAttribute("CT_ChainSlow", slow, 0.01)
	setLocalAttribute("CT_ChainTaut", taut)
end)

print("[ChainTag] ChainVisuals loaded. Chain mode: " .. tostring(ChainConfig.Mode))
