--[[
	ChainTagUI  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > ChainTagUI

	Everything you read on screen:
	  * top panel: phase, timer, how many runners are left
	  * role banner when a round starts and when you get chained
	  * the red 3-2-1 catch countdown
	  * win / lose banner
	  * the catch feed in the corner
	  * red edge glow when a seeker is breathing down your neck

	This replaces the old CatchCountdownUI - delete that one.

	The whole HUD is driven by attributes on ReplicatedStorage.ChainTagState,
	which the server updates. Nothing here is on a timer of its own, so the
	clock on your screen is the same clock the server is counting.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config
local State = Shared.State
local Remotes = Shared.Remotes

local player = Players.LocalPlayer

if not (State and Remotes) then
	error("[ChainTag] ChainTagState/ChainTagRemotes are missing. Check that ServerScriptService.GameSetup exists and is enabled.")
end

--------------------------------------------------------------------------
-- Tiny helpers
--------------------------------------------------------------------------

local function create(className, props, children)
	local instance = Instance.new(className)
	for key, value in pairs(props or {}) do
		instance[key] = value
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	return instance
end

local function corner(radius, parent)
	return create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

local function tween(instance, time, props, style)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local animation = TweenService:Create(instance, info, props)
	animation:Play()
	return animation
end

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name = "ChainTagHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Top panel ---------------------------------------------------------------

local topPanel = create("Frame", {
	Name = "TopPanel",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 46),   -- clears the Roblox top bar
	Size = UDim2.fromOffset(250, 84),
	BackgroundColor3 = Color3.fromRGB(10, 12, 16),
	BackgroundTransparency = 0.25,
	BorderSizePixel = 0,
	Parent = gui,
})
corner(12, topPanel)
create("UIStroke", {
	Color = Color3.fromRGB(255, 255, 255),
	Transparency = 0.88,
	Parent = topPanel,
})

local phaseLabel = create("TextLabel", {
	Name = "Phase",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 8),
	Size = UDim2.new(1, 0, 0, 14),
	Font = Enum.Font.GothamMedium,
	Text = "WAITING FOR PLAYERS",
	TextColor3 = Color3.fromRGB(176, 184, 199),
	TextSize = 12,
	Parent = topPanel,
})

local timerLabel = create("TextLabel", {
	Name = "Timer",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 20),
	Size = UDim2.new(1, 0, 0, 34),
	Font = Enum.Font.GothamBlack,
	Text = "--",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 30,
	Parent = topPanel,
})

local timerTrack = create("Frame", {
	Name = "TimerTrack",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.new(1, -24, 0, 3),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.85,
	BorderSizePixel = 0,
	Parent = topPanel,
})
corner(2, timerTrack)

local timerFill = create("Frame", {
	Name = "Fill",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Config.Colors.Neutral,
	BorderSizePixel = 0,
	Parent = timerTrack,
})
corner(2, timerFill)

local runnersLabel = create("TextLabel", {
	Name = "Runners",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 62),
	Size = UDim2.new(1, 0, 0, 16),
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Config.Colors.Runner,
	TextSize = 12,
	Parent = topPanel,
})

-- Pips: one dot per runner, dimmed as they get caught. Hidden above 10
-- players, where a row of dots stops being readable.
local pipRow = create("Frame", {
	Name = "Pips",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 1, 6),
	Size = UDim2.new(1, 0, 0, 6),
	BackgroundTransparency = 1,
	Parent = topPanel,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 4),
	Parent = pipRow,
})

-- Centre banners ----------------------------------------------------------

local bannerHolder = create("Frame", {
	Name = "Banner",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.30),
	Size = UDim2.new(0.8, 0, 0, 110),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})

local bannerTitle = create("TextLabel", {
	Name = "Title",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 64),
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextScaled = true,
	TextStrokeTransparency = 0.6,
	Parent = bannerHolder,
})

local bannerSubtitle = create("TextLabel", {
	Name = "Subtitle",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 66),
	Size = UDim2.new(1, 0, 0, 26),
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(226, 231, 240),
	TextSize = 18,
	TextStrokeTransparency = 0.8,
	Parent = bannerHolder,
})

local bannerScale = create("UIScale", { Parent = bannerHolder })

-- Catch countdown ---------------------------------------------------------

local countdownHolder = create("Frame", {
	Name = "CatchCountdown",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.52),
	Size = UDim2.new(0.6, 0, 0, 170),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 20,
	Parent = gui,
})

local countdownNumber = create("TextLabel", {
	Name = "Number",
	BackgroundTransparency = 1,
	Size = UDim2.new(1, 0, 0, 130),
	Font = Enum.Font.GothamBlack,
	Text = "3",
	TextColor3 = Config.Colors.Seeker,
	TextScaled = true,
	TextStrokeTransparency = 0.35,
	ZIndex = 20,
	Parent = countdownHolder,
})
local countdownScale = create("UIScale", { Parent = countdownNumber })

