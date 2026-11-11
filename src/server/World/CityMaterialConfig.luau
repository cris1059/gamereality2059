--!strict

-- Hand-authored material roles for the imported City2059 mesh groups.
-- Keep this separate from City2059Data: that module is generated from the GLB
-- and may be rebuilt whenever collision data changes.

local roles = table.freeze({
	Asphalt = table.freeze({
		variantName = "R2059_Asphalt",
		baseMaterial = Enum.Material.Asphalt,
		fallbackMaterial = Enum.Material.Asphalt,
		studsPerTile = 16,
	}),
	Concrete = table.freeze({
		variantName = "R2059_Concrete",
		baseMaterial = Enum.Material.Concrete,
		fallbackMaterial = Enum.Material.Concrete,
		studsPerTile = 12,
	}),
	Metal = table.freeze({
		variantName = "R2059_Metal",
		baseMaterial = Enum.Material.Metal,
		fallbackMaterial = Enum.Material.Metal,
		studsPerTile = 10,
	}),
	Facade = table.freeze({
		variantName = "R2059_Facade",
		baseMaterial = Enum.Material.Metal,
		fallbackMaterial = Enum.Material.Metal,
		studsPerTile = 12,
	}),
})

local pieceRoles: { [string]: string } = {}

local function register(role: string, names: { string })
	for _, name in names do
		pieceRoles[name] = role
	end
end

-- Roads and broad floor plates.
register("Asphalt", {
	"Cuberpunk2077.003",
	"City2059_02_Meshpart1Mtl",
	"Cuberpunk2077.029",
	"City2059_28_Meshpart30Mtl",
})

-- Sidewalks, ramps, structural concrete and weathered lower walls.
register("Concrete", {
	"Cuberpunk2077.005",
	"City2059_04_Meshpart3Mtl",
	"Cuberpunk2077.006",
	"City2059_05_Meshpart4Mtl",
	"Cuberpunk2077.020",
	"City2059_19_Meshpart19Mtl",
	"Cuberpunk2077.025",
	"City2059_24_Meshpart24Mtl",
})

-- Structural metal, decks and mechanical details.
register("Metal", {
	"Cuberpunk2077.007",
	"City2059_06_Meshpart5Mtl",
	"Cuberpunk2077.008",
	"City2059_07_Meshpart6Mtl",
	"Cuberpunk2077.011",
	"City2059_10_Meshpart9Mtl",
	"Cuberpunk2077.013",
	"City2059_12_Meshpart12Mtl",
	"Cuberpunk2077.016",
	"City2059_15_Meshpart15Mtl",
	"Cuberpunk2077.019",
	"City2059_18_Meshpart18Mtl",
	"Cuberpunk2077.027",
	"City2059_26_Meshpart27Mtl",
})

-- Tower shells and coated architectural panels.
register("Facade", {
	"Cuberpunk2077.004",
	"City2059_03_Meshpart2Mtl",
	"Cuberpunk2077.009",
	"City2059_08_Meshpart7Mtl",
	"Cuberpunk2077.012",
	"City2059_11_Meshpart11Mtl",
	"Cuberpunk2077.021",
	"City2059_20_Meshpart20Mtl",
	"Cuberpunk2077.022",
	"City2059_21_Meshpart21Mtl",
	"Cuberpunk2077.024",
	"City2059_23_Meshpart23Mtl",
})

-- Deliberately excluded:
-- .002, .030 and .031 are the three special UV/alpha groups whose original
-- source images are missing. Replacing them blindly can cover road markings
-- or special props. Emissive groups also stay as Neon.

return table.freeze({
	Roles = roles,
	PieceRoles = table.freeze(pieceRoles),
	TexturePackPath = "assets-source/textures/city2059_pbr",
})
