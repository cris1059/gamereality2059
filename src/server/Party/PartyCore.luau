--!strict

-- Party rules on plain user ids (no Instances), so the Studio tests can run
-- them directly. PartyService wraps this with remotes and players.
-- Every function returns (ok, errorCode?).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local PartyConfig = require(root.Config.PartyConfig)

export type Party = {
	id: string,
	leader: number,
	members: { number },
	ready: { [number]: boolean },
	mode: string,
	-- idle | searching | found (accepting) | launching | ingame | results
	status: string,
	-- Current match while found..results: { id, deadline, accepted, simulated, ... }
	match: any?,
}

export type State = {
	parties: { [string]: Party },
	memberOf: { [number]: string },
	-- invitee -> partyId -> expiresAt
	invites: { [number]: { [string]: number } },
	nextId: number,
}

local PartyCore = {}

function PartyCore.capacity(mode: string): number
	local info = PartyConfig.Modes[mode]
	local configured = info and info.maxMembers
	return if type(configured) == "number" then configured else PartyConfig.MaxMembers
end

function PartyCore.new(): State
	return { parties = {}, memberOf = {}, invites = {}, nextId = 0 }
end

function PartyCore.get(state: State, userId: number): Party?
	local partyId = state.memberOf[userId]
	return if partyId then state.parties[partyId] else nil
end

