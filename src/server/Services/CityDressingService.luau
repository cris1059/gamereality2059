--!strict

-- Gives every City2059 tower its own cyberpunk identity (brand, neon colour,
-- billboard screens, edge strips, rooftop sign). All towers share one mesh,
-- so a texture alone repeats identically; this dressing is anchored to each
-- tower's real walls (World/City2059Dressing, scripts/build_city2059_dressing.py)
-- through CityWorldService.Transform. Runtime only, inside the FreeRoam model
-- (persistent). Screens are SurfaceGuis: no images to upload. The client
-- animates elements tagged CityDressingConfig.FxTag.

local CollectionService = game:GetService("CollectionService")
local MaterialService = game:GetService("MaterialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local Config = require(root.Config.CityDressingConfig)
local Buildings = require(script.Parent.Parent.World.City2059Dressing)
local Facade = require(script.Parent.Parent.World.CityFacadeConfig)
local CityTextureConfig = require(script.Parent.Parent.World.CityTextureConfig)
local CityWorldService = require(script.Parent.CityWorldService)

local CityDressingService = {}

local DARK = Color3.fromRGB(8, 8, 12)

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	item.Size = size
	item.CFrame = cframe
	item.Color = color
	item.Material = material
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2, font: Enum.Font, color: Color3, stroke: Color3?): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Size = size
	item.Position = position
	item.Font = font
	item.Text = text
	item.TextScaled = true
	item.TextColor3 = color
	item.Parent = parent
	if stroke then
		local outline = Instance.new("UIStroke")
		outline.Color = stroke
		outline.Thickness = 2
		outline.Parent = item
	end
	return item
end

local function verticalText(text: string): string
	local letters = {}
	for _, code in utf8.codes(text) do
		local character = utf8.char(code)
		if character ~= " " then
			table.insert(letters, character)
		end
	end
	return table.concat(letters, "\n")
end

local function surface(screen: BasePart): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = Config.ScreenPixelsPerStud
	gui.LightInfluence = 0
	gui.Brightness = Config.ScreenBrightness
	gui.Parent = screen
	CollectionService:AddTag(gui, Config.FxTag)
	gui:SetAttribute("Fx", "flicker")
	return gui
end

-- Animated gradient background with scan lines and a neon border.
local function screenBase(gui: SurfaceGui, style): Frame
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Color3.new(1, 1, 1)
	frame.BorderSizePixel = 0
	frame.Parent = gui
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, style.bg1),
		ColorSequenceKeypoint.new(0.5, style.bg2),
		ColorSequenceKeypoint.new(1, style.bg1),
	})
	gradient.Rotation = 90
	gradient.Parent = frame
	CollectionService:AddTag(gradient, Config.FxTag)
	gradient:SetAttribute("Fx", "scroll")
	local border = Instance.new("UIStroke")
	border.Color = style.a
	border.Thickness = 6
	border.Parent = frame
	for index = 1, 18 do
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(0, 0, 0)
		line.BackgroundTransparency = 0.82
		line.Size = UDim2.new(1, 0, 0, 2)
		line.Position = UDim2.fromScale(0, index / 19)
		line.ZIndex = 3
		line.Parent = frame
	end
	return frame
end

