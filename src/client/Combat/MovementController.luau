--!strict

-- Shooter movement for the local player (ideas from sysscan/Roblox-FPS-Movement,
-- rewritten): SHIFT sprints while there is stamina (it drains while
-- sprinting and refills after a short pause); C / CTRL crouches; crouching
-- while sprinting slides the way you are running, fast at first and slowing
-- down on a progress^curve to crouch speed. Mid-slide the movement keys steer
-- it (up to SLIDE.turnRate, less as it slows; a sharp carve costs speed),
-- the opposite key brakes, C / CTRL again ends it in a crouch,
-- and it ends early against a wall or off a ledge. The hips go down and up
-- smoothly (HipHeight eases to its target). Walk speed follows
-- a priority: slide > crouch > aiming > sprint > walk. Firing or aiming stops
-- the sprint. The stance is posed by ShooterAnimation (and shared with others
-- through it).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local MovementController = {}
MovementController.__index = MovementController

local SPRINT_ACTION = "Reality2059ShooterSprint"
local CROUCH_ACTION = "Reality2059Crouch"

local SPEEDS = table.freeze({ walk = 16, sprint = 24, crouch = 9, aim = 11, slide = 36 })
local STAMINA = table.freeze({ max = 100, drain = 22, regen = 30, regenDelay = 0.9, minToSprint = 15 })
local SLIDE = table.freeze({
	seconds = 0.95,
	cooldown = 1.0,
	curve = 2.4,
	minSpeed = 14,
	turnRate = 150, -- degrees a second of steering at full speed
	minTurnShare = 0.45, -- share of turnRate still there at the slowest
	carveLoss = 0.14, -- speed share lost per 90 degrees turned
	brakeLoss = 1.6, -- speed share lost a second while braking (opposite key)
	blockedShare = 0.35, -- moving slower than this share of the slide speed: blocked, ends
	airGrace = 0.2, -- seconds off the ground before the slide ends
	drop = 1.38, -- hip height lowered in a slide
})
-- Mid-slide the humanoid is told to move along the slide (each step, after
-- the controls), so it does not pull towards the keys; the keys are read
-- directly for steering (_inputDirection).
local CROUCH_DROP = 0.55
local HEIGHT_EASE = 16 -- how fast the hips go down / up

function MovementController.new(playerGui: PlayerGui, animation: any, isAiming: () -> boolean)
	-- Stamina bar (bottom centre), shown only while not full.
	local screen = Instance.new("ScreenGui")
	screen.Name = "StaminaHUD"
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 80
	screen.Enabled = false
	screen.Parent = playerGui
	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 1)
	track.Position = UDim2.new(0.5, 0, 1, -36)
	track.Size = UDim2.fromOffset(220, 6)
	track.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
	track.BackgroundTransparency = 0.3
	track.BorderSizePixel = 0
	track.Parent = screen
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(0, 220, 255)
	fill.BorderSizePixel = 0
	fill.Parent = track
	for _, frame in { track, fill } do
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = frame
	end
	return setmetatable({
		_screen = screen,
		_track = track,
		_fill = fill,
		_animation = animation,
		_isAiming = isAiming,
		_enabled = false,
		_sprintHeld = false,
		_crouching = false,
		_sliding = false,
		_slideStart = 0,
		_slideDirection = Vector3.zero,
		_slideLoss = 0, -- speed share lost to carving / braking this slide
		_slideAir = 0, -- seconds off the ground this slide
		_slideSpeed = 0, -- speed asked for last step (to notice a wall)
		_heightEasing = false, -- hips still on their way back up
		_lastSlide = -10,
		_stamina = STAMINA.max,
		_lastSprint = 0,
		_baseHipHeight = nil :: number?,
		_humanoid = nil :: Humanoid?,
		_connection = nil :: RBXScriptConnection?,
		_driveConnection = nil :: RBXScriptConnection?,
	}, MovementController)
end

function MovementController:_character(): (Humanoid?, BasePart?)
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid ~= self._humanoid then
		-- New character (respawn): its own hip height, standing.
		self._humanoid = humanoid
		self._baseHipHeight = if humanoid then humanoid.HipHeight else nil
		self._crouching = false
		self._sliding = false
		self._heightEasing = false
	end
	return humanoid, if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

