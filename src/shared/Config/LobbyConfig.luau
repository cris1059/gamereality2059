--!strict

-- The lobby is the main menu (the "hub"): the player's character on a
-- rooftop in front of City2059, the squad on the rings beside them, and the
-- menu over it (JUGAR / PERSONAJE / ESCUADRÓN / AJUSTES / CRÉDITOS).
local LobbyConfig = {
	SceneVersion = 7,
	ModelName = "Lobby",
	-- Lobby-only city dressing (lit windows, signs, portal), kept in
	-- ReplicatedStorage and cloned by the client while the hub is open, so
	-- MODO LIBRE never sees it.
	SkylineName = "LobbySkyline",
	CityModelName = "City2059",
	-- Used when City2059 is missing from Workspace.
	FallbackOrigin = Vector3.new(0, 50, 60),
	-- Lobby origin relative to the city: in front of its front (+Z) face, at
	-- this fraction of its height. Low, so the towers rise behind the line-up;
	-- MORPHLAB stands at the same height beside it (same backdrop).
	CityHeightFraction = 0.35,
	CityFrontGap = 90,
	-- The player's ring (slot 0, at the origin) and the squad rings left to
	-- right: a tight, gently curved line-up so all five fit in the shot.
	PlayerColor = Color3.fromRGB(255, 40, 190),
	PlayerRingDiameter = 3.4,
	RingDiameter = 3,
	SquadSlots = table.freeze({
		table.freeze({ offset = Vector3.new(-6.4, 0, -1.9), color = Color3.fromRGB(0, 229, 255) }),
		table.freeze({ offset = Vector3.new(-3.2, 0, -0.6), color = Color3.fromRGB(255, 32, 48) }),
		table.freeze({ offset = Vector3.new(3.2, 0, -0.6), color = Color3.fromRGB(255, 200, 40) }),
		table.freeze({ offset = Vector3.new(6.4, 0, -1.9), color = Color3.fromRGB(0, 229, 255) }),
	}),
	-- JUGAR framing (MorphLabConfig FieldOfView 42): the five stand right of
	-- centre, clear of the menu column, feet at ~80 % of the screen height.
	Camera = table.freeze({
		PositionOffset = Vector3.new(-2.3, 5.3, 18.5),
		LookOffset = Vector3.new(-2.3, 4.4, -0.6),
	}),
	-- Camera framing per menu tab, relative to the platform centre (studs).
	-- PERSONAJE moves in on the player; ESCUADRÓN pulls back a little.
	CameraPresets = table.freeze({
		play = table.freeze({ position = Vector3.new(-2.3, 5.3, 18.5), look = Vector3.new(-2.3, 4.4, -0.6) }),
		character = table.freeze({ position = Vector3.new(-1.1, 4.4, 9.5), look = Vector3.new(-1.1, 3.3, 0) }),
		squad = table.freeze({ position = Vector3.new(-2.3, 6.4, 22), look = Vector3.new(-2.3, 4.1, -0.6) }),
		settings = table.freeze({ position = Vector3.new(-2.8, 5.6, 19.5), look = Vector3.new(-2.8, 4.6, -0.6) }),
		credits = table.freeze({ position = Vector3.new(-2.8, 5.6, 19.5), look = Vector3.new(-2.8, 4.6, -0.6) }),
	}),
	-- Stage lighting (LobbySceneBuilder): two shared key lights from the
	-- camera side (offsets from the platform centre), a coloured rim light
	-- behind each character (the ring's colour) and a light pool per ring.
	Lighting = table.freeze({
		Keys = table.freeze({ Vector3.new(-8, 9, 12), Vector3.new(7, 8, 13) }),
		-- Moderate: light plastic R15 avatars wash out under stronger lights.
		KeyColor = Color3.fromRGB(210, 226, 255),
		KeyBrightness = 1.3,
		KeyRange = 34,
		KeyAngle = 75,
		RimOffset = Vector3.new(0, 7.5, -5.5),
		RimBrightness = 2.4,
		RimRange = 14,
		RimAngle = 60,
		RingBrightness = 1.2,
		RingRange = 6,
		FloorReflectance = 0.25,
	}),
	-- Wet-floor reflections painted on the rooftop (self-lit streaks): one
	-- under each ring towards the camera, plus far streaks of city neon.
	Reflections = table.freeze({
		Length = 8,
		Width = 2.2,
		Opacity = 0.42,
		CityStreaks = 12,
	}),
	-- NEO-EDEN board, right of the line-up (offset from the platform centre).
	Sign = table.freeze({ Offset = Vector3.new(12.5, 8.6, -16), Size = 9 }),
	-- Sky rift placed relative to the JUGAR view, so it is always framed:
	-- turned right / up from the view centre (degrees), radius as an angle.
	Portal = table.freeze({ Distance = 360, YawDegrees = -4.7, PitchDegrees = 13.8, RadiusDegrees = 5.7 }),
	-- Lit city: the uploaded Reality2059Windows_* tiles, self-lit, on the
	-- city walls that face the lobby camera, plus neon bands and vertical
	-- signs on them (deterministic, seeded).
	Skyline = table.freeze({
		WindowSets = table.freeze({ "Grid", "Bands", "Slits" }),
		WindowTileStuds = 22,
		WindowPixelsPerStud = 2,
		WindowBrightness = 1.15,
		SignBrightness = 1,
		MinFacing = 0.2,
		MaxDistance = 1800,
		MaxWalls = 48,
		SignChance = 0.55,
		BandChance = 0.65,
		-- The pink is kept soft: at full strength it glared over the skyline.
		Colors = table.freeze({
			Color3.fromRGB(176, 40, 132),
			Color3.fromRGB(0, 229, 255),
			Color3.fromRGB(150, 70, 255),
			Color3.fromRGB(255, 170, 40),
		}),
		SignWords = table.freeze({ "ネオン", "電脳街", "夢", "未来", "サイバー", "ホテル", "酒場", "東京", "NEO", "BAR" }),
	}),
	-- Rain. Texture: the engine's sparkle (stretched) until a custom streak
	-- image is uploaded; set Enabled = false to turn it off.
	Rain = table.freeze({
		Enabled = true,
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = Color3.fromRGB(170, 215, 255),
		Rate = 240,
		SplashRate = 60,
		Speed = 95,
		Width = 0.14,
		-- ParticleEmitter.Squash accepts -3..3.
		Stretch = -2.8,
	}),
	-- Held postures for the line-up (Character/R15Pose:SetStance). Values are
	-- degrees added to the idle at the R15 joints; { l, r } are the left and
	-- right arm (armRaise > 0 = outward, < 0 = folded across; elbow > 0 bends
	-- the forearm forward; curl is unused on blocky hands).
	-- StanceBySlot: 0 = you, 1..4 = the squad rings left to right.
	-- These were set by eye from the reference art: tune them in Studio.
	Stances = table.freeze({
		confident = table.freeze({
			armRaise = { l = 9, r = 9 }, elbow = { l = 22, r = 22 }, curl = { l = 38, r = 38 },
			chestPitch = -2, headPitch = -2,
		}),
		openHand = table.freeze({
			armForward = { l = 24, r = 0 }, armRaise = { l = 26, r = 6 }, elbow = { l = 62, r = 14 }, curl = { l = -10, r = 18 },
			spineTwist = -4, headYaw = 6,
		}),
		crossed = table.freeze({
			armForward = { l = 42, r = 42 }, armRaise = { l = -22, r = -22 }, elbow = { l = 118, r = 126 }, curl = { l = 14, r = 14 },
			spineTwist = 5, headPitch = 3, quiet = true,
		}),
		handToFace = table.freeze({
			armForward = { l = 0, r = 54 }, armRaise = { l = 6, r = -10 }, elbow = { l = 18, r = 100 }, curl = { l = 24, r = 40 },
			spineTwist = -3, headYaw = -8, headRoll = 4,
		}),
		relaxed = table.freeze({
			armForward = { l = -6, r = -6 }, armRaise = { l = 5, r = 5 }, elbow = { l = 26, r = 26 }, curl = { l = 20, r = 20 },
			lean = -2, headRoll = -3,
		}),
	}),
	StanceBySlot = table.freeze({ [0] = "confident", [1] = "openHand", [2] = "crossed", [3] = "handToFace", [4] = "relaxed" }),
	-- The squad line-up is seen from slightly above and to the front, so the
	-- camera drifts a little (studs) to give parallax.
	CameraDrift = table.freeze({ X = 0.35, Y = 0.12, Yaw = 0.008, Speed = 0.3 }),
	-- Client-only "night rooftop" look while the hub is open (restored on exit).
	-- The ambient is high enough for the city facades to read; the bloom
	-- threshold keeps skin out of the glow so only neon blooms.
	Look = table.freeze({
		Lighting = table.freeze({
			Ambient = Color3.fromRGB(40, 28, 64),
			OutdoorAmbient = Color3.fromRGB(92, 64, 142),
			Brightness = 1,
			ClockTime = 0,
			ExposureCompensation = 0.05,
			EnvironmentDiffuseScale = 0.6,
			EnvironmentSpecularScale = 0,
		}),
		-- Threshold above 1: only neon blooms, never the avatars.
		Bloom = table.freeze({ Intensity = 0.55, Size = 30, Threshold = 1.3 }),
		Grade = table.freeze({ Contrast = 0.14, Saturation = 0.26, Brightness = 0, Tint = Color3.fromRGB(245, 234, 255) }),
		Depth = table.freeze({ FarIntensity = 0.12, FocusDistance = 19, InFocusRadius = 26, NearIntensity = 0 }),
	}),
	-- Client-only atmosphere while the lobby is open (restored on exit):
	-- purple haze that still lets the lit city through.
	Atmosphere = table.freeze({
		Density = 0.22,
		Offset = 0.1,
		Color = Color3.fromRGB(120, 60, 170),
		Decay = Color3.fromRGB(40, 20, 70),
		Glare = 0.3,
		Haze = 1.4,
	}),
	-- The selected mode tints the haze and the menu accent.
	Modes = table.freeze({
		-- The JUGAR page opens a MULTIJUGADOR gateway before showing these
		-- queues. Modes without a complete server flow stay visible but locked.
		table.freeze({
			id = "ranked",
			name = "COMPETITIVO",
			locked = true,
			description = "Escuadrón contra escuadrón. Cada partida cuenta para tu rango.",
			detail = "Lobby competitivo: todo el escuadrón debe estar LISTO antes de buscar. Las partidas se juegan en servidores dedicados.",
			rules = "5 VS 5  ·  RONDAS DE ELIMINACIÓN  ·  PRIMERO A 6",
			rank = "RANGO: SIN CLASIFICAR",
			accent = Color3.fromRGB(255, 40, 70),
			haze = Color3.fromRGB(170, 30, 50),
			decay = Color3.fromRGB(60, 10, 20),
		}),
		table.freeze({
			id = "quick",
			name = "PARTIDA RÁPIDA",
			description = "Duelo por equipos 5 contra 5 con jugadores de otros servidores.",
			detail = "Duelo por equipos: gana el equipo con más eliminaciones. Buscamos partida para tu escuadrón completo; puedes cancelar cuando quieras.",
			rules = "5 VS 5  ·  DUELO POR EQUIPOS  ·  REAPARICIÓN",
			accent = Color3.fromRGB(0, 229, 255),
			haze = Color3.fromRGB(30, 120, 170),
			decay = Color3.fromRGB(10, 40, 70),
		}),
		table.freeze({
			id = "private",
			name = "PARTIDA PRIVADA",
			description = "Crea una sala con código o únete a la partida de otro jugador.",
			detail = "Crea un código de seis caracteres para compartir o coloca uno existente. Cada sala admite hasta 10 jugadores.",
			rules = "CÓDIGO PRIVADO  ·  HASTA 10 JUGADORES  ·  5 VS 5",
			accent = Color3.fromRGB(170, 90, 255),
			haze = Color3.fromRGB(120, 60, 170),
			decay = Color3.fromRGB(40, 20, 70),
		}),
		table.freeze({
			id = "training",
			name = "MODO ENTRENAMIENTO",
			locked = true,
			description = "Practica movimiento, puntería y armas contra objetivos.",
			detail = "Entra a una zona de práctica para probar armas, movilidad y sensibilidad sin buscar una partida.",
			rules = "PRÁCTICA  ·  OBJETIVOS  ·  SIN CLASIFICACIÓN",
			accent = Color3.fromRGB(255, 190, 60),
			haze = Color3.fromRGB(145, 92, 30),
			decay = Color3.fromRGB(58, 30, 10),
		}),
	}),
	Tabs = table.freeze({
		table.freeze({ id = "play", label = "JUGAR" }),
		table.freeze({ id = "character", label = "PERSONAJE" }),
		table.freeze({ id = "squad", label = "ESCUADRÓN" }),
		table.freeze({ id = "shop", label = "TIENDA" }),
		table.freeze({ id = "settings", label = "AJUSTES" }),
		table.freeze({ id = "credits", label = "CRÉDITOS" }),
	}),
	SquadSize = 4,
	-- Squad rings stay empty for invited players; true fills them with AI
	-- placeholders (useful only for previewing the layout).
	ShowAISquad = false,
	SquadNames = table.freeze({ "Nova", "Raze", "Vex", "Kairo" }),
}

return table.freeze(LobbyConfig)
