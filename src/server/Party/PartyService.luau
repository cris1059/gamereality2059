--!strict

-- Squads with a mode-specific capacity (5 normally, 10 in private rooms).
-- PartyRequest (RemoteFunction): action + argument, validated by PartyCore.
-- PartyUpdate (to members): the party snapshot, or nil after leaving.
-- PartyInvite (to the invitee): who invites and to which party.
-- PartyLaunch (to members): start MODO LIBRE together.
-- Matchmaking modes go through MatchmakingService.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MemoryStoreService = game:GetService("MemoryStoreService")
local TeleportService = game:GetService("TeleportService")
local RunService = game:GetService("RunService")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local PartyConfig = require(root.Config.PartyConfig)
local MatchConfig = require(root.Config.MatchConfig)
local RemoteNames = require(root.Network.RemoteNames)
local PartyCore = require(script.Parent.PartyCore)
local MatchmakingService = require(script.Parent.MatchmakingService)
local RateLimiter = require(script.Parent.Parent.Services.RateLimiter)

local PartyService = {}
PartyService.__index = PartyService

local PRIVATE_CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
-- Shared code -> server map for private rooms. Fetched on first use and only
-- on published servers: asking for it in an unpublished place throws, which
-- used to stop the whole server script from loading. Without it (Studio or
-- MemoryStore down) codes still work between players of the same server.
local privateRoomMap: MemoryStoreSortedMap? = nil
local function roomMap(): MemoryStoreSortedMap?
	if privateRoomMap or RunService:IsStudio() or game.JobId == "" then
		return privateRoomMap
	end
	local ok, map = pcall(function()
		return MemoryStoreService:GetSortedMap(PartyConfig.PrivateRooms.CodeMapName)
	end)
	if ok then
		privateRoomMap = map
	else
		warn("[REALITY 2059] MemoryStore no disponible para salas privadas: " .. tostring(map))
	end
	return privateRoomMap
end

local function normalizePrivateCode(value: any): string?
	if type(value) ~= "string" then
		return nil
	end
	local code = string.upper(value):gsub("[^A-Z0-9]", "")
	return if #code == PartyConfig.PrivateRooms.CodeLength then code else nil
end

local function create(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function PartyService.new(runtime: Folder, dataService: any)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	local self = setmetatable({
		_data = dataService,
		_state = PartyCore.new(),
		_details = {} :: { [string]: string? },
		_privateCodes = {} :: { [string]: string }, -- code -> local party id
		_partyCodes = {} :: { [string]: string }, -- local party id -> code
		_codeRandom = Random.new(),
		_matchCounter = 0,
		_matchmaking = MatchmakingService.new(),
		_limiter = RateLimiter.new(PartyConfig.MaxRequestsPerWindow, PartyConfig.RequestWindowSeconds),
		_request = create(remotes, "RemoteFunction", RemoteNames.PartyRequest) :: RemoteFunction,
		_update = create(remotes, "RemoteEvent", RemoteNames.PartyUpdate) :: RemoteEvent,
		_invite = create(remotes, "RemoteEvent", RemoteNames.PartyInvite) :: RemoteEvent,
		_launch = create(remotes, "RemoteEvent", RemoteNames.PartyLaunch) :: RemoteEvent,
	}, PartyService)
	return self
end

-- MatchService: private rooms play their match on this server.
function PartyService:SetMatchService(matchService: any)
	self._matchService = matchService
end

-- The private room's match, here: the room becomes "playing" (the lobby's
-- match screens stay away; MatchService drives the clients) and goes back to
-- idle when the match ends.
function PartyService:_startLocalMatch(party: PartyCore.Party): (boolean, string?)
	local players = {}
	for _, userId in party.members do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(players, player)
		end
	end
	local ok, errorCode = self._matchService:Start(players, function()
		if self._state.parties[party.id] == party and party.status == "playing" then
			party.status = "idle"
			table.clear(party.ready)
			party.match = nil
			self:_broadcast(party)
		end
	end)
	if not ok then
		return false, errorCode
	end
	party.status = "playing"
	self._details[party.id] = nil
	return true, nil
end

