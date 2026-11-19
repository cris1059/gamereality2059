--!strict

-- MODO LIBRE on the client: asks the server to spawn the player's R15 avatar
-- in City2059, follows it with the default camera, runs the day/night cycle
-- (FreeRoamLighting) and the HUD. SHIFT (or the CORRER button) switches
-- between walking and running.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local FreeRoamConfig = require(root.Config.FreeRoamConfig)
local LeanConfig = require(root.Config.LeanConfig)
local LeanPose = require(root.Combat.LeanPose)
local RemoteNames = require(root.Network.RemoteNames)
local FreeRoamLighting = require(script.Parent.FreeRoamLighting)
local FreeRoamHUD = require(script.Parent.FreeRoamHUD)
local InventoryController = require(script.Parent.Parent.Inventory.InventoryController)
local CityLife = require(script.Parent.CityLife)
local GraphicsSettings = require(script.Parent.Parent.Settings.GraphicsSettings)
local ShooterCamera = require(script.Parent.Parent.Combat.ShooterCamera)
local WeaponController = require(script.Parent.Parent.Combat.WeaponController)
local MapLighting = require(script.Parent.Parent.Combat.MapLighting)
local ShooterAnimation = require(script.Parent.Parent.Combat.ShooterAnimation)
local MovementController = require(script.Parent.Parent.Combat.MovementController)
local CombatController = require(script.Parent.Parent.Combat.CombatController)
local CombatHUD = require(script.Parent.Parent.HUD.CombatHUD)

local FreeRoamController = {}
FreeRoamController.__index = FreeRoamController

local SPRINT_ACTION = "Reality2059Sprint"
local CAMERA_ACTION = "Reality2059CameraMode"

function FreeRoamController.new(playerGui: PlayerGui, morphLabConfig)
	local runtime = root:WaitForChild("Runtime")
	local self = setmetatable({
		_runtime = runtime,
		_lighting = FreeRoamLighting.new(FreeRoamConfig, runtime),
		_hud = FreeRoamHUD.new(playerGui, morphLabConfig),
		_inventory = InventoryController.new(playerGui, morphLabConfig),
		_cityLife = CityLife.new(morphLabConfig),
		_shooterCamera = ShooterCamera.new(playerGui),
		_weapons = WeaponController.new(playerGui),
		_mapLighting = MapLighting.new(),
		_animation = nil :: any,
		_movement = nil :: any,
		_combat = nil :: any,
		-- Shooter mode (map tests, later matches): no city HUD, clock,
		-- inventory or city life; the camera follows the mouse.
		_shooter = false,
		_active = false,
		_sprinting = false,
		_firstPerson = false,
		_onExit = nil,
		_connections = {},
		_clockConnection = nil,
	}, FreeRoamController)
	local function isAiming(): boolean
		return self._shooterCamera:IsAiming()
	end
	-- 0..1 into the sights over the weapon's aim time (pose and accuracy).
	local function aimProgress(): number
		return self._shooterCamera:GetAimProgress()
	end
	self._animation = ShooterAnimation.new(isAiming, aimProgress)
	self._movement = MovementController.new(playerGui, self._animation, isAiming)
	-- The camera widens a little in a slide.
	self._shooterCamera:SetSlideSource(function(): number
		local amount = self._animation:GetSlide()
		return amount
	end)
	self._combat = CombatController.new(playerGui, self._animation, isAiming, function()
		self._movement:StopSprint()
	end, aimProgress)
	self._hud:Bind({
		exit = function()
			if self._onExit then
				self._onExit()
			end
		end,
		toggleSprint = function()
			self:_setSprint(not self._sprinting)
		end,
	})
	return self
end

function FreeRoamController:SetExitHandler(handler: () -> ())
	self._onExit = handler
end

function FreeRoamController:_humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

function FreeRoamController:_setSprint(sprinting: boolean)
	self._sprinting = sprinting
	local humanoid = self:_humanoid()
	if humanoid then
		humanoid.WalkSpeed = if sprinting then FreeRoamConfig.Movement.RunSpeed else FreeRoamConfig.Movement.WalkSpeed
	end
	self._hud:SetSprinting(sprinting)
