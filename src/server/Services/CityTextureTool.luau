--!strict

-- STUDIO TOOL (edit mode, Command Bar) for the cyberpunk city textures.
-- SurfaceAppearance maps can only be set in Studio, so the steps are:
--   1. local T = require(game.ServerScriptService.CyberpunkOnlineServer.Services.CityTextureTool)
--      T.Prepare()   -- creates ServerStorage/TexturasCyber with 5 empty templates
--   2. Select each template and pick its images in Properties (ColorMap,
--      NormalMap, RoughnessMap, MetalnessMap for Facade/Panels) from
--      assets-source/textures/city2059_cyber; Studio uploads them.
--   3. T.Install()   -- copies the templates into the city's MeshParts
--      T.Remove()    -- takes them off again
-- Shortcut after Asset Manager > Bulk Import of the 17 images:
--      T.Setup()     -- Prepare + AutoFill (by image name) + Install
-- Every step is one undo waypoint (Ctrl+Z). Save the place afterwards.

local ServerStorage = game:GetService("ServerStorage")

local CityData = require(script.Parent.Parent.World.City2059Data)
-- Captured at require time: the Command Bar may destroy this module copy.
local worldFolder = script.Parent.Parent.World
local configModule = worldFolder.CityTextureConfig
local Config = require(configModule)
local CityWorldService = require(script.Parent.CityWorldService)

local CityTextureTool = {}

-- The Command Bar caches required modules, so edits to CityTextureConfig
-- (e.g. AssetIds) would be ignored: every tool call reads a fresh copy.
local function refreshConfig()
	local copy = configModule:Clone()
	copy.Parent = ServerStorage
	local ok, fresh = pcall(require, copy)
	copy:Destroy()
	if ok then
		Config = fresh
	end
end

local function waypoint(name: string)
	pcall(function()
		game:GetService("ChangeHistoryService"):SetWaypoint(name)
	end)
end

-- Readable in plugin context: legacy ContentId string or the newer Content.
local function mapSet(appearance: SurfaceAppearance, property: string): boolean
	local ok, value = pcall(function()
		return (appearance :: any)[property]
	end)
	if ok and type(value) == "string" and value ~= "" then
		return true
	end
	local contentOk, uri = pcall(function()
		return (appearance :: any)[property .. "Content"].Uri
	end)
	return contentOk and type(uri) == "string" and uri ~= ""
end

local function tintFor(pieceName: string): Color3
	local info = CityData.Pieces[pieceName]
	if not info then
		return Color3.new(1, 1, 1)
	end
	local c, k = info.color, Config.TintBoost
	return Color3.new(math.min(1, c.R * k), math.min(1, c.G * k), math.min(1, c.B * k))
end

