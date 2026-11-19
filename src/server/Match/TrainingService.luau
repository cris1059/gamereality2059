--!strict

-- MODO ENTRENAMIENTO: practice in shooter mode without a match. The first
-- player to start it places one copy of MatchConfig.Training.Map for the
-- whole server (MatchService:PlaceMap), with every weapon on a pedestal
-- (WeaponService armory, pick up with F) and practice dummies that come back
-- after dying (CombatService). Each trainee spawns on the training team's
-- spawns with the starting weapons and respawns there; the map is removed
-- when the last trainee leaves.
-- TrainingStart (RemoteFunction): -> { ok, map | errorCode }; the client then
-- enters free roam in shooter mode on that map. TrainingLeave (RemoteEvent):
-- back to the lobby.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local MatchConfig = require(root.Config.MatchConfig)
local RemoteNames = require(root.Network.RemoteNames)

local TrainingService = {}
TrainingService.__index = TrainingService

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

-- freeRoam: FreeRoamService; weapons: WeaponService; combat: CombatService;
-- matches: MatchService (map placement, and nobody trains mid-match).
function TrainingService.new(runtime: Folder, freeRoam: any, weapons: any, combat: any, matches: any)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	return setmetatable({
		_freeRoam = freeRoam,
		_weapons = weapons,
		_combat = combat,
		_matches = matches,
		_start = remote(remotes, "RemoteFunction", RemoteNames.TrainingStart) :: RemoteFunction,
		_leave = remote(remotes, "RemoteEvent", RemoteNames.TrainingLeave) :: RemoteEvent,
		_map = nil :: Model?,
		_trainees = {} :: { [Player]: boolean },
		_zones = {} :: { { pad: BasePart, perSecond: number } },
	}, TrainingService)
end

-- The shared training map, placed (with armory and dummies) on first use.
function TrainingService:_ensureMap(): Model?
	local map = self._map
	if map and map.Parent then
		return map
	end
	local settings = MatchConfig.Training
	local placed = self._matches:PlaceMap(settings.Map, settings.Slot)
	if not placed then
		return nil
	end
	placed.Name = settings.Map .. "_Entrenamiento"
	self._weapons:_buildArmory(placed)
	self._combat:_dummies(placed)
	self:_buildZones(placed)
	self._map = placed
	print("[REALITY 2059] Modo entrenamiento: mapa " .. settings.Map .. " listo")
	return placed
end

-- Practice zones beside the spawns (MatchConfig.Training.Zones): standing in
-- one hurts or heals, applied here on the server like real damage, so the
-- HUD's CRÍTICO / ELIMINADO / healing can be tried without an opponent.
function TrainingService:_buildZones(map: Model)
	local bounds = map:FindFirstChild("Bounds")
	local area = bounds and bounds:FindFirstChild("PlayArea")
	if not area or not area:IsA("BasePart") then
		return
	end
	local floor = area.Position - Vector3.new(0, area.Size.Y / 2, 0)
	local folder = Instance.new("Folder")
	folder.Name = "PracticeZones"
	folder.Parent = map
	table.clear(self._zones)
	for _, zone in MatchConfig.Training.Zones do
		local pad = Instance.new("Part")
		pad.Name = zone.name
		pad.Anchored = true
		pad.CanCollide = false
		pad.CanQuery = false
		pad.CanTouch = false
		pad.Material = Enum.Material.Neon
		pad.Color = zone.color
		pad.Transparency = 0.45
		pad.Size = Vector3.new(zone.size, 0.25, zone.size)
		pad.CFrame = CFrame.new(floor + zone.offset + Vector3.new(0, 0.15, 0))
		pad.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = zone.color
		light.Range = 14
		light.Brightness = 1.5
		light.Parent = pad
		local sign = Instance.new("BillboardGui")
		sign.Size = UDim2.fromOffset(240, 54)
		sign.StudsOffset = Vector3.new(0, 4.5, 0)
		sign.MaxDistance = 140
		sign.LightInfluence = 0
		sign.Parent = pad
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 30)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.SciFi
		title.TextSize = 24
		title.TextColor3 = zone.color
		title.TextStrokeTransparency = 0.4
		title.Text = zone.label
		title.Parent = sign
		local detail = Instance.new("TextLabel")
		detail.Position = UDim2.fromOffset(0, 30)
		detail.Size = UDim2.new(1, 0, 0, 20)
		detail.BackgroundTransparency = 1
		detail.Font = Enum.Font.Code
		detail.TextSize = 15
		detail.TextColor3 = Color3.fromRGB(234, 247, 255)
		detail.TextStrokeTransparency = 0.4
		detail.Text = zone.detail
		detail.Parent = sign
		table.insert(self._zones, { pad = pad, perSecond = zone.perSecond })
	end
