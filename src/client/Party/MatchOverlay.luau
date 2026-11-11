--!strict

-- Screens of a match, over the hub, driven by the squad snapshot's status:
--   found     PARTIDA ENCONTRADA: ACEPTAR / RECHAZAR with a countdown
--   launching loading screen (map, progress)
--   ingame    match room: both teams and the clock
--   results   results and VOLVER AL LOBBY
-- Every button is a request to the server (PartyController:Request); the
-- server owns the state. While the match itself does not exist yet (the
-- combat arrives in the next phase) the room and the results are labelled
-- as a simulation and show no invented numbers.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local LobbyConfig = require(root.Config.LobbyConfig)
local PartyConfig = require(root.Config.PartyConfig)

local MatchOverlay = {}
MatchOverlay.__index = MatchOverlay

local PANEL = Color3.fromRGB(7, 10, 18)
local CARD = Color3.fromRGB(14, 20, 32)
local MUTED = Color3.fromRGB(135, 148, 172)
local GOOD = Color3.fromRGB(90, 255, 160)
local BAD = Color3.fromRGB(255, 80, 105)
local WARN = Color3.fromRGB(255, 190, 60)
local FADE = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function corner(parent: Instance, radius: number)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0, radius)
	item.Parent = parent
end

local function stroke(parent: Instance, color: Color3, transparency: number, thickness: number?): UIStroke
	local item = Instance.new("UIStroke")
	item.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	item.Color = color
	item.Transparency = transparency
	item.Thickness = thickness or 1
	item.Parent = parent
	return item
end

local function box(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, transparency: number): Frame
	local item = Instance.new("Frame")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = color
	item.BackgroundTransparency = transparency
	item.BorderSizePixel = 0
	item.Parent = parent
	return item
end

local function text(parent: Instance, name: string, value: string, size: UDim2, position: UDim2, font: Enum.Font, textSize: number, color: Color3, align: Enum.TextXAlignment?): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = value
	item.TextSize = textSize
	item.TextColor3 = color
	item.TextWrapped = true
	item.TextXAlignment = align or Enum.TextXAlignment.Left
	item.Parent = parent
	return item
end

local function button(parent: Instance, name: string, value: string, size: UDim2, position: UDim2, font: Enum.Font, color: Color3): TextButton
	local item = Instance.new("TextButton")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundColor3 = color
	item.BorderSizePixel = 0
	item.AutoButtonColor = true
	item.Font = font
	item.Text = value
	item.TextSize = 20
	item.TextColor3 = Color3.fromRGB(10, 6, 12)
	item.Parent = parent
	corner(item, 6)
	return item
end

local function modeOf(modeId: string)
	for _, mode in LobbyConfig.Modes do
		if mode.id == modeId then
			return mode
		end
	end
	return LobbyConfig.Modes[1]
end

local function secondsLeft(deadline: number?): number
	return math.max(0, (deadline or 0) - Workspace:GetServerTimeNow())
end

function MatchOverlay.new(playerGui: PlayerGui, config, party)
	local screen = Instance.new("ScreenGui")
	screen.Name = "Reality2059Match"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 130
	screen.Parent = playerGui
	local self = setmetatable({
		_screen = screen,
		_scaleValue = 1,
		_stage = nil :: Frame?,
		_stageScale = nil :: UIScale?,
		_config = config,
		_party = party,
		_page = nil :: string?,
		_matchId = nil :: number?,
		_group = nil :: CanvasGroup?,
		_refs = {} :: { [string]: any },
		_snapshot = nil :: any,
		_alive = true,
		_busy = false,
	}, MatchOverlay)
	local camera = Workspace.CurrentCamera
	if camera then
		local function updateScale()
			local viewport = camera.ViewportSize
			self._scaleValue = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.6, 1.4)
			if self._stage and self._stageScale then
				self._stage.Size = UDim2.fromScale(1 / self._scaleValue, 1 / self._scaleValue)
				self._stageScale.Scale = self._scaleValue
			end
		end
		updateScale()
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
	end
	task.spawn(function()
		while self._alive do
			task.wait(0.1)
			if self._page then
				self:_tick()
			end
		end
	end)
	return self
end

-- A request that disables the buttons while it is in flight.
function MatchOverlay:_request(action: string)
	if self._busy then
		return
	end
	self._busy = true
	task.spawn(function()
		self._party:Request(action)
		self._busy = false
	end)
end

