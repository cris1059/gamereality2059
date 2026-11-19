--!strict

-- Bottom-right weapon module: the magazine count dominates; reserve (the
-- game has unlimited reserve ammo, shown as ∞), weapon name, class and fire
-- mode, a row of rounds, the reload progress, a low-ammo warning and the
-- two loadout slots above. Ammo and reload state come from CombatController
-- (server Ammo / Reloading attributes plus its own prediction), the slots
-- from WeaponController (WeaponLoadout).

local HUDConfig = require(script.Parent.HUDConfig)
local Poly = require(script.Parent.Poly)
local UIKit = require(script.Parent.UIKit)

local P = HUDConfig.Palette
local F = HUDConfig.Fonts
local A = HUDConfig.Ammo

local WeaponPanel = {}
WeaponPanel.__index = WeaponPanel

local SIZE = Vector2.new(390, 152)
local PANEL_Y = 34
local PIPS = { x = 22, y = 120, height = 10, maxCount = 30, area = 220 }

function WeaponPanel.new(parent: Instance)
	local root = UIKit.anchored(parent, "WeaponModule", Vector2.new(1, 1), SIZE, Vector2.zero, 10)
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local body = UIKit.frame(root, "Body", Vector2.zero, SIZE, 10)

	-- Slots (filled by SetSlots).
	local slots = UIKit.frame(root, "Slots", Vector2.zero, Vector2.new(SIZE.X, 26), 10)

	local shape = Poly.chamfer(0, PANEL_Y, SIZE.X, SIZE.Y - PANEL_Y, 20, 0, 12, 0)
	Poly.fill(body, "Glass", shape, P.Carbon, 0.4, 10, 2)
	local outline = Poly.outline(body, "Outline", shape, P.Electric, 1, 0.55, 11)
	UIKit.box(body, "Accent", Vector2.new(0, PANEL_Y + 26), Vector2.new(3, 52), P.Electric, 0, 11)
	Poly.outline(body, "Corner", { Vector2.new(SIZE.X - 40, SIZE.Y + 5), Vector2.new(SIZE.X + 5, SIZE.Y + 5), Vector2.new(SIZE.X + 5, SIZE.Y - 30) }, P.Electric, 2, 0.2, 11, true)

	local countHolder = UIKit.frame(body, "CountHolder", Vector2.new(18, PANEL_Y + 6), Vector2.new(190, 70), 12)
	local countScale = Instance.new("UIScale")
	countScale.Parent = countHolder
	local count = UIKit.text(countHolder, "Count", "", Vector2.zero, Vector2.new(190, 70), F.Display, 62, P.White, 12)
	count.RichText = true
	UIKit.shadow(count)

	local weaponName = UIKit.text(body, "WeaponName", "", Vector2.new(170, PANEL_Y + 12), Vector2.new(SIZE.X - 188, 22), F.Interface, 19, P.White, 12, Enum.TextXAlignment.Right)
	weaponName.FontFace = Font.new(weaponName.FontFace.Family, Enum.FontWeight.Bold)
	UIKit.shadow(weaponName, 0.7)
	local modeTag = UIKit.text(body, "Mode", "", Vector2.new(170, PANEL_Y + 36), Vector2.new(SIZE.X - 188, 14), F.Technical, 12, P.Cyan, 12, Enum.TextXAlignment.Right)
	local warning = UIKit.text(body, "LowAmmo", "MUNICIÓN BAJA", Vector2.new(170, PANEL_Y + 56), Vector2.new(SIZE.X - 188, 14), F.Technical, 12, P.Warning, 12, Enum.TextXAlignment.Right)
	warning.Visible = false

	local pips = UIKit.frame(body, "Rounds", Vector2.new(PIPS.x, PIPS.y), Vector2.new(PIPS.area + 10, PIPS.height), 12)
	local reload = UIKit.frame(body, "Reload", Vector2.new(PIPS.x, PIPS.y - 16), Vector2.new(SIZE.X - 44, 28), 12)
	local reloadLabel = UIKit.text(reload, "Label", "RECARGANDO", Vector2.zero, Vector2.new(200, 12), F.Technical, 12, P.Cyan, 12)
	UIKit.box(reload, "Track", Vector2.new(0, 16), Vector2.new(SIZE.X - 44, 6), P.Metal, 0.2, 12)
	local reloadFill = UIKit.box(reload, "Fill", Vector2.new(0, 16), Vector2.new(0, 6), P.Cyan, 0, 13)
	UIKit.gradient(reloadFill, P.Electric, P.White, 0)
	reload.Visible = false

	return setmetatable({
		_root = root,
		_scale = scale,
		_body = body,
		_slots = slots,
		_outline = outline,
		_count = count,
		_countScale = countScale,
		_weaponName = weaponName,
		_modeTag = modeTag,
		_warning = warning,
		_pips = pips,
		_pipFrames = {} :: { Frame },
		_pipCount = 0,
		_reload = reload,
		_reloadFill = reloadFill,
		_reloadLabel = reloadLabel,
		-- The bar shows the reload, else the draw (taking the weapon out).
		_reloadState = { active = false, progress = 0 },
		_drawState = { active = false, progress = 0 },
		_ammo = -1,
		_magazine = 0,
		_weaponKey = "",
		_low = false,
		_clock = 0,
	}, WeaponPanel)
end

function WeaponPanel:Place(uiScale: number, margin: number)
	self._scale.Scale = uiScale
	self._root.Position = UDim2.new(1, -margin * uiScale, 1, -margin * uiScale)
end

