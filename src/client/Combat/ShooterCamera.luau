--!strict

-- Third-person shooter camera: the mouse is locked to the screen centre and
-- turns the camera directly (no right click), the character turns to face
-- where the camera looks, and a crosshair marks the aim. Hold LEFT ALT to
-- free the cursor (menus, chat). Works on top of the default camera and the
-- free roam shoulder rig, which keeps the camera behind the shoulder.

local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local ShooterCamera = {}
ShooterCamera.__index = ShooterCamera

local STEP_NAME = "Reality2059ShooterCamera"
local AIM_ACTION = "Reality2059Aim"
local FREE_CURSOR_KEY = Enum.KeyCode.LeftAlt
-- Aiming down sights (hold right click): a tighter field of view.
local FIELD_OF_VIEW = 70
local AIM_FIELD_OF_VIEW = 48
local ZOOM_SPEED = 14
local CROSSHAIR_COLOR = Color3.fromRGB(235, 240, 255)

local function bar(parent: Instance, size: UDim2, position: UDim2)
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = CROSSHAIR_COLOR
	frame.BorderSizePixel = 0
	local outline = Instance.new("UIStroke")
	outline.Color = Color3.new(0, 0, 0)
	outline.Transparency = 0.5
	outline.Parent = frame
	frame.Parent = parent
end

function ShooterCamera.new(playerGui: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "Crosshair"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 80
	screen.Enabled = false
	screen.Parent = playerGui
	-- Four ticks around a small gap, plus a centre dot.
	local center = UDim2.fromScale(0.5, 0.5)
	for _, offset in { Vector2.new(0, -9), Vector2.new(0, 9), Vector2.new(-9, 0), Vector2.new(9, 0) } do
		local vertical = offset.X == 0
		bar(screen, if vertical then UDim2.fromOffset(2, 7) else UDim2.fromOffset(7, 2), center + UDim2.fromOffset(offset.X, offset.Y))
	end
	bar(screen, UDim2.fromOffset(2, 2), center)
	return setmetatable({
		_screen = screen,
		_enabled = false,
		_aiming = false,
		_savedRotation = nil :: Enum.RotationType?,
		_savedFieldOfView = nil :: number?,
	}, ShooterCamera)
end

function ShooterCamera:IsAiming(): boolean
	return self._enabled and self._aiming
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
		local current = Workspace.CurrentCamera
		if current then
			local target = if self._aiming then AIM_FIELD_OF_VIEW else FIELD_OF_VIEW
			current.FieldOfView += (target - current.FieldOfView) * (1 - math.exp(-ZOOM_SPEED * deltaTime))
		end
	end)
end

function ShooterCamera:Disable()
	if not self._enabled then
		return
	end
	self._enabled = false
	self._aiming = false
	pcall(RunService.UnbindFromRenderStep, RunService, STEP_NAME)
	ContextActionService:UnbindAction(AIM_ACTION)
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
