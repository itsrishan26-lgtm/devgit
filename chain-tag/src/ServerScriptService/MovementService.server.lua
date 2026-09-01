--[[
	MovementService  -  Script  (a normal Script, NOT a LocalScript)
	WHERE IT GOES: ServerScriptService > MovementService

	The server half of slide and vault. It does not perform the movement -
	the client does that, because movement has to answer on the same frame
	the key is pressed. This script decides whether the move was allowed,
	counts it, and tells everybody else it happened.

	WHAT IT ACTUALLY PROTECTS
	Roblox hands every client authority over its own character's physics,
	so pretending the server can prevent a cheater from moving strangely
	would be theatre. What it can do, and what matters, is make sure
	nothing is ever PAID OUT from a client's word: the cooldowns and the
	counters live here, so a player spamming the remote sixty times a
	second gets refused sixty times and earns nothing for it.

	Server cooldowns are slightly shorter than the client's so a player on
	a bad connection is never told no for a move they legitimately made.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedModule = ReplicatedStorage:FindFirstChild("ChainTagShared")
if not sharedModule then
	error("[ChainTag] ReplicatedStorage.ChainTagShared is missing (README step 2).")
end

local Shared = require(sharedModule)
local Config = Shared.Config
local Move = Config.Movement

-- Latency slack: accept a move a little sooner than the client's own rule.
local TOLERANCE = 0.9

local MOVES = {
	slide = {
		state = "Slide",
		cooldown = Move.Slide.Cooldown * TOLERANCE,
		duration = Move.Slide.MaxTime,
		stat = "Slides",
	},
	vault = {
		state = "Vault",
		cooldown = Move.Vault.Cooldown * TOLERANCE,
		duration = Move.Vault.Duration,
		stat = "Vaults",
	},
}

local nextAllowed = {}   -- [player] = { [moveName] = os.clock() }
local clearToken = {}    -- [player] = number, so overlapping moves do not
                         -- clear each other's state early

Players.PlayerRemoving:Connect(function(player)
	nextAllowed[player] = nil
	clearToken[player] = nil
end)

Shared.Remotes.Movement.OnServerEvent:Connect(function(player, moveName)
	if not Move.Enabled then
		return
	end
	-- A remote can be fired with anything at all.
	if type(moveName) ~= "string" then
		return
	end
	local move = MOVES[moveName]
	if not move then
		return
	end

	-- Frozen players are mid catch-countdown and are not moving anywhere.
	if player:GetAttribute("Frozen") == true then
		return
	end
	if not Shared.getRoot(player) then
		return   -- dead, or still loading in
	end

	local now = os.clock()
	local schedule = nextAllowed[player]
	if not schedule then
		schedule = {}
		nextAllowed[player] = schedule
	end
	if (schedule[moveName] or 0) > now then
		return   -- too soon; this is the spam gate
	end
	schedule[moveName] = now + move.cooldown

	-- Everyone else's client reads this to draw the slide pose.
	player:SetAttribute("MoveState", move.state)
	Shared.addStat(player, move.stat, 1)

	local token = (clearToken[player] or 0) + 1
	clearToken[player] = token
	task.delay(move.duration, function()
		if player.Parent and clearToken[player] == token then
			player:SetAttribute("MoveState", "")
		end
	end)
end)

print("[ChainTag] MovementService running. Slide and vault validated server-side.")
