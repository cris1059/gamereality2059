--!strict

-- Ambient city life in MODO LIBRE, simulated on each client around its own
-- player (no network cost, nothing for exploiters to touch). Cars and
-- pedestrians follow World/City2059Streets, generated from the real road and
-- sidewalk geometry by scripts/build_city2059_streets.py, so they never leave
-- the asphalt or the sidewalks. Counts are scaled by the graphics profile.

return table.freeze({
	-- Agents live within ActiveRadius of the player; new ones appear between
	-- SpawnMin and SpawnMax, preferably out of the camera's view.
	ActiveRadius = 380,
	SpawnMin = 70,
	SpawnMax = 340,
	-- Far agents update less often (seconds between updates).
	FarDistance = 170,
	FarUpdateInterval = 0.12,

	Cars = table.freeze({
		Count = 18,
		Speed = NumberRange.new(30, 42),
		TurnSpeed = 17,
		UTurnSpeed = 9,
		Acceleration = 12,
		Braking = 28,
		Length = 13,
		-- Bumper gap kept to the car ahead / a pedestrian crossing.
		Gap = 6,
		LookAhead = 45,
		-- Stop this far before the end of the lane at a red light.
		StopMargin = 2,
		-- Choice at junctions (U-turns only where nothing else is possible).
		TurnWeights = table.freeze({ straight = 0.55, right = 0.25, left = 0.2 }),
		-- Entering the roundabout waits while a car in the ring is this close.
		YieldDistance = 30,
	}),

	FlyingCars = table.freeze({
		Count = 18,
		Speed = NumberRange.new(55, 80),
		-- Cruise heights above the street; each car keeps one, climbing over
		-- anything taller under its route (plus Clearance) ahead of time.
		Altitudes = table.freeze({ 70, 105, 140, 180 }),
		Clearance = 20,
		LookAhead = 90,
		ClimbRate = 1.6,
		Gap = 25,
		MaxBank = math.rad(28),
	}),

	-- Traffic lights (seconds); every junction has its own offset.
	Lights = table.freeze({
		Green = 11,
		Yellow = 2.5,
		AllRed = 1.5,
		PostHeight = 10,
		-- From the end of the outer lane to the post, toward the curb.
		CurbOffset = 6,
	}),

	Pedestrians = table.freeze({
		Count = 26,
		WalkSpeed = NumberRange.new(4.2, 6.2),
		-- Each person walks a little to one side of the sidewalk line.
		Lateral = 1.4,
		-- Chance per second of stopping for a moment.
		PauseChance = 0.03,
		PauseSeconds = NumberRange.new(2, 6),
		-- Chance of taking a crosswalk when passing one.
		CrossChance = 0.45,
		CrossSpeedFactor = 1.25,
		-- Crossing without a light: no car closer than this to the crosswalk.
		CarClearance = 28,
		-- Animation level of detail (studs from the player): every frame within
		-- AnimateNear, every FarAnimationInterval seconds up to HideBeyond.
		AnimateNear = 70,
		FarAnimationInterval = 0.1,
		HideBeyond = 260,
		-- New characters built per second (each one is a full rig).
		BuildPerSecond = 5,
		-- Keep people apart on the same sidewalk.
		Personal = 2.2,
	}),

	Palette = table.freeze({
		CarBody = table.freeze({
			Color3.fromRGB(20, 22, 28), Color3.fromRGB(120, 124, 132), Color3.fromRGB(150, 24, 36),
			Color3.fromRGB(230, 230, 236), Color3.fromRGB(24, 50, 90), Color3.fromRGB(60, 60, 64),
		}),
		Neon = table.freeze({
			Color3.fromRGB(255, 32, 48), Color3.fromRGB(0, 229, 255), Color3.fromRGB(255, 200, 40),
			Color3.fromRGB(190, 70, 255), Color3.fromRGB(90, 255, 180),
		}),
	}),
})
