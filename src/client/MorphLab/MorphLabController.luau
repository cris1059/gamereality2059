--!strict

-- MORPHLAB: the character creator. The draft (Character/CharacterDraft) is
-- edited through validated setters and shown on a standard R15 avatar
-- (AvatarPreview): catalog items swap the model (built by the server), the
-- rest is painted on it instantly. The scene is a rooftop facing the city;
-- the lobby's lit skyline and haze are borrowed while MORPHLAB is open.

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local CharacterDraft = require(root.Character.CharacterDraft)
local LobbyConfig = require(root.Config.LobbyConfig)

local MorphLabCameraController = require(script.Parent.MorphLabCameraController)
local MorphLabUI = require(script.Parent.MorphLabUI)
local AvatarPreview = require(script.Parent.AvatarPreview)
local MorphLabVortex = require(script.Parent.MorphLabVortex)
local CityPreload = require(script.Parent.CityPreload)

local MorphLabController = {}
MorphLabController.__index = MorphLabController

-- ENTRAR A LA REALIDAD unlocks once every section has been edited at least
-- once (any control in it). Randomize does not count.
local PROGRESS_CATEGORIES = table.freeze({ "BODY", "FACE", "HAIR", "OUTFIT", "IMPLANTS", "CLASS", "COLOR" })

local function posesFrom(config): { any }
	local poses = {}
	for _, poseId in config.PoseOrder do
		local pose = config.Poses[poseId]
		if pose then
			table.insert(poses, pose)
		end
	end
	return poses
end

