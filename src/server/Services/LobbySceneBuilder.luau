--!strict

-- Builds the post-creation lobby: a wet rooftop in front of City2059 with the
-- player's ring and four squad rings in a tight line-up, stage lights, rain
-- and the NEO-EDEN sign. Idempotent, like MorphLabSceneBuilder; it never
-- modifies City2059 itself.
--
-- The lobby's city dressing (lit windows and signs on the walls the camera
-- sees, light columns, the sky rift) is a separate model, LobbySkyline, kept
-- in ReplicatedStorage: the client clones it only while the hub is open, so
-- MODO LIBRE keeps its own look.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local MorphLabConfig = require(root.Config.MorphLabConfig)
local Config = require(root.Config.LobbyConfig)
local Buildings = require(script.Parent.Parent.World.City2059Dressing)
local Facade = require(script.Parent.Parent.World.CityFacadeConfig)
local CityWorldService = require(script.Parent.CityWorldService)
local CityDressingService = require(script.Parent.CityDressingService)

local LobbySceneBuilder = {}

local DARK = Color3.fromRGB(12, 13, 20)
local ACCENT = MorphLabConfig.Palette.Magenta
local CYAN = MorphLabConfig.Palette.Cyan
local VIOLET = Color3.fromRGB(150, 70, 255)

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
	local item = part(parent, name, size, cframe, color, Enum.Material.Neon, MorphLabConfig.NeonTransparency)
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

