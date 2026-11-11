--!strict

-- Closed-testing gate (see Config/AccessConfig). Checked when a player joins;
-- a lookup that fails (group service down) denies, never allows.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local AccessConfig = require(root.Config.AccessConfig)

local AccessService = {}

local function isAllowed(player: Player): boolean
	if game.CreatorType == Enum.CreatorType.User and game.CreatorId == player.UserId then
		return true
	end
	if table.find(AccessConfig.UserIds, player.UserId) then
		return true
	end
	if AccessConfig.GroupId > 0 then
		local ok, rank = pcall(function()
			return player:GetRankInGroup(AccessConfig.GroupId)
		end)
		return ok and rank >= AccessConfig.MinRank
	end
	return false
end

function AccessService.Start()
	if not AccessConfig.Enabled or RunService:IsStudio() then
		return
	end
	local function check(player: Player)
		task.spawn(function()
			if not isAllowed(player) then
				warn(string.format("[REALITY 2059] Acceso cerrado: %s (%d) no está en la lista", player.Name, player.UserId))
				player:Kick(AccessConfig.KickMessage)
			end
		end)
	end
	Players.PlayerAdded:Connect(check)
	for _, player in Players:GetPlayers() do
		check(player)
	end
end

return AccessService
