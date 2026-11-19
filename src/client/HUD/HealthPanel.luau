--!strict

-- Bottom-left health module: the character portrait in a pointed shield
-- frame, the segmented health bar and the player's identity, as one piece.
-- States (worked out by the HUD from real data):
--   normal   - cyan frame, slow breathing glow, an occasional light sweep
--   gloat    - kill streak: violet frame, wings out, closer portrait, streak tag
--   critical - 25 % or less: red frame pulsing, short controlled glitches,
--              medical alert
--   dead     - everything dimmed until the respawn
-- Health always comes from the Humanoid (server-authoritative); the bar is
-- proportional to MaxHealth whatever its value. The bar follows quickly; a
-- white "ghost" shows the health just lost before draining; healing flashes.

local HUDConfig = require(script.Parent.HUDConfig)
local Poly = require(script.Parent.Poly)
local Portrait = require(script.Parent.Portrait)
local UIKit = require(script.Parent.UIKit)

local P = HUDConfig.Palette
local F = HUDConfig.Fonts
local H = HUDConfig.Health

local HealthPanel = {}
HealthPanel.__index = HealthPanel

export type State = "normal" | "gloat" | "critical" | "dead"

local SIZE = Vector2.new(480, 168)
local SHIELD = {
	Vector2.new(16, 0), Vector2.new(120, 0), Vector2.new(120, 122),
	Vector2.new(60, 166), Vector2.new(0, 122), Vector2.new(0, 16),
}
local VIEW_POSITION = Vector2.new(9, 8)
local VIEW_SIZE = Vector2.new(102, 112)
local BAR = { x = 140, y = 78, width = 304, height = 16, gap = 4, skew = 5 }

local STATE_COLORS: { [string]: Color3 } = {
	normal = P.Electric,
	gloat = P.Violet,
	critical = P.Danger,
	dead = P.Muted,
}
local STATUS_TEXT: { [string]: string } = {
	normal = "ESTABLE",
	gloat = "DOMINANDO",
	critical = "CRÍTICO",
	dead = "ELIMINADO",
}

local function bandColor(fraction: number): Color3
	if fraction <= H.Critical then
		return P.Danger
	elseif fraction <= H.Caution then
		return P.Amber
	end
	return P.Electric
end

-- One row of slanted segments (a layer of the bar) inside `parent`.
local function segments(parent: Instance, name: string, color: Color3, transparency: number, zIndex: number): { Frame }
	local list = {}
	local count = H.Segments
	local width = (BAR.width - (count - 1) * BAR.gap) / count
	for index = 1, count do
		local x = (index - 1) * (width + BAR.gap)
		table.insert(list, Poly.fill(parent, name .. index, Poly.slant(x, 0, width, BAR.height, BAR.skew), color, transparency, zIndex, 2))
	end
	return list
end

-- A clipping strip over the bar: its width is the shown share of health.
local function clip(parent: Instance, name: string, zIndex: number): Frame
	local frame = UIKit.frame(parent, name, Vector2.new(BAR.x, BAR.y), Vector2.new(BAR.width + BAR.skew, BAR.height), zIndex)
	frame.ClipsDescendants = true
	return frame
end

