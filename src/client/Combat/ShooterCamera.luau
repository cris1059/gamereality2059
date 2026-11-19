--!strict

-- Third-person shooter camera: the mouse is locked to the screen centre and
-- turns the camera directly (no right click), the character turns to face
-- where the camera looks, and a crosshair marks the aim. Hold LEFT ALT to
-- free the cursor (menus, chat). Works on top of the default camera and the
-- free roam shoulder rig, which keeps the camera behind the shoulder.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WeaponStats = require(ReplicatedStorage:WaitForChild("CyberpunkOnline").Combat.WeaponStats)
local FirstPersonArms = require(script.Parent.FirstPersonArms)
local CombatHUD = require(script.Parent.Parent.HUD.CombatHUD)

local ShooterCamera = {}
ShooterCamera.__index = ShooterCamera

local STEP_NAME = "Reality2059ShooterCamera"
local AIM_ACTION = "Reality2059Aim"
local FREE_CURSOR_KEY = Enum.KeyCode.LeftAlt
-- Aiming down sights (hold right click): a tighter field of view, reached
-- over the held weapon's aimSeconds (WeaponStats) together with the pose and
-- the accuracy (GetAimProgress); leaving the sights takes AIM_OUT_SHARE of it.
local FIELD_OF_VIEW = 70
local AIM_FIELD_OF_VIEW = 48
local AIM_OUT_SHARE = 0.7
-- Only smooths the switch between the first- and third-person widths.
local ZOOM_SPEED = 20
-- First person: the camera is this close to the head (FreeRoamConfig's
-- FirstPersonDistance is 0.5).
local FIRST_PERSON_RANGE = 1.5
-- A wider view in first person keeps the hands and weapon from filling the
-- screen (aiming still narrows to AIM_FIELD_OF_VIEW).
local FIRST_PERSON_FIELD_OF_VIEW = 80
-- A slide widens the view this many degrees (less on the sights).
local SLIDE_FIELD_OF_VIEW = 9

local function heldWeapon(): Tool?
	local character = Players.LocalPlayer.Character
	if not character then
		return nil
	end
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("LoadoutSlot") then
			return child
		end
	end
	return nil
end

-- Eased 0..1 (slow in, slow out) for the sights.
local function ease(t: number): number
	return t * t * (3 - 2 * t)
end

local function isFirstPerson(camera: Camera): boolean
	local character = Players.LocalPlayer.Character
	local head = character and character:FindFirstChild("Head")
	return head ~= nil and head:IsA("BasePart") and (camera.CFrame.Position - head.Position).Magnitude <= FIRST_PERSON_RANGE
end

-- In first person the whole character is hidden here every frame
-- (LocalTransparencyModifier = 1): body, hair, catalog clothing (layered
-- clothing and accessories) and cyberware, which Roblox's own first-person
-- fade does not always cover (the jacket showed under the view in a crouch,
-- when the upper body leans forward under the camera). The weapon in hand
-- stays visible, and slim stand-in forearms and hands are drawn
-- (FirstPersonArms) in place of the avatar's blocky arms. Leaving first
-- person, what was hidden here is shown again.
local hiddenHere: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function restoreHidden()
	for item in hiddenHere do
		if item.Parent then
			(item :: any).LocalTransparencyModifier = 0
		end
	end
	table.clear(hiddenHere)
end

local function showArmsInFirstPerson(camera: Camera)
	local character = Players.LocalPlayer.Character
	local firstPerson = character ~= nil and isFirstPerson(camera)
	FirstPersonArms.update(camera, character, firstPerson)
	if not character or not firstPerson then
		if next(hiddenHere) then
			restoreHidden()
		end
		return
	end
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Decal") then
			if descendant:FindFirstAncestorWhichIsA("Tool") then
				(descendant :: any).LocalTransparencyModifier = 0
			else
				(descendant :: any).LocalTransparencyModifier = 1
				hiddenHere[descendant] = true
			end
		end
	end
end

