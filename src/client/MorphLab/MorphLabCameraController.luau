--!strict

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MorphLabCameraController = {}
MorphLabCameraController.__index = MorphLabCameraController

function MorphLabCameraController.new(config)
	return setmetatable({
		_config = config,
		_connection = nil,
		_saved = nil,
		_active = false,
		_baseCFrame = nil,
		_anchorCFrame = nil,
		_currentZoom = 0,
		_targetZoom = 0,
		_locked = false,
		_effects = nil,
		_savedLighting = nil,
	}, MorphLabCameraController)
end

-- withEffects = false skips this controller's bloom and grade (the hub
-- brings its own; stacking two blooms made skin highlights glare).
function MorphLabCameraController:Enable(scene: Model, withEffects: boolean?): boolean
	if self._active then
		return true
	end
	local cameras = scene:WaitForChild("Cameras", 10)
	local anchor = cameras and cameras:WaitForChild("CinematicCamera", 10)
	if not anchor or not anchor:IsA("BasePart") then
		warn("[REALITY 2059] MORPHLAB camera anchor was not replicated in time")
		return false
	end
	local deadline = os.clock() + 10
	local camera = Workspace.CurrentCamera
	while not camera and os.clock() < deadline do
		task.wait()
		camera = Workspace.CurrentCamera
	end
	if not camera then
		warn("[REALITY 2059] CurrentCamera was not available for MORPHLAB")
		return false
	end

	self._active = true
	self._saved = {
		cameraType = camera.CameraType,
		cameraSubject = camera.CameraSubject,
		cframe = camera.CFrame,
		fieldOfView = camera.FieldOfView,
	}
	camera.CameraType = Enum.CameraType.Scriptable
	-- Lighting edits made on the client only affect this player; the previous
	-- values are restored in Disable.
	local savedLighting = {}
	for property, value in self._config.SceneLighting do
		savedLighting[property] = (Lighting :: any)[property];
		(Lighting :: any)[property] = value
	end
	self._savedLighting = savedLighting
	-- Post effects parented to the camera are local to this client and only
	-- live while MORPHLAB is active.
	self._effects = {}
	if withEffects ~= false then
		local bloom = Instance.new("BloomEffect")
		bloom.Name = "MorphLabBloom"
		-- Threshold above 1: only neon blooms, never the avatar's skin.
		local settings = self._config.Bloom
		bloom.Intensity = settings.Intensity
		bloom.Size = settings.Size
		bloom.Threshold = settings.Threshold
		bloom.Parent = camera
		local grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "MorphLabGrade"
		grade.Brightness = 0
		grade.Contrast = 0.12
		grade.Saturation = 0.18
		grade.TintColor = Color3.fromRGB(246, 238, 255)
		grade.Parent = camera
		self._effects = { bloom, grade }
	end

	self._baseCFrame = anchor.CFrame
	self._anchorCFrame = anchor.CFrame
	self._currentZoom = 0
	self._targetZoom = 0
	local targetFov = self._config.Camera.FieldOfView
	self._connection = RunService.RenderStepped:Connect(function(deltaTime)
		if not self._active or Workspace.CurrentCamera ~= camera then
			return
		end
		local alpha = 1 - math.exp(-self._config.Camera.BlendSpeed * deltaTime)
		self._currentZoom += (self._targetZoom - self._currentZoom) * alpha
		local targetCFrame = self._baseCFrame * CFrame.new(0, 0, self._currentZoom)
		camera.CFrame = camera.CFrame:Lerp(targetCFrame, alpha)
		camera.FieldOfView += (targetFov - camera.FieldOfView) * alpha
	end)
	return true
end

function MorphLabCameraController:Disable()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self._active then
		local camera = Workspace.CurrentCamera
		local saved = self._saved
		if camera and saved then
			camera.CameraType = saved.cameraType
			camera.CameraSubject = saved.cameraSubject
			camera.CFrame = saved.cframe
			camera.FieldOfView = saved.fieldOfView
		end
	end
	for _, effect in self._effects or {} do
		effect:Destroy()
	end
	self._effects = nil
	for property, value in self._savedLighting or {} do
		(Lighting :: any)[property] = value
	end
	self._savedLighting = nil
	self._saved = nil
	self._baseCFrame = nil
	self._anchorCFrame = nil
	self._currentZoom = 0
	self._targetZoom = 0
	self._locked = false
	self._active = false
end

function MorphLabCameraController:Zoom(delta: number)
	if self._active and not self._locked then
		-- A close-up must not zoom through the face.
		local focused = self._baseCFrame ~= self._anchorCFrame
		local minimum = if focused then self._config.Camera.FaceMinZoom else self._config.Camera.MinZoom
		local maximum = if focused then self._config.Camera.FaceMaxZoom else self._config.Camera.MaxZoom
		self._targetZoom = math.clamp(self._targetZoom + delta, minimum, maximum)
	end
end

-- Blends the camera to a different framing (e.g. a face close-up); nil
-- returns to the cinematic anchor. Zoom is reset either way.
function MorphLabCameraController:SetFocus(focus: CFrame?)
	if not self._active then
		return
	end
	self._baseCFrame = focus or self._anchorCFrame
	self._targetZoom = 0
end

function MorphLabCameraController:GetAnchorCFrame(): CFrame?
	return self._anchorCFrame
end

function MorphLabCameraController:ResetView()
	self._targetZoom = 0
end

function MorphLabCameraController:SetInteractionLocked(locked: boolean)
	self._locked = locked
end

function MorphLabCameraController:IsActive(): boolean
	return self._active
end

return MorphLabCameraController
