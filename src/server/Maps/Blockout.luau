--!strict

-- Greybox kit for multiplayer maps. Every piece is a plain anchored Part,
-- colour-coded by what it is for, so a map can be built quickly by code and
-- then reshaped by hand in Studio. Sizes are studs; the R15 avatar is about
-- 5.2 studs tall.
--   grey      floors, walls, buildings
--   yellow    low cover (3-4 studs: covers you crouched)
--   orange    high cover (7-8 studs: covers you standing)
--   blue      ramps
--   cyan      team A spawn / magenta team B spawn
-- Pieces are named in Spanish so they read well in the Explorer.

local Blockout = {}
Blockout.__index = Blockout

local KINDS = table.freeze({
	Piso = { color = Color3.fromRGB(96, 98, 106), material = Enum.Material.Concrete },
	Muro = { color = Color3.fromRGB(62, 64, 74), material = Enum.Material.SmoothPlastic },
	Edificio = { color = Color3.fromRGB(50, 52, 62), material = Enum.Material.Concrete },
	Techo = { color = Color3.fromRGB(58, 60, 70), material = Enum.Material.SmoothPlastic },
	Plataforma = { color = Color3.fromRGB(112, 112, 126), material = Enum.Material.DiamondPlate },
	CoberturaBaja = { color = Color3.fromRGB(230, 182, 40), material = Enum.Material.SmoothPlastic },
	CoberturaAlta = { color = Color3.fromRGB(232, 112, 32), material = Enum.Material.SmoothPlastic },
	Rampa = { color = Color3.fromRGB(70, 140, 232), material = Enum.Material.SmoothPlastic },
	SpawnA = { color = Color3.fromRGB(0, 200, 255), material = Enum.Material.SmoothPlastic },
	SpawnB = { color = Color3.fromRGB(255, 60, 170), material = Enum.Material.SmoothPlastic },
})
Blockout.Kinds = KINDS

-- model: the map Model (already parented); origin: centre of the floor.
function Blockout.new(model: Model, origin: Vector3)
	local folders = {}
	for _, name in { "Geometry", "Spawns", "Bounds" } do
		local folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = model
		folders[name] = folder
	end
	for _, team in { "TeamA", "TeamB" } do
		local folder = Instance.new("Folder")
		folder.Name = team
		folder.Parent = folders.Spawns
		folders[team] = folder
	end
	return setmetatable({ _model = model, _origin = origin, _folders = folders, _count = 0 }, Blockout)
end

function Blockout:_part(kind: string, size: Vector3, cframe: CFrame, parent: Instance?): Part
	local style = KINDS[kind]
	local part = Instance.new("Part")
	part.Name = kind
	part.Anchored = true
	part.Size = size
	part.CFrame = CFrame.new(self._origin) * cframe
	part.Color = style.color
	part.Material = style.material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("Blockout", kind)
	part.Parent = parent or self._folders.Geometry
	self._count += 1
	return part
end

-- A box standing on the floor: position is the centre of its base.
function Blockout:Box(kind: string, size: Vector3, base: Vector3, yawDegrees: number?): Part
	return self:_part(kind, size, CFrame.new(base + Vector3.new(0, size.Y / 2, 0)) * CFrame.Angles(0, math.rad(yawDegrees or 0), 0))
end

-- Same box and its mirror across the map's middle line (z -> -z), so both
-- teams get the same layout.
function Blockout:Pair(kind: string, size: Vector3, base: Vector3, yawDegrees: number?)
	self:Box(kind, size, base, yawDegrees)
	if math.abs(base.Z) > 1e-3 then
		self:Box(kind, size, Vector3.new(base.X, base.Y, -base.Z), -(yawDegrees or 0))
	end
end

-- A walkable slope from `low` (on its floor) up to `high` (top of what it
-- climbs), `width` studs wide. Keep it under ~35 degrees.
function Blockout:Ramp(low: Vector3, high: Vector3, width: number): Part
	local run = high - low
	local length = run.Magnitude
	local center = (low + high) / 2
	local frame = CFrame.lookAt(center, high)
	-- The slab's top surface runs through the two points.
	return self:_part("Rampa", Vector3.new(width, 1, length + 0.6), frame * CFrame.new(0, -0.5, 0))
end

function Blockout:RampPair(low: Vector3, high: Vector3, width: number)
	self:Ramp(low, high, width)
	self:Ramp(Vector3.new(low.X, low.Y, -low.Z), Vector3.new(high.X, high.Y, -high.Z), width)
end

-- Spawn point for a team: a 4x4 pad (half see-through while editing; the
-- match makes it invisible). Players appear standing on it, facing `facing`.
function Blockout:Spawn(team: "TeamA" | "TeamB", position: Vector3, facing: Vector3)
	local folder = self._folders[team]
	local look = Vector3.new(facing.X, 0, facing.Z).Unit
	local part = self:_part(if team == "TeamA" then "SpawnA" else "SpawnB", Vector3.new(4, 0.4, 4), CFrame.lookAt(position + Vector3.new(0, 0.2, 0), position + Vector3.new(0, 0.2, 0) + look), folder)
	part.Name = string.format("Spawn%d", #folder:GetChildren())
	part.Transparency = 0.5
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
end

-- Invisible box with the playable area (out-of-bounds checks use it).
function Blockout:Bounds(size: Vector3)
	local part = Instance.new("Part")
	part.Name = "PlayArea"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = size
	part.CFrame = CFrame.new(self._origin + Vector3.new(0, size.Y / 2, 0))
	part.Parent = self._folders.Bounds
end

function Blockout:Count(): number
	return self._count
end

-- Where blockouts are built for editing (Workspace, beyond the city's
-- ground and above its floor, so free roam's fall check never fires there).
Blockout.WorkshopName = "MapWorkshop"
Blockout.WorkshopOrigin = Vector3.new(0, 40, 2500)

-- Creates the workshop model `name`, or returns nil if one already exists
-- (so hand edits are never overwritten).
function Blockout.Create(name: string, overwrite: boolean?): Model?
	local Workspace = game:GetService("Workspace")
	local workshop = Workspace:FindFirstChild(Blockout.WorkshopName)
	if not workshop then
		workshop = Instance.new("Folder")
		workshop.Name = Blockout.WorkshopName
		workshop.Parent = Workspace
	end
	local existing = workshop:FindFirstChild(name)
	if existing then
		if not overwrite then
			warn(string.format("[REALITY 2059] %s ya existe en Workspace.%s: no se reconstruye (tus cambios se conservan). Usa Build(true) para empezar de cero.", name, Blockout.WorkshopName))
			return nil
		end
		existing:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = workshop
	return model
end

return Blockout
