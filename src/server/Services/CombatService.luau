--!strict

-- Shooting, server side. The client fires instantly (tracer, recoil) and
-- sends only where the shot started and its directions (WeaponFire); this
-- service decides what was hit:
--   * the shooter is alive, holding a loadout weapon, within its fire rate,
--     with ammo, not reloading, and the shot starts at their head;
--   * every pellet is traced against the world (walls stop it) and against
--     the targets' body parts as they were when the shot was fired (a short
--     position history per target: light lag compensation);
--   * damage = weapon damage x body zone (head / torso / arm / leg), applied
--     with Humanoid:TakeDamage; teammates are never hurt.
-- The shooter gets each hit back (WeaponHit: damage numbers, hit marker);
-- everyone else gets the tracers (WeaponShots). Ammo lives on the Tool as
-- attributes (Ammo), so the client can show it. In Studio map tests, practice
-- dummies stand in the middle of the map.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local DevConfig = require(root.Config.DevConfig)
local WeaponStats = require(root.Combat.WeaponStats)

local CombatService = {}
CombatService.__index = CombatService

local TARGET_TAG = "Damageable"
local HISTORY_SECONDS = 1
local MAX_REWIND = 0.4
local ORIGIN_TOLERANCE = 7
local RATE_TOLERANCE = 0.8
local DUMMY_RESPAWN = 3

type Sample = { time: number, position: Vector3 }

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

function CombatService.new(runtime: Folder)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	return setmetatable({
		_fire = remote(remotes, "RemoteEvent", RemoteNames.WeaponFire) :: RemoteEvent,
		_reload = remote(remotes, "RemoteEvent", RemoteNames.WeaponReload) :: RemoteEvent,
		_hit = remote(remotes, "RemoteEvent", RemoteNames.WeaponHit) :: RemoteEvent,
		_shots = remote(remotes, "UnreliableRemoteEvent", RemoteNames.WeaponShots) :: UnreliableRemoteEvent,
		_history = {} :: { [Model]: { Sample } },
		_lastShot = {} :: { [Player]: number },
	}, CombatService)
end

-- The loadout weapon in the character's hand.
local function heldWeapon(character: Model): Tool?
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("LoadoutSlot") then
			return child
		end
	end
	return nil
end

-- Full magazine on a weapon Tool that has none yet (WeaponService sets it
-- when handing weapons out; this covers anything else).
local function prepareTool(tool: Tool)
	if tool:GetAttribute("Ammo") == nil then
		local stats = WeaponStats.Get(tool)
		tool:SetAttribute("Ammo", stats.magazine)
		tool:SetAttribute("Magazine", stats.magazine)
		tool:SetAttribute("WeaponClass", WeaponStats.ClassOf(tool))
	end
end

-- Everything that can be shot: player characters and practice dummies.
local function targets(): { Model }
	local list = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(list, player.Character)
		end
	end
	for _, dummy in CollectionService:GetTagged(TARGET_TAG) do
		if dummy:IsA("Model") then
			table.insert(list, dummy)
		end
	end
	return list
end

function CombatService:_record()
	local now = Workspace:GetServerTimeNow()
	for _, target in targets() do
		local rootPart = target:FindFirstChild("HumanoidRootPart")
		if rootPart and rootPart:IsA("BasePart") then
			local samples = self._history[target]
			if not samples then
				samples = {}
				self._history[target] = samples
			end
			table.insert(samples, { time = now, position = rootPart.Position })
			while #samples > 0 and samples[1].time < now - HISTORY_SECONDS do
				table.remove(samples, 1)
			end
		end
	end
	for target in self._history do
		if not target.Parent then
			self._history[target] = nil
		end
	end
end

-- How far the target has moved since `time` (to put its hitboxes back).
function CombatService:_rewind(target: Model, time: number): Vector3
	local samples = self._history[target]
	local rootPart = target:FindFirstChild("HumanoidRootPart")
	if not samples or #samples == 0 or not rootPart or not rootPart:IsA("BasePart") then
		return Vector3.zero
	end
	local past = samples[1].position
	for index = #samples, 1, -1 do
		local sample = samples[index]
		if sample.time <= time then
			local nextSample = samples[index + 1]
			if nextSample then
				local alpha = math.clamp((time - sample.time) / math.max(nextSample.time - sample.time, 1e-3), 0, 1)
				past = sample.position:Lerp(nextSample.position, alpha)
			else
				past = sample.position
			end
			break
		end
	end
	return past - rootPart.Position
