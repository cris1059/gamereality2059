--!strict

-- Weapon classes and their numbers, shared by the server (validation,
-- damage) and the client (fire rate, spread, ammo display). A weapon's class
-- comes from its Tool's WeaponClass attribute, else from its name (sniper,
-- shotgun, pistol, smg...) and, failing that, from its size.

local WeaponStats = {}

export type Stats = {
	name: string,
	damage: number,
	pellets: number,
	fireRate: number, -- shots per second
	automatic: boolean,
	magazine: number,
	reloadSeconds: number,
	range: number,
	spread: number, -- degrees (hip fire)
	aimSpread: number, -- degrees (aiming down sights)
	headMultiplier: number,
	recoil: number, -- degrees of kick per shot
}

WeaponStats.Classes = table.freeze({
	pistol = table.freeze({ name = "PISTOLA", damage = 24, pellets = 1, fireRate = 4.5, automatic = false, magazine = 12, reloadSeconds = 1.4, range = 300, spread = 1.4, aimSpread = 0.5, headMultiplier = 2, recoil = 3 }),
	smg = table.freeze({ name = "SUBFUSIL", damage = 16, pellets = 1, fireRate = 11, automatic = true, magazine = 32, reloadSeconds = 1.8, range = 220, spread = 2.6, aimSpread = 1.2, headMultiplier = 1.8, recoil = 1.6 }),
	rifle = table.freeze({ name = "RIFLE", damage = 24, pellets = 1, fireRate = 8, automatic = true, magazine = 30, reloadSeconds = 2.1, range = 500, spread = 1.6, aimSpread = 0.35, headMultiplier = 2, recoil = 2.2 }),
	shotgun = table.freeze({ name = "ESCOPETA", damage = 12, pellets = 8, fireRate = 1.1, automatic = false, magazine = 6, reloadSeconds = 2.6, range = 120, spread = 6, aimSpread = 4.5, headMultiplier = 1.5, recoil = 7 }),
	sniper = table.freeze({ name = "FRANCOTIRADOR", damage = 85, pellets = 1, fireRate = 0.9, automatic = false, magazine = 5, reloadSeconds = 2.8, range = 1500, spread = 4, aimSpread = 0, headMultiplier = 2.5, recoil = 9 }),
})

-- Damage multiplier and label per body part (R15 part names).
WeaponStats.Zones = table.freeze({
	head = table.freeze({ label = "CABEZA", multiplier = 1 }), -- uses the weapon's headMultiplier
	torso = table.freeze({ label = "TORSO", multiplier = 1 }),
	arm = table.freeze({ label = "BRAZO", multiplier = 0.75 }),
	leg = table.freeze({ label = "PIERNA", multiplier = 0.75 }),
})

local PART_ZONES = table.freeze({
	Head = "head",
	UpperTorso = "torso", LowerTorso = "torso", HumanoidRootPart = "torso",
	LeftUpperArm = "arm", LeftLowerArm = "arm", LeftHand = "arm",
	RightUpperArm = "arm", RightLowerArm = "arm", RightHand = "arm",
	LeftUpperLeg = "leg", LeftLowerLeg = "leg", LeftFoot = "leg",
	RightUpperLeg = "leg", RightLowerLeg = "leg", RightFoot = "leg",
})

-- Zone of a body part, or nil when the part is not a body part (hair,
-- clothing and accessories count as the part they are worn on: see Resolve).
function WeaponStats.ZoneOf(partName: string): string?
	return PART_ZONES[partName]
end

local KEYWORDS = table.freeze({
	{ "sniper", "sniper" }, { "francotirador", "sniper" }, { "rail", "sniper" },
	{ "shotgun", "shotgun" }, { "barrel", "shotgun" }, { "escopeta", "shotgun" },
	{ "smg", "smg" }, { "pulse", "smg" }, { "subfusil", "smg" },
	{ "pistol", "pistol" }, { "revolver", "pistol" }, { "pistola", "pistol" },
	{ "rifle", "rifle" },
})

local function weaponLength(tool: Instance): number
	local longest = 0
	for _, part in tool:GetDescendants() do
		if part:IsA("BasePart") then
			longest = math.max(longest, part.Size.X, part.Size.Y, part.Size.Z)
		end
	end
	return longest
end

function WeaponStats.ClassOf(tool: Instance): string
	local attribute = tool:GetAttribute("WeaponClass")
	if type(attribute) == "string" and WeaponStats.Classes[attribute] then
		return attribute
	end
	local name = string.lower(tool.Name)
	for _, entry in KEYWORDS do
		if string.find(name, entry[1], 1, true) then
			return entry[2]
		end
	end
	return if weaponLength(tool) < 2.2 then "pistol" else "rifle"
end

function WeaponStats.Get(tool: Instance): Stats
	return WeaponStats.Classes[WeaponStats.ClassOf(tool)] :: any
end

return WeaponStats