function HealthPanel.new(parent: Instance)
	local root = UIKit.anchored(parent, "HealthModule", Vector2.new(0, 1), SIZE, Vector2.zero, 10)
	local scale = Instance.new("UIScale")
	scale.Parent = root

	-- Portrait shield: aura, glass body, picture, inner line, border.
	local aura = Poly.outline(root, "Aura", Poly.inset(SHIELD, -3), P.Electric, 7, 0.8, 11)
	local body = Poly.fill(root, "Body", SHIELD, P.Carbon, 0.12, 12, 2)
	local portraitHolder = UIKit.frame(root, "Portrait", Vector2.zero, Vector2.new(120, 166), 13)
	local portrait = Portrait.new(portraitHolder, VIEW_SIZE, VIEW_POSITION, 13)
	-- Depth: the picture fades into the metal at the bottom, glass sheen on top.
	local fade = UIKit.box(root, "PortraitFade", Vector2.new(VIEW_POSITION.X, VIEW_POSITION.Y + VIEW_SIZE.Y - 40), Vector2.new(VIEW_SIZE.X, 40), P.Carbon, 0, 14)
	UIKit.gradient(fade, P.Carbon, P.Carbon, 90, NumberSequence.new(1, 0))
	local sheen = UIKit.box(root, "Sheen", VIEW_POSITION, Vector2.new(VIEW_SIZE.X, 46), P.White, 0, 14)
	UIKit.gradient(sheen, P.White, P.White, 90, NumberSequence.new(0.88, 1))
	-- Scan line for the glitch.
	local scan = UIKit.box(root, "ScanLine", Vector2.new(VIEW_POSITION.X, 40), Vector2.new(VIEW_SIZE.X, 2), P.Danger, 1, 15)
	-- Class emblem in the point.
	local emblemPoints = { Vector2.new(38, 128), Vector2.new(60, 138), Vector2.new(82, 128), Vector2.new(60, 156) }
	local emblem = Poly.fill(root, "Emblem", emblemPoints, P.Violet, 0.1, 15, 1)
	Poly.outline(root, "EmblemLine", emblemPoints, P.White, 1, 0.75, 16)
	Poly.outline(root, "Inner", Poly.inset(SHIELD, 4), P.MetalLight, 1, 0.35, 16)
	local border = Poly.outline(root, "Border", SHIELD, P.Electric, 2, 0, 17)
	-- Corner bracket and a diagonal light that sweeps across now and then.
	local bracket = Poly.outline(root, "Bracket", { Vector2.new(100, -6), Vector2.new(126, -6), Vector2.new(126, 20) }, P.Electric, 2, 0.1, 17, true)
	local sweep = UIKit.box(portraitHolder, "Sweep", Vector2.new(-30, -20), Vector2.new(14, 200), P.White, 0.8, 16)
	sweep.Rotation = 20
	portraitHolder.ClipsDescendants = true

	-- Gloat wings (hidden until a streak).
	local wings = UIKit.frame(root, "Wings", Vector2.zero, SIZE, 10)
	local leftWing = { Vector2.new(-18, 34), Vector2.new(-6, 26), Vector2.new(-6, 108), Vector2.new(-18, 98) }
	local topCrown = { Vector2.new(30, -14), Vector2.new(90, -14), Vector2.new(80, -6), Vector2.new(40, -6) }
	local wingShapes = {
		Poly.fill(wings, "LeftWing", leftWing, P.Violet, 0.2, 10, 1),
		Poly.fill(wings, "Crown", topCrown, P.Violet, 0.2, 10, 1),
	}
	local wingLines = {
		Poly.outline(wings, "LeftWingLine", leftWing, P.Cyan, 1, 0.3, 11),
		Poly.outline(wings, "CrownLine", topCrown, P.Cyan, 1, 0.3, 11),
	}
	wings.Visible = false

	-- Connector from the shield to the readout plate.
	Poly.outline(root, "Connector", { Vector2.new(120, 52), Vector2.new(132, 52), Vector2.new(138, 46) }, P.Electric, 1, 0.4, 12, true)
	local plate = Poly.chamfer(130, 20, 340, 104, 0, 16, 0, 0)
	Poly.fill(root, "Plate", plate, P.Carbon, 0.42, 9, 2)
	local plateLine = Poly.outline(root, "PlateLine", plate, P.Electric, 1, 0.7, 10)

	-- Medical cross, the numbers, the status tag.
	local cross = UIKit.frame(root, "Medical", Vector2.new(140, 34), Vector2.new(22, 22), 12)
	local crossH = UIKit.box(cross, "H", Vector2.new(3, 9), Vector2.new(16, 4), P.Electric, 0, 12)
	local crossV = UIKit.box(cross, "V", Vector2.new(9, 3), Vector2.new(4, 16), P.Electric, 0, 12)
	Poly.outline(cross, "Ring", Poly.chamfer(0, 0, 22, 22, 5, 0, 5, 0), P.Electric, 1, 0.5, 12)
	local value = UIKit.text(root, "Value", "", Vector2.new(170, 24), Vector2.new(220, 44), F.Display, 40, P.White, 12)
	value.RichText = true
	UIKit.shadow(value)
	local status = UIKit.text(root, "Status", "ESTABLE", Vector2.new(350, 30), Vector2.new(110, 16), F.Technical, 12, P.Electric, 12, Enum.TextXAlignment.Right)
	local streak = UIKit.text(root, "Streak", "", Vector2.new(350, 48), Vector2.new(110, 18), F.Display, 16, P.Violet, 12, Enum.TextXAlignment.Right)

	-- The bar: empty segments, the white ghost, the fill.
	local track = UIKit.frame(root, "Track", Vector2.new(BAR.x, BAR.y), Vector2.new(BAR.width + BAR.skew, BAR.height), 12)
	segments(track, "Empty", P.Metal, 0.25, 12)
	local ghostClip = clip(root, "Ghost", 13)
	local ghost = segments(ghostClip, "Ghost", P.White, 0.15, 13)
	local fillClip = clip(root, "Fill", 14)
	local fill = segments(fillClip, "Fill", P.Electric, 0, 14)
	local shine = UIKit.box(fillClip, "Shine", Vector2.zero, Vector2.new(BAR.width + BAR.skew, 5), P.White, 0, 15)
	UIKit.gradient(shine, P.White, P.White, 90, NumberSequence.new(0.6, 1))
	-- Tick marks under the bar every quarter.
	for index = 0, 4 do
		UIKit.box(root, "Tick" .. index, Vector2.new(BAR.x + index * BAR.width / 4, BAR.y + BAR.height + 3), Vector2.new(1, 5), P.Muted, 0.4, 12)
	end

	-- Identity: side light, name, class and level, medical alert.
	local sideLight = UIKit.box(root, "SideLight", Vector2.new(140, 104), Vector2.new(3, 30), P.Electric, 0, 12)
	local name = UIKit.text(root, "PlayerName", "", Vector2.new(150, 102), Vector2.new(230, 18), F.Interface, 17, P.White, 12)
	name.FontFace = Font.new(name.FontFace.Family, Enum.FontWeight.Bold)
	UIKit.shadow(name, 0.7)
	local class = UIKit.text(root, "ClassLine", "", Vector2.new(150, 120), Vector2.new(230, 14), F.Technical, 12, P.Cyan, 12)
	local alert = UIKit.text(root, "Alert", "+ ALERTA MÉDICA // SOPORTE VITAL", Vector2.new(250, 120), Vector2.new(215, 14), F.Technical, 11, P.Danger, 12, Enum.TextXAlignment.Right)
	alert.Visible = false

	local self = setmetatable({
		_root = root,
		_scale = scale,
		_portrait = portrait,
		_aura = aura,
		_body = body,
		_border = border,
		_bracket = bracket,
		_plateLine = plateLine,
		_emblem = emblem,
		_crossParts = { crossH, crossV },
		_value = value,
		_status = status,
		_streak = streak,
		_ghostClip = ghostClip,
		_ghost = ghost,
		_fillClip = fillClip,
		_fill = fill,
		_sideLight = sideLight,
		_name = name,
		_class = class,
		_alert = alert,
		_scan = scan,
		_sweep = sweep,
		_wings = wings,
		_wingShapes = wingShapes,
		_wingLines = wingLines,
		_state = "normal" :: State,
		_fraction = 1,
		_health = 0,
		_maxHealth = 0,
		_ghostTween = nil :: Tween?,
		_ghostTask = nil :: thread?,
		_clock = 0,
		_nextSweep = 3,
		_nextGlitch = 1,
		_glitchUntil = 0,
	}, HealthPanel)
	self:_paint()
	return self