function PartyService:_snapshot(party: PartyCore.Party)
	local members = {}
	for _, userId in party.members do
		local player = Players:GetPlayerByUserId(userId)
		local data = self._data:GetData(userId)
		local character = data and data.character
		table.insert(members, {
			userId = userId,
			name = if player then player.DisplayName else "?",
			ready = party.ready[userId] == true or userId == party.leader,
			isLeader = userId == party.leader,
			character = if character and character.creationComplete then character else nil,
		})
	end
	local match = nil
	if party.match then
		local accepted = {}
		for userId in party.match.accepted do
			table.insert(accepted, userId)
		end
		match = {
			id = party.match.id,
			deadline = party.match.deadline,
			phaseEnds = party.match.phaseEnds,
			accepted = accepted,
			simulated = party.match.simulated,
			map = party.match.map,
			teams = party.match.teams,
			result = party.match.result,
		}
	end
	return {
		id = party.id,
		mode = party.mode,
		status = party.status,
		detail = self._details[party.id],
		maxMembers = PartyCore.capacity(party.mode),
		privateCode = self._partyCodes[party.id],
		members = members,
		match = match,
		serverTime = Workspace:GetServerTimeNow(),
	}
end

function PartyService:_generatePrivateCode(party: PartyCore.Party): (string?, string?)
	local existing = self._partyCodes[party.id]
	if existing then
		return existing, nil
	end
	for _ = 1, 20 do
		local parts = table.create(PartyConfig.PrivateRooms.CodeLength)
		for index = 1, PartyConfig.PrivateRooms.CodeLength do
			local at = self._codeRandom:NextInteger(1, #PRIVATE_CODE_CHARS)
			parts[index] = string.sub(PRIVATE_CODE_CHARS, at, at)
		end
		local code = table.concat(parts)
		if not self._privateCodes[code] then
			local record = { placeId = game.PlaceId, jobId = game.JobId, partyId = party.id }
			local claimed = true
			-- Studio codes are local. Published servers atomically claim the code
			-- in MemoryStore so two rooms can never receive the same one.
			local map = roomMap()
			if map then
				claimed = false
				local stored = pcall(function()
					map:UpdateAsync(code, function(current)
						if current == nil then
							claimed = true
							return record
						end
						return nil
					end, PartyConfig.PrivateRooms.CodeSeconds)
				end)
				if not stored then
					return nil, "PRIVATE_CODE_UNAVAILABLE"
				end
			end
			if claimed then
				self._privateCodes[code] = party.id
				self._partyCodes[party.id] = code
				return code, nil
			end
		end
	end
	return nil, "PRIVATE_CODE_UNAVAILABLE"
end

function PartyService:_removePrivateCode(partyId: string)
	local code = self._partyCodes[partyId]
	if not code then
		return
	end
	self._partyCodes[partyId] = nil
	self._privateCodes[code] = nil
	local map = roomMap()
	if map then
		task.spawn(function()
			pcall(map.RemoveAsync, map, code)
		end)
	end
end

function PartyService:_joinLocalPrivate(player: Player, code: string, partyId: string): (boolean, string?)
	if self._privateCodes[code] ~= partyId then
		return false, "PRIVATE_ROOM_NOT_FOUND"
	end
	local before = PartyCore.get(self._state, player.UserId)
	local ok, errorCode = PartyCore.joinPrivate(self._state, player.UserId, partyId)
	if ok then
		if before and before.id ~= partyId then
			self:_stopSearch(before)
			self:_broadcast(before)
			if not self._state.parties[before.id] then
				self:_removePrivateCode(before.id)
			end
		end
		self:_broadcast(self._state.parties[partyId])
	end
	return ok, errorCode
end

function PartyService:_joinPrivateCode(player: Player, rawCode: any): (boolean, string?, any?)
	local code = normalizePrivateCode(rawCode)
	if not code then
		return false, "INVALID_PRIVATE_CODE", nil
	end
	local localPartyId = self._privateCodes[code]
	if localPartyId then
		local ok, errorCode = self:_joinLocalPrivate(player, code, localPartyId)
		return ok, errorCode, if ok then { code = code, teleporting = false } else nil
	end
	-- Not on this server: other servers' rooms are only known through MemoryStore.
	local map = roomMap()
	if not map then
		return false, "PRIVATE_ROOM_NOT_FOUND", nil
	end
	local ok, record = pcall(map.GetAsync, map, code)
	if not ok then
		return false, "PRIVATE_CODE_UNAVAILABLE", nil
	end
	if type(record) ~= "table" or type(record.jobId) ~= "string" or record.jobId == "" or record.placeId ~= game.PlaceId then
		return false, "PRIVATE_ROOM_NOT_FOUND", nil
	end
	if record.jobId == game.JobId and type(record.partyId) == "string" then
		local joined, errorCode = self:_joinLocalPrivate(player, code, record.partyId)
		return joined, errorCode, if joined then { code = code, teleporting = false } else nil
	end
	local teleported, teleportError = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = record.jobId
		options:SetTeleportData({ privateRoomCode = code })
		TeleportService:TeleportAsync(record.placeId, { player }, options)
	end)
	if not teleported then
		return false, "TELEPORT_FAILED:" .. tostring(teleportError), nil
	end
	return true, nil, { code = code, teleporting = true }