-- Any change to the roster or mode stops a search and clears ready flags
-- (except the leader's, who is ready by starting).
local function resetReady(party: Party)
	table.clear(party.ready)
	party.status = "idle"
	party.match = nil
end

function PartyCore.create(state: State, userId: number): (boolean, string?)
	if state.memberOf[userId] then
		return false, "ALREADY_IN_PARTY"
	end
	state.nextId += 1
	local id = "p" .. state.nextId
	state.parties[id] = { id = id, leader = userId, members = { userId }, ready = {}, mode = "quick", status = "idle" }
	state.memberOf[userId] = id
	return true, nil
end

function PartyCore.leave(state: State, userId: number): (boolean, string?)
	local party = PartyCore.get(state, userId)
	if not party then
		return false, "NOT_IN_PARTY"
	end
	local index = table.find(party.members, userId)
	if index then
		table.remove(party.members, index)
	end
	state.memberOf[userId] = nil
	if #party.members == 0 then
		state.parties[party.id] = nil
		for _, invites in state.invites do
			invites[party.id] = nil
		end
		return true, nil
	end
	if party.leader == userId then
		party.leader = party.members[1]
	end
	resetReady(party)
	return true, nil
end

-- Inviting without a party creates one with the inviter as leader.
function PartyCore.invite(state: State, fromId: number, targetId: number, now: number): (boolean, string?)
	if fromId == targetId then
		return false, "INVALID_TARGET"
	end
	if not state.memberOf[fromId] then
		PartyCore.create(state, fromId)
	end
	local party = PartyCore.get(state, fromId) :: Party
	if party.leader ~= fromId then
		return false, "NOT_LEADER"
	end
	-- Nobody joins a squad that is searching or inside a match.
	if party.status ~= "idle" then
		return false, "PARTY_BUSY"
	end
	if #party.members >= PartyCore.capacity(party.mode) then
		return false, "PARTY_FULL"
	end
	if table.find(party.members, targetId) then
		return false, "ALREADY_MEMBER"
	end
	state.invites[targetId] = state.invites[targetId] or {}
	state.invites[targetId][party.id] = now + PartyConfig.InviteSeconds
	return true, nil
end

-- Accepting leaves the current party first.
function PartyCore.accept(state: State, userId: number, partyId: any, now: number): (boolean, string?)
	local invites = state.invites[userId]
	local expiresAt = if type(partyId) == "string" and invites then invites[partyId] else nil
	if not expiresAt or expiresAt < now then
		return false, "INVITE_EXPIRED"
	end
	invites[partyId] = nil
	local party = state.parties[partyId]
	if not party then
		return false, "PARTY_GONE"
	end
	if #party.members >= PartyCore.capacity(party.mode) then
		return false, "PARTY_FULL"
	end
	if party.status ~= "idle" then
		return false, "PARTY_BUSY"
	end
	if state.memberOf[userId] then
		PartyCore.leave(state, userId)
	end
	table.insert(party.members, userId)
	state.memberOf[userId] = partyId
	resetReady(party)
	return true, nil
end

-- Joins an idle private room by code. The code itself is resolved by
-- PartyService; the pure core only validates and changes party membership.
function PartyCore.joinPrivate(state: State, userId: number, partyId: string): (boolean, string?)
	local party = state.parties[partyId]
	if not party or party.mode ~= "private" then
		return false, "PRIVATE_ROOM_NOT_FOUND"
	end
	if party.status ~= "idle" then
		return false, "PARTY_BUSY"
	end
	if table.find(party.members, userId) then
		return true, nil
	end
	if #party.members >= PartyCore.capacity(party.mode) then
		return false, "PARTY_FULL"
	end
	if state.memberOf[userId] then
		PartyCore.leave(state, userId)
	end
	table.insert(party.members, userId)
	state.memberOf[userId] = partyId
	resetReady(party)
	return true, nil
end

function PartyCore.decline(state: State, userId: number, partyId: any): (boolean, string?)
	local invites = state.invites[userId]
	if type(partyId) == "string" and invites then
		invites[partyId] = nil
	end
	return true, nil
end

function PartyCore.kick(state: State, leaderId: number, targetId: any): (boolean, string?)
	local party = PartyCore.get(state, leaderId)
	if not party or party.leader ~= leaderId then
		return false, "NOT_LEADER"
	end
	if type(targetId) ~= "number" or targetId == leaderId or not table.find(party.members, targetId) then
		return false, "INVALID_TARGET"
	end
	if party.status == "found" or party.status == "launching" or party.status == "ingame" or party.status == "results" then
		return false, "PARTY_BUSY"
	end
	return PartyCore.leave(state, targetId)
end

function PartyCore.setReady(state: State, userId: number, ready: any): (boolean, string?)
	local party = PartyCore.get(state, userId)
	if not party then
		return false, "NOT_IN_PARTY"
	end
	if type(ready) ~= "boolean" then
		return false, "INVALID_VALUE"
	end
	if party.status ~= "idle" then
		return false, "PARTY_BUSY"
	end
	party.ready[userId] = ready or nil
	return true, nil
end

function PartyCore.setMode(state: State, userId: number, mode: any): (boolean, string?)
	local party = PartyCore.get(state, userId)
	if not party or party.leader ~= userId then
		return false, "NOT_LEADER"
	end
	if type(mode) ~= "string" or not PartyConfig.Modes[mode] then
		return false, "INVALID_MODE"
	end
	if PartyConfig.Modes[mode].locked then
		return false, "MODE_LOCKED"
	end
	if #party.members > PartyCore.capacity(mode) then
		return false, "PARTY_TOO_LARGE"
	end
	-- A search can be changed (it restarts); a found or running match cannot.
	if party.status == "found" or party.status == "launching" or party.status == "ingame" or party.status == "results" then
		return false, "PARTY_BUSY"
	end
	party.mode = mode
	resetReady(party)
	return true, nil
end

-- The leader may start when every other member is ready.
function PartyCore.canStart(state: State, userId: number): (boolean, string?)
	local party = PartyCore.get(state, userId)
	if not party or party.leader ~= userId then
		return false, "NOT_LEADER"
	end
	if party.status ~= "idle" then
		return false, "PARTY_BUSY"
	end
	for _, memberId in party.members do
		if memberId ~= party.leader and not party.ready[memberId] then
			return false, "NOT_ALL_READY"
		end
	end
	return true, nil
end

-- ------------------------------------------------------------- match flow --
-- searching -> found (every member accepts before the deadline) -> launching
-- -> ingame -> results -> idle. Any roster change drops back to idle.

function PartyCore.beginMatch(state: State, partyId: string, matchId: number, deadline: number, simulated: boolean): (boolean, string?)
	local party = state.parties[partyId]
	if not party or party.status ~= "searching" then
		return false, "NOT_SEARCHING"
	end
	party.status = "found"
	party.match = { id = matchId, deadline = deadline, accepted = {}, simulated = simulated }
	return true, nil
end

function PartyCore.acceptMatch(state: State, userId: number, now: number): (boolean, string?)
	local party = PartyCore.get(state, userId)
	if not party or party.status ~= "found" or not party.match then
		return false, "NO_MATCH"
	end
	if now > party.match.deadline then
		return false, "MATCH_EXPIRED"
	end
	party.match.accepted[userId] = true
	return true, nil
end

function PartyCore.allAccepted(party: Party): boolean
	if party.status ~= "found" or not party.match then
		return false
	end
	for _, userId in party.members do
		if not party.match.accepted[userId] then
			return false
		end
	end
	return true
end

-- A member declines: the whole squad goes back to the lobby.
function PartyCore.declineMatch(state: State, userId: number): (boolean, string?)
	local party = PartyCore.get(state, userId)
	if not party or party.status ~= "found" then
		return false, "NO_MATCH"
	end
	resetReady(party)
	return true, nil
end

-- Acceptance time ran out (matchId guards against an older timer).
function PartyCore.expireMatch(state: State, partyId: string, matchId: number, now: number): boolean
	local party = state.parties[partyId]
	if party and party.status == "found" and party.match and party.match.id == matchId and now >= party.match.deadline then
		resetReady(party)
		return true
	end
	return false
end

-- Everyone accepted: loading starts.
function PartyCore.launchMatch(state: State, partyId: string): boolean
	local party = state.parties[partyId]
	if party and PartyCore.allAccepted(party) then
		party.status = "launching"
		return true
	end
	return false
end

-- A member leaves the results (or the room): the squad returns to the lobby.
function PartyCore.returnToLobby(state: State, userId: number): (boolean, string?)
	local party = PartyCore.get(state, userId)
	if not party or (party.status ~= "ingame" and party.status ~= "results" and party.status ~= "launching") then
		return false, "NOT_IN_MATCH"
	end
	resetReady(party)
	return true, nil
end

-- Invites still pending for a user: { partyId -> expiresAt }.
function PartyCore.pendingInvites(state: State, userId: number, now: number): { [string]: number }
	local result = {}
	for partyId, expiresAt in state.invites[userId] or {} do
		if expiresAt >= now and state.parties[partyId] then
			result[partyId] = expiresAt
		end
	end
	return result
end

return PartyCore
