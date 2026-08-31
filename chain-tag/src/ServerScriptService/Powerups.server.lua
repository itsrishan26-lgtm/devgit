--[[
	Powerups  -  Script  (a normal Script, NOT a LocalScript)
	WHERE IT GOES: ServerScriptService > Powerups

	Three abilities, two slots. Everybody has Dash on slot 1. Slot 2 changes
	with your role: seekers get Radar, runners get Vanish.

	  DASH    a shove in the direction you are moving. 9 second cooldown.
	  RADAR   seekers only. Every runner outlines through walls for 4s.
	  VANISH  runners only. You fade out on everyone else's screen for 4s.
	          You can still be tagged while faded - it breaks the chase, it
	          does not make you safe.

	HOW IT IS WIRED
	The cooldown lives here, on the server, and nowhere else. A client asks
	to use an ability through the UseAbility remote; this script decides yes
	or no and writes the answer to attributes. The ability bar on screen only
	draws what these attributes already say, so a player editing their own
	client cannot shorten a cooldown - the worst they can do is spam a
	request that gets refused.

	The dash impulse itself is applied by the client that owns the character,
	because that is the only way it comes out smooth. The server decides
	whether it happens at all.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedModule = ReplicatedStorage:FindFirstChild("ChainTagShared")
if not sharedModule then
	error("[ChainTag] ReplicatedStorage.ChainTagShared is missing (README step 2).")
end

local Shared = require(sharedModule)
local Config = Shared.Config
local Abilities = Config.Abilities

-- name -> which role may use it. "any" rather than nil on purpose: a nil
-- value means the key is simply not in the table, so Dash would drop out of
-- every loop over this list, including the one that clears cooldowns.
local ABILITY_ROLES = {
	Dash = "any",
	Radar = "seeker",
	Vanish = "runner",
}

local function readyAttribute(abilityName)
	return "AbilityReady_" .. abilityName
end

local function isReady(player, abilityName)
	local readyAt = player:GetAttribute(readyAttribute(abilityName)) or 0
	return workspace:GetServerTimeNow() >= readyAt
end

local function startCooldown(player, abilityName, seconds)
	player:SetAttribute(readyAttribute(abilityName), workspace:GetServerTimeNow() + seconds)
end

-- Puts every ability back to ready and cancels anything still running.
local function resetPlayer(player)
	for abilityName in pairs(ABILITY_ROLES) do
		player:SetAttribute(readyAttribute(abilityName), 0)
	end
	player:SetAttribute("RadarUntil", 0)
	player:SetAttribute("VanishUntil", 0)
end

local function canUse(player, abilityName)
	if not Abilities.Enabled then
		return false
	end
	if Shared.getState("Phase") ~= "Round" then
		return false
	end
	if not Shared.inRound(player) then
		return false
	end
	if player:GetAttribute("Frozen") == true then
		return false
	end
	if not Shared.getRoot(player) then
		return false   -- dead or still loading
	end

	local role = ABILITY_ROLES[abilityName]
	if role == "seeker" and not Shared.isSeeker(player) then
		return false
	end
	if role == "runner" and Shared.isSeeker(player) then
		return false
	end

	return isReady(player, abilityName)
end

--------------------------------------------------------------------------
-- The abilities themselves
--------------------------------------------------------------------------

local function useDash(player)
	startCooldown(player, "Dash", Abilities.Dash.Cooldown)
	-- The owning client watches this counter and applies the shove itself.
	player:SetAttribute("DashPulse", (player:GetAttribute("DashPulse") or 0) + 1)
end

local function useRadar(player)
	startCooldown(player, "Radar", Abilities.Radar.Cooldown)
	player:SetAttribute("RadarUntil", workspace:GetServerTimeNow() + Abilities.Radar.Duration)
	Shared.toast(player.Name .. " swept the park", "seeker")
end

local function useVanish(player)
	startCooldown(player, "Vanish", Abilities.Vanish.Cooldown)
	player:SetAttribute("VanishUntil", workspace:GetServerTimeNow() + Abilities.Vanish.Duration)
end

local HANDLERS = {
	Dash = useDash,
	Radar = useRadar,
	Vanish = useVanish,
}

--------------------------------------------------------------------------
-- Requests from clients
--------------------------------------------------------------------------

Shared.Remotes.UseAbility.OnServerEvent:Connect(function(player, abilityName)
	-- Never trust the argument: a remote can be fired with anything at all.
	if type(abilityName) ~= "string" then
		return
	end
	local handler = HANDLERS[abilityName]
	if not handler then
		return
	end
	if not canUse(player, abilityName) then
		return   -- on cooldown, wrong role, wrong phase, or frozen
	end
	handler(player)
end)

Players.PlayerAdded:Connect(function(player)
	resetPlayer(player)
	player:SetAttribute("DashPulse", 0)
end)
for _, player in ipairs(Players:GetPlayers()) do
	resetPlayer(player)
end

-- Everybody starts each round with everything off cooldown.
Shared.State:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = Shared.getState("Phase")
	if phase == "Starting" or phase == "Intermission" then
		for _, player in ipairs(Players:GetPlayers()) do
			resetPlayer(player)
		end
	end
end)

print("[ChainTag] Powerups running. Dash " .. Abilities.Dash.Cooldown ..
	"s, Radar " .. Abilities.Radar.Cooldown .. "s, Vanish " .. Abilities.Vanish.Cooldown .. "s.")
