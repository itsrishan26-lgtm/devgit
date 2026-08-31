--[[
	ChainVisuals  —  LocalScript
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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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
	if not set then
		local parts = {}
		for index = 1, ChainConfig.Links do
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

local function drawChain(set, fromPosition, toPosition)
	local count = #set.parts
	local sag = ChainConfig.Sag
	local step = 1 / (count + 1)

	local function samplePoint(t)
		return fromPosition:Lerp(toPosition, t) - Vector3.new(0, math.sin(t * math.pi) * sag, 0)
	end

	for index, part in ipairs(set.parts) do
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
		elseif Shared.isSeeker(other) then
			setHighlight(other, Config.Colors.Seeker, false)
		elseif lastRunnerId == other.UserId and Config.LastRunnerBeacon then
			setHighlight(other, Config.Colors.Warn, true)
			beaconTarget = other
		elseif reveal and localIsSeeker then
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
end

Players.PlayerRemoving:Connect(function(leaving)
	dropLinkSet(leaving)
	clearHighlight(leaving)
end)

task.spawn(function()
	while true do
		rebuildRelationships()
		task.wait(0.25)
	end
end)

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

RunService.RenderStepped:Connect(function()
	local cameraPosition = camera.CFrame.Position
	local renderDistanceSquared = ChainConfig.RenderDistance * ChainConfig.RenderDistance

	-- 1. Draw every chain that is close enough to be worth drawing.
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
				drawChain(set, from, to)
			else
				setLinkSetShown(set, false)
			end
		else
			setLinkSetShown(set, false)
		end
	end

	-- 2. How hard is the chain pulling on me?
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

	-- 3. How close is the nearest seeker? (runners only, during the hunt)
	local danger = 0
	if State:GetAttribute("Phase") == "Round"
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
end)

print("[ChainTag] ChainVisuals loaded. Chain mode: " .. tostring(ChainConfig.Mode))
