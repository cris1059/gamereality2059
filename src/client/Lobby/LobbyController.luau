--!strict

-- The hub (main menu): the lobby scene with the player's character on the
-- central ring, the squad on the rings beside them and HubUI over it. Owns
-- the menu state that is not the server's: the selected mode (the squad's
-- mode when in a squad; only the leader changes it), the camera framing per
-- tab, and the haze tint of the selected mode. Squad data comes from
-- PartyController; JUGAR and PERSONAJE go out through the handlers.

local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local LobbyConfig = require(root.Config.LobbyConfig)
local PartyConfig = require(root.Config.PartyConfig)
local ShopConfig = require(root.Config.ShopConfig)
local RemoteNames = require(root.Network.RemoteNames)

local MorphLab = script.Parent.Parent.MorphLab
local MorphLabCameraController = require(MorphLab.MorphLabCameraController)
local AvatarPreview = require(MorphLab.AvatarPreview)
local MorphLabVortex = require(MorphLab.MorphLabVortex)
local CityPreload = require(MorphLab.CityPreload)
local HubUI = require(script.Parent.HubUI)
local PartyController = require(script.Parent.Parent.Party.PartyController)
local GraphicsSettings = require(script.Parent.Parent.Settings.GraphicsSettings)
local DevConfig = require(root.Config.DevConfig)
local RandomCharacter = require(root.Character.RandomCharacter)
local CharacterValidator = require(root.Validation.CharacterValidator)

local LobbyController = {}
LobbyController.__index = LobbyController

local GOOD = Color3.fromRGB(90, 255, 160)
local WARN = Color3.fromRGB(255, 190, 60)
local BAD = Color3.fromRGB(255, 80, 105)
local CYAN = Color3.fromRGB(0, 229, 255)
local HAZE = TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
-- Studio only (DevConfig.PreviewSquad): empty rings get random characters.
local PREVIEW_SQUAD = RunService:IsStudio() and DevConfig.PreviewSquad == true

-- Held posture for a lobby slot (0 = you, 1..4 = the rings left to right).
local function stanceFor(slot: number): any?
	local name = LobbyConfig.StanceBySlot[slot]
	return if name then LobbyConfig.Stances[name] else nil
end

local function classColor(character: any): Color3?
	local info = type(character) == "table" and CharacterCatalog.ClassInfo[character.classId or ""]
	return if info then info.color else nil
end

-- The mode's config; locked modes (LobbyConfig) and unknown ids fall back to
-- the first playable mode.
local function modeInfo(modeId: string)
	local fallback = nil
	for _, mode in LobbyConfig.Modes do
		if not mode.locked then
			if mode.id == modeId then
				return mode
			end
			fallback = fallback or mode
		end
	end
	return fallback or LobbyConfig.Modes[1]
end

