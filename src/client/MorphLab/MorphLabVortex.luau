--!strict

-- The sky vortex behind MORPHLAB: a dark core inside a bright event-horizon
-- ring, three tilted accretion rings turning at different speeds, spiral
-- arms, orbiting debris and the odd lightning flash. Client-only, built while
-- MORPHLAB is open; everything faces the cinematic camera. Neon parts stay
-- partly transparent so the vortex never glares.

local RunService = game:GetService("RunService")

local MorphLabVortex = {}
MorphLabVortex.__index = MorphLabVortex

local CORE = Color3.fromRGB(6, 2, 14)
local PURPLE = Color3.fromRGB(168, 92, 255)
local MAGENTA = Color3.fromRGB(255, 60, 200)
local CYAN = Color3.fromRGB(80, 220, 255)
local HORIZON = Color3.fromRGB(235, 215, 255)
local ROCK = Color3.fromRGB(24, 20, 34)

local BOLT_SEGMENTS = 6
local BOLT_TIME = 0.12

local function piece(parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, transparency: number): Part
	local item = Instance.new("Part")
	item.Anchored = true
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material
	item.Transparency = transparency
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

-- Segment from a to b (local XY plane, z toward the camera).
local function segmentFrame(a: Vector3, b: Vector3): (CFrame, number)
	return CFrame.lookAt((a + b) * 0.5, b, Vector3.zAxis), (b - a).Magnitude
end

function MorphLabVortex.new(settings)
	return setmetatable({
		_settings = settings,
		_model = nil :: Model?,
		_frame = CFrame.new(),
		_radius = 1,
		_layers = {} :: { any },
		_bolts = {} :: { { Part } },
		_boltTimer = 1,
		_boltLeft = 0,
		_activeBolt = nil :: { Part }?,
		_connection = nil :: RBXScriptConnection?,
		_moving = {} :: { BasePart },
		_offsets = {} :: { CFrame },
		_owners = {} :: { any },
		_targets = {} :: { CFrame },
	}, MorphLabVortex)
end

-- A layer turns about the axis facing the camera; `tilt` leans it in depth.
function MorphLabVortex:_layer(name: string, speed: number, tiltDegrees: number): (Model, CFrame)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = self._model
	local base = self._frame * CFrame.Angles(math.rad(tiltDegrees), 0, 0)
	table.insert(self._layers, { model = model, base = base, frame = base, speed = speed, angle = 0 })
	return model, base
end

-- Dashed ring of tangent neon segments; every `skip`-th segment is left out.
function MorphLabVortex:_ring(name: string, radius: number, segments: number, thickness: number, color: Color3, transparency: number, speed: number, tilt: number, skip: number?)
	local model, base = self:_layer(name, speed, tilt)
	for index = 1, segments do
		if not skip or index % skip ~= 0 then
			local a0 = (index - 1) / segments * 2 * math.pi
			local a1 = index / segments * 2 * math.pi
			local frame, length = segmentFrame(Vector3.new(math.cos(a0), math.sin(a0), 0) * radius, Vector3.new(math.cos(a1), math.sin(a1), 0) * radius)
			piece(model, Vector3.new(thickness, thickness, length * 1.06), base * frame, color, Enum.Material.Neon, transparency)
		end
	end
	model.WorldPivot = base
end

