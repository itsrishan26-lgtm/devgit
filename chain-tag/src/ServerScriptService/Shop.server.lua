--[[
	Shop  -  Script  (a normal Script, NOT a LocalScript)
	WHERE IT GOES: ServerScriptService > Shop

	Spends Points on cosmetics. The catalogue lives in ChainTagConfig, so
	adding an item is one line there and nothing here.

	EVERYTHING IN THE STORE IS COSMETIC ON PURPOSE
	Trails, auras, chain colours and titles change nothing about how the
	game plays. A store that sells speed turns every round into a question
	of who has ground the most points, and the people who most need a fair
	round are the new ones with nothing bought.

	SPENDING NEVER COSTS YOU A LEVEL
	Points is a balance the store spends down. TotalPoints is everything
	you have ever earned and only ever goes up - that is what levels read.

	Nothing here trusts the client. It is handed an item id and re-reads the
	price, the balance and the ownership from the server's own copy.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local sharedModule = ReplicatedStorage:FindFirstChild("ChainTagShared")
if not sharedModule then
	error("[ChainTag] ReplicatedStorage.ChainTagShared is missing (README step 2).")
end

local Shared = require(sharedModule)
local Config = Shared.Config

local VALID_KINDS = { Trail = true, Aura = true, Chain = true, Title = true }

local function points(player)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Points")
	return value
end

local function reply(player, status, detail)
	Shared.Remotes.Shop:FireClient(player, status, detail)
end

local function grant(player, itemId)
	local owned = player:GetAttribute("OwnedItems") or ""
	if owned == "" then
		owned = itemId
	else
		owned = owned .. "," .. itemId
	end
	player:SetAttribute("OwnedItems", owned)
end

local function equip(player, item)
	player:SetAttribute("Equipped" .. item.kind, item.id)
end

local function buy(player, itemId)
	local item = Shared.shopItem(itemId)
	if not item then
		reply(player, "denied", "That item does not exist")
		return
	end
	if Shared.owns(player, itemId) then
		reply(player, "denied", "You already own that")
		return
	end

	local balance = points(player)
	if not balance then
		reply(player, "denied", "Your stats are still loading")
		return
	end
	if balance.Value < item.price then
		reply(player, "denied", string.format("You need %d more points", item.price - balance.Value))
		return
	end

	-- Spend from the balance only. TotalPoints, which levels read, is
	-- deliberately left alone.
	balance.Value = balance.Value - item.price
	grant(player, itemId)
	equip(player, item)
	reply(player, "bought", itemId)
	Shared.toast(player.Name .. " unlocked " .. item.name, "purchase")
end

local function equipRequest(player, itemId)
	local item = Shared.shopItem(itemId)
	if not item then
		reply(player, "denied", "That item does not exist")
		return
	end
	if not Shared.owns(player, itemId) then
		reply(player, "denied", "You do not own that yet")
		return
	end
	equip(player, item)
	reply(player, "equipped", itemId)
end

local function unequipRequest(player, kind)
	if not VALID_KINDS[kind] then
		return
	end
	player:SetAttribute("Equipped" .. kind, "")
	reply(player, "equipped", "")
end

Shared.Remotes.Shop.OnServerEvent:Connect(function(player, action, argument)
	if not Config.Shop.Enabled then
		return
	end
	-- A remote can be fired with anything at all, so check the shapes first.
	if type(action) ~= "string" or type(argument) ~= "string" then
		return
	end

	if action == "buy" then
		buy(player, argument)
	elseif action == "equip" then
		equipRequest(player, argument)
	elseif action == "unequip" then
		unequipRequest(player, argument)
	end
end)

-- Make sure every slot exists from the moment a player joins, so the client
-- never reads a nil attribute and the shop UI draws correctly on frame one.
local function prepare(player)
	if player:GetAttribute("OwnedItems") == nil then
		player:SetAttribute("OwnedItems", "")
	end
	for kind in pairs(VALID_KINDS) do
		if player:GetAttribute("Equipped" .. kind) == nil then
			player:SetAttribute("Equipped" .. kind, "")
		end
	end
end

Players.PlayerAdded:Connect(prepare)
for _, player in ipairs(Players:GetPlayers()) do
	prepare(player)
end

print("[ChainTag] Shop running. " .. #Config.Shop.Items .. " items in the catalogue.")