function MorphLabController.new(playerGui: PlayerGui, config)
	local self = setmetatable({
		_config = config,
		_ui = MorphLabUI.new(playerGui, config),
		_camera = MorphLabCameraController.new(config),
		_preview = AvatarPreview.new(config),
		_vortex = MorphLabVortex.new(config.Vortex),
		_draft = CharacterDraft.createDefault(),
		_classStatsOpen = false,
		_savedChat = nil :: { [Instance]: boolean }?,
		_completed = {},
		_suppressProgress = false,
		_onConfirm = nil,
		_active = false,
		_scene = nil :: Model?,
		_skyline = nil :: Model?,
		_atmosphere = nil :: Atmosphere?,
		_createdAtmosphere = nil :: Atmosphere?,
		_savedAtmosphere = nil :: any?,
		_platformColors = nil :: { [BasePart]: Color3 }?,
		_portraitToken = 0,
		_focusToken = 0,
	}, MorphLabController)

	-- Runs a validated draft change; on success refreshes the avatar and the
	-- UI selection, and marks `category` as edited.
	local function edit(category: string, change: () -> (boolean, string?), refresh: () -> (), rejectedStatus: string?)
		local ok, problem = change()
		if not ok then
			warn("[REALITY 2059] Change rejected: " .. tostring(problem))
			self._ui:SetAvatarStatus(rejectedStatus or "CAMBIO RECHAZADO", true)
			return
		end
		refresh()
		if category ~= "CLASS" then
			self:_hideClassStats()
		end
		self:_markEdited(category)
		self:_refreshPreview()
	end

	local handlers = {
		drag = function(deltaPixels: number)
			self._preview:Rotate(deltaPixels * config.Preview.DragRadiansPerPixel)
		end,
		zoom = function(direction: number)
			self._camera:Zoom(direction * config.Camera.ZoomStep)
		end,
		bodyBase = function(bodyBaseId: string)
			edit("BODY", function()
				return CharacterDraft.setBodyBase(self._draft, bodyBaseId)
			end, function()
				self._ui:SetSelectedBodyBase(bodyBaseId)
				self._ui:SetGender(if bodyBaseId == "slim" then "f" else "m")
			end, "SELECCIÓN DE CUERPO RECHAZADA")
		end,
		skinTone = function(skinToneId: string)
			edit("BODY", function()
				return CharacterDraft.setSkinTone(self._draft, skinToneId)
			end, function()
				self._ui:SetSelectedSkinTone(skinToneId)
			end)
		end,
		face = function(faceId: string)
			edit("FACE", function()
				return CharacterDraft.setFace(self._draft, faceId)
			end, function()
				self._ui:SetSelectedFace(faceId)
			end)
			self:_focusFace()
		end,
		hairStyle = function(hairId: string)
			edit("HAIR", function()
				return CharacterDraft.setHair(self._draft, hairId)
			end, function()
				self._ui:SetSelectedHair(hairId)
			end)
		end,
		piece = function(slot: string, pieceId: string)
			edit("OUTFIT", function()
				return CharacterDraft.setPiece(self._draft, slot, pieceId)
			end, function()
				self._ui:SetSelectedPieces(CharacterDraft.pieces(self._draft))
				self._preview:StrikePose()
			end)
		end,
		accessory = function(accessoryId: string)
			edit("OUTFIT", function()
				return CharacterDraft.toggleAccessory(self._draft, accessoryId)
			end, function()
				self._ui:SetSelectedAccessories(self._draft.outfit.accessoryIds)
			end, string.format("MÁXIMO %d ACCESORIOS", CharacterCatalog.MaxAccessories))
		end,
		implant = function(implantId: string)
			edit("IMPLANTS", function()
				return CharacterDraft.toggleImplant(self._draft, implantId)
			end, function()
				self._ui:SetSelectedImplants(self._draft.cyberwareIds)
				self._ui:SetColorHint(self._draft.cyberwareIds[1] ~= "none")
			end, "LÍMITE DE IMPLANTES O CAMBIO RECHAZADO")
		end,
		color = function(slot: string, colorId: string)
			edit("COLOR", function()
				return CharacterDraft.setColor(self._draft, slot, colorId)
			end, function()
				self._ui:SetSelectedColors(self._draft.colors)
			end)
		end,
		class = function(classId: string)
			edit("CLASS", function()
				return CharacterDraft.setClass(self._draft, classId)
			end, function()
				self._ui:SetSelectedClass(classId)
				self:_applyClassColor()
				self._preview:StrikePose()
			end)
			self:_showClassStats(classId)
		end,
		closeClassStats = function()
			self:_hideClassStats()
		end,
		confirm = function()
			if self._onConfirm then
				self._onConfirm(CharacterDraft.clone(self._draft))
			else
				self._ui:SetAvatarStatus("PERFIL COMPLETO", false)
			end
		end,
		-- Back to the default look, in underwear again.
		resetDraft = function()
			self._draft = CharacterDraft.reset(self._draft)
			self:_syncUI()
			self:_refreshPreview()
			self._ui:SetAvatarStatus("VALORES RESTABLECIDOS", false)
		end,
		-- Random look from the whole catalog, through the validated setters.
		randomize = function()
			-- Randomize touches every section but does not count as reviewing them.
			self._suppressProgress = true
			local random = Random.new()
			local function pick(list: { string }): string
				return list[random:NextInteger(1, #list)]
			end
			local draft = self._draft
			CharacterDraft.setBodyBase(draft, pick(CharacterCatalog.BodyBases))
			CharacterDraft.setSkinTone(draft, pick(CharacterCatalog.SkinTones))
			CharacterDraft.setFace(draft, pick(CharacterCatalog.Faces))
			local gender = if draft.appearance.bodyBaseId == "slim" then "f" else "m"
			local hairs = {}
			for _, hairId in CharacterCatalog.Hair do
				local info = CharacterCatalog.HairInfo[hairId]
				if hairId ~= "none" and (info.gender == "both" or info.gender == gender) then
					table.insert(hairs, hairId)
				end
			end
			CharacterDraft.setHair(draft, pick(hairs))
			-- Each piece on most of the time; a jacket only now and then.
			for _, slot in CharacterCatalog.OutfitSlots do
				local options = CharacterCatalog.OutfitPieces[slot]
				local wear = random:NextNumber() < (if slot == "jacket" then 0.55 else 0.85)
				CharacterDraft.setPiece(draft, slot, if wear then options[random:NextInteger(2, #options)] else "none")
			end
			draft.outfit.accessoryIds = {}
			for _ = 1, random:NextInteger(0, 2) do
				local accessoryId = pick(CharacterCatalog.Accessories)
				if not table.find(draft.outfit.accessoryIds, accessoryId) then
					CharacterDraft.toggleAccessory(draft, accessoryId)
				end
			end
			draft.cyberwareIds = { "none" }
			for _ = 1, random:NextInteger(0, 2) do
				local implantId = CharacterCatalog.Implants[random:NextInteger(2, #CharacterCatalog.Implants)]
				if not table.find(draft.cyberwareIds, implantId) then
					CharacterDraft.toggleImplant(draft, implantId)
				end
			end
			CharacterDraft.setClass(draft, pick(CharacterCatalog.Classes))
			CharacterDraft.setColor(draft, "neonPrimary", pick(CharacterCatalog.NeonColors))
			CharacterDraft.setColor(draft, "neonSecondary", pick(CharacterCatalog.NeonColors))
			CharacterDraft.setColor(draft, "metal", pick(CharacterCatalog.MetalFinishes))
			self:_syncUI()
			self:_refreshPreview()
			self._preview:StrikePose()
			self._suppressProgress = false
		end,
	}
	self._ui:BindControls(handlers)
	self._ui:SetControlsEnabled(false)
	return self
end

-- Receives the finished character when ENTRAR A LA REALIDAD is pressed.
function MorphLabController:SetConfirmHandler(handler: (any) -> ())
	self._onConfirm = handler
end

-- Close-up on the new face for a few seconds, then back to the full body.
local FACE_FOCUS_SECONDS = 3.5

function MorphLabController:_focusFace()
	local model = self._preview:GetModel()
	local head = model and model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local target = head.Position + Vector3.new(0, 0.1, 0)
	local eye = target + head.CFrame.LookVector * 4.2 + head.CFrame.RightVector * 0.6 + Vector3.new(0, 0.25, 0)
	self._camera:SetFocus(CFrame.lookAt(eye, target))
	self._focusToken += 1
	local token = self._focusToken
	task.delay(FACE_FOCUS_SECONDS, function()
		if token == self._focusToken and self._active then
			self:_restoreView()
		end
	end)
end

-- The resting view: the full body, nudged left while the class stats show.
local CLASS_VIEW_SHIFT = 1.4

function MorphLabController:_restoreView()
	local anchor = self._camera:GetAnchorCFrame()
	if self._classStatsOpen and anchor then
		self._camera:SetFocus(anchor * CFrame.new(CLASS_VIEW_SHIFT, 0, 0))
	else
		self._camera:SetFocus(nil)
	end
end

function MorphLabController:_showClassStats(classId: string)
	self._classStatsOpen = true
	self._focusToken += 1
	self._ui:ShowClassStats(classId)
	self:_restoreView()
end

function MorphLabController:_hideClassStats()
	if not self._classStatsOpen then
		return
	end
	self._classStatsOpen = false
	self._ui:HideClassStats()
	self._focusToken += 1
	self:_restoreView()
end

-- Shows the draft on the avatar; a new item combination yields while the
-- server builds it (the status line says so).
function MorphLabController:_refreshPreview()
	self:_refreshSummary()
	if not self._active or not self._scene then
		return
	end
	self._ui:SetAvatarStatus("CARGANDO ARTÍCULOS…", false)
	local ok, problem = self._preview:Show(self._scene, self._draft)
	if ok then
		self._ui:SetAvatarStatus("BORRADOR // LOCAL", false)
		self:_refreshPortrait()
	elseif problem ~= "SUPERSEDED" then
		warn("[REALITY 2059] Avatar preview failed: " .. tostring(problem))
		self._ui:SetAvatarStatus("ERROR AL CARGAR EL AVATAR // REINTENTA", true)
	end
end

-- The portrait copies the avatar once its cyberware is built (next frames).
function MorphLabController:_refreshPortrait()
	self._portraitToken += 1
	local token = self._portraitToken
	task.delay(0.25, function()
		if token == self._portraitToken and self._active then
			self._ui:SetPortrait(self._preview:GetModel())
		end
	end)
end

function MorphLabController:_refreshSummary()
	self._ui:SetSummary(self._draft)
end

-- Every selection in the UI from the draft.
function MorphLabController:_syncUI()
	local draft = self._draft
	self._ui:SetSelectedBodyBase(draft.appearance.bodyBaseId)
	self._ui:SetSelectedSkinTone(draft.appearance.skinToneId)
	self._ui:SetGender(if draft.appearance.bodyBaseId == "slim" then "f" else "m")
	self._ui:SetSelectedFace(draft.appearance.faceId)
	self._ui:SetSelectedHair(draft.appearance.hairId)
	self._ui:SetSelectedPieces(CharacterDraft.pieces(draft))
	self._ui:SetSelectedAccessories(draft.outfit.accessoryIds)
	self._ui:SetSelectedImplants(draft.cyberwareIds)
	self._ui:SetColorHint(draft.cyberwareIds[1] ~= "none")
	self._ui:SetSelectedClass(draft.classId)
	self._ui:SetSelectedColors(draft.colors)
	self:_applyClassColor()
	self:_refreshSummary()
end

function MorphLabController:_markEdited(categoryId: string)
	if self._suppressProgress or self._completed[categoryId] or not table.find(PROGRESS_CATEGORIES, categoryId) then
		return
	end
	self._completed[categoryId] = true
	self:_refreshProgress()
end

function MorphLabController:_refreshProgress()
	local completed = 0
	for _, categoryId in PROGRESS_CATEGORIES do
		local done = self._completed[categoryId] == true
		self._ui:SetCategoryCompleted(categoryId, done)
		completed += if done then 1 else 0
	end
	self._ui:SetProgress(completed, #PROGRESS_CATEGORIES)
end

-- Opens the next Activate on a saved character. Every section counts as
-- edited, so ENTRAR A LA REALIDAD is available right away.
function MorphLabController:LoadDraft(character)
	if self._active or type(character) ~= "table" then
		return
	end
	self._draft = CharacterDraft.clone(character)
	for _, categoryId in PROGRESS_CATEGORIES do
		self._completed[categoryId] = true
	end
end

-- The platform's energy rings take the class colour. The scene is shared, so
-- this is a local-only change; the original colours return on Deactivate.
local CLASS_TINTED_PARTS = table.freeze({ "OuterEnergyRing", "CoreEnergyRing" })

function MorphLabController:_applyClassColor()
	local platform = self._scene and self._scene:FindFirstChild("Platform")
	local info = CharacterCatalog.ClassInfo[self._draft.classId or ""]
	if not platform or not info then
		return
	end
	local saved = self._platformColors or {}
	self._platformColors = saved
	for _, name in CLASS_TINTED_PARTS do
		local ring = platform:FindFirstChild(name)
		if ring and ring:IsA("BasePart") then
			if not saved[ring] then
				saved[ring] = ring.Color
			end
			ring.Color = info.color
		end
	end
end

function MorphLabController:_restorePlatformColors()
	for ring, color in self._platformColors or {} do
		if ring.Parent then
			ring.Color = color
		end
	end
	self._platformColors = nil
end

-- The lobby's city dressing (lit walls, signs, the sky rift), cloned locally.
function MorphLabController:_attachSkyline(scene: Model)
	task.spawn(function()
		local runtime = root:WaitForChild("Runtime", 10)
		local template = runtime and runtime:WaitForChild(LobbyConfig.SkylineName, 10)
		if template and self._active and self._scene == scene and not self._skyline then
			local skyline = template:Clone() :: Model
			-- MORPHLAB has its own animated vortex in place of the lobby's rift.
			local portal = skyline:FindFirstChild("Portal")
			if portal then
				portal:Destroy()
			end
			skyline.Parent = scene
			self._skyline = skyline
		end
	end)
end

function MorphLabController:_detachSkyline()
	if self._skyline then
		self._skyline:Destroy()
		self._skyline = nil
	end
end

-- The lobby's violet haze over the city (client-only, restored on exit).
function MorphLabController:_applyAtmosphere()
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
		atmosphere.Name = "MorphLabAtmosphere"
		atmosphere.Parent = Lighting
		self._createdAtmosphere = atmosphere
	end
	for property, value in settings do
		(atmosphere :: any)[property] = value
	end
	self._atmosphere = atmosphere
end

function MorphLabController:_restoreAtmosphere()
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

function MorphLabController:Activate(reportProgress: ((string, number) -> ())?): (boolean, string?)
	if self._active then
		return true, nil
	end
	local report = reportProgress or function(_stage: string, _progress: number) end
	report("SINCRONIZANDO MORPHLAB", 0.42)
	local runtime = Workspace:WaitForChild(self._config.RuntimeFolderName, 10)
	local scene = runtime and runtime:WaitForChild(self._config.ModelName, 10)
	if not scene or not scene:IsA("Model") then
		warn("[REALITY 2059] MORPHLAB scene was not replicated in time")
		return false, "MORPHLAB_SCENE_UNAVAILABLE"
	end
	-- The city's meshes first, so the skyline is there when the menu shows.
	CityPreload.Run(function(progress: number)
		report(string.format("CARGANDO CIUDAD  %d%%", math.floor(progress * 100)), 0.44 + 0.12 * progress)
	end, 15)
	report("CALIBRANDO CÁMARA E ILUMINACIÓN", 0.58)
	if not self._camera:Enable(scene) then
		return false, "MORPHLAB_CAMERA_UNAVAILABLE"
	end
	self._scene = scene
	self._active = true
	self:_attachSkyline(scene)
	self:_applyAtmosphere()
	local view = self._camera:GetAnchorCFrame()
	if view then
		self._vortex:Attach(scene, view)
	end
	self._ui:Show()
	self._ui:SetAvatarStatus("PREPARANDO VISTA PREVIA", false)
	self:_hideChat()
	report("CARGANDO AVATAR", 0.72)
	self._preview:SetPoseCycle(posesFrom(self._config), self._config.Preview.IdleSeconds, self._config.Preview.HoldSeconds)
	local previewOk, previewError = self._preview:Show(scene, self._draft)
	if not previewOk then
		warn("[REALITY 2059] MORPHLAB preview failed: " .. tostring(previewError))
		self._ui:SetAvatarStatus("ERROR DE VISTA PREVIA // REINGRESA PARA REINTENTAR", true)
		self:Deactivate()
		return false, previewError
	end
	report("APLICANDO APARIENCIA", 0.91)
	self:_syncUI()
	self:_refreshProgress()
	self:_refreshPortrait()
	self._camera:SetFocus(nil)
	self._ui:SetAvatarStatus("AVATAR R15 // LOCAL", false)
	self._ui:SetControlsEnabled(true)
	report("FINALIZANDO MORPHLAB", 0.97)
	RunService.RenderStepped:Wait()
	RunService.RenderStepped:Wait()
	return true, nil
end

function MorphLabController:Deactivate()
	self:_restorePlatformColors()
	self._ui:Hide()
	self._ui:SetControlsEnabled(false)
	self._ui:SetPortrait(nil)
	self._preview:Destroy()
	self._vortex:Detach()
	self:_detachSkyline()
	self._camera:Disable()
	self:_restoreAtmosphere()
	self:_restoreChat()
	self._classStatsOpen = false
	self._ui:HideClassStats()
	self._scene = nil
	self._active = false
end

-- The chat window sits over the title and the left column; it is hidden
-- while MORPHLAB is open and restored on exit.
function MorphLabController:_hideChat()
	local ok, service = pcall(function()
		return game:GetService("TextChatService")
	end)
	if not ok or self._savedChat then
		return
	end
	local saved = {}
	for _, name in { "ChatWindowConfiguration", "ChatInputBarConfiguration" } do
		local configuration: any = service:FindFirstChild(name)
		if configuration then
			saved[configuration] = configuration.Enabled
			configuration.Enabled = false
		end
	end
	self._savedChat = saved
end

function MorphLabController:_restoreChat()
	for configuration: any, enabled in self._savedChat or {} do
		if configuration.Parent then
			configuration.Enabled = enabled
		end
	end
	self._savedChat = nil
end

function MorphLabController:Destroy()
	self:Deactivate()
	self._ui:Destroy()
end

function MorphLabController:IsActive(): boolean
	return self._active
end

return MorphLabController
