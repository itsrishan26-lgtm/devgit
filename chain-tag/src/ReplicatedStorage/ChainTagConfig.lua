--[[
	ChainTagConfig  -  ModuleScript
	WHERE IT GOES: ReplicatedStorage > ChainTagConfig
	The name must match EXACTLY (no spaces, capital C, capital T, capital C).

	Every number you might want to tweak lives in this one file. Nothing else
	needs editing to rebalance the game - change a value here, press Play.
--]]

local Config = {}

--------------------------------------------------------------------------
-- ROUND FLOW (all times in seconds)
--------------------------------------------------------------------------

-- How many players before a real round can start.
-- Set to 1 while testing alone: you get a solo practice round (no seeker).
Config.MinPlayers = 2

Config.Intermission = 12     -- lobby time between rounds
Config.HeadStart = 8         -- seekers are frozen this long at round start
Config.RoundLength = 120     -- length of the hunt itself
Config.ResultsTime = 8       -- how long the win/lose banner stays up
Config.RespawnTime = 3       -- Roblox default is 5s; a shorter one keeps rounds moving

-- When this many seconds are left, every remaining runner is outlined
-- through walls for the seeker team. Stops endgame hide-and-seek stalls.
Config.EndgameRevealAt = 30

-- When one runner is left, everybody gets a "LAST RUNNER" marker on them.
Config.LastRunnerBeacon = true

--------------------------------------------------------------------------
-- CATCHING
--------------------------------------------------------------------------

Config.CatchRadius = 6        -- studs between root parts that counts as a tag
Config.CatchTickRate = 0.1    -- how often the server checks (10x a second)
Config.CatchCooldown = 1.25   -- per-seeker delay before they can tag again
Config.CatchCountdown = 3     -- red 3-2-1 shown to everyone on a catch
Config.RequireLineOfSight = true  -- no tagging through walls
Config.TeleportOnCatch = true     -- both players return to Seeker Spawn after the countdown

--------------------------------------------------------------------------
-- SPAWNS
-- These MUST match the SpawnLocation names in Workspace exactly,
-- including the space in the middle.
--------------------------------------------------------------------------

Config.SeekerSpawnName = "Seeker Spawn"
Config.RunnerSpawnName = "Runner Spawn"

Config.SpawnRingRadius = 10   -- first ring of spawn slots, in studs
Config.SpawnRingSpacing = 6   -- extra studs per additional ring
Config.SpawnSlotsPerRing = 8

--------------------------------------------------------------------------
-- MOVEMENT
-- Seekers are a touch faster than runners so a chase actually closes.
-- Runners get the bigger stamina pool, so they win by managing it.
--------------------------------------------------------------------------

Config.Speeds = {
	RunnerWalk = 16,
	RunnerSprint = 24,
	SeekerWalk = 17,
	SeekerSprint = 25,
	Smoothing = 9,   -- higher = snappier acceleration
	SprintFov = 6,   -- extra field of view while sprinting
}

Config.Stamina = {
	Max = 100,
	Drain = 20,        -- per second while sprinting
	Regen = 14,        -- per second while recovering
	RegenDelay = 0.7,  -- pause before regen starts
	MinToRestart = 15, -- after hitting empty you need this much to sprint again
	RunnerBonus = 25,  -- runners get this much extra max stamina
}

--------------------------------------------------------------------------
-- THE CHAIN
--   "Leash"  - chained players slow each other down when they drift apart
--              and a chain is drawn between them (recommended)
--   "Visual" - chain is drawn, but never slows anyone
--   "Off"    - no chain at all
--
-- Note: this is a *simulated* leash, not a RopeConstraint. Physical ropes
-- between two player characters fight over network ownership and fling
-- people across the map. This version never touches physics.
--------------------------------------------------------------------------

Config.Chain = {
	Mode = "Leash",
	SlowStart = 14,        -- studs apart before the chain starts to bite
	MaxDistance = 22,      -- studs where the chain is fully taut
	MinSpeedFactor = 0.3,  -- slowest you can be dragged down to
	Links = 7,
	LinkSize = Vector3.new(0.45, 0.45, 0.95),
	Color = Color3.fromRGB(148, 151, 158),
	Sag = 2.5,             -- how far the chain droops in the middle
	RenderDistance = 220,  -- chains further than this are not drawn
}

--------------------------------------------------------------------------
-- THE MAP
-- Pickups and beacons find their own ground by raycasting downwards, so
-- they work on any map without you marking or tagging a single part.
-- Radius is measured out from Center; keep it inside your grass so nothing
-- spawns in the water.
--------------------------------------------------------------------------

Config.Map = {
	Center = Vector3.new(0, 0, 0),
	Radius = 170,
	ScanHeight = 300,     -- raycasts start this high and look straight down
	MinSpacing = 30,      -- studs between two spawned things
	MinGroundNormal = 0.75, -- how flat a surface has to be to count as ground
}

-- Glowing crystals scattered around the park. Runners get their stamina
-- back plus a short burst of speed; seekers get a smaller burst. Both sides
-- want them, so they become places worth fighting over.
Config.Pickups = {
	Enabled = true,
	Count = 8,
	RespawnTime = 22,     -- a taken pickup comes back somewhere new
	Radius = 6,
	Hover = 3,
	SeekerScale = 0.6,    -- seekers get this fraction of the speed reward
}

