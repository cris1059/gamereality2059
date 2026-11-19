--!strict

-- Top-centre match strip: your team always on the left ("TU EQUIPO"), the
-- rival on the right ("RIVAL") so the sides never depend on colour alone,
-- the clock and the mode in the middle, and a thin progress line per team
-- towards the score limit. In training it shrinks to the mode alone.
-- Data: MatchState (MatchController) - score, endsAt, phase, team.

local Workspace = game:GetService("Workspace")

local HUDConfig = require(script.Parent.HUDConfig)
local Poly = require(script.Parent.Poly)
local UIKit = require(script.Parent.UIKit)

local P = HUDConfig.Palette
local F = HUDConfig.Fonts

local MatchBar = {}
MatchBar.__index = MatchBar

local SIZE = Vector2.new(560, 74)
local CENTER_W = 150
local SIDE_W = 170

export type View = {
	allyScore: number,
	rivalScore: number,
	scoreLimit: number,
	allyName: string,
	rivalName: string,
	mode: string,
	endsAt: number,
	phase: string,
}

local function side(parent: Instance, name: string, x: number, mirrored: boolean, color: Color3, tag: string)
	local holder = UIKit.frame(parent, name, Vector2.new(x, 6), Vector2.new(SIDE_W, 46), 10)
	local points = if mirrored
		then Poly.chamfer(0, 0, SIDE_W, 40, 0, 14, 0, 0)
		else Poly.chamfer(0, 0, SIDE_W, 40, 14, 0, 0, 0)
	Poly.fill(holder, "Back", points, P.Carbon, 0.35, 10, 2)
	Poly.outline(holder, "Line", points, color, 1, 0.45, 11)
	UIKit.box(holder, "Edge", Vector2.new(if mirrored then SIDE_W - 3 else 0, 6), Vector2.new(3, 28), color, 0, 11)
	local align = if mirrored then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	local score = UIKit.text(holder, "Score", "0", Vector2.new(if mirrored then 10 else 12, 2), Vector2.new(SIDE_W - 22, 36), F.Display, 30, P.White, 12, if mirrored then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right)
	UIKit.shadow(score)
	local label = UIKit.text(holder, "Tag", tag, Vector2.new(if mirrored then SIDE_W - 110 else 12, 4), Vector2.new(98, 12), F.Technical, 11, color, 12, align)
	local team = UIKit.text(holder, "Team", "", Vector2.new(if mirrored then SIDE_W - 110 else 12, 18), Vector2.new(98, 14), F.Interface, 12, P.Muted, 12, align)
	UIKit.box(holder, "Track", Vector2.new(0, 42), Vector2.new(SIDE_W, 3), P.Metal, 0.3, 11)
	local progress = UIKit.box(holder, "Progress", Vector2.new(if mirrored then SIDE_W else 0, 42), Vector2.new(0, 3), color, 0, 12)
	if mirrored then
		progress.AnchorPoint = Vector2.new(1, 0)
	end
	return { holder = holder, score = score, team = team, progress = progress }
end

function MatchBar.new(parent: Instance)
	local root = UIKit.anchored(parent, "MatchStrip", Vector2.new(0.5, 0), SIZE, Vector2.zero, 10)
	local scale = Instance.new("UIScale")
	scale.Parent = root

	local centerX = (SIZE.X - CENTER_W) / 2
	local centerPoints = Poly.chamfer(centerX, 0, CENTER_W, 52, 0, 0, 16, 16)
	Poly.fill(root, "Center", centerPoints, P.Carbon, 0.25, 10, 2)
	Poly.outline(root, "CenterLine", centerPoints, P.Electric, 1, 0.35, 11)
	local clock = UIKit.text(root, "Clock", "--:--", Vector2.new(centerX, 2), Vector2.new(CENTER_W, 32), F.Display, 26, P.White, 12, Enum.TextXAlignment.Center)
	UIKit.shadow(clock)
	local mode = UIKit.text(root, "Mode", "", Vector2.new(centerX - 40, 56), Vector2.new(CENTER_W + 80, 14), F.Technical, 11, P.Muted, 12, Enum.TextXAlignment.Center)
	local phase = UIKit.text(root, "Phase", "", Vector2.new(centerX, 32), Vector2.new(CENTER_W, 14), F.Technical, 10, P.Cyan, 12, Enum.TextXAlignment.Center)

	local ally = side(root, "Ally", centerX - SIDE_W - 8, false, P.Cyan, "TU EQUIPO")
	local rival = side(root, "Rival", centerX + CENTER_W + 8, true, P.Enemy, "RIVAL")

	root.Visible = false
	return setmetatable({
		_root = root,
		_scale = scale,
		_clock = clock,
		_mode = mode,
		_phase = phase,
		_ally = ally,
		_rival = rival,
		_view = nil :: View?,
	}, MatchBar)
end

function MatchBar:Place(uiScale: number, margin: number)
	self._scale.Scale = uiScale
	self._root.Position = UDim2.new(0.5, 0, 0, math.max(margin - 12, 8) * uiScale)
end

-- A match (teams and score) or nil to hide.
function MatchBar:SetMatch(view: View?)
	self._view = view
	if not view then
		self._root.Visible = false
		return
	end
	self._root.Visible = true
	self._ally.holder.Visible = true
	self._rival.holder.Visible = true
	self._mode.Text = view.mode
	self._ally.team.Text = view.allyName
	self._rival.team.Text = view.rivalName
	local function apply(view_: any, score: number)
		local previous = tonumber(view_.score.Text) or 0
		view_.score.Text = string.format("%02d", score)
		view_.progress.Size = UDim2.fromOffset(SIDE_W * math.clamp(score / math.max(view.scoreLimit, 1), 0, 1), 3)
		if score > previous then
			view_.score.TextColor3 = P.White
			view_.score.TextSize = 36
			UIKit.tween(view_.score, 0.3, { TextSize = 30 }, Enum.EasingStyle.Back)
		end
	end
	apply(self._ally, view.allyScore)
	apply(self._rival, view.rivalScore)
end

-- Training: the strip shows only the mode.
function MatchBar:SetFreeMode(title: string, subtitle: string)
	self._view = nil
	self._root.Visible = true
	self._ally.holder.Visible = false
	self._rival.holder.Visible = false
	self._clock.Text = title
	self._clock.TextSize = 18
	self._phase.Text = ""
	self._mode.Text = subtitle
end

function MatchBar:Hide()
	self._view = nil
	self._root.Visible = false
end

function MatchBar:Update()
	local view = self._view
	if not view then
		return
	end
	self._clock.TextSize = 26
	local left = math.max(0, math.ceil(view.endsAt - Workspace:GetServerTimeNow()))
	if view.phase == "countdown" then
		self._clock.Text = "--:--"
		self._phase.Text = "PREPARADOS"
	elseif view.phase == "playing" then
		self._clock.Text = string.format("%02d:%02d", left // 60, left % 60)
		self._clock.TextColor3 = if left <= 30 then P.Warning else P.White
		self._phase.Text = "EN COMBATE"
	else
		self._clock.Text = "FIN"
		self._phase.Text = ""
	end
end

function MatchBar:Destroy()
	self._root:Destroy()
end

return MatchBar
