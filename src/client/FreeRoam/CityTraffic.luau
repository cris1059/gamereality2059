--!strict

-- Ambient traffic for MODO LIBRE: ground cars on the generated lanes and
-- flying cars in the air lanes above the streets. Purely local and visual.
-- Ground cars stop at red lights (shared server clock, so every player sees
-- the same lights), yield at the roundabout, keep their distance, brake for
-- people on crosswalks and signal their turns. Flying cars keep a cruise
-- height and climb over anything taller under their route ahead of time.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CityLifeConfig = require(root.Config.CityLifeConfig)
local CityStreets = require(root.World.CityStreets)

local CityTraffic = {}
CityTraffic.__index = CityTraffic

local Cars = CityLifeConfig.Cars
local Air = CityLifeConfig.FlyingCars
local Lights = CityLifeConfig.Lights

local LIGHT_COLORS = {
	red = Color3.fromRGB(255, 40, 40),
	yellow = Color3.fromRGB(255, 190, 30),
	green = Color3.fromRGB(40, 255, 110),
}
local LAMP_OFF = Color3.fromRGB(30, 30, 34)
local SIGNAL = Color3.fromRGB(255, 160, 20)

local random = Random.new()
local function pick<T>(list: { T }): T
	return list[random:NextInteger(1, #list)]
end

local function part(parent: Instance, name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local item = Instance.new("Part")
	item.Name = name
	item.Size = size
	item.Color = color
	item.Material = material or Enum.Material.SmoothPlastic
	item.Anchored = false
	item.CanCollide = false
	item.CanQuery = false
	item.CanTouch = false
	item.CastShadow = false
	item.Massless = true
	item.Parent = parent
	return item
end

local function weld(rootPart: BasePart, child: BasePart, offset: CFrame)
	child.CFrame = rootPart.CFrame * offset
	local constraint = Instance.new("WeldConstraint")
	constraint.Part0 = rootPart
	constraint.Part1 = child
	constraint.Parent = child
end

-- -Z is forward. The pivot sits on the road under the car's centre. 5.6 studs
-- wide: lanes keep 3.6 studs from curbs, so the body never enters a sidewalk.
local function buildCar(parent: Instance, flying: boolean)
	local palette = CityLifeConfig.Palette
	local model = Instance.new("Model")
	model.Name = if flying then "Aeroauto" else "Auto"
	local body = part(model, "Body", Vector3.new(5.6, 1.6, 12.6), pick(palette.CarBody), Enum.Material.Metal)
	body.Anchored = true
	model.PrimaryPart = body
	local cabin = part(model, "Cabin", Vector3.new(4.9, 1.4, 6.2), Color3.fromRGB(14, 18, 26), Enum.Material.Glass)
	cabin.Transparency = 0.2
	weld(body, cabin, CFrame.new(0, 1.45, 0.6))
	local neon = pick(palette.Neon)
	local glow = part(model, "Underglow", Vector3.new(5.2, 0.2, 11.8), neon, Enum.Material.Neon)
	weld(body, glow, CFrame.new(0, -0.85, 0))
	local signals = { left = {} :: { BasePart }, right = {} :: { BasePart } }
	for _, x in { -2.05, 2.05 } do
		weld(body, part(model, "Headlight", Vector3.new(1.2, 0.4, 0.2), Color3.fromRGB(235, 245, 255), Enum.Material.Neon), CFrame.new(x, 0.1, -6.35))
		weld(body, part(model, "Taillight", Vector3.new(1.4, 0.35, 0.2), Color3.fromRGB(255, 30, 40), Enum.Material.Neon), CFrame.new(x, 0.2, 6.35))
		for _, z in { -6.2, 6.2 } do
			local signal = part(model, "Signal", Vector3.new(0.5, 0.3, 0.3), SIGNAL, Enum.Material.Neon)
			signal.Transparency = 1
			weld(body, signal, CFrame.new(if x < 0 then -2.75 else 2.75, 0.35, z))
			table.insert(if x < 0 then signals.left else signals.right, signal)
		end
	end
	if flying then
		for _, x in { -3.2, 3.2 } do
			weld(body, part(model, "Thruster", Vector3.new(1, 0.8, 4), Color3.fromRGB(40, 42, 50), Enum.Material.Metal), CFrame.new(x, -0.2, 2))
			weld(body, part(model, "Flame", Vector3.new(0.7, 0.5, 0.2), neon, Enum.Material.Neon), CFrame.new(x, -0.2, 4.1))
		end
	end
	-- The pivot of a model with a PrimaryPart is that part's pivot
	-- (WorldPivot is ignored), so the offset goes on the body itself: the
	-- pivot sits on the road 1.2 studs under the body's centre.
	body.PivotOffset = CFrame.new(0, -1.2, 0)
	model.Parent = parent
	return model, signals
end

function CityTraffic.new(network: CityStreets.Network, floorY: number)
	return setmetatable({
		_network = network,
		_floorY = floorY,
		_cars = {} :: { any },
		_folder = nil :: Folder?,
		_posts = {} :: { any },
		_postTimer = 0,
		_pedestrians = nil :: (() -> { Vector3 })?,
	}, CityTraffic)
end

-- People currently on crosswalks (positions), as obstacles for the cars.
function CityTraffic:SetPedestrianSource(source: () -> { Vector3 })
	self._pedestrians = source
end

-- True when a ground car is within radius of position (pedestrians check
-- before crossing where there is no traffic light).
function CityTraffic:CarNear(position: Vector3, radius: number): boolean
	for _, car in self._cars do
		if not car.air and car.active and (car.position - position).Magnitude < radius then
			return true
		end
	end
	return false
end

function CityTraffic:_clock(): number
	return Workspace:GetServerTimeNow()
end

-- ------------------------------------------------------------- lights ----

function CityTraffic:_buildPosts()
	local network = self._network
	for nodeIndex, node in network.nodes do
		if node.control ~= 1 or not node.phases then
			continue
		end
		local byStreet = {}
		for _, lane in network.lanes do
			if lane.to == nodeIndex then
				byStreet[lane.street] = byStreet[lane.street] or {}
				table.insert(byStreet[lane.street], lane)
			end
		end
		for street, lanes in byStreet do
			-- The outermost lane end (furthest right), then out to the curb.
			local bestPoint, bestForward, bestRight = nil, nil, -math.huge
			for _, lane in lanes do
				local point, forward = CityStreets.sample(lane.path, lane.path.length)
				local right = forward:Cross(Vector3.yAxis)
				local score = (point - node.position):Dot(right)
				if score > bestRight then
					bestPoint, bestForward, bestRight = point, forward, score
				end
			end
			if not bestPoint or not bestForward then
				continue
			end
			local flat = Vector3.new(bestForward.X, 0, bestForward.Z)
			if flat.Magnitude < 1e-3 then
				continue
			end
			flat = flat.Unit
			local right = flat:Cross(Vector3.yAxis)
			local base = bestPoint + right * Lights.CurbOffset
			local post = Instance.new("Model")
			post.Name = "Semaforo"
			local pole = part(post, "Pole", Vector3.new(0.45, Lights.PostHeight, 0.45), Color3.fromRGB(28, 30, 36), Enum.Material.Metal)
			pole.Anchored = true
			pole.CFrame = CFrame.lookAt(base + Vector3.yAxis * Lights.PostHeight / 2, base + Vector3.yAxis * Lights.PostHeight / 2 - flat)
			local head = part(post, "Head", Vector3.new(1.1, 3.2, 0.7), Color3.fromRGB(18, 18, 22), Enum.Material.Metal)
			head.Anchored = true
			-- Facing the approaching drivers.
			local headCenter = base + Vector3.yAxis * (Lights.PostHeight - 1.6)
			head.CFrame = CFrame.lookAt(headCenter, headCenter - flat)
			local lamps = {}
			for i, color in { "red", "yellow", "green" } do
				local lamp = part(post, "Lamp_" .. color, Vector3.new(0.7, 0.7, 0.15), LAMP_OFF, Enum.Material.SmoothPlastic)
				lamp.Anchored = true
				lamp.CFrame = head.CFrame * CFrame.new(0, 1 - (i - 1), -0.42)
				lamps[color] = lamp
			end
			post.Parent = self._folder
			table.insert(self._posts, { node = node, street = street, lamps = lamps, state = "" })
		end
	end
end

function CityTraffic:_updatePosts()
	local clock = self:_clock()
	for _, post in self._posts do
		local state = CityStreets.lightFor(post.node, post.street, clock, Lights)
		if state ~= post.state then
			post.state = state
			for color, lamp in post.lamps do
				local on = color == state
				lamp.Color = if on then LIGHT_COLORS[color] else LAMP_OFF
				lamp.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end
	end
end

-- ------------------------------------------------------------- routing ---

-- Next junction curve from a lane: weighted by turn, U-turns as a last resort.
function CityTraffic:_chooseConnector(laneIndex: number): number?
	local lane = self._network.lanes[laneIndex]
	local options, total = {}, 0
	local uturn = nil
	for _, connectorIndex in lane.outs do
		local connector = self._network.connectors[connectorIndex]
		local weight = if connector.turn == 0 then Cars.TurnWeights.straight
			elseif connector.turn == 1 then Cars.TurnWeights.right
			elseif connector.turn == 2 then Cars.TurnWeights.left
			else 0
		if weight > 0 then
			table.insert(options, { connectorIndex, weight })
			total += weight
		else
			uturn = connectorIndex
		end
	end
	if total <= 0 then
		return uturn
	end
	local roll = random:NextNumber() * total
	for _, option in options do
		roll -= option[2]
		if roll <= 0 then
			return option[1]
		end
	end
	return options[#options][1]
end

function CityTraffic:_chooseAir(airIndex: number): number?
	local outs = self._network.air[airIndex].outs
	if #outs == 0 then
		return nil
	end
	-- Prefer going on rather than doubling back over the same street.
	local street = self._network.air[airIndex].street
	local onward = {}
	for _, connectorIndex in outs do
		if self._network.air[self._network.airConnectors[connectorIndex].toAir].street ~= street then
			table.insert(onward, connectorIndex)
		end
	end
	return pick(if #onward > 0 then onward else outs)
end

-- ------------------------------------------------------------- spawning --

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
	return offset.Magnitude > 220 or offset.Unit:Dot(camera.CFrame.LookVector) < 0.35
end

function CityTraffic:_place(car, around: Vector3): boolean
	local network = self._network
	local list = if car.air then network.air else network.lanes
	if #list == 0 then
		return false
	end
	for attempt = 1, 40 do
		local index = random:NextInteger(1, #list)
		local path = list[index].path
		if path.length < 8 then
			continue
		end
		local distance = random:NextNumber() * path.length
		local position = CityStreets.sample(path, distance)
		local flat = Vector3.new(position.X - around.X, 0, position.Z - around.Z).Magnitude
		if flat < CityLifeConfig.SpawnMin or flat > CityLifeConfig.SpawnMax then
			continue
		end
		if attempt < 25 and not outOfView(position) then
			continue
		end
		local crowded = false
		for _, other in self._cars do
			if other ~= car and other.active and other.air == car.air and (other.position - position).Magnitude < 20 then
				crowded = true
				break
			end
		end
		if crowded then
			continue
		end
		car.onConnector = false
		car.index = index
		car.path = path
		car.distance = distance
		car.speed = car.cruise * 0.6
		car.nextConnector = if car.air then self:_chooseAir(index) else self:_chooseConnector(index)
		car.position = position
		car.forward = select(2, CityStreets.sample(path, distance))
		car.stuck = 0
		car.lastFlat = nil
		car.bank = 0
		car.active = true
		if car.air then
			local top = self:_airTopAhead(car)
			car.y = math.max(self._floorY + car.altitude, top + Air.Clearance)
		end
		car.model.Parent = self._folder
		return true
	end
	return false
end

function CityTraffic:_spawn(air: boolean, around: Vector3)
	local model, signals = buildCar(self._folder :: Folder, air)
	local speed = if air then Air.Speed else Cars.Speed
	local car = {
		air = air,
		model = model,
		signals = signals,
		cruise = speed.Min + random:NextNumber() * (speed.Max - speed.Min),
		altitude = if air then pick(Air.Altitudes) else 0,
		onConnector = false,
		index = 0,
		path = nil :: any,
		distance = 0,
		speed = 0,
		nextConnector = nil :: number?,
		position = Vector3.zero,
		forward = Vector3.zAxis,
		y = 0,
		bank = 0,
		stuck = 0,
		waitingLight = false,
		queued = false,
		lastFlat = nil :: Vector3?,
		accumulated = 0,
		active = false,
		leftOn = false,
		rightOn = false,
	}
	table.insert(self._cars, car)
	if not self:_place(car, around) then
		model.Parent = nil
	end
end

-- ------------------------------------------------------------- driving ---

-- Highest obstacle (world Y) under the next LookAhead studs of the route.
function CityTraffic:_airTopAhead(car): number
	local network = self._network
	local entry = if car.onConnector then network.airConnectors[car.index] else network.air[car.index]
	local best = -math.huge
	local function scan(path, tops, from: number, to: number)
		local cumulative = path.cumulative
		for i = 1, #tops do
			if cumulative[i] >= from - 10 and cumulative[i] <= to then
				best = math.max(best, tops[i])
			end
		end
	end
	scan(car.path, entry.tops, car.distance, car.distance + Air.LookAhead)
	local remaining = car.path.length - car.distance
	if remaining < Air.LookAhead then
		local nextEntry
		if car.onConnector then
			nextEntry = network.air[network.airConnectors[car.index].toAir]
		elseif car.nextConnector then
			nextEntry = network.airConnectors[car.nextConnector]
		end
		if nextEntry then
			scan(nextEntry.path, nextEntry.tops, 0, Air.LookAhead - remaining)
		end
	end
	return if best > -math.huge then best else self._floorY
end

-- Nearest obstacle ahead in this car's lane: another car going the same way,
-- or a pedestrian crossing (ground cars only). Returns the free gap in studs.
function CityTraffic:_gapAhead(car, pedestrians: { Vector3 }): (number, any)
	local nearest = math.huge
	local blocker = nil
	local forward = car.forward
	-- On junction curves the car ahead drifts sideways: look wider there.
	local width = if car.air then 6 elseif car.onConnector then 4.5 else 3.2
	for _, other in self._cars do
		if other ~= car and other.active and other.air == car.air then
			local offset = other.position - car.position
			if offset.Magnitude < Cars.LookAhead + Cars.Length and other.forward:Dot(forward) > 0.2 then
				local along = offset:Dot(forward)
				if along > 0 then
					local lateral = (offset - forward * along).Magnitude
					if lateral < width and along - Cars.Length < nearest then
						nearest = along - Cars.Length
						blocker = other
					end
				end
			end
		end
	end
	if not car.air then
		for _, position in pedestrians do
			local offset = position - car.position
			local along = offset:Dot(forward)
			if along > 0 and along < Cars.LookAhead then
				local lateral = (Vector3.new(offset.X, 0, offset.Z) - Vector3.new(forward.X, 0, forward.Z) * along).Magnitude
				if lateral < 4.5 and along - Cars.Length * 0.5 - 2 < nearest then
					nearest = along - Cars.Length * 0.5 - 2
					blocker = nil
				end
			end
		end
	end
	return nearest, blocker
end

-- A car already in the roundabout close to this entry.
function CityTraffic:_ringBusy(nodeIndex: number): boolean
	local network = self._network
	for _, other in self._cars do
		if other.air or not other.active then
			continue
		end
		if other.onConnector then
			local connector = network.connectors[other.index]
			if connector.node == nodeIndex and network.lanes[connector.fromLane].ring then
				return true
			end
		else
			local lane = network.lanes[other.index]
			if lane.ring and lane.to == nodeIndex and lane.path.length - other.distance < Cars.YieldDistance then
				return true
			end
		end
	end
	return false
end

function CityTraffic:_targetSpeed(car, pedestrians: { Vector3 }): number
	local network = self._network
	local target = car.cruise
	if car.air then
		local gap = self:_gapAhead(car, pedestrians)
		if gap < Air.Gap * 2 then
			target = math.min(target, math.max(0, (gap - Air.Gap) / Air.Gap) * car.cruise)
		end
		return target
	end
	car.waitingLight = false
	car.queued = false
	if car.onConnector then
		local connector = network.connectors[car.index]
		target = if connector.turn == 0 then car.cruise * 0.8 elseif connector.turn == 3 then Cars.UTurnSpeed else Cars.TurnSpeed
	else
		local lane = network.lanes[car.index]
		local remaining = car.path.length - car.distance
		local connector = car.nextConnector and network.connectors[car.nextConnector]
		if connector and connector.turn ~= 0 then
			local turnSpeed = if connector.turn == 3 then Cars.UTurnSpeed else Cars.TurnSpeed
			target = math.min(target, math.sqrt(turnSpeed * turnSpeed + 2 * Cars.Braking * 0.5 * remaining))
		end
		-- Stop line: red light, or a yellow too late to clear, or the ring busy.
		local node = network.nodes[lane.to]
		local mustStop = false
		-- The front bumper stops before the crosswalk (or the junction).
		local stopLine = (lane.stopBack or Cars.StopMargin) + Cars.Length * 0.5 + 1
		if node.control == 1 then
			local light = CityStreets.lightFor(node, lane.street, self:_clock(), Lights)
			local stoppingDistance = car.speed * car.speed / (2 * Cars.Braking)
			-- On yellow, go only if already moving and unable to stop in time.
			mustStop = light == "red" or (light == "yellow" and (car.speed < 2 or remaining - stopLine > stoppingDistance + 2))
		elseif node.control == 2 and not lane.ring then
			mustStop = self:_ringBusy(lane.to)
		end
		if mustStop and remaining > stopLine - 1 then
			car.waitingLight = true
			local room = math.max(0, remaining - stopLine)
			target = math.min(target, math.sqrt(2 * Cars.Braking * room))
			if room < 0.5 then
				target = 0
			end
		end
	end
	local gap, blocker = self:_gapAhead(car, pedestrians)
	if gap < Cars.LookAhead then
		target = math.min(target, math.sqrt(2 * Cars.Braking * math.max(0, gap - Cars.Gap)))
		-- Waiting behind a car that waits for the light is not being stuck.
		if blocker and (blocker.waitingLight or blocker.queued) then
			car.queued = true
		end
	end
	return target
end

function CityTraffic:_advance(car, distance: number)
	local network = self._network
	car.distance += distance
	while car.distance > car.path.length do
		local overflow = car.distance - car.path.length
		if car.onConnector then
			local connector = if car.air then network.airConnectors[car.index] else network.connectors[car.index]
			car.onConnector = false
			car.index = if car.air then connector.toAir else connector.toLane
			car.path = (if car.air then network.air[car.index] else network.lanes[car.index]).path
			car.nextConnector = if car.air then self:_chooseAir(car.index) else self:_chooseConnector(car.index)
		elseif car.nextConnector then
			car.onConnector = true
			car.index = car.nextConnector
			car.path = (if car.air then network.airConnectors[car.index] else network.connectors[car.index]).path
			car.nextConnector = nil
		else
			-- A street that leaves the city: this car is recycled elsewhere.
			car.active = false
			return
		end
		car.distance = overflow
	end
end

-- side: 0 none, 1 right, 2 left. Blinks; parts only change on a toggle.
function CityTraffic:_setSignal(car, side: number)
	local blink = side ~= 0 and (os.clock() % 0.8) < 0.4
	local left, right = blink and side == 2, blink and side == 1
	if car.leftOn == left and car.rightOn == right then
		return
	end
	car.leftOn, car.rightOn = left, right
	for _, signal in car.signals.left do
		signal.Transparency = if left then 0 else 1
	end
	for _, signal in car.signals.right do
		signal.Transparency = if right then 0 else 1
	end
end

function CityTraffic:_step(car, deltaTime: number, pedestrians: { Vector3 })
	local target = self:_targetSpeed(car, pedestrians)
	local braking = if car.air then 30 else Cars.Braking
	local acceleration = if car.air then 14 else Cars.Acceleration
	if target < car.speed then
		car.speed = math.max(target, car.speed - braking * 1.5 * deltaTime)
	else
		car.speed = math.min(target, car.speed + acceleration * deltaTime)
	end
	-- Never wait forever behind something that is not moving away (a red
	-- light is not "stuck": it always turns green).
	if car.speed < 0.5 and not car.waitingLight and not car.queued then
		car.stuck += deltaTime
	else
		car.stuck = 0
	end
	if car.stuck > 25 then
		car.active = false
		return
	end
	self:_advance(car, car.speed * deltaTime)
	if not car.active then
		return
	end
	local position, tangent = CityStreets.sample(car.path, car.distance)
	local alpha = 1 - math.exp(-10 * deltaTime)
	if car.air then
		local flat = Vector3.new(tangent.X, 0, tangent.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else car.forward
		local previous = Vector3.new(car.forward.X, 0, car.forward.Z)
		-- Bank from how fast the route itself turns (not from the easing
		-- lag), so it looks the same at any frame rate.
		local lastFlat = car.lastFlat or flat
		local turn = math.atan2(lastFlat:Cross(flat).Y, lastFlat:Dot(flat))
		car.lastFlat = flat
		local yawRate = turn / math.max(deltaTime, 1e-3)
		car.forward = previous:Lerp(flat, alpha)
		car.forward = if car.forward.Magnitude > 1e-3 then car.forward.Unit else flat
		local wanted = math.max(self._floorY + car.altitude, self:_airTopAhead(car) + Air.Clearance)
		local climb = (wanted - car.y) * (1 - math.exp(-Air.ClimbRate * deltaTime))
		car.y += climb
		-- Right turns have a negative yaw rate; a negative roll lowers the
		-- right side, so the car leans into the turn.
		car.bank += (math.clamp(yawRate * 0.35, -Air.MaxBank, Air.MaxBank) - car.bank) * alpha
		car.position = Vector3.new(position.X, car.y, position.Z)
		local pitch = math.atan2(climb / math.max(deltaTime, 1e-3), math.max(car.speed, 1)) * 0.6
		car.model:PivotTo(CFrame.lookAt(car.position, car.position + car.forward) * CFrame.Angles(pitch, 0, car.bank))
		return
	end
	car.forward = car.forward:Lerp(tangent, alpha)
	car.forward = if car.forward.Magnitude > 1e-3 then car.forward.Unit else tangent
	car.position = position
	car.model:PivotTo(CFrame.lookAt(position, position + car.forward))
	-- Turn signals: before and during a turn.
	local network = self._network
	local turn = 0
	if car.onConnector then
		turn = network.connectors[car.index].turn
	elseif car.nextConnector and car.path.length - car.distance < 40 then
		turn = network.connectors[car.nextConnector].turn
	end
	self:_setSignal(car, if turn == 1 then 1 elseif turn == 2 or turn == 3 then 2 else 0)
end

function CityTraffic:Update(deltaTime: number)
	local around = playerPosition()
	if not around then
		return
	end
	self._postTimer += deltaTime
	if self._postTimer > 0.2 then
		self._postTimer = 0
		self:_updatePosts()
	end
	local pedestrians = if self._pedestrians then self._pedestrians() else {}
	for _, car in self._cars do
		if car.active then
			local flat = Vector3.new(car.position.X - around.X, 0, car.position.Z - around.Z).Magnitude
			if flat > CityLifeConfig.ActiveRadius then
				car.active = false
			else
				car.accumulated += deltaTime
				-- Flying cars are seen from far away: they always update.
				if car.air or flat < CityLifeConfig.FarDistance or car.accumulated >= CityLifeConfig.FarUpdateInterval then
					self:_step(car, car.accumulated, pedestrians)
					car.accumulated = 0
				end
			end
		end
		if not car.active and not self:_place(car, around) then
			car.model.Parent = nil
		end
	end
end

function CityTraffic:Start(folder: Folder, density: number, around: Vector3)
	self._folder = folder
	self:_buildPosts()
	self:_updatePosts()
	for _ = 1, math.floor(Cars.Count * density + 0.5) do
		self:_spawn(false, around)
	end
	for _ = 1, math.floor(Air.Count * density + 0.5) do
		self:_spawn(true, around)
	end
end

function CityTraffic:Stop()
	for _, car in self._cars do
		car.model:Destroy()
	end
	table.clear(self._cars)
	table.clear(self._posts)
end

function CityTraffic:Count(): (number, number)
	local ground, flying = 0, 0
	for _, car in self._cars do
		if car.active then
			if car.air then
				flying += 1
			else
				ground += 1
			end
		end
	end
	return ground, flying
end

return CityTraffic