function MorphLabVortex:Attach(parent: Instance, view: CFrame)
	self:Detach()
	local settings = self._settings
	local direction = (view * CFrame.Angles(0, math.rad(settings.YawDegrees), 0) * CFrame.Angles(math.rad(settings.PitchDegrees), 0, 0)).LookVector
	local center = view.Position + direction * settings.Distance
	local r = settings.Distance * math.tan(math.rad(settings.RadiusDegrees))
	self._radius = r
	self._frame = CFrame.lookAt(center, view.Position)
	local model = Instance.new("Model")
	model.Name = "MorphLabVortex"
	self._model = model

	-- Static backdrop: violet haze discs and the black core.
	local static = Instance.new("Model")
	static.Name = "Backdrop"
	static.Parent = model
	local facing = self._frame * CFrame.Angles(0, math.rad(90), 0)
	for _, entry in { { 3.4, -6, 0.93, PURPLE }, { 2.2, -4, 0.86, MAGENTA }, { 1.3, -2, 0.8, PURPLE } } do
		local disc = piece(static, Vector3.new(0.5, r * entry[1], r * entry[1]), facing * CFrame.new(entry[2], 0, 0), entry[4], Enum.Material.Neon, entry[3])
		disc.Shape = Enum.PartType.Cylinder
	end
	local core = piece(static, Vector3.new(0.6, r * 0.72, r * 0.72), facing * CFrame.new(1, 0, 0), CORE, Enum.Material.SmoothPlastic, 0)
	core.Shape = Enum.PartType.Cylinder

	-- Event horizon, accretion rings (alternating directions) and spiral arms.
	self:_ring("Horizon", r * 0.37, 30, r * 0.045, HORIZON, 0.25, 1.3, 0)
	self:_ring("RingInner", r * 0.56, 30, r * 0.07, MAGENTA, 0.3, 0.7, 12, 4)
	self:_ring("RingMiddle", r * 0.8, 36, r * 0.055, PURPLE, 0.32, -0.42, -9, 5)
	self:_ring("RingOuter", r * 1.02, 44, r * 0.032, CYAN, 0.4, 0.26, 6, 3)
	local arms, armBase = self:_layer("SpiralArms", 0.45, 0)
	for arm = 0, 3 do
		local previous: Vector3? = nil
		for step = 0, 12 do
			local radius = r * (0.4 + step * 0.09)
			local angle = arm * math.pi / 2 + 2.3 * math.log(radius / (r * 0.4))
			local point = Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, r * 0.02)
			if previous then
				local frame, length = segmentFrame(previous, point)
				local fade = step / 12
				local thickness = r * (0.065 - 0.045 * fade)
				piece(arms, Vector3.new(thickness, thickness, length * 1.1), armBase * frame, if fade < 0.5 then MAGENTA else PURPLE, Enum.Material.Neon, 0.3 + 0.55 * fade)
			end
			previous = point
		end
	end
	arms.WorldPivot = armBase

	-- Debris in a slow orbit around the rift.
	local debris, debrisBase = self:_layer("Debris", 0.05, 0)
	local random = Random.new(2059)
	for _ = 1, 16 do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = r * random:NextNumber(1.25, 2)
		local size = r * random:NextNumber(0.05, 0.14)
		local position = Vector3.new(math.cos(angle) * distance, math.sin(angle) * distance, r * random:NextNumber(-0.3, 0.3))
		piece(debris, Vector3.new(size, size * 0.7, size * 1.2), debrisBase * CFrame.new(position) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0), ROCK, Enum.Material.Slate, 0)
	end
	debris.WorldPivot = debrisBase

	-- Lightning: hidden jagged bolts, re-shaped and flashed now and then.
	local bolts = Instance.new("Folder")
	bolts.Name = "Lightning"
	bolts.Parent = model
	self._bolts = {}
	for _ = 1, 3 do
		local bolt = {}
		for _ = 1, BOLT_SEGMENTS do
			table.insert(bolt, piece(bolts, Vector3.new(r * 0.025, r * 0.025, 1), self._frame, HORIZON, Enum.Material.Neon, 1))
		end
		table.insert(self._bolts, bolt)
	end
	self._boltTimer = 1

	-- Each moving part keeps its offset from its layer's base; every frame the
	-- whole set moves in one BulkMoveTo (far cheaper than PivotTo per layer).
	self._moving = {}
	self._offsets = {}
	self._owners = {}
	for _, layer in self._layers do
		for _, child in layer.model:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(self._moving, child)
				table.insert(self._offsets, layer.base:ToObjectSpace(child.CFrame))
				table.insert(self._owners, layer)
			end
		end
	end
	self._targets = table.create(#self._moving)
	model.Parent = parent
	self._connection = RunService.RenderStepped:Connect(function(deltaTime)
		self:_step(deltaTime)
	end)
end

function MorphLabVortex:_flash(bolt: { Part })
	local r = self._radius
	local angle = math.random() * 2 * math.pi
	local outward = Vector3.new(math.cos(angle), math.sin(angle), 0)
	local side = Vector3.new(-outward.Y, outward.X, 0)
	local point = outward * r * 0.95
	for index, segment in bolt do
		local nextPoint = outward * r * (0.95 + index * 0.13) + side * r * (math.random() - 0.5) * 0.22 + Vector3.new(0, 0, r * 0.05)
		local frame, length = segmentFrame(point, nextPoint)
		segment.Size = Vector3.new(segment.Size.X, segment.Size.Y, length)
		segment.CFrame = self._frame * frame
		segment.Transparency = 0.15
		point = nextPoint
	end
end

function MorphLabVortex:_step(deltaTime: number)
	for _, layer in self._layers do
		layer.angle += layer.speed * deltaTime
		layer.frame = layer.base * CFrame.Angles(0, 0, layer.angle)
	end
	local targets = self._targets
	for index, offset in self._offsets do
		targets[index] = self._owners[index].frame * offset
	end
	if #self._moving > 0 then
		workspace:BulkMoveTo(self._moving, targets, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if self._activeBolt then
		self._boltLeft -= deltaTime
		if self._boltLeft <= 0 then
			for _, segment in self._activeBolt do
				segment.Transparency = 1
			end
			self._activeBolt = nil
		end
	else
		self._boltTimer -= deltaTime
		if self._boltTimer <= 0 and #self._bolts > 0 then
			self._boltTimer = 0.8 + math.random() * 2.2
			local bolt = self._bolts[math.random(1, #self._bolts)]
			self:_flash(bolt)
			self._activeBolt = bolt
			self._boltLeft = BOLT_TIME
		end
	end
end

function MorphLabVortex:Detach()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	table.clear(self._layers)
	self._moving = {}
	self._offsets = {}
	self._owners = {}
	self._targets = {}
	self._bolts = {}
	self._activeBolt = nil
end

return MorphLabVortex
