--!strict

local MorphLabSceneBuilder = require(script.Parent.Parent.Services.MorphLabSceneBuilder)

local PhaseC2Tests = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

function PhaseC2Tests.run(): { passed: number, total: number }
	local scene = MorphLabSceneBuilder.Build()
	local platform = scene:FindFirstChild("Platform")
	local spawn = platform and platform:FindFirstChild("CharacterSpawn")
	expect(spawn ~= nil and spawn:IsA("BasePart"), "C.2 requires a reusable CharacterSpawn anchor")
	expect(spawn:GetAttribute("Purpose") == "UniversalR15Preview", "CharacterSpawn purpose must remain explicit")
	local lighting = scene:FindFirstChild("Lighting")
	expect(lighting ~= nil and lighting:FindFirstChild("AvatarFrontFill") ~= nil, "Avatar front fill light is required")
	expect(lighting ~= nil and lighting:FindFirstChild("AvatarCyanRim") ~= nil, "Avatar cyan rim light is required")
	return { passed = 4, total = 4 }
end

return PhaseC2Tests
