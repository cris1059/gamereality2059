--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local GameConfig = require(root.Config.GameConfig)
local PlayerState = require(root.State.PlayerState)
local RemoteNames = require(root.Network.RemoteNames)
local CharacterValidator = require(root.Validation.CharacterValidator)
local RateLimiter = require(script.Parent.RateLimiter)

local PlayerBootstrapService = {}
PlayerBootstrapService.__index = PlayerBootstrapService

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing.ClassName == className, string.format("%s must be a %s", name, className))
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function PlayerBootstrapService.new(dataService: any, runtime: Folder)
	local self = setmetatable({}, PlayerBootstrapService)
	self._dataService = dataService
	self._states = {} :: { [number]: any }
	self._running = false
	self._rateLimiter = RateLimiter.new(
		GameConfig.Networking.MaxDraftRequestsPerWindow,
		GameConfig.Networking.RequestWindowSeconds
	)
	local remotes = getOrCreate(runtime, "Folder", RemoteNames.Folder) :: Folder
	self._stateChanged = getOrCreate(remotes, "RemoteEvent", RemoteNames.PlayerStateChanged) :: RemoteEvent
	self._getState = getOrCreate(remotes, "RemoteFunction", RemoteNames.GetPlayerState) :: RemoteFunction
	self._validateDraft = getOrCreate(remotes, "RemoteFunction", RemoteNames.ValidateCharacterDraft) :: RemoteFunction
	self._saveCharacter = getOrCreate(remotes, "RemoteFunction", RemoteNames.SaveCharacter) :: RemoteFunction
	return self
end

function PlayerBootstrapService:_setState(player: Player, result: any)
	self._states[player.UserId] = result
	self._stateChanged:FireClient(player, result)
end

function PlayerBootstrapService:_load(player: Player)
	self:_setState(player, { state = PlayerState.LOADING })
	local result = self._dataService:Load(player.UserId)
	if player.Parent == Players then
		self:_setState(player, result)
	else
		self._dataService:Release(player.UserId)
	end
end

function PlayerBootstrapService:Start()
	assert(not self._running, "PlayerBootstrapService already started")
	self._running = true

	self._getState.OnServerInvoke = function(player: Player)
		return self._states[player.UserId] or { state = PlayerState.LOADING }
	end
	self._validateDraft.OnServerInvoke = function(player: Player, candidate: any)
		if not self._rateLimiter:Allow(player.UserId) then
			return { ok = false, errorCode = "RATE_LIMITED" }
		end
		if not self._dataService:HasSession(player.UserId) then
			return { ok = false, errorCode = "SESSION_NOT_LOADED" }
		end
		local valid, validationError = CharacterValidator.validate(candidate)
		return { ok = valid, errorCode = if valid then nil else "INVALID_CHARACTER", message = validationError }
	end
	self._saveCharacter.OnServerInvoke = function(player: Player, candidate: any)
		if not self._rateLimiter:Allow(player.UserId) then
			return { ok = false, errorCode = "RATE_LIMITED" }
		end
		local ok, saveError = self._dataService:SaveCharacter(player.UserId, candidate)
		if ok then
			local data = self._dataService:GetData(player.UserId)
			local nextState = if data.character.creationComplete then PlayerState.EXISTING_PLAYER else PlayerState.NEW_PLAYER
			self:_setState(player, { state = nextState, data = data })
		end
		return { ok = ok, errorCode = saveError }
	end

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			self:_load(player)
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._states[player.UserId] = nil
		self._rateLimiter:Remove(player.UserId)
		local ok, releaseError = self._dataService:Release(player.UserId)
		if not ok then
			warn(string.format("Failed to release player %d: %s", player.UserId, tostring(releaseError)))
		end
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:_load(player)
		end)
	end

	task.spawn(function()
		while self._running do
			task.wait(GameConfig.Persistence.RenewIntervalSeconds)
			for _, player in Players:GetPlayers() do
				local ok, renewError = self._dataService:Renew(player.UserId)
				if not ok then
					self:_setState(player, {
						state = PlayerState.DATA_ERROR,
						errorCode = renewError,
						message = "Session lease could not be renewed",
					})
				end
			end
		end
	end)
end

function PlayerBootstrapService:Shutdown()
	self._running = false
	for _, player in Players:GetPlayers() do
		self._dataService:Release(player.UserId)
	end
end

return PlayerBootstrapService
