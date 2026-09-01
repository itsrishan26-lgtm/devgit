--[[
	ChainService  -  ModuleScript  (NOT a Script - it has no code of its own
	                                that runs; other server scripts require it)
	WHERE IT GOES: ServerScriptService > ChainService

	The chain, and nothing else. Membership, order, tension, breaks and the
	speed the chain gives or takes away all live here, so no other script
	has to know how a chain works - they call in and read attributes back.

	THE SHAPE
	A line, not a tree. Member 1 is the original seeker; everyone caught is
	appended to the tail and linked to whoever is now in front of them. The
	old version linked you to whoever caught you, which made a branching
	shape that could never be drawn or reasoned about sensibly.

	THE CAP
	Four. Past that, a catch makes a Support Seeker instead: no chain, no
	formation bonus, but a much faster Radar. An eight-person chain is not
	twice as good as a four-person one, it is a conga line that cannot lose.

	THE BALANCE, WHICH IS THE WHOLE POINT
	A chain in formation moves FASTER than four loose seekers. So the chain
	is a prize the seekers have to keep hold of by moving as a unit, and a
	runner who baits them around opposite sides of a building takes that
	prize away. Without the bonus, being chained would be nothing but a
	penalty and breaking it would be doing the seeker team a favour.

	  together      formation bonus, everyone quick
	  drifting      bonus fades out
	  stretched     the chain drags, down to MinSpeedFactor
	  groaning      WARNING on everyone's screen
	  snapped       tail detaches into Support Seekers, the member who lost
	                their link recoils, the nearest runner is paid for it

	Server-authoritative on purpose: the client draws the chain, it does not
	decide who is on it, how fast they are, or when it breaks.

	ATTRIBUTES IT OWNS (all written here, read everywhere else)
	  ChainedTo    UserId of the player ahead of you, nil if you are first
	  ChainIndex   1..MaxLength, 0 if you are not in the chain
	  IsSupport    true for a Support Seeker
	  LinkStretch  0..1, how stretched YOUR link to the player ahead is
	  ChainMul     speed multiplier from the chain (<= 1)
	  ChainAdd     flat speed bonus from formation (>= 0)
	  ChainState   Formation | Drifting | Stretched | Warning | None
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config
local ChainConfig = Config.Chain

local ChainService = {}

local chain = {}          -- ordered list of players, 1 = the head
local support = {}        -- [player] = true
local overBreakSince = {} -- [player] = os.clock() their link went past breaking
local recoilUntil = {}    -- [player] = os.clock() their recoil ends
local refillAt = 0        -- earliest time a Support Seeker may be pulled in

--------------------------------------------------------------------------
-- Attribute plumbing
--------------------------------------------------------------------------

-- Every write here replicates to every client, and Update runs ten times a
-- second, so nothing is written unless it actually changed. Floats are
-- rounded first: a stretch value wobbling in the fourth decimal is not a
-- change worth telling twenty clients about.
local function setIfChanged(instance, name, value)
	if type(value) == "number" then
		value = math.floor(value * 100 + 0.5) / 100
	end
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function clearPlayerState(player)
	player:SetAttribute("ChainedTo", nil)
	player:SetAttribute("ChainIndex", 0)
	player:SetAttribute("LinkStretch", 0)
	player:SetAttribute("ChainMul", 1)
	player:SetAttribute("ChainAdd", 0)
	player:SetAttribute("ChainState", "None")
end

-- Rewrites index and link for every member. Cheap (at most four) and it
-- keeps the line correct no matter how it was edited.
local function reindex()
	for index, member in ipairs(chain) do
		setIfChanged(member, "ChainIndex", index)
		setIfChanged(member, "IsSupport", false)
		if index == 1 then
			setIfChanged(member, "ChainedTo", nil)
			setIfChanged(member, "LinkStretch", 0)
		else
			setIfChanged(member, "ChainedTo", chain[index - 1].UserId)
		end
	end
	Shared.setState("ChainLength", #chain)

	local supportCount = 0
	for _ in pairs(support) do
		supportCount += 1
	end
	Shared.setState("SupportCount", supportCount)
end

local function indexOf(player)
	return table.find(chain, player)
end

--------------------------------------------------------------------------
-- Membership
--------------------------------------------------------------------------

function ChainService.Reset()
	for _, player in ipairs(Players:GetPlayers()) do
		clearPlayerState(player)
		player:SetAttribute("IsSupport", false)
	end
	table.clear(chain)
	table.clear(support)
	table.clear(overBreakSince)
	table.clear(recoilUntil)
	refillAt = 0
	Shared.setState("ChainLength", 0)
	Shared.setState("SupportCount", 0)
end

-- The original seeker starts the chain as its head.
function ChainService.Start(seeker)
	ChainService.Reset()
	table.insert(chain, seeker)
	reindex()
end

function ChainService.IsSupport(player)
	return support[player] == true
end

function ChainService.Length()
	return #chain
end

-- Returns a copy, so callers cannot reorder the real chain by accident.
function ChainService.Members()
	return table.clone(chain)
end

-- Everyone the seeker team can teleport together: the chain itself.
function ChainService.Group()
	return table.clone(chain)
end

-- Called when a runner is caught. Returns "chained" or "support" so the
-- caller can tell the player which one happened to them.
function ChainService.Add(player)
	if indexOf(player) or support[player] then
		return support[player] and "support" or "chained"
	end

	if #chain < ChainConfig.MaxLength then
		table.insert(chain, player)
		support[player] = nil
		player:SetAttribute("IsSupport", false)
		reindex()
		return "chained"
	end

	support[player] = true
	clearPlayerState(player)
	player:SetAttribute("IsSupport", true)
	reindex()
	return "support"
end

-- Taking somebody out of the chain (rescued, left, or snapped off). Anyone
-- behind them closes up rather than being orphaned.
function ChainService.Remove(player)
	local index = indexOf(player)
	if index then
		table.remove(chain, index)
		refillAt = os.clock() + ChainConfig.RefillDelay
	end
	support[player] = nil
	overBreakSince[player] = nil
	recoilUntil[player] = nil
	clearPlayerState(player)
	player:SetAttribute("IsSupport", false)
	reindex()
end

-- A gap opened. Pull in the Support Seeker nearest the tail, once the
-- refill delay has passed, so a break actually buys the runners a window.
local function tryRefill()
	if #chain >= ChainConfig.MaxLength or os.clock() < refillAt then
		return
	end
	local tail = chain[#chain]
	local tailRoot = tail and Shared.getRoot(tail)
	if not tailRoot then
		return
	end

	local best, bestDistance = nil, math.huge
	for candidate in pairs(support) do
		if candidate.Parent and Shared.inRound(candidate) then
			local root = Shared.getRoot(candidate)
			if root then
				local distance = (root.Position - tailRoot.Position).Magnitude
				if distance < bestDistance then
					best, bestDistance = candidate, distance
				end
			end
		end
	end

	if best then
		support[best] = nil
		table.insert(chain, best)
		best:SetAttribute("IsSupport", false)
		reindex()
		Shared.toast(best.Name .. " joined the chain", "seeker")
	end
end

--------------------------------------------------------------------------
-- Breaking
--------------------------------------------------------------------------

-- Whoever forced it gets paid. Nearest runner to where the link snapped,
-- which is almost always the one who baited the two of them apart.
local function creditBreak(position)
	local best, bestDistance = nil, ChainConfig.BreakCreditRange
	for _, player in ipairs(Players:GetPlayers()) do
		if Shared.inRound(player) and not Shared.isSeeker(player) then
			local root = Shared.getRoot(player)
			if root then
				local distance = (root.Position - position).Magnitude
				if distance < bestDistance then
					best, bestDistance = player, distance
				end
			end
		end
	end
	return best
end

local function breakAt(index, position)
	-- Everyone from `index` back is snapped off into Support Seekers.
	local detached = {}
	for cut = #chain, index, -1 do
		local member = chain[cut]
		table.remove(chain, cut)
		table.insert(detached, member)
	end

	for _, member in ipairs(detached) do
		support[member] = true
		clearPlayerState(member)
		setIfChanged(member, "IsSupport", true)
		overBreakSince[member] = nil
	end

	-- The member still holding the front half takes the recoil: they were
	-- the one pulling, so they are the one who stumbles.
	local anchor = chain[#chain]
	if anchor then
		recoilUntil[anchor] = os.clock() + ChainConfig.RecoilTime
	end

	refillAt = os.clock() + ChainConfig.RefillDelay
	reindex()

	local runner = creditBreak(position)
	if runner then
		Shared.addStat(runner, "Points", ChainConfig.BreakPoints)
		Shared.addStat(runner, "ChainBreaks", 1)
		Shared.toast(runner.Name .. " snapped the chain", "rescue")
	else
		Shared.toast("The chain snapped", "warn")
	end

	if Shared.Remotes then
		Shared.Remotes.ChainBreak:FireAllClients(position, runner and runner.UserId or 0)
	end
end

--------------------------------------------------------------------------
-- The tick: tension, speed, breaks
--------------------------------------------------------------------------

-- Drops anyone who left, died out of the round, or stopped being a seeker.
local function prune()
	for index = #chain, 1, -1 do
		local member = chain[index]
		if not (member.Parent and Shared.inRound(member) and Shared.isSeeker(member)) then
			table.remove(chain, index)
			clearPlayerState(member)
			refillAt = os.clock() + ChainConfig.RefillDelay
		end
	end
	for member in pairs(support) do
		if not (member.Parent and Shared.inRound(member) and Shared.isSeeker(member)) then
			support[member] = nil
			setIfChanged(member, "IsSupport", false)
		end
	end
end

function ChainService.Update()
	prune()
	reindex()
	tryRefill()

	local now = os.clock()
	local worstState = "Formation"
	local breakIndex, breakPosition

	for index = 2, #chain do
		local member = chain[index]
		local ahead = chain[index - 1]
		local memberRoot = Shared.getRoot(member)
		local aheadRoot = Shared.getRoot(ahead)

		if memberRoot and aheadRoot then
			local distance = (memberRoot.Position - aheadRoot.Position).Magnitude

			-- Stretch runs 0 at formation range to 1 at breaking distance,
			-- and is what every client uses to colour the links.
			local span = math.max(1, ChainConfig.BreakDistance - ChainConfig.SlowStart)
			local stretch = math.clamp((distance - ChainConfig.SlowStart) / span, 0, 1)
			setIfChanged(member, "LinkStretch", stretch)

			if distance > ChainConfig.BreakDistance then
				local since = overBreakSince[member] or now
				overBreakSince[member] = since
				if now - since >= ChainConfig.BreakGrace and not breakIndex then
					breakIndex = index
					breakPosition = memberRoot.Position:Lerp(aheadRoot.Position, 0.5)
				end
				worstState = "Warning"
			else
				overBreakSince[member] = nil
				if distance > ChainConfig.WarnDistance then
					worstState = "Warning"
				elseif distance > ChainConfig.MaxDistance and worstState ~= "Warning" then
					worstState = "Stretched"
				elseif distance > ChainConfig.SlowStart
					and worstState ~= "Warning" and worstState ~= "Stretched"
				then
					worstState = "Drifting"
				end
			end
		else
			setIfChanged(member, "LinkStretch", 0)
			overBreakSince[member] = nil
		end
	end

	if breakIndex then
		breakAt(breakIndex, breakPosition)
		worstState = "None"
	end

	-- One state for the whole chain, so every member sees the same warning
	-- and the HUD never disagrees with itself between two players.
	for index, member in ipairs(chain) do
		setIfChanged(member, "ChainState", #chain > 1 and worstState or "None")

		local multiplier, bonus = 1, 0
		if #chain > 1 then
			-- The stretch that matters to you is the worse of your own link
			-- and the link of whoever is behind you: both ends feel it.
			local mine = member:GetAttribute("LinkStretch") or 0
			local behind = chain[index + 1]
			local theirs = behind and behind:GetAttribute("LinkStretch") or 0
			local stretch = math.max(mine, theirs)

			local formationEnd = (ChainConfig.MaxDistance - ChainConfig.SlowStart)
				/ math.max(1, ChainConfig.BreakDistance - ChainConfig.SlowStart)

			if stretch <= 0 then
				bonus = ChainConfig.FormationBonus
			elseif stretch < formationEnd then
				bonus = ChainConfig.FormationBonus * (1 - stretch / formationEnd)
			else
				local drag = (stretch - formationEnd) / math.max(0.01, 1 - formationEnd)
				multiplier = 1 - drag * (1 - ChainConfig.MinSpeedFactor)
			end
		end

		if (recoilUntil[member] or 0) > now then
			multiplier = math.min(multiplier, ChainConfig.RecoilFactor)
			bonus = 0
		end

		setIfChanged(member, "ChainMul", multiplier)
		setIfChanged(member, "ChainAdd", bonus)
	end

	-- Support Seekers carry no chain penalty and no bonus.
	for member in pairs(support) do
		setIfChanged(member, "ChainMul", (recoilUntil[member] or 0) > now
			and ChainConfig.RecoilFactor or 1)
		setIfChanged(member, "ChainAdd", 0)
		setIfChanged(member, "ChainState", "None")
	end
end

-- Called when the hunt ends. Keeps the chain on screen for the results
-- banner but stops it affecting anybody's speed - otherwise a round that
-- ended mid-stretch leaves two seekers crawling through the whole payoff.
function ChainService.Relax()
	for _, member in ipairs(chain) do
		setIfChanged(member, "ChainMul", 1)
		setIfChanged(member, "ChainAdd", 0)
		setIfChanged(member, "ChainState", "None")
		setIfChanged(member, "LinkStretch", 0)
	end
	for member in pairs(support) do
		setIfChanged(member, "ChainMul", 1)
		setIfChanged(member, "ChainAdd", 0)
	end
	table.clear(overBreakSince)
	table.clear(recoilUntil)
end

Players.PlayerRemoving:Connect(function(player)
	ChainService.Remove(player)
end)

return ChainService
