--!strict

-- MODO LIBRE on the server. Characters only exist in free roam
-- (CharacterAutoLoads is off): each player spawns as their standard R15
-- avatar (AvatarService.LoadCharacter: catalog items, skin, scales and
-- cyberware), which Roblox animates and replicates like any character. The
-- day/night clock is a shared epoch.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local Config = require(root.Config.FreeRoamConfig)
local GameConfig = require(root.Config.GameConfig)
local RemoteNames = require(root.Network.RemoteNames)
local CharacterValidator = require(root.Validation.CharacterValidator)
local RateLimiter = require(script.Parent.RateLimiter)
local DayCycle = require(root.World.DayCycle)
local PartyConfig = require(root.Config.PartyConfig)
local DevConfig = require(root.Config.DevConfig)
local RunService = game:GetService("RunService")

local FreeRoamService = {}
FreeRoamService.__index = FreeRoamService

local RESPAWN_SECONDS = 3

-- avatars: the AvatarService that spawns the real characters.
function FreeRoamService.new(runtime: Folder, world: Model, avatars)
	local self = setmetatable({}, FreeRoamService)
	self._world = world
	self._avatars = avatars
	self._drafts = {} :: { [Player]: any }
	self._inFreeRoam = {} :: { [Player]: boolean }
	-- Last grounded spot per roaming player (fall recovery).
	self._safe = {} :: { [Player]: CFrame }
	self._spawnIndex = 0
	-- Matches (MatchService): where each match player spawns. While a player
	-- has one, they may enter even though MODO LIBRE is locked.
	self._spawnProviders = {} :: { [Player]: () -> CFrame? }
	self._rateLimiter = RateLimiter.new(GameConfig.Networking.MaxDraftRequestsPerWindow, GameConfig.Networking.RequestWindowSeconds)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	self._enter = Instance.new("RemoteFunction")
	self._enter.Name = RemoteNames.EnterFreeRoam
	self._enter.Parent = remotes
	self._leave = Instance.new("RemoteFunction")
	self._leave.Name = RemoteNames.LeaveFreeRoam
	self._leave.Parent = remotes
	-- Clock epoch so ClockTime = StartClockTime when the server starts.
	local cycle = Config.DayCycle
	runtime:SetAttribute("DayCycleEpoch", Workspace:GetServerTimeNow() - DayCycle.ElapsedFor(cycle, cycle.StartClockTime))
	return self
end

-- Studio map test (DevConfig.QuickStart = "MapTest"): team A's spawns of
-- Workspace.MapWorkshop[DevConfig.MapTest].
local function mapTestSpawns(): { BasePart }?
	if not RunService:IsStudio() or DevConfig.QuickStart ~= "MapTest" then
		return nil
	end
	local workshop = Workspace:FindFirstChild("MapWorkshop")
	local map = workshop and workshop:FindFirstChild(DevConfig.MapTest)
	local spawns = map and map:FindFirstChild("Spawns")
	local team = spawns and spawns:FindFirstChild("TeamA")
	if not team then
		warn("[REALITY 2059] MapTest: no existe Workspace.MapWorkshop." .. tostring(DevConfig.MapTest) .. ".Spawns.TeamA (construye el mapa desde la Command Bar)")
		return nil
	end
	local list = {}
	for _, spawn in team:GetChildren() do
		if spawn:IsA("BasePart") then
			table.insert(list, spawn)
		end
	end
	return if #list > 0 then list else nil
end

-- A match sets where `player` spawns (nil clears it).
function FreeRoamService:SetSpawnProvider(player: Player, provider: (() -> CFrame?)?)
	self._spawnProviders[player] = provider
end

-- Takes the player out (end of a match): no respawn, character removed.
function FreeRoamService:Remove(player: Player)
	self._inFreeRoam[player] = nil
	self._safe[player] = nil
	local character = player.Character
	if character then
		player.Character = nil
		character:Destroy()
	end
end

function FreeRoamService:_nextSpawn(player: Player?): CFrame
	local provider = player and self._spawnProviders[player]
	local provided = provider and provider()
	if provided then
		return provided
	end
	local testSpawns = mapTestSpawns()
	if testSpawns then
		self._spawnIndex = self._spawnIndex % #testSpawns + 1
		return testSpawns[self._spawnIndex].CFrame
	end
	local spawns = self._world:FindFirstChild("Spawns")
	local list = if spawns then spawns:GetChildren() else {}
	if #list == 0 then
		return CFrame.new(Config.CityCenter + Vector3.new(0, 1, 0))
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	self._spawnIndex = self._spawnIndex % #list + 1
	return (list[self._spawnIndex] :: BasePart).CFrame
