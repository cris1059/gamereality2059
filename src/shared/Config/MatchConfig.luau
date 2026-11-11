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
	-- empty = a rifle and a pistol picked automatically.
	StartingWeapons = table.freeze({}),
}

return table.freeze(MatchConfig)