-- The loadout slots (names from WeaponLoadout, equipped index).
function WeaponPanel:SetSlots(names: { string }, equipped: number, max: number)
	self._slots:ClearAllChildren()
	local width = 150
	for index = 1, math.max(max, #names) do
		local name = names[index]
		local active = index == equipped and name ~= nil
		local x = SIZE.X - (math.max(max, #names) - index + 1) * (width + 8)
		local tag = UIKit.frame(self._slots, "Slot" .. index, Vector2.new(x, 0), Vector2.new(width, 24), 10)
		local points = Poly.chamfer(0, 0, width, 24, 8, 0, 8, 0)
		Poly.fill(tag, "Back", points, if active then P.Electric else P.Carbon, if active then 0.75 else 0.45, 10, 2)
		Poly.outline(tag, "Line", points, if active then P.Cyan else P.Metal, 1, if active then 0 else 0.3, 11)
		UIKit.text(tag, "Key", tostring(index), Vector2.new(10, 0), Vector2.new(14, 24), F.Display, 14, if active then P.Cyan else P.Muted, 12)
		local label = UIKit.text(tag, "Name", name or "VACÍO", Vector2.new(26, 0), Vector2.new(width - 32, 24), F.Interface, 13, if active then P.White else P.Muted, 12)
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

-- The weapon in hand. A different weapon slides the panel in.
function WeaponPanel:SetWeapon(name: string, classLabel: string, automatic: boolean, magazine: number)
	local key = name .. "|" .. magazine
	if key == self._weaponKey then
		return
	end
	local switched = self._weaponKey ~= ""
	self._weaponKey = key
	self._weaponName.Text = string.upper(name)
	self._modeTag.Text = string.format("%s  ·  %s", classLabel, if automatic then "AUTO" else "SEMI")
	self:_buildPips(magazine)
	if switched then
		self._body.Position = UDim2.fromOffset(40, 0)
		UIKit.tween(self._body, A.SwitchSlideTime, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	end
end

function WeaponPanel:_buildPips(magazine: number)
	self._pips:ClearAllChildren()
	table.clear(self._pipFrames)
	local count = math.clamp(magazine, 1, PIPS.maxCount)
	local gap = 2
	local width = math.min(8, (PIPS.area - (count - 1) * gap) / count)
	for index = 1, count do
		local x = (index - 1) * (width + gap)
		table.insert(self._pipFrames, Poly.fill(self._pips, "Round" .. index, Poly.slant(x, 0, width, PIPS.height, 3), P.Cyan, 0, 12, 2))
	end
	self._pipCount = count
	self._magazine = magazine
	self._ammo = -1
end

-- Rounds in the magazine (predicted by the client, never above the server).
function WeaponPanel:SetAmmo(ammo: number, magazine: number)
	if magazine ~= self._magazine then
		self:_buildPips(magazine)
	end
	if ammo == self._ammo then
		return
	end
	local fired = self._ammo > 0 and ammo < self._ammo
	self._ammo = ammo
	local fraction = if magazine > 0 then ammo / magazine else 0
	local low = fraction <= A.Low
	local color = if ammo <= 0 then P.Danger elseif low then P.Warning else P.White
	self._count.Text = string.format('%d<font size="24" color="#8FA9C0"> / ∞</font>', ammo)
	self._count.TextColor3 = color
	self._warning.Visible = low
	self._warning.Text = if ammo <= 0 then "SIN MUNICIÓN // RECARGA [R]" else "MUNICIÓN BAJA"
	self._warning.TextColor3 = if ammo <= 0 then P.Danger else P.Warning
	self._low = low
	local lit = math.ceil(fraction * self._pipCount - 1e-6)
	for index, pip in self._pipFrames do
		Poly.paint(pip, if index <= lit then (if low then P.Warning else P.Cyan) else P.Metal, if index <= lit then 0 else 0.3)
	end
	if fired then
		-- A quick kick of the number on each shot.
		self._countScale.Scale = 1.08
		UIKit.tween(self._countScale, A.FireKickTime * 2, { Scale = 1 })
	end
end

-- The progress bar in place of the rounds row: the reload first, else the
-- draw.
function WeaponPanel:_refreshBar()
	local state = if self._reloadState.active then self._reloadState elseif self._drawState.active then self._drawState else nil
	self._reload.Visible = state ~= nil
	self._pips.Visible = state == nil
	if state then
		self._reloadLabel.Text = if state == self._reloadState then "RECARGANDO" else "DESENFUNDANDO"
		self._reloadFill.Size = UDim2.fromOffset((SIZE.X - 44) * math.clamp(state.progress, 0, 1), 6)
		self._warning.Visible = false
	end
end

-- Reload progress (0..1).
function WeaponPanel:SetReload(active: boolean, progress: number)
	self._reloadState.active, self._reloadState.progress = active, progress
	self:_refreshBar()
end

-- Draw progress (0..1) while the weapon is taken out.
function WeaponPanel:SetDraw(active: boolean, progress: number)
	if not active and not self._drawState.active then
		return
	end
	self._drawState.active, self._drawState.progress = active, progress
	self:_refreshBar()
end

function WeaponPanel:Update(deltaTime: number)
	self._clock += deltaTime
	if self._low and self._warning.Visible then
		self._warning.TextTransparency = 0.4 * (math.sin(self._clock * 6) + 1) / 2
	end
end

function WeaponPanel:SetVisible(visible: boolean)
	self._root.Visible = visible
end

function WeaponPanel:Destroy()
	self._root:Destroy()
end

return WeaponPanel