end

-- Every tick: trainees standing on a zone take its damage (negative heals).
function TrainingService:_tickZones(seconds: number)
	if #self._zones == 0 then
		return
	end
	for player in self._trainees do
		local character = player.Character
		local rootPart = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if rootPart and rootPart:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			for _, zone in self._zones do
				local pad = zone.pad
				local inside = pad.CFrame:PointToObjectSpace(rootPart.Position)
				if math.abs(inside.X) <= pad.Size.X / 2 and math.abs(inside.Z) <= pad.Size.Z / 2 and inside.Y > -1 and inside.Y < 8 then
					if zone.perSecond > 0 then
						humanoid:TakeDamage(zone.perSecond * seconds)
					else
						humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health - zone.perSecond * seconds)
					end
				end
			end
		end
	end
end

local function spawnsOf(map: Model, team: string): { BasePart }
	local spawns = map:FindFirstChild("Spawns")
	local folder = spawns and spawns:FindFirstChild("Team" .. team)
	local list = {}
	if folder then
		for _, spawn in folder:GetChildren() do
			if spawn:IsA("BasePart") then
				table.insert(list, spawn)
			end
		end
	end
	return list
end

function TrainingService:_join(player: Player): any
	if self._matches:IsInMatch(player) then
		return { ok = false, errorCode = "IN_MATCH" }
	end
	local map = self:_ensureMap()
	if not map then
		return { ok = false, errorCode = "MAP_NOT_FOUND" }
	end
	local points = spawnsOf(map, MatchConfig.Training.Team)
	self._trainees[player] = true
	self._freeRoam:SetSpawnProvider(player, function(): CFrame?
		if #points == 0 then
			return nil
		end
		return points[math.random(1, #points)].CFrame
	end)
	local weapons = MatchConfig.StartingWeapons
	if #weapons == 0 then
		weapons = self._weapons:DefaultWeapons()
	end
	self._weapons:SetLoadout(player, weapons)
	return { ok = true, map = MatchConfig.Training.Map }
end

-- Back to the lobby (or gone): weapons and spawn point cleared; the map goes
-- when nobody is training any more.
function TrainingService:_release(player: Player)
	if not self._trainees[player] then
		return
	end
	self._trainees[player] = nil
	-- A match that just started owns the spawn point and loadout now.
	if player.Parent == Players and not self._matches:IsInMatch(player) then
		self._weapons:ClearLoadout(player)
		self._freeRoam:SetSpawnProvider(player, nil)
	end
	if next(self._trainees) == nil and self._map then
		self._map:Destroy()
		self._map = nil
		table.clear(self._zones)
	end
end

function TrainingService:IsTraining(player: Player): boolean
	return self._trainees[player] == true
end

function TrainingService:Run()
	self._start.OnServerInvoke = function(player: Player)
		return self:_join(player)
	end
	self._leave.OnServerEvent:Connect(function(player: Player)
		self:_release(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		self:_release(player)
	end)
	-- Practice zones tick a few times a second.
	local ZONE_TICK = 0.25
	local elapsed = 0
	RunService.Heartbeat:Connect(function(deltaTime: number)
		elapsed += deltaTime
		if elapsed >= ZONE_TICK then
			self:_tickZones(elapsed)
			elapsed = 0
		end
	end)
end

return TrainingService
