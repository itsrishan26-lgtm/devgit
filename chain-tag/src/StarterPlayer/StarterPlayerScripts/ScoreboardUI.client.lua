--[[
	ScoreboardUI  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > ScoreboardUI

	Hold TAB for the scoreboard. It also opens on its own when a round ends,
	so the last thing everyone sees is who actually did the work.

	Columns: role, name, catches, prison breaks, points. Sorted by points.
	Everything it shows is already replicated (leaderstats values and player
	attributes), so there is no RemoteEvent behind this and no way for it to
	fall out of sync with the server.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config
local State = Shared.State

local player = Players.LocalPlayer

if not State then
	error("[ChainTag] ChainTagState is missing. Check that ServerScriptService.GameSetup exists and is enabled.")
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
-- Layout
--------------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name = "ChainTagScoreboard",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 6,
	Enabled = false,
	Parent = player:WaitForChild("PlayerGui"),
})

local panel = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(430, 340),
	BackgroundColor3 = Color3.fromRGB(10, 12, 16),
	BackgroundTransparency = 0.12,
	BorderSizePixel = 0,
	Parent = gui,
})
create("UICorner", { CornerRadius = UDim.new(0, 14), Parent = panel })
create("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Transparency = 0.86, Parent = panel })

local title = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 14),
	Size = UDim2.new(1, 0, 0, 24),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBlack,
	Text = "SCOREBOARD",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 20,
	Parent = panel,
})

local subtitle = create("TextLabel", {
	Position = UDim2.new(0, 0, 0, 38),
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "",
	TextColor3 = Color3.fromRGB(168, 176, 190),
	TextSize = 12,
	Parent = panel,
})

-- Column headers
local header = create("Frame", {
	Position = UDim2.new(0, 16, 0, 62),
	Size = UDim2.new(1, -32, 0, 16),
	BackgroundTransparency = 1,
	Parent = panel,
})

local COLUMNS = {
	{ text = "PLAYER", x = 0, width = 200, align = Enum.TextXAlignment.Left },
	{ text = "CATCHES", x = 210, width = 60, align = Enum.TextXAlignment.Center },
	{ text = "FREES", x = 275, width = 55, align = Enum.TextXAlignment.Center },
	{ text = "POINTS", x = 335, width = 63, align = Enum.TextXAlignment.Right },
}

for _, column in ipairs(COLUMNS) do
	create("TextLabel", {
		Position = UDim2.fromOffset(column.x, 0),
		Size = UDim2.fromOffset(column.width, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = column.text,
		TextColor3 = Color3.fromRGB(126, 134, 148),
		TextSize = 11,
		TextXAlignment = column.align,
		Parent = header,
	})
end

local rows = create("ScrollingFrame", {
	Position = UDim2.new(0, 16, 0, 82),
	Size = UDim2.new(1, -32, 1, -98),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageTransparency = 0.6,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	Parent = panel,
})
create("UIListLayout", {
	SortOrder = Enum.SortOrder.LayoutOrder,
	Padding = UDim.new(0, 3),
	Parent = rows,
})

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------

local function statOf(target, name)
	local stats = target:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild(name)
	return value and value.Value or 0
end

local function roleOf(target)
	if not Shared.inRound(target) then
		return "NEXT ROUND", Color3.fromRGB(120, 128, 142)
	elseif Shared.isSeeker(target) then
		return "SEEKER", Config.Colors.Seeker
	end
	return "RUNNER", Config.Colors.Runner
end

local function buildRow(target, index)
	local isSelf = (target == player)
	local roleText, roleColor = roleOf(target)

	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = isSelf and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = isSelf and 0.9 or 1,
		BorderSizePixel = 0,
		LayoutOrder = index,
		Parent = rows,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = row })

	create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 2, 0.5, 0),
		Size = UDim2.fromOffset(6, 6),
		BackgroundColor3 = roleColor,
		BorderSizePixel = 0,
		Parent = row,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	create("TextLabel", {
		Position = UDim2.fromOffset(16, 0),
		Size = UDim2.fromOffset(130, 26),
		BackgroundTransparency = 1,
		Font = isSelf and Enum.Font.GothamBold or Enum.Font.GothamMedium,
		Text = target.DisplayName,
		TextColor3 = Color3.fromRGB(235, 239, 246),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = row,
	})

	create("TextLabel", {
		Position = UDim2.fromOffset(146, 0),
		Size = UDim2.fromOffset(58, 26),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = roleText,
		TextColor3 = roleColor,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local numbers = {
		{ x = 210, width = 60, value = statOf(target, "Catches"), align = Enum.TextXAlignment.Center },
		{ x = 275, width = 55, value = target:GetAttribute("Rescues") or 0, align = Enum.TextXAlignment.Center },
		{ x = 335, width = 63, value = statOf(target, "Points"), align = Enum.TextXAlignment.Right },
	}
	for _, number in ipairs(numbers) do
		create("TextLabel", {
			Position = UDim2.fromOffset(number.x, 0),
			Size = UDim2.fromOffset(number.width, 26),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = tostring(number.value),
			TextColor3 = Color3.fromRGB(226, 231, 240),
			TextSize = 13,
			TextXAlignment = number.align,
			Parent = row,
		})
	end
end

local function refresh()
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local list = Players:GetPlayers()
	table.sort(list, function(a, b)
		local pointsA, pointsB = statOf(a, "Points"), statOf(b, "Points")
		if pointsA ~= pointsB then
			return pointsA > pointsB
		end
		return statOf(a, "Catches") > statOf(b, "Catches")
	end)

	for index, target in ipairs(list) do
		buildRow(target, index)
	end

	local phase = State:GetAttribute("Phase")
	if phase == "Results" then
		local winner = State:GetAttribute("Winner")
		if winner == "Seekers" then
			title.Text = "SEEKERS WIN"
			title.TextColor3 = Config.Colors.Seeker
		elseif winner == "Runners" then
			title.Text = "RUNNERS WIN"
			title.TextColor3 = Config.Colors.Runner
		else
			title.Text = "ROUND OVER"
			title.TextColor3 = Color3.fromRGB(255, 255, 255)
		end
		subtitle.Text = State:GetAttribute("ResultText") or ""
	else
		title.Text = "SCOREBOARD"
		title.TextColor3 = Color3.fromRGB(255, 255, 255)
		subtitle.Text = string.format("%d in the park - hold Tab to keep this open", #list)
	end
end

--------------------------------------------------------------------------
-- Showing and hiding
--------------------------------------------------------------------------

local heldOpen = false
local scale = create("UIScale", { Scale = 1, Parent = panel })

local function setOpen(open)
	if gui.Enabled == open then
		return
	end
	gui.Enabled = open
	if open then
		refresh()
		scale.Scale = 0.94
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = 1 }):Play()
	end
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Tab then
		heldOpen = true
		setOpen(true)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Tab then
		heldOpen = false
		if State:GetAttribute("Phase") ~= "Results" then
			setOpen(false)
		end
	end
end)

-- Open by itself for the results, close again when the next round starts.
State:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = State:GetAttribute("Phase")
	if phase == "Results" then
		setOpen(true)
	elseif not heldOpen then
		setOpen(false)
	end
end)

task.spawn(function()
	while true do
		task.wait(0.5)
		if gui.Enabled then
			refresh()
		end
	end
end)

print("[ChainTag] ScoreboardUI loaded. Hold Tab.")