local countdownCaption = create("TextLabel", {
	Name = "Caption",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 0, 132),
	Size = UDim2.new(1, 0, 0, 26),
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 20,
	TextStrokeTransparency = 0.5,
	ZIndex = 20,
	Parent = countdownHolder,
})

-- Toast feed --------------------------------------------------------------

-- Left edge, vertically centred. The top left is the Roblox chat window and
-- the bottom corners are the mobile thumbstick and jump button, so the
-- middle of the left edge is the only part of that side actually free.
local toastHolder = create("Frame", {
	Name = "Feed",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 14, 0.5, 0),
	Size = UDim2.fromOffset(320, 130),
	BackgroundTransparency = 1,
	Parent = gui,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Vertical,
	VerticalAlignment = Enum.VerticalAlignment.Top,
	HorizontalAlignment = Enum.HorizontalAlignment.Left,
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 4),
	Parent = toastHolder,
})

-- Danger vignette ---------------------------------------------------------

local vignette = create("Frame", {
	Name = "Danger",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 2,
	Parent = gui,
})

local vignetteBars = {}
do
	local edges = {
		{ anchor = Vector2.new(0.5, 0), pos = UDim2.fromScale(0.5, 0), size = UDim2.new(1, 0, 0, 120), rotation = 270 },
		{ anchor = Vector2.new(0.5, 1), pos = UDim2.fromScale(0.5, 1), size = UDim2.new(1, 0, 0, 120), rotation = 90 },
		{ anchor = Vector2.new(0, 0.5), pos = UDim2.fromScale(0, 0.5), size = UDim2.new(0, 140, 1, 0), rotation = 180 },
		{ anchor = Vector2.new(1, 0.5), pos = UDim2.fromScale(1, 0.5), size = UDim2.new(0, 140, 1, 0), rotation = 0 },
	}
	for _, edge in ipairs(edges) do
		local bar = create("Frame", {
			AnchorPoint = edge.anchor,
			Position = edge.pos,
			Size = edge.size,
			BackgroundColor3 = Config.Colors.Seeker,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = vignette,
		})
		create("UIGradient", {
			Rotation = edge.rotation,
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = bar,
		})
		table.insert(vignetteBars, bar)
	end
end

-- Beacon marker -----------------------------------------------------------
-- A needle that swings to point at the beacon when it is off screen, and a
-- diamond over it when it is in view. Built out of plain Frames rather than
-- arrow glyphs, which not every font has.

local beaconMarker = create("Frame", {
	Name = "BeaconMarker",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Size = UDim2.fromOffset(80, 80),
	BackgroundTransparency = 1,
	Visible = false,
	ZIndex = 4,
	Parent = gui,
})

local beaconNeedleHolder = create("Frame", {
	Name = "Needle",
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ZIndex = 4,
	Parent = beaconMarker,
})

local beaconNeedle = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.fromScale(0.5, 0),
	Size = UDim2.fromOffset(6, 15),
	BackgroundColor3 = Config.Beacon.Color,
	BorderSizePixel = 0,
	ZIndex = 4,
	Parent = beaconNeedleHolder,
})
corner(3, beaconNeedle)

local beaconDot = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(11, 11),
	Rotation = 45,
	BackgroundColor3 = Config.Beacon.Color,
	BorderSizePixel = 0,
	ZIndex = 4,
	Parent = beaconMarker,
})
corner(2, beaconDot)

local beaconLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0.5, 12),
	Size = UDim2.fromOffset(80, 14),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = Config.Beacon.Color,
	TextSize = 12,
	TextStrokeTransparency = 0.5,
	ZIndex = 4,
	Parent = beaconMarker,
})

-- Rescue progress ---------------------------------------------------------

local rescueHolder = create("Frame", {
	Name = "Rescue",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -74),
	Size = UDim2.fromOffset(280, 34),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})

local rescueLabel = create("TextLabel", {
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = Config.Colors.Good,
	TextSize = 14,
	TextStrokeTransparency = 0.55,
	Parent = rescueHolder,
})

local rescueTrack = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 20),
	Size = UDim2.fromOffset(220, 6),
	BackgroundColor3 = Color3.fromRGB(12, 14, 18),
	BackgroundTransparency = 0.35,
	BorderSizePixel = 0,
	Parent = rescueHolder,
})
corner(3, rescueTrack)

local rescueFill = create("Frame", {
	Size = UDim2.fromScale(0, 1),
	BackgroundColor3 = Config.Colors.Good,
	BorderSizePixel = 0,
	Parent = rescueTrack,
})
corner(3, rescueFill)

-- Immunity pill -----------------------------------------------------------

