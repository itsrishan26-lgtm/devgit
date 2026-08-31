--[[
	ChainTagSettings  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > ChainTagSettings

	The settings panel, and the frame-time sample that picks a quality level
	for you the first time you play.

	WHY QUALITY IS A REAL SETTING AND NOT A GUESS
	Roblox has no API that tells you how fast a device is. Guessing from
	"is it a phone" is wrong in both directions - plenty of phones outrun
	plenty of laptops. So this measures the thing that actually matters:
	how long frames are taking on THIS device, for a few seconds after the
	player joins, and picks a level from that. The player can override it.

	Quality only ever changes what a client draws - shorter chains, fewer
	aura orbs, no screen shake. It never touches a cooldown, a speed or a
	tag radius, so nobody can turn the settings down for an advantage.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config
local Remotes = Shared.Remotes

local player = Players.LocalPlayer

if not Remotes then
	error("[ChainTag] ChainTagRemotes is missing. Check that ServerScriptService.GameSetup exists and is enabled.")
end

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

--------------------------------------------------------------------------
-- Auto quality: measure, then decide
--------------------------------------------------------------------------

task.spawn(function()
	-- Give the place a moment to finish loading in; the first second of
	-- frames is all asset streaming and tells you nothing about the device.
	task.wait(2)

	local frames, elapsed = 0, 0
	local connection
	connection = RunService.RenderStepped:Connect(function(deltaTime)
		frames += 1
		elapsed += deltaTime
	end)
	task.wait(Config.Quality.AutoDetectSeconds)
	connection:Disconnect()

	local fps = elapsed > 0 and frames / elapsed or 60
	local level = #Config.Quality.Levels
	if fps < Config.Quality.LowFpsThreshold then
		level = 1
	elseif fps < Config.Quality.MediumFpsThreshold then
		level = 2
	end

	player:SetAttribute("CT_AutoQuality", level)
	print(string.format("[ChainTag] Measured %.0f FPS, using %s quality. Change it in Settings.",
		fps, Config.Quality.Levels[level].name))
end)

--------------------------------------------------------------------------
-- Reading and writing settings
--------------------------------------------------------------------------

local function current()
	return Shared.parseSettings(player:GetAttribute("Settings"))
end

-- Write locally so the UI answers instantly, then tell the server, which
-- is what actually saves it. If the server disagrees it writes the
-- attribute back and the panel redraws from that.
local function apply(changes)
	local settings = current()
	for key, value in pairs(changes) do
		settings[key] = value
	end
	local text = Shared.serializeSettings(settings)
	player:SetAttribute("Settings", text)
	Remotes.Settings:FireServer(text)
end

--------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name = "ChainTagSettings",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 8,
	Parent = player:WaitForChild("PlayerGui"),
})

-- Sits directly above the STORE button, which ShopUI puts at 0.5, -78.
-- Together they read as one rail down the left edge.
local openButton = create("TextButton", {
	Name = "Open",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 0.5, -112),
	Size = UDim2.fromOffset(92, 30),
	BackgroundColor3 = Color3.fromRGB(12, 14, 19),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "SETTINGS",
	TextColor3 = Color3.fromRGB(196, 203, 216),
	TextSize = 12,
	Parent = gui,
})
create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = openButton })
create("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.7, Parent = openButton })

local shade = create("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.fromRGB(0, 0, 0),
	BackgroundTransparency = 0.45,
	BorderSizePixel = 0,
	Visible = false,
	Parent = gui,
})

local panel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(400, 330),
	BackgroundColor3 = Color3.fromRGB(10, 12, 16),
	BackgroundTransparency = 0.05,
	BorderSizePixel = 0,
	Parent = shade,
})
create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = panel })
create("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.85, Parent = panel })
local panelScale = create("UIScale", { Parent = panel })

create("TextLabel", {
	Position = UDim2.new(0, 20, 0, 14),
	Size = UDim2.new(1, -40, 0, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "SETTINGS",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

local closeButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 14),
	Size = UDim2.fromOffset(26, 24),
	BackgroundTransparency = 1,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "X",
	TextColor3 = Color3.fromRGB(170, 178, 192),
	TextSize = 16,
	Parent = panel,
})

local body = create("Frame", {
	Position = UDim2.new(0, 20, 0, 52),
	Size = UDim2.new(1, -40, 1, -72),
	BackgroundTransparency = 1,
	Parent = panel,
})
create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 14),
	Parent = body,
})

local order = 0

