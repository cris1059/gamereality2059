--!strict

-- Standard R15 avatars from saved characters (Character/AvatarDescription):
--  * preview models for the client (MORPHLAB, lobby rings): only the catalog
--    part (face, hair, outfit, accessories), built once per combination and
--    kept in ReplicatedStorage (Runtime/AvatarModels); the client clones one
--    and paints skin, scales and cyberware itself, so those change instantly;
--  * a pool of random looks for the city pedestrians (Runtime/PedestrianLooks);
--  * the player's real character in the world (LoadCharacter).
-- Catalog items load through HumanoidDescription: players need not own them.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local CharacterValidator = require(root.Validation.CharacterValidator)
local AvatarDescription = require(root.Character.AvatarDescription)
local R15Cyberware = require(root.Character.R15Cyberware)
local RandomCharacter = require(root.Character.RandomCharacter)
local RateLimiter = require(script.Parent.RateLimiter)

local AvatarService = {}
AvatarService.__index = AvatarService

-- Cached preview models; older ones (unused for a minute) are dropped.
local MAX_CACHED = 60
local EVICT_AFTER_SECONDS = 60
local BUILD_TIMEOUT_SECONDS = 25
local PEDESTRIAN_LOOKS = 10

-- Builds an R15 rig from a description; scripts are removed (previews and
-- pool models are never controlled by a player).
function AvatarService.BuildModel(description: HumanoidDescription): (Model?, string?)
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		return nil, tostring(result)
	end
	local model = result :: Model
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		end
	end
	model:SetAttribute("RigStandard", "R15Avatar")
	return model, nil
end

function AvatarService.new(runtime: Folder)
	local self = setmetatable({}, AvatarService)
	self._runtime = runtime
	local cache = Instance.new("Folder")
	cache.Name = "AvatarModels"
	cache.Parent = runtime
	self._cache = cache
	self._models = {} :: { [string]: Model }
	self._lastUsed = {} :: { [string]: number }
	self._building = {} :: { [string]: boolean }
	-- Editing in MORPHLAB asks for a model on every item change.
	self._limiter = RateLimiter.new(40, 10)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	local remote = Instance.new("RemoteFunction")
	remote.Name = RemoteNames.AvatarModel
	remote.Parent = remotes
	self._remote = remote
	return self
end

function AvatarService:_evict()
	local count = 0
	for _ in self._models do
		count += 1
	end
	if count <= MAX_CACHED then
		return
	end
	local now = os.clock()
	for key, model in self._models do
		if now - (self._lastUsed[key] or 0) > EVICT_AFTER_SECONDS then
			self._models[key] = nil
			self._lastUsed[key] = nil
			model:Destroy()
		end
	end
end

-- The preview model for a character's catalog items (cached; yields while
-- the items load).
function AvatarService:GetModel(draft): (Model?, string?)
	local key = AvatarDescription.ItemsKey(draft)
	if self._building[key] then
		local deadline = os.clock() + BUILD_TIMEOUT_SECONDS
		while self._building[key] and os.clock() < deadline do
			task.wait(0.1)
		end
	end
	local cached = self._models[key]
	if cached and cached.Parent then
		self._lastUsed[key] = os.clock()
		return cached, nil
	end
	self._building[key] = true
	local model, problem = AvatarService.BuildModel(AvatarDescription.Build(draft, false))
	if not model then
		-- An item that no longer loads (taken off the catalog) must not leave
		-- the player without an avatar: fall back to the plain body.
		warn(string.format("[REALITY 2059] Avatar items failed (%s): %s", key, tostring(problem)))
		model, problem = AvatarService.BuildModel(Instance.new("HumanoidDescription"))
	end
	self._building[key] = nil
	if not model then
		return nil, problem
	end
	model.Name = "Avatar"
	model:SetAttribute("ItemsKey", key)
	model.Parent = self._cache
	self._models[key] = model
	self._lastUsed[key] = os.clock()
	self:_evict()
	return model, nil
end

-- Random looks the pedestrians are drawn from (each keeps its draft as JSON).
function AvatarService:_buildPedestrianLooks()
	local folder = Instance.new("Folder")
	folder.Name = "PedestrianLooks"
	folder.Parent = self._runtime
	local random = Random.new(2059)
	for index = 1, PEDESTRIAN_LOOKS do
		local draft = RandomCharacter.create(random)
		local model = AvatarService.BuildModel(AvatarDescription.Build(draft, false))
		if model then
			model.Name = "Look" .. index
			model:SetAttribute("Draft", HttpService:JSONEncode(draft))
			model.Parent = folder
		end
	end
	folder:SetAttribute("Ready", true)
end

-- Spawns the player's real character: the R15 avatar with its skin, scales
-- and cyberware. Yields while the avatar loads.
function AvatarService:LoadCharacter(player: Player, draft): (boolean, string?)
	local ok, problem = pcall(function()
		player:LoadCharacterWithHumanoidDescription(AvatarDescription.Build(draft, true))
	end)
	local character = player.Character
	if not ok or not character then
		warn("[REALITY 2059] Avatar spawn failed for " .. player.Name .. ": " .. tostring(problem))
		return false, "SPAWN_FAILED"
	end
	-- The chosen face, drawn on the blocky head.
	AvatarDescription.ApplyFaceExpression(character, draft)
	R15Cyberware.Build(character, draft.cyberwareIds, AvatarDescription.CyberwareStyle(draft))
	character:SetAttribute("ClassId", draft.classId)
	return true, nil
end

function AvatarService:Start()
	self._remote.OnServerInvoke = function(player: Player, candidate: any)
		if not self._limiter:Allow(player.UserId) then
			return nil, "RATE_LIMITED"
		end
		if not CharacterValidator.validate(candidate) then
			return nil, "INVALID_CHARACTER"
		end
		return self:GetModel(candidate)
	end
	Players.PlayerRemoving:Connect(function(player)
		self._limiter:Remove(player.UserId)
	end)
	task.spawn(self._buildPedestrianLooks, self)
end

return AvatarService
