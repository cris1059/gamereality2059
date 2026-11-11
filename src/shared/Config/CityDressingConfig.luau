--!strict

-- Per-building cyberpunk dressing for City2059 (CityDressingService): every
-- tower gets its own brand, neon colour, screens, edge strips and rooftop
-- sign, anchored to its real walls (World/City2059Dressing). All brands are
-- fictional. a = main neon, b = accent, bg1/bg2 = screen gradient.

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

return table.freeze({
	Enabled = true,
	FolderName = "Dressing",
	-- Studs between a wall and the dressing in front of it.
	WallGap = 0.35,
	ScreenPixelsPerStud = 8,
	ScreenBrightness = 1.2,
	NeonThickness = 0.9,
	LightRange = 36,
	Styles = table.freeze({
		table.freeze({ brand = "KAIJU RAMEN", jp = "ラーメン", tag = "SABOR 24/7", a = rgb(255, 60, 40), b = rgb(255, 200, 60), bg1 = rgb(40, 4, 4), bg2 = rgb(120, 20, 10), font = Enum.Font.Oswald }),
		table.freeze({ brand = "SYNAPSE", jp = "シナプス", tag = "TU MENTE, MEJORADA", a = rgb(0, 220, 255), b = rgb(150, 90, 255), bg1 = rgb(2, 10, 30), bg2 = rgb(10, 60, 120), font = Enum.Font.Michroma }),
		table.freeze({ brand = "VOLT//X", jp = "電気", tag = "ENERGÍA SIN LÍMITE", a = rgb(60, 255, 90), b = rgb(220, 255, 60), bg1 = rgb(2, 20, 6), bg2 = rgb(10, 80, 30), font = Enum.Font.Arcade }),
		table.freeze({ brand = "CRIPTOVAULT", jp = "安全", tag = "TU DINERO, BLINDADO", a = rgb(90, 170, 255), b = rgb(230, 240, 255), bg1 = rgb(4, 8, 24), bg2 = rgb(30, 60, 140), font = Enum.Font.GothamBlack }),
		table.freeze({ brand = "AUGMENT", jp = "強化", tag = "MEJÓRATE HOY", a = rgb(255, 40, 110), b = rgb(255, 150, 190), bg1 = rgb(30, 2, 12), bg2 = rgb(140, 10, 60), font = Enum.Font.Michroma }),
		table.freeze({ brand = "ORBITAL", jp = "軌道", tag = "VIAJA MÁS ALLÁ", a = rgb(170, 90, 255), b = rgb(90, 220, 255), bg1 = rgb(10, 4, 30), bg2 = rgb(60, 20, 120), font = Enum.Font.SciFi }),
		table.freeze({ brand = "ZERO-G", jp = "無重力", tag = "BEBIDA ORBITAL", a = rgb(255, 220, 40), b = rgb(255, 120, 20), bg1 = rgb(30, 22, 2), bg2 = rgb(120, 80, 10), font = Enum.Font.Oswald }),
		table.freeze({ brand = "HOLO//MED", jp = "医療", tag = "CLÍNICA 24 HORAS", a = rgb(40, 255, 210), b = rgb(255, 255, 255), bg1 = rgb(2, 24, 22), bg2 = rgb(10, 90, 80), font = Enum.Font.Code }),
		table.freeze({ brand = "RED LOTUS", jp = "赤い蓮", tag = "CLUB NOCTURNO", a = rgb(255, 30, 60), b = rgb(255, 100, 200), bg1 = rgb(28, 2, 8), bg2 = rgb(90, 8, 40), font = Enum.Font.Michroma }),
		table.freeze({ brand = "NEO-EDEN", jp = "新楽園", tag = "EL FUTURO YA LLEGÓ", a = rgb(0, 255, 255), b = rgb(255, 40, 190), bg1 = rgb(4, 4, 20), bg2 = rgb(40, 10, 70), font = Enum.Font.SciFi }),
	}),
	-- Second, smaller screens.
	Promos = table.freeze({ "ABIERTO 24H", "NIVEL 59", "SECTOR 7", "ACCESO VIP", "OFERTA -59%", "REALIDAD 2059", "SIN LÍMITES", "CONECTA YA" }),
	-- Tag for UI elements the client animates (gradient scroll, flicker).
	FxTag = "Reality2059DressingFX",
})
