--!strict

-- Weapons: carried loadout, pickups and the weapon import.

local WeaponConfig = {
	-- Weapons a player can carry; picking one up with a full loadout swaps it
	-- for the one in hand (which is dropped where the pickup was).
	MaxSlots = 2,
	-- Weapon Tools, built once in Studio by Weapons/WeaponImporter.
	StorageFolder = "Weapons",
	Pickup = table.freeze({
		Key = Enum.KeyCode.E,
		GamepadKey = Enum.KeyCode.ButtonX,
		MaxDistance = 8,
		-- Armory pickups come back after this long (map tests).
		RespawnSeconds = 4,
	}),
	-- Map test armory: one pedestal per weapon in front of team A's spawns
	-- (map-local Z), unless the map has its own WeaponSpawns folder.
	Armory = table.freeze({
		RowZ = 138,
		RowGap = 5,
		Spacing = 5,
		PerRow = 40,
	}),
	-- Imported models are scaled so their longest side is within this range.
	LengthRange = NumberRange.new(1.4, 4.5),
	FallbackLength = 3.2,
	-- Creator Store models (free, no scripts), checked on 2026-10-26. Sketchfab
	-- re-uploads and very heavy meshes were left out.
	CatalogAssets = table.freeze({
		5409356848, -- Futuristic Gun Pack (BKing1261)
		5211081064, -- Sci-Fi Weapon Pack (LammerVulture)
		1882832085, -- Sci-fi guns (L_SR)
		4082840116, -- Sci Fi Rifle (Fauxia)
		14669763613, -- Paralyzer Laser Rifle
		10465481056, -- Futuristic Pistol
		14633438661, -- Sci-Fi Pistol Model
		10001772936, -- Sci-Fi double barrel shotgun
		110379825973729, -- Sci-Fi Double Barrel Shotgun (credit: tnnv)
		705764221, -- Sci-Fi Sniper Rifle (PuffleBuns)
		16833993204, -- Laser Sniper Rifle
		13664107153, -- Neon Sniper
	}),
}

return table.freeze(WeaponConfig)
