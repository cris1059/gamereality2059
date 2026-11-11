--!strict

-- MORPHLAB scene: a wet night rooftop beside the lobby, facing City2059. The
-- avatar stands on a ringed platform between two railings; the city, its lit
-- walls and the sky rift (the lobby's LobbySkyline, cloned in by the client)
-- fill the background. Lights are deliberately soft: plastic skin and PBR
-- hair glare under strong spot lights. Idempotent; build after the lobby.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local Config = require(root.Config.MorphLabConfig)
local LobbyConfig = require(root.Config.LobbyConfig)

local MorphLabSceneBuilder = {}

local VARIANT = "NEO_EDEN_ROOFTOP"
local DARK = Color3.fromRGB(12, 12, 20)
local METAL = Color3.fromRGB(30, 30, 42)
local AMBER = Color3.fromRGB(255, 160, 60)
local PURPLE = Config.Palette.Purple
local CYAN = Config.Palette.Cyan

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, transparency: number?): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material
	item.Transparency = transparency or 0
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function neon(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3): Part
	local item = part(parent, name, size, cframe, color, Enum.Material.Neon)
	item.CanCollide = false
	item.CanQuery = false
	item.CastShadow = false
	return item
end

-- Invisible holder part (lights, particles and SurfaceGuis hang on it).
local function emitter(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	local item = part(parent, name, size, cframe, Color3.new(), Enum.Material.SmoothPlastic, 1)
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	return item
end

-- Flat disc centred on `center` (cylinder lying on its side).
local function disc(parent: Instance, name: string, diameter: number, thickness: number, center: Vector3, color: Color3, material: Enum.Material): Part
	local item = part(parent, name, Vector3.new(thickness, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	item.Shape = Enum.PartType.Cylinder
	item.CastShadow = false
	if material == Enum.Material.Neon then
		item.CanCollide = false
		item.CanQuery = false
	end
	return item
end

local function folder(parent: Instance, name: string): Folder
	local item = Instance.new("Folder")
	item.Name = name
	item.Parent = parent
	return item
end

-- Horizontal ring of tangent neon segments; `skip` leaves gaps (dashed arcs).
local function neonRing(parent: Instance, name: string, center: Vector3, radius: number, segments: number, thickness: number, color: Color3, skip: number?)
	local length = 2 * math.pi * radius / segments * 1.05
	for index = 1, segments do
		if not skip or index % skip ~= 0 then
			local angle = (index - 0.5) / segments * 2 * math.pi
			local position = center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
			neon(parent, name, Vector3.new(thickness, 0.05, length), CFrame.lookAt(position, position + tangent), color)
		end
	end
end

local function light(parent: Instance, class: string, color: Color3, brightness: number, range: number, angle: number?, shadows: boolean?): Light
	local item = Instance.new(class) :: any
	item.Color = color
	item.Brightness = brightness
	item.Range = range
	if angle then
		item.Angle = angle
		item.Face = Enum.NormalId.Front
	end
	item.Shadows = shadows == true
	item.Parent = parent
	return item
end

-- Self-lit text on the front face of `target`.
local function signText(target: BasePart, text: string, color: Color3, font: Enum.Font, background: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Display"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 0.9
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = target
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = background or Color3.new()
	label.BackgroundTransparency = if background then 0.1 else 1
	label.BorderSizePixel = 0
	label.Font = font
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextWrapped = true
	label.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.08, 0)
	padding.PaddingRight = UDim.new(0.08, 0)
	padding.PaddingTop = UDim.new(0.06, 0)
	padding.PaddingBottom = UDim.new(0.06, 0)
	padding.Parent = label
	return label
end

-- The lobby's origin shifted sideways: same height and distance from the
-- city, so both scenes share the same backdrop.
local function resolveOrigin(): Vector3
	local runtime = Workspace:FindFirstChild(Config.RuntimeFolderName)
	local lobby = runtime and runtime:FindFirstChild(LobbyConfig.ModelName)
	local platform = lobby and lobby:FindFirstChild("Platform")
	local spawn = platform and platform:FindFirstChild("CharacterSpawn")
	if spawn and spawn:IsA("BasePart") then
		return spawn.Position - Vector3.new(0, 0.55, 0) + Config.RooftopOffset
	end
	return Config.Origin
end

local function buildArchitecture(model: Model, o: Vector3)
	local group = folder(model, "Architecture")
	local floor = part(group, "Floor", Vector3.new(60, 1, 48), CFrame.new(o + Vector3.new(0, 0, -6)), Color3.fromRGB(11, 10, 20), Enum.Material.SmoothPlastic)
	floor.Reflectance = 0.16
	-- Faint tile seams across the wet roof.
	for x = -28, 28, 8 do
		part(group, "FloorSeam", Vector3.new(0.08, 0.02, 46), CFrame.new(o + Vector3.new(x, 0.51, -6)), Color3.fromRGB(22, 20, 36), Enum.Material.SmoothPlastic).CanCollide = false
	end
	for z = -28, 16, 8 do
		part(group, "FloorSeam", Vector3.new(58, 0.02, 0.08), CFrame.new(o + Vector3.new(0, 0.51, z)), Color3.fromRGB(22, 20, 36), Enum.Material.SmoothPlastic).CanCollide = false
	end
	-- Low back parapet with a violet line where the roof meets the skyline.
	part(group, "BackParapet", Vector3.new(60, 1.6, 1), CFrame.new(o + Vector3.new(0, 1.3, -29.5)), DARK, Enum.Material.Metal)
	neon(group, "BackRailLight", Vector3.new(58, 0.12, 0.2), CFrame.new(o + Vector3.new(0, 2.15, -29.2)), PURPLE)
	-- Side railings running towards the camera, as in the reference art.
	for _, side in { -1, 1 } do
		local x = side * 15
		for z = -26, 12, 4 do
			part(group, "RailPost", Vector3.new(0.3, 3.2, 0.3), CFrame.new(o + Vector3.new(x, 2.1, z)), METAL, Enum.Material.Metal)
		end
		part(group, "RailTop", Vector3.new(0.3, 0.3, 38.4), CFrame.new(o + Vector3.new(x, 3.7, -7)), METAL, Enum.Material.Metal)
		part(group, "RailMid", Vector3.new(0.2, 0.2, 38.4), CFrame.new(o + Vector3.new(x, 2.4, -7)), METAL, Enum.Material.Metal)
		neon(group, "RailLight", Vector3.new(0.08, 0.08, 38), CFrame.new(o + Vector3.new(x - side * 0.2, 3.5, -7)), if side < 0 then PURPLE else CYAN)
		-- Corner pylons at the back of the roof.
		part(group, "Pylon", Vector3.new(2, 18, 2), CFrame.new(o + Vector3.new(side * 24, 9.5, -26)), DARK, Enum.Material.Metal).CastShadow = false
		neon(group, "PylonLight", Vector3.new(0.25, 15, 0.25), CFrame.new(o + Vector3.new(side * 24 - side * 1.1, 9.5, -25)), if side < 0 then CYAN else PURPLE)
	end
end

local function buildPlatform(model: Model, o: Vector3)
	-- "Platform/CharacterSpawn" is where AvatarPreview stands the avatar.
	local group = folder(model, "Platform")
	local deckColor = Color3.fromRGB(22, 20, 34)
	local halo = disc(group, "MagentaHalo", 15, 0.04, o + Vector3.new(0, 0.52, 0), PURPLE, Enum.Material.Neon)
	halo.Transparency = 0.8
	disc(group, "Foundation", 13, 0.6, o + Vector3.new(0, 0.8, 0), DARK, Enum.Material.Metal)
	-- Neon discs slightly wider than the dark disc above them: only a rim shows.
	disc(group, "OuterEnergyRing", 13.3, 0.14, o + Vector3.new(0, 0.86, 0), PURPLE, Enum.Material.Neon)
	disc(group, "Step", 12, 0.35, o + Vector3.new(0, 1.25, 0), Color3.fromRGB(18, 17, 28), Enum.Material.Metal)
	disc(group, "Deck", 10, 0.2, o + Vector3.new(0, 1.45, 0), deckColor, Enum.Material.DiamondPlate)
	disc(group, "InnerEnergyRing", 9.2, 0.04, o + Vector3.new(0, 1.565, 0), PURPLE, Enum.Material.Neon)
	disc(group, "InnerRingMask", 8.8, 0.05, o + Vector3.new(0, 1.58, 0), deckColor, Enum.Material.Metal)
	disc(group, "CoreEnergyRing", 6.4, 0.04, o + Vector3.new(0, 1.6, 0), CYAN, Enum.Material.Neon)
	disc(group, "ScannerPad", 6, 0.05, o + Vector3.new(0, 1.615, 0), Color3.fromRGB(14, 13, 24), Enum.Material.Metal)
	-- Amber status lights along the platform's front edge.
	for _, degrees in { -50, -25, 25, 50 } do
		local angle = math.rad(90 + degrees)
		local position = o + Vector3.new(math.cos(angle) * 6.55, 0.8, math.sin(angle) * 6.55)
		neon(group, "StatusLight", Vector3.new(0.7, 0.14, 0.1), CFrame.lookAt(position, o + Vector3.new(0, 0.8, 0)), AMBER)
	end
	local spawn = part(group, "CharacterSpawn", Vector3.new(4, 0.2, 4), CFrame.new(o + Vector3.new(0, 1.54, 0)), PURPLE, Enum.Material.ForceField, 1)
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn:SetAttribute("Purpose", "UniversalR15Preview")
end

-- Floor rings around the platform (the "scanner" field).
local function buildScanner(model: Model, o: Vector3)
	local group = folder(model, "Scanner")
	neonRing(group, "FieldRing", o + Vector3.new(0, 0.53, 0), 9.5, 56, 0.12, PURPLE)
	neonRing(group, "FieldArc", o + Vector3.new(0, 0.53, 0), 11.5, 64, 0.08, Color3.fromRGB(255, 50, 110), 4)
end

local function buildLighting(model: Model, o: Vector3)
	local group = folder(model, "Lighting")
	local chest = o + Vector3.new(0, 4.6, 0)
	-- Key from the camera side, a warm fill from the left, two coloured rims.
	local front = emitter(group, "AvatarFrontFill", Vector3.one, CFrame.lookAt(o + Vector3.new(2, 8.5, 12), chest))
	front:SetAttribute("Role", "Key")
	light(front, "SpotLight", Color3.fromRGB(232, 228, 255), 1.7, 26, 60, true)
	local fill = emitter(group, "AvatarSoftFill", Vector3.one, CFrame.lookAt(o + Vector3.new(-7, 5, 8), chest))
	light(fill, "SpotLight", Color3.fromRGB(255, 214, 190), 0.8, 20, 70)
	local cyanRim = emitter(group, "AvatarCyanRim", Vector3.one, CFrame.lookAt(o + Vector3.new(5.5, 8, -6), chest))
	light(cyanRim, "SpotLight", CYAN, 1.5, 16, 50)
	local purpleRim = emitter(group, "AvatarMagentaRim", Vector3.one, CFrame.lookAt(o + Vector3.new(-5.5, 8, -6), chest))
	light(purpleRim, "SpotLight", PURPLE, 1.6, 16, 50)
	local pad = emitter(group, "PlatformGlow", Vector3.one, CFrame.new(o + Vector3.new(0, 1.8, 0)))
	light(pad, "PointLight", PURPLE, 0.8, 9)
	-- The roof itself: pools of light along the railings and from the pylons.
	for _, side in { -1, 1 } do
		for z = -22, 8, 10 do
			local lamp = emitter(group, "RailGlow", Vector3.one, CFrame.new(o + Vector3.new(side * 14.6, 3.6, z)))
			light(lamp, "PointLight", if side < 0 then PURPLE else CYAN, 0.7, 11)
		end
		local pylon = emitter(group, "PylonGlow", Vector3.one, CFrame.new(o + Vector3.new(side * 22.8, 10, -24.5)))
		light(pylon, "PointLight", if side < 0 then CYAN else PURPLE, 1, 20)
	end
end

local function buildDecorations(model: Model, o: Vector3, camera: Vector3)
	local group = folder(model, "Decorations")
	local function facing(position: Vector3): CFrame
		return CFrame.lookAt(position, Vector3.new(camera.X, position.Y, camera.Z))
	end
	-- Top left: NEO-EDEN sign above the left column of the UI.
	local sign = part(group, "NeoEdenSign", Vector3.new(7, 4, 0.3), facing(o + Vector3.new(-9, 18, -30)), Color3.fromRGB(6, 14, 24), Enum.Material.Metal)
	sign.CanCollide = false
	signText(sign, "NEO-EDEN\nネオ・エデン", CYAN, Enum.Font.GothamBlack)
	neon(group, "NeoEdenFrame", Vector3.new(7.3, 0.12, 0.12), sign.CFrame * CFrame.new(0, -2.1, 0), CYAN)
	-- Foreground: crates with amber work lamps on both sides.
	for _, entry in { { -12, 9 }, { 12, 8 } } do
		local x, z = entry[1], entry[2]
		part(group, "Crate", Vector3.new(2.4, 2, 2), CFrame.new(o + Vector3.new(x, 1.5, z)) * CFrame.Angles(0, math.rad(x * 2), 0), Color3.fromRGB(26, 24, 34), Enum.Material.Metal)
		local lamp = neon(group, "WorkLamp", Vector3.new(0.6, 0.6, 0.6), CFrame.new(o + Vector3.new(x, 2.8, z)), AMBER)
		lamp.Transparency = 0.2
		light(lamp, "PointLight", AMBER, 0.5, 7)
	end
end

-- Light rain over the roof (see LobbyConfig.Rain).
local function buildRain(model: Model, o: Vector3)
	local settings = LobbyConfig.Rain
	if not settings.Enabled then
		return
	end
	local group = folder(model, "Rain")
	local sky = emitter(group, "RainSky", Vector3.new(60, 1, 44), CFrame.new(o + Vector3.new(0, 30, -6)))
	local rain = Instance.new("ParticleEmitter")
	rain.Texture = settings.Texture
	rain.Color = ColorSequence.new(settings.Color)
	rain.LightEmission = 0.5
	rain.LightInfluence = 0
	rain.Rate = settings.Rate * 0.6
	rain.Lifetime = NumberRange.new(0.5, 0.65)
	rain.Speed = NumberRange.new(settings.Speed * 0.9, settings.Speed * 1.1)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(2, 2)
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Size = NumberSequence.new(settings.Width)
	rain.Squash = NumberSequence.new(settings.Stretch)
	rain.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.55), NumberSequenceKeypoint.new(1, 0.8) })
	rain.Parent = sky
