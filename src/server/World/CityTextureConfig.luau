--!strict

-- Cyberpunk texture sets for City2059 (scripts/generate_cyber_textures.py,
-- images in assets-source/textures/city2059_cyber). The city's UVs are
-- world-scale box projections, so each tile covers ~7.3 studs at scale 60
-- (one building floor) and stays upright on every wall.
--
-- Each set is a SurfaceAppearance template in ServerStorage/<TemplateFolder>
-- named like the set; CityTextureTool.Install() copies it into the listed
-- MeshParts. tint = true multiplies the texture by the piece's glTF colour
-- (brightened), so one neutral texture keeps the teal monorail teal and the
-- brown houses brown.

return table.freeze({
	TemplateFolder = "TexturasCyber",
	-- Sets not installed (and removed in play): the procedural window facade
	-- was replaced by the per-tower KitBash3D cladding.
	DisabledSets = table.freeze({ Facade = true }),
	-- Multiplied onto the installed textures in play (SurfaceAppearance.Color),
	-- so ground surfaces match the dark towers: streets darkest, sidewalks a
	-- cool dark grey so the two read apart. 1,1,1 = unchanged.
	PlayTint = table.freeze({
		Panels = Color3.new(0.7, 0.72, 0.78),
		Residential = Color3.new(0.62, 0.62, 0.66),
	}),
	-- Sets replaced in play by a plain colour (no texture, no pattern): the
	-- roads near-black and the sidewalks/plazas a smooth grey.
	-- Hidden in play (none now: the texture-less decal layer .002 forms the
	-- sidewalk edge, so it is painted like the sidewalk instead).
	HiddenPieces = table.freeze({}),
	-- Coplanar pairs z-fight into a two-tone checker even in the same colour
	-- (their normals differ): the lower piece of each pair is dropped this
	-- many studs in play so the upper one always wins.
	PieceDrop = table.freeze({
		["Cuberpunk2077.002"] = 0.08, -- sidewalk edge layer under the sidewalk sheets .003
		["Cuberpunk2077.005"] = 0.06, -- second street slab under .004
	}),
	PlainSets = table.freeze({
		Asphalt = table.freeze({ color = Color3.fromRGB(20, 21, 25), material = Enum.Material.SmoothPlastic }),
		Pavement = table.freeze({ color = Color3.fromRGB(92, 95, 102), material = Enum.Material.SmoothPlastic }),
	}),
	InstalledName = "CyberSurface",
	TintBoost = 1.6,
	Sets = table.freeze({
		-- Tower bodies: one floor per tile with a window band and a neon line.
		Facade = table.freeze({ tint = false, pieces = { "Cuberpunk2077.009", "Cuberpunk2077.021", "Cuberpunk2077.022" } }),
		-- Monorail, elevated decks, curbs and light structures.
		Panels = table.freeze({ tint = true, pieces = { "Cuberpunk2077.008", "Cuberpunk2077.007", "Cuberpunk2077.027" } }),
		-- Low-rise houses on the west side.
		Residential = table.freeze({ tint = true, pieces = { "Cuberpunk2077.020", "Cuberpunk2077.025" } }),
		-- Streets: the base slab under the whole city (.004, .005), visible
		-- wherever there is no sidewalk sheet, plus .011 (medians, lamp posts).
		Asphalt = table.freeze({ tint = false, pieces = { "Cuberpunk2077.004", "Cuberpunk2077.005", "Cuberpunk2077.011" } }),
		-- Sidewalks and plazas: the sheets .003 lying on the base slab (checked
		-- in play with a raycast) and the decal layer .002 on them, whose image
		-- never shipped; same grey, so the coplanar pair cannot z-fight.
		Pavement = table.freeze({ tint = false, pieces = { "Cuberpunk2077.003", "Cuberpunk2077.002" } }),
	}),
	-- Images to pick for each template property (from city2059_cyber).
	Maps = table.freeze({ "ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap" }),
	MetallicSets = table.freeze({ Facade = true, Panels = true }),
	-- Uploaded image ids (Toolbox > Inventory > My Images > right click >
	-- Copy Asset ID). 0 = look it up in the Asset Manager by name.
	AssetIds = table.freeze({
		Reality2059Cyber_Facade_Color = 76024859601666,
		Reality2059Cyber_Facade_Normal = 102321904723196,
		Reality2059Cyber_Facade_Roughness = 113404790655204,
		Reality2059Cyber_Facade_Metalness = 93523475415938,
		Reality2059Cyber_Panels_Color = 88416166201545,
		Reality2059Cyber_Panels_Normal = 97481883835890,
		Reality2059Cyber_Panels_Roughness = 78956098142822,
		Reality2059Cyber_Panels_Metalness = 122936617093319,
		Reality2059Cyber_Residential_Color = 103131548074855,
		Reality2059Cyber_Residential_Normal = 74401187957274,
		Reality2059Cyber_Residential_Roughness = 75632492208450,
		Reality2059Cyber_Asphalt_Color = 86105024829402,
		Reality2059Cyber_Asphalt_Normal = 87362309310903,
		Reality2059Cyber_Asphalt_Roughness = 87343669720430,
		Reality2059Cyber_Pavement_Color = 103058282394386,
		Reality2059Cyber_Pavement_Normal = 85794757869050,
		Reality2059Cyber_Pavement_Roughness = 73577358950530,
	}),
})
