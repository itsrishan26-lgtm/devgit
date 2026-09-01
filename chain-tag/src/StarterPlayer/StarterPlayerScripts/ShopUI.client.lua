--[[
	ShopUI  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > ShopUI

	The store. Opens with the STORE button on the left edge, or the P key.

	Rows are grouped by what they are, each one showing its colour, its
	price and its state - BUY, EQUIP or EQUIPPED. Clicking asks the server;
	the server decides and the row redraws from the attributes it writes
	back, so what you see is always what the server actually granted.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
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

local KIND_ORDER = { "Trail", "Aura", "Chain", "Title" }
local KIND_BLURB = {
	Trail = "Streams behind you when you run",
	Aura = "Orbits you all round long",
	Chain = "Recolours the chain you drag",
	Title = "Floats over your head",
}

--------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------

local gui = create("ScreenGui", {
	Name = "ChainTagShop",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 7,
	Parent = player:WaitForChild("PlayerGui"),
})

-- The open button sits just above the catch feed on the left edge, which is
-- the one strip of screen that is not chat, thumbstick or jump button.
local openButton = create("TextButton", {
	Name = "Open",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 14, 0.5, -78),
	Size = UDim2.fromOffset(92, 30),
	BackgroundColor3 = Color3.fromRGB(12, 14, 19),
	BackgroundTransparency = 0.15,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Font = Enum.Font.GothamBold,
	Text = "STORE",
	TextColor3 = Config.Beacon.Color,
	TextSize = 13,
	Parent = gui,
})
create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = openButton })
create("UIStroke", { Color = Config.Beacon.Color, Transparency = 0.55, Parent = openButton })

local shade = create("Frame", {
	Name = "Shade",
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
	Size = UDim2.fromOffset(460, 400),
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
	Text = "STORE",
	TextColor3 = Color3.fromRGB(255, 255, 255),
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = panel,
})

local balanceLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -46, 0, 16),
	Size = UDim2.fromOffset(160, 20),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamBold,
	Text = "0 POINTS",
	TextColor3 = Config.Beacon.Color,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Right,
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

local notice = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -40, 0, 18),
	BackgroundTransparency = 1,
	Font = Enum.Font.GothamMedium,
	Text = "Everything here is cosmetic - nothing in the store changes how the game plays",
	TextColor3 = Color3.fromRGB(120, 128, 142),
	TextSize = 11,
	Parent = panel,
})

local rows = create("ScrollingFrame", {
	Position = UDim2.new(0, 16, 0, 46),
	Size = UDim2.new(1, -32, 1, -78),
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
	Padding = UDim.new(0, 4),
	Parent = rows,
})

--------------------------------------------------------------------------
-- Rows
--------------------------------------------------------------------------

local order = 0

local function addHeading(kind)
	order += 1
	local heading = create("Frame", {
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = rows,
	})
	create("TextLabel", {
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = string.upper(kind) .. "S",
		TextColor3 = Color3.fromRGB(226, 231, 240),
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = heading,
	})
	create("TextLabel", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.55, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = KIND_BLURB[kind] or "",
		TextColor3 = Color3.fromRGB(112, 120, 134),
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = heading,
	})
end

local function addRow(item)
	order += 1
	local owned = Shared.owns(player, item.id)
	local equipped = player:GetAttribute("Equipped" .. item.kind) == item.id
	local swatch = item.color or Config.Colors.Neutral

	local row = create("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BackgroundTransparency = equipped and 0.9 or 0.96,
		BorderSizePixel = 0,
		LayoutOrder = order,
		Parent = rows,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = row })

	create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 12, 0.5, 0),
		Size = UDim2.fromOffset(14, 14),
		BackgroundColor3 = swatch,
		BorderSizePixel = 0,
		Parent = row,
	}, { create("UICorner", { CornerRadius = UDim.new(1, 0) }) })

	create("TextLabel", {
		Position = UDim2.fromOffset(36, 0),
		Size = UDim2.new(0.5, 0, 1, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = item.name,
		TextColor3 = Color3.fromRGB(240, 244, 250),
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local action = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(96, 26),
		BackgroundColor3 = owned and (equipped and swatch or Color3.fromRGB(46, 52, 64))
			or Color3.fromRGB(28, 32, 40),
		BackgroundTransparency = equipped and 0.25 or 0,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Enum.Font.GothamBold,
		Text = equipped and "EQUIPPED" or (owned and "EQUIP" or (item.price .. " PTS")),
		TextColor3 = equipped and Color3.fromRGB(255, 255, 255)
			or (owned and Color3.fromRGB(226, 231, 240) or Config.Beacon.Color),
		TextSize = 12,
		Parent = row,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = action })

	action.Activated:Connect(function()
		Shared.playCue("Click")
		if equipped then
			Remotes.Shop:FireServer("unequip", item.kind)
		elseif owned then
			Remotes.Shop:FireServer("equip", item.id)
		else
			Remotes.Shop:FireServer("buy", item.id)
		end
	end)
end

local function refresh()
	for _, child in ipairs(rows:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	order = 0

	for _, kind in ipairs(KIND_ORDER) do
		local any = false
		for _, item in ipairs(Config.Shop.Items) do
			if item.kind == kind then
				if not any then
					addHeading(kind)
					any = true
				end
				addRow(item)
			end
		end
	end

	local stats = player:FindFirstChild("leaderstats")
	local balance = stats and stats:FindFirstChild("Points")
	balanceLabel.Text = string.format("%d POINTS", balance and balance.Value or 0)
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
		refresh()
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
	if input.KeyCode == Enum.KeyCode.P then
		setOpen(not shade.Visible)
	elseif input.KeyCode == Enum.KeyCode.Escape and shade.Visible then
		setOpen(false)
	end
end)

Remotes.Shop.OnClientEvent:Connect(function(status, detail)
	if status == "bought" then
		local item = Shared.shopItem(detail)
		Shared.playCue("Purchase")
		notice.Text = item and ("Unlocked and equipped " .. item.name) or "Unlocked"
		notice.TextColor3 = Config.Colors.Good
	elseif status == "denied" then
		Shared.playCue("Deny")
		notice.Text = tostring(detail)
		notice.TextColor3 = Config.Colors.Warn
	end
	if shade.Visible then
		refresh()
	end
end)

-- Redraw whenever the server changes something the rows are showing.
for _, attribute in ipairs({ "OwnedItems", "EquippedTrail", "EquippedAura", "EquippedChain", "EquippedTitle" }) do
	player:GetAttributeChangedSignal(attribute):Connect(function()
		if shade.Visible then
			refresh()
		end
	end)
end

task.spawn(function()
	local stats = player:WaitForChild("leaderstats", 30)
	local balance = stats and stats:WaitForChild("Points", 10)
	if balance then
		balance.Changed:Connect(function()
			if shade.Visible then
				refresh()
			end
		end)
	end
end)

print("[ChainTag] ShopUI loaded. Press P or click STORE.")
