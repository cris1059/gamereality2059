--!strict

-- Custom inventory (replaces the Roblox backpack in MODO LIBRE). The server
-- owns the contents; the client only asks to equip / unequip.

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

	-- Item catalog: empty until the game has real items. Format:
	--   some_item = table.freeze({ name = "NOMBRE", category = "weapon", rarity = "rare",
	--       slot = "weapon" (or nil if not equippable), glyph = "X",
	--       icon = "rbxassetid://..." (optional), description = "..." }),
	-- Items a profile holds that are no longer in the catalog are kept in the
	-- save but not shown.
	Items = table.freeze({}),

	Slots = table.freeze({ "weapon", "body", "gadget" }),
}

return table.freeze(InventoryConfig)
