--!strict

local MorphLabSceneBuilder = require(script.Parent.Parent.Services.MorphLabSceneBuilder)

local PhaseC1Tests = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

function PhaseC1Tests.run(): { passed: number, total: number }
	local sceneA = MorphLabSceneBuilder.Build()
	local descendantCount = #sceneA:GetDescendants()
	local sceneB = MorphLabSceneBuilder.Build()
	expect(sceneA == sceneB, "Repeated build must return the existing MORPHLAB scene")
	expect(#sceneB:GetDescendants() == descendantCount, "Repeated build must not duplicate instances")
	for _, groupName in ipairs({ "Architecture", "Platform", "Scanner", "Lighting", "Decorations", "Cameras" }) do
		expect(sceneB:FindFirstChild(groupName) ~= nil, "Missing MORPHLAB group: " .. groupName)
	end
	local platform = sceneB:FindFirstChild("Platform")
	expect(platform ~= nil and platform:FindFirstChild("CharacterSpawn") ~= nil, "CharacterSpawn marker is required")
	local cameras = sceneB:FindFirstChild("Cameras")
	expect(cameras ~= nil and cameras:FindFirstChild("CinematicCamera") ~= nil, "Cinematic camera anchor is required")
	return { passed = 4, total = 4 }
end

return PhaseC1Tests