end

-- Locks the zoom to the current mode (Roblox fades the avatar itself when
-- the camera reaches first person).
function FreeRoamController:_applyCameraMode()
	local settings = FreeRoamConfig.Camera
	local distance = if self._firstPerson then settings.FirstPersonDistance else settings.ThirdPersonDistance
	local player = Players.LocalPlayer
	-- Max first so Min never exceeds it while switching.
	player.CameraMaxZoomDistance = math.max(distance, player.CameraMinZoomDistance)
	player.CameraMinZoomDistance = distance
	player.CameraMaxZoomDistance = distance
end

-- Over-the-shoulder rig, run right after the default camera each frame:
-- 1. shift the orbit pivot sideways in camera space, over the right shoulder
--    (character on the left of the screen), plus the lean (shooter mode,
--    Q / E, LeanConfig) with a slight roll;
-- 2. collide both the shoulder shift and the orbit arm against
--    City2059/Colisiones, because Roblox's own occlusion only stops at
--    visible solid parts and the city's colliders are invisible.
-- In first person a lean shifts and rolls the view the same way (no orbit).
local CAMERA_RIG = "Reality2059CameraRig"
local LEAN_LEFT_ACTION = "Reality2059LeanLeft"
local LEAN_RIGHT_ACTION = "Reality2059LeanRight"
local OCCLUSION_MARGIN = 0.6

-- Shooter mode: the body turns with the view at once. Roblox turns the
-- character towards the camera at a limited rate, so on fast turns the body,
-- and with it the weapon and hands, trailed the view (in first person they
-- swung off the screen). Done right after the camera moves each frame, before
-- the pose and physics, so the weapon is drawn where the view is.
local function faceDirection(direction: Vector3)
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 or humanoid.Sit then
		return
	end
	-- Studio checks only: lets a test camera orbit the character.
	if Workspace:GetAttribute("R2059FreeFacing") == true then
		return
	end
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 1e-3 then
		return
	end
	local position = root.Position
	root.CFrame = CFrame.lookAt(position, position + flat.Unit)
end

local function clampRay(origin: Vector3, offset: Vector3, params: RaycastParams?): Vector3
	if not params or offset.Magnitude < 1e-3 then
		return offset
	end
	local hit = Workspace:Raycast(origin, offset, params)
	if not hit then
		return offset
	end
	return offset.Unit * math.max(hit.Distance - OCCLUSION_MARGIN, 0)
end