local statusLabel = create("TextLabel", {
	Name = "Status",
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 140),
	Size = UDim2.fromOffset(180, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "",
	TextColor3 = Config.Colors.Good,
	TextSize = 14,
	TextStrokeTransparency = 0.55,
	Visible = false,
	Parent = gui,
})

-- Screen flash ------------------------------------------------------------

local flash = create("Frame", {
	Name = "Flash",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 30,
	Parent = gui,
})

-- Speed streaks -----------------------------------------------------------
-- Two soft gradients that bleed in from the sides while you sprint. Cheap,
-- needs no image, and gives running an actual sense of speed.

local streaks = {}
for _, side in ipairs({ { anchor = Vector2.new(0, 0.5), pos = UDim2.fromScale(0, 0.5), rotation = 180 },
	{ anchor = Vector2.new(1, 0.5), pos = UDim2.fromScale(1, 0.5), rotation = 0 } }) do
	local streak = create("Frame", {
		AnchorPoint = side.anchor,
		Position = side.pos,
		Size = UDim2.new(0, 200, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = gui,
	})
	create("UIGradient", {
		Rotation = side.rotation,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = streak,
	})
	table.insert(streaks, streak)
end

-- Round-start countdown ---------------------------------------------------

local introLabel = create("TextLabel", {
	Name = "Intro",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.44),
	Size = UDim2.new(0.5, 0, 0, 120),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextScaled = true,
	TextStrokeTransparency = 0.4,
	Visible = false,
	ZIndex = 15,
	Parent = gui,
})
local introScale = create("UIScale", { Parent = introLabel })

-- Points popups -----------------------------------------------------------

local popupHolder = create("Frame", {
	Name = "Popups",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -28, 0.5, 0),
	Size = UDim2.fromOffset(150, 220),
	BackgroundTransparency = 1,
	Parent = gui,
})
local popupIndex = 0

local function showPopup(text)
	popupIndex += 1
	local startY = (popupIndex % 4) * 26
	local label = create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, startY),
		Size = UDim2.fromOffset(150, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = text,
		TextColor3 = Config.Beacon.Color,
		TextSize = 24,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextStrokeTransparency = 0.4,
		Parent = popupHolder,
	})
	local scale = create("UIScale", { Scale = 0.6, Parent = label })
	tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(label, 0.9, {
		Position = UDim2.new(1, 0, 0.5, startY - 70),
		TextTransparency = 1,
		TextStrokeTransparency = 1,
	})
	task.delay(1, function()
		label:Destroy()
	end)
end

-- Effects -----------------------------------------------------------------

local function screenFlash(color, strength)
	flash.BackgroundColor3 = color
	flash.BackgroundTransparency = 1 - strength
	tween(flash, 0.5, { BackgroundTransparency = 1 })
end

-- Bound after the camera has already been positioned for this frame, so the
-- shake is applied on top of whatever the normal camera did rather than
-- fighting it.
local shakeUntil, shakeStrength = 0, 0

local function addShake(strength, duration)
	-- Off on Low, and off for anyone who turned it off in Settings.
	if not Shared.quality().shake or Shared.settings().shake == 0 then
		return
	end
	shakeStrength = math.max(shakeStrength, strength)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

RunService:BindToRenderStep("ChainTagShake", Enum.RenderPriority.Camera.Value + 1, function()
	local camera = workspace.CurrentCamera
	if not camera or os.clock() >= shakeUntil then
		shakeStrength = 0
		return
	end
	local amount = shakeStrength * math.min(1, shakeUntil - os.clock())
	camera.CFrame = camera.CFrame
		* CFrame.new((math.random() - 0.5) * amount, (math.random() - 0.5) * amount, 0)
end)

-- Music ------------------------------------------------------------------
-- Two sound objects so tracks crossfade instead of cutting. With no ids in
-- Config.Music.Tracks this does nothing at all and says nothing about it,
-- which is the correct behaviour for a game shipped without music.

local function makeMusicSound()
	local sound = Instance.new("Sound")
	sound.Name = "ChainTagMusic"
	sound.Looped = true
	sound.Volume = 0
	sound.Parent = SoundService
	return sound
end

local musicA, musicB = makeMusicSound(), makeMusicSound()
local activeMusic = musicA
local currentTrackId = ""

local function musicVolume()
	return Config.Music.Volume * (Shared.settings().mus / 100)
end

local function setMusicTrack(id)
	if not Config.Music.Enabled or id == currentTrackId then
		return
	end
	currentTrackId = id

	local outgoing = activeMusic
	local incoming = (activeMusic == musicA) and musicB or musicA
	activeMusic = incoming

	TweenService:Create(outgoing, TweenInfo.new(Config.Music.FadeTime), { Volume = 0 }):Play()
	task.delay(Config.Music.FadeTime, function()
		if outgoing.SoundId ~= currentTrackId then
			outgoing:Stop()
		end
	end)

	if id == "" then
		return
	end
	incoming.SoundId = id
	incoming.Volume = 0
	incoming:Play()
	TweenService:Create(incoming, TweenInfo.new(Config.Music.FadeTime),
		{ Volume = musicVolume() }):Play()
