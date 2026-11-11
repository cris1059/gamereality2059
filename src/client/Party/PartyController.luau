--!strict

-- Squad state and requests on the client. The server (PartyService) decides
-- and pushes snapshots; the hub (lobby menu) draws them. Invitations pop up on
-- any screen. Also answers which modes can start right now and why not.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local PartyConfig = require(root.Config.PartyConfig)
local MatchConfig = require(root.Config.MatchConfig)
local RemoteNames = require(root.Network.RemoteNames)

local PartyController = {}
PartyController.__index = PartyController

local PANEL = Color3.fromRGB(6, 9, 15)
local CARD = Color3.fromRGB(14, 20, 30)
local GOOD = Color3.fromRGB(90, 255, 180)
local BAD = Color3.fromRGB(255, 80, 105)

-- Server error codes -> player-facing text.
local MESSAGES = {
	NOT_LEADER = "SOLO EL LÍDER PUEDE HACER ESO",
	PARTY_FULL = "EL ESCUADRÓN ESTÁ LLENO",
	ALREADY_MEMBER = "YA ESTÁ EN TU ESCUADRÓN",
	INVITE_EXPIRED = "LA INVITACIÓN EXPIRÓ",
	PARTY_GONE = "ESE ESCUADRÓN YA NO EXISTE",
	NOT_ALL_READY = "FALTAN INTEGRANTES POR ESTAR LISTOS",
	PARTY_BUSY = "EL ESCUADRÓN ESTÁ BUSCANDO O EN PARTIDA",
	PLAYER_NOT_FOUND = "ESE JUGADOR YA NO ESTÁ EN EL SERVIDOR",
	RATE_LIMITED = "DEMASIADAS SOLICITUDES, ESPERA UN MOMENTO",
	MATCH_PLACE_NOT_CONFIGURED = "SIN SERVIDOR DE PARTIDAS CONFIGURADO",
	TELEPORT_UNAVAILABLE = "PARTIDA ENCONTRADA, PERO STUDIO NO PUEDE VIAJAR A ELLA",
	PARTY_TOO_LARGE = "EL ESCUADRÓN ES DEMASIADO GRANDE PARA ESTE MODO",
	MODE_LOCKED = "ESTE MODO ESTÁ BLOQUEADO // PRÓXIMAMENTE",
	INVALID_PRIVATE_CODE = "EL CÓDIGO DEBE TENER 6 CARACTERES",
	PRIVATE_ROOM_NOT_FOUND = "ESA SALA PRIVADA NO EXISTE O YA EXPIRÓ",
	PRIVATE_CODE_UNAVAILABLE = "NO SE PUDO CONSULTAR EL CÓDIGO; INTÉNTALO DE NUEVO",
	NOT_SEARCHING = "NO HAY BÚSQUEDA ACTIVA",
	CANCELADO = "BÚSQUEDA CANCELADA",
	MATCH_EXPIRED = "TIEMPO AGOTADO: NO TODOS ACEPTARON LA PARTIDA",
	MATCH_DECLINED = "UN INTEGRANTE RECHAZÓ LA PARTIDA",
	MATCH_GONE = "LA PARTIDA YA NO ESTÁ DISPONIBLE",
	NO_MATCH = "NO HAY PARTIDA PENDIENTE",
	NOT_IN_MATCH = "NO ESTÁS EN UNA PARTIDA",
	MAP_NOT_FOUND = "NO HAY MAPA LISTO EN ESTE SERVIDOR",
	ALREADY_IN_MATCH = "UN INTEGRANTE YA ESTÁ EN UNA PARTIDA",
	NO_PLAYERS = "NO HAY JUGADORES EN LA SALA",
}

function PartyController.Describe(code: string?): string
	if not code then
		return ""
	end
	local base = string.split(code, ":")[1]
	if MESSAGES[base] then
		return MESSAGES[base]
	end
	if base == "QUEUE_UNAVAILABLE" then
		return "SIN CONEXIÓN CON EL EMPAREJAMIENTO"
	elseif base == "TELEPORT_FAILED" then
		return "FALLÓ EL VIAJE A LA PARTIDA, INTÉNTALO DE NUEVO"
	end
	return "ERROR // " .. code
end

-- Whether a mode can be started at all on this experience, and why not.
-- Third value: the search will be a Studio SIMULATION, not a real match.
function PartyController.ModeAvailability(mode: string): (boolean, string?, boolean)
	local info = PartyConfig.Modes[mode]
	if not info then
		return false, "MODO DESCONOCIDO", false
	end
	if info.locked then
		return false, "PRÓXIMAMENTE", false
	end
	-- Private rooms play on their own server (MatchService): no match place.
	if mode == "private" and MatchConfig.LocalPrivateMatches then
		return true, nil, false
	end
	if info.matchmaking and (PartyConfig.Matchmaking.PlaceIds[mode] or 0) == 0 then
		if game:GetService("RunService"):IsStudio() and PartyConfig.StudioSimulation then
			return true, nil, true
		end
		return false, "Falta configurar el servidor de partidas de este modo.", false
	end
	return true, nil, false
