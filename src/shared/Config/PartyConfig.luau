--!strict

-- Parties (squads) and matchmaking. Parties live on one server; matches are
-- formed across servers through MemoryStoreService and TeleportService.

local PartyConfig = {
	-- 5 vs 5: a full squad is one team.
	MaxMembers = 5,
	InviteSeconds = 60,
	PrivateRooms = table.freeze({
		CodeLength = 6,
		CodeSeconds = 7200,
		CodeMapName = "Reality2059_PrivateRooms",
	}),
	-- Match found: every member must accept within this time.
	AcceptSeconds = 15,
	TeamSize = 5,
	-- A real teleport that has not left after this long is abandoned.
	TeleportTimeoutSeconds = 45,
	-- Studio only: while no match place is configured, a search finds a
	-- SIMULATED match so the whole flow (accept, loading, room, results,
	-- return) can be walked through. It never runs on a published server.
	StudioSimulation = true,
	Simulation = table.freeze({
		SearchSeconds = NumberRange.new(4, 7),
		LoadSeconds = 4,
		RoomSeconds = 12,
	}),
	-- Maps per queue (placeholder until the first real map exists).
	Maps = table.freeze({
		quick = table.freeze({ table.freeze({ id = "nexus_grid", name = "DISTRITO NEXUS", tagline = "MAPA EN CONSTRUCCIÓN" }) }),
		ranked = table.freeze({ table.freeze({ id = "nexus_grid", name = "DISTRITO NEXUS", tagline = "MAPA EN CONSTRUCCIÓN" }) }),
		private = table.freeze({ table.freeze({ id = "nexus_grid", name = "DISTRITO NEXUS", tagline = "SALA PRIVADA" }) }),
	}),
	MaxRequestsPerWindow = 30,
	RequestWindowSeconds = 10,

	-- Modes a party can start. "free" keeps everyone on this server in
	-- MODO LIBRE; the others go through matchmaking.
	Modes = table.freeze({
		-- Locked: competitive comes first (LobbyConfig shows it as BLOQUEADO).
		free = table.freeze({ name = "MODO LIBRE", matchmaking = false, locked = true, maxMembers = 5 }),
		-- Quick match: team deathmatch only.
		quick = table.freeze({ name = "PARTIDA RÁPIDA", matchmaking = true, gameMode = "team_deathmatch", maxMembers = 5 }),
		-- Locked until ranked play opens.
		ranked = table.freeze({ name = "COMPETITIVO", matchmaking = true, locked = true, maxMembers = 5 }),
		-- A private room is one complete 10-player match. It never gets combined
		-- with another party in matchmaking.
		private = table.freeze({ name = "PARTIDA PRIVADA", matchmaking = true, privateServer = true, gameMode = "team_deathmatch", maxMembers = 10 }),
		training = table.freeze({ name = "MODO ENTRENAMIENTO", matchmaking = false, locked = true, maxMembers = 5 }),
	}),

	Matchmaking = table.freeze({
		-- Place that hosts the matches (a second place of this experience).
		-- 0 = not configured yet: queueing answers MATCH_PLACE_NOT_CONFIGURED
		-- instead of pretending to search.
		PlaceIds = table.freeze({
			quick = 0,
			ranked = 0,
			private = 0,
		}),
		-- Players needed to start a match (parties are never split).
		-- 5 vs 5 (quick can start short-handed; ranked needs both teams full).
		MinPlayers = table.freeze({ quick = 2, ranked = 10, private = 1 }),
		MaxPlayers = table.freeze({ quick = 10, ranked = 10, private = 10 }),
		-- MemoryStore entries expire if a server dies mid-queue.
		TicketSeconds = 120,
		PollSeconds = 3,
		QueueMapName = "Reality2059_Queue_",
		LockMapName = "Reality2059_QueueLock",
	}),
}

return table.freeze(PartyConfig)
