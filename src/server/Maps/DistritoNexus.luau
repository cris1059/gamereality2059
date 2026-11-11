--!strict

-- DISTRITO NEXUS (map 1 of 5): greybox for 5 vs 5 team deathmatch.
-- Run once from Studio's Command Bar (edit mode, not during Play):
--   require(game.ServerScriptService.CyberpunkOnlineServer.Maps.DistritoNexus).Build()
-- It builds Workspace.MapWorkshop.DistritoNexus as plain parts; from then on
-- edit it by hand and save the place. Build() never overwrites it; Build(true)
-- starts over from scratch.
--
-- Layout (team A spawns at +Z, team B at -Z, mirrored across Z = 0):
--   left lane   x -140..-80  open street with parked cars (long sightlines)
--   centre      x  -35.. 35  plaza with a raised platform (the hot spot)
--   right lane  x   80..140  roofed arcade with pillars (close quarters)
--   alleys at z = +-60 cut through the buildings between the lanes.

local Blockout = require(script.Parent.Blockout)

local DistritoNexus = {}

local WIDTH, DEPTH = 280, 340
local HALF_W, HALF_D = WIDTH / 2, DEPTH / 2

function DistritoNexus.Build(overwrite: boolean?): Model?
	local model = Blockout.Create("DistritoNexus", overwrite)
	if not model then
		return nil
	end
	model:SetAttribute("MapId", "nexus_grid")
	model:SetAttribute("DisplayName", "DISTRITO NEXUS")
	model:SetAttribute("Mode", "team_deathmatch")
	model:SetAttribute("TeamSize", 5)
	-- Lighting preset (MapsConfig.Maps.DistritoNexus.timeOfDay).
	model:SetAttribute("TimeOfDay", "day")
	local kit = Blockout.new(model, Blockout.WorkshopOrigin)

	-- Floor and outer walls.
	kit:Box("Piso", Vector3.new(WIDTH + 16, 1, DEPTH + 16), Vector3.new(0, -1, 0))
	kit:Pair("Muro", Vector3.new(WIDTH + 16, 30, 4), Vector3.new(0, 0, HALF_D + 6))
	for _, x in { -HALF_W - 6, HALF_W + 6 } do
		kit:Box("Muro", Vector3.new(4, 30, DEPTH + 16), Vector3.new(x, 0, 0))
	end

	-- Buildings between the lanes, split by the alleys at z = +-60 (14 wide).
	for _, x in { -57.5, 57.5 } do
		kit:Box("Edificio", Vector3.new(45, 24, 106), Vector3.new(x, 0, 0))
		kit:Pair("Edificio", Vector3.new(45, 24, 43), Vector3.new(x, 0, 88.5))
	end

	-- CENTRE: raised platform with a ramp on each side, cover around it.
	kit:Box("Plataforma", Vector3.new(28, 4, 28), Vector3.new(0, 0, 0))
	kit:RampPair(Vector3.new(0, 0, 27), Vector3.new(0, 4, 14), 10)
	kit:Box("CoberturaBaja", Vector3.new(2, 1.2, 28), Vector3.new(-13, 4, 0))
	kit:Box("CoberturaBaja", Vector3.new(2, 1.2, 28), Vector3.new(13, 4, 0))
	kit:Pair("CoberturaBaja", Vector3.new(8, 3, 2), Vector3.new(-20, 0, 38))
	kit:Pair("CoberturaBaja", Vector3.new(8, 3, 2), Vector3.new(20, 0, 38))
	kit:Pair("CoberturaBaja", Vector3.new(12, 3, 2), Vector3.new(0, 0, 60))
	kit:Pair("CoberturaAlta", Vector3.new(4, 8, 4), Vector3.new(-25, 0, 82))
	kit:Pair("CoberturaAlta", Vector3.new(4, 8, 4), Vector3.new(25, 0, 82))
	-- Blocks the straight line from one spawn door to the other.
	kit:Pair("CoberturaAlta", Vector3.new(16, 8, 2), Vector3.new(0, 0, 100))

	-- LEFT LANE: street with parked cars and barriers.
	kit:Pair("CoberturaBaja", Vector3.new(5, 4, 11), Vector3.new(-120, 0, 30))
	kit:Pair("CoberturaBaja", Vector3.new(5, 4, 11), Vector3.new(-98, 0, 78), 12)
	kit:Pair("CoberturaBaja", Vector3.new(5, 4, 11), Vector3.new(-127, 0, 104), -8)
	kit:Box("CoberturaBaja", Vector3.new(8, 3, 2), Vector3.new(-96, 0, 0))
	kit:Box("CoberturaBaja", Vector3.new(8, 3, 2), Vector3.new(-126, 0, 0))
	kit:Pair("CoberturaAlta", Vector3.new(3, 8, 3), Vector3.new(-84, 0, 45))

	-- RIGHT LANE: roofed arcade (14 high inside) with pillars and stalls.
	kit:Box("Techo", Vector3.new(60, 1, 140), Vector3.new(110, 14, 0))
	for _, z in { 20, 50 } do
		for _, x in { 92, 128 } do
			kit:Pair("Muro", Vector3.new(3, 14, 3), Vector3.new(x, 0, z))
		end
	end
	kit:Pair("Muro", Vector3.new(2, 14, 30), Vector3.new(110, 0, 32))
	kit:Pair("CoberturaBaja", Vector3.new(6, 3, 4), Vector3.new(100, 0, 6))
	kit:Pair("CoberturaBaja", Vector3.new(6, 3, 4), Vector3.new(122, 0, 66))
	kit:Box("CoberturaAlta", Vector3.new(10, 8, 2), Vector3.new(110, 0, 0))

	-- SPAWN ROOMS: a wall across the map with a door per lane (20 wide).
	for _, span in { { -140, -120 }, { -100, -10 }, { 10, 100 }, { 120, 140 } } do
		local length = span[2] - span[1]
		kit:Pair("Muro", Vector3.new(length, 10, 2), Vector3.new((span[1] + span[2]) / 2, 0, 125))
	end
	for index, x in { -50, -30, -10, 10, 30, 50 } do
		local z = if index % 2 == 0 then 150 else 156
		kit:Spawn("TeamA", Vector3.new(x, 0, z), Vector3.new(0, 0, -1))
		kit:Spawn("TeamB", Vector3.new(x, 0, -z), Vector3.new(0, 0, 1))
	end

	kit:Bounds(Vector3.new(WIDTH, 60, DEPTH))
	print(string.format("[REALITY 2059] DISTRITO NEXUS creado: %d piezas en Workspace.%s.DistritoNexus", kit:Count(), Blockout.WorkshopName))
	return model
end

return DistritoNexus