end

local function buildCameras(model: Model, o: Vector3)
	local group = folder(model, "Cameras")
	local anchor = part(group, "CinematicCamera", Vector3.one, CFrame.lookAt(o + Config.Camera.PositionOffset, o + Config.Camera.LookOffset), Color3.new(), Enum.Material.SmoothPlastic, 1)
	anchor.CanCollide = false
	local focus = part(group, "PlatformFocus", Vector3.one, CFrame.new(o + Config.Camera.LookOffset), Color3.new(), Enum.Material.SmoothPlastic, 1)
	focus.CanCollide = false
end

function MorphLabSceneBuilder.IsVariantSupported(variant: string): boolean
	return variant == VARIANT
end

function MorphLabSceneBuilder.Build(): Model
	local runtime = Workspace:FindFirstChild(Config.RuntimeFolderName)
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = Config.RuntimeFolderName
		runtime.Parent = Workspace
	end
	local existing = runtime:FindFirstChild(Config.ModelName)
	if existing and existing:IsA("Model") and existing:GetAttribute("SceneVersion") == Config.SceneVersion then
		return existing
	end
	if existing then
		existing:Destroy()
	end

	local o = resolveOrigin()
	local model = Instance.new("Model")
	model.Name = Config.ModelName
	-- StreamingEnabled: no character stands here, so the scene must always replicate.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("GeneratedBy", "MorphLabSceneBuilder")
	model:SetAttribute("SceneVersion", Config.SceneVersion)
	model:SetAttribute("EnvironmentVariant", VARIANT)
	model.Parent = runtime

	buildArchitecture(model, o)
	buildPlatform(model, o)
	buildScanner(model, o)
	buildLighting(model, o)
	buildDecorations(model, o, o + Config.Camera.PositionOffset)
	buildRain(model, o)
	buildCameras(model, o)
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant.Material == Enum.Material.Neon then
			descendant.Transparency = math.max(descendant.Transparency, Config.NeonTransparency)
		end
	end
	return model
end

return MorphLabSceneBuilder
