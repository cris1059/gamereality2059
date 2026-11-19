--!strict

-- Angular shapes for the HUD from plain Frames: Roblox UI has no polygons
-- and the game uses no uploaded art, so
--   * fill: a convex polygon as horizontal strips (one Frame per `step`
--     pixels of height; strips never overlap, so transparency stays even);
--   * outline: one rotated Frame per edge, overlapping at the corners;
--   * chamfer / shield: point lists for the shapes the HUD uses.
-- Coordinates are design pixels relative to the parent (the HUD scales the
-- whole screen with a UIScale).

local Poly = {}

export type Points = { Vector2 }

local function bounds(points: Points): (number, number, number, number)
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, p in points do
		minX, minY = math.min(minX, p.X), math.min(minY, p.Y)
		maxX, maxY = math.max(maxX, p.X), math.max(maxY, p.Y)
	end
	return minX, minY, maxX, maxY
end

-- Convex polygon filled with `color`. Returns the holder Frame (its Size is
-- the polygon's bounding box, positioned at its top-left corner).
function Poly.fill(parent: Instance, name: string, points: Points, color: Color3, transparency: number, zIndex: number, step: number?): Frame
	local stride = step or 2
	local minX, minY, maxX, maxY = bounds(points)
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Position = UDim2.fromOffset(minX, minY)
	holder.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
	holder.ZIndex = zIndex
	local count = #points
	local y = minY
	while y < maxY - 1e-3 do
		local height = math.min(stride, maxY - y)
		local scan = y + height / 2
		local left, right = math.huge, -math.huge
		for index = 1, count do
			local a, b = points[index], points[index % count + 1]
			if (a.Y <= scan and b.Y >= scan) or (b.Y <= scan and a.Y >= scan) then
				local x = if math.abs(b.Y - a.Y) < 1e-6 then math.min(a.X, b.X) else a.X + (scan - a.Y) * (b.X - a.X) / (b.Y - a.Y)
				local x2 = if math.abs(b.Y - a.Y) < 1e-6 then math.max(a.X, b.X) else x
				left, right = math.min(left, x, x2), math.max(right, x, x2)
			end
		end
		if right > left then
			local strip = Instance.new("Frame")
			strip.BorderSizePixel = 0
			strip.BackgroundColor3 = color
			strip.BackgroundTransparency = transparency
			strip.Position = UDim2.fromOffset(left - minX, y - minY)
			strip.Size = UDim2.fromOffset(right - left, height)
			strip.ZIndex = zIndex
			strip.Parent = holder
		end
		y += height
	end
	holder.Parent = parent
	return holder
end

-- Recolours / fades every strip of a filled shape.
function Poly.paint(shape: Instance, color: Color3?, transparency: number?)
	for _, strip in shape:GetChildren() do
		if strip:IsA("Frame") then
			if color then
				strip.BackgroundColor3 = color
			end
			if transparency then
				strip.BackgroundTransparency = transparency
			end
		end
	end
end

-- Outline of a polygon (closed unless `open`). Returns a holder Frame.
function Poly.outline(parent: Instance, name: string, points: Points, color: Color3, thickness: number, transparency: number, zIndex: number, open: boolean?): Frame
	local holder = Instance.new("Frame")
	holder.Name = name
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = zIndex
	local count = #points
	local last = if open then count - 1 else count
	for index = 1, last do
		local a, b = points[index], points[index % count + 1]
		local delta = b - a
		local line = Instance.new("Frame")
		line.BorderSizePixel = 0
		line.BackgroundColor3 = color
		line.BackgroundTransparency = transparency
		line.AnchorPoint = Vector2.new(0.5, 0.5)
		local middle = (a + b) / 2
		line.Position = UDim2.fromOffset(middle.X, middle.Y)
		-- A little longer so neighbouring edges meet without a gap.
		line.Size = UDim2.fromOffset(delta.Magnitude + thickness * 0.8, thickness)
		line.Rotation = math.deg(math.atan2(delta.Y, delta.X))
		line.ZIndex = zIndex
		line.Parent = holder
	end
	holder.Parent = parent
	return holder
end

-- Rectangle (x, y, w, h) with its corners cut by the given sizes
-- (top-left, top-right, bottom-right, bottom-left; 0 = square corner).
function Poly.chamfer(x: number, y: number, w: number, h: number, tl: number, tr: number, br: number, bl: number): Points
	local points = {}
	local function add(px: number, py: number)
		local p = Vector2.new(px, py)
		if #points == 0 or (points[#points] - p).Magnitude > 1e-3 then
			table.insert(points, p)
		end
	end
	add(x + tl, y)
	add(x + w - tr, y)
	add(x + w, y + tr)
	add(x + w, y + h - br)
	add(x + w - br, y + h)
	add(x + bl, y + h)
	add(x, y + h - bl)
	add(x, y + tl)
	if (points[1] - points[#points]).Magnitude < 1e-3 then
		table.remove(points)
	end
	return points
end

-- Parallelogram leaning right by `skew` pixels (health / ammo segments).
function Poly.slant(x: number, y: number, w: number, h: number, skew: number): Points
	return {
		Vector2.new(x + skew, y), Vector2.new(x + w + skew, y),
		Vector2.new(x + w, y + h), Vector2.new(x, y + h),
	}
end

-- Points moved in (or out, if negative) towards their centroid by `amount`
-- pixels, for inner frames and glows of the same shape.
function Poly.inset(points: Points, amount: number): Points
	local center = Vector2.zero
	for _, p in points do
		center += p
	end
	center /= #points
	local result = {}
	for _, p in points do
		local away = p - center
		local length = away.Magnitude
		table.insert(result, if length > 1e-3 then p - away.Unit * amount else p)
	end
	return result
end

return Poly
