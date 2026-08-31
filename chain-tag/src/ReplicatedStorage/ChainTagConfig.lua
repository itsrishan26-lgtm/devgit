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
	Stamina = 60,
	RunnerSpeed = 5,      -- extra walk speed
	SeekerSpeed = 3,
	SpeedTime = 4,
	Color = Color3.fromRGB(120, 255, 190),
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
	Blip = "rbxasset://sounds/electronicpingshort.wav",
	CatchVolume = 0.5,
	UiVolume = 0.35,
}

-- Prints extra detail to the Output window while you are building.
Config.Debug = false

return Config