-- Vertical-axis disc (cylinder lying flat).
local function disc(parent: Instance, name: string, diameter: number, thickness: number, center: Vector3, color: Color3, material: Enum.Material): Part
	local item = part(parent, name, Vector3.new(thickness, diameter, diameter), CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	item.Shape = Enum.PartType.Cylinder
	item.CanCollide = false
	item.CastShadow = false
	return item
end

local function folder(parent: Instance, name: string): Folder
	local item = Instance.new("Folder")
	item.Name = name
	item.Parent = parent
	return item
end

-- Self-lit SurfaceGui on a part's face.
local function glowGui(target: BasePart, face: Enum.NormalId, pixelsPerStud: number, brightness: number?): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.LightInfluence = 0
	gui.Brightness = brightness or 1
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = pixelsPerStud
	gui.Parent = target
	return gui
end

local function surfaceText(target: Part, text: string, color: Color3, font: Enum.Font)
	local gui = glowGui(target, Enum.NormalId.Front, 30)
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = font
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.Parent = gui
end

-- Glowing ring on the floor: a soft halo, the neon band and a dark centre,
-- with a light pool in the ring's colour.
local function floorRing(parent: Instance, name: string, center: Vector3, diameter: number, color: Color3)
	local halo = disc(parent, name .. "Halo", diameter + 0.9, 0.04, center + Vector3.new(0, 0.52, 0), color, Enum.Material.Neon)
	halo.Transparency = 0.82
	local glow = disc(parent, name, diameter, 0.08, center + Vector3.new(0, 0.54, 0), color, Enum.Material.Neon)
	glow.Transparency = MorphLabConfig.NeonTransparency * 0.6
	disc(parent, name .. "Mask", diameter - 0.45, 0.08, center + Vector3.new(0, 0.58, 0), Color3.fromRGB(10, 10, 16), Enum.Material.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = Config.Lighting.RingBrightness
	light.Range = Config.Lighting.RingRange
	light.Parent = glow
end

-- Lobby origin in front of the city's front (+Z) face, partway up its height.
local function resolveOrigin(): (Vector3, any)
	local city = Workspace:FindFirstChild(Config.CityModelName, true)
	if city and city:IsA("Model") then
		local frame, size = city:GetBoundingBox()
		local front = frame.Position.Z + size.Z * 0.5
		local bottom = frame.Position.Y - size.Y * 0.5
		return Vector3.new(frame.Position.X, bottom + size.Y * Config.CityHeightFraction, front + Config.CityFrontGap), { frame, size }
	end
	return Config.FallbackOrigin, nil
end

local function buildRooftop(model: Model, o: Vector3)
	local group = folder(model, "Rooftop")
	local floor = part(group, "Floor", Vector3.new(90, 1, 46), CFrame.new(o + Vector3.new(0, 0, -4)), Color3.fromRGB(10, 11, 18), Enum.Material.SmoothPlastic)
	floor.Reflectance = Config.Lighting.FloorReflectance
	-- Front edge with a railing light, side parapets and corner pylons.
	part(group, "FrontLip", Vector3.new(90, 1.4, 1), CFrame.new(o + Vector3.new(0, 0.7, 19)), DARK, Enum.Material.Metal)
	neon(group, "FrontRailLight", Vector3.new(88, 0.15, 0.2), CFrame.new(o + Vector3.new(0, 1.45, 18.6)), ACCENT)
	for _, x in { -45, 45 } do
		part(group, "SideParapet", Vector3.new(1, 3, 46), CFrame.new(o + Vector3.new(x, 1.5, -4)), DARK, Enum.Material.Metal)
		local pylon = part(group, "Pylon", Vector3.new(2, 16, 2), CFrame.new(o + Vector3.new(x * 0.8, 8.5, -22)), DARK, Enum.Material.Metal)
		pylon.CastShadow = false
		neon(group, "PylonLight", Vector3.new(0.3, 14, 0.3), CFrame.new(o + Vector3.new(x * 0.8 + (if x < 0 then 1.1 else -1.1), 8.5, -21)), if x < 0 then CYAN else ACCENT)
	end
	-- Back edge light: a thin neon line where the roof meets the skyline.
	neon(group, "BackRailLight", Vector3.new(88, 0.12, 0.2), CFrame.new(o + Vector3.new(0, 0.62, -26.6)), VIOLET)
end

local function buildSquad(model: Model, o: Vector3)
	-- "Platform/CharacterSpawn" is where AvatarPreview stands the player.
	local platform = folder(model, "Platform")
	floorRing(platform, "PlayerRing", o, Config.PlayerRingDiameter, Config.PlayerColor)
	local spawn = part(platform, "CharacterSpawn", Vector3.new(3, 0.2, 3), CFrame.new(o + Vector3.new(0, 0.55, 0)), Config.PlayerColor, Enum.Material.ForceField, 1)
	spawn.CanCollide = false
	spawn:SetAttribute("Purpose", "LobbyPlayer")
	local squad = folder(model, "Squad")
	for index, slot in Config.SquadSlots do
		local center = o + slot.offset
		floorRing(squad, "SquadRing" .. index, center, Config.RingDiameter, slot.color)
		-- Where a squad member (a friend, or a Studio preview) stands.
		local memberSpawn = part(squad, "SquadSpawn" .. index, Vector3.new(3, 0.2, 3), CFrame.new(center + Vector3.new(0, 0.55, 0)), slot.color, Enum.Material.ForceField, 1)
		memberSpawn.CanCollide = false
		-- Anchor for the client's "+ INVITAR" hologram.
		local anchor = part(squad, "SquadSlot" .. index, Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 3.5, 0)), slot.color, Enum.Material.SmoothPlastic, 1)
		anchor.CanCollide = false
		anchor:SetAttribute("SlotIndex", index)
	end
end

-- Wet floor: soft self-lit streaks painted on the roof, as reflections of the
-- rings (towards the camera) and of the city's neon (far half of the roof).
-- The gradient is symmetric, so the face's canvas orientation does not matter.
local function streak(parent: Instance, name: string, center: Vector3, width: number, length: number, color: Color3, opacity: number)
	local holder = emitter(parent, name, Vector3.new(width, 0.02, length), CFrame.new(center))
	local gui = glowGui(holder, Enum.NormalId.Top, 6)
	local paint = Instance.new("Frame")
	paint.Size = UDim2.fromScale(1, 1)
	paint.BackgroundColor3 = color
	paint.BorderSizePixel = 0
	paint.Parent = gui
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0.5, 0)
	round.Parent = paint
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.35, 1 - opacity),
		NumberSequenceKeypoint.new(0.65, 1 - opacity),
		NumberSequenceKeypoint.new(1, 1),
	})
	fade.Parent = paint