function MatchOverlay:_clear()
	if self._group then
		self._group:Destroy()
		self._group = nil
	end
	table.clear(self._refs)
	self._page = nil
end

-- Returns the page (full-screen background) and its stage (where the content
-- goes): the stage is scaled to the viewport without moving the page.
local function newGroup(screen: ScreenGui, opaque: boolean, scale: number): (CanvasGroup, Frame, UIScale)
	local group = Instance.new("CanvasGroup")
	group.Name = "Page"
	group.Size = UDim2.fromScale(1, 1)
	group.BackgroundColor3 = if opaque then Color3.fromRGB(4, 6, 12) else Color3.new(0, 0, 0)
	group.BackgroundTransparency = if opaque then 0 else 0.45
	group.BorderSizePixel = 0
	group.GroupTransparency = 1
	group.Parent = screen
	TweenService:Create(group, FADE, { GroupTransparency = 0 }):Play()
	local stage = box(group, "Stage", UDim2.fromScale(1 / scale, 1 / scale), UDim2.new(), Color3.new(), 1)
	local stageScale = Instance.new("UIScale")
	stageScale.Scale = scale
	stageScale.Parent = stage
	return group, stage, stageScale
end

local function simulationTag(parent: Instance, fonts, position: UDim2)
	local tag = box(parent, "Simulation", UDim2.fromOffset(190, 22), position, WARN, 0.8)
	corner(tag, 4)
	local label = text(tag, "Text", "SIMULACIÓN DE STUDIO", UDim2.fromScale(1, 1), UDim2.new(), fonts.Technical, 11, WARN, Enum.TextXAlignment.Center)
	label.TextWrapped = false
end

-- ------------------------------------------------------------------ found --

function MatchOverlay:_buildFound(snapshot)
	local fonts, palette = self._config.Typography, self._config.Palette
	local mode = modeOf(snapshot.mode)
	local page, group, stageScale = newGroup(self._screen, false, self._scaleValue)
	self._group = page
	self._stage, self._stageScale = group, stageScale
	local card = box(group, "Card", UDim2.fromOffset(560, 340), UDim2.fromScale(0.5, 0.5), PANEL, 0.02)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	corner(card, 8)
	stroke(card, mode.accent, 0.2, 2)
	box(card, "Accent", UDim2.new(1, 0, 0, 5), UDim2.new(), mode.accent, 0)
	text(card, "Title", "PARTIDA ENCONTRADA", UDim2.new(1, -40, 0, 40), UDim2.fromOffset(20, 22), fonts.Display, 34, palette.Text)
	local match = snapshot.match
	local mapName = if match and match.map then match.map.name else "—"
	text(card, "Sub", mode.name .. "   ·   " .. mapName, UDim2.new(1, -40, 0, 22), UDim2.fromOffset(20, 64), fonts.Technical, 14, mode.accent)
	local countdown = text(card, "Countdown", "", UDim2.new(1, -40, 0, 70), UDim2.fromOffset(20, 92), fonts.Display, 64, palette.Text, Enum.TextXAlignment.Center)
	local track = box(card, "Track", UDim2.new(1, -40, 0, 6), UDim2.fromOffset(20, 166), Color3.fromRGB(30, 36, 52), 0)
	corner(track, 3)
	local fill = box(track, "Fill", UDim2.fromScale(1, 1), UDim2.new(), mode.accent, 0)
	corner(fill, 3)
	local members = box(card, "Members", UDim2.new(1, -40, 0, 56), UDim2.fromOffset(20, 186), Color3.new(), 1)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 8)
	layout.Parent = members
	local chips = {}
	for index, member in snapshot.members do
		local chip = box(members, "Member" .. index, UDim2.fromOffset(120, 52), UDim2.new(), CARD, 0.1)
		corner(chip, 4)
		local stroke1 = stroke(chip, MUTED, 0.5)
		local name = text(chip, "Name", member.name, UDim2.new(1, -12, 0, 22), UDim2.fromOffset(8, 6), fonts.Interface, 13, palette.Text)
		name.TextWrapped = false
		name.TextTruncate = Enum.TextTruncate.AtEnd
		local state = text(chip, "State", "ESPERANDO", UDim2.new(1, -12, 0, 16), UDim2.fromOffset(8, 28), fonts.Technical, 11, MUTED)
		chips[member.userId] = { stroke = stroke1, state = state }
	end
	local accept = button(card, "Accept", "ACEPTAR", UDim2.new(0.5, -28, 0, 52), UDim2.new(0, 20, 1, -72), Enum.Font.GothamBlack, GOOD)
	local decline = button(card, "Decline", "RECHAZAR", UDim2.new(0.5, -28, 0, 52), UDim2.new(0.5, 8, 1, -72), Enum.Font.GothamBlack, BAD)
	accept.Activated:Connect(function()
		self:_request("accept_match")
	end)
	decline.Activated:Connect(function()
		self:_request("decline_match")
	end)
	local waiting = text(card, "Waiting", "", UDim2.new(1, -40, 0, 52), UDim2.new(0, 20, 1, -72), fonts.Interface, 16, GOOD, Enum.TextXAlignment.Center)
	waiting.TextYAlignment = Enum.TextYAlignment.Center
	if match and match.simulated then
		simulationTag(card, fonts, UDim2.new(1, -210, 0, 64))
	end
	self._refs = { countdown = countdown, fill = fill, chips = chips, accept = accept, decline = decline, waiting = waiting }
