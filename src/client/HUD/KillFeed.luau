--!strict

-- Top-right elimination feed: compact angled strips that slide in, stay
-- HUDConfig.KillFeed.Seconds and fade, at most MaxEntries at a time.
-- Ally names cyan, rival names red (plus the strip's edge); lines about the
-- local player get a brighter frame (your kill: cyan, your death: red).
-- Data: MatchState events { kind = "kill" | "left", killer?, victim, teams }.
-- The server sends no weapon with a kill, so no weapon icon is shown.

local HUDConfig = require(script.Parent.HUDConfig)
local Poly = require(script.Parent.Poly)
local UIKit = require(script.Parent.UIKit)

local P = HUDConfig.Palette
local F = HUDConfig.Fonts
local K = HUDConfig.KillFeed

local KillFeed = {}
KillFeed.__index = KillFeed

local WIDTH = 340
local ROW = 28

export type Entry = { killer: string?, killerAlly: boolean?, victim: string, victimAlly: boolean?, left: boolean?, mine: boolean?, myDeath: boolean? }

function KillFeed.new(parent: Instance)
	local root = UIKit.anchored(parent, "KillFeed", Vector2.new(1, 0), Vector2.new(WIDTH, K.MaxEntries * (ROW + 4)), Vector2.zero, 10)
	local scale = Instance.new("UIScale")
	scale.Parent = root
	return setmetatable({ _root = root, _scale = scale, _rows = {} :: { Frame } }, KillFeed)
end

function KillFeed:Place(uiScale: number, margin: number)
	self._scale.Scale = uiScale
	self._root.Position = UDim2.new(1, -margin * uiScale, 0, (margin + 60) * uiScale)
end

local function hex(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

function KillFeed:_layout()
	for index, row in self._rows do
		UIKit.tween(row, 0.18, { Position = UDim2.fromOffset(row.Position.X.Offset, (index - 1) * (ROW + 4)) })
	end
end

function KillFeed:Push(entry: Entry)
	local edge = if entry.myDeath then P.Danger elseif entry.mine then P.Cyan elseif entry.killer and entry.killerAlly then P.Cyan else P.Enemy
	local row = UIKit.frame(self._root, "Entry", Vector2.new(60, 0), Vector2.new(WIDTH, ROW), 10)
	local points = Poly.chamfer(0, 0, WIDTH, ROW, 10, 0, 10, 0)
	Poly.fill(row, "Back", points, P.Carbon, if entry.mine or entry.myDeath then 0.2 else 0.4, 10, 2)
	Poly.outline(row, "Line", points, edge, 1, if entry.mine or entry.myDeath then 0 else 0.55, 11)
	UIKit.box(row, "Edge", Vector2.new(WIDTH - 3, 4), Vector2.new(3, ROW - 8), edge, 0, 11)
	local text = UIKit.text(row, "Text", "", Vector2.new(10, 0), Vector2.new(WIDTH - 22, ROW), F.Interface, 14, P.White, 12, Enum.TextXAlignment.Right)
	text.RichText = true
	text.FontFace = Font.new(text.FontFace.Family, Enum.FontWeight.Bold)
	local function name(value: string, ally: boolean?): string
		return string.format('<font color="%s">%s</font>', hex(if ally then P.Cyan else P.Enemy), value)
	end
	if entry.left then
		text.Text = string.format('%s <font color="%s">SALIÓ</font>', name(entry.victim, entry.victimAlly), hex(P.Muted))
	elseif entry.killer then
		text.Text = string.format('%s  <font color="%s">▸▸</font>  %s', name(entry.killer, entry.killerAlly), hex(P.White), name(entry.victim, entry.victimAlly))
	else
		text.Text = string.format('%s <font color="%s">CAYÓ</font>', name(entry.victim, entry.victimAlly), hex(P.Muted))
	end
	table.insert(self._rows, 1, row)
	while #self._rows > K.MaxEntries do
		local old = table.remove(self._rows) :: Frame
		old:Destroy()
	end
	self:_layout()
	UIKit.tween(row, 0.22, { Position = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Quint)
	task.delay(K.Seconds, function()
		if row.Parent then
			for _, child in row:GetDescendants() do
				if child:IsA("Frame") and child.BackgroundTransparency < 1 then
					UIKit.tween(child, 0.4, { BackgroundTransparency = 1 })
				elseif child:IsA("TextLabel") then
					UIKit.tween(child, 0.4, { TextTransparency = 1 })
				end
			end
			task.delay(0.42, function()
				local index = table.find(self._rows, row)
				if index then
					table.remove(self._rows, index)
				end
				row:Destroy()
				self:_layout()
			end)
		end
	end)
end

function KillFeed:Clear()
	for _, row in self._rows do
		row:Destroy()
	end
	table.clear(self._rows)
end

function KillFeed:Destroy()
	self._root:Destroy()
end

return KillFeed