end

local function trackForPhase(phase)
	if phase == "Round" then
		-- The last stretch gets its own track, which is the single cheapest
		-- way to make a round feel like it is ending.
		if Shared.timeLeft() <= Config.EndgameRevealAt then
			return Config.Music.Tracks.Final
		end
		return Config.Music.Tracks.Round
	elseif phase == "Results" then
		return Config.Music.Tracks.Results
	end
	return Config.Music.Tracks.Lobby
end

player:GetAttributeChangedSignal("Settings"):Connect(function()
	if activeMusic.IsPlaying then
		activeMusic.Volume = musicVolume()
	end
end)

-- Heartbeat ---------------------------------------------------------------
-- The one sound allowed to play continuously, because it tells you
-- something the HUD cannot: how close the thing behind you is.

local nextBeatAt = 0

local function updateHeartbeat(danger)
	if not Config.Heartbeat.Enabled or danger < Config.Heartbeat.StartAt then
		nextBeatAt = 0
		return
	end
	if os.clock() < nextBeatAt then
		return
	end
	-- Danger runs StartAt..1; map that onto slow..fast.
	local span = math.max(0.01, 1 - Config.Heartbeat.StartAt)
	local closeness = math.clamp((danger - Config.Heartbeat.StartAt) / span, 0, 1)
	local interval = Config.Heartbeat.SlowInterval
		+ (Config.Heartbeat.FastInterval - Config.Heartbeat.SlowInterval) * closeness

	Shared.playCue("Heartbeat", 0.6 + closeness * 0.6)
	nextBeatAt = os.clock() + interval
end

local function showIntro(text, color)
	introLabel.Visible = true
	introLabel.Text = text
	introLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	introLabel.TextTransparency = 0
	introLabel.TextStrokeTransparency = 0.4
	introScale.Scale = 1.7
	tween(introScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(introLabel, 0.75, { TextTransparency = 1, TextStrokeTransparency = 1 })
end

-- Pickup card -------------------------------------------------------------
-- One card, reused. Colour is the only thing that says how rare the crystal
-- was, and it is the same colour the crystal, its burst and your aura use.

local cardHolder = create("Frame", {
	Name = "PickupCard",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.66),
	Size = UDim2.fromOffset(260, 62),
	BackgroundColor3 = Color3.fromRGB(10, 12, 16),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Visible = false,
	ZIndex = 12,
	Parent = gui,
})
corner(10, cardHolder)
local cardStroke = create("UIStroke", { Thickness = 2, Parent = cardHolder })
local cardScale = create("UIScale", { Parent = cardHolder })

local cardRarity = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 9),
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "",
	TextSize = 15,
	ZIndex = 12,
	Parent = cardHolder,
})

local cardReward = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 28),
	Size = UDim2.new(1, 0, 0, 26),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(214, 220, 230),
	TextSize = 13,
	ZIndex = 12,
	Parent = cardHolder,
})

local cardToken = 0

