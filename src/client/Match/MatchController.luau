--!strict

-- Client side of matches played on this server (MatchService). Follows
-- MatchState: on the first countdown / playing state it asks the game to
-- enter the map in shooter mode; it shows the score (both teams, time left,
-- the score limit), the countdown, the kill feed and, at the end, the
-- results; on "closed" (or after leaving) the game goes back to the lobby.
-- Hold P to leave a match early.

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local MatchConfig = require(root.Config.MatchConfig)

local MatchController = {}
MatchController.__index = MatchController

local LEAVE_ACTION = "Reality2059LeaveMatch"
local LEAVE_HOLD = 1.5
local TEXT = Color3.fromRGB(236, 240, 255)
local MUTED = Color3.fromRGB(150, 158, 182)
local PANEL = Color3.fromRGB(8, 10, 20)
local FEED_SECONDS = 5

local function label(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, font: Enum.Font, textSize: number, color: Color3): TextLabel
	local item = Instance.new("TextLabel")
	item.Name = name
	item.Size = size
	item.Position = position
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = text
	item.TextSize = textSize
	item.TextColor3 = color
	item.TextStrokeTransparency = 0.6
	item.Parent = parent
	return item
end

local function panel(parent: Instance, name: string, size: UDim2, position: UDim2, anchor: Vector2): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = anchor
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = PANEL
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(0, 6)
	round.Parent = frame
	return frame
end

local function teamColor(teamId: string?): Color3
	local info = teamId and MatchConfig.Teams[teamId]
	return if info then info.color else MUTED
end

local function teamName(teamId: string?): string
	local info = teamId and MatchConfig.Teams[teamId]
	return if info then info.name else ""
end

