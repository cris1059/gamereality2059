--!strict

-- Custom inventory (replaces the Roblox backpack in MODO LIBRE). The server
-- owns the contents; the client only asks to equip / unequip.

local WeaponStats = require(script.Parent.Parent.Combat.WeaponStats)

-- Weapon items take their numbers from the combat classes, so the
-- inventory always shows what the weapon really does.
local function weapon(class: string, rarity: string, glyph: string, flavor: string)
	local stats = WeaponStats.Classes[class]
	local damage = if stats.pellets > 1 then string.format("%d x%d", stats.damage, stats.pellets) else tostring(stats.damage)
	return table.freeze({
		name = stats.name,
		category = "weapon",
		rarity = rarity,
		slot = "weapon",
		glyph = glyph,
		weaponClass = class,
		description = string.format(
			"%s\n\nDAÑO %s · CARGADOR %d · %s %.1f/s · ALCANCE %d",
			flavor,
			damage,
			stats.magazine,
			if stats.automatic then "AUTOMÁTICA" else "SEMIAUTO",
			stats.fireRate,
			stats.range
		),
	})
end

local InventoryConfig = {
	-- I / Y open and close it; touch screens get an INVENTARIO button.
	-- (Tab is taken by Roblox's player list.)
	ToggleKeys = table.freeze({ Enum.KeyCode.I, Enum.KeyCode.ButtonY }),
	MaxRequestsPerWindow = 20,
	RequestWindowSeconds = 10,

	Categories = table.freeze({
		{ id = "all", name = "TODO" },
		{ id = "weapon", name = "ARMAS" },
		{ id = "gear", name = "EQUIPO" },
		{ id = "consumable", name = "CONSUMIBLES" },
		{ id = "data", name = "DATOS" },
	}),

	-- Display order low -> high.
	Rarities = table.freeze({
		common = table.freeze({ name = "COMÚN", color = Color3.fromRGB(170, 178, 190), order = 1 }),
		uncommon = table.freeze({ name = "POCO COMÚN", color = Color3.fromRGB(80, 220, 120), order = 2 }),
		rare = table.freeze({ name = "RARO", color = Color3.fromRGB(0, 170, 255), order = 3 }),
		epic = table.freeze({ name = "ÉPICO", color = Color3.fromRGB(190, 70, 255), order = 4 }),
		legendary = table.freeze({ name = "LEGENDARIO", color = Color3.fromRGB(255, 176, 32), order = 5 }),
	}),

	-- Item catalog. Format:
	--   some_item = table.freeze({ name = "NOMBRE", category = "weapon", rarity = "rare",
	--       slot = "weapon" (or nil if not equippable), glyph = "X",
	--       icon = "rbxassetid://..." (optional), description = "..." }),
	-- Items a profile holds that are no longer in the catalog are kept in the
	-- save but not shown. Ids are saved in profiles: never rename one.
	-- Gear, consumables and data have no gameplay effect yet.
	Items = table.freeze({
		-- Weapons: one per combat class (Combat/WeaponStats).
		weapon_pistol = weapon("pistol", "common", "P", "Arma de mano fiable. Precisa a media distancia."),
		weapon_smg = weapon("smg", "uncommon", "S", "Cadencia altísima para el cuerpo a cuerpo urbano."),
		weapon_rifle = weapon("rifle", "rare", "R", "Equilibrada a cualquier distancia. El estándar de NEO-EDEN."),
		weapon_shotgun = weapon("shotgun", "rare", "E", "Ocho perdigones por disparo. Letal en pasillos."),
		weapon_sniper = weapon("sniper", "epic", "F", "Un disparo a la cabeza basta. Lenta de recargar."),

		-- Gear.
		gear_vest = table.freeze({
			name = "CHALECO BALÍSTICO", category = "gear", rarity = "uncommon", slot = "body", glyph = "C",
			description = "Placas de cerámica bajo tela táctica. Pensado para absorber impactos.",
		}),
		gear_visor = table.freeze({
			name = "VISOR TÁCTICO", category = "gear", rarity = "rare", slot = "gadget", glyph = "V",
			description = "Superpone datos del entorno sobre tu vista.",
		}),
		gear_drone = table.freeze({
			name = "DRON DE RECONOCIMIENTO", category = "gear", rarity = "epic", slot = "gadget", glyph = "D",
			description = "Dron plegable que explora por delante del escuadrón.",
		}),

		-- Consumables.
		consumable_medkit = table.freeze({
			name = "BOTIQUÍN", category = "consumable", rarity = "common", glyph = "+",
			description = "Vendas, sellador y un analgésico de grado militar.",
		}),
		consumable_stim = table.freeze({
			name = "ESTIMULANTE", category = "consumable", rarity = "uncommon", glyph = "!",
			description = "Inyector de adrenalina sintética. No abuses.",
		}),
		consumable_ammo = table.freeze({
			name = "CAJA DE MUNICIÓN", category = "consumable", rarity = "common", glyph = "M",
			description = "Cargadores universales para cualquier arma.",
		}),

		-- Data.
		data_chip = table.freeze({
			name = "CHIP DE DATOS", category = "data", rarity = "rare", glyph = "#",
			description = "Datos cifrados de una corporación. Alguien pagaría bien por ellos.",
		}),
		data_keycard = table.freeze({
			name = "TARJETA DE ACCESO", category = "data", rarity = "legendary", glyph = "K",
			description = "Abre puertas del SECTOR 7 que nadie debería abrir.",
		}),
	}),

	-- How many of each item the Studio dev grant gives (DevConfig.GrantAllItems).
	DevGrantQuantity = table.freeze({ consumable = 5, default = 1 }),

	Slots = table.freeze({ "weapon", "body", "gadget" }),
}

return table.freeze(InventoryConfig)
