--!strict

-- Carried weapons. Each player holds up to WeaponConfig.MaxSlots weapons
-- (Tools cloned from ServerStorage.Weapons); the server owns the loadout.
-- Pickups are weapon models on the map with a ProximityPrompt (E): with a free
-- slot the weapon is added; with a full loadout it replaces the weapon in
-- hand, which drops where the player stands. The client switches with 1/2
-- (WeaponEquip) and is told its loadout (WeaponLoadout).
-- In Studio map tests (DevConfig.QuickStart = "MapTest") every weapon is laid
-- out on pedestals in front of team A's spawns.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local WeaponConfig = require(root.Config.WeaponConfig)
local DevConfig = require(root.Config.DevConfig)
local RemoteNames = require(root.Network.RemoteNames)
local WeaponStats = require(root.Combat.WeaponStats)

local WeaponService = {}
WeaponService.__index = WeaponService

local PICKUP_TAG = "WeaponPickup"
local LOADOUT_ATTRIBUTE = "LoadoutSlot"

type Loadout = { slots: { string }, equipped: number }

local function remote(folder: Instance, className: string, name: string): any
	local existing = folder:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = folder
	return created
end

function WeaponService.new(runtime: Folder)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	return setmetatable({
		_equip = remote(remotes, "RemoteEvent", RemoteNames.WeaponEquip) :: RemoteEvent,
		_loadoutRemote = remote(remotes, "RemoteEvent", RemoteNames.WeaponLoadout) :: RemoteEvent,
		-- Aim (pitch, aiming, reloading) a few times a second; lost packets
		-- do not matter, so it is unreliable.
		_aim = remote(remotes, "UnreliableRemoteEvent", RemoteNames.WeaponAim) :: UnreliableRemoteEvent,
		_loadouts = {} :: { [Player]: Loadout },
	}, WeaponService)
end

function WeaponService:_templates(): Folder?
	local folder = ServerStorage:FindFirstChild(WeaponConfig.StorageFolder)
	return if folder and folder:IsA("Folder") then folder else nil
end

function WeaponService:_template(weaponId: string): Tool?
	local folder = self:_templates()
	local template = folder and folder:FindFirstChild(weaponId)
	return if template and template:IsA("Tool") and template:FindFirstChild("Handle") then template else nil
end

local function displayName(tool: Tool): string
	local name = tool:GetAttribute("DisplayName")
	return if type(name) == "string" then name else string.upper(tool.Name)
end

function WeaponService:_loadout(player: Player): Loadout
	local loadout = self._loadouts[player]
	if not loadout then
		loadout = { slots = {}, equipped = 1 }
		self._loadouts[player] = loadout
	end
	return loadout
end

-- A starting loadout for matches: the first rifle and the first pistol (by
-- name) among the imported weapons, or whatever there is.
function WeaponService:DefaultWeapons(): { string }
	local folder = self:_templates()
	if not folder then
		return {}
	end
	local byClass: { [string]: string } = {}
	local names = {}
	for _, tool in folder:GetChildren() do
		if tool:IsA("Tool") and tool:FindFirstChild("Handle") then
			table.insert(names, tool.Name)
		end
	end
	table.sort(names)
	for _, name in names do
		local class = WeaponStats.ClassOf(folder:FindFirstChild(name) :: Tool)
		byClass[class] = byClass[class] or name
	end
	local picked = {}
	for _, class in { "rifle", "pistol" } do
		if byClass[class] then
			table.insert(picked, byClass[class])
		end
	end
	for _, name in names do
		if #picked >= WeaponConfig.MaxSlots then
			break
		end
		if not table.find(picked, name) then
			table.insert(picked, name)
		end
	end
	return picked
end

-- Gives `player` these weapons (a match start); they are handed out again on
-- every respawn.
function WeaponService:SetLoadout(player: Player, weaponIds: { string })
	local slots = {}
	for _, weaponId in weaponIds do
		if #slots < WeaponConfig.MaxSlots and self:_template(weaponId) then
			table.insert(slots, weaponId)
		end
	end
	self._loadouts[player] = { slots = slots, equipped = 1 }
	self:_giveTools(player)
	self:_push(player)
end

-- No more weapons (match over).
function WeaponService:ClearLoadout(player: Player)
	self._loadouts[player] = { slots = {}, equipped = 1 }
	self:_giveTools(player)
	self:_push(player)
	self._loadouts[player] = nil
end

function WeaponService:_push(player: Player)
	local loadout = self:_loadout(player)
	local names = {}
	for _, weaponId in loadout.slots do
		local template = self:_template(weaponId)
		table.insert(names, if template then displayName(template) else weaponId)
	end
	self._loadoutRemote:FireClient(player, { slots = names, equipped = loadout.equipped, max = WeaponConfig.MaxSlots })
