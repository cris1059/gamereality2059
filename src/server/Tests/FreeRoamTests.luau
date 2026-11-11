--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local MorphLabConfig = require(root.Config.MorphLabConfig)
local FreeRoamConfig = require(root.Config.FreeRoamConfig)
local DayCycle = require(root.World.DayCycle)
local CityData = require(script.Parent.Parent.World.City2059Data)
local CityMaterialConfig = require(script.Parent.Parent.World.CityMaterialConfig)
local FreeRoamService = require(script.Parent.Parent.Services.FreeRoamService)

local FreeRoamTests = {}

local function expect(condition: boolean, message: string)
	if not condition then error("Free roam test failed: " .. message, 2) end
end

local function isReadyMaterialVariant(candidate: Instance?, roleName: string, role): boolean
	if not candidate or not candidate:IsA("MaterialVariant") then
		return false
	end
	return candidate:GetAttribute("Reality2059PBRReady") == true
		and candidate:GetAttribute("Reality2059MaterialRole") == roleName
		and candidate.BaseMaterial == role.baseMaterial
		and math.abs(candidate.StudsPerTile - role.studsPerTile) <= 0.01
end

function FreeRoamTests.run(): { passed: number, total: number }
	local passed = 0

	expect(#CityData.Colliders > 100, "city collision boxes are missing")
	expect(CityData.CollisionVersion >= 5, "city collision data is outdated")
	expect(CityData.CollisionCell <= 0.025, "city collision grid is too coarse")
	for _, box in CityData.Colliders do
		expect(box[4] > 0 and box[5] > 0 and box[6] > 0, "collision box with an empty size")
	end
	expect(#CityData.SurfaceColliders > 100, "walkable surface collision boxes are missing")
	for _, box in CityData.SurfaceColliders do
		expect(box[4] > 0 and box[5] > 0 and box[6] > 0, "surface collision box with an empty size")
	end
	expect(#CityData.Spawns >= 4, "city needs spawn spots")
	expect(CityMaterialConfig.PieceRoles["Cuberpunk2077.003"] == "Asphalt", "road material role is missing")
	expect(CityMaterialConfig.PieceRoles["Cuberpunk2077.005"] == "Concrete", "sidewalk material role is missing")
	expect(CityMaterialConfig.PieceRoles["Cuberpunk2077.007"] == "Metal", "structural metal role is missing")
	expect(CityMaterialConfig.PieceRoles["Cuberpunk2077.009"] == "Facade", "facade material role is missing")
	expect(CityMaterialConfig.PieceRoles["Cuberpunk2077.002"] == nil, "ambiguous alpha group must remain untouched")
	for pieceName, roleName in CityMaterialConfig.PieceRoles do
		expect(CityData.Pieces[pieceName] ~= nil, "material role points at an unknown city piece: " .. pieceName)
		local role = CityMaterialConfig.Roles[roleName]
		expect(role ~= nil and role.studsPerTile > 0, "invalid city material role: " .. roleName)
	end
	-- Day/night clock: round trip, split durations and the frozen hour.
	local cycle = { DaySeconds = 600, NightSeconds = 200, NightStart = 18, NightEnd = 6, FixedClockTime = false }
	for _, hour in { 0, 5.5, 6, 12, 17.9, 18, 23 } do
		expect(math.abs(DayCycle.ClockAt(cycle, DayCycle.ElapsedFor(cycle, hour)) - hour) < 1e-6, "clock round trip failed at " .. hour)
	end
	expect(math.abs(DayCycle.ClockAt(cycle, 300) - 12) < 1e-6 and math.abs(DayCycle.ClockAt(cycle, 700) - 0) < 1e-6, "day and night durations are not honoured")
	expect(DayCycle.IsNight(cycle, 22) and DayCycle.IsNight(cycle, 3) and not DayCycle.IsNight(cycle, 12), "night detection failed")
	expect(DayCycle.ClockAt({ DaySeconds = 1, NightSeconds = 1, NightStart = 18, NightEnd = 6, FixedClockTime = 22 }, 123) == 22, "fixed hour is ignored")
	for _, spot in CityData.Spawns do
		expect(spot.X >= CityData.BoundsMin.X and spot.X <= CityData.BoundsMax.X and spot.Z >= CityData.BoundsMin.Z and spot.Z <= CityData.BoundsMax.Z, "spawn spot outside the city")
	end
	passed += 1

	-- Players spawn as their R15 avatar: the old invisible capsule must be gone.
	local starter = StarterPlayer:FindFirstChild("StarterCharacter")
	expect(starter == nil or not starter:GetAttribute("Reality2059Capsule"), "the old capsule StarterCharacter would replace every avatar")
	expect(type(FreeRoamService.new) == "function", "free roam service is missing")
	passed += 1

	local runtime = Workspace:FindFirstChild(MorphLabConfig.RuntimeFolderName)
	local world = runtime and runtime:FindFirstChild(FreeRoamConfig.ModelName)
	expect(world ~= nil, "free roam world was not built")
	local colliders = (world :: Instance):FindFirstChild("Colliders")
	expect((world :: Instance):FindFirstChild("Ground") ~= nil, "free roam ground is missing")
	local expectedBoxes = if FreeRoamConfig.GeneratedColliders then #CityData.Colliders + #CityData.SurfaceColliders else 0
	expect(colliders ~= nil and #colliders:GetChildren() == expectedBoxes, "generated collision boxes do not match the config")
	expect((world :: Instance):GetAttribute("CityFound") == true, "City2059 was not found in Workspace (import it, any name or folder)")
	expect(#((world :: Instance):FindFirstChild("Spawns") :: Folder):GetChildren() == #CityData.Spawns, "spawn spots were not built")
	if (world :: Instance):GetAttribute("CityFound") then
		local scale = (world :: Instance):GetAttribute("CityScale") :: number
		expect(scale > 0, "city scale must be positive")
		expect(math.abs(scale - FreeRoamConfig.CityScale) < 0.5, "saved city scale drifted from CityScale")
		-- Collision space must match the imported geometry (the importer turns
		-- the city 180 degrees): every mesh centre lands on its part.
		local city = Workspace:FindFirstChild(FreeRoamConfig.CityModelName, true)
		local reference = city and city:FindFirstChild(CityData.ReferenceMesh, true)
		local signs = (world :: Instance):GetAttribute("CityAxisSigns")
		expect(reference ~= nil and typeof(signs) == "Vector3", "city orientation was not measured")
		local worst = 0
		for _, descendant in (city :: Instance):GetDescendants() do
			local center = descendant:IsA("MeshPart") and CityData.MeshCenters[descendant.Name]
			if center then
				local predicted = (reference :: MeshPart).CFrame * ((center - CityData.ReferenceCenter) * scale * (signs :: Vector3))
				worst = math.max(worst, (predicted - descendant.Position).Magnitude)
			end
		end
		expect(worst < 1, string.format("collision space is off the city by %.1f studs", worst))
		-- Per-building dressing: most towers get screens, neon and a sign.
		local dressed = (world :: Instance):GetAttribute("DressedTowers")
		expect(type(dressed) == "number" and dressed >= 20, "city towers were not dressed")
		local screens = 0
		for _, descendant in ((world :: Instance):FindFirstChild("Dressing") :: Instance):GetDescendants() do
			if descendant:IsA("SurfaceGui") then
				screens += 1
			end
		end
		expect(screens >= dressed, "dressed towers are missing their screens")

		local assigned = 0
		for _, descendant in (city :: Instance):GetDescendants() do
			if descendant:IsA("BasePart") then
				local roleName = descendant:GetAttribute("CityMaterialRole")
				if typeof(roleName) == "string" then
					assigned += 1
					local role = CityMaterialConfig.Roles[roleName]
					expect(role ~= nil, "city part has an unknown material role")
					local variant = MaterialService:FindFirstChild(role.variantName, true)
					local materialSource = descendant:GetAttribute("CityMaterialSource")
					if materialSource == "SURFACE_APPEARANCE" then
						expect(descendant:FindFirstChildOfClass("SurfaceAppearance") ~= nil, "SurfaceAppearance source is missing")
					elseif materialSource == "PBR" then
						expect(isReadyMaterialVariant(variant, roleName, role), "PBR source does not have a ready MaterialVariant")
						expect(descendant.MaterialVariant == (variant :: MaterialVariant).Name, "PBR material variant was not assigned")
					else
						expect(materialSource == "BUILTIN_FALLBACK", "city part has an unknown material source")
						expect(descendant.Material == role.fallbackMaterial, "native material fallback was not assigned")
						expect(descendant.MaterialVariant == "", "invalid material variant should not remain assigned")
					end
				end
			end
		end
		expect(assigned >= 10, "too few city mesh groups received material roles")
		expect(((world :: Instance):GetAttribute("PBRMaterialParts") :: number) + ((world :: Instance):GetAttribute("FallbackMaterialParts") :: number) == assigned, "material counters do not match assigned parts")
	end
	passed += 1
	return { passed = passed, total = 3 }
end

return FreeRoamTests