end

-- ---------------------------------------------------------------- loading --

function MatchOverlay:_buildLoading(snapshot)
	local fonts, palette = self._config.Typography, self._config.Palette
	local mode = modeOf(snapshot.mode)
	local page, group, stageScale = newGroup(self._screen, true, self._scaleValue)
	self._group = page
	self._stage, self._stageScale = group, stageScale
	local match = snapshot.match
	local map = match and match.map
	box(group, "Accent", UDim2.new(0, 6, 0.5, 0), UDim2.fromScale(0.08, 0.25), mode.accent, 0)
	text(group, "Mode", mode.name, UDim2.fromOffset(600, 24), UDim2.new(0.08, 22, 0.28, 0), fonts.Technical, 16, mode.accent)
	text(group, "Map", if map then map.name else "PARTIDA", UDim2.fromOffset(900, 80), UDim2.new(0.08, 22, 0.33, 0), fonts.Display, 64, palette.Text)
	text(group, "Tagline", if map then map.tagline else "", UDim2.fromOffset(600, 24), UDim2.new(0.08, 22, 0.46, 0), fonts.Interface, 18, MUTED)
	local label = text(group, "Label", "CARGANDO PARTIDA", UDim2.fromOffset(400, 22), UDim2.new(0.08, 22, 0.78, 0), fonts.Technical, 15, palette.Text)
	local track = box(group, "Track", UDim2.new(0.84, -22, 0, 6), UDim2.new(0.08, 22, 0.82, 0), Color3.fromRGB(30, 36, 52), 0)
	corner(track, 3)
	track.ClipsDescendants = true
	local fill = box(track, "Fill", UDim2.fromScale(0, 1), UDim2.new(), mode.accent, 0)
	corner(fill, 3)
	if match and match.simulated then
		simulationTag(group, fonts, UDim2.new(0.08, 22, 0.88, 0))
	end
	-- A real teleport that stalls must not trap the squad: after a while the
	-- player can go back to the lobby.
	local abort = button(group, "Abort", "VOLVER AL LOBBY", UDim2.fromOffset(240, 44), UDim2.new(0.08, 22, 0.88, 0), Enum.Font.GothamBlack, BAD)
	abort.Visible = false
	abort.Activated:Connect(function()
		self:_request("return_lobby")
	end)
	self._refs = { fill = fill, label = label, track = track, abort = abort, startedAt = os.clock(), simulated = match ~= nil and match.simulated == true }
end

-- ------------------------------------------------------------------- room --

local function teamColumn(parent: Instance, fonts, palette, title: string, names: { string }, position: UDim2, color: Color3)
	local column = box(parent, "Team", UDim2.new(0.5, -12, 0, 280), position, CARD, 0.1)
	corner(column, 6)
	stroke(column, color, 0.35, 1.5)
	text(column, "Title", title, UDim2.new(1, -28, 0, 28), UDim2.fromOffset(14, 10), fonts.Display, 20, color)
	for index, name in names do
		local row = box(column, "Row" .. index, UDim2.new(1, -28, 0, 44), UDim2.fromOffset(14, 46 + (index - 1) * 52), Color3.fromRGB(10, 14, 24), 0.1)
		corner(row, 4)
		local label = text(row, "Name", name, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(12, 0), fonts.Interface, 15, if string.find(name, "SIMULADO") then MUTED else palette.Text)
		label.TextWrapped = false
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

