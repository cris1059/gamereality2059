--!strict

-- MODO LIBRE: the playable City2059 (server world setup, player movement and
-- the client-side day/night cycle).

local FreeRoamConfig = {
	SceneVersion = 1,
	ModelName = "FreeRoam",
	CityModelName = "City2059",
	-- Studs per glTF unit. The saved city is at effective scale 60:
	-- approximately 1227 x 415 x 1179 studs for a 5.7-stud character.
	-- RescaleCity = false keeps the exact size the city has in Studio.
	CityScale = 60,
	RescaleCity = false,
	-- Where the centre of the city floor is placed (clear of MORPHLAB at z=220).
	-- RepositionCity = false keeps the position the city has in Studio.
	RepositionCity = true,
	-- Floor 1 stud above y = 0, so it never coincides with the template
	-- Baseplate or Studio's build grid plane.
	CityCenter = Vector3.new(0, 1, -1200),
	-- Collision. The city meshes never collide (each spans the whole city).
	-- Hand-made collision: Parts inside a Folder or Model with this name
	-- inside City2059; they scale and move with the city and turn invisible
	-- and solid in play.
	CollisionFolderName = "Colisiones",
	-- Boxes generated from the GLB (World/City2059Data). Off until reviewed.
	GeneratedColliders = false,
	-- Ground around and under the city (top flush with the city slab).
	Ground = table.freeze({
		Size = 4400,
		Thickness = 8,
		Color = Color3.fromRGB(34, 36, 44),
		Material = Enum.Material.Asphalt,
		-- Invisible walls at the ground's edge.
		WallHeight = 400,
	}),
	-- Only two camera modes: fixed-distance third person and optional first
	-- person (V / D-pad up). Min = Max zoom, so the mouse wheel does nothing;
	-- the default camera's occlusion keeps it from going through walls.
	Camera = table.freeze({
		ThirdPersonDistance = 7,
		FirstPersonDistance = 0.5,
		ToggleKeys = table.freeze({ Enum.KeyCode.V, Enum.KeyCode.DPadUp }),
		-- Over-the-shoulder: X studs to the side, Y up (side starts on the left
		-- so the character sits on the right of the screen; Q swaps).
		ShoulderOffset = Vector2.new(2.2, 0.6),
		ShoulderKeys = table.freeze({ Enum.KeyCode.Q, Enum.KeyCode.DPadRight }),
		-- Higher = faster shoulder swap.
		ShoulderSwapSpeed = 10,
		-- Roblox defaults, restored when leaving MODO LIBRE.
		DefaultMinZoom = 0.5,
		DefaultMaxZoom = 400,
	}),
	-- Server puts a player back on their last grounded spot when they drop
	-- this far below the ground (checked every CheckInterval seconds).
	FallRecovery = table.freeze({ BelowFloor = 25, CheckInterval = 0.5 }),
	Movement = table.freeze({
		WalkSpeed = 16,
		RunSpeed = 28,
		JumpPower = 50,
		-- The character is the player's R15 avatar (its own HipHeight); the
		-- city's 2-3 stud curbs may need a jump.
	}),
	-- Day / night (shared/World/DayCycle). Real seconds for the daylight part
	-- (NightEnd -> NightStart) and for the night; the clock is the same for
	-- every player. FixedClockTime = an hour (e.g. 22) freezes the time, for
	-- testing; false runs the cycle.
	DayCycle = table.freeze({
		DaySeconds = 600,
		NightSeconds = 300,
		StartClockTime = 8.5,
		NightStart = 18.6,
		NightEnd = 6.2,
		FixedClockTime = false,
	}),
	-- Lighting keyframes by clock time (hours), interpolated by the client.
	LightingKeys = table.freeze({
		{ time = 0, ambient = Color3.fromRGB(34, 26, 58), outdoor = Color3.fromRGB(46, 38, 82), brightness = 0.6, fog = Color3.fromRGB(22, 14, 40), haze = 2.4, density = 0.38, tint = Color3.fromRGB(205, 200, 255), exposure = 0.15 },
		{ time = 5.2, ambient = Color3.fromRGB(46, 36, 70), outdoor = Color3.fromRGB(70, 54, 100), brightness = 0.9, fog = Color3.fromRGB(46, 30, 66), haze = 2.2, density = 0.36, tint = Color3.fromRGB(220, 205, 255), exposure = 0.1 },
		{ time = 6.6, ambient = Color3.fromRGB(110, 80, 92), outdoor = Color3.fromRGB(170, 120, 120), brightness = 2.0, fog = Color3.fromRGB(230, 140, 120), haze = 1.8, density = 0.32, tint = Color3.fromRGB(255, 225, 210), exposure = 0 },
		{ time = 9, ambient = Color3.fromRGB(120, 124, 140), outdoor = Color3.fromRGB(150, 156, 172), brightness = 2.8, fog = Color3.fromRGB(170, 185, 210), haze = 1.2, density = 0.28, tint = Color3.fromRGB(255, 250, 245), exposure = 0 },
		{ time = 13, ambient = Color3.fromRGB(130, 134, 148), outdoor = Color3.fromRGB(160, 166, 180), brightness = 3.1, fog = Color3.fromRGB(180, 195, 220), haze = 1.0, density = 0.26, tint = Color3.fromRGB(255, 255, 255), exposure = 0 },
		{ time = 17, ambient = Color3.fromRGB(120, 100, 104), outdoor = Color3.fromRGB(170, 130, 126), brightness = 2.4, fog = Color3.fromRGB(220, 150, 130), haze = 1.6, density = 0.3, tint = Color3.fromRGB(255, 230, 215), exposure = 0 },
		{ time = 18.7, ambient = Color3.fromRGB(80, 50, 90), outdoor = Color3.fromRGB(120, 70, 120), brightness = 1.3, fog = Color3.fromRGB(150, 60, 110), haze = 2.0, density = 0.34, tint = Color3.fromRGB(240, 205, 250), exposure = 0.05 },
		{ time = 20.5, ambient = Color3.fromRGB(40, 30, 66), outdoor = Color3.fromRGB(54, 42, 92), brightness = 0.7, fog = Color3.fromRGB(26, 16, 46), haze = 2.4, density = 0.38, tint = Color3.fromRGB(205, 200, 255), exposure = 0.15 },
		{ time = 24, ambient = Color3.fromRGB(34, 26, 58), outdoor = Color3.fromRGB(46, 38, 82), brightness = 0.6, fog = Color3.fromRGB(22, 14, 40), haze = 2.4, density = 0.38, tint = Color3.fromRGB(205, 200, 255), exposure = 0.15 },
	}),
	-- City windows: lit glass by day, glowing at night.
	WindowDayColor = Color3.fromRGB(150, 170, 190),
	Bloom = table.freeze({ Intensity = 0.9, Size = 28, Threshold = 1.6 }),
}

return table.freeze(FreeRoamConfig)