local function mainScreenContent(gui: SurfaceGui, style, vertical: boolean)
	local frame = screenBase(gui, style)
	if vertical then
		local ring = Instance.new("Frame")
		ring.AnchorPoint = Vector2.new(0.5, 0)
		ring.Position = UDim2.fromScale(0.5, 0.04)
		ring.Size = UDim2.fromScale(0.5, 0.5)
		ring.BackgroundTransparency = 1
		ring.Parent = frame
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.Parent = ring
		local roundness = Instance.new("UICorner")
		roundness.CornerRadius = UDim.new(1, 0)
		roundness.Parent = ring
		local ringStroke = Instance.new("UIStroke")
		ringStroke.Color = style.a
		ringStroke.Thickness = 5
		ringStroke.Parent = ring
		label(frame, verticalText(style.brand), UDim2.fromScale(0.5, 0.62), UDim2.fromScale(0.25, 0.2), style.font, Color3.new(1, 1, 1), style.a)
		label(frame, style.jp, UDim2.fromScale(0.16, 0.5), UDim2.fromScale(0.78, 0.22), Enum.Font.GothamBold, style.b)
		label(frame, style.tag, UDim2.fromScale(0.9, 0.08), UDim2.fromScale(0.05, 0.88), Enum.Font.GothamBold, style.b)
	else
		label(frame, style.brand, UDim2.fromScale(0.86, 0.5), UDim2.fromScale(0.07, 0.12), style.font, Color3.new(1, 1, 1), style.a)
		label(frame, style.jp .. "  //  " .. style.tag, UDim2.fromScale(0.86, 0.22), UDim2.fromScale(0.07, 0.68), Enum.Font.GothamBold, style.b)
	end
end

local function promoContent(gui: SurfaceGui, style, promo: string)
	local frame = screenBase(gui, style)
	label(frame, promo, UDim2.fromScale(0.86, 0.46), UDim2.fromScale(0.07, 0.14), Enum.Font.GothamBlack, style.b, style.a)
	label(frame, style.brand, UDim2.fromScale(0.6, 0.2), UDim2.fromScale(0.2, 0.66), style.font, Color3.new(1, 1, 1))
end

local function wallFrame(transform, wall): (Vector3, Vector3, Vector3, number, number)
	local center = transform.toWorld(Vector3.new(wall[1], wall[2], wall[3]))
	local signs = transform.signs
	local normal = transform.rotation:VectorToWorldSpace(Vector3.new(wall[4] * signs.X, 0, wall[5] * signs.Z)).Unit
	local along = Vector3.yAxis:Cross(normal).Unit
	return center, normal, along, wall[6] * transform.scale.X, wall[7] * transform.scale.Y
end

-- Billboard on a wall: vertical when the wall is tall enough.
local function screen(parent: Instance, transform, wall, style, kind: string, promo: string?)
	local center, normal, _, width, height = wallFrame(transform, wall)
	local vertical = kind == "main" and height > 70
	local w, h
	if kind == "main" and vertical then
		w = math.clamp(width * 0.5, 14, 56)
		h = math.min(height * 0.62, w * 3.4)
	elseif kind == "main" then
		w = math.clamp(width * 0.7, 18, 90)
		h = math.min(height * 0.55, w * 0.45)
	else
		w = math.clamp(width * 0.45, 12, 40)
		h = math.min(height * 0.3, w * 0.6)
	end
	local bottom = center.Y - height / 2
	local y = if kind == "main" then bottom + height * 0.55 else bottom + height * 0.28
	y = math.clamp(y, bottom + h / 2 + 2, bottom + height - h / 2 - 2)
	local position = Vector3.new(center.X, y, center.Z) + normal * Config.WallGap
	local item = part(parent, if kind == "main" then "Screen" else "Promo", Vector3.new(w, h, 0.4), CFrame.lookAt(position, position + normal), DARK, Enum.Material.SmoothPlastic)
	local gui = surface(item)
	if kind == "main" then
		mainScreenContent(gui, style, vertical)
		local light = Instance.new("SurfaceLight")
		light.Face = Enum.NormalId.Front
		light.Color = style.a
		light.Brightness = 1.2
		light.Range = Config.LightRange
		light.Angle = 120
		light.Parent = item
	else
		promoContent(gui, style, promo or "ABIERTO 24H")
	end
end

