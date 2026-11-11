--!strict

-- Runtime street network for the ambient city life: World/City2059Streets
-- (glTF units, generated from the real road and sidewalk geometry) mapped
-- to the world, plus path sampling helpers. Pure; the client builds it with
-- the transform the server publishes on the FreeRoam model (CityRef*
-- attributes, see CityWorldService).

local CityStreets = {}

export type Path = {
	points: { Vector3 },
	cumulative: { number },
	length: number,
	closed: boolean,
}

export type Network = {
	nodes: { any },
	lanes: { any },
	connectors: { any },
	air: { any },
	airConnectors: { any },
	walkways: { any },
	walkNodes: { Vector3 },
	walkAt: { [number]: { number } },
	crosswalks: { any },
	studsPerUnit: number,
}

function CityStreets.makePath(points: { Vector3 }): Path
	local cumulative = table.create(#points, 0)
	local total = 0
	for i = 2, #points do
		total += (points[i] - points[i - 1]).Magnitude
		cumulative[i] = total
	end
	local closed = #points > 2 and (points[1] - points[#points]).Magnitude < 1e-3
	return { points = points, cumulative = cumulative, length = total, closed = closed }
end

-- Segment index i such that cumulative[i] <= distance <= cumulative[i + 1].
local function segmentAt(path: Path, distance: number): number
	local cumulative = path.cumulative
	local low, high = 1, #cumulative - 1
	while low < high do
		local middle = (low + high + 1) // 2
		if cumulative[middle] <= distance then
			low = middle
		else
			high = middle - 1
		end
	end
	return low
end

-- Position and unit tangent at a distance along the path (clamped, or
-- wrapped on closed loops).
function CityStreets.sample(path: Path, distance: number): (Vector3, Vector3)
	local points = path.points
	if #points == 1 then
		return points[1], Vector3.zAxis
	end
	if path.closed and path.length > 0 then
		distance %= path.length
	else
		distance = math.clamp(distance, 0, path.length)
	end
	local i = segmentAt(path, distance)
	local a, b = points[i], points[i + 1]
	local span = path.cumulative[i + 1] - path.cumulative[i]
	local f = if span > 1e-6 then (distance - path.cumulative[i]) / span else 0
	local delta = b - a
	return a + delta * f, if delta.Magnitude > 1e-6 then delta.Unit else Vector3.zAxis
end

-- Distance along the path of the point nearest to `position`.
function CityStreets.project(path: Path, position: Vector3): number
	local best, bestDistance = math.huge, 0
	local points = path.points
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local ab = b - a
		local lengthSquared = ab:Dot(ab)
		local f = if lengthSquared > 1e-9 then math.clamp((position - a):Dot(ab) / lengthSquared, 0, 1) else 0
		local gap = (a + ab * f - position).Magnitude
		if gap < best then
			best = gap
			bestDistance = path.cumulative[i] + f * math.sqrt(lengthSquared)
		end
	end
	return bestDistance
end

-- glTF -> world from the FreeRoam model's attributes; nil when the city was
-- not found (no attributes).
function CityStreets.transformFrom(model: Instance): ((Vector3) -> Vector3)?
	local frame = model:GetAttribute("CityRefFrame")
	local center = model:GetAttribute("CityRefCenter")
	local scale = model:GetAttribute("CityScaleVector")
	local signs = model:GetAttribute("CityAxisSigns")
	if typeof(frame) ~= "CFrame" or typeof(center) ~= "Vector3" or typeof(scale) ~= "Vector3" or typeof(signs) ~= "Vector3" then
		return nil
	end
	local factor = scale * signs
	return function(point: Vector3): Vector3
		return frame * ((point - center) * factor)
	end
end

local function points(entry: { number }, first: number, toWorld: (Vector3) -> Vector3): { Vector3 }
	local result = {}
	for i = first, #entry - 2, 3 do
		table.insert(result, toWorld(Vector3.new(entry[i], entry[i + 1], entry[i + 2])))
	end
	return result
end

-- data: World/City2059Streets; studsPerUnit: city scale (radii, distances).
function CityStreets.build(data, toWorld: (Vector3) -> Vector3, studsPerUnit: number): Network
	local nodes = {}
	for _, entry in data.Nodes do
		table.insert(nodes, {
			position = toWorld(Vector3.new(entry[1], entry[2], entry[3])),
			radius = entry[4] * studsPerUnit,
			control = entry[5],
			phases = nil :: { [number]: number }?,
		})
	end
	for nodeIndex, phases in data.Phases do
		nodes[nodeIndex].phases = phases
	end

	local lanes = {}
	for _, entry in data.Lanes do
		table.insert(lanes, {
			street = entry[1],
			from = entry[2],
			to = entry[3],
			oneWay = bit32.band(entry[4], 1) ~= 0,
			ring = bit32.band(entry[4], 2) ~= 0,
			path = CityStreets.makePath(points(entry, 5, toWorld)),
			outs = {} :: { number },
		})
	end
	local connectors = {}
	for index, entry in data.Connectors do
		table.insert(connectors, {
			fromLane = entry[1],
			toLane = entry[2],
			node = entry[3],
			turn = entry[4],
			path = CityStreets.makePath(points(entry, 5, toWorld)),
		})
		table.insert(lanes[entry[1]].outs, index)
	end

	-- Air paths keep the obstacle height under each point as world Y.
	local function airPath(entry: { number }, first: number)
		local list, tops = {}, {}
		for i = first, #entry - 2, 3 do
			local world = toWorld(Vector3.new(entry[i], entry[i + 1], entry[i + 2]))
			table.insert(list, world)
			table.insert(tops, world.Y)
		end
		local path = CityStreets.makePath(list)
		return path, tops
	end
	local air = {}
	for _, entry in data.AirLanes do
		local path, tops = airPath(entry, 4)
		table.insert(air, { street = entry[1], from = entry[2], to = entry[3], path = path, tops = tops, outs = {} :: { number } })
	end
	local airConnectors = {}
	for index, entry in data.AirConnectors do
		local path, tops = airPath(entry, 3)
		table.insert(airConnectors, { fromAir = entry[1], toAir = entry[2], path = path, tops = tops })
		table.insert(air[entry[1]].outs, index)
	end

	local walkways, walkAt = {}, {}
	for index, entry in data.Walkways do
		local walkway = { a = entry[1], b = entry[2], path = CityStreets.makePath(points(entry, 3, toWorld)), crossings = {} }
		table.insert(walkways, walkway)
		for _, node in { entry[1], entry[2] } do
			walkAt[node] = walkAt[node] or {}
			if not table.find(walkAt[node], index) then
				table.insert(walkAt[node], index)
			end
		end
	end
	local walkNodes = {}
	for _, entry in data.WalkNodes do
		table.insert(walkNodes, toWorld(Vector3.new(entry[1], entry[2], entry[3])))
	end
	-- Where a crosswalk crosses a lane before its junction, cars stop behind
	-- it: stopBack = distance from that crossing to the end of the lane.
	local function crossing2D(a: Vector3, b: Vector3, c: Vector3, d: Vector3): number?
		local rx, rz = b.X - a.X, b.Z - a.Z
		local sx, sz = d.X - c.X, d.Z - c.Z
		local denominator = rx * sz - rz * sx
		if math.abs(denominator) < 1e-9 then
			return nil
		end
		local t = ((c.X - a.X) * sz - (c.Z - a.Z) * sx) / denominator
		local u = ((c.X - a.X) * rz - (c.Z - a.Z) * rx) / denominator
		return if t >= 0 and t <= 1 and u >= 0 and u <= 1 then t else nil
	end
	local crosswalks = {}
	for index, entry in data.Crosswalks do
		local path = CityStreets.makePath(points(entry, 5, toWorld))
		local first, last = path.points[1], path.points[#path.points]
		local crosswalk = {
			a = entry[1],
			b = entry[2],
			node = entry[3],
			street = entry[4],
			path = path,
			distA = CityStreets.project(walkways[entry[1]].path, first),
			distB = CityStreets.project(walkways[entry[2]].path, last),
			middle = (first + last) / 2,
		}
		table.insert(crosswalks, crosswalk)
		table.insert(walkways[entry[1]].crossings, { distance = crosswalk.distA, crosswalk = index, fromStart = true })
		table.insert(walkways[entry[2]].crossings, { distance = crosswalk.distB, crosswalk = index, fromStart = false })
		for _, lane in lanes do
			if lane.to == crosswalk.node then
				local lanePoints = lane.path.points
				for i = 1, #lanePoints - 1 do
					local t = crossing2D(lanePoints[i], lanePoints[i + 1], first, last)
					if t then
						local along = lane.path.cumulative[i] + t * (lane.path.cumulative[i + 1] - lane.path.cumulative[i])
						-- Half a crosswalk's width behind the painted line.
						lane.stopBack = math.max(lane.stopBack or 0, lane.path.length - along + 2)
						break
					end
				end
			end
		end
	end

	return {
		nodes = nodes,
		lanes = lanes,
		connectors = connectors,
		air = air,
		airConnectors = airConnectors,
		walkways = walkways,
		walkNodes = walkNodes,
		walkAt = walkAt,
		crosswalks = crosswalks,
		studsPerUnit = studsPerUnit,
	}
end

-- Moves the whole network up or down (vertical correction, see CityLife).
function CityStreets.shift(network: Network, dy: number)
	local offset = Vector3.new(0, dy, 0)
	local function move(path: Path)
		for i, point in path.points do
			path.points[i] = point + offset
		end
	end
	for _, node in network.nodes do
		node.position += offset
	end
	for _, list in { network.lanes, network.connectors, network.walkways } do
		for _, entry in list do
			move(entry.path)
		end
	end
	for _, list in { network.air, network.airConnectors } do
		for _, entry in list do
			move(entry.path)
			for i, top in entry.tops do
				entry.tops[i] = top + dy
			end
		end
	end
	for _, crosswalk in network.crosswalks do
		move(crosswalk.path)
		crosswalk.middle += offset
	end
	for i, point in network.walkNodes do
		network.walkNodes[i] = point + offset
	end
end

-- Traffic light of one approach street at a light node: "green", "yellow"
-- or "red", and the seconds until it changes. Driven by the shared server
-- clock so every client agrees. Phase 1 is green first, phase 2 half a cycle
-- later; each phase's red covers the all-red gaps and the other phase.
function CityStreets.lightState(node, street: number, clock: number, timing): (string, number)
	local phases = node.phases
	local phase = phases and phases[street]
	if not phase then
		return "green", math.huge
	end
	local green, yellow = timing.Green, timing.Yellow
	local half = green + yellow + timing.AllRed
	-- Each junction starts its cycle at its own offset.
	local offset = (node.position.X * 0.37 + node.position.Z * 0.61) % (2 * half)
	local sinceGreen = (clock + offset - (phase - 1) * half) % (2 * half)
	if sinceGreen < green then
		return "green", green - sinceGreen
	elseif sinceGreen < green + yellow then
		return "yellow", green + yellow - sinceGreen
	end
	return "red", 2 * half - sinceGreen
end

function CityStreets.lightFor(node, street: number, clock: number, timing): string
	return (CityStreets.lightState(node, street, clock, timing))
end

return CityStreets
