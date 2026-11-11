--!strict

-- City pedestrians for MODO LIBRE: standard R15 avatars (random looks the
-- server builds once, Runtime/PedestrianLooks, each with its own skin tone
-- here) walking the generated sidewalk lines. They pause now and then, keep
-- their personal space, and cross at crosswalks when the light holds the
-- traffic long enough (or when no car is close where there is no light).
-- Their feet always stand on the surface height of the sidewalk or the road.
-- Local and visual only.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CityLifeConfig = require(root.Config.CityLifeConfig)
local CityStreets = require(root.World.CityStreets)
local CharacterCatalog = require(root.Catalog.CharacterCatalog)

local AvatarPreview = require(script.Parent.Parent.MorphLab.AvatarPreview)

local CityPedestrians = {}
CityPedestrians.__index = CityPedestrians

local Settings = CityLifeConfig.Pedestrians
local Lights = CityLifeConfig.Lights
-- Shown again below HideBeyond, hidden above HideBeyond + this (no flicker).
local HIDE_MARGIN = 15
-- People who could not be placed retry this often (seconds).
local PLACE_RETRY = 1
-- How long to wait for the server's pool of looks.
local LOOKS_TIMEOUT = 30

local random = Random.new()

-- The server's pedestrian looks: { template, draft } pairs.
local function pedestrianLooks(): { any }
	local runtime = root:WaitForChild("Runtime", 10)
	local folder = runtime and runtime:WaitForChild("PedestrianLooks", LOOKS_TIMEOUT)
	if not folder then
		return {}
	end
	local deadline = os.clock() + LOOKS_TIMEOUT
	while not folder:GetAttribute("Ready") and os.clock() < deadline do
		task.wait(0.5)
	end
	local looks = {}
	for _, model in folder:GetChildren() do
		local raw = model:GetAttribute("Draft")
		local ok, draft = pcall(function()
			return HttpService:JSONDecode(raw)
		end)
		if model:IsA("Model") and ok and type(draft) == "table" then
			table.insert(looks, { template = model, draft = draft })
		end
	end
	return looks
end

local function playerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	return if rootPart and rootPart:IsA("BasePart") then rootPart.Position else nil
end

local function outOfView(position: Vector3): boolean
	local camera = Workspace.CurrentCamera
	if not camera then
		return true
	end
	local offset = position - camera.CFrame.Position
	return offset.Magnitude > 160 or offset.Unit:Dot(camera.CFrame.LookVector) < 0.35
end

local function flatUnit(vector: Vector3): Vector3?
	local flat = Vector3.new(vector.X, 0, vector.Z)
	return if flat.Magnitude > 1e-4 then flat.Unit else nil
end

local function yawOf(direction: Vector3): number
	return math.atan2(direction.X, direction.Z)
end

function CityPedestrians.new(network: CityStreets.Network, morphLabConfig)
	return setmetatable({
		_network = network,
		_config = morphLabConfig,
		_people = {} :: { any },
		_folder = nil :: Folder?,
		_scene = nil :: Model?,
		_traffic = nil :: any,
		_generation = 0,
		_crossing = {} :: { Vector3 },
	}, CityPedestrians)
end

-- traffic: CityTraffic (CarNear) for crossing where there is no light.
function CityPedestrians:SetTraffic(traffic)
	self._traffic = traffic
end

-- Positions of the people on crosswalks right now (obstacles for cars).
function CityPedestrians:GetCrossing(): { Vector3 }
	return self._crossing
end

-- ------------------------------------------------------------ placement --

