--!strict

-- Centre crosshair, on its own layer above every HUD decoration: four ticks
-- and a dot that open with each shot and settle back (tighter while aiming),
-- white diagonal ticks to confirm a hit, larger red ones and a ring flash to
-- confirm an elimination. Shots and hits come from CombatController.

local HUDConfig = require(script.Parent.HUDConfig)
local UIKit = require(script.Parent.UIKit)

local P = HUDConfig.Palette
local C = HUDConfig.Crosshair

local Crosshair = {}
Crosshair.__index = Crosshair

local function tick(parent: Instance, name: string, size: Vector2, zIndex: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BorderSizePixel = 0
	frame.BackgroundColor3 = P.White
	frame.Size = UDim2.fromOffset(size.X, size.Y)
	frame.ZIndex = zIndex
	local stroke = Instance.new("UIStroke")
	stroke.Color = P.Carbon
	stroke.Transparency = 0.5
	stroke.Thickness = 1
	stroke.Parent = frame
	frame.Parent = parent
	return frame
end

function Crosshair.new(parent: Instance)
	local root = Instance.new("Frame")
	root.Name = "Crosshair"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(120, 120)
	root.BackgroundTransparency = 1
	root.ZIndex = 50
	root.Parent = parent
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local arms = {
		{ frame = tick(root, "Up", Vector2.new(2, C.Length), 51), dir = Vector2.new(0, -1) },
		{ frame = tick(root, "Down", Vector2.new(2, C.Length), 51), dir = Vector2.new(0, 1) },
		{ frame = tick(root, "Left", Vector2.new(C.Length, 2), 51), dir = Vector2.new(-1, 0) },
		{ frame = tick(root, "Right", Vector2.new(C.Length, 2), 51), dir = Vector2.new(1, 0) },
	}
	local dot = tick(root, "Dot", Vector2.new(2, 2), 51)
	dot.Position = UDim2.fromScale(0.5, 0.5)

	-- Hit confirmation: four diagonal ticks.
	local hit = Instance.new("Frame")
	hit.Name = "Hit"
	hit.BackgroundTransparency = 1
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 52
	hit.Parent = root
	local hitTicks = {}
	for index, angle in { 45, 135, 225, 315 } do
		local frame = tick(hit, "Tick" .. index, Vector2.new(9, 2), 52)
		frame.Rotation = angle
		local radians = math.rad(angle)
		frame.Position = UDim2.new(0.5, math.cos(radians) * 11, 0.5, math.sin(radians) * 11)
		table.insert(hitTicks, frame)
	end
	hit.Visible = false
	-- Elimination ring.
	local ring = Instance.new("Frame")
	ring.Name = "KillRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromOffset(20, 20)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 52
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = P.Danger
	ringStroke.Thickness = 2
	ringStroke.Transparency = 1
	ringStroke.Parent = ring
	ring.Parent = root

	return setmetatable({
		_root = root,
		_scale = scale,
		_arms = arms,
		_dot = dot,
		_hit = hit,
		_hitTicks = hitTicks,
		_ring = ring,
		_ringStroke = ringStroke,
		_spread = 0,
		_aiming = false,
		_hitUntil = 0,
		_clock = 0,
	}, Crosshair)
end

function Crosshair:Place(uiScale: number)
	self._scale.Scale = uiScale
end

function Crosshair:SetVisible(visible: boolean)
	self._root.Visible = visible
end

function Crosshair:SetAiming(aiming: boolean)
	self._aiming = aiming
end

-- A shot: the ticks open a little.
function Crosshair:Shot()
	self._spread = math.min(self._spread + C.ShotSpread, C.MaxSpread)
end

-- A confirmed hit (killed = an elimination).
function Crosshair:Hit(killed: boolean)
	local color = if killed then P.Danger else P.White
	local length = if killed then 13 else 9
	for _, frame in self._hitTicks do
		frame.BackgroundColor3 = color
		frame.Size = UDim2.fromOffset(length, 2)
	end
	self._hit.Visible = true
	self._hitUntil = self._clock + (if killed then C.KillTime else C.HitTime)
	if killed then
		self._ring.Size = UDim2.fromOffset(18, 18)
		self._ringStroke.Transparency = 0
		UIKit.tween(self._ring, C.KillTime, { Size = UDim2.fromOffset(46, 46) })
		UIKit.tween(self._ringStroke, C.KillTime, { Transparency = 1 })
	end
end

function Crosshair:Update(deltaTime: number)
	self._clock += deltaTime
	self._spread = math.max(self._spread - C.RecoverSpeed * deltaTime, 0)
	local gap = (if self._aiming then C.Gap * 0.6 else C.Gap) + self._spread
	for _, arm in self._arms do
		local offset = arm.dir * (gap + C.Length / 2)
		arm.frame.Position = UDim2.new(0.5, offset.X, 0.5, offset.Y)
	end
	if self._hit.Visible and self._clock >= self._hitUntil then
		self._hit.Visible = false
	end
end

function Crosshair:Destroy()
	self._root:Destroy()
end

return Crosshair