end

function PartyService:_broadcast(party: PartyCore.Party?)
	if not party or not self._state.parties[party.id] then
		return
	end
	local snapshot = self:_snapshot(party)
	for _, userId in party.members do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			self._update:FireClient(player, snapshot)
		end
	end
end

local function playersOf(party: PartyCore.Party): { Player }
	local result = {}
	for _, userId in party.members do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			table.insert(result, player)
		end
	end
	return result
end

-- Roster / mode changes stop an active search.
function PartyService:_stopSearch(party: PartyCore.Party?)
	if party then
		self._matchmaking:Cancel(party.id)
	end
end

function PartyService:_start(player: Player): (boolean, string?)
	local ok, errorCode = PartyCore.canStart(self._state, player.UserId)
	if not ok then
		return false, errorCode
	end
	local party = PartyCore.get(self._state, player.UserId) :: PartyCore.Party
	self._details[party.id] = nil
	if not PartyConfig.Modes[party.mode].matchmaking then
		for _, member in playersOf(party) do
			self._launch:FireClient(member, { mode = party.mode })
		end
		return true, nil
	end
	if party.mode == "private" and MatchConfig.LocalPrivateMatches and self._matchService then
		return self:_startLocalMatch(party)
	end
	party.status = "searching"
	local queued, queueError = self._matchmaking:Queue(party.mode, party.id, playersOf(party), function(status: string, detail: string?)
		if self._state.parties[party.id] ~= party then
			return
		end
		-- Late reports of an older search or teleport must not touch a newer state.
		if status == "found" and party.status ~= "searching" then
			return
		end
		if status == "failed" and party.status ~= "searching" and party.status ~= "launching" then
			return
		end
		if status == "found" then
			self:_beginAccept(party)
			-- Readiness is the confirmation for an invited private room; unlike
			-- public matchmaking, its players do not accept a second prompt.
			if party.mode == "private" and party.status == "found" and party.match then
				for _, userId in party.members do
					party.match.accepted[userId] = true
				end
				self:_launchMatch(party)
			end
			return
		end
		party.status = if status == "failed" then "idle" else "searching"
		if status == "failed" then
			party.match = nil
		end
		self._details[party.id] = detail
		self:_broadcast(party)
	end)
	if not queued then
		party.status = "idle"
		self._details[party.id] = queueError
		self:_broadcast(party)
		return false, queueError
	end
	return true, nil
end

-- ------------------------------------------------------------ match flow --

local function sameMatch(state: PartyCore.State, party: PartyCore.Party, matchId: number, status: string): boolean
	return state.parties[party.id] == party and party.status == status and party.match ~= nil and party.match.id == matchId
end

-- A match was found: every member has AcceptSeconds to accept.
function PartyService:_beginAccept(party: PartyCore.Party)
	self._matchCounter += 1
	local matchId = self._matchCounter
	local simulated = self._matchmaking:IsSimulated(party.id)
	local deadline = Workspace:GetServerTimeNow() + PartyConfig.AcceptSeconds
	if not PartyCore.beginMatch(self._state, party.id, matchId, deadline, simulated) then
		self._matchmaking:Cancel(party.id)
		return
	end
	local maps = PartyConfig.Maps[party.mode]
	party.match.map = if maps then maps[1] else nil
	self._details[party.id] = nil
	self:_broadcast(party)
	task.delay(PartyConfig.AcceptSeconds + 0.5, function()
		if PartyCore.expireMatch(self._state, party.id, matchId, Workspace:GetServerTimeNow()) then
			self._matchmaking:Cancel(party.id)
			self._details[party.id] = "MATCH_EXPIRED"
			self:_broadcast(party)
		end
	end)
end

