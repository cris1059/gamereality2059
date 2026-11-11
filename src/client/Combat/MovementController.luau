--!strict

-- Shooter movement for the local player (ideas from sysscan/Roblox-FPS-Movement,
-- rewritten): SHIFT sprints while there is stamina (it drains while
-- sprinting and refills after a short pause); C / CTRL crouches; crouching
-- while sprinting slides along the camera's direction, fast at first and
-- slowing down on a progress^2.8 curve to crouch speed. Walk speed follows
-- a priority: slide > crouch > aiming > sprint > walk. Firing or aiming stops
-- the sprint. The stance is posed by ShooterAnimation (and shared with others
-- through it).

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MovementController = {}
MovementController.__index = MovementController

local SPRINT_ACTION = "Reality2059ShooterSprint"
local CROUCH_ACTION = "Reality2059Crouch"

local SPEEDS = table.freeze({ walk = 16, sprint = 24, crouch = 9, aim = 11, slide = 36 })
local STAMINA = table.freeze({ max = 100, drain = 22, regen = 30, regenDelay = 0.9, minToSprint = 15 })
local SLIDE = table.freeze({ seconds = 0.85, cooldown = 1.1, curve = 2.8, minSpeed = 14 })
local CROUCH_DROP = 1.1

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
		_lastSlide = -10,
		_stamina = STAMINA.max,
		_lastSprint = 0,
		_baseHipHeight = nil :: number?,
		_humanoid = nil :: Humanoid?,
		_connection = nil :: RBXScriptConnection?,
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
	end
	return humanoid, if rootPart and rootPart:IsA("BasePart") then rootPart else nil
end

-- Firing stops the sprint.
function MovementController:StopSprint()
	self._sprintHeld = false
end

function MovementController:_setCrouch(crouching: boolean)
	local humanoid = self:_character()
	self._crouching = crouching
	if humanoid and self._baseHipHeight then
		humanoid.HipHeight = if crouching then math.max(self._baseHipHeight - CROUCH_DROP, 0.3) else self._baseHipHeight
	end
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
		-- Slide along where the camera looks (flattened).
		local camera = Workspace.CurrentCamera
		local look = if camera then camera.CFrame.LookVector else rootPart.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		self._slideDirection = if flat.Magnitude > 1e-3 then flat.Unit else horizontal.Unit
		self._sliding = true
		self._slideStart = now
		self._lastSlide = now
		self._sprintHeld = false
		self:_setCrouch(true)
		return
	end
	if self._crouching then
		self._sliding = false
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
		self._sliding = false
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
	if self._sliding then
		local progress = math.clamp((now - self._slideStart) / SLIDE.seconds, 0, 1)
		speed = SPEEDS.slide - (SPEEDS.slide - SPEEDS.crouch) * progress ^ SLIDE.curve
		local velocity = rootPart.AssemblyLinearVelocity
		rootPart.AssemblyLinearVelocity = self._slideDirection * speed + Vector3.new(0, velocity.Y, 0)
		if progress >= 1 then
			self._sliding = false
		end
	elseif self._crouching then
		speed = SPEEDS.crouch
	elseif aiming then
		speed = SPEEDS.aim
	elseif sprinting then
		speed = SPEEDS.sprint
	end
	humanoid.WalkSpeed = speed
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
	local humanoid = self:_character()
	self._sliding = false
	self._sprintHeld = false
	if humanoid then
		self:_setCrouch(false)
		humanoid.WalkSpeed = SPEEDS.walk
	end
	self._animation:SetStance(false, false)
end

function MovementController:Destroy()
	self:Disable()
	self._screen:Destroy()
end

return MovementController