-- Rarity ladder. Weights are picked so Common and Rare feel like scenery,
-- Epic feels like a find, and Legendary is a genuine event - it announces
-- itself to the whole server when it lands, so people race for it.
-- Colour is the only thing that communicates rarity, and it is used
-- consistently: crystal, light, collection burst, popup card and aura.
Config.Rarities = {
	{
		name = "Common", weight = 62, color = Color3.fromRGB(120, 255, 190),
		size = 1.7, light = 12, spin = 1.6,
		stamina = 40, speed = 4, duration = 4, points = 0,
		announce = false, cue = "PickupCommon",
	},
	{
		name = "Rare", weight = 26, color = Color3.fromRGB(88, 170, 255),
		size = 2.0, light = 17, spin = 2.1,
		stamina = 70, speed = 6, duration = 5, points = 5,
		announce = false, cue = "PickupRare",
	},
	{
		name = "Epic", weight = 9, color = Color3.fromRGB(190, 120, 255),
		size = 2.4, light = 23, spin = 2.8,
		stamina = 100, speed = 8, duration = 6, points = 15,
		announce = false, cue = "PickupEpic",
	},
	{
		name = "Legendary", weight = 3, color = Color3.fromRGB(255, 200, 80),
		size = 2.9, light = 32, spin = 3.6,
		stamina = 140, speed = 11, duration = 8, points = 40,
		announce = true, cue = "PickupLegendary",
	},
}

-- The ring of orbs that spins around you after a pickup, and the burst the
-- crystal leaves behind. Both are built out of plain parts on each client,
-- so there is no texture to load and nothing to replicate.
Config.Aura = {
	Orbs = 4,
	Radius = 2.6,
	Height = 0.1,
	OrbSize = 0.45,
	Spin = 2.4,           -- radians per second
	BurstShards = 8,
	BurstTime = 0.45,
	BurstSpread = 7,
}

-- A marked circle that moves around the map. Runners earn points every
-- second they stand in it, which drags people out of the boring corners -
-- and tells the seekers exactly where to look.
Config.Beacon = {
	Enabled = true,
	Radius = 24,
	MoveEvery = 35,
	StartAfter = 15,      -- seconds into the round before the first one
	PointsPerSecond = 1,
	Color = Color3.fromRGB(255, 205, 90),
}

-- Free a teammate: stand next to somebody on the end of a chain and hold
-- your ground. Gives runners something to do besides run, and gives the
-- seeker team a reason to guard its chain instead of splitting up.
Config.Rescue = {
	Enabled = true,
	Radius = 9,
	HoldTime = 4,
	Immunity = 3,          -- seconds the freed player cannot be re-tagged
	Points = 20,
	OncePerPlayer = true,  -- each player can only be freed once a round
	BlockedInEndgame = true, -- no rescues once the runners get revealed
}

--------------------------------------------------------------------------
-- POWERUPS
-- Everybody gets Dash. The second slot swaps with your role: seekers get a
-- radar sweep, runners get a vanish. Cooldowns are counted on the server -
-- the buttons on your screen only draw what the server already decided.
--------------------------------------------------------------------------

Config.Abilities = {
	Enabled = true,

	Dash = {
		Cooldown = 9,
		Power = 62,      -- forward shove, in studs per second
		Lift = 9,        -- small hop so it clears kerbs instead of stubbing
	},

	-- Seekers only: every runner lights up through walls for a moment.
	Radar = {
		Cooldown = 24,
		Duration = 4,
	},

	-- Runners only: you fade out for everyone else. It breaks the chase
	-- rather than making you safe - you can still be tagged while faded.
	Vanish = {
		Cooldown = 26,
		Duration = 4,
		Transparency = 0.85,
	},
}

-- Catch two or more runners inside this many seconds and the whole server
-- hears about it. Streaks are what make a good seeker feel like one.
Config.Combo = {
	Window = 20,
}

--------------------------------------------------------------------------
-- LEVELS
-- Levels come from total points earned, so they carry across rounds and
-- give people a reason to come back. Level 2 at 40 points, 3 at 160,
-- 4 at 360: level = 1 + floor(sqrt(points / PointsPerLevel))
--------------------------------------------------------------------------

Config.Levels = {
	PointsPerLevel = 40,
}

--------------------------------------------------------------------------
-- SCORING  (Points and Catches show on the player list)
--------------------------------------------------------------------------

Config.Points = {
	Catch = 10,       -- per runner you personally tag
	Survive = 25,     -- for being uncaught when the timer runs out
	SeekerWin = 15,   -- to every seeker when the team catches everyone
	-- beacon points are Config.Beacon.PointsPerSecond
	-- rescue points are Config.Rescue.Points
}

Config.SaveStats = true                    -- set false to keep stats session-only
Config.DataStoreName = "ChainTagStats_v1"  -- bump the version to wipe saved stats

--------------------------------------------------------------------------
-- LOOK & FEEL
--------------------------------------------------------------------------