-- Everyone accepted: teleport (real matches) or play the Studio simulation.
function PartyService:_launchMatch(party: PartyCore.Party)
	if not PartyCore.launchMatch(self._state, party.id) then
		self._matchmaking:Cancel(party.id)
		return
	end
	local matchId = party.match.id
	local confirmed, how = self._matchmaking:Confirm(party.id)
	if not confirmed then
		party.status = "idle"
		party.match = nil
		self._details[party.id] = "MATCH_GONE"
		self:_broadcast(party)
		return
	end
	if how ~= "simulated" then
		self:_broadcast(party)
		-- A teleport that never happens must not trap the squad on the loading screen.
		task.delay(PartyConfig.TeleportTimeoutSeconds, function()
			if sameMatch(self._state, party, matchId, "launching") then
				party.status = "idle"
				party.match = nil
				self._details[party.id] = "TELEPORT_FAILED"
				self:_broadcast(party)
			end
		end)
		return
	end
	local simulation = PartyConfig.Simulation
	party.match.phaseEnds = Workspace:GetServerTimeNow() + simulation.LoadSeconds
	self:_broadcast(party)
	task.delay(simulation.LoadSeconds, function()
		if not sameMatch(self._state, party, matchId, "launching") then
			return
		end
		-- Public queues keep the squad together. A private room is the complete
		-- match, split deterministically into two teams of up to five.
		local ours, theirs = {}, {}
		for index, userId in party.members do
			local member = Players:GetPlayerByUserId(userId)
			local team = if party.mode == "private" and index > PartyConfig.TeamSize then theirs else ours
			table.insert(team, if member then member.DisplayName else "?")
		end
		while #ours < PartyConfig.TeamSize do
			table.insert(ours, "COMPAÑERO SIMULADO " .. (#ours + 1))
		end
		while #theirs < PartyConfig.TeamSize do
			table.insert(theirs, "RIVAL SIMULADO " .. (#theirs + 1))
		end
		party.status = "ingame"
		party.match.teams = { ours = ours, theirs = theirs }
		party.match.phaseEnds = Workspace:GetServerTimeNow() + simulation.RoomSeconds
		self:_broadcast(party)
		task.delay(simulation.RoomSeconds, function()
			if not sameMatch(self._state, party, matchId, "ingame") then
				return
			end
			party.status = "results"
			party.match.result = { simulated = true }
			self:_broadcast(party)
		end)
	end)
end

function PartyService:_handle(player: Player, action: any, argument: any): (boolean, string?, any?)
	local state = self._state
	local userId = player.UserId
	local now = os.time()
	local before = PartyCore.get(state, userId)

	if action == "create_private" then
		if not before then
			PartyCore.create(state, userId)
		end
		local party = PartyCore.get(state, userId) :: PartyCore.Party
		if party.leader ~= userId then
			return false, "NOT_LEADER", nil
		end
		if party.status ~= "idle" then
			return false, "PARTY_BUSY", nil
		end
		if party.mode ~= "private" then
			local changed, changeError = PartyCore.setMode(state, userId, "private")
			if not changed then
				return false, changeError, nil
			end
			self:_stopSearch(party)
		end
		local code, codeError = self:_generatePrivateCode(party)
		if not code then
			return false, codeError, nil
		end
		self:_broadcast(party)
		return true, nil, { code = code, teleporting = false }
	elseif action == "join_private" then
		return self:_joinPrivateCode(player, argument)
	elseif action == "invite" then
		local target = if type(argument) == "number" then Players:GetPlayerByUserId(argument) else nil
		if not target then
			return false, "PLAYER_NOT_FOUND"
		end
		local ok, errorCode = PartyCore.invite(state, userId, target.UserId, now)
		if ok then
			local party = PartyCore.get(state, userId) :: PartyCore.Party
			self._invite:FireClient(target, { partyId = party.id, fromName = player.DisplayName, mode = party.mode })
			self:_broadcast(party)
		end
		return ok, errorCode
	elseif action == "accept" then
		local ok, errorCode = PartyCore.accept(state, userId, argument, now)
		if ok then
			self:_stopSearch(before)
			self:_broadcast(before)
			if before and not state.parties[before.id] then
				self:_removePrivateCode(before.id)
			end
			local party = PartyCore.get(state, userId)
			self:_stopSearch(party)
			self:_broadcast(party)
		end
		return ok, errorCode
	elseif action == "decline" then
		return PartyCore.decline(state, userId, argument)
	elseif action == "leave" then
		local ok, errorCode = PartyCore.leave(state, userId)
		if ok then
			self:_stopSearch(before)
			self:_broadcast(before)
			self._update:FireClient(player, nil)
			if before and not state.parties[before.id] then
				self._details[before.id] = nil
				self:_removePrivateCode(before.id)
			end
		end
		return ok, errorCode
	elseif action == "kick" then
		local target = if type(argument) == "number" then Players:GetPlayerByUserId(argument) else nil
		local ok, errorCode = PartyCore.kick(state, userId, argument)
		if ok then
			self:_stopSearch(before)
			self:_broadcast(before)
			if target then
				self._update:FireClient(target, nil)
			end
		end
		return ok, errorCode
	elseif action == "ready" then
		local ok, errorCode = PartyCore.setReady(state, userId, argument)
		if ok then
			self:_broadcast(before)
		end
		return ok, errorCode
	elseif action == "mode" then
		if not before then
			PartyCore.create(state, userId)
		end
		local ok, errorCode = PartyCore.setMode(state, userId, argument)
		if ok then
			local party = PartyCore.get(state, userId)
			self:_stopSearch(party)
			if argument ~= "private" and party then
				self:_removePrivateCode(party.id)
			end
			self:_broadcast(party)
		end
		return ok, errorCode
	elseif action == "start" then
		if not before then
			PartyCore.create(state, userId)
		end
		local ok, errorCode = self:_start(player)
		self:_broadcast(PartyCore.get(state, userId))
		return ok, errorCode
	elseif action == "cancel" then
		if not before or before.status ~= "searching" then
			return false, "NOT_SEARCHING"
		end
		self:_stopSearch(before)
		before.status = "idle"
		self._details[before.id] = "CANCELADO"
		self:_broadcast(before)
		return true, nil
	elseif action == "accept_match" then
		local ok, errorCode = PartyCore.acceptMatch(state, userId, Workspace:GetServerTimeNow())
		if not ok then
			return false, errorCode
		end
		local party = before :: PartyCore.Party
		if PartyCore.allAccepted(party) then
			self:_launchMatch(party)
		end
		self:_broadcast(party)
		return true, nil
	elseif action == "decline_match" then
		local ok, errorCode = PartyCore.declineMatch(state, userId)
		if ok then
			self:_stopSearch(before)
			self._details[(before :: PartyCore.Party).id] = "MATCH_DECLINED"
			self:_broadcast(before)
		end
		return ok, errorCode
	elseif action == "return_lobby" then
		local ok, errorCode = PartyCore.returnToLobby(state, userId)
		if ok then
			self._details[(before :: PartyCore.Party).id] = nil
			self:_broadcast(before)
		end
		return ok, errorCode
	elseif action == "get" then
		if before then
			self:_broadcast(before)
		end
		for partyId in PartyCore.pendingInvites(state, userId, now) do
			local party = state.parties[partyId]
			local leader = party and Players:GetPlayerByUserId(party.leader)
			if party and leader then
				self._invite:FireClient(player, { partyId = partyId, fromName = leader.DisplayName, mode = party.mode })
			end
		end
		return true, nil
	end
	return false, "INVALID_ACTION"
end

function PartyService:Start()
	self._request.OnServerInvoke = function(player: Player, action: any, argument: any)
		if not self._limiter:Allow(player.UserId) then
			return { ok = false, errorCode = "RATE_LIMITED" }
		end
		local called, result, errorCode, data = pcall(self._handle, self, player, action, argument)
		if not called then
			warn("[REALITY 2059] Party request failed: " .. tostring(result))
			return { ok = false, errorCode = "SERVER_ERROR" }
		end
		return { ok = result, errorCode = errorCode, data = data }
	end
	Players.PlayerAdded:Connect(function(player)
		task.defer(function()
			local joinData = player:GetJoinData()
			local teleportData = joinData and joinData.TeleportData
			local code = teleportData and normalizePrivateCode(teleportData.privateRoomCode)
			local partyId = code and self._privateCodes[code]
			if code and partyId then
				local ok, errorCode = self:_joinLocalPrivate(player, code, partyId)
				if not ok then
					warn("[REALITY 2059] Private room join failed: " .. tostring(errorCode))
					self._update:FireClient(player, { privateJoinError = errorCode })
				end
			end
		end)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local party = PartyCore.get(self._state, player.UserId)
		if party then
			PartyCore.leave(self._state, player.UserId)
			self:_stopSearch(party)
			self:_broadcast(party)
			if not self._state.parties[party.id] then
				self._details[party.id] = nil
				self:_removePrivateCode(party.id)
			end
		end
		self._state.invites[player.UserId] = nil
		self._limiter:Remove(player.UserId)
	end)
end

return PartyService
