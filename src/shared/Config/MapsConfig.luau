--!strict

-- Multiplayer maps (models built from src/server/Maps) and their lighting.
-- Each map is lit as day or night; the preset applies while it is played.

local MapsConfig = {
	Maps = table.freeze({
		DistritoNexus = table.freeze({ id = "nexus_grid", name = "DISTRITO NEXUS", timeOfDay = "day" }),
	}),
	Lighting = table.freeze({
		day = table.freeze({
			lighting = table.freeze({
				ClockTime = 13.5,
				Brightness = 2.4,
				Ambient = Color3.fromRGB(88, 90, 100),
				OutdoorAmbient = Color3.fromRGB(128, 130, 140),
				ExposureCompensation = 0,
				EnvironmentDiffuseScale = 1,
				EnvironmentSpecularScale = 0.4,
				GlobalShadows = true,
				FogStart = 0,
				FogEnd = 100000,
			}),
			atmosphere = table.freeze({
				Density = 0.28,
				Offset = 0.2,
				Color = Color3.fromRGB(199, 205, 215),
				Decay = Color3.fromRGB(106, 112, 125),
				Glare = 0,
				Haze = 0.5,
			}),
		}),
		night = table.freeze({
			lighting = table.freeze({
				ClockTime = 0,
				Brightness = 1,
				Ambient = Color3.fromRGB(40, 32, 62),
				OutdoorAmbient = Color3.fromRGB(70, 58, 110),
				ExposureCompensation = 0.1,
				EnvironmentDiffuseScale = 0.5,
				EnvironmentSpecularScale = 0.2,
				GlobalShadows = true,
				FogStart = 0,
				FogEnd = 100000,
			}),
			atmosphere = table.freeze({
				Density = 0.3,
				Offset = 0.1,
				Color = Color3.fromRGB(110, 70, 160),
				Decay = Color3.fromRGB(40, 20, 70),
				Glare = 0.2,
				Haze = 1.2,
			}),
		}),
	}),
}

return table.freeze(MapsConfig)
