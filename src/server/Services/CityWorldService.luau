--!strict

-- Makes City2059 playable for MODO LIBRE. Runtime only (the saved place is
-- never changed): the imported city is found, optionally scaled and placed at
-- CityCenter, gets back the glTF colours the importer dropped,
-- and loses its mesh collision in favour of generated invisible boxes
-- (World/City2059Data). A ground plane, edge walls and spawn spots are built
-- in Workspace/Reality2059Runtime/FreeRoam. Runs before the lobby, which is
-- placed in front of the city.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MaterialService = game:GetService("MaterialService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local MorphLabConfig = require(root.Config.MorphLabConfig)
local Config = require(root.Config.FreeRoamConfig)
local CityData = require(script.Parent.Parent.World.City2059Data)
local CityMaterialConfig = require(script.Parent.Parent.World.CityMaterialConfig)

local CityWorldService = {}

-- Set by Build() when the city is found: glTF point -> world, plus the scale,
-- the part rotation and the importer's axis signs.
CityWorldService.Transform = nil :: any

local function invisiblePart(parent: Instance, name: string, size: Vector3, cframe: CFrame): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Anchored = true
	item.Size = size
	item.CFrame = cframe
	item.Transparency = 1
	item.CastShadow = false
	item.CanTouch = false
	item.TopSurface = Enum.SurfaceType.Smooth
	item.BottomSurface = Enum.SurfaceType.Smooth
	item.Parent = parent
	return item
end

local function countCityMeshes(container: Instance): number
	local count = 0
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("MeshPart") and CityData.MeshCenters[descendant.Name] then
			count += 1
		end
	end
	return count
end

-- The city may have been imported under another name (e.g. "Scene") and may
-- sit inside folders: it is the smallest model around the reference tower
-- mesh that holds every city mesh found in Workspace.
function CityWorldService.FindCity(): (Model?, MeshPart?)
	local named = Workspace:FindFirstChild(Config.CityModelName, true)
	local reference = named and named:FindFirstChild(CityData.ReferenceMesh, true)
	if not reference then
		for _, descendant in Workspace:GetDescendants() do
			if descendant.Name == CityData.ReferenceMesh and descendant:IsA("MeshPart") then
				reference = descendant
				break
			end
		end
	end
	if not reference or not reference:IsA("MeshPart") then
		return nil, nil
	end
	local total = countCityMeshes(Workspace)
	local best: Model? = nil
	local ancestor = reference.Parent
	while ancestor and ancestor ~= Workspace do
		if ancestor:IsA("Model") then
			best = ancestor
			if countCityMeshes(ancestor) >= total then
				break
			end
		end
		ancestor = ancestor.Parent
	end
	if not best then
		return nil, nil
	end
	return best, reference
end

local function inCollisionFolder(part: Instance, city: Model): boolean
	local ancestor = part.Parent
	while ancestor and ancestor ~= city do
		if ancestor.Name == Config.CollisionFolderName then
			return true
		end
		ancestor = ancestor.Parent
	end
	return false
end

-- Import default: grey plastic. Anything else was edited in Studio and is kept.
local IMPORT_GREY = Color3.fromRGB(163, 162, 165)
local function isImportDefault(part: BasePart): boolean
	local color = part.Color
	return part.Material == Enum.Material.Plastic
		and math.abs(color.R - IMPORT_GREY.R) < 0.01 and math.abs(color.G - IMPORT_GREY.G) < 0.01 and math.abs(color.B - IMPORT_GREY.B) < 0.01
end

-- How the importer oriented the geometry inside the parts: the Roblox
-- importer bakes a 180-degree turn (X and Z negated) into the vertices while
-- the parts keep an identity rotation. Every axis sign is measured from where
-- the other meshes actually sit relative to the reference.
local function measureAxisSigns(city: Model, reference: MeshPart, scale: Vector3): Vector3
	local sums = Vector3.zero
	for _, descendant in city:GetDescendants() do
		local center = descendant:IsA("MeshPart") and descendant ~= reference and CityData.MeshCenters[descendant.Name]
		if center then
			local expected = (center - CityData.ReferenceCenter) * scale
			local actual = reference.CFrame:PointToObjectSpace(descendant.Position)
			sums += expected * actual
		end
	end
	return Vector3.new(if sums.X < 0 then -1 else 1, if sums.Y < 0 then -1 else 1, if sums.Z < 0 then -1 else 1)
end

-- glTF point -> world, through the reference mesh's box (handles any import
-- position, rotation, scale and the importer's turn).
local function makeTransform(city: Model, reference: MeshPart)
	local scale = reference.Size / CityData.ReferenceSize
	local frame = reference.CFrame
	local signs = measureAxisSigns(city, reference, scale)
	return function(point: Vector3): Vector3
		return frame * ((point - CityData.ReferenceCenter) * scale * signs)
	end, scale, frame.Rotation, signs
end

local PBR_READY_ATTRIBUTE = "Reality2059PBRReady"
local PBR_ROLE_ATTRIBUTE = "Reality2059MaterialRole"

local function findMaterialVariant(roleName: string, role): MaterialVariant?
	local candidate = MaterialService:FindFirstChild(role.variantName, true)
	if candidate and candidate:IsA("MaterialVariant") then
		-- Map IDs are PluginSecurity fields and cannot be inspected by a server
		-- Script. The Studio import step marks a fully reviewed variant explicitly;
		-- an unmarked or partially imported object must stay on the native fallback.
		if candidate:GetAttribute(PBR_READY_ATTRIBUTE) ~= true
			or candidate:GetAttribute(PBR_ROLE_ATTRIBUTE) ~= roleName then
			warn(string.format(
				"[REALITY 2059] MaterialVariant %s no está marcado como PBR listo para %s. Se usará el material nativo.",
				candidate.Name, roleName
			))
			return nil
		end
		if candidate.BaseMaterial ~= role.baseMaterial
			or math.abs(candidate.StudsPerTile - role.studsPerTile) > 0.01 then
			warn(string.format(
				"[REALITY 2059] MaterialVariant %s tiene material base o escala de mosaico incorrectos. Se usará el material nativo.",
				candidate.Name
			))
			return nil
		end
		return candidate
	end
	return nil
end

local function applyMaterialRole(part: BasePart, roleName: string): boolean
	local role = CityMaterialConfig.Roles[roleName]
	if not role then
		return false
	end

	-- A deliberately authored SurfaceAppearance wins over the city-wide pack.
	-- The current import has none on these groups, but this keeps future Blender
	-- reimports extensible without destroying artist work.
	if part:FindFirstChildOfClass("SurfaceAppearance") then
		part:SetAttribute("CityMaterialRole", roleName)
		part:SetAttribute("CityMaterialSource", "SURFACE_APPEARANCE")
		return true
	end

	local variant = findMaterialVariant(roleName, role)
	if variant then
		part.Material = role.baseMaterial
		part.MaterialVariant = variant.Name
		part:SetAttribute("CityMaterialSource", "PBR")
	else
		part.Material = role.fallbackMaterial
		part.MaterialVariant = ""
		part:SetAttribute("CityMaterialSource", "BUILTIN_FALLBACK")
	end
	part:SetAttribute("CityMaterialRole", roleName)

	-- The source package only supplied a white 1x1 placeholder on the mapped
	-- textured group. Preserve its ID as metadata before allowing the selected
	-- Roblox material to render. The three ambiguous alpha/UV groups are not
	-- mapped and therefore remain untouched.
	if part:IsA("MeshPart") and part.TextureID ~= "" then
		if part:GetAttribute("CityOriginalTextureID") == nil then
			part:SetAttribute("CityOriginalTextureID", part.TextureID)
		end
		part.TextureID = ""
	end

	return variant ~= nil
end

local function applyMaterials(city: Model): (number, number, number, number)
	local styled, collision, pbr, fallback = 0, 0, 0, 0
	for _, descendant in city:GetDescendants() do
		if descendant:IsA("BasePart") and inCollisionFolder(descendant, city) then
			-- Hand-made collision: solid and invisible in play.
			descendant.Anchored = true
			descendant.CanCollide = true
			descendant.CanQuery = true
			descendant.CanTouch = false
			descendant.CastShadow = false
			descendant.Transparency = 1
			descendant.MaterialVariant = ""
			collision += 1
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			local pieceName = if CityData.Pieces[descendant.Name] then descendant.Name
				elseif descendant.Parent and CityData.Pieces[descendant.Parent.Name] then descendant.Parent.Name
				else nil
			local info = pieceName and CityData.Pieces[pieceName] or nil
			local materialRole = pieceName and CityMaterialConfig.PieceRoles[pieceName] or nil
			local preserveStudioColor = info and info.kind == "solid" and not isImportDefault(descendant)
			if info then
				styled += 1
				if info.kind == "solid" then
					if not preserveStudioColor then
						descendant.Color = info.color
					end
					if not materialRole then
						descendant.Material = info.material
						descendant.MaterialVariant = ""
					end
				elseif info.kind == "emissive" then
					descendant.Color = info.color
					descendant.Material = Enum.Material.Neon
					descendant.MaterialVariant = ""
					descendant.CastShadow = false
					-- White emissive pieces are the windows (day/night on the client).
					local white = info.color.R > 0.9 and info.color.G > 0.9 and info.color.B > 0.9
					descendant:SetAttribute(if white then "CityWindow" else "CityGlow", true)
					descendant:SetAttribute("GlowColor", info.color)
				end
				-- Unmapped textured groups keep their imported TextureID.
			end
			if materialRole then
				if applyMaterialRole(descendant, materialRole) then
					pbr += 1
				else
					fallback += 1
				end
			end
		end
	end
	return styled, collision, pbr, fallback
end

function CityWorldService.Build(): Model
	local runtime = Workspace:FindFirstChild(MorphLabConfig.RuntimeFolderName)
	if not runtime then
		runtime = Instance.new("Folder")
		runtime.Name = MorphLabConfig.RuntimeFolderName
		runtime.Parent = Workspace
	end
	local existing = runtime:FindFirstChild(Config.ModelName)
	if existing then
		existing:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = Config.ModelName
	-- StreamingEnabled: the ground must be there before any character (lobby view).
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model:SetAttribute("GeneratedBy", "CityWorldService")
	model:SetAttribute("SceneVersion", Config.SceneVersion)

	-- The template Baseplate (grid texture, top at y = 0) sits exactly at the
	-- city floor once the city is centred at CityCenter and shows its grid
	-- over roads and sidewalks. Free roam has its own ground: remove it in play.
	local baseplate = Workspace:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		baseplate:Destroy()
		print("[REALITY 2059] Baseplate de la plantilla quitado en Play (tapaba el piso de la ciudad)")
	end

	local city, reference = CityWorldService.FindCity()
	model:SetAttribute("CityFound", city ~= nil)
	local toWorld, scale, rotation
	if city and reference then
		if city.Name ~= Config.CityModelName then
			city.Name = Config.CityModelName
		end
		-- Seen from the lobby with no character nearby, and the client needs
		-- every window for the day/night cycle: always replicate it.
		city.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		-- Nested models too, with no level-of-detail swap: far walls were
		-- streamed or simplified away mid-view in the menus.
		for _, descendant in city:GetDescendants() do
			if descendant:IsA("Model") then
				descendant.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
				pcall(function()
					(descendant :: any).LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
				end)
			end
		end
		pcall(function()
			(city :: any).LevelOfDetail = Enum.ModelLevelOfDetail.Disabled
		end)
		local currentScale = reference.Size.X / CityData.ReferenceSize.X
		if Config.RescaleCity and math.abs(currentScale - Config.CityScale) / Config.CityScale > 0.01 then
			city:ScaleTo(city:GetScale() * Config.CityScale / currentScale)
		end
		toWorld = makeTransform(city, reference)
		if Config.RepositionCity then
			local floorCenter = Vector3.new(
				(CityData.BoundsMin.X + CityData.BoundsMax.X) * 0.5,
				CityData.FloorY,
				(CityData.BoundsMin.Z + CityData.BoundsMax.Z) * 0.5
			)
			city:PivotTo(city:GetPivot() + (Config.CityCenter - toWorld(floorCenter)))
		end
		local signs
		toWorld, scale, rotation, signs = makeTransform(city, reference)
		-- Shared with CityDressingService (signs, billboards on the real walls).
		CityWorldService.Transform = { toWorld = toWorld, scale = scale, rotation = rotation, signs = signs }
		model:SetAttribute("CityAxisSigns", signs)
		-- glTF -> world for the client (street network of the city life):
		-- world = CityRefFrame * ((p - CityRefCenter) * CityScaleVector * CityAxisSigns).
		model:SetAttribute("CityRefFrame", reference.CFrame)
		model:SetAttribute("CityRefCenter", CityData.ReferenceCenter)
		model:SetAttribute("CityScaleVector", scale)
		local styled, collision, pbr, fallback = applyMaterials(city)
		model:SetAttribute("StyledParts", styled)
		model:SetAttribute("HandmadeColliders", collision)
		model:SetAttribute("PBRMaterialParts", pbr)
		model:SetAttribute("FallbackMaterialParts", fallback)
		print(string.format("[REALITY 2059] Ciudad '%s' lista: escala %.1f, centro %s, %d piezas estilizadas, materiales PBR=%d/fallback=%d, %d colisiones hechas a mano", city:GetFullName(), scale.X, tostring(toWorld(Vector3.new((CityData.BoundsMin.X + CityData.BoundsMax.X) * 0.5, CityData.FloorY, (CityData.BoundsMin.Z + CityData.BoundsMax.Z) * 0.5))), styled, pbr, fallback, collision))
	else
		warn("[REALITY 2059] City2059 not found in Workspace; free roam uses the bare ground")
		local fallbackScale = Config.CityScale
		scale = Vector3.one * fallbackScale
		rotation = CFrame.identity
		toWorld = function(point: Vector3): Vector3
			return Config.CityCenter + (point - Vector3.new(
				(CityData.BoundsMin.X + CityData.BoundsMax.X) * 0.5,
				CityData.FloorY,
				(CityData.BoundsMin.Z + CityData.BoundsMax.Z) * 0.5
			)) * fallbackScale
		end
	end

	-- Ground: top a hair below the city slab so the two never z-fight.
	local floorWorld = toWorld(Vector3.new(
		(CityData.BoundsMin.X + CityData.BoundsMax.X) * 0.5,
		CityData.FloorY,
		(CityData.BoundsMin.Z + CityData.BoundsMax.Z) * 0.5
	))
	local ground = Config.Ground
	local groundTop = floorWorld.Y - 0.12

	-- Street-level slabs from collision data v5 and older are covered by the
	-- ground plane; dropping them in play saves ~2,400 physics parts without
	-- regenerating the place (data v6 no longer emits them).
	local pruned = 0
	if city then
		local folder = city:FindFirstChild(Config.CollisionFolderName)
		local limit = floorWorld.Y + 0.01 * scale.Y + 0.05
		for _, descendant in if folder then folder:GetDescendants() else {} do
			if descendant:IsA("BasePart") and descendant:GetAttribute("CollisionKind") == "Surface"
				and descendant.Position.Y + descendant.Size.Y * 0.5 < limit then
				descendant:Destroy()
				pruned += 1
			end
		end
		if pruned > 0 then
			print(string.format("[REALITY 2059] %d superficies a ras de calle quitadas (las cubre el piso)", pruned))
		end
	end
	model:SetAttribute("PrunedStreetSurfaces", pruned)
	local groundPart = Instance.new("Part")
	groundPart.Name = "Ground"
	groundPart.Anchored = true
	groundPart.Size = Vector3.new(ground.Size, ground.Thickness, ground.Size)
	groundPart.CFrame = CFrame.new(floorWorld.X, groundTop - ground.Thickness * 0.5, floorWorld.Z) * rotation
	groundPart.Color = ground.Color
	groundPart.Material = ground.Material
	local groundVariant = findMaterialVariant("Asphalt", CityMaterialConfig.Roles.Asphalt)
	if groundVariant then
		groundPart.Material = CityMaterialConfig.Roles.Asphalt.baseMaterial
		groundPart.MaterialVariant = groundVariant.Name
		groundPart:SetAttribute("CityMaterialRole", "Asphalt")
		groundPart:SetAttribute("CityMaterialSource", "PBR")
	else
		groundPart.MaterialVariant = ""
		groundPart:SetAttribute("CityMaterialRole", "Asphalt")
		groundPart:SetAttribute("CityMaterialSource", "BUILTIN_FALLBACK")
	end
	groundPart.TopSurface = Enum.SurfaceType.Smooth
	groundPart.Parent = model
	for index, offset in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local along = Vector3.new(math.abs(offset.Z), 0, math.abs(offset.X))
		local size = along * ground.Size + Vector3.new(0, ground.WallHeight, 0) + Vector3.new(math.abs(offset.X), 0, math.abs(offset.Z)) * 4
		local center = CFrame.new(floorWorld.X, groundTop + ground.WallHeight * 0.5, floorWorld.Z) * rotation * CFrame.new(offset * ground.Size * 0.5)
		invisiblePart(model, "EdgeWall" .. index, size, center)
	end

	-- Collision boxes (city coordinates -> world).
	local colliders = Instance.new("Folder")
	colliders.Name = "Colliders"
	colliders.Parent = model
	for _, box in if Config.GeneratedColliders then CityData.Colliders else {} do
		local center = toWorld(Vector3.new(box[1], box[2], box[3]))
		local size = Vector3.new(box[4], box[5], box[6]) * scale
		invisiblePart(colliders, "Collider", size, CFrame.new(center) * rotation)
	end
	for _, box in if Config.GeneratedColliders then CityData.SurfaceColliders else {} do
		local center = toWorld(Vector3.new(box[1], box[2], box[3]))
		local size = Vector3.new(box[4], box[5], box[6]) * scale
		invisiblePart(colliders, "SurfaceCollider", size, CFrame.new(center) * rotation)
	end

	-- Spawn spots, facing the city centre.
	local spawns = Instance.new("Folder")
	spawns.Name = "Spawns"
	spawns.Parent = model
	for index, spot in CityData.Spawns do
		local position = toWorld(spot)
		local toCenter = Vector3.new(floorWorld.X - position.X, 0, floorWorld.Z - position.Z)
		local facing = if toCenter.Magnitude > 1 then toCenter.Unit else Vector3.new(0, 0, -1)
		local marker = invisiblePart(spawns, "Spawn" .. index, Vector3.new(4, 0.2, 4), CFrame.lookAt(position, position + facing))
		marker.CanCollide = false
		marker.CanQuery = false
	end

	model:SetAttribute("CityScale", scale.X)
	model:SetAttribute("ColliderCount", #colliders:GetChildren())
	model:SetAttribute("FloorY", floorWorld.Y)
	model.Parent = runtime
	return model
end

-- STUDIO TOOL (edit mode, Command Bar):
--   require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityWorldService).GenerateEditableCollision()
-- Writes the generated collision boxes as visible, editable Parts into
-- City2059/Colisiones at the city's current size and position, so they are
-- saved with the place and can be moved, resized, deleted or added to by
-- hand. Earlier generated boxes are replaced; Parts made by hand (without the
-- GeneratedCollision attribute) are never touched. Undo with Ctrl+Z.
function CityWorldService.GenerateEditableCollision(): string
	local city, reference = CityWorldService.FindCity()
	if not city or not reference then
		warn("[REALITY 2059] No encontré la ciudad en Workspace")
		return "CITY_MISSING"
	end
	local ChangeHistoryService = game:GetService("ChangeHistoryService")
	pcall(function()
		ChangeHistoryService:SetWaypoint("Antes de generar colisiones")
	end)
	local folder = city:FindFirstChild(Config.CollisionFolderName)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.CollisionFolderName
		folder.Parent = city
	end
	local removed = 0
	for _, child in folder:GetDescendants() do
		if child:IsA("BasePart") and child:GetAttribute("GeneratedCollision") then
			child:Destroy()
			removed += 1
		end
	end
	local visualMeshesDisabled = 0
	for _, descendant in city:GetDescendants() do
		if descendant:IsA("MeshPart") and not inCollisionFolder(descendant, city) then
			if descendant.CanCollide then
				visualMeshesDisabled += 1
			end
			descendant.CanCollide = false
			descendant.CanTouch = false
		end
	end
	local structures = folder:FindFirstChild("Estructuras")
	if not structures then
		structures = Instance.new("Folder")
		structures.Name = "Estructuras"
		structures.Parent = folder
	end
	local surfaces = folder:FindFirstChild("Superficies")
	if not surfaces then
		surfaces = Instance.new("Folder")
		surfaces.Name = "Superficies"
		surfaces.Parent = folder
	end
	local toWorld, scale, rotation = makeTransform(city, reference)
	local function createCollider(box: { number }, index: number, kind: string, parent: Instance, color: Color3)
		local item = Instance.new("Part")
		item.Name = if kind == "Surface" then "Superficie" else "Estructura"
		item.Anchored = true
		item.CanCollide = true
		item.CanQuery = true
		item.CanTouch = false
		item.Massless = true
		item.CastShadow = false
		item.Material = Enum.Material.SmoothPlastic
		item.Color = color
		item.Transparency = 0.6
		item.TopSurface = Enum.SurfaceType.Smooth
		item.BottomSurface = Enum.SurfaceType.Smooth
		item.Size = Vector3.new(box[4], box[5], box[6]) * scale
		item.CFrame = CFrame.new(toWorld(Vector3.new(box[1], box[2], box[3]))) * rotation
		item:SetAttribute("GeneratedCollision", true)
		item:SetAttribute("CollisionVersion", CityData.CollisionVersion)
		item:SetAttribute("CollisionKind", kind)
		item:SetAttribute("Index", index)
		item.Parent = parent
	end
	for index, box in CityData.Colliders do
		createCollider(box, index, "Structure", structures, Color3.fromRGB(255, 40, 80))
	end
	for index, box in CityData.SurfaceColliders do
		createCollider(box, index, "Surface", surfaces, Color3.fromRGB(0, 220, 255))
	end
	pcall(function()
		ChangeHistoryService:SetWaypoint("Colisiones generadas")
	end)
	local message = string.format(
		"[REALITY 2059] %d colisiones generadas (%d estructuras + %d superficies) en %s (%d anteriores reemplazadas, %d mallas visuales desactivadas)",
		#CityData.Colliders + #CityData.SurfaceColliders, #CityData.Colliders, #CityData.SurfaceColliders,
		folder:GetFullName(), removed, visualMeshesDisabled
	)
	print(message)
	return message
end

export type CollisionAudit = {
	status: string,
	total: number,
	generated: number,
	manual: number,
	invalid: number,
	visualMeshBlockers: number,
}

-- STUDIO TOOL (edit mode, Command Bar):
--   require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityWorldService).AuditEditableCollision()
-- Read-only audit. It never creates, moves or removes Instances.
function CityWorldService.AuditEditableCollision(): CollisionAudit
	local city = CityWorldService.FindCity()
	if not city then
		local missing = {
			status = "CITY_MISSING",
			total = 0,
			generated = 0,
			manual = 0,
			invalid = 0,
			visualMeshBlockers = 0,
		}
		warn("[REALITY 2059] Auditoría de colisiones: ciudad no encontrada")
		return missing
	end

	local folder = city:FindFirstChild(Config.CollisionFolderName)
	local total, generated, manual, invalid, visualMeshBlockers = 0, 0, 0, 0, 0
	for _, descendant in city:GetDescendants() do
		if descendant:IsA("BasePart") then
			if inCollisionFolder(descendant, city) then
				total += 1
				if descendant:GetAttribute("GeneratedCollision") then
					generated += 1
				else
					manual += 1
				end
				if not descendant.Anchored or not descendant.CanCollide
					or descendant.Size.X <= 0 or descendant.Size.Y <= 0 or descendant.Size.Z <= 0 then
					invalid += 1
					warn("[REALITY 2059] Colisión inválida: " .. descendant:GetFullName())
				end
			elseif descendant:IsA("MeshPart") and descendant.CanCollide then
				visualMeshBlockers += 1
				warn("[REALITY 2059] Mesh visual con CanCollide=true: " .. descendant:GetFullName())
			end
		end
	end
	local status = if not folder then "COLLISION_FOLDER_MISSING"
		elseif total == 0 then "NO_COLLIDERS"
		elseif invalid > 0 or visualMeshBlockers > 0 then "ISSUES_FOUND"
		else "OK"
	local result = {
		status = status,
		total = total,
		generated = generated,
		manual = manual,
		invalid = invalid,
		visualMeshBlockers = visualMeshBlockers,
	}
	print(string.format(
		"[REALITY 2059] Auditoría: %s | total=%d, generadas=%d, manuales=%d, inválidas=%d, meshes visuales bloqueando=%d",
		status, total, generated, manual, invalid, visualMeshBlockers
	))
	return result
end

-- STUDIO TOOL: shows (0.6) or hides (1) the collision Parts while editing.
function CityWorldService.SetCollisionVisible(visible: boolean)
	local city = CityWorldService.FindCity()
	local folder = city and city:FindFirstChild(Config.CollisionFolderName)
	for _, child in if folder then folder:GetDescendants() else {} do
		if child:IsA("BasePart") then
			child.Transparency = if visible then 0.6 else 1
		end
	end
end

return CityWorldService