function CityPedestrians:_place(person, around: Vector3, anywhere: boolean): boolean
	local walkways = self._network.walkways
	if #walkways == 0 then
		return false
	end
	for attempt = 1, 40 do
		local index = random:NextInteger(1, #walkways)
		local path = walkways[index].path
		if path.length < 6 then
			continue
		end
		local distance = random:NextNumber() * path.length
		local position, tangent = CityStreets.sample(path, distance)
		local flat = Vector3.new(position.X - around.X, 0, position.Z - around.Z).Magnitude
		local minimum = if anywhere then 15 else CityLifeConfig.SpawnMin
		if flat < minimum or flat > CityLifeConfig.SpawnMax then
			continue
		end
		if not anywhere and attempt < 25 and not outOfView(position) then
			continue
		end
		person.walkway = index
		person.distance = distance
		person.direction = if random:NextNumber() < 0.5 then 1 else -1
		person.state = "walk"
		person.timer = 0
		person.crosswalk = nil
		person.position = position
		person.y = position.Y
		local facing = flatUnit(tangent * person.direction) or Vector3.zAxis
		person.yaw = yawOf(facing)
		local side = (flatUnit(tangent) or Vector3.zAxis):Cross(Vector3.yAxis)
		person.offset = side * person.lateral
		person.active = true
		return true
	end
	return false
end

-- ------------------------------------------------------------- walking ---

-- Walkway to continue on at a sidewalk node (never straight back unless it
-- is a dead end).
function CityPedestrians:_continueAt(person, node: number, overflow: number)
	local network = self._network
	local options = {}
	for _, index in network.walkAt[node] or {} do
		if index ~= person.walkway then
			table.insert(options, index)
		end
	end
	local nextIndex = if #options > 0 then options[random:NextInteger(1, #options)] else person.walkway
	local walkway = network.walkways[nextIndex]
	person.walkway = nextIndex
	if walkway.a == node and (walkway.b ~= node or random:NextNumber() < 0.5) then
		person.direction = 1
		person.distance = math.min(overflow, walkway.path.length)
	else
		person.direction = -1
		person.distance = math.max(walkway.path.length - overflow, 0)
	end
end

-- Crossing starts only when it can finish: the light of the street being
-- crossed stays red long enough, or (no light) no car is close.
function CityPedestrians:_mayCross(person, crosswalk): boolean
	local node = self._network.nodes[crosswalk.node]
	if node and node.control == 1 and node.phases and node.phases[crosswalk.street] then
		local state, left = CityStreets.lightState(node, crosswalk.street, Workspace:GetServerTimeNow(), Lights)
		local needed = crosswalk.path.length / (person.baseSpeed * Settings.CrossSpeedFactor) + 1
		return state == "red" and left >= needed
	end
	return not (self._traffic and self._traffic:CarNear(crosswalk.middle, Settings.CarClearance))
end

-- Slows down behind someone, steps aside for someone coming the other way.
function CityPedestrians:_personalSpace(person, forward: Vector3): number
	local factor = 1
	for _, other in self._people do
		if other ~= person and other.active then
			local offset = other.position - person.position
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local distance = flat.Magnitude
			if distance < Settings.Personal * 2.5 and distance > 1e-3 then
				local ahead = flat.Unit:Dot(forward)
				if ahead > 0.6 then
					local otherForward = Vector3.new(math.sin(other.yaw), 0, math.cos(other.yaw))
					if otherForward:Dot(forward) > 0.3 then
						factor = math.min(factor, math.clamp((distance - Settings.Personal) / Settings.Personal, 0, 1))
					else
						person.sidestep = 1.6
					end
				end
			end
		end
	end
	return factor
end

-- Crosswalk entrances passed while moving from `before` to `after` on a
-- walkway (on closed loops the step may wrap past the start).
local function passed(crossing, before: number, after: number, length: number, closed: boolean): boolean
	local low, high = math.min(before, after), math.max(before, after)
	local distance = crossing.distance
	if distance >= low and distance <= high then
		return true
	end
	if closed then
		return (distance + length >= low and distance + length <= high) or (distance - length >= low and distance - length <= high)
	end
	return false
end

-- Moves one person; returns the feet CFrame and the walking speed.
function CityPedestrians:_simulate(person, deltaTime: number): (CFrame, number)
	local network = self._network
	local speed = 0
	local position: Vector3
	local facing: Vector3? -- direction the person should face
	local side: Vector3 -- right of the line they follow (fixed per path)
	local lateralScale = 1
	if person.state == "cross" then
		local crosswalk = network.crosswalks[person.crosswalk]
		local path = crosswalk.path
		speed = person.baseSpeed * Settings.CrossSpeedFactor
		person.crossDistance += speed * deltaTime
		if person.crossDistance >= path.length then
			-- Arrived on the other sidewalk.
			person.walkway = if person.crossForward then crosswalk.b else crosswalk.a
			person.distance = if person.crossForward then crosswalk.distB else crosswalk.distA
			person.direction = if random:NextNumber() < 0.5 then 1 else -1
			person.state = "walk"
			person.cooldown = 10
			return self:_simulate(person, 0)
		end
		local along = if person.crossForward then person.crossDistance else path.length - person.crossDistance
		local tangent
		position, tangent = CityStreets.sample(path, along)
		facing = flatUnit(if person.crossForward then tangent else -tangent)
		side = (flatUnit(tangent) or Vector3.zAxis):Cross(Vector3.yAxis)
		lateralScale = 0.3
	else
		local walkway = network.walkways[person.walkway]
		local path = walkway.path
		person.cooldown = math.max(0, person.cooldown - deltaTime)
		if person.state == "pause" then
			person.timer -= deltaTime
			if person.timer <= 0 then
				person.state = "walk"
			end
		elseif person.state == "wait" then
			person.timer += deltaTime
			local crosswalk = network.crosswalks[person.crosswalk]
			if self:_mayCross(person, crosswalk) then
				person.state = "cross"
				person.crossDistance = 0
			elseif person.timer > 30 then
				person.state = "walk"
				person.cooldown = 10
			end
		elseif random:NextNumber() < Settings.PauseChance * deltaTime then
			person.state = "pause"
			person.timer = Settings.PauseSeconds.Min + random:NextNumber() * (Settings.PauseSeconds.Max - Settings.PauseSeconds.Min)
		end
		if person.state == "walk" then
			local _, ahead = CityStreets.sample(path, person.distance)
			speed = person.baseSpeed * self:_personalSpace(person, (flatUnit(ahead) or Vector3.zAxis) * person.direction)
			local before = person.distance
			person.distance += speed * person.direction * deltaTime
			if person.cooldown <= 0 then
				for _, crossing in walkway.crossings do
					if passed(crossing, before, person.distance, path.length, path.closed) and random:NextNumber() < Settings.CrossChance then
						person.state = "wait"
						person.timer = 0
						person.crosswalk = crossing.crosswalk
						person.crossForward = crossing.fromStart
						person.distance = crossing.distance
						speed = 0
						break
					end
				end
			end
			if path.closed then
				person.distance %= path.length
			elseif person.distance > path.length then
				self:_continueAt(person, walkway.b, person.distance - path.length)
			elseif person.distance < 0 then
				self:_continueAt(person, walkway.a, -person.distance)
			end
		end
		local tangent
		position, tangent = CityStreets.sample(network.walkways[person.walkway].path, person.distance)
		side = (flatUnit(tangent) or Vector3.zAxis):Cross(Vector3.yAxis)
		if person.state == "wait" then
			-- Face the road while waiting at the curb.
			local crosswalk = network.crosswalks[person.crosswalk]
			local across = crosswalk.path.points[#crosswalk.path.points] - crosswalk.path.points[1]
			facing = flatUnit(if person.crossForward then across else -across)
		else
			facing = flatUnit(tangent * person.direction)
		end
	end
	-- Turn by the shortest angle (also right round when walking back).
	if facing then
		local difference = (yawOf(facing) - person.yaw + math.pi) % (2 * math.pi) - math.pi
		person.yaw += difference * (1 - math.exp(-7 * deltaTime))
	end
	-- Side offset eased as a world vector: no jumps when turning round,
	-- stopping at the curb or stepping onto a crosswalk.
	person.sidestep = math.max(0, person.sidestep - deltaTime * 0.8)
	local wanted = side * (person.lateral + person.sidestep) * lateralScale
	person.offset = person.offset:Lerp(wanted, 1 - math.exp(-4 * deltaTime))
	local feet = position + person.offset
	person.y += (feet.Y - person.y) * (1 - math.exp(-14 * deltaTime))
	person.position = Vector3.new(feet.X, person.y, feet.Z)
	local heading = Vector3.new(math.sin(person.yaw), 0, math.cos(person.yaw))
	return CFrame.lookAt(person.position, person.position + heading), speed
end

-- Animation level of detail: every frame near the player, a few times a
-- second further out, nothing (and not even moved on screen) when hidden.
function CityPedestrians:_puppet(person, deltaTime: number): (CFrame?, number?, number?)
	if not person.active then
		return nil, nil, nil
	end
	local stand, speed = self:_simulate(person, deltaTime)
	local around = playerPosition()
	local distance = if around then (person.position - around).Magnitude else 0
	local visible = if person.visible then distance < Settings.HideBeyond + HIDE_MARGIN else distance < Settings.HideBeyond
	if visible ~= person.visible then
		person.visible = visible
		person.model.Parent = if visible then self._folder else nil
		person.animation = 0
	end
	if not visible then
		return nil, nil, nil
	end
	if distance < Settings.AnimateNear then
		person.animation = 0
		return stand, speed, deltaTime
	end
	person.animation += deltaTime
	if person.animation >= Settings.FarAnimationInterval then
		local step = person.animation
		person.animation = 0
		return stand, speed, step
	end
	return stand, speed, nil
end

-- --------------------------------------------------------------- building --

function CityPedestrians:_build(around: Vector3, anywhere: boolean, generation: number, look)
	local person = {
		active = false,
		visible = true,
		walkway = 1,
		distance = 0,
		direction = 1,
		state = "walk",
		timer = 0,
		cooldown = 0,
		crosswalk = nil :: number?,
		crossForward = true,
		crossDistance = 0,
		baseSpeed = Settings.WalkSpeed.Min + random:NextNumber() * (Settings.WalkSpeed.Max - Settings.WalkSpeed.Min),
		lateral = (random:NextNumber() * 2 - 1) * Settings.Lateral,
		offset = Vector3.zero,
		sidestep = 0,
		yaw = 0,
		position = around,
		y = around.Y,
		animation = 0,
		nextPlace = 0,
		model = nil :: Model?,
		preview = nil :: any,
	}
	-- Somewhere to stand; if no sidewalk is in range right now, the person
	-- waits hidden and Update places them later.
	local placed = self:_place(person, around, anywhere)
	if self._generation ~= generation or not self._folder then
		return
	end
	-- Same catalog look as its pool entry, with its own skin tone.
	local draft = table.clone(look.draft)
	draft.appearance = table.clone(look.draft.appearance)
	draft.appearance.skinToneId = CharacterCatalog.SkinTones[random:NextInteger(1, 6)]
	local preview = AvatarPreview.new(self._config)
	preview:SetPuppet(function(deltaTime: number)
		return self:_puppet(person, deltaTime)
	end)
	local heading = Vector3.new(math.sin(person.yaw), 0, math.cos(person.yaw))
	preview:ShowTemplate(self._scene :: Model, look.template, draft, CFrame.lookAt(person.position, person.position + heading))
	local model = preview:GetModel()
	if not model then
		preview:Destroy()
		return
	end
	model.Name = "Peaton"
	person.model = model
	person.preview = preview
	person.visible = placed
	model.Parent = if placed then self._folder else nil
	table.insert(self._people, person)
end

function CityPedestrians:Start(folder: Folder, density: number, around: Vector3)
	self._folder = folder
	local scene = Instance.new("Model")
	scene.Name = "PedestrianScene"
	scene.Parent = folder
	self._scene = scene
	self._generation += 1
	local generation = self._generation
	local count = math.floor(Settings.Count * density + 0.5)
	task.spawn(function()
		local looks = pedestrianLooks()
		if #looks == 0 then
			warn("[REALITY 2059] No pedestrian looks from the server: the city stays empty")
			return
		end
		for i = 1, count do
			if self._generation ~= generation then
				return
			end
			local position = playerPosition() or around
			local look = looks[random:NextInteger(1, #looks)]
			local ok, problem = pcall(self._build, self, position, i <= count // 2, generation, look)
			if not ok then
				warn("[REALITY 2059] Pedestrian failed to build: " .. tostring(problem))
			end
			task.wait(1 / Settings.BuildPerSecond)
		end
	end)
end

-- Recycles people who drifted out of range (or were never placed) and
-- refreshes the list of people on crosswalks.
function CityPedestrians:Update(_deltaTime: number)
	local around = playerPosition()
	local now = os.clock()
	table.clear(self._crossing)
	for _, person in self._people do
		if person.active and person.state == "cross" then
			table.insert(self._crossing, person.position)
		end
		if around then
			local flat = Vector3.new(person.position.X - around.X, 0, person.position.Z - around.Z).Magnitude
			if (not person.active or flat > CityLifeConfig.ActiveRadius) and now >= person.nextPlace then
				if not self:_place(person, around, false) then
					person.active = false
					person.nextPlace = now + PLACE_RETRY
				end
			end
		end
	end
end

function CityPedestrians:Stop()
	self._generation += 1
	for _, person in self._people do
		person.preview:SetPuppet(nil)
		person.preview:Destroy()
	end
	table.clear(self._people)
	table.clear(self._crossing)
	if self._scene then
		self._scene:Destroy()
		self._scene = nil
	end
	self._folder = nil
end

function CityPedestrians:Count(): number
	local count = 0
	for _, person in self._people do
		if person.active then
			count += 1
		end
	end
	return count
end

return CityPedestrians
