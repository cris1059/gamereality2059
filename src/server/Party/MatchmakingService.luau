--!strict

-- Cross-server matchmaking for PARTIDA RÁPIDA and COMPETITIVO.
--
-- 1. A party queues a ticket in a MemoryStore sorted map per mode (keys sort
--    by queue time, so the oldest tickets match first).
-- 2. Every server with tickets polls; the one holding the short lock for the
--    mode groups whole parties until MinPlayers..MaxPlayers is reached,
--    reserves a server and writes an assignment for every ticket in the match.
-- 3. Each server reads its own tickets' assignments and reports "found".
--    The party then accepts (PartyService); Confirm teleports it, Abort
--    drops the assignment.
--
-- Requirements (not available offline): a published experience, the match
-- place id in PartyConfig.Matchmaking.PlaceIds (the same place id works: the
-- reserved server starts in match mode) and API access. Teleport does not
-- work inside Studio.
--
-- Studio simulation: with no place configured, PartyConfig.StudioSimulation
-- makes a search "find" a simulated match after a few seconds so the whole
-- flow can be walked through. It is refused outside Studio.

local HttpService = game:GetService("HttpService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local PartyConfig = require(root.Config.PartyConfig)

local Settings = PartyConfig.Matchmaking
local LOCK_SECONDS = 10
local ASSIGNMENT_SECONDS = 90

local MatchmakingService = {}
MatchmakingService.__index = MatchmakingService

export type Ticket = {
	key: string?,
	mode: string,
	partyId: string,
	players: { Player },
	simulated: boolean,
	assignment: any?,
	-- (status, detail?) -> (); status: searching | found | failed
	report: (string, string?) -> (),
}

function MatchmakingService.new()
	local self = setmetatable({
		_tickets = {} :: { [string]: Ticket },
		_found = {} :: { [string]: Ticket },
		_running = false,
		_serverId = if game.JobId ~= "" then game.JobId else HttpService:GenerateGUID(false),
	}, MatchmakingService)
	return self
end

local function queueMap(mode: string)
	return MemoryStoreService:GetSortedMap(Settings.QueueMapName .. mode)
end

local function assignmentMap()
	return MemoryStoreService:GetSortedMap(Settings.QueueMapName .. "assignments")
end

-- Pure grouping rule for the tests: entries in queue order
-- ({ key, size }); returns the keys of the first match or nil.
function MatchmakingService.Group(entries: { { key: string, size: number } }, minPlayers: number, maxPlayers: number): { string }?
	local chosen, total = {}, 0
	for _, entry in entries do
		if total + entry.size <= maxPlayers then
			table.insert(chosen, entry.key)
			total += entry.size
		end
		if total == maxPlayers then
			break
		end
	end
	return if total >= minPlayers then chosen else nil
end

function MatchmakingService:Queue(mode: string, partyId: string, players: { Player }, report: (string, string?) -> ()): (boolean, string?)
	local placeId = Settings.PlaceIds[mode]
	if not placeId then
		return false, "INVALID_MODE"
	end
	if #players > Settings.MaxPlayers[mode] then
		return false, "PARTY_TOO_LARGE"
	end
	if placeId == 0 then
		if not (RunService:IsStudio() and PartyConfig.StudioSimulation) then
			return false, "MATCH_PLACE_NOT_CONFIGURED"
		end
		-- Simulated search: "found" after a few seconds, unless cancelled.
		local ticket: Ticket = { key = nil, mode = mode, partyId = partyId, players = players, simulated = true, assignment = nil, report = report }
		self._tickets[partyId] = ticket
		local search = PartyConfig.Simulation.SearchSeconds
		report("searching", nil)
		task.delay(search.Min + math.random() * (search.Max - search.Min), function()
			if self._tickets[partyId] == ticket then
				self._tickets[partyId] = nil
				self._found[partyId] = ticket
				report("found", nil)
			end
		end)
		return true, nil
	end
	-- A private room owns its reserved server. It is never written to the
	-- shared queue, so another party cannot be grouped into the same match.
	local modeInfo = PartyConfig.Modes[mode]
	if modeInfo and modeInfo.privateServer then
		local ok, accessCode = pcall(TeleportService.ReserveServer, TeleportService, placeId)
		if not ok then
			return false, "TELEPORT_FAILED:" .. tostring(accessCode)
		end
		local ticket: Ticket = {
			key = nil,
			mode = mode,
			partyId = partyId,
			players = players,
			simulated = false,
			assignment = { placeId = placeId, accessCode = accessCode, mode = mode },
			report = report,
		}
		self._found[partyId] = ticket
		task.defer(function()
			if self._found[partyId] == ticket then
				report("found", nil)
			end
		end)
		return true, nil
	end
	-- Zero-padded time first so the sorted map keeps queue order.
	local key = string.format("%012d_%s_%s", os.time(), self._serverId:sub(1, 8), partyId)
	local value = { server = self._serverId, partyId = partyId, size = #players }
	local ok, err = pcall(function()
		queueMap(mode):SetAsync(key, value, Settings.TicketSeconds)
	end)
	if not ok then
		return false, "QUEUE_UNAVAILABLE:" .. tostring(err)
	end
	self._tickets[partyId] = { key = key, mode = mode, partyId = partyId, players = players, simulated = false, assignment = nil, report = report }
	report("searching", nil)
	self:_ensureLoop()
	return true, nil
end

-- Stops a search or drops a found match.
function MatchmakingService:Cancel(partyId: string)
	local ticket = self._tickets[partyId] or self._found[partyId]
	self._tickets[partyId] = nil
	self._found[partyId] = nil
	if ticket and ticket.key then
		local key, mode = ticket.key, ticket.mode
		task.spawn(pcall, function()
			queueMap(mode):RemoveAsync(key)
		end)
	end
end

function MatchmakingService:IsSimulated(partyId: string): boolean
	local ticket = self._found[partyId]
	return ticket ~= nil and ticket.simulated
end

-- The squad accepted: teleports it (real matches). Simulated matches return
-- (true, "simulated") and PartyService plays the simulated flow.
function MatchmakingService:Confirm(partyId: string): (boolean, string?)
	local ticket = self._found[partyId]
	if not ticket then
		return false, "NO_MATCH"
	end
	self._found[partyId] = nil
	if ticket.simulated then
		return true, "simulated"
	end
	self:_teleport(ticket, ticket.assignment)
	return true, nil
end

function MatchmakingService:_ensureLoop()
	if self._running then
		return
	end
	self._running = true
	task.spawn(function()
		while next(self._tickets) do
			local modes = {}
			for _, ticket in self._tickets do
				if not ticket.simulated then
					modes[ticket.mode] = true
				end
			end
			for mode in modes do
				local ok, err = pcall(self._matchMode, self, mode)
				if not ok then
					warn("[REALITY 2059] Matchmaking (" .. mode .. "): " .. tostring(err))
				end
			end
			pcall(self._collectAssignments, self)
			pcall(self._renewTickets, self)
			task.wait(Settings.PollSeconds)
		end
		self._running = false
	end)
end

function MatchmakingService:_renewTickets()
	for _, ticket in self._tickets do
		if ticket.key then
			queueMap(ticket.mode):UpdateAsync(ticket.key, function(current)
				return current
			end, Settings.TicketSeconds)
		end
	end
end

-- Only the server holding the mode's lock forms matches.
function MatchmakingService:_matchMode(mode: string)
	local lock = MemoryStoreService:GetSortedMap(Settings.LockMapName)
	local owned = false
	lock:UpdateAsync(mode, function(current)
		if current == nil or current == self._serverId then
			owned = true
			return self._serverId
		end
		return nil
	end, LOCK_SECONDS)
	if not owned then
		return
	end
	local queue = queueMap(mode)
	local items = queue:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	local entries = {}
	for _, item in items do
		table.insert(entries, { key = item.key, size = item.value.size })
	end
	local chosen = MatchmakingService.Group(entries, Settings.MinPlayers[mode], Settings.MaxPlayers[mode])
	if not chosen then
		return
	end
	local placeId = Settings.PlaceIds[mode]
	local accessCode = TeleportService:ReserveServer(placeId)
	local assignments = assignmentMap()
	for _, key in chosen do
		assignments:SetAsync(key, { placeId = placeId, accessCode = accessCode, mode = mode }, ASSIGNMENT_SECONDS)
		queue:RemoveAsync(key)
	end
end

function MatchmakingService:_collectAssignments()
	local assignments = assignmentMap()
	for partyId, ticket in self._tickets do
		if ticket.key then
			local assignment = assignments:GetAsync(ticket.key)
			if assignment then
				self._tickets[partyId] = nil
				assignments:RemoveAsync(ticket.key)
				ticket.assignment = assignment
				self._found[partyId] = ticket
				ticket.report("found", nil)
			end
		end
	end
end

function MatchmakingService:_teleport(ticket: Ticket, assignment: any)
	if RunService:IsStudio() then
		ticket.report("failed", "TELEPORT_UNAVAILABLE")
		return
	end
	local options = Instance.new("TeleportOptions")
	options.ReservedServerAccessCode = assignment.accessCode
	local teleportData: any = { mode = assignment.mode, partyId = ticket.partyId }
	if ticket.mode == "private" then
		local teamA, teamB = {}, {}
		for index, player in ticket.players do
			table.insert(if index <= PartyConfig.TeamSize then teamA else teamB, player.UserId)
		end
		teleportData.teams = { teamA = teamA, teamB = teamB }
	end
	options:SetTeleportData(teleportData)
	local players = {}
	for _, player in ticket.players do
		if player.Parent then
			table.insert(players, player)
		end
	end
	local ok, err = pcall(function()
		TeleportService:TeleportAsync(assignment.placeId, players, options)
	end)
	if not ok then
		ticket.report("failed", "TELEPORT_FAILED:" .. tostring(err))
	end
end

return MatchmakingService