function LobbyController.new(playerGui: PlayerGui, config)
	local self = setmetatable({
		_config = config,
		_ui = HubUI.new(playerGui, config, LobbyConfig),
		_camera = MorphLabCameraController.new(config),
		_preview = AvatarPreview.new(config),
		_active = false,
		_mode = modeInfo("").id,
		_party = nil :: any,
		_onOperator = nil :: (() -> ())?,
		_onPlay = nil :: ((string) -> ())?,
		_character = nil :: any,
		_playerData = nil :: any,
		_savedAtmosphere = nil :: any,
		_createdAtmosphere = nil :: Atmosphere?,
		_atmosphere = nil :: Atmosphere?,
		_squad = {} :: { any },
		_squadModels = {} :: { any },
		_baseFrame = nil :: CFrame?,
		_savedLook = nil :: any,
		_lookEffects = {} :: { Instance },
		_rosterKey = "",
		_buildingSquad = false,
		_squadDirty = false,
		_scene = nil :: Model?,
		_skyline = nil :: Model?,
		-- The same sky vortex as MORPHLAB, in place of the skyline's rift.
		_vortex = MorphLabVortex.new(config.Vortex),
		_connections = {} :: { RBXScriptConnection },
	}, LobbyController)
	self._ui:BindControls({
		tab = function(tabId: string)
			self:_frame(tabId)
		end,
		mode = function(modeId: string)
			self:_selectMode(modeId)
		end,
		privateCreate = function()
			if not self._party then
				return
			end
			local ok, data = self._party:CreatePrivateRoom()
			if ok and type(data) == "table" and type(data.code) == "string" then
				self:SetMode("private")
				self._ui:ClosePrivateSetup()
				self._ui:Toast("SALA CREADA // CÓDIGO " .. data.code, GOOD)
			end
		end,
		privateJoin = function(code: string)
			if not self._party then
				return
			end
			local ok, data = self._party:JoinPrivateRoom(code)
			if ok and type(data) == "table" then
				if data.teleporting then
					self._ui:Toast("CONECTANDO CON LA SALA " .. tostring(data.code), GOOD)
				else
					self:SetMode("private")
					self._ui:ClosePrivateSetup()
					self._ui:Toast("TE UNISTE A LA SALA // CÓDIGO " .. tostring(data.code), GOOD)
				end
			end
		end,
		primary = function()
			if self._onPlay then
				self._onPlay(self._mode)
			end
		end,
		editCharacter = function()
			if self._onOperator then
				self._onOperator()
			end
		end,
		invite = function(userId: number)
			local target = Players:GetPlayerByUserId(userId)
			-- Recreate a solo party in the selected mode first (for example after
			-- leaving a private room) so its capacity is not reset to quick/5.
			local hasParty = self._party and self._party:GetSnapshot() ~= nil
			local modeReady = hasParty or (self._party and self._party:SelectMode(self._mode))
			if modeReady and self._party:Request("invite", userId) then
				self._ui:Toast("INVITACIÓN ENVIADA A " .. string.upper(if target then target.DisplayName else "?"), GOOD)
			end
		end,
		kick = function(userId: number)
			if self._party then
				self._party:Request("kick", userId)
			end
		end,
		leave = function()
			if self._party and self._party:Request("leave") then
				self._ui:Toast("SALISTE DEL ESCUADRÓN", WARN)
			end
		end,
		quality = function()
			GraphicsSettings.Cycle()
			self._ui:SetQuality(GraphicsSettings.Label())
		end,
		-- Robux purchase: Roblox shows its own prompt; the server grants the
		-- credits (ShopService) and CurrencyChanged updates the balance.
		buyCredits = function(packId: string)
			for _, pack in ShopConfig.CreditPacks do
				if pack.id == packId then
					if pack.productId <= 0 then
						self._ui:Toast("ESTE PAQUETE AÚN NO ESTÁ A LA VENTA", WARN)
						return
					end
					MarketplaceService:PromptProductPurchase(Players.LocalPlayer, pack.productId)
				end
			end
		end,
		-- Items for NEOCRÉDITOS are not sold yet (ShopConfig.Items is empty).
		buyItem = function(_itemId: string)
			self._ui:Toast("COMPRA DE ARTÍCULOS PRÓXIMAMENTE", WARN)
		end,
	})
	task.spawn(function()
		local runtime = root:WaitForChild("Runtime")
		local remotes = runtime:WaitForChild(RemoteNames.Folder)
		local changed = remotes:WaitForChild(RemoteNames.CurrencyChanged)
		if changed:IsA("RemoteEvent") then
			changed.OnClientEvent:Connect(function(balance: number, added: number?)
				self._ui:SetCredits(balance)
				if added then
					self._ui:Toast(string.format("+%d %s", added, ShopConfig.CurrencyName), GOOD)
				end
			end)
		end
	end)
	return self
end

-- party: the PartyController (snapshot + requests).
function LobbyController:SetParty(party)
	self._party = party
end

-- JUGAR: handler(modeId). The handler decides (start, ready, cancel).
function LobbyController:SetPlayHandler(handler: (string) -> ())
	self._onPlay = handler
end

-- PERSONAJE > EDITAR EN MORPHLAB.
function LobbyController:SetOperatorHandler(handler: () -> ())
	self._onOperator = handler
end

-- --------------------------------------------------------------- modes --

function LobbyController:_inSquad(): boolean
	local snapshot = self._party and self._party:GetSnapshot()
	return snapshot ~= nil and #snapshot.members > 1
end

function LobbyController:_selectMode(modeId: string)
	for _, mode in LobbyConfig.Modes do
		if mode.id == modeId and mode.locked then
			self._ui:Toast(mode.name .. " ESTÁ BLOQUEADO // PRÓXIMAMENTE", WARN)
			return
		end
	end
	if self:_inSquad() and not self._party:IsLeader() then
		self._ui:Toast("EL LÍDER DEL ESCUADRÓN ELIGE EL MODO", WARN)
		return
	end
	if self._party and not self._party:SelectMode(modeId) then
		return
	end
	self:SetMode(modeId)