local function showPickupCard(rarityName)
	local rarity = Shared.rarity(rarityName)
	cardToken += 1
	local token = cardToken

	cardRarity.Text = string.upper(rarity.name) .. " CRYSTAL"
	cardRarity.TextColor3 = rarity.color
	cardStroke.Color = rarity.color
	cardStroke.Transparency = 0.15

	local reward = string.format("+%d stamina   +%d speed for %ds", rarity.stamina, rarity.speed, rarity.duration)
	if rarity.points > 0 then
		reward = reward .. string.format("   +%d points", rarity.points)
	end
	cardReward.Text = reward

	cardHolder.Visible = true
	cardHolder.BackgroundTransparency = 0.12
	cardRarity.TextTransparency = 0
	cardReward.TextTransparency = 0
	cardScale.Scale = 0.8
	tween(cardScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	-- The big one sits on screen long enough to actually read.
	local hold = rarity.announce and 2.4 or 1.2
	task.delay(hold, function()
		if token ~= cardToken then
			return
		end
		tween(cardHolder, 0.4, { BackgroundTransparency = 1 })
		tween(cardStroke, 0.4, { Transparency = 1 })
		tween(cardRarity, 0.4, { TextTransparency = 1 })
		tween(cardReward, 0.4, { TextTransparency = 1 })
		task.delay(0.45, function()
			if token == cardToken then
				cardHolder.Visible = false
			end
		end)
	end)
end

-- Chain taut warning ------------------------------------------------------

local tautLabel = create("TextLabel", {
	Name = "ChainTaut",
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -46),
	Size = UDim2.fromOffset(260, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "CHAIN TAUT",
	TextColor3 = Config.Colors.Warn,
	TextSize = 15,
	TextStrokeTransparency = 0.6,
	Visible = false,
	Parent = gui,
})

--------------------------------------------------------------------------
-- Banner + toast behaviour
--------------------------------------------------------------------------

local bannerToken = 0

local function showBanner(title, subtitle, color, holdSeconds)
	bannerToken += 1
	local token = bannerToken

	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerSubtitle.Text = subtitle or ""
	bannerHolder.Visible = true
	bannerTitle.TextTransparency = 1
	bannerSubtitle.TextTransparency = 1
	bannerScale.Scale = 0.85

	tween(bannerScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(bannerTitle, 0.25, { TextTransparency = 0 })
	tween(bannerSubtitle, 0.25, { TextTransparency = 0.05 })

	task.delay(holdSeconds or 3, function()
		if token ~= bannerToken then
			return
		end
		tween(bannerTitle, 0.4, { TextTransparency = 1 })
		tween(bannerSubtitle, 0.4, { TextTransparency = 1 })
		task.delay(0.4, function()
			if token == bannerToken then
				bannerHolder.Visible = false
			end
		end)
	end)
end

local toastColors = {
	legendary = Config.Beacon.Color,
	purchase = Config.Colors.Good,
	catch = Config.Colors.Seeker,
	seeker = Config.Colors.Seeker,
	warn = Config.Colors.Warn,
	beacon = Config.Beacon.Color,
	rescue = Config.Colors.Good,
	info = Color3.fromRGB(210, 216, 226),
}

local toastOrder = 0

local function pushToast(text, kind)
	toastOrder += 1
	local card = create("Frame", {
		Name = "Toast",
		Size = UDim2.fromOffset(300, 24),
		BackgroundColor3 = Color3.fromRGB(10, 12, 16),
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		LayoutOrder = toastOrder,
		Parent = toastHolder,
	})
	corner(6, card)

	create("Frame", {
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = toastColors[kind] or toastColors.info,
		BorderSizePixel = 0,
		Parent = card,
	})

	local label = create("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(1, -18, 1, 0),
		Font = Enum.Font.GothamMedium,
		Text = text,
		TextColor3 = Color3.fromRGB(235, 239, 246),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = card,
	})

	-- Keep the feed short.
	local cards = {}
	for _, child in ipairs(toastHolder:GetChildren()) do
		if child:IsA("Frame") then
			table.insert(cards, child)
		end
	end
	table.sort(cards, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #cards > 4 do
		local oldest = table.remove(cards, 1)
		oldest:Destroy()
	end

	task.delay(4.5, function()
		if not card.Parent then
			return
		end
		tween(card, 0.5, { BackgroundTransparency = 1 })
		tween(label, 0.5, { TextTransparency = 1 })
		task.delay(0.55, function()
			card:Destroy()
		end)
	end)
end

--------------------------------------------------------------------------
-- Phase driven text
--------------------------------------------------------------------------

local pips = {}

local function rebuildPips(total)
	for _, pip in ipairs(pips) do
		pip:Destroy()
	end
	table.clear(pips)
	if total <= 0 or total > 10 then
		return
	end
	for index = 1, total do
		local pip = create("Frame", {
			Name = "Pip" .. index,
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Config.Colors.Runner,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = pipRow,
		})
		corner(3, pip)
		table.insert(pips, pip)
	end
end

local function refreshCounts()
	local left = State:GetAttribute("RunnersLeft") or 0
	local total = State:GetAttribute("TotalRunners") or 0
	local phase = State:GetAttribute("Phase")

	if phase == "Round" or phase == "Starting" then
		if State:GetAttribute("SoloPractice") then
			runnersLabel.Text = "SOLO PRACTICE"
			runnersLabel.TextColor3 = toastColors.info
		elseif Shared.isSeeker(player) then
			-- Seekers care about their own formation; runners care about how
			-- many of them are left. Same slot, different question. The pips
			-- below stay on runners for both, because that is the objective.
			local length = State:GetAttribute("ChainLength") or 0
			local supporting = State:GetAttribute("SupportCount") or 0
			local text = string.format("CHAIN %d/%d", length, Config.Chain.MaxLength)
			if supporting > 0 then
				text = text .. string.format("   %d SUPPORT", supporting)
			end
			runnersLabel.Text = text
			runnersLabel.TextColor3 = player:GetAttribute("IsSupport") == true
				and Config.Colors.Warn or Config.Colors.Seeker
		else
			runnersLabel.Text = string.format("%d OF %d RUNNERS FREE", left, total)
			runnersLabel.TextColor3 = left <= 1 and Config.Colors.Warn or Config.Colors.Runner
		end
	else
		runnersLabel.Text = ""
	end

	if #pips ~= total then
		rebuildPips(total)
	end
	for index, pip in ipairs(pips) do
		local caught = index > left
		pip.BackgroundColor3 = caught and Color3.fromRGB(72, 78, 90) or Config.Colors.Runner
	end
	pipRow.Visible = (phase == "Round" or phase == "Starting") and #pips > 0
end

local function phaseText()
	local phase = State:GetAttribute("Phase")
	if phase == "Waiting" then
		local needed = State:GetAttribute("PlayersNeeded") or Config.MinPlayers
		return string.format("WAITING - %d OF %d PLAYERS", #Players:GetPlayers(), needed)
	elseif phase == "Intermission" then
		return "NEXT ROUND IN"
	elseif phase == "Starting" then
		if Shared.isSeeker(player) then
			return "YOU ARE RELEASED IN"
		end
		return "RUN - SEEKER RELEASED IN"
	elseif phase == "Round" then
		return "TIME LEFT"
	elseif phase == "Results" then
		return "ROUND OVER"
	end
	return ""
end

local lastPhase = ""

local function onPhaseChanged()
	local phase = State:GetAttribute("Phase")
	if phase == lastPhase then
		return
	end
	lastPhase = phase

	if phase == "Round" then
		showIntro("GO!", Config.Colors.Good)
		Shared.playCue("RoundStart")
	end

	if phase == "Starting" then
		if State:GetAttribute("SoloPractice") then
			showBanner("PRACTICE ROUND", "No seeker until a second player joins",
				Config.Colors.Neutral, 3.5)
		elseif Shared.isSeeker(player) then
			showBanner("YOU ARE THE SEEKER", "Chain every runner before the timer runs out",
				Config.Colors.Seeker, 4)
			Shared.playCue("RoundStart")
		else
			showBanner("RUN", "Stay free until the clock hits zero", Config.Colors.Runner, 4)
			Shared.playCue("RoundStart")
		end
	elseif phase == "Results" then
		local winner = State:GetAttribute("Winner")
		local subtitle = State:GetAttribute("ResultText") or ""
		-- Win and lose are different cues, so which one you hear depends on
		-- which side you were on.
		local iWon = (winner == "Seekers") == Shared.isSeeker(player)
		if winner == "Seekers" then
			showBanner("SEEKERS WIN", subtitle, Config.Colors.Seeker, Config.ResultsTime - 1)
			Shared.playCue(iWon and "Win" or "Lose")
		elseif winner == "Runners" then
			showBanner("RUNNERS WIN", subtitle, Config.Colors.Runner, Config.ResultsTime - 1)
			Shared.playCue(iWon and "Win" or "Lose")
		else
			showBanner("ROUND OVER", subtitle, Config.Colors.Neutral, Config.ResultsTime - 1)
		end
	end

	refreshCounts()
end

State:GetAttributeChangedSignal("Phase"):Connect(onPhaseChanged)
State:GetAttributeChangedSignal("RunnersLeft"):Connect(refreshCounts)
State:GetAttributeChangedSignal("TotalRunners"):Connect(refreshCounts)
State:GetAttributeChangedSignal("ChainLength"):Connect(refreshCounts)
State:GetAttributeChangedSignal("SupportCount"):Connect(refreshCounts)
player:GetAttributeChangedSignal("IsSupport"):Connect(refreshCounts)
Players.PlayerAdded:Connect(refreshCounts)
Players.PlayerRemoving:Connect(refreshCounts)

-- Getting chained mid-round is the moment that needs the loudest feedback.
player:GetAttributeChangedSignal("IsSeeker"):Connect(function()
	if not (Shared.isSeeker(player) and State:GetAttribute("Phase") == "Round") then
		return
	end
	-- Wait out the 3-2-1 first, so the two do not fight over the middle of
	-- the screen. The banner is the punchline, not the setup.
	task.delay(Config.CatchCountdown + 0.3, function()
		if Shared.isSeeker(player) then
			showBanner("YOU ARE CHAINED", "Help the seekers catch the rest", Config.Colors.Seeker, 3)
		end
	end)
end)

--------------------------------------------------------------------------
-- Catch countdown
--------------------------------------------------------------------------

local countdownToken = 0

Remotes.CatchCountdown.OnClientEvent:Connect(function(catcherName, caughtName, seconds, catcherId, caughtId)
	countdownToken += 1
	local token = countdownToken
	local involved = (player.UserId == catcherId or player.UserId == caughtId)

	countdownHolder.Visible = true
	countdownCaption.Text = string.format("%s chained %s", tostring(catcherName), tostring(caughtName))
	countdownCaption.TextColor3 = involved and Config.Colors.Seeker or Color3.fromRGB(255, 255, 255)

	if involved then
		screenFlash(Config.Colors.Seeker, 0.35)
		addShake(0.55, 0.45)
	end

	for count = math.floor(seconds or Config.CatchCountdown), 1, -1 do
		if token ~= countdownToken then
			return
		end
		countdownNumber.Text = tostring(count)
		countdownNumber.TextTransparency = 0
		countdownScale.Scale = 1.45
		tween(countdownScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(countdownNumber, 0.9, { TextTransparency = 0.15 })
		Shared.playCue(involved and "Caught" or "CountdownTick")
		task.wait(1)
	end

	if token == countdownToken then
		countdownHolder.Visible = false
	end
end)

Remotes.Toast.OnClientEvent:Connect(pushToast)
Remotes.Popup.OnClientEvent:Connect(showPopup)

Remotes.ChainBreak.OnClientEvent:Connect(function(_, runnerId)
	local mine = runnerId == player.UserId
	local seeker = Shared.isSeeker(player)

	-- A banner for the people it happened to and the runner who earned it;
	-- everyone else already gets the line in the feed. A break is loud, but
	-- it is not everyone's business.
	if mine then
		showBanner("CHAIN BROKEN", "You forced them apart", Config.Colors.Good, 2.4)
		Shared.playCue("Win")
	elseif seeker then
		showBanner("CHAIN BROKEN", "Regroup", Config.Colors.Seeker, 2.2)
		Shared.playCue("Lose")
		addShake(0.5, 0.4)
		screenFlash(Config.Colors.Seeker, 0.25)
	end
end)

Remotes.Collect.OnClientEvent:Connect(function(_, rarityName, collectorId)
	local rarity = Shared.rarity(rarityName)
	if collectorId == player.UserId then
		showPickupCard(rarityName)
		Shared.playCue(rarity.cue)
		if rarity.announce then
			screenFlash(rarity.color, 0.3)
		end
	elseif rarity.announce then
		-- Somebody else got the big one. Worth hearing about, quietly.
		Shared.playCue(rarity.cue, 0.4)
	end
end)


-- Levels come from total points, so the moment to celebrate one is when the
-- points value itself changes.
local level = Shared.playerLevel(player)
player:GetAttributeChangedSignal("TotalPoints"):Connect(function()
	local reached = Shared.playerLevel(player)
	if reached > level then
		level = reached
		showBanner("LEVEL " .. reached, "Keep it up", Config.Colors.Good, 2.5)
		Shared.playCue("LevelUp")
	end
end)

--------------------------------------------------------------------------
-- Per frame: clock, vignette, taut warning
--------------------------------------------------------------------------

-- Points the marker at the beacon: straight at it when it is on screen,
-- clamped to a ring around the middle of the screen when it is not.
local function updateBeaconMarker(phase)
	local active = State:GetAttribute("BeaconActive") == true and phase == "Round"
	beaconMarker.Visible = active
	if not active then
		return
	end

	local camera = workspace.CurrentCamera
	local target = State:GetAttribute("BeaconPosition") or Vector3.zero
	local viewport = camera.ViewportSize
	local centre = viewport / 2

	-- WorldToViewportPoint, not WorldToScreenPoint: this ScreenGui ignores
	-- the top bar inset, so the un-inset coordinates are the matching pair.
	local screenPoint, onScreen = camera:WorldToViewportPoint(target)
	local direction = Vector2.new(screenPoint.X, screenPoint.Y) - centre
	if screenPoint.Z <= 0 then
		direction = -direction   -- behind the camera: flip it round
	end

	local inView = onScreen and screenPoint.Z > 0
	if not inView then
		local edge = math.min(viewport.X, viewport.Y) * 0.36
		direction = direction.Magnitude > 0.001 and direction.Unit * edge or Vector2.new(0, -edge)
	end

	local position = centre + direction
	beaconMarker.Position = UDim2.fromOffset(position.X, position.Y)
	beaconNeedleHolder.Visible = not inView
	beaconNeedleHolder.Rotation = math.deg(math.atan2(direction.Y, direction.X)) + 90

	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	beaconLabel.Text = root
		and string.format("%dm", math.floor((root.Position - target).Magnitude))
		or "BEACON"
end

-- Shown to the rescuer while they hold, and to the prisoner being freed.
local function updateRescueBar()
	local progress = player:GetAttribute("RescueProgress") or 0
	local beingRescued = player:GetAttribute("BeingRescued") == true

	if progress > 0 then
		local targetId = player:GetAttribute("RescueTargetId") or 0
		local target = targetId ~= 0 and Players:GetPlayerByUserId(targetId) or nil
		rescueLabel.Text = target and ("FREEING " .. string.upper(target.Name)) or "FREEING"
	elseif beingRescued then
		-- Find whoever is working on us so the bar shows their progress.
		for _, other in ipairs(Players:GetPlayers()) do
			if other:GetAttribute("RescueTargetId") == player.UserId then
				progress = other:GetAttribute("RescueProgress") or 0
				break
			end
		end
		rescueLabel.Text = "BEING FREED - STAY PUT"
	end

	local show = progress > 0
	rescueHolder.Visible = show
	if show then
		rescueFill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
	end
end

local lastTimerText = ""
local phaseTextClock = 0
local musicTimer = 0
local phaseLengths = {
	Intermission = Config.Intermission,
	Starting = Config.HeadStart,
	Round = Config.RoundLength,
	Results = Config.ResultsTime,
}

RunService.RenderStepped:Connect(function(deltaTime)
	local phase = State:GetAttribute("Phase")
	local left = Shared.timeLeft()

	-- The phase caption only changes on the second, so do not rebuild it 60
	-- times a second just to set the same string.
	phaseTextClock -= deltaTime
	if phaseTextClock <= 0 then
		phaseTextClock = 0.25
		phaseLabel.Text = phaseText()
	end

	local text
	if phase == "Waiting" then
		text = "--"
	else
		text = Shared.formatTime(left)
	end
	if text ~= lastTimerText then
		lastTimerText = text
		timerLabel.Text = text
	end

	local full = phaseLengths[phase]
	timerTrack.Visible = full ~= nil
	if full then
		timerFill.Size = UDim2.fromScale(math.clamp(left / full, 0, 1), 1)
	end

	local urgent = (phase == "Round" and left <= 10 and left > 0)
	timerLabel.TextColor3 = urgent and Config.Colors.Seeker or Color3.fromRGB(255, 255, 255)
	timerFill.BackgroundColor3 = urgent and Config.Colors.Seeker
		or (phase == "Round" and Config.Colors.Good or Config.Colors.Neutral)

	-- Danger glow, written by ChainVisuals: 0 = clear, 1 = a seeker is on you.
	local danger = player:GetAttribute("CT_Danger") or 0
	vignette.Visible = danger > 0.01
	updateHeartbeat(danger)

	-- Music only needs checking a few times a second, and the Round to
	-- Final swap is the only one that is not driven by a phase change.
	musicTimer -= deltaTime
	if musicTimer <= 0 then
		musicTimer = 0.5
		setMusicTrack(trackForPhase(phase))
	end
	for _, bar in ipairs(vignetteBars) do
		local goal = 1 - danger * 0.55
		bar.BackgroundTransparency += (goal - bar.BackgroundTransparency) * math.min(1, deltaTime * 6)
	end

	-- Two stages, so a stretched chain and a chain about to snap do not
	-- look the same. The pulse speeds up with the danger.
	local chainState = player:GetAttribute("ChainState")
	if chainState == "Warning" then
		tautLabel.Visible = true
		tautLabel.Text = "CHAIN BREAKING"
		tautLabel.TextColor3 = Config.Colors.Seeker
		tautLabel.TextTransparency = 0.15 + 0.25 * math.sin(os.clock() * 14)
	elseif chainState == "Stretched" then
		tautLabel.Visible = true
		tautLabel.Text = "CHAIN TAUT"
		tautLabel.TextColor3 = Config.Colors.Warn
		tautLabel.TextTransparency = 0.25 + 0.25 * math.sin(os.clock() * 8)
	else
		tautLabel.Visible = false
	end

	-- One pill, whichever of the two is currently true.
	local now = workspace:GetServerTimeNow()
	if player:GetAttribute("Immune") == true then
		statusLabel.Text = "UNTOUCHABLE"
		statusLabel.TextColor3 = Config.Colors.Good
		statusLabel.Visible = true
	elseif (player:GetAttribute("VanishUntil") or 0) > now then
		statusLabel.Text = "VANISHED"
		statusLabel.TextColor3 = Config.Colors.Runner
		statusLabel.Visible = true
	else
		statusLabel.Visible = false
	end

	-- Speed streaks follow the sprint flag the Sprint script publishes.
	-- Low quality turns them off entirely.
	local sprinting = player:GetAttribute("CT_Sprinting") == true
		and Shared.quality().streaks
	for _, streak in ipairs(streaks) do
		local goal = sprinting and 0.82 or 1
		streak.BackgroundTransparency += (goal - streak.BackgroundTransparency) * math.min(1, deltaTime * 7)
	end

	updateBeaconMarker(phase)
	updateRescueBar()
end)

-- Round-start countdown beeps for the last three seconds of the head start.
task.spawn(function()
	local beepedAt = -1
	while true do
		task.wait(0.1)
		if State:GetAttribute("Phase") == "Starting" then
			local left = math.ceil(Shared.timeLeft())
			if left <= 3 and left >= 1 and left ~= beepedAt then
				beepedAt = left
				Shared.playCue("CountdownTick")
				showIntro(tostring(left))
			end
		else
			beepedAt = -1
		end
	end
end)

onPhaseChanged()
refreshCounts()
print("[ChainTag] ChainTagUI loaded and listening.")
