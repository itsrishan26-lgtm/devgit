--[[
	ChainTagShared  -  ModuleScript
	WHERE IT GOES: ReplicatedStorage > ChainTagShared
	The name must match EXACTLY.

	One module required by every other script. It:
	  * builds the RemoteEvents and the replicated state folder (server side)
	  * waits for them (client side)
	  * holds the helpers both server scripts need, so nothing is copy-pasted twice

	HOW STATE REACHES THE CLIENT
	Instead of firing a RemoteEvent every second for the timer, the server
	writes attributes onto ReplicatedStorage.ChainTagState. Attributes replicate
	automatically and the client listens with GetAttributeChangedSignal, so the
	HUD stays in sync with zero network chatter.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("ChainTagConfig"))

-- Every section ChainTagConfig is expected to have. Mixing an old config
-- with newer scripts otherwise dies somewhere in the middle of building the
-- HUD with "attempt to index nil", which says nothing useful about the real
-- problem: one file did not get copied in with the rest.
local REQUIRED_CONFIG = {
	"Speeds", "Stamina", "Chain", "Colors", "Sounds", "Points",
	"Map", "Pickups", "Beacon", "Rescue", "Abilities", "Levels", "Combo",
	"Rarities", "Aura", "Shop", "Quality", "Heartbeat", "Music",
}

do
	local missing = {}
	for _, name in ipairs(REQUIRED_CONFIG) do
		if type(Config[name]) ~= "table" then
			table.insert(missing, "Config." .. name)
		end
	end
	if #missing > 0 then
		error("[ChainTag] ChainTagConfig is older than the other scripts - it has no " ..
			table.concat(missing, ", ") .. ". Copy ChainTagConfig in again from the same " ..
			"place you got the rest of the files, then press Play again.", 0)
	end
end

local Shared = {}
Shared.Config = Config

local IS_SERVER = RunService:IsServer()

-- Remote names created under ReplicatedStorage.ChainTagRemotes.
local REMOTE_NAMES = { "CatchCountdown", "Toast", "UseAbility", "Popup", "Collect", "Shop", "Settings", "ChainBreak" }

-- Default values for every replicated state attribute. Listing them here means
-- the client never reads a nil attribute, so the HUD is correct on frame one.
local STATE_DEFAULTS = {
	Phase = "Waiting",          -- Waiting | Intermission | Starting | Round | Results
	PhaseEndsAt = 0,            -- server clock time the phase ends (0 = no timer)
	RunnersLeft = 0,
	TotalRunners = 0,
	SeekerCount = 0,
	PlayersNeeded = Config.MinPlayers,
	EndgameReveal = false,
	LastRunnerUserId = 0,
	CatchesInProgress = 0,
	Winner = "",                -- "" | "Seekers" | "Runners" | "None"
	ResultText = "",
	SoloPractice = false,
	BeaconActive = false,       -- set by MapEvents
	BeaconPosition = Vector3.zero,
	ChainLength = 0,            -- set by ChainService
	SupportCount = 0,
}

--------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------

if IS_SERVER then
	local remotes = ReplicatedStorage:FindFirstChild("ChainTagRemotes")
	if not remotes then
		remotes = Instance.new("Folder")
		remotes.Name = "ChainTagRemotes"
		remotes.Parent = ReplicatedStorage
	end
	for _, name in ipairs(REMOTE_NAMES) do
		if not remotes:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = remotes
		end
	end

	local state = ReplicatedStorage:FindFirstChild("ChainTagState")
	if not state then
		state = Instance.new("Folder")
		state.Name = "ChainTagState"
		state.Parent = ReplicatedStorage
	end
	for key, value in pairs(STATE_DEFAULTS) do
		if state:GetAttribute(key) == nil then
			state:SetAttribute(key, value)
		end
	end

	Shared.Remotes = remotes
	Shared.State = state
else
	Shared.Remotes = ReplicatedStorage:WaitForChild("ChainTagRemotes", 30)
	Shared.State = ReplicatedStorage:WaitForChild("ChainTagState", 30)
	if not Shared.Remotes or not Shared.State then
		warn("[ChainTag] Client could not find ChainTagRemotes/ChainTagState. " ..
			"Is ServerScriptService.GameSetup present and enabled?")
	end
end

--------------------------------------------------------------------------
-- Small helpers used on both sides
--------------------------------------------------------------------------

function Shared.log(...)
	if Config.Debug then
		print("[ChainTag]", ...)
	end
end

-- 95 -> "1:35"
function Shared.formatTime(seconds)
	seconds = math.max(0, math.floor((seconds or 0) + 0.5))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Shared.getState(key)
	local state = Shared.State
	if not state then
		return nil
	end
	return state:GetAttribute(key)
end

-- Seconds left in the current phase, using the clock the server and every
-- client agree on. Returns 0 when the phase has no timer.
function Shared.timeLeft()
	local endsAt = Shared.getState("PhaseEndsAt") or 0
	if endsAt <= 0 then
		return 0
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

-- Levels come from TotalPoints - everything a player has ever earned - and
-- never from the Points they can spend in the store, so buying a trail can
-- never cost you a level. 2 at 40, 3 at 160, 4 at 360. Both sides work it
-- out the same way so they can never disagree.
function Shared.levelFromPoints(points)
	return 1 + math.floor(math.sqrt(math.max(0, points or 0) / Config.Levels.PointsPerLevel))
end

-- Player settings travel as one short string on the Settings attribute, so
-- they replicate like anything else and save with the rest of the profile.
--   q     quality level, 0 meaning auto-detect
--   mus   music volume 0-100
--   sfx   effect volume 0-100
--   shake screen shake on or off
local SETTING_DEFAULTS = { q = 0, mus = 100, sfx = 100, shake = 1 }

function Shared.parseSettings(text)
	local parsed = table.clone(SETTING_DEFAULTS)
	for key, value in string.gmatch(tostring(text or ""), "(%a+)=(%d+)") do
		if parsed[key] ~= nil then
			parsed[key] = tonumber(value) or parsed[key]
		end
	end
	parsed.q = math.clamp(parsed.q, 0, #Config.Quality.Levels)
	parsed.mus = math.clamp(parsed.mus, 0, 100)
	parsed.sfx = math.clamp(parsed.sfx, 0, 100)
	parsed.shake = math.clamp(parsed.shake, 0, 1)
	return parsed
end

function Shared.serializeSettings(parsed)
	return string.format("q=%d;mus=%d;sfx=%d;shake=%d",
		parsed.q or 0, parsed.mus or 100, parsed.sfx or 100, parsed.shake or 1)
end

function Shared.auraStyle(name)
	return Config.Aura.Styles[name] or Config.Aura.Styles.Ring
end

function Shared.playerLevel(player)
	--------------------------------------------------------------------------
-- Client-only: one place that makes every noise in the game
--------------------------------------------------------------------------

if not IS_SERVER then
	local SoundService = game:GetService("SoundService")
	local localPlayer = Players.LocalPlayer

	-- Parsing a settings string every frame would be exactly the kind of
	-- waste this pass is meant to remove, so it is cached and thrown away
	-- only when something actually changes it.
	local cachedSettings, cachedQuality

	local function invalidate()
		cachedSettings, cachedQuality = nil, nil
	end

	localPlayer:GetAttributeChangedSignal("Settings"):Connect(invalidate)
	localPlayer:GetAttributeChangedSignal("CT_AutoQuality"):Connect(invalidate)

	function Shared.settings()
		if not cachedSettings then
			cachedSettings = Shared.parseSettings(localPlayer:GetAttribute("Settings"))
		end
		return cachedSettings
	end

	-- The quality level this client is actually drawing at, resolving 0
	-- (auto) through whatever the frame-time sample decided.
	function Shared.quality()
		if not cachedQuality then
			local chosen = Shared.settings().q
			if chosen == 0 then
				chosen = localPlayer:GetAttribute("CT_AutoQuality") or #Config.Quality.Levels
			end
			cachedQuality = Config.Quality.Levels[chosen]
				or Config.Quality.Levels[#Config.Quality.Levels]
		end
		return cachedQuality
	end

	-- Plays a cue from Config.Sounds.Cues. A cue with `chord` plays its
	-- pitches in quick succession, which is what separates "you picked
	-- something up" from "you picked something rare up".
	function Shared.playCue(cueName, volumeScale)
		local cue = Config.Sounds.Cues[cueName]
		if not cue or Config.Sounds.Blip == "" then
			return
		end
		local master = Shared.settings().sfx / 100
		if master <= 0 then
			return
		end
		local pitches = cue.chord or { cue.pitch or 1 }
		for index, pitch in ipairs(pitches) do
			task.delay((index - 1) * Config.Sounds.ChordGap, function()
				local sound = Instance.new("Sound")
				sound.SoundId = cue.soundId or Config.Sounds.Blip
				sound.PlaybackSpeed = pitch
				sound.Volume = (cue.volume or 0.3) * (volumeScale or 1) * master
				sound.Parent = SoundService
				SoundService:PlayLocalSound(sound)
				task.delay(3, function()
					sound:Destroy()
				end)
			end)
		end
	end
end

return Shared.levelFromPoints(player and player:GetAttribute("TotalPoints") or 0)
end

-- Weighted roll down the rarity ladder in ChainTagConfig.
function Shared.rollRarity()
	local total = 0
	for _, rarity in ipairs(Config.Rarities) do
		total += rarity.weight
	end
	local roll = math.random() * total
	for _, rarity in ipairs(Config.Rarities) do
		roll -= rarity.weight
		if roll <= 0 then
			return rarity
		end
	end
	return Config.Rarities[1]
end

function Shared.rarity(name)
	for _, rarity in ipairs(Config.Rarities) do
		if rarity.name == name then
			return rarity
		end
	end
	return Config.Rarities[1]
end

function Shared.shopItem(id)
	if not id or id == "" then
		return nil
	end
	for _, item in ipairs(Config.Shop.Items) do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- Owned items ride along as one comma separated string, because an
-- attribute cannot hold a table and this has to replicate to the client.
function Shared.ownedSet(player)
	local owned = {}
	for id in string.gmatch(player:GetAttribute("OwnedItems") or "", "[^,]+") do
		owned[id] = true
	end
	return owned
end

function Shared.owns(player, id)
	--------------------------------------------------------------------------
-- Client-only: one place that makes every noise in the game
--------------------------------------------------------------------------

if not IS_SERVER then
	local SoundService = game:GetService("SoundService")
	local localPlayer = Players.LocalPlayer

	-- Parsing a settings string every frame would be exactly the kind of
	-- waste this pass is meant to remove, so it is cached and thrown away
	-- only when something actually changes it.
	local cachedSettings, cachedQuality

	local function invalidate()
		cachedSettings, cachedQuality = nil, nil
	end

	localPlayer:GetAttributeChangedSignal("Settings"):Connect(invalidate)
	localPlayer:GetAttributeChangedSignal("CT_AutoQuality"):Connect(invalidate)

	function Shared.settings()
		if not cachedSettings then
			cachedSettings = Shared.parseSettings(localPlayer:GetAttribute("Settings"))
		end
		return cachedSettings
	end

	-- The quality level this client is actually drawing at, resolving 0
	-- (auto) through whatever the frame-time sample decided.
	function Shared.quality()
		if not cachedQuality then
			local chosen = Shared.settings().q
			if chosen == 0 then
				chosen = localPlayer:GetAttribute("CT_AutoQuality") or #Config.Quality.Levels
			end
			cachedQuality = Config.Quality.Levels[chosen]
				or Config.Quality.Levels[#Config.Quality.Levels]
		end
		return cachedQuality
	end

	-- Plays a cue from Config.Sounds.Cues. A cue with `chord` plays its
	-- pitches in quick succession, which is what separates "you picked
	-- something up" from "you picked something rare up".
	function Shared.playCue(cueName, volumeScale)
		local cue = Config.Sounds.Cues[cueName]
		if not cue or Config.Sounds.Blip == "" then
			return
		end
		local master = Shared.settings().sfx / 100
		if master <= 0 then
			return
		end
		local pitches = cue.chord or { cue.pitch or 1 }
		for index, pitch in ipairs(pitches) do
			task.delay((index - 1) * Config.Sounds.ChordGap, function()
				local sound = Instance.new("Sound")
				sound.SoundId = cue.soundId or Config.Sounds.Blip
				sound.PlaybackSpeed = pitch
				sound.Volume = (cue.volume or 0.3) * (volumeScale or 1) * master
				sound.Parent = SoundService
				SoundService:PlayLocalSound(sound)
				task.delay(3, function()
					sound:Destroy()
				end)
			end)
		end
	end
end

return Shared.ownedSet(player)[id] == true
end

function Shared.equipped(player, kind)
	--------------------------------------------------------------------------
-- Client-only: one place that makes every noise in the game
--------------------------------------------------------------------------

if not IS_SERVER then
	local SoundService = game:GetService("SoundService")
	local localPlayer = Players.LocalPlayer

	-- Parsing a settings string every frame would be exactly the kind of
	-- waste this pass is meant to remove, so it is cached and thrown away
	-- only when something actually changes it.
	local cachedSettings, cachedQuality

	local function invalidate()
		cachedSettings, cachedQuality = nil, nil
	end

	localPlayer:GetAttributeChangedSignal("Settings"):Connect(invalidate)
	localPlayer:GetAttributeChangedSignal("CT_AutoQuality"):Connect(invalidate)

	function Shared.settings()
		if not cachedSettings then
			cachedSettings = Shared.parseSettings(localPlayer:GetAttribute("Settings"))
		end
		return cachedSettings
	end

	-- The quality level this client is actually drawing at, resolving 0
	-- (auto) through whatever the frame-time sample decided.
	function Shared.quality()
		if not cachedQuality then
			local chosen = Shared.settings().q
			if chosen == 0 then
				chosen = localPlayer:GetAttribute("CT_AutoQuality") or #Config.Quality.Levels
			end
			cachedQuality = Config.Quality.Levels[chosen]
				or Config.Quality.Levels[#Config.Quality.Levels]
		end
		return cachedQuality
	end

	-- Plays a cue from Config.Sounds.Cues. A cue with `chord` plays its
	-- pitches in quick succession, which is what separates "you picked
	-- something up" from "you picked something rare up".
	function Shared.playCue(cueName, volumeScale)
		local cue = Config.Sounds.Cues[cueName]
		if not cue or Config.Sounds.Blip == "" then
			return
		end
		local master = Shared.settings().sfx / 100
		if master <= 0 then
			return
		end
		local pitches = cue.chord or { cue.pitch or 1 }
		for index, pitch in ipairs(pitches) do
			task.delay((index - 1) * Config.Sounds.ChordGap, function()
				local sound = Instance.new("Sound")
				sound.SoundId = cue.soundId or Config.Sounds.Blip
				sound.PlaybackSpeed = pitch
				sound.Volume = (cue.volume or 0.3) * (volumeScale or 1) * master
				sound.Parent = SoundService
				SoundService:PlayLocalSound(sound)
				task.delay(3, function()
					sound:Destroy()
				end)
			end)
		end
	end
end

return Shared.shopItem(player:GetAttribute("Equipped" .. kind))
end

function Shared.isSeeker(player)
	return player and player:GetAttribute("IsSeeker") == true
end

function Shared.inRound(player)
	return player and player:GetAttribute("InRound") == true
end

function Shared.getRoot(player)
	local character = player and player.Character
	if not character then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	return root, humanoid, character
end

-- Finds a spawn pad by name anywhere in Workspace (top level first, then a
-- deep search so it still works if the map got grouped into a Model).
function Shared.findSpawn(name)
	local direct = workspace:FindFirstChild(name)
	if direct and direct:IsA("BasePart") then
		return direct
	end
	local deep = workspace:FindFirstChild(name, true)
	if deep and deep:IsA("BasePart") then
		return deep
	end
	return nil
end

-- Spreads players out in rings around a spawn pad so nobody stacks on
-- anybody's head. index is 1-based and stable per player.
function Shared.spawnCFrame(spawnPart, index)
	local perRing = Config.SpawnSlotsPerRing
	local ring = math.floor((index - 1) / perRing)
	local slot = (index - 1) % perRing
	local radius = Config.SpawnRingRadius + ring * Config.SpawnRingSpacing
	local angle = (slot / perRing) * math.pi * 2 + ring * 0.4

	local flat = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local position = spawnPart.Position
		+ flat * radius
		+ Vector3.new(0, spawnPart.Size.Y * 0.5 + 4, 0)

	-- Face outwards, away from the pad, so runners are already pointed at the map.
	return CFrame.lookAt(position, position + flat * 10)
end

--------------------------------------------------------------------------
-- Server-only helpers (shared by GameSetup and CatchDetection)
--------------------------------------------------------------------------

if IS_SERVER then
	local jumpDefaults = setmetatable({}, { __mode = "k" })

	local function rememberJump(humanoid)
		if jumpDefaults[humanoid] == nil then
			jumpDefaults[humanoid] = {
				height = humanoid.JumpHeight,
				power = humanoid.JumpPower,
			}
		end
		return jumpDefaults[humanoid]
	end

	function Shared.setState(key, value)
		if Shared.State and Shared.State:GetAttribute(key) ~= value then
			Shared.State:SetAttribute(key, value)
		end
	end

	function Shared.baseWalkSpeed(player)
		if Shared.isSeeker(player) then
			return Config.Speeds.SeekerWalk
		end
		return Config.Speeds.RunnerWalk
	end

	-- The client movement script owns WalkSpeed frame to frame; this is the
	-- baseline the server sets so things are sane before that script runs.
	function Shared.applyBaseSpeed(player)
		local _, humanoid = Shared.getRoot(player)
		if humanoid then
			humanoid.WalkSpeed = Shared.baseWalkSpeed(player)
		end
	end

	-- Freezing is done with an attribute so the client movement script
	-- cooperates instead of fighting the server over WalkSpeed every frame.
	function Shared.setFrozen(player, frozen)
		player:SetAttribute("Frozen", frozen and true or false)

		local _, humanoid = Shared.getRoot(player)
		if not humanoid then
			return
		end
		local defaults = rememberJump(humanoid)
		if frozen then
			humanoid.WalkSpeed = 0
			humanoid.JumpHeight = 0
			humanoid.JumpPower = 0
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
		else
			humanoid.JumpHeight = defaults.height
			humanoid.JumpPower = defaults.power
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
			humanoid.WalkSpeed = Shared.baseWalkSpeed(player)
		end
	end

	-- Used only for the 3 second catch countdown: anchoring is the one way to
	-- guarantee nobody slides, falls or gets flung while the timer plays.
	function Shared.setAnchored(player, anchored)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		if anchored then
			root.Anchored = true
		else
			root.Anchored = false
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			pcall(function()
				root:SetNetworkOwnershipAuto()
			end)
		end
	end

	function Shared.teleportTo(player, spawnPart, index)
		local character = player.Character
		if not (character and spawnPart) then
			return false
		end
		if not character:FindFirstChild("HumanoidRootPart") then
			return false
		end
		character:PivotTo(Shared.spawnCFrame(spawnPart, index or 1))
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
		return true
	end

	-- Old versions of this game welded real chain parts onto the character.
	-- If a place still has them lying around, get rid of them on respawn.
	function Shared.clearLegacyChain(character)
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		for _, name in ipairs({ "ChainLinks", "ChainRope", "ChainAtt" }) do
			for _, child in ipairs(root:GetChildren()) do
				if child.Name == name then
					child:Destroy()
				end
			end
		end
	end

	function Shared.addStat(player, statName, amount)
		local stats = player:FindFirstChild("leaderstats")
		local value = stats and stats:FindFirstChild(statName)
		if value then
			value.Value = value.Value + amount
			if statName == "Points" and amount > 0 then
				-- Lifetime total, for levels. Points itself is a balance the
				-- store spends down; this only ever climbs.
				player:SetAttribute("TotalPoints", (player:GetAttribute("TotalPoints") or 0) + amount)
				-- And it floats up the screen, wherever it came from.
				if Shared.Remotes then
					Shared.Remotes.Popup:FireClient(player, "+" .. amount)
				end
			end
			return
		end
		-- Stats not shown on the player list (Wins, Survivals, RoundsPlayed)
		-- ride along as attributes and get saved with the rest.
		player:SetAttribute(statName, (player:GetAttribute(statName) or 0) + amount)
	end

	function Shared.toast(text, kind)
		if Shared.Remotes then
			Shared.Remotes.Toast:FireAllClients(text, kind or "info")
		end
	end
end

--------------------------------------------------------------------------
-- Client-only: one place that makes every noise in the game
--------------------------------------------------------------------------

if not IS_SERVER then
	local SoundService = game:GetService("SoundService")
	local localPlayer = Players.LocalPlayer

	-- Parsing a settings string every frame would be exactly the kind of
	-- waste this pass is meant to remove, so it is cached and thrown away
	-- only when something actually changes it.
	local cachedSettings, cachedQuality

	local function invalidate()
		cachedSettings, cachedQuality = nil, nil
	end

	localPlayer:GetAttributeChangedSignal("Settings"):Connect(invalidate)
	localPlayer:GetAttributeChangedSignal("CT_AutoQuality"):Connect(invalidate)

	function Shared.settings()
		if not cachedSettings then
			cachedSettings = Shared.parseSettings(localPlayer:GetAttribute("Settings"))
		end
		return cachedSettings
	end

	-- The quality level this client is actually drawing at, resolving 0
	-- (auto) through whatever the frame-time sample decided.
	function Shared.quality()
		if not cachedQuality then
			local chosen = Shared.settings().q
			if chosen == 0 then
				chosen = localPlayer:GetAttribute("CT_AutoQuality") or #Config.Quality.Levels
			end
			cachedQuality = Config.Quality.Levels[chosen]
				or Config.Quality.Levels[#Config.Quality.Levels]
		end
		return cachedQuality
	end

	-- Plays a cue from Config.Sounds.Cues. A cue with `chord` plays its
	-- pitches in quick succession, which is what separates "you picked
	-- something up" from "you picked something rare up".
	function Shared.playCue(cueName, volumeScale)
		local cue = Config.Sounds.Cues[cueName]
		if not cue or Config.Sounds.Blip == "" then
			return
		end
		local master = Shared.settings().sfx / 100
		if master <= 0 then
			return
		end
		local pitches = cue.chord or { cue.pitch or 1 }
		for index, pitch in ipairs(pitches) do
			task.delay((index - 1) * Config.Sounds.ChordGap, function()
				local sound = Instance.new("Sound")
				sound.SoundId = cue.soundId or Config.Sounds.Blip
				sound.PlaybackSpeed = pitch
				sound.Volume = (cue.volume or 0.3) * (volumeScale or 1) * master
				sound.Parent = SoundService
				SoundService:PlayLocalSound(sound)
				task.delay(3, function()
					sound:Destroy()
				end)
			end)
		end
	end
end

return Shared
