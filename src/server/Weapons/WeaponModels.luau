--!strict

-- Quick original weapon models built from Parts (greybox quality, cyberpunk
-- palette): the VK-7 assault rifle and the Pm-8 pistol. Both prefer their
-- imported Blender models when present (see MeshSpec). The server builds them
-- into ServerStorage.Weapons on every start, so changing this file changes
-- the weapons with no Command Bar step; they replace only their own Tools
-- (marked "Procedural") and never touch imported weapons.
--
-- Every piece is laid out in grip space: origin at the shooting hand, -Z
-- along the barrel, +Y up, +X to the right. The Tool's Grip is that frame,
-- which is what ShooterAnimation and CombatController expect (the barrel
-- along the grip's LookVector, the muzzle its furthest point forward).

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local WeaponConfig = require(root.Config.WeaponConfig)

local WeaponModels = {}

local BODY = Color3.fromRGB(26, 28, 36)
local TRIM = Color3.fromRGB(58, 62, 76)
local GRIP = Color3.fromRGB(16, 17, 22)
local CYAN = Color3.fromRGB(0, 220, 255)
local MAGENTA = Color3.fromRGB(255, 40, 170)

type Piece = {
	name: string,
	size: Vector3,
	at: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?,
	handle: boolean?,
}

-- A Blender model imported into ServerStorage with Studio's 3D Importer. Its
-- MeshParts are named <prefix>_*: <prefix>_Cuerpo (the textured body, which
-- becomes the Handle), <prefix>_Neon* (glowing strips), <prefix>_Lente, and
-- three small markers that place the hand whatever axes the importer used:
-- <prefix>_Grip (the hand), <prefix>_Boca (the muzzle) and <prefix>_Arriba
-- (straight above the hand).
type MeshSpec = {
	prefix: string,
	length: number, -- studs from stock to muzzle
}

type Spec = {
	toolName: string,
	displayName: string,
	class: string,
	pieces: { Piece },
	mesh: MeshSpec?,
}

local function p(name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?): Piece
	return { name = name, size = size, at = at, color = color, material = material }
end

-- Cylinder along the barrel (a Roblox cylinder's axis is its X).
local function tube(name: string, length: number, diameter: number, at: Vector3, color: Color3, material: Enum.Material?): Piece
	return {
		name = name,
		size = Vector3.new(length, diameter, diameter),
		at = CFrame.new(at) * CFrame.Angles(0, math.rad(90), 0),
		color = color,
		material = material,
		shape = Enum.PartType.Cylinder,
	}
end

local function tilt(position: Vector3, degrees: number): CFrame
	return CFrame.new(position) * CFrame.Angles(math.rad(degrees), 0, 0)
end

local METAL = Enum.Material.Metal
local PLASTIC = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon

-- VK-7: bullpup-free assault rifle, ~3.9 studs from stock to muzzle. Uses
-- the Blender model (src/assets/weapons/vk7/VK7_Modelo.glb) when it has been
-- imported into ServerStorage; these Parts are the fallback.
local RIFLE: Spec = {
	toolName = "R2059 Rifle VK-7",
	displayName = "FUSIL VK-7",
	class = "rifle",
	mesh = { prefix = "VK7", length = 3.9 },
	pieces = {
		{ name = "Receiver", size = Vector3.new(0.28, 0.4, 1.3), at = CFrame.new(0, 0.28, -0.35), color = BODY, material = METAL, handle = true },
		p("TopRail", Vector3.new(0.16, 0.07, 1.15), CFrame.new(0, 0.515, -0.4), TRIM, METAL),
		p("Handguard", Vector3.new(0.26, 0.3, 0.9), CFrame.new(0, 0.29, -1.45), TRIM, PLASTIC),
		p("HandguardBottom", Vector3.new(0.2, 0.08, 0.8), CFrame.new(0, 0.1, -1.45), BODY, METAL),
		tube("Barrel", 0.7, 0.12, Vector3.new(0, 0.32, -2.2), BODY, METAL),
		p("Muzzle", Vector3.new(0.18, 0.18, 0.22), CFrame.new(0, 0.32, -2.62), TRIM, METAL),
		p("Grip", Vector3.new(0.18, 0.44, 0.22), tilt(Vector3.new(0, -0.06, 0.04), -14), GRIP, PLASTIC),
		p("TriggerGuard", Vector3.new(0.05, 0.05, 0.32), CFrame.new(0, 0.04, -0.2), TRIM, METAL),
		p("Magazine", Vector3.new(0.16, 0.52, 0.26), tilt(Vector3.new(0, -0.1, -0.58), 10), GRIP, PLASTIC),
		p("Stock", Vector3.new(0.2, 0.32, 0.8), CFrame.new(0, 0.22, 0.75), BODY, PLASTIC),
		p("Buttpad", Vector3.new(0.22, 0.46, 0.1), CFrame.new(0, 0.17, 1.17), GRIP, PLASTIC),
		tube("Scope", 0.62, 0.18, Vector3.new(0, 0.7, -0.38), BODY, METAL),
		p("ScopeMountFront", Vector3.new(0.08, 0.14, 0.08), CFrame.new(0, 0.6, -0.6), TRIM, METAL),
		p("ScopeMountRear", Vector3.new(0.08, 0.14, 0.08), CFrame.new(0, 0.6, -0.16), TRIM, METAL),
		p("ScopeLens", Vector3.new(0.13, 0.13, 0.02), CFrame.new(0, 0.7, -0.7), CYAN, NEON),
		p("NeonLeft", Vector3.new(0.02, 0.04, 0.95), CFrame.new(-0.15, 0.3, -0.35), CYAN, NEON),
		p("NeonRight", Vector3.new(0.02, 0.04, 0.95), CFrame.new(0.15, 0.3, -0.35), CYAN, NEON),
		p("NeonGuardLeft", Vector3.new(0.02, 0.04, 0.6), CFrame.new(-0.14, 0.3, -1.45), CYAN, NEON),
		p("NeonGuardRight", Vector3.new(0.02, 0.04, 0.6), CFrame.new(0.14, 0.3, -1.45), CYAN, NEON),
	},
}

-- Pm-8 (formerly P-9): cyberpunk sidearm, ~1.1 studs long. Uses the Blender
-- model (src/assets/weapons/pm8/PM8_Modelo.glb; source Modelos/Pm-8) when it
-- has been imported into ServerStorage; these Parts are the fallback. Its
-- slide (PM8_Palanca) racks back on reload, carrying its red LED strips and
-- holographic ammo counter (PM8_PalancaNeon / PM8_PalancaHolo).
local PISTOL: Spec = {
	toolName = "R2059 Pistola Pm-8",
	displayName = "PISTOLA PM-8",
	class = "pistol",
	mesh = { prefix = "PM8", length = 1.1 },
	pieces = {
		{ name = "Slide", size = Vector3.new(0.16, 0.2, 0.95), at = CFrame.new(0, 0.3, -0.36), color = BODY, material = METAL, handle = true },
		p("Frame", Vector3.new(0.15, 0.12, 0.72), CFrame.new(0, 0.15, -0.3), TRIM, METAL),
		p("Grip", Vector3.new(0.15, 0.46, 0.22), tilt(Vector3.new(0, -0.08, 0.06), -12), GRIP, PLASTIC),
		p("TriggerGuard", Vector3.new(0.04, 0.04, 0.24), CFrame.new(0, 0.04, -0.2), TRIM, METAL),
		tube("Barrel", 0.08, 0.08, Vector3.new(0, 0.3, -0.87), TRIM, METAL),
		p("RearSight", Vector3.new(0.1, 0.05, 0.04), CFrame.new(0, 0.425, 0.08), MAGENTA, NEON),
		p("FrontSight", Vector3.new(0.03, 0.05, 0.04), CFrame.new(0, 0.425, -0.78), MAGENTA, NEON),
		p("NeonLeft", Vector3.new(0.02, 0.03, 0.7), CFrame.new(-0.085, 0.32, -0.38), MAGENTA, NEON),
		p("NeonRight", Vector3.new(0.02, 0.03, 0.7), CFrame.new(0.085, 0.32, -0.38), MAGENTA, NEON),
	},
}

WeaponModels.Specs = table.freeze({ RIFLE, PISTOL })

local function build(spec: Spec): Tool
	local tool = Instance.new("Tool")
	tool.Name = spec.toolName
	tool.ToolTip = spec.displayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("DisplayName", spec.displayName)
	tool:SetAttribute("WeaponClass", spec.class)
	tool:SetAttribute("Procedural", true)
	local handle: BasePart? = nil
	local handleAt = CFrame.identity
	local parts = {}
	for _, piece in spec.pieces do
		local part = Instance.new("Part")
		part.Name = if piece.handle then "Handle" else piece.name
		part.Size = piece.size
		part.CFrame = piece.at
		part.Color = piece.color
		part.Material = piece.material or Enum.Material.SmoothPlastic
		if piece.shape then
			part.Shape = piece.shape
		end
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = piece.material ~= NEON
		part.Massless = true
		part.Parent = tool
		table.insert(parts, part)
		if piece.handle then
			handle = part
			handleAt = piece.at
		end
	end
	assert(handle, spec.toolName .. " has no handle piece")
	for _, part in parts do
		if part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		end
	end
	-- Handle = gripFrame * Grip^-1, and the grip frame is the origin here.
	tool.Grip = handleAt:Inverse()
	return tool
end

local MESH_COLORS: { [string]: Color3 } = {
	NeonCian = CYAN,
	NeonMagenta = MAGENTA,
	NeonVioleta = Color3.fromRGB(120, 60, 255),
	Lente = MAGENTA,
	CargadorNeon = MAGENTA,
	PalancaNeon = Color3.fromRGB(255, 30, 55),
	PalancaHolo = Color3.fromRGB(255, 70, 70),
}
-- Glowing pieces drawn see-through (holograms).
local MESH_TRANSPARENCY: { [string]: number } = {
	PalancaHolo = 0.35,
}

-- Parts the reload animation moves (ReloadAnimation on the client): joined to
-- the body with a Motor6D of this name instead of a weld.
local MOVING_JOINTS: { [string]: string } = {
	Cargador = "MagJoint",
	Palanca = "BoltJoint",
}

local function markerNames(prefix: string): { string }
	return { prefix .. "_Grip", prefix .. "_Boca", prefix .. "_Arriba" }
end

local function holdsMarkers(instance: Instance, prefix: string): boolean
	for _, name in markerNames(prefix) do
		if not instance:FindFirstChild(name, true) then
			return false
		end
	end
	return true
end

-- The imported model in ServerStorage: the smallest ancestor of <prefix>_Cuerpo
-- that also holds the three markers (never a built Tool).
local function findMeshTemplate(prefix: string): Instance?
	for _, descendant in ServerStorage:GetDescendants() do
		if descendant.Name == prefix .. "_Cuerpo" and descendant:IsA("BasePart") then
			local node: Instance? = descendant.Parent
			while node and node ~= ServerStorage do
				if node:IsA("Tool") then
					break
				end
				if holdsMarkers(node, prefix) then
					return node
				end
				node = node.Parent
			end
		end
	end
	return nil
end

local function newTool(spec: Spec): Tool
	local tool = Instance.new("Tool")
	tool.Name = spec.toolName
	tool.ToolTip = spec.displayName
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("DisplayName", spec.displayName)
	tool:SetAttribute("WeaponClass", spec.class)
	tool:SetAttribute("Procedural", true)
	return tool
end

local function loosen(part: BasePart)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
end

-- Tool from the imported Blender model, or nil (with a warning) if the model
-- is missing or incomplete.
local function buildFromMesh(spec: Spec, mesh: MeshSpec): Tool?
	local template = findMeshTemplate(mesh.prefix)
	if not template then
		return nil
	end
	local holder = Instance.new("Model")
	local parts: { BasePart } = {}
	local copy = template:Clone()
	if copy:IsA("BasePart") then
		table.insert(parts, copy)
	end
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	for _, part in parts do
		part.Parent = holder
	end
	if not copy:IsA("BasePart") then
		copy:Destroy()
	end
	local function piece(suffix: string): BasePart?
		local found = holder:FindFirstChild(mesh.prefix .. "_" .. suffix)
		return if found and found:IsA("BasePart") then found else nil
	end
	local maybeBody, maybeGrip, maybeMuzzle, maybeAbove = piece("Cuerpo"), piece("Grip"), piece("Boca"), piece("Arriba")
	if not (maybeBody and maybeGrip and maybeMuzzle and maybeAbove) then
		warn("[REALITY 2059] " .. spec.toolName .. ": modelo importado incompleto; se usa el de bloques")
		holder:Destroy()
		return nil
	end
	local body = maybeBody :: BasePart
	local grip = maybeGrip :: BasePart
	local muzzle = maybeMuzzle :: BasePart
	local above = maybeAbove :: BasePart
	-- Whatever units the importer used, scale to the design length.
	local extents = holder:GetExtentsSize()
	local longest = math.max(extents.X, extents.Y, extents.Z)
	if longest > 0 then
		holder:ScaleTo(holder:GetScale() * mesh.length / longest)
	end
	local origin = grip.Position
	local up = (above.Position - origin).Unit
	local forward = muzzle.Position - origin
	forward = (forward - up * forward:Dot(up)).Unit
	local gripFrame = CFrame.lookAt(origin, origin + forward, up)
	grip:Destroy()
	muzzle:Destroy()
	above:Destroy()

	local tool = newTool(spec)
	tool:SetAttribute("MeshModel", template:GetFullName())
	body.Name = "Handle"
	if not body:FindFirstChildWhichIsA("SurfaceAppearance") then
		warn("[REALITY 2059] " .. spec.toolName .. ": el cuerpo no trae SurfaceAppearance (texturas); revisa la importación")
	end
	-- The magazine's neon strip rides on the magazine, and the slide's lights
	-- on the slide (Palanca*).
	local magazine = holder:FindFirstChild(mesh.prefix .. "_Cargador")
	local slide = holder:FindFirstChild(mesh.prefix .. "_Palanca")
	for _, part in holder:GetChildren() do
		if not part:IsA("BasePart") then
			continue
		end
		loosen(part)
		local role = string.sub(part.Name, #mesh.prefix + 2)
		local color = MESH_COLORS[role]
		if color then
			for _, appearance in part:GetChildren() do
				if appearance:IsA("SurfaceAppearance") then
					appearance:Destroy()
				end
			end
			part.Color = color
			if role == "Lente" then
				part.Material = Enum.Material.Glass
				part.Transparency = 0.45
			else
				part.Material = NEON
				part.Transparency = MESH_TRANSPARENCY[role] or 0
			end
			part.CastShadow = false
		elseif part ~= body then
			part.Material = METAL
		end
		part.Parent = tool
		local jointName = MOVING_JOINTS[role]
		if jointName then
			local motor = Instance.new("Motor6D")
			motor.Name = jointName
			motor.Part0 = body
			motor.Part1 = part
			motor.C0 = body.CFrame:ToObjectSpace(part.CFrame)
			motor.C1 = CFrame.identity
			motor.Parent = part
		elseif part ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = if role == "CargadorNeon" and magazine and magazine:IsA("BasePart") then magazine
				elseif string.sub(role, 1, 7) == "Palanca" and slide and slide:IsA("BasePart") then slide
				else body
			weld.Part1 = part
			weld.Parent = part
		end
	end
	body.Material = METAL
	tool.Grip = body.CFrame:ToObjectSpace(gripFrame)
	holder:Destroy()
	return tool
end

-- Builds (or rebuilds) the procedural weapons into ServerStorage.Weapons.
-- Returns the Tool names.
function WeaponModels.Install(): { string }
	local folder = ServerStorage:FindFirstChild(WeaponConfig.StorageFolder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = WeaponConfig.StorageFolder
		folder.Parent = ServerStorage
	end
	local names = {}
	for _, spec in WeaponModels.Specs do
		local existing = folder:FindFirstChild(spec.toolName)
		if existing then
			if not existing:GetAttribute("Procedural") then
				-- A hand-made weapon took the name: leave it alone.
				warn("[REALITY 2059] " .. spec.toolName .. " ya existe y no es procedural; no se reemplaza")
				table.insert(names, spec.toolName)
				continue
			end
			existing:Destroy()
		end
		local tool = if spec.mesh then buildFromMesh(spec, spec.mesh) else nil
		if spec.mesh then
			print(string.format("[REALITY 2059] %s: %s", spec.toolName, if tool then "modelo de Blender" else "modelo de bloques (no hay " .. spec.mesh.prefix .. "_Cuerpo en ServerStorage)"))
		end
		local built = tool or build(spec)
		built.Parent = folder
		table.insert(names, spec.toolName)
	end
	-- Built weapons that are no longer in the list (renamed: P-9 -> Pm-8) go.
	for _, child in folder:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("Procedural") and not table.find(names, child.Name) then
			child:Destroy()
		end
	end
	return names
end

return WeaponModels