function CityTextureTool.Prepare(): string
	refreshConfig()
	waypoint("Antes de preparar texturas cyber")
	local folder = ServerStorage:FindFirstChild(Config.TemplateFolder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = Config.TemplateFolder
		folder.Parent = ServerStorage
	end
	local created = 0
	for setName in Config.Sets do
		if not folder:FindFirstChild(setName) then
			local template = Instance.new("SurfaceAppearance")
			template.Name = setName
			template.Parent = folder
			created += 1
		end
	end
	waypoint("Plantillas de texturas cyber")
	local message = string.format("[REALITY 2059] %d plantillas nuevas en %s. Elige sus imágenes en Propiedades (Reality2059Cyber_<Plantilla>_<Mapa>.png) y luego ejecuta Install().", created, folder:GetFullName())
	print(message)
	return message
end

local MAP_SUFFIX = { ColorMap = "Color", NormalMap = "Normal", RoughnessMap = "Roughness", MetalnessMap = "Metalness" }

local function assign(appearance: SurfaceAppearance, property: string, url: string): boolean
	local ok = pcall(function()
		(appearance :: any)[property] = url
	end)
	if not ok then
		ok = pcall(function()
			(appearance :: any)[property .. "Content"] = (Content :: any).fromUri(url)
		end)
	end
	return ok
end

-- Numeric image id for an imported file name (without .png): first the
-- table in CityTextureConfig.AssetIds, then the Asset Manager aliases
-- (Bulk Import names them Images/<file name>). SurfaceAppearance only
-- accepts rbxassetid://<number>; rbxgameasset:// is rejected.
local ALIAS_METHODS = { "GetImageIdFromAliasName", "GetTextureIdFromAliasName", "GetAssetIdFromAliasName", "GetMeshIdFromAliasName" }
local resolverReport: { string } = {}

local function resolveImageId(fileName: string): number?
	local manual = Config.AssetIds and Config.AssetIds[fileName]
	if type(manual) == "number" and manual > 0 then
		return manual
	end
	local okService, assetManager = pcall(function()
		return game:GetService("AssetManagerService")
	end)
	if not okService or not assetManager then
		return nil
	end
	for _, method in ALIAS_METHODS do
		for _, alias in { "Images/" .. fileName, fileName } do
			local ok, result = pcall(function()
				return (assetManager :: any)[method](assetManager, alias)
			end)
			local id = if ok then tonumber(result) else nil
			if id and id > 0 then
				if not table.find(resolverReport, method) then
					table.insert(resolverReport, method)
				end
				return id
			end
		end
	end
	return nil
end

-- Fills every template with the imported images (by file name), then
-- checks that each map is really set and loads. force = true overwrites
-- maps that were already picked by hand.
function CityTextureTool.AutoFill(force: boolean?): string
	refreshConfig()
	CityTextureTool.Prepare()
	local folder = ServerStorage:FindFirstChild(Config.TemplateFolder) :: Instance
	waypoint("Antes de llenar texturas cyber")
	table.clear(resolverReport)
	local filled, kept = 0, 0
	local missing: { string } = {}
	local expected: { [string]: string } = {}
	for setName in Config.Sets do
		local template = folder:FindFirstChild(setName) :: SurfaceAppearance
		for _, property in Config.Maps do
			if property == "MetalnessMap" and not Config.MetallicSets[setName] then
				continue
			end
			if mapSet(template, property) and not force then
				kept += 1
				continue
			end
			local fileName = string.format("Reality2059Cyber_%s_%s", setName, MAP_SUFFIX[property])
			local id = resolveImageId(fileName)
			if not id then
				table.insert(missing, fileName)
				continue
			end
			local url = "rbxassetid://" .. id
			if assign(template, property, url) and mapSet(template, property) then
				filled += 1
				expected[url] = setName .. "." .. property
			else
				table.insert(missing, fileName .. " (Roblox rechazó " .. url .. ")")
			end
		end
	end
	waypoint("Texturas cyber llenadas")
	-- Verify: preload the templates and report every image that did not load.
	local failed = {}
	pcall(function()
		game:GetService("ContentProvider"):PreloadAsync(folder:GetChildren(), function(contentId: string, status: Enum.AssetFetchStatus)
			if status ~= Enum.AssetFetchStatus.Success then
				table.insert(failed, (expected[contentId] or contentId) .. " (" .. status.Name .. ")")
			end
		end)
	end)
	local message = string.format("[REALITY 2059] Mapas asignados: %d, ya tenían imagen: %d, sin ID: %d.", filled, kept, #missing)
	if #resolverReport > 0 then
		message ..= " IDs leídos del Asset Manager con " .. table.concat(resolverReport, ", ") .. "."
	end
	if #missing > 0 then
		message ..= " FALTAN: " .. table.concat(missing, ", ")
			.. ". Copia su ID (Toolbox > Inventario > Mis imágenes, clic derecho > Copiar ID) en src/server/World/CityTextureConfig.luau > AssetIds y vuelve a ejecutar."
	end
	if #failed > 0 then
		message ..= " NO CARGARON: " .. table.concat(failed, ", ") .. "."
	end
	if #missing > 0 or #failed > 0 then
		warn(message)
	else
		message ..= " Todas cargaron."
		print(message)
	end
	return message
end

-- Prepare + AutoFill + Install in one call.
function CityTextureTool.Setup(): string
	CityTextureTool.AutoFill()
	return CityTextureTool.Install()
end

function CityTextureTool.Install(): string
	refreshConfig()
	local city = CityWorldService.FindCity()
	if not city then
		warn("[REALITY 2059] No encontré la ciudad en Workspace")
		return "CITY_MISSING"
	end
	local folder = ServerStorage:FindFirstChild(Config.TemplateFolder)
	if not folder then
		warn("[REALITY 2059] Falta ServerStorage." .. Config.TemplateFolder .. ": ejecuta Prepare() primero")
		return "TEMPLATES_MISSING"
	end
	local byName: { [string]: MeshPart } = {}
	for _, descendant in city:GetDescendants() do
		if descendant:IsA("MeshPart") and CityData.Pieces[descendant.Name] then
			byName[descendant.Name] = descendant
		end
	end
	waypoint("Antes de instalar texturas cyber")
	local installed, skipped = 0, {}
	for setName, set in Config.Sets do
		if Config.DisabledSets and Config.DisabledSets[setName] then
			continue
		end
		local template = folder:FindFirstChild(setName)
		if not template or not template:IsA("SurfaceAppearance") or not mapSet(template, "ColorMap") then
			table.insert(skipped, setName .. " (sin ColorMap)")
			continue
		end
		for _, property in Config.Maps do
			local needed = property ~= "MetalnessMap" or Config.MetallicSets[setName]
			if needed and not mapSet(template, property) then
				warn(string.format("[REALITY 2059] %s no tiene %s; se instala sin ese mapa", setName, property))
			end
		end
		for _, pieceName in set.pieces do
			local part = byName[pieceName]
			if not part then
				table.insert(skipped, pieceName .. " (no está en la ciudad)")
				continue
			end
			for _, child in part:GetChildren() do
				if child:IsA("SurfaceAppearance") and child.Name == Config.InstalledName then
					child:Destroy()
				end
			end
			local copy = template:Clone()
			copy.Name = Config.InstalledName
			copy.Color = if set.tint then tintFor(pieceName) else Color3.new(1, 1, 1)
			copy:SetAttribute("CyberTextureSet", setName)
			copy.Parent = part
			installed += 1
		end
	end
	waypoint("Texturas cyber instaladas")
	local message = string.format("[REALITY 2059] Texturas cyber instaladas en %d mallas.%s", installed,
		if #skipped > 0 then " Omitidas: " .. table.concat(skipped, ", ") else "")
	print(message)
	return message
end

function CityTextureTool.Remove(): string
	refreshConfig()
	local city = CityWorldService.FindCity()
	if not city then
		return "CITY_MISSING"
	end
	waypoint("Antes de quitar texturas cyber")
	local removed = 0
	for _, descendant in city:GetDescendants() do
		if descendant:IsA("SurfaceAppearance") and descendant.Name == Config.InstalledName then
			descendant:Destroy()
			removed += 1
		end
	end
	waypoint("Texturas cyber quitadas")
	local message = string.format("[REALITY 2059] %d texturas cyber quitadas", removed)
	print(message)
	return message
end

-- KitBash3D facade materials (CityFacadeConfig) as MaterialVariants in
-- MaterialService, which CityDressingService applies to each tower's
-- cladding at runtime. Studio itself reports ids that do not exist ("Failed
-- to upload TexturePack ... NOT found"). verify = true also checks every id's
-- asset name with MarketplaceService (4 s timeout each: in edit mode the call
-- can hang). Reads the config fresh (the Command Bar caches modules).
function CityTextureTool.InstallFacades(verify: boolean?): string
	local copy = worldFolder.CityFacadeConfig:Clone()
	copy.Parent = ServerStorage
	local ok, facade = pcall(require, copy)
	copy:Destroy()
	if not ok then
		warn("[REALITY 2059] CityFacadeConfig no se pudo leer: " .. tostring(facade))
		return "CONFIG_ERROR"
	end
	local MaterialService = game:GetService("MaterialService")
	local MarketplaceService = game:GetService("MarketplaceService")
	local function verified(key: string): (number?, string?)
		local id = facade.AssetIds[key]
		if type(id) ~= "number" or id <= 0 then
			return nil, key .. " (sin ID)"
		end
		if not verify then
			return id, nil
		end
		local done, infoOk, info = false, false, nil
		task.spawn(function()
			infoOk, info = pcall(function()
				return MarketplaceService:GetProductInfo(id)
			end)
			done = true
		end)
		local deadline = os.clock() + 4
		while not done and os.clock() < deadline do
			task.wait(0.1)
		end
		if not done then
			return id, nil -- no answer from Roblox: install it unverified
		end
		if not infoOk or type(info) ~= "table" then
			return nil, key .. " (ID " .. id .. " no existe)"
		end
		if string.lower(tostring(info.Name)) ~= string.lower(key) then
			return nil, key .. " (ID " .. id .. " es '" .. tostring(info.Name) .. "')"
		end
		return id, nil
	end
	waypoint("Antes de instalar fachadas KB3D")
	local total, installed, problems = 0, 0, {}
	for name, material in facade.Materials do
		total += 1
		local ids = {}
		for suffix, kb3d in { Color = "basecolor", Normal = "normal", Roughness = "roughness" } do
			local id, problem = verified("KB3D_NEC_" .. name .. "_" .. kb3d)
			if id then
				ids[suffix] = id
			else
				table.insert(problems, problem :: string)
			end
		end
		if not ids.Color then
			continue
		end
		local variantName = facade.VariantPrefix .. name
		local variant = MaterialService:FindFirstChild(variantName)
		if not variant then
			variant = Instance.new("MaterialVariant")
			variant.Name = variantName
			variant.Parent = MaterialService
		end
		local mv = variant :: MaterialVariant
		mv.BaseMaterial = material.base
		mv.StudsPerTile = material.studsPerTile
		for suffix, property in { Color = "ColorMap", Normal = "NormalMap", Roughness = "RoughnessMap" } do
			if ids[suffix] and not assign(mv :: any, property, "rbxassetid://" .. ids[suffix]) then
				table.insert(problems, variantName .. "." .. property .. " (Roblox lo rechazó)")
			end
		end
		installed += 1
	end
	waypoint("Fachadas KB3D instaladas")
	local message = string.format("[REALITY 2059] Materiales de fachada instalados: %d de %d.", installed, total)
	if #problems > 0 then
		message ..= " REVISAR: " .. table.concat(problems, ", ")
		warn(message)
	else
		message ..= if verify then " Todos los IDs verificados. Guarda el lugar y da Play." else " Si Studio muestra \"Failed to upload TexturePack\", copia ese ID aquí. Guarda el lugar y da Play."
		print(message)
	end
	return message
end

-- Forces Studio to repackage and upload every R2059_KB3D_ MaterialVariant
-- ("Failed to upload TexturePack ... Change a TextureId property to retry"):
-- each map is cleared and set again. Watch Output for TexturePack errors.
function CityTextureTool.RetryFacadeUpload(): string
	local MaterialService = game:GetService("MaterialService")
	waypoint("Antes de reintentar texturas KB3D")
	local retried = 0
	for _, variant in MaterialService:GetChildren() do
		if variant:IsA("MaterialVariant") and string.sub(variant.Name, 1, 11) == "R2059_KB3D_" then
			for _, property in { "ColorMap", "NormalMap", "RoughnessMap" } do
				local ok, value = pcall(function()
					return (variant :: any)[property]
				end)
				if ok and type(value) == "string" and value ~= "" then
					assign(variant :: any, property, "")
					task.wait()
					assign(variant :: any, property, value)
				end
			end
			retried += 1
		end
	end
	waypoint("Texturas KB3D reintentadas")
	local message = string.format("[REALITY 2059] Subida de texturas reintentada en %d materiales. Espera ~30 s y revisa si aparece 'Failed to upload TexturePack'.", retried)
	print(message)
	return message
end

-- Edit-mode check: a row of 16-stud panels (one per facade material) in
-- front of the camera, so the textures can be seen without Play. Remove
-- them with TestFacades(false).
function CityTextureTool.TestFacades(show: boolean?): string
	local MaterialService = game:GetService("MaterialService")
	local existing = workspace:FindFirstChild("R2059_FacadeTest")
	if existing then
		existing:Destroy()
	end
	if show == false then
		return "removed"
	end
	local folder = Instance.new("Model")
	folder.Name = "R2059_FacadeTest"
	folder.Parent = workspace
	local camera = workspace.CurrentCamera
	local origin = camera.CFrame * CFrame.new(0, 0, -90)
	local names = {}
	for _, variant in MaterialService:GetChildren() do
		if variant:IsA("MaterialVariant") and string.sub(variant.Name, 1, 11) == "R2059_KB3D_" then
			table.insert(names, variant)
		end
	end
	table.sort(names, function(a, b)
		return a.Name < b.Name
	end)
	for index, variant in names do
		local column, row = (index - 1) % 9, math.floor((index - 1) / 9)
		local panel = Instance.new("Part")
		panel.Name = variant.Name
		panel.Anchored = true
		panel.Size = Vector3.new(16, 16, 1)
		panel.CFrame = origin * CFrame.new((column - 4) * 18, (1 - row) * 18, 0)
		panel.Material = (variant :: MaterialVariant).BaseMaterial
		panel.MaterialVariant = variant.Name
		panel.Parent = folder
	end
	local message = string.format("[REALITY 2059] %d paneles de prueba frente a la cámara (R2059_FacadeTest). Quítalos con TestFacades(false).", #names)
	print(message)
	return message
end

return CityTextureTool
