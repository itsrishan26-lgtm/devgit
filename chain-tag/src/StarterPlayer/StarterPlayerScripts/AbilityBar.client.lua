--[[
	AbilityBar  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > AbilityBar

	Two slots above the stamina bar.

	  [1] DASH    everybody
	  [2] RADAR   while you are a seeker
	      VANISH  while you are a runner

	Press 1 and 2, or tap the buttons on a phone. The second slot relabels
	itself when your role changes, so the bar never shows you a button you
	are not allowed to press.

	This script draws cooldowns, it does not decide them. Every press asks
	the server, and the server writes the answer to an attribute that this
	reads back. Editing this file cannot give anybody a shorter cooldown.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config
local State = Shared.State
local Remotes = Shared.Remotes

local player = Players.LocalPlayer

if not (State and Remotes) then
	error("[ChainTag] ChainTagState/ChainTagRemotes are missing. Check ServerScriptService.GameSetup.")
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
-- Slots
--------------------------------------------------------------------------

local SLOT_SIZE = 56

local gui = create("ScreenGui", {
	Name = "ChainTagAbilities",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 4,
	Parent = player:WaitForChild("PlayerGui"),
})

local bar = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -34),
	Size = UDim2.fromOffset(SLOT_SIZE * 2 + 8, SLOT_SIZE),
	BackgroundTransparency = 1,
	Visible = false,
	Parent = gui,
})
create("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
	Padding = UDim.new(0, 8),
	SortOrder = Enum.SortOrder.LayoutOrder,
	Parent = bar,
})

-- Builds one slot. `cover` is a bar that grows up from the bottom to hide
-- the button while it is recharging: the emptier it is, the closer to ready.
local function buildSlot(order, keyLabel)
	local button = create("TextButton", {
		Size = UDim2.fromOffset(SLOT_SIZE, SLOT_SIZE),
		BackgroundColor3 = Color3.fromRGB(12, 14, 19),
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		ClipsDescendants = true,
		Parent = bar,
	})
	create("UICorner", { CornerRadius = UDim.new(0, 10), Parent = button })

	local stroke = create("UIStroke", {
		Color = Color3.fromRGB(255, 255, 255),
		Transparency = 0.7,
		Thickness = 1.5,
		Parent = button,
	})

	local cover = create("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = button,
	})

	local name = create("TextLabel", {
		Position = UDim2.new(0, 0, 0, 10),
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 12,
		ZIndex = 3,
		Parent = button,
	})

	local key = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -6),
		Size = UDim2.new(1, 0, 0, 12),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium,
		Text = keyLabel,
		TextColor3 = Color3.fromRGB(140, 148, 162),
		TextSize = 11,
		ZIndex = 3,
		Parent = button,
	})

	local timer = create("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBlack,
		Text = "",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextSize = 20,
		ZIndex = 3,
		Parent = button,
	})

	return {
		button = button,
		stroke = stroke,
		cover = cover,
		name = name,
		key = key,
		timer = timer,
		wasReady = true,
		ability = nil,
	}
end

local slots = {
	buildSlot(1, "1"),
	buildSlot(2, "2"),
}

--------------------------------------------------------------------------
-- Using them
--------------------------------------------------------------------------

local function currentSecondAbility()
	return Shared.isSeeker(player) and "Radar" or "Vanish"
end

local function abilityColor(abilityName)
	if abilityName == "Radar" then
		return Config.Colors.Seeker
	elseif abilityName == "Vanish" then
		return Config.Colors.Runner
	end
	return Config.Colors.Good
end

local function press(slot)
	if not slot.ability then
		return
	end
	local readyAt = player:GetAttribute("AbilityReady_" .. slot.ability) or 0
	if workspace:GetServerTimeNow() < readyAt then
		Shared.playCue("Deny")   -- not yet
		return
	end
	Remotes.UseAbility:FireServer(slot.ability)

	-- A little squash so the press feels answered even before the server
	-- has written the cooldown back.
	local scale = slot.button:FindFirstChildOfClass("UIScale")
		or create("UIScale", { Parent = slot.button })
	scale.Scale = 0.88
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Scale = 1 }):Play()
end

for _, slot in ipairs(slots) do
	slot.button.Activated:Connect(function()
		press(slot)
	end)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.One or input.KeyCode == Enum.KeyCode.ButtonX then
		press(slots[1])
	elseif input.KeyCode == Enum.KeyCode.Two or input.KeyCode == Enum.KeyCode.ButtonY then
		press(slots[2])
	end
end)

--------------------------------------------------------------------------
-- The dash shove
-- The server decides whether it happens; the client that owns the character
-- applies it, because a shove pushed from the server stutters.
--------------------------------------------------------------------------

player:GetAttributeChangedSignal("DashPulse"):Connect(function()
	local root, humanoid = Shared.getRoot(player)
	if not (root and humanoid) then
		return
	end
	local direction = humanoid.MoveDirection
	if direction.Magnitude < 0.1 then
		direction = root.CFrame.LookVector
	end
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.1 then
		return
	end
	root.AssemblyLinearVelocity = direction.Unit * Config.Abilities.Dash.Power
		+ Vector3.new(0, Config.Abilities.Dash.Lift, 0)
	Shared.playCue("AbilityUse")
end)

--------------------------------------------------------------------------
-- Drawing
--------------------------------------------------------------------------

RunService.RenderStepped:Connect(function()
	local phase = State:GetAttribute("Phase")
	local active = Config.Abilities.Enabled
		and phase == "Round"
		and Shared.inRound(player)
	bar.Visible = active
	if not active then
		return
	end

	local now = workspace:GetServerTimeNow()
	slots[1].ability = "Dash"
	slots[2].ability = currentSecondAbility()

	for _, slot in ipairs(slots) do
		local ability = slot.ability
		if not ability then
			continue
		end
		local cooldown = Config.Abilities[ability].Cooldown
		local readyAt = player:GetAttribute("AbilityReady_" .. ability) or 0
		local remaining = math.max(0, readyAt - now)
		local ready = remaining <= 0

		slot.name.Text = string.upper(ability)
		slot.name.TextColor3 = ready and abilityColor(ability) or Color3.fromRGB(150, 156, 168)
		slot.cover.Size = UDim2.fromScale(1, math.clamp(remaining / cooldown, 0, 1))
		slot.timer.Text = ready and "" or tostring(math.ceil(remaining))
		slot.stroke.Color = ready and abilityColor(ability) or Color3.fromRGB(255, 255, 255)
		slot.stroke.Transparency = ready and 0.15 or 0.75

		-- Flash and chirp the moment it comes back, so you can feel it
		-- refresh without staring at the bar.
		if ready and not slot.wasReady then
			Shared.playCue("AbilityReady")
			local scale = slot.button:FindFirstChildOfClass("UIScale")
				or create("UIScale", { Parent = slot.button })
			scale.Scale = 1.16
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Scale = 1 }):Play()
		end
		slot.wasReady = ready
	end
end)

print("[ChainTag] AbilityBar loaded. Keys 1 and 2.")
