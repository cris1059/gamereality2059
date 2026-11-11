--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local StreetData = require(root.World.City2059Streets)
local CityStreets = require(root.World.CityStreets)
local CityLifeConfig = require(root.Config.CityLifeConfig)
local RandomCharacter = require(root.Character.RandomCharacter)
local CharacterValidator = require(root.Validation.CharacterValidator)

local CityLifeTests = {}

local function expect(condition: boolean, message: string)
	if not condition then error("City life test failed: " .. message, 2) end
end

local function point(entry: { number }, index: number): Vector3
	return Vector3.new(entry[index], entry[index + 1], entry[index + 2])
end

function CityLifeTests.run(): { passed: number, total: number }
	local passed = 0

	-- Generated data: curves join their lanes end to start, every lane has a
	-- way on, light phases name streets that really reach that junction.
	local lanes, connectors = StreetData.Lanes, StreetData.Connectors
	expect(#lanes > 50 and #connectors > 50, "street network is missing")
	local outs = {}
	for index, entry in connectors do
		local from, to = lanes[entry[1]], lanes[entry[2]]
		expect(from ~= nil and to ~= nil and StreetData.Nodes[entry[3]] ~= nil, "connector " .. index .. " references a missing lane or node")
		expect((point(entry, 5) - point(from, #from - 2)).Magnitude < 0.01, "connector " .. index .. " does not start at its lane end")
		expect((point(entry, #entry - 2) - point(to, 5)).Magnitude < 0.01, "connector " .. index .. " does not reach its next lane")
		outs[entry[1]] = true
	end
	local exits = 0
	for index, entry in lanes do
		expect(#entry >= 10, "lane " .. index .. " has fewer than two points")
		if not outs[index] then
			exits += 1
		end
	end
	expect(exits <= #lanes * 0.05, string.format("%d lanes end without a way on", exits))
	-- Flying cars must never reach the end of an air lane with nowhere to go.
	local airOuts = {}
	for _, entry in StreetData.AirConnectors do
		airOuts[entry[1]] = true
	end
	for index in StreetData.AirLanes do
		expect(airOuts[index] == true, "air lane " .. index .. " ends without a way on")
	end
	for nodeIndex, phases in StreetData.Phases do
		for street in phases do
			local reaches = false
			for _, entry in lanes do
				if entry[1] == street and entry[3] == nodeIndex then
					reaches = true
				end
			end
			expect(reaches, "light phase for a street that does not reach node " .. nodeIndex)
		end
	end
	passed += 1

	-- Runtime network (identity transform): sampling and projection.
	local network = CityStreets.build(StreetData, function(p: Vector3): Vector3
		return p
	end, 60)
	local path = network.lanes[1].path
	expect(path.length > 0, "lane path has no length")
	local middle = CityStreets.sample(path, path.length * 0.5)
	expect(math.abs(CityStreets.project(path, middle) - path.length * 0.5) < 1e-3, "project(sample(d)) must return d")
	local first = CityStreets.sample(path, -5)
	expect((first - path.points[1]).Magnitude < 1e-6, "sampling before the start must clamp")
	expect(#network.walkways > 0 and #network.crosswalks > 0, "sidewalks or crosswalks are missing")
	passed += 1

	-- Lights: the two phases of a junction are never green together.
	for nodeIndex, node in network.nodes do
		local phases = node.phases
		if phases then
			local streets = { [1] = nil :: number?, [2] = nil :: number? }
			for street, phase in phases do
				streets[phase] = street
			end
			if streets[1] and streets[2] then
				for clock = 0, 60, 0.5 do
					local a = CityStreets.lightFor(node, streets[1] :: number, clock, CityLifeConfig.Lights)
					local b = CityStreets.lightFor(node, streets[2] :: number, clock, CityLifeConfig.Lights)
					expect(not (a ~= "red" and b ~= "red"), "both phases open at node " .. nodeIndex)
				end
			end
		end
	end
	passed += 1

	-- Pedestrians: random characters are valid and varied.
	local generator = Random.new(2059)
	local bodies, hairs = {}, {}
	for _ = 1, 40 do
		local draft = RandomCharacter.create(generator)
		local valid, problem = CharacterValidator.validate(draft)
		expect(valid, "random character rejected: " .. tostring(problem))
		bodies[draft.appearance.bodyBaseId] = true
		hairs[draft.appearance.hairId] = true
	end
	local hairCount = 0
	for _ in hairs do
		hairCount += 1
	end
	expect(bodies.classic and bodies.slim and hairCount >= 4, "random characters are not varied")
	passed += 1

	return { passed = passed, total = 4 }
end

return CityLifeTests
