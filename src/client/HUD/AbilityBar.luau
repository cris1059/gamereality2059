--!strict

-- Bottom-centre abilities: up to three slots (key, name, a geometric icon,
-- cooldown fill and countdown, a flash when ready, a pulse when used) and
-- the ultimate as a ring of segments with its charge, which turns into a
-- violet/cyan "LISTA" when full.
-- The game has no ability system yet: nothing calls SetAbilities in play,
-- so the bar stays hidden; the HUD test mode fills it with sample slots.
-- When abilities exist, their (server-validated) cooldowns and charge go in
-- through SetAbilities / SetCooldown / Used / SetUltimate.

local HUDConfig = require(script.Parent.HUDConfig)
local Poly = require(script.Parent.Poly)
local UIKit = require(script.Parent.UIKit)

local P = HUDConfig.Palette
local F = HUDConfig.Fonts

local AbilityBar = {}
AbilityBar.__index = AbilityBar

export type Ability = { key: string, name: string, icon: string? }

local SIZE = Vector2.new(330, 100)
local SLOT = 58
local RING_TICKS = 24
local RING_RADIUS = 34

-- Simple vector icons (no uploaded art): a few shapes per icon id.
local ICONS: { [string]: { { Vector2 } } } = {
	dash = { { Vector2.new(10, 12), Vector2.new(30, 22), Vector2.new(10, 32) }, { Vector2.new(22, 12), Vector2.new(42, 22), Vector2.new(22, 32) } },
	shield = { { Vector2.new(14, 10), Vector2.new(38, 10), Vector2.new(38, 26), Vector2.new(26, 36), Vector2.new(14, 26) } },
	scan = { { Vector2.new(26, 8), Vector2.new(40, 22), Vector2.new(26, 36), Vector2.new(12, 22) } },
}

function AbilityBar.new(parent: Instance)
	local root = UIKit.anchored(parent, "AbilityModule", Vector2.new(0.5, 1), SIZE, Vector2.zero, 10)
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local slots = UIKit.frame(root, "Slots", Vector2.zero, Vector2.new(3 * (SLOT + 10), SIZE.Y), 10)

	-- Ultimate ring.
	local ult = UIKit.frame(root, "Ultimate", Vector2.new(SIZE.X - 2 * RING_RADIUS - 18, 4), Vector2.new(2 * RING_RADIUS + 12, 2 * RING_RADIUS + 12), 10)
	local center = Vector2.new(RING_RADIUS + 6, RING_RADIUS + 6)
	local hex = {}
	for index = 0, 5 do
		local angle = math.rad(60 * index + 30)
		table.insert(hex, center + Vector2.new(math.cos(angle), math.sin(angle)) * (RING_RADIUS - 9))
	end
	Poly.fill(ult, "Core", hex, P.Carbon, 0.2, 10, 2)
	local coreLine = Poly.outline(ult, "CoreLine", hex, P.Violet, 1.5, 0.2, 11)
	local ticks = {}
	for index = 1, RING_TICKS do
		local angle = math.rad(-90 + (index - 0.5) * 360 / RING_TICKS)
		local frame = UIKit.box(ult, "Tick" .. index, Vector2.zero, Vector2.new(7, 3), P.Metal, 0.1, 11)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(center.X + math.cos(angle) * RING_RADIUS, center.Y + math.sin(angle) * RING_RADIUS)
		frame.Rotation = math.deg(angle)
		table.insert(ticks, frame)
	end
	local percent = UIKit.text(ult, "Percent", "0%", center - Vector2.new(30, 10), Vector2.new(60, 20), F.Display, 15, P.White, 12, Enum.TextXAlignment.Center)
	local ultKey = UIKit.text(ult, "Key", "", Vector2.new(0, 2 * RING_RADIUS + 4), Vector2.new(2 * RING_RADIUS + 12, 14), F.Technical, 11, P.Muted, 12, Enum.TextXAlignment.Center)

	root.Visible = false
	return setmetatable({
		_root = root,
		_scale = scale,
		_slots = slots,
		_slotViews = {} :: { any },
		_ticks = ticks,
		_percent = percent,
		_ultKey = ultKey,
		_coreLine = coreLine,
		_charge = 0,
		_ready = false,
		_clock = 0,
		_enabled = false,
	}, AbilityBar)
end

function AbilityBar:Place(uiScale: number, margin: number)
	self._scale.Scale = uiScale
	-- Kept clear of the stamina bar (MovementController) at the very bottom.
	self._root.Position = UDim2.new(0.5, 0, 1, -(margin + 22) * uiScale)
end