function MatchOverlay:_buildRoom(snapshot)
	local fonts, palette = self._config.Typography, self._config.Palette
	local mode = modeOf(snapshot.mode)
	local page, group, stageScale = newGroup(self._screen, true, self._scaleValue)
	self._group = page
	self._stage, self._stageScale = group, stageScale
	local match = snapshot.match
	local content = box(group, "Content", UDim2.new(0, 860, 1, 0), UDim2.fromScale(0.5, 0), Color3.new(), 1)
	content.AnchorPoint = Vector2.new(0.5, 0)
	text(content, "Title", "SALA DE PARTIDA", UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 24), fonts.Display, 38, palette.Text)
	text(content, "Sub", mode.name .. "   ·   " .. (if match and match.map then match.map.name else "—"), UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 70), fonts.Technical, 14, mode.accent)
	local teams = match and match.teams
	teamColumn(content, fonts, palette, "TU EQUIPO", if teams then teams.ours else {}, UDim2.fromOffset(0, 120), GOOD)
	teamColumn(content, fonts, palette, "EQUIPO RIVAL", if teams then teams.theirs else {}, UDim2.new(0.5, 12, 0, 120), BAD)
	local clock = text(content, "Clock", "", UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 418), fonts.Display, 22, palette.Text, Enum.TextXAlignment.Center)
	local note = text(content, "Note", "", UDim2.new(1, 0, 0, 40), UDim2.fromOffset(0, 452), fonts.Interface, 14, MUTED, Enum.TextXAlignment.Center)
	note.Text = if match and match.simulated then "Aquí empezará el combate. Por ahora el flujo termina solo para probar la pantalla de resultados." else ""
	local leave = button(content, "Leave", "ABANDONAR", UDim2.fromOffset(240, 46), UDim2.new(0.5, -120, 0, 500), Enum.Font.GothamBlack, BAD)
	leave.Activated:Connect(function()
		self:_request("return_lobby")
	end)
	if match and match.simulated then
		simulationTag(content, fonts, UDim2.new(1, -190, 0, 28))
	end
	self._refs = { clock = clock }
end

-- ---------------------------------------------------------------- results --