end

-- Screen scale and distance from the corner (design pixels).
function HealthPanel:Place(uiScale: number, margin: number)
	self._scale.Scale = uiScale
	self._root.Position = UDim2.new(0, margin * uiScale, 1, -margin * uiScale)
end

function HealthPanel:SetIdentity(playerName: string, classLine: string, classColor: Color3?)
	self._name.Text = string.upper(playerName)
	self._class.Text = classLine
	if classColor then
		Poly.paint(self._emblem, classColor)
	end
end

function HealthPanel:SetCharacter(character: Model?, classId: string?)
	self._portrait:SetCharacter(character, classId)
end

-- Colours of everything that follows the state (and the health band).
function HealthPanel:_paint()
	local state = self._state
	local accent = STATE_COLORS[state]
	local band = if state == "dead" then P.Muted else bandColor(self._fraction)
	for _, line in { self._border, self._bracket } do
		Poly.paint(line, accent)
	end
	Poly.paint(self._aura, accent)
	Poly.paint(self._plateLine, accent)
	for _, part in self._crossParts do
		part.BackgroundColor3 = band
	end
	for _, segment in self._fill do
		Poly.paint(segment, band)
	end
	self._sideLight.BackgroundColor3 = accent
	self._status.Text = STATUS_TEXT[state]
	self._status.TextColor3 = accent
	self._class.TextColor3 = if state == "gloat" then P.Violet else P.Cyan
	self._alert.Visible = state == "critical"
	self._wings.Visible = state == "gloat"
	self._scan.BackgroundTransparency = 1
	self._alert.TextTransparency = 0
	self._portrait:SetOffset(Vector2.zero, VIEW_POSITION)
	self._portrait:SetTint(if state == "dead" then Color3.fromRGB(90, 96, 110) else Color3.new(1, 1, 1))
end