local function addRow(labelText, hintText)
	order += 1
	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = body,
	})
	create("TextLabel", {
		Size = UDim2.new(0.45, 0, 0, 18),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = labelText,
		TextColor3 = Color3.fromRGB(235, 239, 246),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	create("TextLabel", {
		Position = UDim2.new(0, 0, 0, 20),
		Size = UDim2.new(0.45, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = hintText,
		TextColor3 = Color3.fromRGB(120, 128, 142),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = row,
	})
	return row
end

-- A row of small buttons where exactly one is lit.
local function addChoices(row, choices, isSelected, onPick)
	local holder = create("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.fromOffset(#choices * 74, 30),
		BackgroundTransparency = 1,
		Parent = row,
	})
	create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = holder,
	})

	local buttons = {}
	for index, choice in ipairs(choices) do
		local button = create("TextButton", {
			Size = UDim2.fromOffset(68, 28),
			BackgroundColor3 = Color3.fromRGB(24, 28, 36),
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Enum.Font.GothamBold,
			Text = choice.label,
			TextColor3 = Color3.fromRGB(200, 207, 220),
			TextSize = 12,
			LayoutOrder = index,
			Parent = holder,
		})
		create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = button })
		button.Activated:Connect(function()
			Shared.playCue("Click")
			onPick(choice.value)
		end)
		buttons[index] = { button = button, value = choice.value }
	end

	return function()
		for _, entry in ipairs(buttons) do
			local on = isSelected(entry.value)
			entry.button.BackgroundColor3 = on and Config.Colors.Good or Color3.fromRGB(24, 28, 36)
			entry.button.TextColor3 = on and Color3.fromRGB(12, 16, 20) or Color3.fromRGB(200, 207, 220)
		end
	end
end

local redraws = {}

-- Quality
do
	local row = addRow("Graphics", "Lower settings draw less. They never change how the game plays.")
	local choices = { { label = "AUTO", value = 0 } }
	for index, level in ipairs(Config.Quality.Levels) do
		table.insert(choices, { label = string.upper(level.name), value = index })
	end
	table.insert(redraws, addChoices(row, choices,
		function(value)
			return current().q == value
		end,
		function(value)
			apply({ q = value })
		end))
end

-- Effect volume
do
	local row = addRow("Sound effects", "Tags, pickups, countdowns and the heartbeat.")
	table.insert(redraws, addChoices(row,
		{ { label = "OFF", value = 0 }, { label = "HALF", value = 50 }, { label = "FULL", value = 100 } },
		function(value)
			return current().sfx == value
		end,
		function(value)
			apply({ sfx = value })
			Shared.playCue("Click")
		end))
end

-- Music volume
do
	local row = addRow("Music", "Off by default until the game has music of its own.")
	table.insert(redraws, addChoices(row,
		{ { label = "OFF", value = 0 }, { label = "HALF", value = 50 }, { label = "FULL", value = 100 } },
		function(value)
			return current().mus == value
		end,
		function(value)
			apply({ mus = value })
		end))
end

-- Screen shake
do
	local row = addRow("Screen shake", "The kick when you are part of a tag.")
	table.insert(redraws, addChoices(row,
		{ { label = "OFF", value = 0 }, { label = "ON", value = 1 } },
		function(value)
			return current().shake == value
		end,
		function(value)
			apply({ shake = value })
		end))
end

local footer = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -40, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(120, 128, 142),
	TextSize = 11,
	Parent = panel,
})

local function redraw()
	for _, fn in ipairs(redraws) do
		fn()
	end
	local settings = current()
	if settings.q == 0 then
		local auto = player:GetAttribute("CT_AutoQuality")
		footer.Text = auto
			and ("Auto picked " .. Config.Quality.Levels[auto].name .. " from your frame rate")
			or "Measuring your frame rate..."
	else
		footer.Text = "Settings save with your profile"
	end
end

--------------------------------------------------------------------------
-- Opening and closing
--------------------------------------------------------------------------

local function setOpen(open)
	if shade.Visible == open then
		return
	end
	shade.Visible = open
	if open then
		redraw()
		panelScale.Scale = 0.93
		TweenService:Create(panelScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end
end

openButton.Activated:Connect(function()
	Shared.playCue("Click")
	setOpen(not shade.Visible)
end)
closeButton.Activated:Connect(function()
	Shared.playCue("Click")
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.O then
		setOpen(not shade.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and shade.Visible then
		setOpen(false)
	end
end)

player:GetAttributeChangedSignal("Settings"):Connect(redraw)
player:GetAttributeChangedSignal("CT_AutoQuality"):Connect(redraw)

print("[ChainTag] ChainTagSettings loaded. Press O or click SETTINGS.")