end

local function text(parent: Instance, value: string, size: number, color: Color3, font: Enum.Font): TextLabel
	local item = Instance.new("TextLabel")
	item.BackgroundTransparency = 1
	item.Font = font
	item.Text = value
	item.TextSize = size
	item.TextColor3 = color
	item.TextWrapped = true
	item.Parent = parent
	return item
end

local function button(parent: Instance, value: string, color: Color3, font: Enum.Font): TextButton
	local item = Instance.new("TextButton")
	item.BackgroundColor3 = CARD
	item.BorderSizePixel = 0
	item.Font = font
	item.Text = value
	item.TextSize = 14
	item.TextColor3 = Color3.fromRGB(234, 244, 255)
	item.Parent = parent
	local outline = Instance.new("UIStroke")
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Color = color
	outline.Transparency = 0.25
	outline.Parent = item
	return item
end

function PartyController.new(playerGui: PlayerGui, config)
	local runtime = root:WaitForChild("Runtime")
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	local self = setmetatable({
		_config = config,
		_request = remotes:WaitForChild(RemoteNames.PartyRequest) :: RemoteFunction,
		_snapshot = nil :: any,
		_onLaunch = nil :: ((string) -> ())?,
		_onChanged = nil :: ((any) -> ())?,
		_inviteQueue = {} :: { any },
		_searchStarted = 0,
		_connections = {} :: { RBXScriptConnection },
		_toastToken = 0,
	}, PartyController)
	local fonts = config.Typography

	local screen = Instance.new("ScreenGui")
	screen.Name = "Reality2059Party"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.DisplayOrder = 120
	screen.Parent = playerGui
	self._screen = screen

	-- Invitation popup (any screen).
	local popup = Instance.new("Frame")
	popup.Name = "Invite"
	popup.AnchorPoint = Vector2.new(0.5, 0)
	popup.Position = UDim2.new(0.5, 0, 0, 16)
	popup.Size = UDim2.fromOffset(400, 100)
	popup.BackgroundColor3 = PANEL
	popup.BackgroundTransparency = 0.05
	popup.BorderSizePixel = 0
	popup.Visible = false
	popup.Parent = screen
	local popupStroke = Instance.new("UIStroke")
	popupStroke.Color = config.Palette.Cyan
	popupStroke.Parent = popup
	local popupText = text(popup, "", 15, config.Palette.Text, fonts.Interface)
	popupText.Position = UDim2.fromOffset(14, 8)
	popupText.Size = UDim2.new(1, -28, 0, 42)
	local accept = button(popup, "ACEPTAR", GOOD, fonts.Display)
	accept.Size = UDim2.new(0.5, -18, 0, 34)
	accept.Position = UDim2.new(0, 14, 1, -44)
	local decline = button(popup, "RECHAZAR", BAD, fonts.Display)
	decline.Size = UDim2.new(0.5, -18, 0, 34)
	decline.Position = UDim2.new(0.5, 4, 1, -44)
	accept.Activated:Connect(function()
		self:_answerInvite(true)
	end)
	decline.Activated:Connect(function()
		self:_answerInvite(false)
	end)
	self._popup = popup
	self._popupText = popupText

	local toast = text(screen, "", 15, config.Palette.Text, fonts.Interface)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -130)
	toast.Size = UDim2.fromOffset(560, 32)
	toast.BackgroundColor3 = PANEL
	toast.BackgroundTransparency = 0.15
	toast.Visible = false
	self._toast = toast

	table.insert(self._connections, (remotes:WaitForChild(RemoteNames.PartyUpdate) :: RemoteEvent).OnClientEvent:Connect(function(snapshot)
		if type(snapshot) == "table" and snapshot.privateJoinError then
			self:Toast(PartyController.Describe(snapshot.privateJoinError), BAD)
			return
		end
		local wasSearching = self._snapshot and self._snapshot.status == "searching"
		self._snapshot = snapshot
		if snapshot and snapshot.status == "searching" and not wasSearching then
			self._searchStarted = os.clock()
		end
		if self._onChanged then
			self._onChanged(snapshot)
		end
	end))
	table.insert(self._connections, (remotes:WaitForChild(RemoteNames.PartyInvite) :: RemoteEvent).OnClientEvent:Connect(function(invite)
		if type(invite) == "table" and type(invite.partyId) == "string" then
			invite.receivedAt = os.clock()
			table.insert(self._inviteQueue, invite)
			self:_showInvite()
		end
	end))
	table.insert(self._connections, (remotes:WaitForChild(RemoteNames.PartyLaunch) :: RemoteEvent).OnClientEvent:Connect(function(launch)
		if type(launch) == "table" and self._onLaunch then
			self._onLaunch(launch.mode)
		end
	end))
	task.defer(function()
		self:Request("get")
	end)
	return self
