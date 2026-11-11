--!strict

local PartyCore = require(script.Parent.Parent.Party.PartyCore)
local MatchmakingService = require(script.Parent.Parent.Party.MatchmakingService)

local PartyTests = {}

local function expect(condition: boolean, message: string)
	if not condition then error("Party test failed: " .. message, 2) end
end

function PartyTests.run(): { passed: number, total: number }
	local passed = 0
	local now = 1000

	-- Invite / accept up to five (a 5 vs 5 team), the sixth is refused.
	local state = PartyCore.new()
	expect(PartyCore.invite(state, 1, 2, now), "leader could not invite")
	local party = PartyCore.get(state, 1) :: any
	expect(party and party.leader == 1, "inviting did not create a party led by the inviter")
	expect(PartyCore.accept(state, 2, party.id, now), "invitee could not accept")
	PartyCore.invite(state, 1, 3, now)
	PartyCore.invite(state, 1, 4, now)
	PartyCore.invite(state, 1, 5, now)
	PartyCore.invite(state, 1, 8, now)
	expect(PartyCore.accept(state, 3, party.id, now), "third member refused")
	expect(PartyCore.accept(state, 4, party.id, now), "fourth member refused")
	expect(PartyCore.accept(state, 5, party.id, now), "fifth member refused")
	expect(#party.members == 5, "party should have five members")
	expect(not PartyCore.accept(state, 8, party.id, now), "sixth member accepted")
	expect(not PartyCore.invite(state, 1, 6, now), "invited into a full party")
	passed += 1

	-- A private room grows to ten, rejects an eleventh member and cannot be
	-- changed back to a five-player mode while oversized.
	local privateState = PartyCore.new()
	expect(PartyCore.create(privateState, 20), "private leader party was not created")
	expect(PartyCore.setMode(privateState, 20, "private"), "private mode was not accepted")
	local privateParty = PartyCore.get(privateState, 20) :: any
	for userId = 21, 29 do
		expect(PartyCore.invite(privateState, 20, userId, now), "private invite was refused")
		expect(PartyCore.accept(privateState, userId, privateParty.id, now), "private invitee could not accept")
	end
	expect(#privateParty.members == 10, "private room should have ten members")
	expect(not PartyCore.invite(privateState, 20, 30, now), "private room invited an eleventh member")
	expect(not PartyCore.setMode(privateState, 20, "quick"), "oversized private room changed to quick")
	expect(PartyCore.leave(privateState, 29), "private member could not leave")
	expect(PartyCore.joinPrivate(privateState, 30, privateParty.id), "player could not join private room by code")
	expect(not PartyCore.joinPrivate(privateState, 31, "missing"), "missing private room accepted a code join")
	passed += 1

	-- Only the leader invites, kicks and changes mode; expired invites fail.
	expect(not PartyCore.invite(state, 2, 7, now), "non-leader invited")
	expect(not PartyCore.kick(state, 2, 3), "non-leader kicked")
	expect(not PartyCore.setMode(state, 2, "ranked"), "non-leader changed mode")
	expect(not PartyCore.setMode(state, 1, "hack"), "unknown mode accepted")
	local other = PartyCore.new()
	PartyCore.invite(other, 10, 11, now)
	local otherParty = PartyCore.get(other, 10) :: any
	expect(not PartyCore.accept(other, 11, otherParty.id, now + 61), "expired invite accepted")
	expect(not PartyCore.accept(other, 12, otherParty.id, now), "accepted without an invite")
	passed += 1

	-- Ready check and start.
	expect(not PartyCore.canStart(state, 1), "started with members not ready")
	for _, userId in { 2, 3, 4, 5 } do
		PartyCore.setReady(state, userId, true)
	end
	expect(PartyCore.canStart(state, 1), "could not start with everyone ready")
	expect(not PartyCore.canStart(state, 2), "non-leader started")
	-- Locked modes are refused; PARTIDA RÁPIDA remains the default.
	expect(not PartyCore.setMode(state, 1, "free"), "the locked MODO LIBRE was accepted")
	expect(not PartyCore.setMode(state, 1, "ranked"), "the locked COMPETITIVO was accepted")
	expect(party.mode == "quick", "new squads must play PARTIDA RÁPIDA")
	passed += 1

	-- Leaving: leader hands over; the last member closes the party.
	PartyCore.leave(state, 1)
	expect(party.leader == 2, "leadership not handed over")
	expect(PartyCore.kick(state, 2, 3), "leader could not kick")
	PartyCore.leave(state, 4)
	PartyCore.leave(state, 5)
	PartyCore.leave(state, 2)
	expect(state.parties[party.id] == nil, "empty party not removed")
	expect(PartyCore.get(state, 2) == nil, "membership kept after leaving")
	passed += 1

	-- Matchmaking groups whole parties, oldest first.
	local entries = {
		{ key = "a", size = 3 },
		{ key = "b", size = 4 },
		{ key = "c", size = 2 },
		{ key = "d", size = 3 },
	}
	-- 3 + 4 = 7; c and d would overflow 8, so no full match yet.
	expect(MatchmakingService.Group(entries, 8, 8) == nil, "formed a match short of players")
	table.insert(entries, { key = "e", size = 1 })
	local chosen = MatchmakingService.Group(entries, 8, 8)
	expect(chosen ~= nil and table.concat(chosen, ",") == "a,b,e", "expected parties a, b and e")
	local quick = MatchmakingService.Group(entries, 2, 8) :: { string }
	expect(quick and #quick >= 1, "quick match not formed")
	expect(MatchmakingService.Group({ { key = "x", size = 1 } }, 2, 8) == nil, "match formed below minimum")
	passed += 1

	-- Match flow: found -> everyone accepts -> launching -> ingame -> results
	-- -> back to idle; a decline, a timeout or a departure drop it.
	local flow = PartyCore.new()
	PartyCore.invite(flow, 1, 2, now)
	local fparty = PartyCore.get(flow, 1) :: any
	PartyCore.accept(flow, 2, fparty.id, now)
	PartyCore.setReady(flow, 2, true)
	expect(not PartyCore.beginMatch(flow, fparty.id, 1, now + 15, false), "a match began without a search")
	fparty.status = "searching"
	expect(PartyCore.beginMatch(flow, fparty.id, 1, now + 15, false), "could not begin the match")
	expect(fparty.status == "found", "match not in the found state")
	expect(not PartyCore.invite(flow, 1, 3, now), "invited into a squad with a match found")
	expect(not PartyCore.setMode(flow, 1, "quick"), "mode changed during a found match")
	expect(not PartyCore.kick(flow, 1, 2), "kicked during a found match")
	expect(not PartyCore.acceptMatch(flow, 2, now + 60), "accepted after the deadline")
	expect(PartyCore.acceptMatch(flow, 1, now), "leader could not accept")
	expect(not PartyCore.launchMatch(flow, fparty.id), "launched with one acceptance missing")
	expect(PartyCore.acceptMatch(flow, 2, now), "member could not accept")
	expect(PartyCore.launchMatch(flow, fparty.id) and fparty.status == "launching", "did not launch when all accepted")
	expect(not PartyCore.declineMatch(flow, 1), "declined after launching")
	fparty.status = "ingame"
	expect(PartyCore.returnToLobby(flow, 2) and fparty.status == "idle" and fparty.match == nil, "return to lobby did not reset")
	fparty.status = "searching"
	PartyCore.beginMatch(flow, fparty.id, 2, now + 15, false)
	expect(not PartyCore.expireMatch(flow, fparty.id, 2, now + 5), "expired before the deadline")
	expect(not PartyCore.expireMatch(flow, fparty.id, 1, now + 20), "an old timer expired a newer match")
	expect(PartyCore.expireMatch(flow, fparty.id, 2, now + 16) and fparty.status == "idle", "match did not expire")
	fparty.status = "searching"
	PartyCore.beginMatch(flow, fparty.id, 3, now + 15, false)
	expect(PartyCore.declineMatch(flow, 2) and fparty.status == "idle", "decline did not return the squad to idle")
	fparty.status = "searching"
	PartyCore.beginMatch(flow, fparty.id, 4, now + 15, false)
	PartyCore.leave(flow, 2)
	expect(fparty.status == "idle" and fparty.match == nil, "leaving did not drop the found match")
	passed += 1

	return { passed = passed, total = 7 }
end

return PartyTests