-- Where the movement keys point (world, flat, unit) or zero: read from the
-- keys / left stick themselves, since a slide overrides the humanoid's own
-- movement (and with it MoveDirection).
local KEYS = table.freeze({
	{ Enum.KeyCode.W, 0, -1 }, { Enum.KeyCode.Up, 0, -1 },
	{ Enum.KeyCode.S, 0, 1 }, { Enum.KeyCode.Down, 0, 1 },
	{ Enum.KeyCode.A, -1, 0 }, { Enum.KeyCode.Left, -1, 0 },
	{ Enum.KeyCode.D, 1, 0 }, { Enum.KeyCode.Right, 1, 0 },
})
function MovementController:_inputDirection(humanoid: Humanoid): Vector3
	local x, z = 0, 0
	if not UserInputService:GetFocusedTextBox() then
		for _, key in KEYS do
			if UserInputService:IsKeyDown(key[1] :: Enum.KeyCode) then
				x += key[2] :: number
				z += key[3] :: number
			end
		end
	end
	if x == 0 and z == 0 then
		for _, input in UserInputService:GetGamepadState(Enum.UserInputType.Gamepad1) do
			if input.KeyCode == Enum.KeyCode.Thumbstick1 and input.Position.Magnitude > 0.25 then
				x, z = input.Position.X, -input.Position.Y
			end
		end
	end
	local camera = Workspace.CurrentCamera
	if (x == 0 and z == 0) or not camera then
		return Vector3.zero
	end
	local look = camera.CFrame.LookVector
	local forward = Vector3.new(look.X, 0, look.Z)
	if forward.Magnitude < 1e-3 then
		return Vector3.zero
	end
	forward = forward.Unit
	local right = forward:Cross(Vector3.yAxis)
	local world = right * x - forward * z
	return if world.Magnitude > 1e-3 then world.Unit else Vector3.zero
end

-- Firing stops the sprint.
function MovementController:StopSprint()
	self._sprintHeld = false
end

-- The hip height eases to the stance's each step (_step).
function MovementController:_setCrouch(crouching: boolean)
	self._crouching = crouching
end

function MovementController:_targetHipHeight(): number?
	local base = self._baseHipHeight
	if not base then
		return nil
	end
	local drop = if self._sliding then SLIDE.drop elseif self._crouching then CROUCH_DROP else 0
	return math.max(base - drop, 0.3)
end

function MovementController:_endSlide()
	self._sliding = false
	self._slideLoss = 0
	self._slideAir = 0
end

function MovementController:_tryCrouch()
	local humanoid, rootPart = self:_character()
	if not humanoid or not rootPart then
		return
	end
	local now = os.clock()
	local sprinting = self._sprintHeld and humanoid.MoveDirection.Magnitude > 0.1
	local horizontal = Vector3.new(rootPart.AssemblyLinearVelocity.X, 0, rootPart.AssemblyLinearVelocity.Z)
	if not self._crouching and sprinting and horizontal.Magnitude >= SLIDE.minSpeed and now - self._lastSlide >= SLIDE.cooldown
		and humanoid.FloorMaterial ~= Enum.Material.Air then
		-- Slide the way you are running (the movement keys), else where the
		-- camera looks.
		local move = self:_inputDirection(humanoid)
		local camera = Workspace.CurrentCamera
		local look = if camera then camera.CFrame.LookVector else rootPart.CFrame.LookVector
		local flat = if move.Magnitude > 0.1 then move else Vector3.new(look.X, 0, look.Z)
		self._slideDirection = if flat.Magnitude > 1e-3 then flat.Unit else horizontal.Unit
		self._sliding = true
		self._slideLoss = 0
		self._slideAir = 0
		self._slideSpeed = SPEEDS.slide
		self._slideStart = now
		self._lastSlide = now
		self._sprintHeld = false
		self:_setCrouch(true)
		return
	end
	if self._sliding then
		-- Out of the slide early, staying crouched.
		self:_endSlide()
		return
	end
	self:_setCrouch(not self._crouching)
end

