--!strict

local MorphLabSceneBuilder = require(script.Parent.Parent.Services.MorphLabSceneBuilder)

local MorphLabVariantTests = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error("MorphLab variant test failed: " .. message, 2)
	end
end

function MorphLabVariantTests.run(): { passed: number, total: number }
	local checks = 0
	local function check(condition: boolean, message: string)
		expect(condition, message)
		checks += 1
	end
	check(MorphLabSceneBuilder.IsVariantSupported("NEO_EDEN_ROOFTOP"), "the rooftop is the MORPHLAB environment")
	check(not MorphLabSceneBuilder.IsVariantSupported("CORPORATE_LAB"), "the old laboratory must be gone")

	local scene = MorphLabSceneBuilder.Build()
	check(scene:GetAttribute("EnvironmentVariant") == "NEO_EDEN_ROOFTOP", "scene must be the rooftop")
	local architecture = scene:FindFirstChild("Architecture")
	check(architecture ~= nil and architecture:FindFirstChild("RailTop") ~= nil, "side railings are required")
	check(architecture ~= nil and architecture:FindFirstChild("Ceiling") == nil, "the rooftop must be open to the sky")
	local platform = scene:FindFirstChild("Platform")
	for _, name in { "OuterEnergyRing", "CoreEnergyRing" } do
		check(platform ~= nil and platform:FindFirstChild(name) ~= nil, "class-tinted ring missing: " .. name)
	end
	-- Moderate lighting: strong spot lights made skin and hair glare.
	for _, descendant in scene:GetDescendants() do
		if descendant:IsA("Light") then
			check(descendant.Brightness <= 2, "MORPHLAB light too bright: " .. descendant:GetFullName())
		end
	end
	local decorations = scene:FindFirstChild("Decorations")
	check(decorations ~= nil and decorations:FindFirstChild("IdentityBillboard") == nil, "the billboard was removed")
	return { passed = checks, total = checks }
end

return MorphLabVariantTests
