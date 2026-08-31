--[[
	ChainTagUI  —  LocalScript
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

local function playBlip(pitch, volume)
	if Config.Sounds.Blip == "" then
		return
	end
	local sound = create("Sound", {
		SoundId = Config.Sounds.Blip,
		PlaybackSpeed = pitch,
		Volume = volume,
		Parent = SoundService,
	})
	SoundService:PlayLocalSound(sound)
	task.delay(2, function()
		sound:Destroy()
	end)
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

-- Top left, not bottom left: the bottom corners belong to the mobile
-- thumbstick and jump button.
local toastHolder = create("Frame", {
	Name = "Feed",
	AnchorPoint = Vector2.new(0, 0),
	Position = UDim2.new(0, 14, 0, 100),
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
	catch = Config.Colors.Seeker,
	seeker = Config.Colors.Seeker,
	warn = Config.Colors.Warn,
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

	if phase == "Starting" then
		if State:GetAttribute("SoloPractice") then
			showBanner("PRACTICE ROUND", "No seeker until a second player joins",
				Config.Colors.Neutral, 3.5)
		elseif Shared.isSeeker(player) then
			showBanner("YOU ARE THE SEEKER", "Chain every runner before the timer runs out",
				Config.Colors.Seeker, 4)
			playBlip(0.6, Config.Sounds.UiVolume)
		else
			showBanner("RUN", "Stay free until the clock hits zero", Config.Colors.Runner, 4)
			playBlip(1.3, Config.Sounds.UiVolume)
		end
	elseif phase == "Results" then
		local winner = State:GetAttribute("Winner")
		local subtitle = State:GetAttribute("ResultText") or ""
		if winner == "Seekers" then
			showBanner("SEEKERS WIN", subtitle, Config.Colors.Seeker, Config.ResultsTime - 1)
			playBlip(0.7, Config.Sounds.UiVolume)
		elseif winner == "Runners" then
			showBanner("RUNNERS WIN", subtitle, Config.Colors.Runner, Config.ResultsTime - 1)
			playBlip(1.5, Config.Sounds.UiVolume)
		else
			showBanner("ROUND OVER", subtitle, Config.Colors.Neutral, Config.ResultsTime - 1)
		end
	end

	refreshCounts()
end

State:GetAttributeChangedSignal("Phase"):Connect(onPhaseChanged)
State:GetAttributeChangedSignal("RunnersLeft"):Connect(refreshCounts)
State:GetAttributeChangedSignal("TotalRunners"):Connect(refreshCounts)
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

	for count = math.floor(seconds or Config.CatchCountdown), 1, -1 do
		if token ~= countdownToken then
			return
		end
		countdownNumber.Text = tostring(count)
		countdownNumber.TextTransparency = 0
		countdownScale.Scale = 1.45
		tween(countdownScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(countdownNumber, 0.9, { TextTransparency = 0.15 })
		playBlip(involved and 0.8 or 1.1, involved and Config.Sounds.CatchVolume or Config.Sounds.UiVolume)
		task.wait(1)
	end

	if token == countdownToken then
		countdownHolder.Visible = false
	end
end)

Remotes.Toast.OnClientEvent:Connect(pushToast)

--------------------------------------------------------------------------
-- Per frame: clock, vignette, taut warning
--------------------------------------------------------------------------

local lastTimerText = ""
local phaseTextClock = 0
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
	for _, bar in ipairs(vignetteBars) do
		local goal = 1 - danger * 0.55
		bar.BackgroundTransparency += (goal - bar.BackgroundTransparency) * math.min(1, deltaTime * 6)
	end

	local taut = player:GetAttribute("CT_ChainTaut") == true
	tautLabel.Visible = taut
	if taut then
		tautLabel.TextTransparency = 0.25 + 0.25 * math.sin(os.clock() * 8)
	end
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
				playBlip(0.9 + (3 - left) * 0.2, Config.Sounds.UiVolume)
			end
		else
			beepedAt = -1
		end
	end
end)

onPhaseChanged()
refreshCounts()
print("[ChainTag] ChainTagUI loaded and listening.")