function MovementController:_step(deltaTime: number)
	local humanoid, rootPart = self:_character()
	if not humanoid or not rootPart or humanoid.Health <= 0 then
		return
	end
	local now = os.clock()
	local moving = humanoid.MoveDirection.Magnitude > 0.1
	local aiming = self._isAiming()
	-- Jumping stands you up.
	if self._crouching and humanoid:GetState() == Enum.HumanoidStateType.Jumping then
		self:_endSlide()
		self:_setCrouch(false)
	end
	local sprinting = self._sprintHeld and moving and not self._crouching and not aiming and self._stamina > 0
	if sprinting then
		self._stamina = math.max(self._stamina - STAMINA.drain * deltaTime, 0)
		self._lastSprint = now
		if self._stamina <= 0 then
			self._sprintHeld = false
		end
	elseif now - self._lastSprint >= STAMINA.regenDelay then
		self._stamina = math.min(self._stamina + STAMINA.regen * deltaTime, STAMINA.max)
	end
	local speed = SPEEDS.walk
	local velocity = rootPart.AssemblyLinearVelocity
	if self._sliding then
		-- Against a wall (moving far slower than asked) or off a ledge: over.
		local along = Vector3.new(velocity.X, 0, velocity.Z):Dot(self._slideDirection)
		self._slideAir = if humanoid.FloorMaterial == Enum.Material.Air then self._slideAir + deltaTime else 0
		if (now - self._slideStart > 0.12 and along < self._slideSpeed * SLIDE.blockedShare) or self._slideAir > SLIDE.airGrace then
			self:_endSlide()
		end
	end
	if self._sliding then
		local progress = math.clamp((now - self._slideStart) / SLIDE.seconds, 0, 1)
		local curveSpeed = SPEEDS.slide - (SPEEDS.slide - SPEEDS.crouch) * progress ^ SLIDE.curve
		-- Steering: turn towards the movement keys, slower as the slide slows;
		-- the opposite key brakes instead.
		local wanted = self:_inputDirection(humanoid)
		if wanted.Magnitude > 0.1 then
			local direction = self._slideDirection
			if wanted:Dot(direction) < -0.5 then
				self._slideLoss += SLIDE.brakeLoss * deltaTime
			else
				local angle = math.atan2(direction:Cross(wanted).Y, direction:Dot(wanted))
				local grip = SLIDE.minTurnShare + (1 - SLIDE.minTurnShare) * (1 - progress)
				local step = math.sign(angle) * math.min(math.abs(angle), math.rad(SLIDE.turnRate * grip) * deltaTime)
				if math.abs(step) > 1e-5 then
					self._slideDirection = (CFrame.fromAxisAngle(Vector3.yAxis, step) * direction).Unit
					self._slideLoss += SLIDE.carveLoss * math.abs(step) / (math.pi / 2)
				end
			end
		end
		speed = math.max(curveSpeed * (1 - math.min(self._slideLoss, 1)), SPEEDS.crouch)
		self._slideSpeed = speed
		rootPart.AssemblyLinearVelocity = self._slideDirection * speed + Vector3.new(0, velocity.Y, 0)
		if progress >= 1 or speed <= SPEEDS.crouch + 0.5 then
			self:_endSlide()
		end
	elseif self._crouching then
		speed = SPEEDS.crouch
	elseif aiming then
		speed = SPEEDS.aim
	elseif sprinting then
		speed = SPEEDS.sprint
	end
	humanoid.WalkSpeed = speed
	-- Hips down / up. Only while crouched, sliding or on the way back up:
	-- standing, the avatar's own hip height is left alone (and re-read, in
	-- case the avatar changes).
	local lowered = self._crouching or self._sliding
	if lowered or self._heightEasing then
		local targetHeight = self:_targetHipHeight()
		if targetHeight then
			humanoid.HipHeight += (targetHeight - humanoid.HipHeight) * (1 - math.exp(-HEIGHT_EASE * deltaTime))
			self._heightEasing = lowered or math.abs(targetHeight - humanoid.HipHeight) > 0.01
			if not self._heightEasing then
				humanoid.HipHeight = targetHeight
			end
		end
	else
		self._baseHipHeight = humanoid.HipHeight
	end
	self._animation:SetStance(self._crouching and not self._sliding, self._sliding)
	-- Stamina bar.
	local ratio = self._stamina / STAMINA.max
	self._fill.Size = UDim2.fromScale(ratio, 1)
	self._fill.BackgroundColor3 = if self._stamina < STAMINA.minToSprint then Color3.fromRGB(255, 120, 60) else Color3.fromRGB(0, 220, 255)
	self._track.Visible = ratio < 0.999
end

function MovementController:Enable()
	if self._enabled then
		return
	end
	self._enabled = true
	self._screen.Enabled = true
	self._stamina = STAMINA.max
	ContextActionService:BindAction(SPRINT_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			-- Needs some stamina to start again after running dry.
			self._sprintHeld = self._stamina >= STAMINA.minToSprint
			if self._sprintHeld and self._crouching and not self._sliding then
				self:_setCrouch(false)
			end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self._sprintHeld = false
		end
		-- Sink: SHIFT would otherwise also toggle shift-lock.
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindAction(CROUCH_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_tryCrouch()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.C, Enum.KeyCode.LeftControl, Enum.KeyCode.ButtonB)
	self._driveConnection = RunService.PreSimulation:Connect(function()
		local humanoid = self._humanoid
		if self._sliding and humanoid then
			humanoid:Move(self._slideDirection, false)
			humanoid.WalkSpeed = self._slideSpeed
		end
	end)
	self._connection = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end)
end

function MovementController:Disable()
	if not self._enabled then
		return
	end
	self._enabled = false
	self._screen.Enabled = false
	ContextActionService:UnbindAction(SPRINT_ACTION)
	ContextActionService:UnbindAction(CROUCH_ACTION)
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self._driveConnection then
		self._driveConnection:Disconnect()
		self._driveConnection = nil
	end
	local humanoid = self:_character()
	local lowered = self._crouching or self._sliding or self._heightEasing
	self:_endSlide()
	self._sprintHeld = false
	self:_setCrouch(false)
	if humanoid then
		humanoid.WalkSpeed = SPEEDS.walk
		if self._baseHipHeight and lowered then
			humanoid.HipHeight = self._baseHipHeight
		end
		self._heightEasing = false
	end
	self._animation:SetStance(false, false)
end

function MovementController:Destroy()
	self:Disable()
	self._screen:Destroy()
end

return MovementController