function FreeRoamController:_bindCameraRig()
	local settings = FreeRoamConfig.Camera
	local city = Workspace:FindFirstChild(FreeRoamConfig.CityModelName, true)
	local colliders = city and city:FindFirstChild(FreeRoamConfig.CollisionFolderName)
	local params: RaycastParams? = nil
	if colliders then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { colliders }
	else
		warn("[REALITY 2059] Camera collision off: City2059/Colisiones not found")
	end
	RunService:BindToRenderStep(CAMERA_RIG, Enum.RenderPriority.Camera.Value + 1, function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local lean = if self._shooter then self._animation:GetLean() else 0
		-- Sliding, the view leans into a turn a little (about the view axis).
		local slideRoll = 0
		if self._shooter then
			local _, roll = self._animation:GetSlide()
			slideRoll = roll
		end
		local cameraFrame = camera.CFrame
		if self._firstPerson then
			-- The eye moves with the upper body about the waist (LeanPose), as
			-- the head does, and rolls by the same angle, so the weapon and
			-- hands keep their place on screen. The roll is about the view
			-- axis: the default camera starts each frame from this one, and
			-- any change to where it looks would build up. The focus moves by
			-- the same amount: Roblox turns the character along focus - camera,
			-- and with the camera only half a stud from it a lone sideways
			-- shift spun the body. The move never goes through a wall.
			local character = Players.LocalPlayer.Character
			local lowerTorso = character and character:FindFirstChild("LowerTorso")
			if math.abs(lean) > 1e-3 and lowerTorso and lowerTorso:IsA("BasePart") then
				local leaned = LeanPose.upperBodyTransform(lowerTorso.CFrame, lowerTorso.Size, lean) * cameraFrame.Position
				local offset = clampRay(cameraFrame.Position, leaned - cameraFrame.Position, params)
				camera.CFrame = (cameraFrame.Rotation + (cameraFrame.Position + offset)) * CFrame.Angles(0, 0, LeanPose.roll(lean) + slideRoll)
				camera.Focus = camera.Focus + offset
			elseif math.abs(slideRoll) > 1e-4 then
				camera.CFrame = cameraFrame * CFrame.Angles(0, 0, slideRoll)
			end
			if self._shooter then
				faceDirection(camera.CFrame.LookVector)
			end
			return
		end
		local focus = camera.Focus.Position
		local arm = cameraFrame.Position - focus
		local shift = cameraFrame.RightVector * (settings.ShoulderOffset.X + LeanConfig.ThirdPersonShift * lean)
			+ Vector3.yAxis * settings.ShoulderOffset.Y
		local pivot = focus + clampRay(focus, shift, params)
		local position = pivot + clampRay(pivot, arm, params)
		camera.CFrame = (cameraFrame.Rotation + position) * CFrame.Angles(0, 0, -lean * math.rad(LeanConfig.ThirdPersonRoll) + slideRoll)
		-- Roblox turns the character along focus - camera: moving the focus
		-- with the shoulder shift keeps the body facing the crosshair (it was
		-- turned ~16 degrees off it, more while leaning).
		camera.Focus = CFrame.new(pivot)
		if self._shooter then
			faceDirection(pivot - camera.CFrame.Position)
		end
	end)
	if self._shooter then
		for _, entry in { { LEAN_LEFT_ACTION, -1, LeanConfig.LeftKeys }, { LEAN_RIGHT_ACTION, 1, LeanConfig.RightKeys } } do
			local side = entry[2] :: number
			ContextActionService:BindAction(entry[1] :: string, function(_, state)
				if state == Enum.UserInputState.Begin then
					self._animation:ToggleLean(side)
				end
				return Enum.ContextActionResult.Sink
			end, false, table.unpack(entry[3] :: { Enum.KeyCode }))
		end
	end
end