-- Neon strips on both vertical edges of a wall and along its top.
local function edgeStrips(parent: Instance, transform, wall, style, accentBand: boolean)
	local center, normal, along, width, height = wallFrame(transform, wall)
	local t = Config.NeonThickness
	local offset = normal * (Config.WallGap * 0.6)
	for _, side in { -1, 1 } do
		local position = center + along * side * (width / 2 - t / 2) + offset
		part(parent, "NeonEdge", Vector3.new(t, height, t), CFrame.lookAt(position, position + normal), style.a, Enum.Material.Neon)
	end
	local top = center + Vector3.yAxis * (height / 2 - t / 2) + offset
	part(parent, "NeonTop", Vector3.new(width, t, t), CFrame.lookAt(top, top + normal), style.a, Enum.Material.Neon)
	if accentBand then
		local band = center - Vector3.yAxis * (height * 0.18) + offset
		part(parent, "NeonBand", Vector3.new(width * 0.92, t * 0.7, t * 0.7), CFrame.lookAt(band, band + normal), style.b, Enum.Material.Neon)
	end
end

-- Cladding: a thin smooth panel over the whole wall showing the tower's own
-- KitBash3D colour map as a tiled Texture (no TexturePack/MaterialVariant
-- packaging needed, so it always shows in play). If the PBR MaterialVariant
-- is installed it is used underneath for the surface response. Skipped when
-- the material has no colour id. Window overlays only when
-- CityFacadeConfig.Windows is on.
local function cladding(parent: Instance, transform, wall, look): boolean
	local material = Facade.Materials[look.material]
	local colorId = Facade.AssetIds["KB3D_NEC_" .. look.material .. "_basecolor"]
	if not material or type(colorId) ~= "number" or colorId <= 0 then
		return false
	end
	local center, normal, _, width, height = wallFrame(transform, wall)
	local position = center + normal * 0.15
	local panel = part(parent, "Cladding", Vector3.new(width, height, 0.2), CFrame.lookAt(position, position + normal), look.tint, material.base)
	local variant = MaterialService:FindFirstChild(Facade.VariantPrefix .. look.material)
	if variant and variant:IsA("MaterialVariant") then
		panel.MaterialVariant = variant.Name
	end
	local texture = Instance.new("Texture")
	texture.Face = Enum.NormalId.Front
	texture.Texture = "rbxassetid://" .. colorId
	texture.StudsPerTileU = material.studsPerTile
	texture.StudsPerTileV = material.studsPerTile
	texture.Color3 = look.tint
	texture.Parent = panel
	local imageId = look.windows and Facade.AssetIds["Reality2059Windows_" .. look.windows]
	local rows = look.windows and Facade.WindowRows[look.windows]
	if Facade.Windows and type(imageId) == "number" and imageId > 0 and rows and (look.floor or 0) > 0 then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = Facade.WindowPixelsPerStud
		gui.LightInfluence = 1
		gui.Parent = panel
		local tile = look.floor * rows * Facade.WindowPixelsPerStud
		local image = Instance.new("ImageLabel")
		image.BackgroundTransparency = 1
		image.Size = UDim2.fromScale(1, 1)
		image.Image = "rbxassetid://" .. imageId
		image.ImageColor3 = look.tint or Color3.new(1, 1, 1)
		image.ScaleType = Enum.ScaleType.Tile
		image.TileSize = UDim2.fromOffset(tile, tile)
		image.Parent = gui
		CollectionService:AddTag(gui, Config.FxTag)
		gui:SetAttribute("Fx", "windows")
	end
	return true
end

-- Lit sign standing on the roof edge above a wall that reaches the top.
local function rooftopSign(parent: Instance, transform, wall, style)
	local center, normal, _, width, height = wallFrame(transform, wall)
	local w = math.clamp(width * 0.8, 16, 70)
	local h = math.clamp(w * 0.18, 5, 12)
	local base = center + Vector3.yAxis * (height / 2) - normal * 2
	local position = base + Vector3.yAxis * (h / 2 + 2)
	local sign = part(parent, "RoofSign", Vector3.new(w, h, 0.5), CFrame.lookAt(position, position + normal), DARK, Enum.Material.Metal)
	sign.Transparency = 1
	local gui = surface(sign)
	label(gui, style.brand, UDim2.fromScale(1, 1), UDim2.new(), style.font, style.a, style.b)
	for _, side in { -0.35, 0.35 } do
		local post = base + sign.CFrame.RightVector * (w * side) + Vector3.yAxis * 1
		part(parent, "SignPost", Vector3.new(0.6, 2, 0.6), CFrame.new(post), DARK, Enum.Material.Metal)
	end
	local light = Instance.new("PointLight")
	light.Color = style.a
	light.Range = 24
	light.Brightness = 1
	light.Parent = sign