end

local function buildReflections(model: Model, o: Vector3)
	local settings = Config.Reflections
	local group = folder(model, "Reflections")
	-- Just above the floor (top at +0.5) and under the ring halos (+0.54).
	local y = o.Y + 0.515
	local stands = { { position = o, color = Config.PlayerColor } }
	for _, slot in Config.SquadSlots do
		table.insert(stands, { position = o + slot.offset, color = slot.color })
	end
	for index, stand in stands do
		local base = Vector3.new(stand.position.X, y, stand.position.Z + settings.Length * 0.5)
		streak(group, "RingReflection" .. index, base, settings.Width, settings.Length, stand.color, settings.Opacity)
	end
	local random = Random.new(2059)
	local colors = Config.Skyline.Colors
	for index = 1, settings.CityStreaks do
		local x = -40 + 80 * (index - 0.5) / settings.CityStreaks + random:NextNumber(-2, 2)
		local length = random:NextNumber(6, 14)
		local base = Vector3.new(o.X + x, y, o.Z - 6 - random:NextNumber(2, 12))
		streak(group, "CityReflection" .. index, base, random:NextNumber(0.5, 1.4), length, colors[random:NextInteger(1, #colors)], random:NextNumber(0.2, 0.35))
	end
end

-- Stage lighting: two shared key lights from the camera side (with shadows),
-- a coloured rim behind each character in its ring's colour, like the
-- reference art. Shadows and the glossy floor need Lighting.Technology = Future.
local function buildStageLights(model: Model, o: Vector3)
	local group = folder(model, "StageLights")
	local settings = Config.Lighting
	local target = o + Vector3.new(0, 3.4, -0.8)
	for index, offset in settings.Keys do
		local key = emitter(group, "Key" .. index, Vector3.one, CFrame.lookAt(o + offset, target))
		local keyLight = Instance.new("SpotLight")
		keyLight.Color = settings.KeyColor
		keyLight.Brightness = settings.KeyBrightness
		keyLight.Range = settings.KeyRange
		keyLight.Angle = settings.KeyAngle
		keyLight.Shadows = true
		keyLight.Parent = key
	end
	local stands = { { name = "Player", position = o, color = Config.PlayerColor } }
	for index, slot in Config.SquadSlots do
		table.insert(stands, { name = "Squad" .. index, position = o + slot.offset, color = slot.color })
	end
	for _, stand in stands do
		local chest = stand.position + Vector3.new(0, 3.6, 0)
		local rim = emitter(group, stand.name .. "Rim", Vector3.one, CFrame.lookAt(stand.position + settings.RimOffset, chest))
		local rimLight = Instance.new("SpotLight")
		rimLight.Color = stand.color
		rimLight.Brightness = settings.RimBrightness
		rimLight.Range = settings.RimRange
		rimLight.Angle = settings.RimAngle
		rimLight.Shadows = false
		rimLight.Parent = rim
	end
end

-- Rain over the platform, as in the reference art. Streaks use the engine's
-- sparkle texture stretched along their fall; a custom streak texture would
-- look better (see LobbyConfig.Rain).
local function buildRain(model: Model, o: Vector3)
	local settings = Config.Rain
	if not settings.Enabled then
		return
	end
	local group = folder(model, "Rain")
	local sky = emitter(group, "RainSky", Vector3.new(100, 1, 64), CFrame.new(o + Vector3.new(0, 34, -2)))
	local rain = Instance.new("ParticleEmitter")
	rain.Texture = settings.Texture
	rain.Color = ColorSequence.new(settings.Color)
	rain.LightEmission = 0.7
	rain.LightInfluence = 0
	rain.Rate = settings.Rate
	rain.Lifetime = NumberRange.new(0.5, 0.65)
	rain.Speed = NumberRange.new(settings.Speed * 0.9, settings.Speed * 1.1)
	rain.EmissionDirection = Enum.NormalId.Bottom
	rain.SpreadAngle = Vector2.new(2, 2)
	rain.Orientation = Enum.ParticleOrientation.VelocityParallel
	rain.Size = NumberSequence.new(settings.Width)
	rain.Squash = NumberSequence.new(settings.Stretch)
	rain.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.45), NumberSequenceKeypoint.new(1, 0.7) })
	rain.Parent = sky
	-- Droplets bursting on the floor.
	local floorSplash = emitter(group, "RainSplash", Vector3.new(90, 0.5, 46), CFrame.new(o + Vector3.new(0, 0.7, -4)))
	local splash = Instance.new("ParticleEmitter")
	splash.Texture = settings.Texture
	splash.Color = ColorSequence.new(settings.Color)
	splash.LightEmission = 0.8
	splash.LightInfluence = 0
	splash.Rate = settings.SplashRate
	splash.Lifetime = NumberRange.new(0.18, 0.3)
	splash.Speed = NumberRange.new(0.5, 1.5)
	splash.EmissionDirection = Enum.NormalId.Top
	splash.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0.5) })
	splash.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	splash.Parent = floorSplash