end

function PartyController:SetLaunchHandler(handler: (string) -> ())
	self._onLaunch = handler
end

function PartyController:SetChangedHandler(handler: (any) -> ())
	self._onChanged = handler
end

function PartyController:GetSnapshot(): any
	return self._snapshot
end

-- Seconds since the current search started (0 when not searching).
function PartyController:GetSearchSeconds(): number
	if self._snapshot and self._snapshot.status == "searching" then
		return os.clock() - self._searchStarted
	end
	return 0
end

function PartyController:GetLocalMember(): any
	local snapshot = self._snapshot
	if not snapshot then
		return nil
	end
	for _, member in snapshot.members do
		if member.userId == Players.LocalPlayer.UserId then
			return member
		end
	end
	return nil
end

-- Solo players lead themselves.
function PartyController:IsLeader(): boolean
	local me = self:GetLocalMember()
	return me == nil or me.isLeader == true
end

function PartyController:Toast(message: string, color: Color3?)
	self._toastToken += 1
	local token = self._toastToken
	self._toast.Text = message
	self._toast.TextColor3 = color or self._config.Palette.Text
	self._toast.Visible = true
	task.delay(3.5, function()
		if self._toastToken == token then
			self._toast.Visible = false
		end
	end)
end

function PartyController:Request(action: string, argument: any?): (boolean, any?)
	local ok, result = pcall(function()
		return self._request:InvokeServer(action, argument)
	end)
	if not ok or type(result) ~= "table" then
		self:Toast("SIN CONEXIÓN CON EL SERVIDOR", BAD)
		return false, nil
	end
	if not result.ok and action ~= "get" then
		self:Toast(PartyController.Describe(result.errorCode), BAD)
	end
	return result.ok == true, result.data
end

function PartyController:CreatePrivateRoom(): (boolean, any?)
	return self:Request("create_private")
end

function PartyController:JoinPrivateRoom(code: string): (boolean, any?)
	return self:Request("join_private", code)
end

-- The leader picks the squad's mode (members see it); solo players keep it
-- locally until they start.
function PartyController:SelectMode(mode: string): boolean
	local snapshot = self._snapshot
	if not snapshot then
		-- Persist the choice on the server immediately. This matters for a solo
		-- leader who selects a 10-player private room before inviting anyone.
		local ok = self:Request("mode", mode)
		return ok
	end
	if not self:IsLeader() then
		self:Toast("EL LÍDER ELIGE EL MODO", BAD)
		return false
	end
	if snapshot.mode == mode then
		return true
	end
	local ok = self:Request("mode", mode)
	return ok
end

-- The hub's main button: cancels a search, toggles LISTO for members, and
-- for the leader (or a solo player) starts the chosen mode.
function PartyController:Play(mode: string)
	local snapshot = self._snapshot
	if snapshot and snapshot.status == "searching" then
		self:Request("cancel")
		return
	end
	if not self:IsLeader() then
		local me = self:GetLocalMember()
		self:Request("ready", not (me and me.ready))
		return
	end
	local available, reason = PartyController.ModeAvailability(mode)
	if not available then
		self:Toast(string.upper(reason or "MODO NO DISPONIBLE"), BAD)
		return
	end
	if not snapshot or snapshot.mode ~= mode then
		if not self:Request("mode", mode) then
			return
		end
	end
	self:Request("start")
end

function PartyController:_showInvite()
	-- Drop expired invites, then show the oldest.
	while self._inviteQueue[1] and os.clock() - self._inviteQueue[1].receivedAt > PartyConfig.InviteSeconds do
		table.remove(self._inviteQueue, 1)
	end
	local invite = self._inviteQueue[1]
	if not invite then
		self._popup.Visible = false
		return
	end
	local modeInfo = PartyConfig.Modes[invite.mode]
	self._popupText.Text = string.format("%s TE INVITA A SU ESCUADRÓN // %s", string.upper(tostring(invite.fromName)), if modeInfo then modeInfo.name else "")
	if not self._popup.Visible then
		self._popup.Visible = true
		self._popup.Position = UDim2.new(0.5, 0, 0, -110)
		TweenService:Create(self._popup, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = UDim2.new(0.5, 0, 0, 16) }):Play()
	end
	local shown = invite
	task.delay(PartyConfig.InviteSeconds, function()
		if self._inviteQueue[1] == shown then
			table.remove(self._inviteQueue, 1)
			self:_showInvite()
		end
	end)
end

function PartyController:_answerInvite(accept: boolean)
	local invite = table.remove(self._inviteQueue, 1)
	if invite then
		local ok = self:Request(if accept then "accept" else "decline", invite.partyId)
		if accept and ok then
			self:Toast("TE UNISTE AL ESCUADRÓN", GOOD)
		end
	end
	self:_showInvite()
end

function PartyController:Destroy()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._screen:Destroy()
end

return PartyController