end

-- Shared with the lobby skyline (LobbySceneBuilder), which dresses the same walls.
CityDressingService.WallFrame = wallFrame
CityDressingService.VerticalText = verticalText

-- Builds the dressing into world/<FolderName>; returns the number of towers dressed.
function CityDressingService.Build(world: Model): number
	local transform = CityWorldService.Transform
	if not Config.Enabled or not transform then
		return 0
	end
	local existing = world:FindFirstChild(Config.FolderName)
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = Config.FolderName
	folder.Parent = world
	-- Deterministic shuffle so neighbours rarely share a brand.
	local order = {}
	for index = 1, #Config.Styles do
		order[index] = index
	end
	local random = Random.new(2059)
	for index = #order, 2, -1 do
		local swap = random:NextInteger(1, index)
		order[index], order[swap] = order[swap], order[index]
	end
	-- Cyber texture sets switched off in CityTextureConfig.DisabledSets (the
	-- procedural window facade) are taken off the city meshes in play too, so
	-- a place that still has them installed looks right.
	local city = CityWorldService.FindCity()
	-- A global material override in MaterialService (Material Manager > "Set
	-- as override") makes every part of that base material without its own
	-- variant use it: a panels texture showed on the plain SmoothPlastic
	-- roads. The plain sets' materials and any override pointing at a
	-- facade variant are cleared.
	local plainMaterials: { [Enum.Material]: boolean } = {}
	for _, style in CityTextureConfig.PlainSets do
		plainMaterials[style.material] = true
	end
	for _, material in Enum.Material:GetEnumItems() do
		local ok, override = pcall(function()
			return MaterialService:GetBaseMaterialOverride(material)
		end)
		if ok and type(override) == "string" and override ~= "" and override ~= material.Name
			and (plainMaterials[material] or string.sub(override, 1, #Facade.VariantPrefix) == Facade.VariantPrefix) then
			local cleared = pcall(function()
				MaterialService:SetBaseMaterialOverride(material, "")
			end)
			print(string.format("[REALITY 2059] Reemplazo global de material %s -> '%s' %s", material.Name, override,
				if cleared then "quitado en Play (quítalo también en Material Manager)" else "NO se pudo quitar"))
		end
	end
	-- Roads and sidewalks: plain colour (CityTextureConfig.PlainSets).
	local plain: { [string]: any } = {}
	for setName, style in CityTextureConfig.PlainSets do
		local set = CityTextureConfig.Sets[setName]
		for _, pieceName in if set then set.pieces else {} do
			plain[pieceName] = style
		end
	end
	local darkened: { [string]: boolean } = {}
	for setName in CityTextureConfig.DisabledSets do
		local set = CityTextureConfig.Sets[setName]
		for _, pieceName in if set then set.pieces else {} do
			darkened[pieceName] = true
		end
	end
	for _, descendant in if city then city:GetDescendants() else {} do
		local textureSet = descendant:IsA("SurfaceAppearance") and descendant.Name == CityTextureConfig.InstalledName and descendant:GetAttribute("CyberTextureSet")
		if textureSet and (CityTextureConfig.DisabledSets[textureSet] or CityTextureConfig.PlainSets[textureSet]) then
			descendant:Destroy()
		elseif descendant:IsA("MeshPart") and table.find(CityTextureConfig.HiddenPieces, descendant.Name) then
			descendant.Transparency = 1
			descendant.CanQuery = false
		elseif descendant:IsA("MeshPart") and plain[descendant.Name] then
			local style = plain[descendant.Name]
			descendant.TextureID = ""
			descendant.MaterialVariant = ""
			descendant.Transparency = 0
			local drop = CityTextureConfig.PieceDrop[descendant.Name]
			if drop and not descendant:GetAttribute("Dropped") then
				descendant.CFrame -= Vector3.new(0, drop, 0)
				descendant:SetAttribute("Dropped", true)
			end
			descendant.Material = style.material
			descendant.Color = style.color
		elseif textureSet and CityTextureConfig.PlayTint[textureSet] then
			local tint = CityTextureConfig.PlayTint[textureSet]
			local base = (descendant :: SurfaceAppearance).Color
			;(descendant :: SurfaceAppearance).Color = Color3.new(base.R * tint.R, base.G * tint.G, base.B * tint.B)
		elseif descendant:IsA("MeshPart") and darkened[descendant.Name] then
			-- Tower shell parts the cladding does not cover: dark, like the cladding.
			descendant.Color = descendant.Color:Lerp(Color3.fromRGB(14, 15, 20), 0.7)
		end
	end
	-- One material per tower: the material names sorted, then shuffled with
	-- their own seed, so no two towers share a texture (26 for 26 towers).
	local materialOrder = {}
	for name in Facade.Materials do
		table.insert(materialOrder, name)
	end
	table.sort(materialOrder)
	local lookRandom = Random.new(59)
	for index = #materialOrder, 2, -1 do
		local swap = lookRandom:NextInteger(1, index)
		materialOrder[index], materialOrder[swap] = materialOrder[swap], materialOrder[index]
	end
	local dressed, clad = 0, 0
	for index, building in Buildings do
		local walls = building.walls
		if #walls == 0 then
			continue
		end
		local style = Config.Styles[order[(index - 1) % #order + 1]]
		local model = Instance.new("Model")
		model.Name = string.format("Tower%02d_%s", index, string.gsub(style.brand, "[^%w]", ""))
		model.Parent = folder
		local materialName = materialOrder[(index - 1) % #materialOrder + 1]
		-- Darken light materials to TargetBrightness, with a per-tower cool hue.
		local brightness = Facade.Materials[materialName].brightness or Facade.TargetBrightness
		local scale = math.min(1, Facade.TargetBrightness / math.max(brightness, 0.01))
		local hue = Facade.Hues[(index - 1) % #Facade.Hues + 1]
		local look = { material = materialName, tint = Color3.new(math.min(1, hue.R * scale), math.min(1, hue.G * scale), math.min(1, hue.B * scale)) }
		model:SetAttribute("FacadeMaterial", look.material)
		for _, wall in walls do
			if cladding(model, transform, wall, look) then
				clad += 1
			end
		end
		local main = walls[1]
		screen(model, transform, main, style, "main")
		edgeStrips(model, transform, main, style, index % 2 == 0)
		-- A second screen on the biggest wall facing another way.
		for _, wall in walls do
			if wall ~= main and wall[4] * main[4] + wall[5] * main[5] < 0.5 and wall[6] * transform.scale.X >= 18 then
				screen(model, transform, wall, style, "promo", Config.Promos[(index - 1) % #Config.Promos + 1])
				edgeStrips(model, transform, wall, style, false)
				break
			end
		end
		-- Rooftop sign on the widest wall that reaches the top of the tower.
		local roofWall = nil
		for _, wall in walls do
			local wallTop = wall[2] + wall[7] / 2
			if building.top - wallTop < 0.05 and wall[6] * transform.scale.X >= 16 and (not roofWall or wall[6] > roofWall[6]) then
				roofWall = wall
			end
		end
		if roofWall then
			rooftopSign(model, transform, roofWall, style)
		end
		dressed += 1
	end
	world:SetAttribute("DressedTowers", dressed)
	world:SetAttribute("CladWalls", clad)
	print(string.format("[REALITY 2059] Ciudad decorada: %d torres con pantallas, neones y letreros; %d paredes con fachada KB3D%s", dressed, clad,
		if clad == 0 then " (faltan los IDs en CityFacadeConfig)" else ""))
	return dressed
end

return CityDressingService
