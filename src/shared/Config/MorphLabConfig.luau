--!strict

local MorphLabConfig = {
	SceneVersion = 25,
	RuntimeFolderName = "Reality2059Runtime",
	ModelName = "MorphLab",
	-- A single environment: a night rooftop beside the lobby, facing City2059
	-- (the lobby's lit skyline and sky rift are cloned in while it is open).
	ForcedEnvironmentVariant = "NEO_EDEN_ROOFTOP",
	EnvironmentVariants = table.freeze({ "NEO_EDEN_ROOFTOP" }),
	-- Rooftop beside the lobby (same height and city view, see
	-- LobbyConfig.CityHeightFraction), far enough sideways that neither scene
	-- shows up in the other's camera.
	RooftopOffset = Vector3.new(-120, 0, 0),
	-- Used when the lobby (and the city) are missing.
	Origin = Vector3.new(0, 96, 220),
	-- Neon parts are partly transparent to tone down their glow.
	NeonTransparency = 0.55,
	Palette = table.freeze({
		Background = Color3.fromRGB(8, 12, 20),
		Surface = Color3.fromRGB(18, 26, 38),
		Graphite = Color3.fromRGB(25, 31, 43),
		Cyan = Color3.fromRGB(0, 229, 255),
		-- Accent token kept under its original name (the lobby uses it as red).
		Magenta = Color3.fromRGB(255, 32, 48),
		Violet = Color3.fromRGB(150, 28, 44),
		Text = Color3.fromRGB(234, 244, 255),
		-- MORPHLAB art direction: violet neon on deep indigo glass.
		Purple = Color3.fromRGB(168, 92, 255),
		PurpleSoft = Color3.fromRGB(120, 70, 200),
		PurpleDeep = Color3.fromRGB(46, 22, 88),
		Glass = Color3.fromRGB(12, 10, 26),
		Muted = Color3.fromRGB(150, 140, 190),
	}),
	-- Client-only Lighting override while MORPHLAB is open (restored on exit):
	-- a night sky for the city; no environment specular, so skin and hair
	-- stay matte.
	SceneLighting = table.freeze({
		Ambient = Color3.fromRGB(56, 46, 82),
		OutdoorAmbient = Color3.fromRGB(96, 76, 140),
		Brightness = 1,
		ClockTime = 0,
		ExposureCompensation = 0.05,
		EnvironmentDiffuseScale = 0.45,
		EnvironmentSpecularScale = 0,
	}),
	-- Animated vortex in the sky (client-only, MorphLabVortex), placed from the
	-- camera: turned right / up (degrees), its radius as an angle.
	Vortex = table.freeze({
		Distance = 380,
		YawDegrees = -15,
		PitchDegrees = 14,
		RadiusDegrees = 5.5,
	}),
	-- Bloom only on neon (threshold above 1), kept faint.
	Bloom = table.freeze({ Intensity = 0.25, Size = 22, Threshold = 1.6 }),
	Typography = table.freeze({
		-- Zekton/SciFi is Roblox's closest native display face to BLANKA.
		-- Keep this token centralized so a future licensed font asset can replace it.
		Display = Enum.Font.SciFi,
		Interface = Enum.Font.Jura,
		Technical = Enum.Font.Code,
		-- Reserved for dynamic bitmap text. Disabled until variable-width
		-- metrics are required; the START screen uses a pre-kerned overlay.
		BitmapAtlasId = "",
		BitmapCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,:;!?+-/%()[]<>_",
		BitmapColumns = 8,
		BitmapCellSize = 192,
	}),
	StartScreen = table.freeze({
		UseNativeBackground = true,
		BackgroundImageId = "",
		BackgroundLeftImageId = "",
		BackgroundRightImageId = "",
		BlankaOverlayImageId = "",
	}),
	-- Full-body framing between the side columns from a low angle, so the
	-- city rises behind the avatar and the vortex sits above it.
	Camera = table.freeze({
		PositionOffset = Vector3.new(0, 4.9, 13.5),
		LookOffset = Vector3.new(0, 4.3, 0),
		FieldOfView = 42,
		BlendSpeed = 3.2,
		MinZoom = -4,
		MaxZoom = 6,
		ZoomStep = 1.5,
		-- Kept for the camera controller's close-up limits.
		FaceMinZoom = -1.2,
		FaceMaxZoom = 3,
	}),
	Preview = table.freeze({
		-- Turntable: the arrows turn by a step, dragging turns by pixels.
		TurnStepRadians = math.rad(18),
		DragRadiansPerPixel = 0.012,
		RotationBlendSpeed = 12,
		-- Every IdleSeconds (random range) the avatar strikes one of the
		-- poses for HoldSeconds, then returns to the breathing idle.
		IdleSeconds = NumberRange.new(5, 9),
		HoldSeconds = 2.8,
	}),
	-- Poses for the preview (R15Pose stance format, see LobbyConfig.Stances).
	Poses = table.freeze({
		-- The reference art: chin up, arms out from the body, feet apart.
		hero = table.freeze({
			armRaise = { l = 14, r = 14 }, elbow = { l = 18, r = 18 },
			legSpread = 7, chestPitch = -3, headPitch = 4,
		}),
		crossed = table.freeze({
			armForward = { l = 42, r = 42 }, armRaise = { l = -22, r = -22 }, elbow = { l = 118, r = 126 },
			legSpread = 3, spineTwist = 5, headPitch = 3,
		}),
		thinking = table.freeze({
			armForward = { l = 0, r = 54 }, armRaise = { l = 6, r = -10 }, elbow = { l = 18, r = 100 },
			spineTwist = -3, headYaw = -8, headRoll = 4,
		}),
		wave = table.freeze({
			armForward = { l = 0, r = 10 }, armRaise = { l = 6, r = 150 }, elbow = { l = 14, r = 40 },
			headYaw = 6, headRoll = -3,
		}),
	}),
	PoseOrder = table.freeze({ "hero", "wave", "crossed", "hero", "thinking" }),
}

return table.freeze(MorphLabConfig)