end

-- NEO-EDEN board to the right of the line-up, facing the camera.
local function buildSign(model: Model, o: Vector3, cameraPosition: Vector3)
	local group = folder(model, "Signage")
	local s = Config.Sign.Size / 15
	local position = o + Config.Sign.Offset
	local facing = CFrame.lookAt(position, Vector3.new(cameraPosition.X, position.Y, cameraPosition.Z))
	local board = part(group, "NeoEdenSign", Vector3.new(15, 15, 0.4) * s, facing, Color3.fromRGB(10, 8, 16), Enum.Material.Metal)
	board.CanCollide = false
	-- Text on the lower part of the board, emblem above it.
	local textPanel = part(group, "NeoEdenText", Vector3.new(14 * s, 5 * s, 0.1), facing * CFrame.new(0, -4.2 * s, -0.3), Color3.new(), Enum.Material.SmoothPlastic, 1)
	textPanel.CanCollide = false
	surfaceText(textPanel, "NEO-EDEN\n// SECTOR 7", Config.PlayerColor, Enum.Font.GothamBlack)
	-- Emblem: a neon diamond crossed by a slanted bar.
	for _, bar in {
		{ Vector3.new(-2.1, 3.4, 0), 45 }, { Vector3.new(2.1, 3.4, 0), -45 },
		{ Vector3.new(-2.1, -0.8, 0), -45 }, { Vector3.new(2.1, -0.8, 0), 45 },
		{ Vector3.new(0.4, 1.3, 0), 70 },
	} do
		neon(group, "NeoEdenEmblem", Vector3.new(0.45, 6.2, 0.3) * s, facing * CFrame.new(bar[1] * s + Vector3.new(0, 0, -0.35)) * CFrame.Angles(0, 0, math.rad(bar[2])), Config.PlayerColor)
	end
	neon(group, "NeoEdenSignFrame", Vector3.new(15.6 * s, 0.3, 0.3), facing * CFrame.new(0, 7.8 * s, 0), Config.PlayerColor)
	neon(group, "NeoEdenSignFrame", Vector3.new(15.6 * s, 0.3, 0.3), facing * CFrame.new(0, -7.8 * s, 0), Config.PlayerColor)
	local glow = Instance.new("PointLight")
	glow.Color = Config.PlayerColor
	glow.Brightness = 1.5
	glow.Range = 16
	glow.Parent = board
end

local function buildCameras(model: Model, o: Vector3): CFrame
	local group = folder(model, "Cameras")
	local view = CFrame.lookAt(o + Config.Camera.PositionOffset, o + Config.Camera.LookOffset)
	local anchor = part(group, "CinematicCamera", Vector3.one, view, Color3.new(), Enum.Material.SmoothPlastic, 1)
	anchor.CanCollide = false
	return view
end

-- ------------------------------------------------------------- skyline --

