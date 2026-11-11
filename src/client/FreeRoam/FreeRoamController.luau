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
		-- Camera side: -1 = left of the character (character on the right of the
		-- screen, the default), 1 = right. The blend eases between them.
		_shoulderSide = -1,
		_shoulderBlend = -1,
		_onExit = nil,
		_connections = {},
		_clockConnection = nil,
	}, FreeRoamController)
	local function isAiming(): boolean
		return self._shooterCamera:IsAiming()
	end
	self._animation = ShooterAnimation.new(isAiming)
	self._movement = MovementController.new(playerGui, self._animation, isAiming)
	self._combat = CombatController.new(playerGui, self._animation, isAiming, function()
		self._movement:StopSprint()
	end)
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
-- 1. shift the orbit pivot sideways in camera space (character on the left of
--    the screen by default; Q swaps sides, eased);
-- 2. collide both the shoulder shift and the orbit arm against
--    City2059/Colisiones, because Roblox's own occlusion only stops at
--    visible solid parts and the city's colliders are invisible.
local CAMERA_RIG = "Reality2059CameraRig"
local SHOULDER_ACTION = "Reality2059Shoulder"
local OCCLUSION_MARGIN = 0.6

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
	self._shoulderBlend = self._shoulderSide
	RunService:BindToRenderStep(CAMERA_RIG, Enum.RenderPriority.Camera.Value + 1, function(deltaTime: number)
		if self._firstPerson then
			return
		end
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local alpha = 1 - math.exp(-settings.ShoulderSwapSpeed * deltaTime)
		self._shoulderBlend += (self._shoulderSide - self._shoulderBlend) * alpha
		local cameraFrame = camera.CFrame
		local focus = camera.Focus.Position
		local arm = cameraFrame.Position - focus
		local shift = cameraFrame.RightVector * (settings.ShoulderOffset.X * self._shoulderBlend)
			+ Vector3.yAxis * settings.ShoulderOffset.Y
		local pivot = focus + clampRay(focus, shift, params)
		local position = pivot + clampRay(pivot, arm, params)
		camera.CFrame = cameraFrame.Rotation + position
	end)
	ContextActionService:BindAction(SHOULDER_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self._shoulderSide = -self._shoulderSide
		end
		return Enum.ContextActionResult.Sink
	end, false, table.unpack(settings.ShoulderKeys))
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
function FreeRoamController:Activate(character, options: { shooter: boolean?, map: string? }?): (boolean, string?)
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
		self._shooterCamera:Enable()
		self._weapons:Enable()
		self._animation:Enable()
		self._movement:Enable()
		self._combat:Enable()
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
	ContextActionService:UnbindAction(SHOULDER_ACTION)
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