end

-- Selects a mode card (the squad's mode arrives here for members).
function LobbyController:SetMode(modeId: string)
	self._mode = modeInfo(modeId).id
	self:_tint()
	self:_refreshModes()
	self:_refreshAction()
end

function LobbyController:_refreshModes()
	local availability = {}
	for _, mode in LobbyConfig.Modes do
		local ok, reason, simulated = PartyController.ModeAvailability(mode.id)
		availability[mode.id] = { ok = ok, reason = reason, simulated = simulated }
	end
	local locked = self:_inSquad() and not self._party:IsLeader()
	self._ui:SetModes({
		selected = self._mode,
		locked = locked,
		note = if locked then "EL LÍDER ELIGE EL MODO DEL ESCUADRÓN" else nil,
		availability = availability,
	})
end

-- The main button always says what it will do next.
function LobbyController:_refreshAction()
	local party = self._party
	local snapshot = party and party:GetSnapshot()
	local info = modeInfo(self._mode)
	local members = if snapshot then snapshot.members else {}
	local count = math.max(#members, 1)
	local readyCount, waiting = 0, 0
	for _, member in members do
		if member.ready or member.isLeader then
			readyCount += 1
		elseif not member.isLeader then
			waiting += 1
		end
	end
	local configuredMax = PartyConfig.Modes[self._mode] and PartyConfig.Modes[self._mode].maxMembers
	local maxMembers = if snapshot and type(snapshot.maxMembers) == "number" then snapshot.maxMembers elseif type(configuredMax) == "number" then configuredMax else PartyConfig.MaxMembers
	local privateCode = snapshot and snapshot.privateCode
	local status = if self._mode == "private"
		then string.format("SALA %d/%d  ·  %d LISTOS%s", count, maxMembers, readyCount, if type(privateCode) == "string" then "  ·  CÓDIGO " .. privateCode else "")
		elseif count > 1
		then string.format("ESCUADRÓN %d/%d  ·  %d LISTOS", count, maxMembers, readyCount)
		else "SOLO  ·  Invita a tu escuadrón en ESCUADRÓN"
	local view = { mode = info.name, status = status, statusColor = nil :: Color3?, label = "JUGAR", sublabel = "", enabled = true, pulse = true }
	local available, reason, simulated = PartyController.ModeAvailability(self._mode)
	local leader = not party or party:IsLeader()
	local me = party and party:GetLocalMember()
	if snapshot and snapshot.status == "searching" then
		local seconds = math.floor(party:GetSearchSeconds())
		view.label = "CANCELAR"
		view.sublabel = if self._mode == "private" then "CREANDO SERVIDOR PRIVADO" else string.format("BUSCANDO PARTIDA  %d:%02d", seconds // 60, seconds % 60)
		view.status = if self._mode == "private" then "Preparando la sala para tus invitados..." else "Buscando " .. string.lower(info.name) .. "..."
		view.statusColor = CYAN
		view.pulse = false
	elseif snapshot and snapshot.status == "found" then
		view.label = "PARTIDA ENCONTRADA"
		view.sublabel = "ACEPTA LA PARTIDA"
		view.status = "Responde antes de que se acabe el tiempo"
		view.statusColor = GOOD
		view.enabled = false
	elseif snapshot and snapshot.status == "launching" then
		view.label = "CONECTANDO"
		view.sublabel = "CARGANDO PARTIDA"
		view.enabled = false
		view.statusColor = GOOD
	elseif snapshot and (snapshot.status == "ingame" or snapshot.status == "results") then
		view.label = "EN PARTIDA"
		view.sublabel = if snapshot.status == "results" then "VER RESULTADOS" else info.name
		view.enabled = false
		view.statusColor = GOOD
	elseif not leader then
		local ready = me and me.ready
		view.label = if ready then "NO ESTOY LISTO" else "ESTOY LISTO"
		view.sublabel = if ready then "ESPERANDO AL LÍDER" else "AVISA AL LÍDER QUE PUEDES EMPEZAR"
		view.pulse = not ready
	elseif not available then
		view.label = "NO DISPONIBLE"
		view.sublabel = string.upper(reason or "")
		view.status = info.name .. " necesita un servidor de partidas"
		view.statusColor = WARN
		view.enabled = false
	elseif waiting > 0 then
		view.label = "ESPERANDO"
		view.sublabel = string.format("%d %s SIN MARCAR LISTO", waiting, if waiting == 1 then "INTEGRANTE" else "INTEGRANTES")
		view.enabled = false
	elseif self._mode == "free" then
		view.label = "JUGAR"
		view.sublabel = if count > 1 then "ENTRAR A LA CIUDAD CON TU ESCUADRÓN" else "ENTRAR A LA CIUDAD"
	elseif self._mode == "private" then
		view.label = "INICIAR PARTIDA"
		view.sublabel = if type(privateCode) == "string" then "COMPARTE EL CÓDIGO  " .. privateCode else string.format("SALA PRIVADA  ·  %d/10 JUGADORES", count)
	else
		view.label = "BUSCAR PARTIDA"
		view.sublabel = if simulated then info.name .. "  ·  SIMULACIÓN DE STUDIO" else info.name
	end
	-- A failure reported by the server wins over the general status.
	if snapshot and snapshot.detail and snapshot.status ~= "searching" then
		view.status = PartyController.Describe(snapshot.detail)
		view.statusColor = BAD
	end
	self._ui:SetAction(view)
end

-- ---------------------------------------------------------------- squad --

-- Called by the client on every party snapshot (nil after leaving).
function LobbyController:OnPartyChanged(snapshot)
	if snapshot and snapshot.mode ~= self._mode then
		-- The server owns the room mode. This also updates a solo leader after
		-- creating a coded private room.
		self._mode = modeInfo(snapshot.mode).id
		self:_tint()
	end
	if self._active then
		self:_refreshModes()
		self:_refreshSquad()
		self:_refreshAction()
	end
end

function LobbyController:_squadView()
	local snapshot = self._party and self._party:GetSnapshot()
	local localId = Players.LocalPlayer.UserId
	local members = {}
	local leader = not self._party or self._party:IsLeader()
	local inParty = {}
	if snapshot then
		for _, member in snapshot.members do
			inParty[member.userId] = true
			table.insert(members, {
				userId = member.userId,
				name = member.name,
				isLeader = member.isLeader,
				ready = member.ready,
				isYou = member.userId == localId,
				canKick = leader and member.userId ~= localId,
				color = classColor(if member.userId == localId then self._character else member.character),
			})
		end
	else
		table.insert(members, { userId = localId, name = Players.LocalPlayer.DisplayName, isLeader = true, ready = true, isYou = true, canKick = false, color = classColor(self._character) })
	end
	local inviteable = {}
	for _, player in Players:GetPlayers() do
		if player ~= Players.LocalPlayer and not inParty[player.UserId] then
			table.insert(inviteable, { userId = player.UserId, name = player.DisplayName })
		end
	end
	return {
		count = #members,
		max = if snapshot and type(snapshot.maxMembers) == "number" then snapshot.maxMembers else (PartyConfig.Modes[self._mode].maxMembers or PartyConfig.MaxMembers),
		members = members,
		inviteable = inviteable,
		canLeave = #members > 1,
	}
end

-- Other members stand on the rings (rebuilt only when who is there, or how
-- they look, changes); tags and "+ INVITAR" markers follow every update.
function LobbyController:_refreshSquad()
	local view = self:_squadView()
	self._ui:SetSquad(view)
	local scene = self._scene
	if not scene then
		return
	end
	local snapshot = self._party and self._party:GetSnapshot()
	local others = {}
	local keyParts = {}
	for _, member in (if snapshot then snapshot.members else {}) do
		if member.userId ~= Players.LocalPlayer.UserId then
			table.insert(others, member)
			-- The whole look is in the key: any change rebuilds that rig.
			local character = member.character
			table.insert(keyParts, tostring(member.userId) .. ":" .. (if type(character) == "table" then HttpService:JSONEncode(character) else "?"))
		end
	end
	local key = table.concat(keyParts, ",")
	if key ~= self._rosterKey then
		-- Building rigs yields; a newer roster waits for the current build.
		if self._buildingSquad then
			self._squadDirty = true
			return
		end
		self._rosterKey = key
		self._buildingSquad = true
		self:_buildSquad(scene, others)
		self._buildingSquad = false
		if self._squadDirty then
			self._squadDirty = false
			self:_refreshSquad()
			return
		end
		if not self._active then
			return
		end
	end
	-- Name tags: the player, then each member in ring order.
	local me = self._party and self._party:GetLocalMember()
	local classInfo = CharacterCatalog.ClassInfo[(self._character and self._character.classId) or ""]
	local tags = {
		{
			name = Players.LocalPlayer.DisplayName,
			model = self._preview:GetModel(),
			color = if classInfo then classInfo.color else self._config.Palette.Magenta,
			isPlayer = true,
			ready = if me then (me.ready or me.isLeader) else true,
			isLeader = me ~= nil and me.isLeader and #view.members > 1,
		},
	}
	for ring = 1, #LobbyConfig.SquadSlots do
		local entry = self._squadModels[ring]
		local member = others[ring]
		if entry and member and entry.userId == member.userId then
			table.insert(tags, {
				name = member.name,
				model = entry.model,
				color = entry.color,
				isPlayer = false,
				ready = member.ready or member.isLeader,
				isLeader = member.isLeader,
			})
		elseif entry and entry.preview then
			table.insert(tags, { name = entry.name, model = entry.model, color = entry.color, isPlayer = false, ready = true, isLeader = false })
		end
	end
	local freeRings = {}
	local squadFolder = scene:FindFirstChild("Squad")
	for ring = 1, #LobbyConfig.SquadSlots do
		local anchor = squadFolder and squadFolder:FindFirstChild("SquadSlot" .. ring)
		if anchor and anchor:IsA("BasePart") and not self._squadModels[ring] and #view.members < view.max then
			table.insert(freeRings, anchor)
		end
	end
	self._ui:SetSquad3D(tags, freeRings)
end

-- One squad rig on a ring, with that ring's held posture.
function LobbyController:_spawnRig(scene: Model, spawnPart: BasePart, character: any, ring: number): Model?
	local preview = AvatarPreview.new(self._config)
	preview:SetSpawn(spawnPart)
	preview:SetStance(stanceFor(ring))
	local ok, shown, problem = pcall(preview.Show, preview, scene, character)
	local model = preview:GetModel()
	if ok and shown and model and self._active then
		table.insert(self._squad, { preview = preview })
		return model
	end
	if not ok or (not shown and problem ~= "SUPERSEDED") then
		warn("[REALITY 2059] Squad rig failed on ring " .. ring .. ": " .. tostring(if ok then problem else shown))
	end
	preview:Destroy()
	return nil
end

function LobbyController:_buildSquad(scene: Model, others: { any })
	self:_clearSquad()
	local squadFolder = scene:FindFirstChild("Squad")
	for index, member in others do
		local spawnPart = squadFolder and squadFolder:FindFirstChild("SquadSpawn" .. index)
		local memberCharacter = member.character
		if spawnPart and spawnPart:IsA("BasePart") and CharacterValidator.validate(memberCharacter) then
			local model = self:_spawnRig(scene, spawnPart, memberCharacter, index)
			if model then
				local memberClass = CharacterCatalog.ClassInfo[memberCharacter.classId or ""]
				self._squadModels[index] = {
					userId = member.userId,
					model = model,
					color = if memberClass then memberClass.color else self._config.Palette.Cyan,
				}
			end
		end
	end
	-- Studio preview: the rest of the line-up is scenery, not squad members.
	if PREVIEW_SQUAD then
		for ring = #others + 1, #LobbyConfig.SquadSlots do
			local spawnPart = squadFolder and squadFolder:FindFirstChild("SquadSpawn" .. ring)
			if spawnPart and spawnPart:IsA("BasePart") and self._active then
				local character = RandomCharacter.create(Random.new(2059 + ring))
				local model = self:_spawnRig(scene, spawnPart, character, ring)
				if model then
					local classInfo = CharacterCatalog.ClassInfo[character.classId or ""]
					self._squadModels[ring] = {
						preview = true,
						name = LobbyConfig.SquadNames[ring] or ("Aliado " .. ring),
						model = model,
						color = if classInfo then classInfo.color else self._config.Palette.Cyan,
					}
				end
			end
		end
	end
end

function LobbyController:_clearSquad()
	for _, member in self._squad do
		member.preview:Destroy()
	end
	table.clear(self._squad)
	table.clear(self._squadModels)
end

-- --------------------------------------------------------- scene / look --

-- Camera framing per tab (LobbyConfig.CameraPresets), blended by the camera.
function LobbyController:_frame(tabId: string)
	local scene = self._scene
	if not scene then
		return
	end
	local platform = scene:FindFirstChild("Platform")
	local spawn = platform and platform:FindFirstChild("CharacterSpawn")
	if not spawn or not spawn:IsA("BasePart") then
		return
	end
	-- A still camera: each tab blends to its framing and stays there.
	local preset = LobbyConfig.CameraPresets[tabId]
	if not preset or tabId == "play" then
		self._baseFrame = self._camera:GetAnchorCFrame()
	else
		local origin = spawn.Position - Vector3.new(0, 0.55, 0)
		self._baseFrame = CFrame.lookAt(origin + preset.position, origin + preset.look)
	end
	self._camera:SetFocus(self._baseFrame)
end

-- Night-rooftop look: scene lighting plus bloom, colour grade and a soft
-- depth of field on the distant city. Saved and restored on exit.
function LobbyController:_applyLook()
	local look = LobbyConfig.Look
	local saved = {}
	for property in look.Lighting do
		saved[property] = (Lighting :: any)[property]
	end
	self._savedLook = saved
	for property, value in look.Lighting do
		(Lighting :: any)[property] = value
	end
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "HubBloom"
	bloom.Intensity, bloom.Size, bloom.Threshold = look.Bloom.Intensity, look.Bloom.Size, look.Bloom.Threshold
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "HubGrade"
	grade.Contrast, grade.Saturation, grade.Brightness, grade.TintColor = look.Grade.Contrast, look.Grade.Saturation, look.Grade.Brightness, look.Grade.Tint
	local depth = Instance.new("DepthOfFieldEffect")
	depth.Name = "HubDepth"
	depth.FarIntensity, depth.FocusDistance, depth.InFocusRadius, depth.NearIntensity = look.Depth.FarIntensity, look.Depth.FocusDistance, look.Depth.InFocusRadius, look.Depth.NearIntensity
	for _, effect in { bloom, grade, depth } do
		effect.Parent = Lighting
		table.insert(self._lookEffects, effect)
	end
	local technologyOk, technology = pcall(function()
		return Lighting.Technology
	end)
	if technologyOk and technology ~= Enum.Technology.Future then
		warn("[REALITY 2059] Lighting.Technology no es Future: el lobby pierde sombras y reflejos. Cámbialo en Studio (Lighting > Technology).")
	end
end

function LobbyController:_restoreLook()
	for _, effect in self._lookEffects do
		effect:Destroy()
	end
	table.clear(self._lookEffects)
	for property, value in self._savedLook or {} do
		(Lighting :: any)[property] = value
	end
	self._savedLook = nil
end

-- The lobby's city dressing (lit windows, signs, the sky rift) exists only on
-- this client while the hub is open; the template is built by the server.
function LobbyController:_attachSkyline(scene: Model)
	task.spawn(function()
		local runtime = root:WaitForChild("Runtime", 10)
		local template = runtime and runtime:WaitForChild(LobbyConfig.SkylineName, 10)
		if template and self._active and self._scene == scene and not self._skyline then
			local skyline = template:Clone() :: Model
			local portal = skyline:FindFirstChild("Portal")
			if portal then
				portal:Destroy()
			end
			skyline.Parent = scene
			self._skyline = skyline
		end
	end)
end

function LobbyController:_detachSkyline()
	if self._skyline then
		self._skyline:Destroy()
		self._skyline = nil
	end
end

-- Client-only atmosphere while the lobby is open.
function LobbyController:_applyAtmosphere()
	local settings = LobbyConfig.Atmosphere
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local saved = {}
		for property in settings do
			saved[property] = (atmosphere :: any)[property]
		end
		self._savedAtmosphere = { instance = atmosphere, values = saved }
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "LobbyAtmosphere"
		atmosphere.Parent = Lighting
		self._createdAtmosphere = atmosphere
	end
	for property, value in settings do
		(atmosphere :: any)[property] = value
	end
	self._atmosphere = atmosphere
end

-- The haze takes the selected mode's colour.
function LobbyController:_tint()
	local atmosphere = self._atmosphere
	if not atmosphere or not self._active then
		return
	end
	local info = modeInfo(self._mode)
	TweenService:Create(atmosphere, HAZE, { Color = info.haze, Decay = info.decay }):Play()
end

function LobbyController:_restoreAtmosphere()
	if self._createdAtmosphere then
		self._createdAtmosphere:Destroy()
		self._createdAtmosphere = nil
	end
	local saved = self._savedAtmosphere
	if saved and saved.instance.Parent then
		for property, value in saved.values do
			(saved.instance :: any)[property] = value
		end
	end
	self._savedAtmosphere = nil
	self._atmosphere = nil
end

-- ------------------------------------------------------------ lifecycle --

-- character: the saved character; playerData: the profile (level, credits).
function LobbyController:Activate(character, playerData): (boolean, string?)
	if self._active then
		return true, nil
	end
	-- Studio: each step is logged so a stall shows exactly where it stopped.
	local started = os.clock()
	local function step(name: string)
		if RunService:IsStudio() then
			print(string.format("[REALITY 2059] Lobby: %s (%.2f s)", name, os.clock() - started))
		end
	end
	local runtime = Workspace:WaitForChild(self._config.RuntimeFolderName, 10)
	local scene = runtime and runtime:WaitForChild(LobbyConfig.ModelName, 10)
	if not scene or not scene:IsA("Model") then
		return false, "LOBBY_SCENE_UNAVAILABLE"
	end
	if not character or not character.appearance then
		return false, "NO_CHARACTER"
	end
	step("escena encontrada")
	-- No-op if MORPHLAB already downloaded the city this session.
	CityPreload.Run(nil, 10)
	step("ciudad cargada")
	-- No camera post effects: the hub look (_applyLook) brings its own.
	if not self._camera:Enable(scene, false) then
		return false, "LOBBY_CAMERA_UNAVAILABLE"
	end
	step("cámara lista")
	self._active = true
	self._character = character
	self._playerData = playerData
	self._scene = scene
	self:_attachSkyline(scene)
	local view = self._camera:GetAnchorCFrame()
	if view then
		self._vortex:Attach(scene, view)
	end
	self:_applyAtmosphere()
	self:_applyLook()
	step("iluminación aplicada")

	-- The player's avatar on the centre ring (yields while the server builds
	-- a new item combination; the menu waits for it).
	self._preview:SetStance(stanceFor(0))
	local created, createError = self._preview:Show(scene, character)
	if not created then
		warn("[REALITY 2059] Lobby character unavailable: " .. tostring(createError))
	end

	step("personaje creado")
	local classInfo = CharacterCatalog.ClassInfo[character.classId or ""]
	self._ui:SetProfile(Players.LocalPlayer.DisplayName, playerData)
	self._ui:SetCharacter(character, if classInfo then classInfo.color else nil)
	self._ui:SetClassStats(if classInfo then classInfo.stats else nil, if classInfo then classInfo.color else nil)
	self._ui:SetQuality(GraphicsSettings.Label())
	local snapshot = self._party and self._party:GetSnapshot()
	if snapshot and self:_inSquad() then
		self._mode = modeInfo(snapshot.mode).id
	end
	self._rosterKey = ""
	self:_tint()
	self:_refreshModes()
	self:_refreshAction()
	self:_frame(self._ui:GetTab())
	self._ui:Show()
	step("menú visible")
	-- The squad's rigs (several full characters) build after the menu is up.
	task.spawn(function()
		if self._active then
			self:_refreshSquad()
			step("escuadrón listo")
		end
	end)

	-- Who can be invited changes as players come and go; the search timer
	-- ticks on the main button.
	table.insert(self._connections, Players.PlayerAdded:Connect(function()
		self:_refreshSquad()
	end))
	table.insert(self._connections, Players.PlayerRemoving:Connect(function()
		task.defer(function()
			if self._active then
				self:_refreshSquad()
			end
		end)
	end))
	local tick = 0
	table.insert(self._connections, RunService.Heartbeat:Connect(function(deltaTime)
		tick += deltaTime
		local snapshot = self._party and self._party:GetSnapshot()
		if tick >= 0.5 and snapshot and snapshot.status == "searching" then
			tick = 0
			self:_refreshAction()
		end
	end))
	return true, nil
end

function LobbyController:Deactivate()
	if not self._active then
		return
	end
	self._active = false
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._ui:Hide()
	self._preview:Destroy()
	self:_clearSquad()
	self._vortex:Detach()
	self:_detachSkyline()
	self._rosterKey = ""
	self._baseFrame = nil
	-- The look is undone before the camera restores its own saved lighting.
	self:_restoreLook()
	self._camera:Disable()
	self:_restoreAtmosphere()
	self._scene = nil
end

function LobbyController:IsActive(): boolean
	return self._active
end

function LobbyController:Destroy()
	self:Deactivate()
	self._ui:Destroy()
end

return LobbyController
