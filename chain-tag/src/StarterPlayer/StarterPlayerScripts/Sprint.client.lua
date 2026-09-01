--[[
	Sprint  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > Sprint

	Hold Shift (or the on-screen Sprint button on phones, or L3 on a gamepad)
	to run. Stamina drains while you sprint and comes back when you stop.
	Runners get a bigger tank than seekers - that is the runners' whole defence.

	This script owns WalkSpeed frame by frame, which is why the server never
	sets WalkSpeed to freeze anybody. It sets the "Frozen" attribute instead and
	this script holds you at zero. One owner, no tug of war.
--]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local baseFov = camera.FieldOfView

--------------------------------------------------------------------------
-- Stamina bar
--------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "ChainTagStamina"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local holder = Instance.new("Frame")
holder.Name = "Holder"
holder.AnchorPoint = Vector2.new(0.5, 1)
holder.Position = UDim2.new(0.5, 0, 1, -18)
holder.Size = UDim2.fromOffset(240, 8)
holder.BackgroundColor3 = Color3.fromRGB(12, 14, 18)
holder.BackgroundTransparency = 0.35
holder.BorderSizePixel = 0
holder.Parent = gui

local holderCorner = Instance.new("UICorner")
holderCorner.CornerRadius = UDim.new(1, 0)
holderCorner.Parent = holder

local holderStroke = Instance.new("UIStroke")
holderStroke.Color = Color3.fromRGB(255, 255, 255)
holderStroke.Transparency = 0.85
holderStroke.Thickness = 1
holderStroke.Parent = holder

local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(1, 1)
fill.BackgroundColor3 = Config.Colors.Neutral
fill.BorderSizePixel = 0
fill.Parent = holder

local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(1, 0)
fillCorner.Parent = fill

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

local sprintHeld = false

local function onSprintAction(_, inputState)
	sprintHeld = (inputState == Enum.UserInputState.Begin)
	-- Pass the input through so shift lock and anything else still works.
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("ChainTagSprint", onSprintAction, true,
	Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
-- Only touch devices get a button to label and place, so these are optional.
pcall(function()
	ContextActionService:SetTitle("ChainTagSprint", "Sprint")
	ContextActionService:SetPosition("ChainTagSprint", UDim2.new(1, -145, 1, -145))
end)

--------------------------------------------------------------------------
-- Movement
--------------------------------------------------------------------------

local stamina = Config.Stamina.Max + Config.Stamina.RunnerBonus
local exhausted = false
local lastDrainAt = 0
local currentSpeed = Config.Speeds.RunnerWalk
local barVisible = true

local function maxStamina()
	if Shared.isSeeker(player) then
		return Config.Stamina.Max
	end
	return Config.Stamina.Max + Config.Stamina.RunnerBonus
end

player.CharacterAdded:Connect(function()
	stamina = maxStamina()
	exhausted = false
	currentSpeed = Config.Speeds.RunnerWalk
end)

-- MapEvents bumps this counter when you pick up an energy crystal.
player:GetAttributeChangedSignal("StaminaGrant"):Connect(function()
	local amount = player:GetAttribute("StaminaGrantAmount") or 40
	stamina = math.min(maxStamina(), stamina + amount)
	if exhausted and stamina >= Config.Stamina.MinToRestart then
		exhausted = false
	end
end)

local function setBarVisible(visible)
	if visible == barVisible then
		return
	end
	barVisible = visible
	local goal = visible and 0.35 or 1
	TweenService:Create(holder, TweenInfo.new(0.25), { BackgroundTransparency = goal }):Play()
	TweenService:Create(fill, TweenInfo.new(0.25), { BackgroundTransparency = visible and 0 or 1 }):Play()
	TweenService:Create(holderStroke, TweenInfo.new(0.25), { Transparency = visible and 0.85 or 1 }):Play()
end

RunService.RenderStepped:Connect(function(deltaTime)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return
	end

	local cap = maxStamina()
	stamina = math.min(stamina, cap)

	local frozen = player:GetAttribute("Frozen") == true
	local seeker = Shared.isSeeker(player)
	local walkSpeed = seeker and Config.Speeds.SeekerWalk or Config.Speeds.RunnerWalk
	local sprintSpeed = seeker and Config.Speeds.SeekerSprint or Config.Speeds.RunnerSprint

	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local sprinting = sprintHeld and moving and not frozen and not exhausted and stamina > 0

	if sprinting then
		stamina = math.max(0, stamina - Config.Stamina.Drain * deltaTime)
		lastDrainAt = os.clock()
		if stamina <= 0 then
			exhausted = true
		end
	elseif os.clock() - lastDrainAt >= Config.Stamina.RegenDelay then
		stamina = math.min(cap, stamina + Config.Stamina.Regen * deltaTime)
		if exhausted and stamina >= Config.Stamina.MinToRestart then
			exhausted = false
		end
	end

	-- Written by ChainService on the server: a multiplier that drops as the
	-- chain stretches, and a flat bonus while it is in formation. Both are
	-- server-owned, so no client can talk itself into being faster.
	local chainMul = player:GetAttribute("ChainMul") or 1
	local chainAdd = player:GetAttribute("ChainAdd") or 0

	-- Short speed burst from a pickup, on top of everything else.
	local burst = player:GetAttribute("SpeedBonus") or 0

	local target = (sprinting and sprintSpeed or walkSpeed) * chainMul + burst + chainAdd
	if frozen then
		target = 0
	end

	currentSpeed += (target - currentSpeed) * math.min(1, deltaTime * Config.Speeds.Smoothing)
	if math.abs(currentSpeed - target) < 0.05 then
		currentSpeed = target
	end
	humanoid.WalkSpeed = currentSpeed

	local targetFov = baseFov + (sprinting and Config.Speeds.SprintFov or 0)
	camera.FieldOfView += (targetFov - camera.FieldOfView) * math.min(1, deltaTime * 5)

	-- Read by ChainTagUI to draw the speed streaks. Client side only.
	if (player:GetAttribute("CT_Sprinting") == true) ~= sprinting then
		player:SetAttribute("CT_Sprinting", sprinting)
	end

	local ratio = stamina / cap
	fill.Size = UDim2.fromScale(ratio, 1)
	fill.BackgroundColor3 = exhausted and Config.Colors.Warn
		or (sprinting and Config.Colors.Good or Config.Colors.Neutral)
	setBarVisible(ratio < 0.999 or sprinting)
end)