-- onEnter(mapKey): enter the map in shooter mode; onExit(): back to the lobby.
function MatchController.new(playerGui: PlayerGui, onEnter: (string) -> (), onExit: () -> ())
	local screen = Instance.new("ScreenGui")
	screen.Name = "MatchHUD"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 95
	screen.Enabled = false
	screen.Parent = playerGui

	-- Score bar (top centre): A score · time · B score.
	local bar = panel(screen, "Score", UDim2.fromOffset(360, 62), UDim2.new(0.5, 0, 0, 10), Vector2.new(0.5, 0))
	local scoreA = label(bar, "ScoreA", "0", UDim2.fromOffset(90, 40), UDim2.fromOffset(10, 4), Enum.Font.SciFi, 34, teamColor("A"))
	local clock = label(bar, "Clock", "--:--", UDim2.fromOffset(160, 30), UDim2.fromOffset(100, 4), Enum.Font.SciFi, 26, TEXT)
	local scoreB = label(bar, "ScoreB", "0", UDim2.fromOffset(90, 40), UDim2.fromOffset(260, 4), Enum.Font.SciFi, 34, teamColor("B"))
	local subtitle = label(bar, "Subtitle", "", UDim2.new(1, -20, 0, 16), UDim2.fromOffset(10, 42), Enum.Font.Code, 11, MUTED)
	local yourTeam = label(screen, "YourTeam", "", UDim2.fromOffset(360, 18), UDim2.new(0.5, -180, 0, 76), Enum.Font.Code, 12, TEXT)
	local leaveHint = label(screen, "LeaveHint", "MANTÉN P PARA SALIR DE LA PARTIDA", UDim2.fromOffset(320, 16), UDim2.new(0, 16, 0, 60), Enum.Font.Code, 11, MUTED)
	leaveHint.TextXAlignment = Enum.TextXAlignment.Left

	-- Countdown (centre).
	local countdown = label(screen, "Countdown", "", UDim2.fromOffset(600, 60), UDim2.new(0.5, -300, 0.3, 0), Enum.Font.SciFi, 40, TEXT)

	-- Kill feed (top right).
	local feed = Instance.new("Frame")
	feed.Name = "KillFeed"
	feed.AnchorPoint = Vector2.new(1, 0)
	feed.Position = UDim2.new(1, -16, 0, 60)
	feed.Size = UDim2.fromOffset(340, 180)
	feed.BackgroundTransparency = 1
	feed.Parent = screen
	local feedLayout = Instance.new("UIListLayout")
	feedLayout.Padding = UDim.new(0, 4)
	feedLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	feedLayout.SortOrder = Enum.SortOrder.LayoutOrder
	feedLayout.Parent = feed

	-- Results (full panel).
	local results = panel(screen, "Results", UDim2.fromOffset(560, 420), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	results.BackgroundTransparency = 0.08
	results.Visible = false
	local resultTitle = label(results, "Title", "", UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 18), Enum.Font.SciFi, 40, TEXT)
	local resultScore = label(results, "Score", "", UDim2.new(1, 0, 0, 26), UDim2.fromOffset(0, 68), Enum.Font.SciFi, 22, MUTED)
	local table_ = Instance.new("Frame")
	table_.Name = "Players"
	table_.Position = UDim2.fromOffset(24, 108)
	table_.Size = UDim2.new(1, -48, 0, 250)
	table_.BackgroundTransparency = 1
	table_.Parent = results
	local tableLayout = Instance.new("UIListLayout")
	tableLayout.Padding = UDim.new(0, 2)
	tableLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tableLayout.Parent = table_
	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -14)
	back.Size = UDim2.fromOffset(240, 40)
	back.BackgroundColor3 = Color3.fromRGB(30, 60, 90)
	back.Font = Enum.Font.SciFi
	back.Text = "VOLVER AL LOBBY"
	back.TextSize = 18
	back.TextColor3 = TEXT
	back.Parent = results
	local backRound = Instance.new("UICorner")
	backRound.CornerRadius = UDim.new(0, 6)
	backRound.Parent = back

	local self = setmetatable({
		_screen = screen,
		_scoreA = scoreA,
		_scoreB = scoreB,
		_clock = clock,
		_subtitle = subtitle,
		_yourTeam = yourTeam,
		_countdown = countdown,
		_feed = feed,
		_results = results,
		_resultTitle = resultTitle,
		_resultScore = resultScore,
		_table = table_,
		_onEnter = onEnter,
		_onExit = onExit,
		_state = nil :: any,
		_inMatch = false,
		_feedOrder = 0,
		_leaveRemote = nil :: RemoteEvent?,
		_leaveStarted = nil :: number?,
	}, MatchController)
	back.Activated:Connect(function()
		self._results.Visible = false
		self._screen.Enabled = false
	end)
	task.spawn(function()
		local remotes = root:WaitForChild("Runtime"):WaitForChild(RemoteNames.Folder)
		local state = remotes:WaitForChild(RemoteNames.MatchState)
		self._leaveRemote = remotes:WaitForChild(RemoteNames.MatchLeave) :: RemoteEvent
		if state:IsA("RemoteEvent") then
			state.OnClientEvent:Connect(function(view)
				self:_onState(view)
			end)
		end
	end)
	RunService.RenderStepped:Connect(function()
		self:_tick()
	end)
	return self
end

function MatchController:IsInMatch(): boolean
	return self._inMatch
end

function MatchController:_feedLine(event)
	local line = Instance.new("TextLabel")
	self._feedOrder += 1
	line.LayoutOrder = -self._feedOrder
	line.Size = UDim2.fromOffset(340, 22)
	line.BackgroundColor3 = PANEL
	line.BackgroundTransparency = 0.35
	line.Font = Enum.Font.GothamBold
	line.TextSize = 14
	line.TextColor3 = TEXT
	line.RichText = true
	line.TextXAlignment = Enum.TextXAlignment.Right
	local function colored(name: string, teamId: string?): string
		local color = teamColor(teamId)
		return string.format('<font color="rgb(%d,%d,%d)">%s</font>', math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5), name)
	end
	if event.kind == "left" then
		line.Text = event.victim .. " salió de la partida  "
	elseif event.killer then
		line.Text = string.format("%s  eliminó a  %s  ", colored(event.killer, event.killerTeam), colored(event.victim, event.victimTeam))
	else
		line.Text = colored(event.victim, event.victimTeam) .. "  cayó  "
	end
	line.Parent = self._feed
	task.delay(FEED_SECONDS, function()
		line:Destroy()
	end)