-- Default custom camera on the avatar's humanoid.
function FreeRoamController:_attachCamera(character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	local camera = Workspace.CurrentCamera
	if camera and humanoid then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = humanoid
	end
	self:_applyCameraMode()
	self:_setSprint(self._sprinting)
end

-- character: the validated draft from MORPHLAB / the profile.
-- options.shooter: shooter mode (see _shooter); options.map: the map being
-- played (MapsConfig: its day / night lighting replaces the city's cycle).
function FreeRoamController:Activate(character, options: { shooter: boolean?, map: string?, training: boolean? }?): (boolean, string?)
	if self._active then
		return true, nil
	end
	local shooter = options ~= nil and options.shooter == true
	local remotes = self._runtime:WaitForChild(RemoteNames.Folder)
	local enter = remotes:WaitForChild(RemoteNames.EnterFreeRoam, 10) :: RemoteFunction?
	if not enter then
		return false, "FREE_ROAM_UNAVAILABLE"
	end
	local ok, result = pcall(function()
		return enter:InvokeServer(character)
	end)
	if not ok or type(result) ~= "table" or not result.ok then
		return false, if ok and type(result) == "table" then tostring(result.errorCode) else "FREE_ROAM_REQUEST_FAILED"
	end
	local player = Players.LocalPlayer
	local spawned = player.Character or player.CharacterAdded:Wait()
	self._active = true
	self._shooter = shooter
	self._sprinting = false
	local quality = GraphicsSettings.Get()
	local mapName = options and options.map
	if mapName then
		self._mapLighting:Apply(mapName)
	else
		self._lighting:SetQuality(quality)
		self._lighting:Start()
	end
	if not shooter then
		self._cityLife:Start(quality.cityLife)
	end
	-- CONFIGURACIÓN can change the profile while roaming.
	table.insert(self._connections, GraphicsSettings.Changed:Connect(function(profile)
		if not mapName then
			self._lighting:SetQuality(profile)
		end
		if not self._shooter then
			self._cityLife:Stop()
			self._cityLife:Start(profile.cityLife)
		end
	end))
	self:_attachCamera(spawned)
	table.insert(self._connections, player.CharacterAdded:Connect(function(newCharacter)
		-- Respawn after a fall: same camera and speed.
		self:_attachCamera(newCharacter)
	end))
	-- Shooter mode has its own sprint (with stamina) in MovementController.
	if not shooter then
		ContextActionService:BindAction(SPRINT_ACTION, function(_, state)
			if state == Enum.UserInputState.Begin then
				self:_setSprint(true)
			elseif state == Enum.UserInputState.End then
				self:_setSprint(false)
			end
			-- Sink: SHIFT would otherwise also toggle shift-lock.
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	end
	self:_bindCameraRig()
	ContextActionService:BindAction(CAMERA_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self._firstPerson = not self._firstPerson
			self:_applyCameraMode()
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(FreeRoamConfig.Camera.ToggleKeys))
	if shooter then
		-- The combat HUD (health, weapon, crosshair, match strip) first, so the
		-- controllers below feed a live HUD.
		local combatHud = CombatHUD.get()
		combatHud:SetProfile(character)
		combatHud:Enable({ training = options ~= nil and options.training == true })
		self._shooterCamera:Enable()
		self._weapons:Enable()
		self._animation:Enable()
		self._movement:Enable()
		self._combat:Enable()
		if options and options.training then
			-- MODO ENTRENAMIENTO: only the MENÚ button of this HUD (the title is
			-- in the combat HUD's top strip).
			self._hud:SetTraining(true)
			self._hud:Show()
		end
	else
		self._clockConnection = RunService.Heartbeat:Connect(function()
			local hour = self._lighting:GetClockTime()
			self._hud:SetClock(hour, self._lighting:IsNight(hour))
		end)
		self._hud:Show()
		self._inventory:Enable()
	end
	return true, nil
end

function FreeRoamController:Deactivate()
	if not self._active then
		return
	end
	self._active = false
	ContextActionService:UnbindAction(SPRINT_ACTION)
	ContextActionService:UnbindAction(CAMERA_ACTION)
	pcall(RunService.UnbindFromRenderStep, RunService, CAMERA_RIG)
	ContextActionService:UnbindAction(LEAN_LEFT_ACTION)
	ContextActionService:UnbindAction(LEAN_RIGHT_ACTION)
	self._firstPerson = false
	Players.LocalPlayer.CameraMaxZoomDistance = FreeRoamConfig.Camera.DefaultMaxZoom
	Players.LocalPlayer.CameraMinZoomDistance = FreeRoamConfig.Camera.DefaultMinZoom
	for _, connection in self._connections do
		connection:Disconnect()
	end
	self._connections = {}
	if self._clockConnection then
		self._clockConnection:Disconnect()
		self._clockConnection = nil
	end
	self._hud:Hide()
	self._hud:SetTraining(false)
	CombatHUD.get():Disable()
	self._inventory:Disable()
	self._shooterCamera:Disable()
	self._weapons:Disable()
	self._combat:Disable()
	self._movement:Disable()
	self._animation:Disable()
	self._shooter = false
	self._lighting:Stop()
	self._mapLighting:Restore()
	self._cityLife:Stop()
	local remotes = self._runtime:FindFirstChild(RemoteNames.Folder)
	local leave = remotes and remotes:FindFirstChild(RemoteNames.LeaveFreeRoam)
	if leave and leave:IsA("RemoteFunction") then
		pcall(function()
			leave:InvokeServer()
		end)
	end
end

function FreeRoamController:IsActive(): boolean
	return self._active
end

function FreeRoamController:Destroy()
	self:Deactivate()
	self._hud:Destroy()
	self._inventory:Destroy()
	self._shooterCamera:Destroy()
	self._weapons:Destroy()
	self._combat:Destroy()
	self._movement:Destroy()
end

return FreeRoamController