function MatchOverlay:_buildResults(snapshot)
	local fonts, palette = self._config.Typography, self._config.Palette
	local mode = modeOf(snapshot.mode)
	local page, group, stageScale = newGroup(self._screen, true, self._scaleValue)
	self._group = page
	self._stage, self._stageScale = group, stageScale
	local match = snapshot.match
	local simulated = match == nil or match.simulated
	local content = box(group, "Content", UDim2.new(0, 760, 1, 0), UDim2.fromScale(0.5, 0), Color3.new(), 1)
	content.AnchorPoint = Vector2.new(0.5, 0)
	text(content, "Title", if simulated then "SIMULACIÓN COMPLETADA" else "FIN DE LA PARTIDA", UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 40), fonts.Display, 42, palette.Text)
	text(content, "Sub", mode.name, UDim2.new(1, 0, 0, 22), UDim2.fromOffset(0, 94), fonts.Technical, 15, mode.accent)
	local table1 = box(content, "Table", UDim2.new(1, 0, 0, 56 + math.max(#snapshot.members, 1) * 48), UDim2.fromOffset(0, 140), CARD, 0.1)
	corner(table1, 6)
	for _, header in {
		{ label = "JUGADOR", x = 14, width = 300 },
		{ label = "BAJAS", x = 440, width = 70 },
		{ label = "MUERTES", x = 520, width = 80 },
		{ label = "PUNTOS", x = 610, width = 70 },
	} do
		local label = text(table1, "Head", header.label, UDim2.fromOffset(header.width, 24), UDim2.fromOffset(header.x, 14), fonts.Technical, 12, MUTED)
		label.TextWrapped = false
	end
	for index, member in snapshot.members do
		local y = 52 + (index - 1) * 48
		local name = text(table1, "Name", member.name, UDim2.fromOffset(400, 36), UDim2.fromOffset(14, y), fonts.Interface, 16, palette.Text)
		name.TextWrapped = false
		for _, x in { 440, 520, 610 } do
			text(table1, "Cell", "—", UDim2.fromOffset(70, 36), UDim2.fromOffset(x, y), fonts.Technical, 16, MUTED)
		end
	end
	if simulated then
		text(content, "Note", "Sin estadísticas: esta partida fue una simulación. Las bajas, muertes y puntos aparecerán cuando exista el combate.",
			UDim2.new(1, 0, 0, 44), UDim2.fromOffset(0, 150 + 56 + math.max(#snapshot.members, 1) * 48 + 10), fonts.Interface, 14, MUTED)
	end
	local back = button(content, "Back", "VOLVER AL LOBBY", UDim2.fromOffset(300, 56), UDim2.new(0.5, -150, 0, 150 + 56 + math.max(#snapshot.members, 1) * 48 + 80), Enum.Font.GothamBlack, mode.accent)
	back.Activated:Connect(function()
		self:_request("return_lobby")
	end)
end

-- ------------------------------------------------------------------- tick --

function MatchOverlay:_tick()
	local snapshot = self._snapshot
	local refs = self._refs
	local match = snapshot and snapshot.match
	if not snapshot or not match then
		return
	end
	if self._page == "found" then
		local left = secondsLeft(match.deadline)
		refs.countdown.Text = tostring(math.ceil(left))
		refs.countdown.TextColor3 = if left <= 5 then BAD else self._config.Palette.Text
		refs.fill.Size = UDim2.fromScale(math.clamp(left / PartyConfig.AcceptSeconds, 0, 1), 1)
	elseif self._page == "launching" then
		local label = refs.label
		if match.simulated and match.phaseEnds then
			local total = PartyConfig.Simulation.LoadSeconds
			refs.fill.Size = UDim2.fromScale(math.clamp(1 - secondsLeft(match.phaseEnds) / total, 0, 1), 1)
			label.Text = string.format("CARGANDO PARTIDA  %d%%", math.floor(refs.fill.Size.X.Scale * 100))
		else
			-- No known duration (teleport in progress): a block slides along.
			local t = os.clock() % 1.6 / 1.6
			refs.fill.Size = UDim2.fromScale(0.2, 1)
			refs.fill.Position = UDim2.fromScale(t * 1.2 - 0.2, 0)
			label.Text = "CONECTANDO CON EL SERVIDOR DE LA PARTIDA"
			refs.abort.Visible = os.clock() - refs.startedAt > 20
		end
	elseif self._page == "ingame" then
		local left = math.ceil(secondsLeft(match.phaseEnds))
		refs.clock.Text = if match.simulated then string.format("FIN DE LA SIMULACIÓN EN %d", left) else string.format("LA PARTIDA COMIENZA EN %d", left)
	end
end

-- Fills the chips and the buttons of the found page from the snapshot.
function MatchOverlay:_refreshFound(snapshot)
	local refs = self._refs
	local match = snapshot.match
	local accepted = {}
	local count = 0
	for _, userId in match.accepted do
		accepted[userId] = true
		count += 1
	end
	for userId, chip in refs.chips do
		local done = accepted[userId] == true
		chip.state.Text = if done then "ACEPTÓ" else "ESPERANDO"
		chip.state.TextColor3 = if done then GOOD else MUTED
		chip.stroke.Color = if done then GOOD else MUTED
	end
	local mine = accepted[Players.LocalPlayer.UserId] == true
	refs.accept.Visible = not mine
	refs.decline.Visible = not mine
	refs.waiting.Visible = mine
	refs.waiting.Text = string.format("ESPERANDO A LOS DEMÁS  ·  %d/%d", count, #snapshot.members)
end

-- Called with every squad snapshot (nil when there is no squad).
function MatchOverlay:OnPartyChanged(snapshot)
	self._snapshot = snapshot
	local status = if snapshot then snapshot.status else "idle"
	local page = if status == "found" or status == "launching" or status == "ingame" or status == "results" then status else nil
	local matchId = if snapshot and snapshot.match then snapshot.match.id else nil
	if page ~= self._page or matchId ~= self._matchId then
		self:_clear()
		self._matchId = matchId
		if page == "found" then
			self:_buildFound(snapshot)
		elseif page == "launching" then
			self:_buildLoading(snapshot)
		elseif page == "ingame" then
			self:_buildRoom(snapshot)
		elseif page == "results" then
			self:_buildResults(snapshot)
		end
		self._page = page
	end
	if page == "found" then
		self:_refreshFound(snapshot)
	end
	if page then
		self:_tick()
	end
end

function MatchOverlay:IsVisible(): boolean
	return self._page ~= nil
end

function MatchOverlay:Destroy()
	self._alive = false
	self._screen:Destroy()
end

return MatchOverlay