end

-- Ray against a box (part CFrame + size): distance along the ray, or nil.
local function rayBox(origin: Vector3, direction: Vector3, frame: CFrame, size: Vector3): number?
	local o = frame:PointToObjectSpace(origin)
	local d = frame:VectorToObjectSpace(direction)
	local half = size / 2
	local near, far = -math.huge, math.huge
	for _, axis in { "X", "Y", "Z" } do
		local oa, da, ha = (o :: any)[axis], (d :: any)[axis], (half :: any)[axis]
		if math.abs(da) < 1e-8 then
			if oa < -ha or oa > ha then
				return nil
			end
		else
			local t1, t2 = (-ha - oa) / da, (ha - oa) / da
			if t1 > t2 then
				t1, t2 = t2, t1
			end
			near = math.max(near, t1)
			far = math.min(far, t2)
			if near > far then
				return nil
			end
		end
	end
	if far < 0 then
		return nil
	end
	return math.max(near, 0)
end

local function humanoidOf(target: Model): Humanoid?
	local humanoid = target:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

local function sameTeam(shooter: Player, target: Model): boolean
	local other = Players:GetPlayerFromCharacter(target)
	return other ~= nil and shooter.Team ~= nil and other.Team == shooter.Team and other ~= shooter
end

-- Closest body-part hit along one pellet, before `limit` studs.
function CombatService:_trace(shooter: Player, origin: Vector3, direction: Vector3, limit: number, shotTime: number): (Model?, string?, number?)
	local bestTarget, bestZone, bestDistance = nil, nil, limit
	for _, target in targets() do
		if target ~= shooter.Character and humanoidOf(target) and not sameTeam(shooter, target) then
			local offset = self:_rewind(target, shotTime)
			for _, part in target:GetChildren() do
				if part:IsA("BasePart") then
					local zone = WeaponStats.ZoneOf(part.Name)
					if zone and part.Name ~= "HumanoidRootPart" then
						local distance = rayBox(origin, direction, part.CFrame + offset, part.Size)
						if distance and distance < bestDistance then
							bestTarget, bestZone, bestDistance = target, zone, distance
						end
					end
				end
			end
		end
	end
	return bestTarget, bestZone, if bestTarget then bestDistance else nil
end

function CombatService:_onFire(player: Player, origin: any, directions: any, shotTime: any)
	local character = player.Character
	local humanoid = character and humanoidOf(character)
	local head = character and character:FindFirstChild("Head")
	if not character or not humanoid or not head or not head:IsA("BasePart") then
		return
	end
	if typeof(origin) ~= "Vector3" or type(directions) ~= "table" or type(shotTime) ~= "number" then
		return
	end
	local tool = heldWeapon(character)
	if not tool then
		return
	end
	prepareTool(tool)
	local stats = WeaponStats.Get(tool)
	local now = Workspace:GetServerTimeNow()
	local last = self._lastShot[player]
	if last and now - last < (1 / stats.fireRate) * RATE_TOLERANCE then
		return
	end
	local ammo = tool:GetAttribute("Ammo")
	if type(ammo) ~= "number" or ammo <= 0 or tool:GetAttribute("Reloading") then
		return
	end
	if (origin - head.Position).Magnitude > ORIGIN_TOLERANCE or #directions ~= stats.pellets then
		return
	end
	self._lastShot[player] = now
	tool:SetAttribute("Ammo", ammo - 1)
	local time = math.clamp(shotTime, now - MAX_REWIND, now)
	local worldParams = RaycastParams.new()
	worldParams.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = targets()
	worldParams.FilterDescendantsInstances = exclude
	local hits = {}
	local endpoints = {}
	local damageByTarget: { [Model]: number } = {}
	for _, direction in directions do
		if typeof(direction) ~= "Vector3" or direction.Magnitude < 0.5 then
			continue
		end
		local unit = direction.Unit
		local wall = Workspace:Raycast(origin, unit * stats.range, worldParams)
		local limit = if wall then wall.Distance else stats.range
		local target, zone, distance = self:_trace(player, origin, unit, limit, time)
		if target and zone and distance then
			local info = WeaponStats.Zones[zone]
			local multiplier = if zone == "head" then stats.headMultiplier else info.multiplier
			local damage = math.floor(stats.damage * multiplier + 0.5)
			damageByTarget[target] = (damageByTarget[target] or 0) + damage
			table.insert(hits, { position = origin + unit * distance, damage = damage, zone = zone })
			table.insert(endpoints, origin + unit * distance)
		else
			table.insert(endpoints, if wall then wall.Position else origin + unit * stats.range)
		end
	end
	-- Damage once per target (a shotgun blast is one hit with the pellets added).
	local killed = false
	for target, damage in damageByTarget do
		local targetHumanoid = humanoidOf(target)
		if targetHumanoid then
			-- Who hit last gets the kill (MatchService reads it on death).
			targetHumanoid:SetAttribute("LastAttacker", player.UserId)
			targetHumanoid:TakeDamage(damage)
			if targetHumanoid.Health <= 0 then
				killed = true
			end
		end
	end
	if #hits > 0 then
		self._hit:FireClient(player, hits, killed)
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			self._shots:FireClient(other, character, endpoints)
		end
	end