-- Dimensional rift in the sky: a ring of neon segments around a swirling
-- force-field disc, with dark debris around it. Placed by angle from the
-- JUGAR view so it is always framed above the line-up.
local function buildPortal(skyline: Model, view: CFrame)
	local settings = Config.Portal
	local group = folder(skyline, "Portal")
	local direction = (view * CFrame.Angles(0, math.rad(settings.YawDegrees), 0) * CFrame.Angles(math.rad(settings.PitchDegrees), 0, 0)).LookVector
	local center = view.Position + direction * settings.Distance
	local radius = settings.Distance * math.tan(math.rad(settings.RadiusDegrees))
	local k = radius / 34
	local facing = CFrame.lookAt(center, view.Position)
	for index = 1, 36 do
		local angle = (index - 0.5) / 36 * 2 * math.pi
		local position = facing:PointToWorldSpace(Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0))
		local tangent = facing:VectorToWorldSpace(Vector3.new(-math.sin(angle), math.cos(angle), 0))
		neon(group, "RiftRing", Vector3.new(1.6 * k, 1.6 * k, 2 * math.pi * radius / 36 * 1.08), CFrame.lookAt(position, position + tangent), if index % 3 == 0 then CYAN else VIOLET)
	end
	for layer, scale in { 1, 0.7, 0.42 } do
		local swirl = part(group, "RiftSwirl", Vector3.new(0.4, radius * 2 * scale, radius * 2 * scale), facing * CFrame.new(0, 0, -layer * 2 * k) * CFrame.Angles(0, math.rad(90), 0), if layer == 2 then CYAN else VIOLET, Enum.Material.ForceField, 0.15 * layer)
		swirl.Shape = Enum.PartType.Cylinder
		swirl.CanCollide = false
		swirl.CastShadow = false
	end
	local random = Random.new(2059)
	for index = 1, 14 do
		local angle = random:NextNumber(0, 2 * math.pi)
		local distance = radius * random:NextNumber(1.1, 1.7)
		local position = facing:PointToWorldSpace(Vector3.new(math.cos(angle) * distance, math.sin(angle) * distance, random:NextNumber(-10, 10) * k))
		local size = random:NextNumber(3, 8) * k
		local debris = part(group, "Debris" .. index, Vector3.new(size, size * 0.6, size * 1.3), CFrame.new(position) * CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), 0), Color3.fromRGB(20, 18, 30), Enum.Material.Slate)
		debris.CanCollide = false
		debris.CastShadow = false
	end
	local light = Instance.new("PointLight")
	light.Color = VIOLET
	light.Brightness = 3
	light.Range = 60
	light.Parent = group:FindFirstChild("RiftSwirl")
end

-- City walls (CityDressingService.WallFrame) that face the camera and fall
-- inside the JUGAR view, nearest first.
local function facingWalls(view: CFrame): { any }
	local transform = CityWorldService.Transform
	if not transform then
		return {}
	end
	local settings = Config.Skyline
	local tanY = math.tan(math.rad(MorphLabConfig.Camera.FieldOfView / 2)) * 1.25
	local tanX = tanY * 1.9
	local walls = {}
	for buildingIndex, building in Buildings do
		for _, wall in building.walls do
			local center, normal, along, width, height = CityDressingService.WallFrame(transform, wall)
			local toCamera = view.Position - center
			local distance = toCamera.Magnitude
			if distance > settings.MaxDistance or width < 8 or height < 12 or normal:Dot(toCamera.Unit) < settings.MinFacing then
				continue
			end
			local halfX, halfY = along * (width / 2), Vector3.yAxis * (height / 2)
			for _, point in { center, center + halfX + halfY, center - halfX + halfY, center + halfX - halfY, center - halfX - halfY } do
				local p = view:PointToObjectSpace(point)
				if p.Z < -1 and math.abs(p.X / p.Z) < tanX and math.abs(p.Y / p.Z) < tanY then
					table.insert(walls, { center = center, normal = normal, along = along, width = width, height = height, distance = distance, building = buildingIndex })
					break
				end
			end
		end
	end
	table.sort(walls, function(a, b)
		return a.distance < b.distance
	end)
	while #walls > settings.MaxWalls do
		table.remove(walls)
	end
	return walls
