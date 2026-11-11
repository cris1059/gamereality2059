--!strict

-- Studio-only conveniences. Nothing here applies in a published game
-- (the client checks RunService:IsStudio()).

local DevConfig = {
	-- Where Play starts in Studio, skipping the INICIAR menu:
	--   false       normal flow (menu -> MORPHLAB / lobby)
	--   "MorphLab"  straight into the character creator
	--   "Lobby"     straight into the lobby with Character
	--   "FreeRoam"  straight into the city with Character
	--   "MapTest"   walk the map MapTest (Workspace.MapWorkshop) with Character,
	--               starting on its team A spawns
	-- QuickStart = "MapTest",
	QuickStart = false,
	-- Map for "MapTest": a model in Workspace.MapWorkshop (see src/server/Maps).
	MapTest = "DistritoNexus",

	-- Studio only: fills the empty lobby rings with random characters (named
	-- like a full squad, all LISTO) to judge the line-up's lighting and poses
	-- without friends online. They are scenery: not in the squad list.
	PreviewSquad = true,

	-- Test character for "Lobby" / "FreeRoam" (MockDataStore keeps nothing
	-- between Play sessions). Any field may be removed to keep the default;
	-- ids come from CharacterCatalog and are validated like in MORPHLAB.
	Character = table.freeze({
		bodyBaseId = "classic", -- classic | slim
		skinToneId = "neutral_light",
		faceId = "chill",
		hairId = "spiky_white",
		outfitId = "neon_nomad",
		accessories = { "visor_purple", "horns_mech" },
		classId = "runner",
		implants = { "cyber_arm" },
		colors = table.freeze({ neonPrimary = "violet", neonSecondary = "cyan", metal = "black" }),
	}),
}

return table.freeze(DevConfig)