end

function MatchController:_showResults(view)
	local result = view.result or {}
	local mine = view.team
	local title = if result.winner == "draw" then "EMPATE"
		elseif result.winner == mine then "VICTORIA"
		else "DERROTA"
	self._resultTitle.Text = title
	self._resultTitle.TextColor3 = if result.winner == mine then teamColor(mine) else TEXT
	self._resultScore.Text = string.format("%s  %d  —  %d  %s", teamName("A"), view.score.A, view.score.B, teamName("B"))
	for _, child in self._table:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local header = label(self._table, "Header", "JUGADOR                                   BAJAS   MUERTES", UDim2.new(1, 0, 0, 20), UDim2.new(), Enum.Font.Code, 12, MUTED)
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.LayoutOrder = 0
	local roster = table.clone(view.roster)
	table.sort(roster, function(a, b)
		if a.team ~= b.team then
			return a.team < b.team
		end
		return a.kills > b.kills
	end)
	for index, entry in roster do
		local row = label(self._table, "Row", "", UDim2.new(1, 0, 0, 20), UDim2.new(), Enum.Font.Code, 14, teamColor(entry.team))
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.LayoutOrder = index
		row.Text = string.format("%-36s %5d   %7d", string.sub(entry.name, 1, 36), entry.kills, entry.deaths)
	end
	self._results.Visible = true
end

function MatchController:_onState(view)
	if type(view) ~= "table" then
		return
	end
	if view.phase == "closed" then
		self._state = nil
		self:_unbindLeave()
		if self._inMatch then
			self._inMatch = false
			self._onExit()
		end
		-- The results stay up until VOLVER AL LOBBY.
		if not self._results.Visible then
			self._screen.Enabled = false
		end
		return
	end
	self._state = view
	self._screen.Enabled = true
	if (view.phase == "countdown" or view.phase == "playing") and not self._inMatch then
		self._inMatch = true
		self._results.Visible = false
		self:_bindLeave()
		task.spawn(self._onEnter, view.map)
	end
	self._scoreA.Text = tostring(view.score.A)
	self._scoreB.Text = tostring(view.score.B)
	self._subtitle.Text = string.format("%s  ·  PRIMERO A %d", view.mapName or "", view.scoreLimit or 0)
	self._yourTeam.Text = if view.team then "TU EQUIPO: " .. teamName(view.team) else ""
	self._yourTeam.TextColor3 = teamColor(view.team)
	if view.event then
		self:_feedLine(view.event)
	end
	if view.phase == "ended" then
		self:_unbindLeave()
		if self._inMatch then
			self._inMatch = false
			self._onExit()
		end
		self:_showResults(view)
	end
end

function MatchController:_tick()
	local view = self._state
	if not view then
		return
	end
	local left = math.max(0, math.ceil((view.endsAt or 0) - Workspace:GetServerTimeNow()))
	if view.phase == "countdown" then
		self._countdown.Text = string.format("LA PARTIDA EMPIEZA EN %d", left)
		self._clock.Text = "--:--"
	elseif view.phase == "playing" then
		self._countdown.Text = ""
		self._clock.Text = string.format("%d:%02d", left // 60, left % 60)
	else
		self._countdown.Text = ""
		self._clock.Text = "FIN"
	end
	if self._leaveStarted then
		local held = os.clock() - self._leaveStarted
		self._countdown.Text = string.format("SALIENDO… %d", math.max(0, math.ceil(LEAVE_HOLD - held)))
		if held >= LEAVE_HOLD then
			self._leaveStarted = nil
			if self._leaveRemote then
				self._leaveRemote:FireServer()
			end
		end
	end
end

function MatchController:_bindLeave()
	ContextActionService:BindAction(LEAVE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self._leaveStarted = os.clock()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self._leaveStarted = nil
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.P)
end

function MatchController:_unbindLeave()
	self._leaveStarted = nil
	ContextActionService:UnbindAction(LEAVE_ACTION)
end

return MatchController