-- The class's abilities (empty hides the bar) and the ultimate's key.
function AbilityBar:SetAbilities(abilities: { Ability }, ultimateKey: string?)
	self._slots:ClearAllChildren()
	table.clear(self._slotViews)
	for index, ability in abilities do
		local x = (index - 1) * (SLOT + 10)
		local slot = UIKit.frame(self._slots, "Slot" .. index, Vector2.new(x, 6), Vector2.new(SLOT, SLOT + 26), 10)
		local shape = Poly.chamfer(0, 0, SLOT, SLOT, 10, 0, 10, 0)
		Poly.fill(slot, "Back", shape, P.Carbon, 0.3, 10, 2)
		local line = Poly.outline(slot, "Line", shape, P.Electric, 1.5, 0.15, 13)
		for shapeIndex, points in ICONS[ability.icon or ""] or ICONS.scan do
			Poly.fill(slot, "Icon" .. shapeIndex, points, P.Cyan, 0.1, 11, 1)
		end
		-- Cooldown: a dark fill that drains upwards, with the seconds left.
		local cover = UIKit.box(slot, "Cooldown", Vector2.new(0, 0), Vector2.new(SLOT, 0), P.Carbon, 0.25, 12)
		local seconds = UIKit.text(slot, "Seconds", "", Vector2.zero, Vector2.new(SLOT, SLOT), F.Display, 20, P.White, 13, Enum.TextXAlignment.Center)
		local keyTag = UIKit.text(slot, "Key", ability.key, Vector2.new(0, SLOT + 2), Vector2.new(SLOT, 12), F.Display, 12, P.Cyan, 12, Enum.TextXAlignment.Center)
		UIKit.text(slot, "Name", string.upper(ability.name), Vector2.new(-6, SLOT + 13), Vector2.new(SLOT + 12, 11), F.Technical, 9, P.Muted, 12, Enum.TextXAlignment.Center)
		table.insert(self._slotViews, { root = slot, line = line, cover = cover, seconds = seconds, key = keyTag, ready = true })
	end
	self._ultKey.Text = if ultimateKey then "[" .. ultimateKey .. "] DEFINITIVA" else "DEFINITIVA"
	self._enabled = #abilities > 0
	self._root.Visible = self._enabled
end

-- Seconds left of a slot's cooldown out of `total` (0 = ready).
function AbilityBar:SetCooldown(index: number, remaining: number, total: number)
	local view = self._slotViews[index]
	if not view then
		return
	end
	local busy = remaining > 0.05
	view.cover.Size = UDim2.fromOffset(SLOT, if busy then SLOT * math.clamp(remaining / math.max(total, 0.01), 0, 1) else 0)
	view.cover.Position = UDim2.fromOffset(0, SLOT - view.cover.Size.Y.Offset)
	view.seconds.Text = if busy then string.format(if remaining < 10 then "%.1f" else "%d", remaining) else ""
	Poly.paint(view.line, if busy then P.Metal else P.Electric)
	view.key.TextColor3 = if busy then P.Muted else P.Cyan
	if not busy and not view.ready then
		-- Ready again: a short bright flash of the frame.
		Poly.paint(view.line, P.White, 0)
		task.delay(0.18, function()
			Poly.paint(view.line, P.Electric, 0.15)
		end)
	end
	view.ready = not busy
end

-- An ability was used: the slot pops.
function AbilityBar:Used(index: number)
	local view = self._slotViews[index]
	if view then
		view.root.Position += UDim2.fromOffset(0, -6)
		UIKit.tween(view.root, 0.25, { Position = view.root.Position + UDim2.fromOffset(0, 6) }, Enum.EasingStyle.Back)
	end
end

-- Ultimate charge 0..1.
function AbilityBar:SetUltimate(fraction: number)
	fraction = math.clamp(fraction, 0, 1)
	self._charge = fraction
	local wasReady = self._ready
	self._ready = fraction >= 1
	local lit = math.floor(fraction * RING_TICKS + 1e-6)
	for index, frame in self._ticks do
		frame.BackgroundColor3 = if index <= lit then (if index % 2 == 0 then P.Cyan else P.Violet) else P.Metal
	end
	self._percent.Text = if self._ready then "LISTA" else string.format("%d%%", math.floor(fraction * 100))
	self._percent.TextColor3 = if self._ready then P.Cyan else P.White
	if self._ready and not wasReady then
		-- Full charge: one burst outwards, then a calm pulse (Update).
		for _, frame in self._ticks do
			frame.Size = UDim2.fromOffset(12, 4)
			UIKit.tween(frame, 0.4, { Size = UDim2.fromOffset(7, 3) }, Enum.EasingStyle.Back)
		end
	end
end

function AbilityBar:Update(deltaTime: number)
	self._clock += deltaTime
	if self._ready then
		local pulse = (math.sin(self._clock * 4) + 1) / 2
		Poly.paint(self._coreLine, P.Cyan:Lerp(P.Violet, pulse), 0)
	else
		Poly.paint(self._coreLine, P.Violet, 0.2)
	end
end

function AbilityBar:SetVisible(visible: boolean)
	self._root.Visible = visible and self._enabled
end

function AbilityBar:Destroy()
	self._root:Destroy()
end

return AbilityBar
