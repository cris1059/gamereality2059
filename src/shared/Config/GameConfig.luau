--!strict

return table.freeze({
	GameName = "REALITY 2059",
	LobbyName = "Nexus City",
	-- 3: characters are standard R15 avatars (PlayerMigrations).
	DataSchemaVersion = 3,
	RojoProjectVersion = 2,
	Persistence = table.freeze({
		-- Auto | DataStoreService | Mock (see server init).
		Backend = "Auto",
		DataStoreName = "CyberpunkOnline_PlayerData_v1",
		LeaseSeconds = 120,
		RenewIntervalSeconds = 40,
		MaxAttempts = 3,
		RetryBaseSeconds = 0.5,
	}),
	Networking = table.freeze({
		RequestWindowSeconds = 10,
		MaxDraftRequestsPerWindow = 12,
	}),
})