end

-- Lit windows (self-lit tiles), neon bands and vertical signs on each wall.
local function dressWall(group: Instance, wall, random: Random)
	local settings = Config.Skyline
	local colors = settings.Colors
	local color = colors[(wall.building - 1) % #colors + 1]
	local set = settings.WindowSets[(wall.building - 1) % #settings.WindowSets + 1]
	local imageId = Facade.AssetIds["Reality2059Windows_" .. set]
	if type(imageId) == "number" and imageId > 0 then
		local position = wall.center + wall.normal * 0.6
		local panel = emitter(group, "Windows", Vector3.new(wall.width, wall.height, 0.1), CFrame.lookAt(position, position + wall.normal))
		local gui = glowGui(panel, Enum.NormalId.Front, settings.WindowPixelsPerStud, settings.WindowBrightness)
		local image = Instance.new("ImageLabel")
		image.Size = UDim2.fromScale(1, 1)
		image.BackgroundTransparency = 1
		image.Image = "rbxassetid://" .. imageId
		image.ScaleType = Enum.ScaleType.Tile
		local tile = settings.WindowTileStuds * settings.WindowPixelsPerStud
		image.TileSize = UDim2.fromOffset(tile, tile)
		image.Parent = gui
	end
	if random:NextNumber() < settings.BandChance then
		local y = wall.center.Y + random:NextNumber(-0.35, 0.4) * wall.height
		local position = Vector3.new(wall.center.X, y, wall.center.Z) + wall.normal * 0.9
		neon(group, "NeonBand", Vector3.new(wall.width * random:NextNumber(0.5, 0.95), 0.5, 0.4), CFrame.lookAt(position, position + wall.normal), color)
	end
	if wall.height >= 30 and random:NextNumber() < settings.SignChance then
		local signColor = colors[random:NextInteger(1, #colors)]
		local w = math.clamp(wall.width * 0.1, 4, 8)
		local h = math.clamp(wall.height * 0.45, 18, 50)
		local side = if random:NextNumber() < 0.5 then -1 else 1
		local position = wall.center + wall.along * (side * (wall.width / 2 - w / 2 - 2))
			+ Vector3.yAxis * random:NextNumber(-wall.height * 0.15, wall.height * 0.2) + wall.normal * 2
		local sign = part(group, "VerticalSign", Vector3.new(w, h, 0.4), CFrame.lookAt(position, position + wall.normal), Color3.fromRGB(8, 8, 14), Enum.Material.SmoothPlastic)
		sign.CanCollide = false
		sign.CanQuery = false
		sign.CastShadow = false
		local gui = glowGui(sign, Enum.NormalId.Front, 4, settings.SignBrightness)
		local board = Instance.new("Frame")
		board.Size = UDim2.fromScale(1, 1)
		board.BackgroundColor3 = Color3.fromRGB(10, 6, 18)
		board.BackgroundTransparency = 0.15
		board.BorderSizePixel = 0
		board.Parent = gui
		local outline = Instance.new("UIStroke")
		outline.Color = signColor
		outline.Thickness = 3
		outline.Parent = board
		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(0.8, 0.92)
		text.Position = UDim2.fromScale(0.1, 0.04)
		text.BackgroundTransparency = 1
		text.Font = Enum.Font.GothamBlack
		text.Text = CityDressingService.VerticalText(settings.SignWords[random:NextInteger(1, #settings.SignWords)])
		text.TextColor3 = signColor
		text.TextScaled = true
		text.Parent = board
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Front
		light.Color = signColor
		light.Brightness = 0.7
		light.Range = 18
		light.Angle = 100
		light.Parent = sign
	end
end

-- Light columns and coloured glow over the city.
local function buildCityGlow(skyline: Model, o: Vector3, city: any)
	local group = folder(skyline, "CityDressing")
	local random = Random.new(59)
	local cityFrame: CFrame = if city then city[1] else CFrame.new(o + Vector3.new(0, 30, -150))
	local citySize: Vector3 = if city then city[2] else Vector3.new(300, 100, 300)
	local function cityPoint(heightFraction: number): Vector3
		return cityFrame.Position + Vector3.new(
			random:NextNumber(-0.42, 0.42) * citySize.X,
			(heightFraction - 0.5) * citySize.Y,
			random:NextNumber(-0.35, 0.45) * citySize.Z
		)
	end
	for index = 1, 8 do
		local base = cityPoint(0)
		local height = citySize.Y * random:NextNumber(0.9, 1.4)
		neon(group, "LightColumn" .. index, Vector3.new(0.6, height, 0.6), CFrame.new(base + Vector3.new(0, height * 0.5, 0)), if index % 2 == 0 then CYAN else ACCENT)
	end
	for index = 1, 8 do
		local holder = emitter(group, "CityGlow" .. index, Vector3.one, CFrame.new(cityPoint(random:NextNumber(0.3, 0.7))))
		local light = Instance.new("PointLight")
		light.Color = if index % 2 == 0 then VIOLET else CYAN
		light.Brightness = 2
		light.Range = 60
		light.Parent = holder
	end
end

local function buildSkyline(o: Vector3, view: CFrame, city: any): Model
	local skyline = Instance.new("Model")
	skyline.Name = Config.SkylineName
	skyline:SetAttribute("SceneVersion", Config.SceneVersion)
	buildPortal(skyline, view)
	buildCityGlow(skyline, o, city)
	local walls = folder(skyline, "Walls")
	local random = Random.new(2077)
	local dressed = facingWalls(view)
	for _, wall in dressed do
		dressWall(walls, wall, random)
	end
	skyline:SetAttribute("DressedWalls", #dressed)
	return skyline
end

-- Where the skyline template lives (replicated, outside Workspace).
local function skylineHome(): Instance
	return root:FindFirstChild("Runtime") or root
end

function LobbySceneBuilder.Build(): Model
	local runtime = Workspace:FindFirstChild(MorphLabConfig.RuntimeFolderName)
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = MorphLabConfig.RuntimeFolderName
		runtime.Parent = Workspace
	end
	local existing = runtime:FindFirstChild(Config.ModelName)
	local existingSkyline = skylineHome():FindFirstChild(Config.SkylineName)
	if existing and existing:IsA("Model") and existing:GetAttribute("SceneVersion") == Config.SceneVersion
		and existingSkyline and existingSkyline:GetAttribute("SceneVersion") == Config.SceneVersion then
		return existing
	end
	if existing then
		existing:Destroy()
	end
	if existingSkyline then
		existingSkyline:Destroy()
	end
	local origin, city = resolveOrigin()
	local model = Instance.new("Model")
	model.Name = Config.ModelName
	-- StreamingEnabled: no character stands here, so the scene must always replicate.
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("GeneratedBy", "LobbySceneBuilder")
	model:SetAttribute("SceneVersion", Config.SceneVersion)
	model:SetAttribute("AnchoredToCity", city ~= nil)
	model.Parent = runtime

	local view = buildCameras(model, origin)
	buildRooftop(model, origin)
	buildSquad(model, origin)
	buildReflections(model, origin)
	buildStageLights(model, origin)
	buildRain(model, origin)
	buildSign(model, origin, view.Position)
	local skyline = buildSkyline(origin, view, city)
	skyline.Parent = skylineHome()
	print(string.format("[REALITY 2059] Lobby: %d paredes de la ciudad iluminadas para el menú", skyline:GetAttribute("DressedWalls") or 0))
	return model
end

-- The skyline template (cloned by the client while the hub is open).
function LobbySceneBuilder.GetSkyline(): Model?
	local skyline = skylineHome():FindFirstChild(Config.SkylineName)
	return if skyline and skyline:IsA("Model") then skyline else nil
end

return LobbySceneBuilder
