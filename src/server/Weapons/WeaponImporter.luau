--!strict

-- Imports the weapon models (WeaponConfig.CatalogAssets) into
-- ServerStorage.Weapons as ready-to-carry Tools. Studio only: run it once from
-- the Command Bar in edit mode, then save the place:
--   require(game.ServerScriptService.CyberpunkOnlineServer.Weapons.WeaponImporter).Import()
-- Each weapon becomes a Tool: scripts removed, parts welded to a Handle,
-- scaled to a sensible size. Packs are split into one Tool per weapon.
-- Weapons already in the folder are skipped (hand adjustments are kept).
-- If one is held wrong, select its Tool and edit GripPos / GripForward in
-- Properties.

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local WeaponConfig = require(root.Config.WeaponConfig)

local WeaponImporter = {}

local REMOVE_CLASSES = { "LuaSourceContainer", "ClickDetector", "ProximityPrompt", "JointInstance", "WeldConstraint", "TouchTransmitter", "Humanoid" }

local function partsOf(instance: Instance): { BasePart }
	local parts = {}
	if instance:IsA("BasePart") then
		table.insert(parts, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
		end
	end
	return parts
end

-- The weapons inside an imported asset: a pack's child models, or the asset.
local function weaponsIn(object: Instance): { Instance }
	local children = {}
	for _, child in object:GetChildren() do
		if (child:IsA("Model") or child:IsA("Tool")) and #partsOf(child) > 0 then
			table.insert(children, child)
		end
	end
	if #children >= 2 then
		return children
	end
	return { object }
end

local function cleanName(name: string): string
	local cleaned = string.gsub(name, "[^%w%s%-]", "")
	cleaned = string.gsub(cleaned, "%s+", " ")
	cleaned = string.gsub(cleaned, "^%s+", "")
	cleaned = string.gsub(cleaned, "%s+$", "")
	return if cleaned == "" then "Arma" else cleaned
end

-- One weapon model -> Tool (Handle = biggest part; the rest welded to it).
local function toTool(unit: Instance, name: string, assetId: number): Tool?
	local parts = partsOf(unit)
	if #parts == 0 then
		return nil
	end
	for _, descendant in unit:GetDescendants() do
		for _, className in REMOVE_CLASSES do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end
	parts = partsOf(unit)
	-- All parts in one flat model (joints are gone; welds are rebuilt below).
	local holder = Instance.new("Model")
	for _, part in parts do
		part.Parent = holder
	end
	-- Scale into the expected length range.
	local frame, size = holder:GetBoundingBox()
	local longest = math.max(size.X, size.Y, size.Z)
	local range = WeaponConfig.LengthRange
	if longest > 0 and (longest < range.Min or longest > range.Max) then
		holder:ScaleTo(holder:GetScale() * WeaponConfig.FallbackLength / longest)
		frame, size = holder:GetBoundingBox()
	end
	local handle = parts[1]
	for _, part in parts do
		if part.Size.X * part.Size.Y * part.Size.Z > handle.Size.X * handle.Size.Y * handle.Size.Z then
			handle = part
		end
	end
	local tool = Instance.new("Tool")
	tool.Name = name
	tool.ToolTip = string.upper(name)
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool:SetAttribute("SourceAssetId", assetId)
	tool:SetAttribute("DisplayName", string.upper(name))
	for _, part in parts do
		part.Anchored = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.Parent = tool
		if part ~= handle then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = part
			weld.Parent = part
		end
	end
	handle.Name = "Handle"
	-- Grip: the hand at the rear-lower part of the weapon, its forward along
	-- the weapon's longest side (the barrel, best guess), its up the model's up.
	local axes = { frame.RightVector, frame.UpVector, frame.LookVector }
	local lengths = { size.X, size.Y, size.Z }
	local best = 1
	for index = 2, 3 do
		if lengths[index] > lengths[best] then
			best = index
		end
	end
	local barrel = axes[best]
	if math.abs(barrel.Y) > 0.9 then
		barrel = frame.LookVector
	end
	local flat = Vector3.new(barrel.X, 0, barrel.Z)
	barrel = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.zAxis
	local gripWorld = frame.Position - barrel * lengths[best] * 0.2 - Vector3.yAxis * size.Y * 0.15
	local gripFrame = CFrame.lookAt(gripWorld, gripWorld + barrel, Vector3.yAxis)
	tool.Grip = handle.CFrame:ToObjectSpace(gripFrame)
	holder:Destroy()
	return tool
end

-- Weapons removed by hand (RemoveByPosition) are listed on the folder so a
-- later Import never brings them back.
local EXCLUDED_ATTRIBUTE = "Excluded"

local function excluded(folder: Instance): { [string]: boolean }
	local list = {}
	local value = folder:GetAttribute(EXCLUDED_ATTRIBUTE)
	if type(value) == "string" then
		for name in string.gmatch(value, "[^|]+") do
			list[name] = true
		end
	end
	return list
end

-- Weapon names in armory order (left to right as seen from team A's spawn).
local function ordered(folder: Instance): { string }
	local names = {}
	for _, tool in folder:GetChildren() do
		if tool:IsA("Tool") and tool:FindFirstChild("Handle") then
			table.insert(names, tool.Name)
		end
	end
	table.sort(names)
	return names
end

-- Prints the armory order: number -> weapon name.
function WeaponImporter.List()
	local folder = ServerStorage:FindFirstChild(WeaponConfig.StorageFolder)
	if not folder then
		warn("[REALITY 2059] No hay ServerStorage." .. WeaponConfig.StorageFolder)
		return
	end
	for index, name in ordered(folder) do
		print(string.format("%2d  %s", index, name))
	end
end

-- Removes the weapons at these armory positions (1 = leftmost), e.g.
--   WeaponImporter.RemoveByPosition({ 4, 5, 13 })
function WeaponImporter.RemoveByPosition(positions: { number })
	local folder = ServerStorage:FindFirstChild(WeaponConfig.StorageFolder)
	if not folder then
		warn("[REALITY 2059] No hay ServerStorage." .. WeaponConfig.StorageFolder)
		return
	end
	local names = ordered(folder)
	local blocked = excluded(folder)
	for _, position in positions do
		local name = names[position]
		if name then
			local tool = folder:FindFirstChild(name)
			if tool then
				tool:Destroy()
			end
			blocked[name] = true
			print(string.format("[REALITY 2059] Quitada la arma %d: %s", position, name))
		else
			warn(string.format("[REALITY 2059] No hay arma en la posición %d (hay %d)", position, #names))
		end
	end
	local list = {}
	for name in blocked do
		table.insert(list, name)
	end
	table.sort(list)
	folder:SetAttribute(EXCLUDED_ATTRIBUTE, table.concat(list, "|"))
	print(string.format("[REALITY 2059] Quedan %d armas. Guarda el place.", #ordered(folder)))
end

function WeaponImporter.Import(): number
	local folder = ServerStorage:FindFirstChild(WeaponConfig.StorageFolder)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = WeaponConfig.StorageFolder
		folder.Parent = ServerStorage
	end
	local blocked = excluded(folder)
	local added = 0
	for _, assetId in WeaponConfig.CatalogAssets do
		local ok, objects = pcall(function()
			return game:GetObjects("rbxassetid://" .. assetId)
		end)
		if not ok or type(objects) ~= "table" or #objects == 0 then
			warn(string.format("[REALITY 2059] Arma %d: no se pudo descargar (%s)", assetId, tostring(objects)))
			continue
		end
		for _, object in objects do
			for _, unit in weaponsIn(object) do
				local name = cleanName(unit.Name)
				if blocked[name] then
					continue
				end
				if folder:FindFirstChild(name) then
					name = string.format("%s %d", name, assetId % 1000)
				end
				if folder:FindFirstChild(name) or blocked[name] then
					continue
				end
				local tool = toTool(unit, name, assetId)
				if tool then
					tool.Parent = folder
					added += 1
				end
			end
			object:Destroy()
		end
	end
	print(string.format("[REALITY 2059] Armas importadas: %d nuevas en ServerStorage.%s (guarda el place)", added, WeaponConfig.StorageFolder))
	return added
end

return WeaponImporter
