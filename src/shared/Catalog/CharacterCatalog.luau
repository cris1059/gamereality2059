--!strict

-- Character catalog for standard Roblox R15 avatars (blocky body). Ids are
-- what gets saved; assetId values are real Roblox catalog items, checked on
-- 2026-10-26 with the public catalog/economy APIs and their thumbnails.
-- Catalog items are applied through HumanoidDescription, so players do not
-- need to own them. Appending is safe; renaming or removing an id makes saved
-- characters invalid (the profile then goes back to MORPHLAB).
return table.freeze({
	-- Body: both use the default blocky R15 parts; "slim" narrows width and depth.
	BodyBases = table.freeze({ "classic", "slim" }),
	BodyInfo = table.freeze({
		classic = table.freeze({ name = "CLÁSICO", description = "Cuerpo de bloques estándar", width = 1 }),
		slim = table.freeze({ name = "ESBELTO", description = "Más angosto de hombros y cadera", width = 0.88 }),
	}),
	-- Ordered light to dark, then synthetic tones. Selectable list only;
	-- SkinToneColors also keeps retired tones so old saves stay valid.
	SkinTones = table.freeze({
		"neutral_light", "neutral_sand", "neutral_medium",
		"neutral_tan", "neutral_dark", "neutral_deep",
		"synth_ash", "synth_azure", "synth_violet",
	}),
	SkinToneColors = table.freeze({
		neutral_porcelain = Color3.fromRGB(205, 180, 160),
		neutral_light = Color3.fromRGB(190, 158, 132),
		neutral_sand = Color3.fromRGB(172, 132, 100),
		neutral_medium = Color3.fromRGB(176, 139, 116),
		neutral_tan = Color3.fromRGB(141, 101, 76),
		neutral_dark = Color3.fromRGB(101, 70, 55),
		neutral_deep = Color3.fromRGB(66, 41, 30),
		synth_ash = Color3.fromRGB(160, 166, 178),
		synth_azure = Color3.fromRGB(118, 156, 214),
		synth_violet = Color3.fromRGB(158, 126, 206),
	}),
	-- Faces are expression presets drawn on the blocky head (Character/FaceArt).
	-- Each entry maps FaceControls-style channel names → 0..1 values.
	Faces = table.freeze({
		"smile", "chill", "stare", "suspicious", "not_amused", "check_it",
		"grin", "friendly", "vampire", "shiny_teeth", "tired", "sigmund", "asombro",
	}),
	FaceInfo = table.freeze({
		smile       = table.freeze({ name = "SONRISA" }),
		chill       = table.freeze({ name = "TRANQUILO" }),
		stare       = table.freeze({ name = "MIRADA FIJA" }),
		suspicious  = table.freeze({ name = "SOSPECHOSO" }),
		not_amused  = table.freeze({ name = "ENOJADO" }),
		check_it    = table.freeze({ name = "CONFIADO" }),
		grin        = table.freeze({ name = "SABELOTODO" }),
		friendly    = table.freeze({ name = "AMISTOSO" }),
		vampire     = table.freeze({ name = "VAMPIRO" }),
		shiny_teeth = table.freeze({ name = "SONRISA BRILLANTE" }),
		tired       = table.freeze({ name = "CANSADO" }),
		sigmund     = table.freeze({ name = "PENSATIVO" }),
		asombro     = table.freeze({ name = "ASOMBRO" }),
	}),
	-- Resting expression per face (blink and gestures are layered on top in
	-- AvatarPreview). Channels FaceArt does not draw are ignored.
	FaceExpressions = table.freeze({
		smile       = table.freeze({ LeftLipCornerPuller = 0.7, RightLipCornerPuller = 0.7, LeftCheekRaiser = 0.4, RightCheekRaiser = 0.4 }),
		chill       = table.freeze({}),
		stare       = table.freeze({ LeftBrowLowerer = 0.25, RightBrowLowerer = 0.25 }),
		suspicious  = table.freeze({ LeftEyeClosed = 0.3, LeftBrowLowerer = 0.5 }),
		not_amused  = table.freeze({ LeftLipCornerDepressor = 0.45, RightLipCornerDepressor = 0.45, LeftBrowLowerer = 0.3, RightBrowLowerer = 0.3 }),
		check_it    = table.freeze({ RightLipCornerPuller = 0.55 }),
		grin        = table.freeze({ LeftLipCornerPuller = 0.9, RightLipCornerPuller = 0.9, JawDrop = 0.3 }),
		friendly    = table.freeze({ LeftLipCornerPuller = 0.5, RightLipCornerPuller = 0.5 }),
		vampire     = table.freeze({ JawDrop = 0.2, LeftLipCornerPuller = 0.2, RightLipCornerPuller = 0.2 }),
		shiny_teeth = table.freeze({ LeftLipCornerPuller = 0.85, RightLipCornerPuller = 0.85, JawDrop = 0.2 }),
		tired       = table.freeze({ LeftEyeClosed = 0.45, RightEyeClosed = 0.45, LeftLipCornerDepressor = 0.25, RightLipCornerDepressor = 0.25 }),
		sigmund     = table.freeze({ LeftBrowLowerer = 0.3, LeftInnerBrowRaiser = 0.4 }),
		-- Boca abierta, cejas levantadas, ojos abiertos: expresión de asombro.
		asombro     = table.freeze({ JawDrop = 0.65, LeftInnerBrowRaiser = 0.75, RightInnerBrowRaiser = 0.75, LeftOuterBrowRaiser = 0.45, RightOuterBrowRaiser = 0.45, LeftEyeUpperLidRaiser = 0.5, RightEyeUpperLidRaiser = 0.5 }),
	}),
	-- Roblox's built-in classic smile (kept for fallback UI icons).
	DefaultFaceImage = "rbxasset://textures/face.png",
	-- Hair accessories. "none" is the persisted bald option.
	Hair = table.freeze({
		"none", "spiky_white", "mullet_white", "black_anime", "messy_black",
		"wolf_black", "pink_spiky", "true_blue", "blonde_spiked", "pal",
		"long_black", "straight_blonde", "red_long", "beanie",
	}),
	-- gender: "m" = shown for classic body, "f" = slim body, "both" = always shown.
	HairInfo = table.freeze({
		none           = table.freeze({ name = "SIN CABELLO",    assetId = 0,             gender = "both" }),
		spiky_white    = table.freeze({ name = "PICOS BLANCOS",  assetId = 7855160231,    gender = "m" }),
		mullet_white   = table.freeze({ name = "MULLET BLANCO",  assetId = 15518201811,   gender = "m" }),
		black_anime    = table.freeze({ name = "ANIME NEGRO",    assetId = 5891039736,    gender = "both" }),
		messy_black    = table.freeze({ name = "DESPEINADO",     assetId = 6823338112,    gender = "both" }),
		wolf_black     = table.freeze({ name = "LOBO",           assetId = 11770892209,   gender = "both" }),
		pink_spiky     = table.freeze({ name = "PICOS ROSA",     assetId = 98056302834725, gender = "f" }),
		true_blue      = table.freeze({ name = "AZUL ELÉCTRICO", assetId = 451221329,     gender = "both" }),
		blonde_spiked  = table.freeze({ name = "PICOS RUBIOS",   assetId = 376524487,     gender = "m" }),
		pal            = table.freeze({ name = "CLÁSICO",        assetId = 63690008,      gender = "both" }),
		long_black     = table.freeze({ name = "LARGO NEGRO",    assetId = 6778986933,    gender = "f" }),
		straight_blonde= table.freeze({ name = "LARGO RUBIO",    assetId = 376526888,     gender = "f" }),
		red_long       = table.freeze({ name = "LARGO ROJO",     assetId = 2956239660,    gender = "f" }),
		beanie         = table.freeze({ name = "GORRO",          assetId = 1103003368,    gender = "both" }),
	}),
	-- Outfits: a layered jacket over layered pants (both wrap the R15 body).
	Outfits = table.freeze({ "shadow", "neon_nomad", "trench", "runner", "netrunner", "pink_neon" }),
	OutfitInfo = table.freeze({
		shadow = table.freeze({ name = "SOMBRA", description = "Chaqueta techwear negra con capucha", jacket = 82901761169801, pants = 115840857367160 }),
		neon_nomad = table.freeze({ name = "NÓMADA NEÓN", description = "Gabardina techwear con filos morados", jacket = 17638726481, pants = 96794685714412 }),
		trench = table.freeze({ name = "GABARDINA", description = "Gabardina negra de corte clásico", jacket = 112139675895657, pants = 96794685714412 }),
		runner = table.freeze({ name = "CORREDOR", description = "Chaqueta táctica y cargo rojo", jacket = 75814593616002, pants = 98215366502157 }),
		netrunner = table.freeze({ name = "NETRUNNER", description = "Chaqueta gris con circuitos azules", jacket = 86527487837023, pants = 77739657309673 }),
		pink_neon = table.freeze({ name = "ROSA NEÓN", description = "Gabardina techwear con filos rosas", jacket = 17638769103, pants = 122271532800788 }),
	}),
	-- Outfit pieces, worn independently; any slot can be "none" (MORPHLAB
	-- starts with all of them off). Layered clothing; ids checked on
	-- 2026-10-26 (jackets type 67, pants 66, shirts 65/64, shoes 70/71).
	-- Characters saved before the split keep outfitId (see CharacterDraft.pieces).
	OutfitSlots = table.freeze({ "jacket", "shirt", "pants", "shoes" }),
	OutfitPieces = table.freeze({
		jacket = table.freeze({ "none", "shadow", "neon_nomad", "trench", "runner", "netrunner", "pink_neon" }),
		shirt = table.freeze({ "none", "circuit", "cyber", "camo_vest", "tech_mono", "tech_red", "tank_black", "tee_black" }),
		pants = table.freeze({ "none", "shadow", "techwear", "cargo_red", "circuit_grey", "pink_neon" }),
		shoes = table.freeze({ "none", "sneaker_black", "sneaker_white", "sneaker_red", "high_top", "cyber_green", "punk_boots" }),
	}),
	PieceInfo = table.freeze({
		jacket = table.freeze({
			shadow = table.freeze({ name = "SOMBRA", assetId = 82901761169801 }),
			neon_nomad = table.freeze({ name = "NÓMADA NEÓN", assetId = 17638726481 }),
			trench = table.freeze({ name = "GABARDINA", assetId = 112139675895657 }),
			runner = table.freeze({ name = "TÁCTICA", assetId = 75814593616002 }),
			netrunner = table.freeze({ name = "NETRUNNER", assetId = 86527487837023 }),
			pink_neon = table.freeze({ name = "ROSA NEÓN", assetId = 17638769103 }),
		}),
		shirt = table.freeze({
			circuit = table.freeze({ name = "CIRCUITO", assetId = 9343015281, type = "Shirt" }),
			cyber = table.freeze({ name = "CIBER", assetId = 131721143652968, type = "Shirt" }),
			camo_vest = table.freeze({ name = "CHALECO CAMO", assetId = 92930016773018, type = "Shirt" }),
			tech_mono = table.freeze({ name = "TECH MONOCROMO", assetId = 10681139574, type = "Shirt" }),
			tech_red = table.freeze({ name = "TECH ROJA", assetId = 10681146192, type = "Shirt" }),
			tank_black = table.freeze({ name = "TANK NEGRA", assetId = 80814550211761, type = "Shirt" }),
			tee_black = table.freeze({ name = "PLAYERA NEGRA", assetId = 128166455974489, type = "TShirt" }),
		}),
		pants = table.freeze({
			shadow = table.freeze({ name = "CARGO NEGRO", assetId = 115840857367160 }),
			techwear = table.freeze({ name = "TECHWEAR", assetId = 96794685714412 }),
			cargo_red = table.freeze({ name = "CARGO ROJO", assetId = 98215366502157 }),
			circuit_grey = table.freeze({ name = "GRIS CIRCUITO", assetId = 77739657309673 }),
			pink_neon = table.freeze({ name = "ROSA NEÓN", assetId = 122271532800788 }),
		}),
		shoes = table.freeze({
			sneaker_black = table.freeze({ name = "TENIS NEGROS", left = 94211187409746, right = 130327592097332 }),
			sneaker_white = table.freeze({ name = "TENIS BLANCOS", left = 133857839133671, right = 94878716288008 }),
			sneaker_red = table.freeze({ name = "TENIS ROJOS", left = 136486730762511, right = 128357589764045 }),
			high_top = table.freeze({ name = "BOTA TENIS", left = 85415418011919, right = 82907354089354 }),
			cyber_green = table.freeze({ name = "CIBER VERDES", left = 76868452454010, right = 96406198772627 }),
			punk_boots = table.freeze({ name = "BOTAS PUNK", left = 133205499131983, right = 101843831215129 }),
		}),
	}),
	-- Head gear from the catalog, several at once (kind = the accessory type).
	Accessories = table.freeze({
		"visor_purple", "visor_cyan", "visor_red", "visor_cyclops",
		"horns_red", "horns_mech", "horns_azure",
		"phones_edm", "phones_mecha", "phones_hex",
	}),
	AccessoryInfo = table.freeze({
		visor_purple = table.freeze({ name = "VISOR GLITCH", assetId = 74165203905873, kind = "Face" }),
		visor_cyan = table.freeze({ name = "VISOR CIAN", assetId = 78128028122277, kind = "Face" }),
		visor_red = table.freeze({ name = "VISOR ROJO", assetId = 77829375626907, kind = "Face" }),
		visor_cyclops = table.freeze({ name = "VISOR CÍCLOPE", assetId = 78915122250708, kind = "Face" }),
		horns_red = table.freeze({ name = "CUERNOS ROJOS", assetId = 13388808482, kind = "Hat" }),
		horns_mech = table.freeze({ name = "CUERNOS MECH", assetId = 15731459698, kind = "Hat" }),
		horns_azure = table.freeze({ name = "CUERNOS AZUR", assetId = 128129205543959, kind = "Hat" }),
		phones_edm = table.freeze({ name = "AUDÍFONOS EDM", assetId = 16742423103, kind = "Hat" }),
		phones_mecha = table.freeze({ name = "AUDÍFONOS MECHA", assetId = 13345570140, kind = "Hat" }),
		phones_hex = table.freeze({ name = "AUDÍFONOS HEX", assetId = 11838144719, kind = "Hat" }),
	}),
	MaxAccessories = 3,
	-- COLOR: neon and metal finishes for the cyberware.
	ColorSlots = table.freeze({ "neonPrimary", "neonSecondary", "metal" }),
	NeonColors = table.freeze({ "red", "cyan", "magenta", "green", "yellow", "orange", "violet", "white" }),
	NeonColorValues = table.freeze({
		red = Color3.fromRGB(255, 32, 48),
		cyan = Color3.fromRGB(0, 229, 255),
		magenta = Color3.fromRGB(255, 40, 190),
		green = Color3.fromRGB(60, 255, 140),
		yellow = Color3.fromRGB(255, 225, 60),
		orange = Color3.fromRGB(255, 120, 30),
		violet = Color3.fromRGB(150, 100, 255),
		white = Color3.fromRGB(235, 240, 255),
	}),
	MetalFinishes = table.freeze({ "gunmetal", "chrome", "black", "gold", "white" }),
	MetalFinishValues = table.freeze({
		gunmetal = table.freeze({ color = Color3.fromRGB(40, 44, 56), reflectance = 0.05 }),
		chrome = table.freeze({ color = Color3.fromRGB(190, 196, 206), reflectance = 0.35 }),
		black = table.freeze({ color = Color3.fromRGB(14, 14, 18), reflectance = 0 }),
		gold = table.freeze({ color = Color3.fromRGB(212, 170, 70), reflectance = 0.2 }),
		white = table.freeze({ color = Color3.fromRGB(225, 228, 235), reflectance = 0.05 }),
	}),
	DefaultColors = table.freeze({ neonPrimary = "red", neonSecondary = "cyan", metal = "gunmetal" }),
	-- Gameplay role. Stats (1..5) are data only for now; the server will read
	-- them when combat exists. Colour tints the MORPHLAB platform and UI.
	Classes = table.freeze({ "runner", "netrunner", "enforcer", "ghost", "medtech" }),
	ClassStatKeys = table.freeze({ "speed", "armor", "hacking", "stealth", "support" }),
	ClassInfo = table.freeze({
		runner = table.freeze({ color = Color3.fromRGB(0, 229, 255), stats = table.freeze({ speed = 5, armor = 2, hacking = 1, stealth = 3, support = 2 }) }),
		netrunner = table.freeze({ color = Color3.fromRGB(60, 255, 140), stats = table.freeze({ speed = 3, armor = 1, hacking = 5, stealth = 3, support = 2 }) }),
		enforcer = table.freeze({ color = Color3.fromRGB(255, 96, 40), stats = table.freeze({ speed = 2, armor = 5, hacking = 1, stealth = 1, support = 3 }) }),
		ghost = table.freeze({ color = Color3.fromRGB(150, 110, 255), stats = table.freeze({ speed = 4, armor = 1, hacking = 2, stealth = 5, support = 1 }) }),
		medtech = table.freeze({ color = Color3.fromRGB(255, 210, 90), stats = table.freeze({ speed = 3, armor = 2, hacking = 2, stealth = 1, support = 5 }) }),
	}),
	-- Cyberware built by the game (Character/R15Cyberware), welded to the
	-- body. "none" is the persisted placeholder for an empty loadout.
	Implants = table.freeze({ "none", "cyber_eye", "visor", "jaw_plate", "face_circuits", "neck_ports", "cyber_arm" }),
	MaxImplants = 8,
})