end

-- Rebuilds the player's weapon Tools from the loadout and puts the equipped
-- one in hand (after a pickup, a swap or a respawn).
function WeaponService:_giveTools(player: Player)
	local loadout = self:_loadout(player)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	for _, container in { character, backpack } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute(LOADOUT_ATTRIBUTE) then
					child:Destroy()
				end
			end
		end
	end
	if not backpack then
		return
	end
	local equippedTool: Tool? = nil
	for index, weaponId in loadout.slots do
		local template = self:_template(weaponId)
		if template then
			local tool = template:Clone()
			tool:SetAttribute(LOADOUT_ATTRIBUTE, index)
			-- Full magazine (CombatService spends it; the client shows it).
			local stats = WeaponStats.Get(tool)
			tool:SetAttribute("WeaponClass", WeaponStats.ClassOf(tool))
			tool:SetAttribute("Magazine", stats.magazine)
			tool:SetAttribute("Ammo", stats.magazine)
			tool.Parent = backpack
			if index == loadout.equipped then
				equippedTool = tool
			end
		end
	end
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and equippedTool then
		humanoid:EquipTool(equippedTool)
	end
end

-- A weapon lying on the map: the Tool's parts as an anchored model with a
-- prompt. `respawn` brings it back at the same spot after it is taken.
function WeaponService:_spawnPickup(weaponId: string, at: CFrame, parent: Instance, respawn: boolean)
	local template = self:_template(weaponId)
	if not template then
		return
	end
	local copy = template:Clone()
	local model = Instance.new("Model")
	model.Name = "Pickup_" .. weaponId
	for _, child in copy:GetChildren() do
		child.Parent = model
	end
	copy:Destroy()
	local handle = model:FindFirstChild("Handle") :: BasePart
	model.PrimaryPart = handle
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			-- Shots and the camera pass through pickups.
			descendant.CanQuery = false
		end
	end
	-- Resting just above `at`.
	model:PivotTo(at)
	local frame, size = model:GetBoundingBox()
	model:PivotTo(model:GetPivot() + Vector3.new(at.X - frame.X, at.Y + 0.4 - (frame.Y - size.Y / 2), at.Z - frame.Z))
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "AGARRAR"
	prompt.ObjectText = displayName(template)
	prompt.KeyboardKeyCode = WeaponConfig.Pickup.Key
	prompt.GamepadKeyCode = WeaponConfig.Pickup.GamepadKey
	prompt.MaxActivationDistance = WeaponConfig.Pickup.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt:SetAttribute("WeaponId", weaponId)
	prompt.Parent = handle
	CollectionService:AddTag(prompt, PICKUP_TAG)
	model.Parent = parent
	local taken = false
	prompt.Triggered:Connect(function(player: Player)
		if taken or not self:_pickUp(player, weaponId, model) then
			return
		end
		taken = true
		model:Destroy()
		if respawn then
			task.delay(WeaponConfig.Pickup.RespawnSeconds, function()
				if parent.Parent then
					self:_spawnPickup(weaponId, at, parent, true)
				end
			end)
		end
	end)
end

-- Adds the weapon, or swaps it for the one in hand when the loadout is full.
function WeaponService:_pickUp(player: Player, weaponId: string, pickup: Model): boolean
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not rootPart:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then
		return false
	end
	if (rootPart.Position - pickup:GetPivot().Position).Magnitude > WeaponConfig.Pickup.MaxDistance + 4 then
		return false
	end
	local loadout = self:_loadout(player)
	if table.find(loadout.slots, weaponId) then
		-- Already carried: just take it in hand.
		loadout.equipped = table.find(loadout.slots, weaponId) :: number
	elseif #loadout.slots < WeaponConfig.MaxSlots then
		table.insert(loadout.slots, weaponId)
		loadout.equipped = #loadout.slots
	else
		local dropped = loadout.slots[loadout.equipped]
		loadout.slots[loadout.equipped] = weaponId
		local ground = CFrame.new(rootPart.Position - Vector3.new(0, humanoid.HipHeight + rootPart.Size.Y / 2, 0)) * rootPart.CFrame.Rotation
		self:_spawnPickup(dropped, ground * CFrame.new(0, 0, -3), pickup.Parent or Workspace, false)
	end
	self:_giveTools(player)
	self:_push(player)
	return true
end

-- Studio map test: the map in Workspace.MapWorkshop[DevConfig.MapTest].
local function testMap(): Model?
	if not RunService:IsStudio() or DevConfig.QuickStart ~= "MapTest" then
		return nil
	end
	local workshop = Workspace:FindFirstChild("MapWorkshop")
	local map = workshop and workshop:FindFirstChild(DevConfig.MapTest)
	return if map and map:IsA("Model") then map else nil
