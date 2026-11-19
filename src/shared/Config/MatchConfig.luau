--!strict

-- Matches played on this server (MatchService): today the private rooms, so
-- several people can test the shooter together (Studio Team Test or a
-- published server) without teleports or a second place.

local MatchConfig = {
	-- Private rooms play their match on the room's own server.
	LocalPrivateMatches = true,
	-- Team deathmatch: first team to ScoreLimit eliminations, or the leader
	-- when the time runs out (a tie is a draw).
	ScoreLimit = 30,
	TimeLimitSeconds = 8 * 60,
	CountdownSeconds = 5,
	ResultsSeconds = 15,
	-- Maps in rotation (models in ServerStorage.Maps or Workspace.MapWorkshop).
	Maps = table.freeze({ "DistritoNexus" }),
	-- Where match copies of a map are placed (one slot per running match),
	-- beyond the city's ground like the map workshop.
	SlotOrigin = Vector3.new(1600, 40, 2500),
	SlotSpacing = 1200,
	Teams = table.freeze({
		A = table.freeze({ name = "EQUIPO CIAN", color = Color3.fromRGB(0, 200, 255), brick = BrickColor.new("Cyan") }),
		B = table.freeze({ name = "EQUIPO MAGENTA", color = Color3.fromRGB(255, 60, 170), brick = BrickColor.new("Hot pink") }),
	}),
	-- Weapons every player starts with (Tool names in ServerStorage.Weapons);
	-- empty = a rifle and a pistol picked automatically. These two are built
	-- from code by Weapons/WeaponModels.
	StartingWeapons = table.freeze({ "R2059 Rifle VK-7", "R2059 Pistola Pm-8" }),
	-- MODO ENTRENAMIENTO (TrainingService): one shared practice copy of this
	-- map per server, with every weapon on pedestals and practice dummies.
	-- Slot -1 sits between the map workshop and the match slots (0, 1, ...).
	Training = table.freeze({
		Map = "DistritoNexus",
		Slot = -1,
		Team = "A",
		-- Practice zones beside the spawns (offset from the map's floor centre,
		-- studs): standing in one takes perSecond health (negative heals).
		Zones = table.freeze({
			table.freeze({
				name = "ZonaDano", label = "ZONA DE DAÑO", detail = "-20 VIDA / SEG  ·  PRUEBA CRÍTICO",
				offset = Vector3.new(-84, 0, 150), size = 14, perSecond = 20, color = Color3.fromRGB(255, 54, 94),
			}),
			table.freeze({
				name = "EstacionMedica", label = "ESTACIÓN MÉDICA", detail = "+25 VIDA / SEG",
				offset = Vector3.new(84, 0, 150), size = 14, perSecond = -25, color = Color3.fromRGB(60, 255, 150),
			}),
		}),
	}),
}

return table.freeze(MatchConfig)
