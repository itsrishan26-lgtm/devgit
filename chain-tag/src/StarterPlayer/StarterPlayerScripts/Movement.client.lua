--[[
	Movement  -  LocalScript
	WHERE IT GOES: StarterPlayer > StarterPlayerScripts > Movement

	Slide, vault and landing weight. Everybody has all of it from their
	first round; none of it is ever unlocked or bought.

	  C / Slide button   slide, if you are already moving fast enough
	  Space at a wall    vault it instead of jumping into it

	WHY THE CLIENT DOES THIS AND NOT THE SERVER
	Movement has to answer the same frame you press the key. A round trip
	to the server first would put 100ms of nothing between the button and
	the slide, and no amount of correctness makes that feel good. So the
	client acts immediately and tells the server what it did; the server
	rate-limits it, records it, and publishes MoveState so everyone else
	can see you slide.

	That is not a security hole worth pretending about: Roblox gives every
	client authority over its own character's physics, so a cheater can
	already move however they like. What matters is that nothing valuable
	is paid out from a client claim - the server owns the cooldowns and
	the counters, so a spammed remote earns nothing.

	OWNERSHIP OF WALKSPEED
	Sprint normally writes WalkSpeed every frame. During a slide this
	script takes it over and sets CT_MoveLock; Sprint sees that and keeps
	its hands off until the slide ends. One owner at a time, always.
--]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = require(ReplicatedStorage:WaitForChild("ChainTagShared"))
local Config = Shared.Config
local Move = Config.Movement
local Remotes = Shared.Remotes

local player = Players.LocalPlayer

--------------------------------------------------------------------------
-- The default control script
-- A slide steers itself, so the player's input has to be taken off the
-- humanoid for its duration or the two fight over MoveDirection.
--------------------------------------------------------------------------

local controls
task.spawn(function()
	local ok, result = pcall(function()
		local scripts = player:WaitForChild("PlayerScripts", 20)
		local module = scripts and scripts:WaitForChild("PlayerModule", 20)
		return module and require(module):GetControls()
	end)
	if ok then
		controls = result
	else
		warn("[ChainTag] Movement could not reach PlayerModule; sliding will not lock steering.")
	end
end)

local function setControlsEnabled(enabled)
	if not controls then
		return
	end
	pcall(function()
		if enabled then
			controls:Enable()
		else
			controls:Disable()
		end
	end)
end

--------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------

local state = "None"          -- None | Slide | Vault
local slideDirection = Vector3.zero
local slideSpeed = 0
local slideEndsAt = 0
local defaultHipHeight = 2
local nextSlideAt, nextVaultAt = 0, 0

local vaultStart, vaultGoal, vaultBegan = nil, nil, 0
-- Held directly rather than looked up through getRoot, which returns nil
-- the moment health hits zero. Dying mid-vault has to still unanchor.
local vaultRoot = nil

local cameraDip, targetDip = 0, 0
local peakHeight = nil
local landToken = 0

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

local function character()
	local root, humanoid, model = Shared.getRoot(player)
	return root, humanoid, model
end

local function busy()
	return state ~= "None"
end

-- Never take over the character while the server has it: the catch
-- countdown anchors the root, and a vault that unanchored afterwards would
-- hand somebody a free escape out of being caught.
local function locked()
	return player:GetAttribute("Frozen") == true
end

--------------------------------------------------------------------------
-- Slide
--------------------------------------------------------------------------

local function endSlide()
	if state ~= "Slide" then
		return
	end
	state = "None"
	player:SetAttribute("CT_MoveLock", false)
	setControlsEnabled(true)

	local _, humanoid = character()
	if humanoid then
		humanoid.HipHeight = defaultHipHeight
	end
	targetDip = 0
end

local function trySlide()
	if not Move.Enabled or busy() or locked() or os.clock() < nextSlideAt then
		return
	end
	local root, humanoid = character()
	if not (root and humanoid) then
		return
	end
	-- Feet on the ground, already moving, and moving quickly.
	if humanoid.FloorMaterial == Enum.Material.Air then
		return
	end
	local velocity = root.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	if flat.Magnitude < Move.Slide.MinSpeed or humanoid.MoveDirection.Magnitude < 0.1 then
		return
	end

	state = "Slide"
	slideDirection = humanoid.MoveDirection.Unit
	slideSpeed = Move.Slide.Speed
	slideEndsAt = os.clock() + Move.Slide.MaxTime
	nextSlideAt = os.clock() + Move.Slide.Cooldown

	defaultHipHeight = humanoid.HipHeight
	humanoid.HipHeight = defaultHipHeight - Move.Slide.HipDrop
	player:SetAttribute("CT_MoveLock", true)
	-- Sprint reads this and takes the stamina off; sliding is a decision.
	player:SetAttribute("CT_SlideCost", (player:GetAttribute("CT_SlideCost") or 0) + 1)
	setControlsEnabled(false)
	targetDip = Move.Slide.CameraDip

	Shared.playCue("Slide")
	Remotes.Movement:FireServer("slide")
end

local function updateSlide(deltaTime)
	local root, humanoid = character()
	if not (root and humanoid) or locked() then
		endSlide()
		return
	end

	slideSpeed -= Move.Slide.Friction * deltaTime
	if slideSpeed <= Move.Slide.EndSpeed
		or os.clock() >= slideEndsAt
		or humanoid.FloorMaterial == Enum.Material.Air
	then
		endSlide()
		return
	end

	humanoid.WalkSpeed = slideSpeed
	humanoid:Move(slideDirection, false)
end

--------------------------------------------------------------------------
-- Vault
--------------------------------------------------------------------------

-- Looks for something waist-high and climbable directly ahead. Returns the
-- spot to land on, or nil if there is nothing worth vaulting.
local function findVault(root)
	local look = root.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 0.1 then
		return nil
	end
	forward = forward.Unit

	local characters = {}
	for _, other in ipairs(Players:GetPlayers()) do
		if other.Character then
			table.insert(characters, other.Character)
		end
	end
	rayParams.FilterDescendantsInstances = characters

	-- Something at knee height...
	local low = workspace:Raycast(root.Position - Vector3.new(0, 1.4, 0),
		forward * Move.Vault.Reach, rayParams)
	if not low then
		return nil
	end
	-- ...and nothing at chest height, or it is a wall, not an obstacle.
	local high = workspace:Raycast(root.Position + Vector3.new(0, 1.2, 0),
		forward * Move.Vault.Reach, rayParams)
	if high then
		return nil
	end

	-- How tall is it? Look straight down onto its top surface.
	local above = low.Position + forward * 0.6 + Vector3.new(0, Move.Vault.MaxHeight, 0)
	local top = workspace:Raycast(above, Vector3.new(0, -Move.Vault.MaxHeight * 2, 0), rayParams)
	if not top then
		return nil
	end
	local height = top.Position.Y - (root.Position.Y - defaultHipHeight)
	if height < Move.Vault.MinHeight or height > Move.Vault.MaxHeight then
		return nil
	end

	-- Is there floor on the far side to land on?
	local beyond = root.Position + forward * Move.Vault.Depth + Vector3.new(0, 2, 0)
	local landing = workspace:Raycast(beyond, Vector3.new(0, -14, 0), rayParams)
	if not landing then
		return nil
	end

	return landing.Position + Vector3.new(0, defaultHipHeight + 1, 0), forward
end

local function endVault()
	state = "None"
	player:SetAttribute("CT_MoveLock", false)
	targetDip = 0

	local root = vaultRoot
	vaultRoot = nil
	if root and root.Parent then
		-- Only hand physics back if the server has not taken the character
		-- in the meantime - it anchors the root during a catch countdown.
		if not locked() then
			root.Anchored = false
			local look = root.CFrame.LookVector
			root.AssemblyLinearVelocity =
				Vector3.new(look.X, 0, look.Z).Unit * Move.Vault.ExitSpeed
		end
	end
end

local function tryVault()
	if not Move.Enabled or busy() or locked() or os.clock() < nextVaultAt then
		return false
	end
	local root, humanoid = character()
	if not (root and humanoid) then
		return false
	end
	if humanoid.MoveDirection.Magnitude < 0.1 then
		return false
	end
	if humanoid.FloorMaterial == Enum.Material.Air then
		return false   -- feet on the ground; no chaining vaults up a wall
	end

	local target, forward = findVault(root)
	if not target then
		return false
	end

	state = "Vault"
	vaultBegan = os.clock()
	vaultRoot = root
	vaultStart = root.CFrame
	vaultGoal = CFrame.lookAt(target, target + forward)
	nextVaultAt = os.clock() + Move.Vault.Cooldown

	root.Anchored = true
	player:SetAttribute("CT_MoveLock", true)
	targetDip = -0.6   -- a small lift, so the camera rises with you

	Shared.playCue("Vault")
	Remotes.Movement:FireServer("vault")
	return true
end

local function updateVault()
	local root = vaultRoot
	if not (root and root.Parent) or locked() then
		endVault()
		return
	end

	local progress = (os.clock() - vaultBegan) / Move.Vault.Duration
	if progress >= 1 then
		root.CFrame = vaultGoal
		endVault()
		return
	end

	-- Straight line plus a sine arc, so it goes over the obstacle rather
	-- than through where it used to be.
	local blended = vaultStart:Lerp(vaultGoal, progress)
	root.CFrame = blended + Vector3.new(0, math.sin(progress * math.pi) * Move.Vault.Lift, 0)
end

--------------------------------------------------------------------------
-- Landing weight
--------------------------------------------------------------------------

local function onStateChanged(_, new)
	local root = character()
	if not root then
		return
	end

	if new == Enum.HumanoidStateType.Freefall or new == Enum.HumanoidStateType.Jumping then
		peakHeight = math.max(peakHeight or root.Position.Y, root.Position.Y)
	elseif new == Enum.HumanoidStateType.Landed then
		local drop = (peakHeight or root.Position.Y) - root.Position.Y
		peakHeight = nil

		if drop >= Move.Landing.HardDrop then
			Shared.playCue("LandHard")
			targetDip = Move.Landing.MaxDip
			-- A long drop costs you a moment on the ground. Without this,
			-- a rooftop is a free escape from anything.
			landToken += 1
			local token = landToken
			player:SetAttribute("CT_LandSlow", Move.Landing.HardSlowFactor)
			task.delay(Move.Landing.HardSlowTime, function()
				if landToken == token then
					player:SetAttribute("CT_LandSlow", 1)
				end
			end)
			task.delay(0.18, function()
				if state == "None" then
					targetDip = 0
				end
			end)
		elseif drop >= Move.Landing.SoftDrop then
			Shared.playCue("LandSoft")
			targetDip = Move.Landing.MaxDip * 0.4
			task.delay(0.14, function()
				if state == "None" then
					targetDip = 0
				end
			end)
		end
	end
end

local function bindCharacter(model)
	local humanoid = model:WaitForChild("Humanoid", 10)
	if not humanoid then
		return
	end
	defaultHipHeight = humanoid.HipHeight
	state = "None"
	peakHeight = nil
	cameraDip, targetDip = 0, 0
	player:SetAttribute("CT_MoveLock", false)
	player:SetAttribute("CT_LandSlow", 1)
	humanoid.StateChanged:Connect(onStateChanged)
end

player.CharacterAdded:Connect(bindCharacter)
if player.Character then
	task.spawn(bindCharacter, player.Character)
end

--------------------------------------------------------------------------
-- Other people's slides
-- MoveState is published by the server, so every client can drop the pose
-- on somebody else's character. Purely local: changing another player's
-- HipHeight here never leaves this machine.
--------------------------------------------------------------------------

local remoteHip = {}   -- [player] = their normal hip height

local function watchOther(other)
	if other == player then
		return
	end
	other.CharacterAdded:Connect(function()
		remoteHip[other] = nil
	end)
	other:GetAttributeChangedSignal("MoveState"):Connect(function()
		local _, humanoid = Shared.getRoot(other)
		if not humanoid then
			return
		end
		if other:GetAttribute("MoveState") == "Slide" then
			remoteHip[other] = remoteHip[other] or humanoid.HipHeight
			humanoid.HipHeight = remoteHip[other] - Move.Slide.HipDrop
		elseif remoteHip[other] then
			humanoid.HipHeight = remoteHip[other]
		end
	end)
end

Players.PlayerAdded:Connect(watchOther)
Players.PlayerRemoving:Connect(function(other)
	remoteHip[other] = nil
end)
for _, other in ipairs(Players:GetPlayers()) do
	watchOther(other)
end

--------------------------------------------------------------------------
-- Input
--------------------------------------------------------------------------

local function onSlideAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		trySlide()
	end
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("ChainTagSlide", onSlideAction, true,
	Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
pcall(function()
	ContextActionService:SetTitle("ChainTagSlide", "Slide")
	ContextActionService:SetPosition("ChainTagSlide", UDim2.new(1, -145, 1, -75))
end)

-- Jump is bound at a higher priority than the default jump action so a
-- vault can swallow the press when there is something to vault; otherwise
-- it passes straight through and you get a normal jump.
ContextActionService:BindActionAtPriority("ChainTagVault", function(_, inputState)
	if inputState == Enum.UserInputState.Begin and tryVault() then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value + 1,
	Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

--------------------------------------------------------------------------
-- Frame work
--------------------------------------------------------------------------

RunService.RenderStepped:Connect(function(deltaTime)
	if state == "Slide" then
		updateSlide(deltaTime)
	elseif state == "Vault" then
		updateVault()
	end

	cameraDip += (targetDip - cameraDip) * math.min(1, deltaTime * 9)
end)

-- Bound after the camera has been placed for the frame, like the shake in
-- ChainTagUI, so it rides on top of the normal camera rather than fighting
-- it. Runs a step later than the shake so the two compose.
RunService:BindToRenderStep("ChainTagMoveDip", Enum.RenderPriority.Camera.Value + 2, function()
	if math.abs(cameraDip) < 0.01 then
		return
	end
	local camera = workspace.CurrentCamera
	if camera then
		camera.CFrame = camera.CFrame * CFrame.new(0, -cameraDip, 0)
	end
end)

print("[ChainTag] Movement loaded. C to slide, Space to vault.")