end

function FreeRoamService:_spawn(player: Player)
	local draft = self._drafts[player]
	if not draft or not self._avatars:LoadCharacter(player, draft) then
		return
	end
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local spawnedHumanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not rootPart or not rootPart:IsA("BasePart") or not spawnedHumanoid then
		return
	end
	local movement = Config.Movement
	spawnedHumanoid.WalkSpeed = movement.WalkSpeed
	spawnedHumanoid.UseJumpPower = true
	spawnedHumanoid.JumpPower = movement.JumpPower
	spawnedHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	local spot = self:_nextSpawn(player)
	local lift = spawnedHumanoid.HipHeight + rootPart.Size.Y * 0.5 + 0.2
	-- Stream the surroundings first so the player never lands in an empty
	-- world (city scenes are Persistent; props around the spot may not be).
	pcall(function()
		player:RequestStreamAroundAsync(spot.Position, 5)
	end)
	character:PivotTo(spot + Vector3.new(0, lift, 0))
	self._safe[player] = spot + Vector3.new(0, lift, 0)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.Died:Once(function()
			task.delay(RESPAWN_SECONDS, function()
				if self._inFreeRoam[player] and player.Parent == Players and player.Character == character then
					self:_spawn(player)
				end
			end)
		end)
	end
end

function FreeRoamService:Start()
	Players.CharacterAutoLoads = false
	-- The old invisible capsule would replace every avatar if it were left
	-- in StarterPlayer (e.g. saved into the place).
	local capsule = StarterPlayer:FindFirstChild("StarterCharacter")
	if capsule and capsule:GetAttribute("Reality2059Capsule") then
		capsule:Destroy()
	end
	-- A default avatar that spawned before autoload was switched off.
	for _, player in Players:GetPlayers() do
		if player.Character and not self._inFreeRoam[player] then
			player.Character:Destroy()
			player.Character = nil
		end
	end
	self._enter.OnServerInvoke = function(player: Player, candidate: any)
		if not self._rateLimiter:Allow(player.UserId) then
			return { ok = false, errorCode = "RATE_LIMITED" }
		end
		-- MODO LIBRE is locked for players; Studio keeps it for testing, and
		-- match players (with a spawn provider) always get in.
		if PartyConfig.Modes.free.locked and not RunService:IsStudio() and not self._spawnProviders[player] then
			return { ok = false, errorCode = "MODE_LOCKED" }
		end
		local valid, validationError = CharacterValidator.validate(candidate)
		if not valid then
			return { ok = false, errorCode = "INVALID_CHARACTER", message = validationError }
		end
		self._drafts[player] = candidate
		self._inFreeRoam[player] = true
		self:_spawn(player)
		return { ok = player.Character ~= nil, errorCode = if player.Character then nil else "SPAWN_FAILED" }
	end
	self._leave.OnServerInvoke = function(player: Player)
		self._inFreeRoam[player] = nil
		local character = player.Character
		if character then
			player.Character = nil
			character:Destroy()
		end
		return { ok = true }
	end
	Players.PlayerRemoving:Connect(function(player)
		self._inFreeRoam[player] = nil
		self._spawnProviders[player] = nil
		self._drafts[player] = nil
		self._safe[player] = nil
		self._rateLimiter:Remove(player.UserId)
	end)
	task.spawn(function()
		while true do
			task.wait(Config.FallRecovery.CheckInterval)
			self:_checkFalls()
		end
	end)
end

-- Remembers each roaming player's last grounded spot and puts them back
-- there when they drop below the ground (a hole in the collision, the map
-- edge), instead of waiting for the fall to kill them.
function FreeRoamService:_checkFalls()
	local ground = self._world:FindFirstChild("Ground")
	if not ground or not ground:IsA("BasePart") then
		return
	end
	local floor = ground.Position.Y + ground.Size.Y / 2
	for player in self._inFreeRoam do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		if humanoid and rootPart and rootPart:IsA("BasePart") and humanoid.Health > 0 then
			local position = rootPart.Position
			if position.Y < floor - Config.FallRecovery.BelowFloor then
				local safe = self._safe[player] or self:_nextSpawn(player)
				rootPart.AssemblyLinearVelocity = Vector3.zero
				character:PivotTo(safe + Vector3.new(0, 2, 0))
			elseif humanoid.FloorMaterial ~= Enum.Material.Air and position.Y >= floor - 1 then
				self._safe[player] = CFrame.new(position) * rootPart.CFrame.Rotation
			end
		end
	end
end

return FreeRoamService