Config.Colors = {
	Seeker = Color3.fromRGB(232, 72, 72),
	Runner = Color3.fromRGB(78, 158, 255),
	Neutral = Color3.fromRGB(235, 238, 245),
	Good = Color3.fromRGB(96, 214, 140),
	Warn = Color3.fromRGB(255, 196, 84),
}

-- Danger vignette: how close a seeker has to be before a runner's screen
-- starts glowing red at the edges.
Config.DangerRadius = 38

--------------------------------------------------------------------------
-- SOUND
-- These rbxasset:// paths ship with Roblox itself, so they always play and
-- can never be "not authorized" like a private rbxassetid:// upload.
-- The game pitch-shifts this one sample to make its whole audio language.
-- Paste your own rbxassetid:// links here once you own/verify them.
--------------------------------------------------------------------------

Config.Sounds = {
	-- The one sample everything is built from. It ships with Roblox, so it
	-- can never fail with "not authorized" like a private upload.
	Blip = "rbxasset://sounds/electronicpingshort.wav",
	UiVolume = 0.35,
	CatchVolume = 0.5,

	-- Each cue is that sample at a different pitch. A cue with `chord`
	-- plays several pitches in quick succession, which is what makes the
	-- rarer pickups and the level-up sound like an event rather than a
	-- click. Swap in your own SoundId per cue once you own one.
	Cues = {
		Click =           { pitch = 1.20, volume = 0.22 },
		Deny =            { pitch = 0.50, volume = 0.20 },
		AbilityUse =      { pitch = 1.60, volume = 0.30 },
		AbilityReady =    { pitch = 1.35, volume = 0.26 },
		CountdownTick =   { pitch = 1.00, volume = 0.35 },
		RoundStart =      { chord = { 1.2, 1.6 }, volume = 0.40 },
		Catch =           { pitch = 1.10, volume = 0.35 },
		Caught =          { pitch = 0.62, volume = 0.50 },
		Rescue =          { chord = { 1.2, 1.6 }, volume = 0.40 },
		Beacon =          { chord = { 1.1, 1.4 }, volume = 0.32 },
		Win =             { chord = { 1.2, 1.5, 1.9 }, volume = 0.45 },
		Lose =            { chord = { 0.9, 0.7 }, volume = 0.45 },
		LevelUp =         { chord = { 1.2, 1.5, 1.9 }, volume = 0.42 },
		Purchase =        { chord = { 1.3, 1.7 }, volume = 0.40 },
		PickupCommon =    { pitch = 1.30, volume = 0.28 },
		PickupRare =      { chord = { 1.3, 1.7 }, volume = 0.34 },
		PickupEpic =      { chord = { 1.2, 1.5, 1.9 }, volume = 0.40 },
		PickupLegendary = { chord = { 1.0, 1.3, 1.6, 2.1 }, volume = 0.52 },
	},
	ChordGap = 0.07,      -- seconds between the notes of a chord

	-- Background music. Left empty on purpose: only paste an id you own or
	-- know is free to use, or the whole server gets a red error and silence.
	Music = "",
	MusicVolume = 0.18,
}

--------------------------------------------------------------------------
-- THE STORE
-- Everything costs Points, which you earn by playing. Nothing here touches
-- how the game plays - they are all cosmetic on purpose, so nobody can buy
-- an advantage with a grind. Spending Points never lowers your level:
-- levels come from TotalPoints, which only ever goes up.
--------------------------------------------------------------------------

Config.Shop = {
	Enabled = true,
	Items = {
		-- Trails stream behind you while you sprint.
		{ id = "trail_mint",   kind = "Trail", name = "Mint Trail",   price = 60,  color = Color3.fromRGB(120, 255, 190) },
		{ id = "trail_ember",  kind = "Trail", name = "Ember Trail",  price = 120, color = Color3.fromRGB(255, 138, 76) },
		{ id = "trail_violet", kind = "Trail", name = "Violet Trail", price = 220, color = Color3.fromRGB(190, 120, 255) },

		-- Auras orbit you all round long.
		{ id = "aura_sky",     kind = "Aura",  name = "Sky Aura",     price = 180, color = Color3.fromRGB(88, 170, 255) },
		{ id = "aura_gold",    kind = "Aura",  name = "Gold Aura",    price = 450, color = Color3.fromRGB(255, 200, 80) },

		-- Chain colours apply to the chain you are dragging.
		{ id = "chain_bronze", kind = "Chain", name = "Bronze Chain", price = 140, color = Color3.fromRGB(196, 132, 74) },
		{ id = "chain_frost",  kind = "Chain", name = "Frost Chain",  price = 260, color = Color3.fromRGB(168, 226, 255) },

		-- Titles float over your head.
		{ id = "title_quick",  kind = "Title", name = "QUICK",     price = 100, text = "QUICK" },
		{ id = "title_ghost",  kind = "Title", name = "GHOST",     price = 300, text = "GHOST" },
		{ id = "title_warden", kind = "Title", name = "WARDEN",    price = 500, text = "WARDEN" },
	},
}

-- Prints extra detail to the Output window while you are building.
Config.Debug = false

return Config
