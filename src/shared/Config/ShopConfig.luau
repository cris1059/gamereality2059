--!strict

-- TIENDA (lobby). Two parts:
--  * Items bought with NEOCRÉDITOS, browsed by category. Empty until the game
--    has items; each category then shows "vuelve pronto".
--  * NEOCRÉDITOS packs sold for Robux. Each pack is a Developer Product of
--    this experience: create it in the Creator Hub (your experience >
--    Monetization > Developer Products) with the same Robux price and paste
--    its id in productId. productId = 0 means "not created yet": the pack is
--    listed but cannot be bought.

local ShopConfig = {
	CurrencyName = "NEOCRÉDITOS",
	Categories = table.freeze({
		table.freeze({ id = "featured", name = "DESTACADO" }),
		table.freeze({ id = "outfits", name = "ATUENDOS" }),
		table.freeze({ id = "accessories", name = "ACCESORIOS" }),
		table.freeze({ id = "implants", name = "IMPLANTES" }),
		table.freeze({ id = "weapons", name = "ARMAS" }),
		table.freeze({ id = "emotes", name = "EMOTES" }),
	}),
	-- Items for sale. Format:
	--   table.freeze({ id = "item_id", name = "NOMBRE", category = "outfits",
	--       price = 500, rarity = "rare" (InventoryConfig.Rarities),
	--       icon = "rbxassetid://..." (optional), featured = true (optional) }),
	Items = table.freeze({}),
	CreditPacks = table.freeze({
		table.freeze({ id = "credits_s", name = "PAQUETE CHICO", credits = 500, robux = 49, bonus = "", productId = 0 }),
		table.freeze({ id = "credits_m", name = "PAQUETE MEDIO", credits = 1200, robux = 99, bonus = "+20%", productId = 0 }),
		table.freeze({ id = "credits_l", name = "PAQUETE GRANDE", credits = 2600, robux = 199, bonus = "+30%", productId = 0 }),
		table.freeze({ id = "credits_xl", name = "BÓVEDA", credits = 7000, robux = 499, bonus = "+40%", productId = 0 }),
	}),
	-- Receipt ids remembered per profile, so a receipt Roblox delivers twice
	-- never grants twice.
	ReceiptHistory = 50,
}

return table.freeze(ShopConfig)
