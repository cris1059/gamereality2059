--!strict

-- Ambient life for MODO LIBRE: traffic (CityTraffic) and pedestrians
-- (CityPedestrians) on the street network detected from the city's real
-- geometry (World/City2059Streets, built by scripts/build_city2059_streets.py).
-- Local to each client; the network is mapped to the world once with the
-- transform the server publishes on the FreeRoam model.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local FreeRoamConfig = require(root.Config.FreeRoamConfig)
local MorphLabConfig = require(root.Config.MorphLabConfig)
local CityStreets = require(root.World.CityStreets)
local StreetData = require(root.World.City2059Streets)
local CityTraffic = require(script.Parent.CityTraffic)
local CityPedestrians = require(script.Parent.CityPedestrians)

local CityLife = {}
CityLife.__index = CityLife

-- Built once per session (the city does not move during play).
local cachedNetwork: CityStreets.Network? = nil

local function freeRoamModel(): Instance?
	local runtime = Workspace:FindFirstChild(MorphLabConfig.RuntimeFolderName)
	return runtime and runtime:FindFirstChild(FreeRoamConfig.ModelName)
end

-- The asphalt is drawn about 0.4 studs above the ground plane players walk
-- on. Rays from the lane centres check that against the real ground; if the
-- network ended up under it (or floating far above), it is moved back and
-- the numbers are printed so the cause can be found.
local EXPECTED_ROAD_ABOVE_GROUND = 0.37

local function verifyHeight(network: CityStreets.Network, model: Instance)
	local ground = model:FindFirstChild("Ground")
	if not ground or not ground:IsA("BasePart") then
		return
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { ground }
	local deltas = {}
	local stride = math.max(1, #network.lanes // 40)
	for i = 1, #network.lanes, stride do
		local points = network.lanes[i].path.points
		local point = points[math.ceil(#points / 2)]
		local hit = Workspace:Raycast(point + Vector3.new(0, 40, 0), Vector3.new(0, -80, 0), params)
		if hit then
			table.insert(deltas, point.Y - hit.Position.Y)
		end
	end
	if #deltas == 0 then
		return
	end
	table.sort(deltas)
	local median = deltas[(#deltas + 1) // 2]
	if median < -0.05 or median > 3 then
		CityStreets.shift(network, EXPECTED_ROAD_ABOVE_GROUND - median)
		warn(string.format("[REALITY 2059] Calles: la red estaba %.2f studs %s del piso; corregida a +%.2f (%d muestras)",
			math.abs(median), if median < 0 then "por debajo" else "por encima", EXPECTED_ROAD_ABOVE_GROUND, #deltas))
	else
		print(string.format("[REALITY 2059] Calles: altura verificada, asfalto %.2f studs sobre el piso (%d muestras)", median, #deltas))
	end
end

function CityLife.new(morphLabConfig)
	return setmetatable({
		_config = morphLabConfig,
		_active = false,
		_folder = nil :: Folder?,
		_traffic = nil :: any,
		_people = nil :: any,
		_connection = nil :: RBXScriptConnection?,
	}, CityLife)
end

-- density: 0..1 multiplier from the graphics profile.
function CityLife:Start(density: number?)
	if self._active then
		return
	end
	local model = freeRoamModel()
	if not model then
		warn("[REALITY 2059] City life off: the FreeRoam world is missing")
		return
	end
	if not cachedNetwork then
		local toWorld = CityStreets.transformFrom(model)
		if not toWorld then
			warn("[REALITY 2059] City life off: City2059 was not found (no street transform)")
			return
		end
		local studsPerUnit = model:GetAttribute("CityScale")
		cachedNetwork = CityStreets.build(StreetData, toWorld, if type(studsPerUnit) == "number" then studsPerUnit else FreeRoamConfig.CityScale)
		verifyHeight(cachedNetwork :: CityStreets.Network, model)
	end
	local network = cachedNetwork :: CityStreets.Network
	local floorY = model:GetAttribute("FloorY")
	self._active = true
	local folder = Instance.new("Folder")
	folder.Name = "CityLife"
	folder.Parent = Workspace
	self._folder = folder

	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local around = if rootPart and rootPart:IsA("BasePart") then rootPart.Position else network.nodes[1].position
	local traffic = CityTraffic.new(network, if type(floorY) == "number" then floorY else around.Y)
	local people = CityPedestrians.new(network, self._config)
	traffic:SetPedestrianSource(function()
		return people:GetCrossing()
	end)
	people:SetTraffic(traffic)
	traffic:Start(folder, density or 1, around)
	people:Start(folder, density or 1, around)
	self._traffic = traffic
	self._people = people
	local statsTimer = 0
	self._connection = RunService.Heartbeat:Connect(function(deltaTime)
		traffic:Update(deltaTime)
		people:Update(deltaTime)
		-- Live counts for the F3 panel.
		statsTimer += deltaTime
		if statsTimer >= 1 then
			statsTimer = 0
			local stats = self:GetStats()
			folder:SetAttribute("Cars", stats.cars)
			folder:SetAttribute("Flying", stats.flying)
			folder:SetAttribute("People", stats.people)
		end
	end)
end

function CityLife:Stop()
	self._active = false
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self._traffic then
		self._traffic:Stop()
		self._traffic = nil
	end
	if self._people then
		self._people:Stop()
		self._people = nil
	end
	if self._folder then
		self._folder:Destroy()
		self._folder = nil
	end
end

-- Debug summary (F3 panel, tests).
function CityLife:GetStats(): { [string]: number }
	local ground, flying = 0, 0
	if self._traffic then
		ground, flying = self._traffic:Count()
	end
	return {
		cars = ground,
		flying = flying,
		people = if self._people then self._people:Count() else 0,
	}
end

return CityLife