function HealthPanel:SetState(state: State)
	if self._state == state then
		return
	end
	local previous = self._state
	self._state = state
	self._portrait:SetState(if state == "dead" then "critical" else state :: any)
	self:_paint()
	if state == "gloat" and previous ~= "gloat" then
		-- Activation: the wings spread out from the shield.
		for index, shape in self._wingShapes do
			Poly.paint(shape, nil, 1)
			for _, strip in shape:GetChildren() do
				if strip:IsA("Frame") then
					UIKit.tween(strip, 0.35, { BackgroundTransparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, index * 0.05)
				end
			end
		end
		self._root.Position += UDim2.fromOffset(0, -4)
		UIKit.tween(self._root, 0.3, { Position = self._root.Position + UDim2.fromOffset(0, 4) }, Enum.EasingStyle.Back)
	end
end

function HealthPanel:SetStreak(kills: number)
	self._streak.Text = if kills >= 2 then string.format("RACHA x%d", kills) else ""
end

-- New health from the Humanoid. The fill follows quickly; on damage the
-- ghost keeps the old width for a moment and then drains; on healing the
-- fill flashes white.
function HealthPanel:SetHealth(health: number, maxHealth: number)
	local max = math.max(maxHealth, 1)
	local fraction = math.clamp(health / max, 0, 1)
	local previous = self._fraction
	local healed = fraction > previous + 1e-3 and self._health > 0
	self._health, self._maxHealth, self._fraction = health, maxHealth, fraction
	self._value.Text = string.format(
		'%d<font size="18" color="#8FA9C0"> / %d</font><font size="13" color="#8FA9C0">  HP</font>',
		math.ceil(math.max(health, 0)), math.ceil(maxHealth)
	)
	local full = BAR.width + BAR.skew
	UIKit.tween(self._fillClip, H.FollowTime, { Size = UDim2.fromOffset(full * fraction, BAR.height) })
	if fraction < previous then
		if self._ghostTween then
			self._ghostTween:Cancel()
		end
		local ghostWidth = math.max(self._ghostClip.Size.X.Offset, full * previous)
		self._ghostClip.Size = UDim2.fromOffset(ghostWidth, BAR.height)
		self._ghostTween = UIKit.tween(self._ghostClip, H.GhostDrain, { Size = UDim2.fromOffset(full * fraction, BAR.height) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, H.GhostDelay)
		-- The frame flinches.
		Poly.paint(self._aura, nil, 0.45)
		for _, strip in self._aura:GetChildren() do
			if strip:IsA("Frame") then
				UIKit.tween(strip, 0.4, { BackgroundTransparency = 0.8 })
			end
		end
	else
		self._ghostClip.Size = UDim2.fromOffset(full * fraction, BAR.height)
	end
	self:_paint()
	if healed then
		for _, segment in self._fill do
			for _, strip in segment:GetChildren() do
				if strip:IsA("Frame") then
					strip.BackgroundColor3 = P.White
					UIKit.tween(strip, H.HealFlashTime, { BackgroundColor3 = bandColor(fraction) })
				end
			end
		end
	end
end

-- Per-frame life: breathing glow, the occasional light sweep, the critical
-- pulse and glitches. Cheap: a few property writes.
function HealthPanel:Update(deltaTime: number)
	self._clock += deltaTime
	local t = self._clock
	local state = self._state
	if state == "critical" then
		-- Slow red pulse of the frame and the alert.
		local pulse = (math.sin(t * 5) + 1) / 2
		Poly.paint(self._border, nil, 0.35 * pulse)
		self._alert.TextTransparency = 0.45 * pulse
		if t >= self._nextGlitch then
			self._nextGlitch = t + 1.4 + math.random() * 1.6
			self._glitchUntil = t + 0.09
			self._scan.Position = UDim2.fromOffset(VIEW_POSITION.X, VIEW_POSITION.Y + math.random() * (VIEW_SIZE.Y - 4))
		end
		local glitching = t < self._glitchUntil
		self._portrait:SetOffset(if glitching then Vector2.new(math.random(-3, 3), 0) else Vector2.zero, VIEW_POSITION)
		self._portrait:SetTint(if glitching then Color3.fromRGB(255, 150, 160) else Color3.fromRGB(255, 215, 220))
		self._scan.BackgroundTransparency = if glitching then 0.2 else 1
	elseif state == "gloat" then
		local pulse = (math.sin(t * 3.2) + 1) / 2
		for _, line in self._wingLines do
			Poly.paint(line, nil, 0.1 + 0.5 * pulse)
		end
		Poly.paint(self._aura, nil, 0.6 + 0.25 * pulse)
	elseif state == "normal" then
		-- Breathing: the aura brightens and dims very slightly.
		local breath = (math.sin(t * 1.6) + 1) / 2
		Poly.paint(self._aura, nil, 0.76 + 0.1 * breath)
		Poly.paint(self._border, nil, 0)
	end
	-- A diagonal light sweep across the portrait every few seconds.
	if state ~= "dead" and t >= self._nextSweep then
		self._nextSweep = t + 5 + math.random() * 4
		self._sweep.Position = UDim2.fromOffset(-30, -20)
		UIKit.tween(self._sweep, 0.6, { Position = UDim2.fromOffset(150, -20) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	end
end

function HealthPanel:SetVisible(visible: boolean)
	self._root.Visible = visible
end

function HealthPanel:Destroy()
	self._portrait:Destroy()
	self._root:Destroy()
end

return HealthPanel
