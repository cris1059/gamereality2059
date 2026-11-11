--!strict

-- Graphics quality profiles (CONFIGURACIÓN > CALIDAD GRÁFICA). AUTO follows
-- the Roblox graphics level of the device.

return table.freeze({
	Order = table.freeze({ "auto", "low", "medium", "high" }),
	Default = "auto",
	Profiles = table.freeze({
		low = table.freeze({ name = "BAJA", shadows = false, bloom = 0.4, atmosphere = 0.6, cityLife = 0.35 }),
		medium = table.freeze({ name = "MEDIA", shadows = true, bloom = 0.75, atmosphere = 0.85, cityLife = 0.7 }),
		high = table.freeze({ name = "ALTA", shadows = true, bloom = 1, atmosphere = 1, cityLife = 1 }),
	}),
	-- AUTO: Roblox quality level (1-10) at or below these picks the profile.
	AutoThresholds = table.freeze({ low = 3, medium = 6 }),
})