function ShooterCamera.new(playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "Crosshair"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 80
	screen.Enabled = false
	screen.Parent = playerGui
	-- The crosshair itself is drawn by the HUD (HUD/Crosshair); this camera
	-- tells it when to show (not while the cursor is free) and when aiming.
	return setmetatable({
		_screen = screen,
		_hud = CombatHUD.get(),
		_enabled = false,
		_aiming = false,
		_aimProgress = 0, -- 0 = hip, 1 = fully on the sights
		_baseFov = FIELD_OF_VIEW,
		_savedRotation = nil :: Enum.RotationType?,
		_savedFieldOfView = nil :: number?,
		_slideSource = nil :: (() -> number)?,
	}, ShooterCamera)
end

-- How far into a slide the local character is (0..1), for the view.
function ShooterCamera:SetSlideSource(source: () -> number)
	self._slideSource = source
end

function ShooterCamera:IsAiming(): boolean
	return self._enabled and self._aiming
end

-- How far into the sights (0..1, eased): zoom, pose and accuracy follow it.
function ShooterCamera:GetAimProgress(): number
	return if self._enabled then ease(self._aimProgress) else 0
end

local function gameSettings(): any?
	local ok, settings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	return if ok then settings else nil
end

function ShooterCamera:Enable()
	if self._enabled then
		return
	end
	self._enabled = true
	-- Camera-relative rotation: the avatar faces where the camera looks.
	local settings = gameSettings()
	if settings then
		self._savedRotation = settings.RotationType
		pcall(function()
			settings.RotationType = Enum.RotationType.CameraRelative
		end)
	end
	self._screen.Enabled = true
	local camera = Workspace.CurrentCamera
	self._savedFieldOfView = if camera then camera.FieldOfView else nil
	self._baseFov = FIELD_OF_VIEW
	ContextActionService:BindAction(AIM_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self._aiming = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self._aiming = false
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonL2)
	-- After the camera scripts, which reset the mouse behaviour every frame.
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 2, function(deltaTime: number)
		local freeCursor = UserInputService:IsKeyDown(FREE_CURSOR_KEY)
		UserInputService.MouseBehavior = if freeCursor then Enum.MouseBehavior.Default else Enum.MouseBehavior.LockCenter
		UserInputService.MouseIconEnabled = freeCursor
		self._screen.Enabled = not freeCursor
		self._hud:SetCrosshairVisible(not freeCursor)
		self._hud:SetAiming(self._aiming)
		-- Into the sights over the weapon's aim time, out a little faster.
		local weapon = heldWeapon()
		local aimSeconds = math.max(if weapon then WeaponStats.AimSeconds(weapon) else 0.25, 0.01)
		if self._aiming and weapon then
			self._aimProgress = math.min(self._aimProgress + deltaTime / aimSeconds, 1)
		else
			self._aimProgress = math.max(self._aimProgress - deltaTime / (aimSeconds * AIM_OUT_SHARE), 0)
		end
		local current = Workspace.CurrentCamera
		if current then
			-- The hip width eases between views; the sights follow the
			-- progress exactly, so the zoom takes the weapon's aim time.
			local base = if isFirstPerson(current) then FIRST_PERSON_FIELD_OF_VIEW else FIELD_OF_VIEW
			self._baseFov += (base - self._baseFov) * (1 - math.exp(-ZOOM_SPEED * deltaTime))
			local slide = if self._slideSource then self._slideSource() else 0
			local aimed = ease(self._aimProgress)
			current.FieldOfView = self._baseFov + (AIM_FIELD_OF_VIEW - self._baseFov) * aimed
				+ SLIDE_FIELD_OF_VIEW * ease(math.clamp(slide, 0, 1)) * (1 - 0.7 * aimed)
			showArmsInFirstPerson(current)
		end
	end)
end

function ShooterCamera:Disable()
	if not self._enabled then
		return
	end
	self._enabled = false
	self._aiming = false
	self._aimProgress = 0
	pcall(RunService.UnbindFromRenderStep, RunService, STEP_NAME)
	ContextActionService:UnbindAction(AIM_ACTION)
	FirstPersonArms.clear()
	restoreHidden()
	local camera = Workspace.CurrentCamera
	if camera and self._savedFieldOfView then
		camera.FieldOfView = self._savedFieldOfView
	end
	self._savedFieldOfView = nil
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	self._screen.Enabled = false
	local settings = gameSettings()
	if settings and self._savedRotation then
		pcall(function()
			settings.RotationType = self._savedRotation
		end)
	end
	self._savedRotation = nil
end

function ShooterCamera:Destroy()
	self:Disable()
	self._screen:Destroy()
end

return ShooterCamera