end

function CombatService:_onReload(player: Player)
	local character = player.Character
	local tool = character and heldWeapon(character)
	if not tool or tool:GetAttribute("Reloading") then
		return
	end
	prepareTool(tool)
	local stats = WeaponStats.Get(tool)
	if (tool:GetAttribute("Ammo") :: number) >= stats.magazine then
		return
	end
	tool:SetAttribute("Reloading", true)
	task.delay(stats.reloadSeconds, function()
		if tool.Parent then
			tool:SetAttribute("Ammo", stats.magazine)
			tool:SetAttribute("Reloading", nil)
		end
	end)
end

-- ------------------------------------------------------------ dummies --

local function buildDummy(at: CFrame, parent: Instance, index: number): Model?
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	model.Name = "Maniqui" .. index
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("LuaSourceContainer") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Color = Color3.fromRGB(150, 155, 170)
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = "MANIQUÍ"
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOn
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 80
	humanoid.HealthDisplayDistance = 80
	humanoid.BreakJointsOnDeath = false
	local rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart
	rootPart.Anchored = true
	model:PivotTo(at + Vector3.new(0, humanoid.HipHeight + rootPart.Size.Y / 2, 0))
	CollectionService:AddTag(model, TARGET_TAG)
	model.Parent = parent
	return model
end

function CombatService:_dummies(map: Model)
	local bounds = map:FindFirstChild("Bounds")
	local area = bounds and bounds:FindFirstChild("PlayArea")
	if not area or not area:IsA("BasePart") then
		return
	end
	local origin = area.Position - Vector3.new(0, area.Size.Y / 2, 0)
	local folder = Instance.new("Folder")
	folder.Name = "PracticeDummies"
	folder.Parent = map
	-- In the plaza, facing team A's side (+Z); one on the platform.
	local spots = {
		Vector3.new(-16, 0, 40), Vector3.new(0, 0, 44), Vector3.new(16, 0, 40),
		Vector3.new(-8, 4, 0), Vector3.new(8, 4, 0),
	}
	for index, offset in spots do
		local at = CFrame.lookAt(origin + offset, origin + offset + Vector3.zAxis)
		local function spawn()
			local dummy = buildDummy(at, folder, index)
			local humanoid = dummy and dummy:FindFirstChildOfClass("Humanoid")
			if dummy and humanoid then
				humanoid.Died:Connect(function()
					task.delay(DUMMY_RESPAWN, function()
						dummy:Destroy()
						if folder.Parent then
							spawn()
						end
					end)
				end)
			end
		end
		spawn()
	end
end

function CombatService:Start()
	self._fire.OnServerEvent:Connect(function(player, origin, directions, shotTime)
		self:_onFire(player, origin, directions, shotTime)
	end)
	self._reload.OnServerEvent:Connect(function(player)
		self:_onReload(player)
	end)
	RunService.Heartbeat:Connect(function()
		self:_record()
	end)
	Players.PlayerRemoving:Connect(function(player)
		self._lastShot[player] = nil
	end)
	if RunService:IsStudio() and DevConfig.QuickStart == "MapTest" then
		local workshop = Workspace:FindFirstChild("MapWorkshop")
		local map = workshop and workshop:FindFirstChild(DevConfig.MapTest)
		if map and map:IsA("Model") then
			self:_dummies(map)
		end
	end
end

return CombatService