end

-- Every weapon on a pedestal in front of team A's spawns (or on the map's
-- own WeaponSpawns parts, if it has them).
function WeaponService:_buildArmory(map: Model)
	local folder = self:_templates()
	if not folder then
		warn("[REALITY 2059] No hay armas: corre WeaponImporter desde la Command Bar (ServerStorage." .. WeaponConfig.StorageFolder .. ")")
		return
	end
	local ids = {}
	for _, tool in folder:GetChildren() do
		if tool:IsA("Tool") and tool:FindFirstChild("Handle") then
			table.insert(ids, tool.Name)
		end
	end
	table.sort(ids)
	local armory = Instance.new("Folder")
	armory.Name = "Armory"
	armory.Parent = map
	local spots = {}
	local custom = map:FindFirstChild("WeaponSpawns")
	if custom then
		for _, spot in custom:GetChildren() do
			if spot:IsA("BasePart") then
				table.insert(spots, spot.CFrame + Vector3.new(0, spot.Size.Y / 2, 0))
			end
		end
	else
		local bounds = map:FindFirstChild("Bounds")
		local area = bounds and bounds:FindFirstChild("PlayArea")
		local origin = if area and area:IsA("BasePart") then area.Position - Vector3.new(0, area.Size.Y / 2, 0) else map:GetPivot().Position
		local settings = WeaponConfig.Armory
		for index = 1, #ids do
			local row = (index - 1) // settings.PerRow
			local column = (index - 1) % settings.PerRow
			local inRow = math.min(settings.PerRow, #ids - row * settings.PerRow)
			local x = (column - (inRow - 1) / 2) * settings.Spacing
			local base = origin + Vector3.new(x, 0, settings.RowZ + row * settings.RowGap)
			local pedestal = Instance.new("Part")
			pedestal.Name = "Pedestal"
			pedestal.Anchored = true
			pedestal.Size = Vector3.new(3, 1, 3)
			pedestal.CFrame = CFrame.new(base + Vector3.new(0, 0.5, 0))
			pedestal.Color = Color3.fromRGB(30, 32, 42)
			pedestal.Material = Enum.Material.Metal
			pedestal.Parent = armory
			local strip = Instance.new("Part")
			strip.Name = "PedestalLight"
			strip.Anchored = true
			strip.CanCollide = false
			strip.Size = Vector3.new(3.1, 0.12, 3.1)
			strip.CFrame = CFrame.new(base + Vector3.new(0, 1.02, 0))
			strip.Color = Color3.fromRGB(0, 200, 255)
			strip.Material = Enum.Material.Neon
			strip.Transparency = 0.6
			strip.Parent = armory
			-- Facing team A's way out (map -Z), the barrel sideways.
			table.insert(spots, CFrame.new(base + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(90), 0))
		end
	end
	for index, weaponId in ids do
		local spot = spots[(index - 1) % math.max(#spots, 1) + 1]
		if spot then
			self:_spawnPickup(weaponId, spot, armory, true)
		end
	end
	print(string.format("[REALITY 2059] Armería de prueba: %d armas en %s", #ids, map.Name))
end

function WeaponService:Start()
	-- Shared on the character so every client poses it (ShooterAnimation).
	self._aim.OnServerEvent:Connect(function(player: Player, pitch: any, aiming: any, reloading: any, crouching: any, sliding: any)
		local character = player.Character
		if not character or type(pitch) ~= "number" or pitch ~= pitch then
			return
		end
		character:SetAttribute("AimPitch", math.floor(math.clamp(pitch, -80, 80) + 0.5))
		character:SetAttribute("Aiming", aiming == true)
		character:SetAttribute("Reloading", reloading == true)
		character:SetAttribute("Crouching", crouching == true)
		character:SetAttribute("Sliding", sliding == true)
	end)
	self._equip.OnServerEvent:Connect(function(player: Player, slot: any)
		local loadout = self._loadouts[player]
		if not loadout or type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > #loadout.slots then
			return
		end
		loadout.equipped = slot
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local backpack = player:FindFirstChildOfClass("Backpack")
		if humanoid and backpack then
			for _, tool in backpack:GetChildren() do
				if tool:IsA("Tool") and tool:GetAttribute(LOADOUT_ATTRIBUTE) == slot then
					humanoid:EquipTool(tool)
				end
			end
		end
		self:_push(player)
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			-- Respawned characters get their weapons back.
			task.defer(function()
				if self._loadouts[player] then
					self:_giveTools(player)
					self:_push(player)
				end
			end)
		end)
	end
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player)
		self._loadouts[player] = nil
	end)
	local map = testMap()
	if map then
		self:_buildArmory(map)
	end
end

return WeaponService
