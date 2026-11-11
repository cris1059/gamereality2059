--!strict

-- Shooting, client side. Left click fires the weapon in hand (held for
-- automatic weapons), R reloads (also automatic on an empty magazine). The
-- shot is aimed through the crosshair: a ray from the camera finds what is
-- under it, and the bullets leave the player's head towards that point (the
-- server checks they start there). Everything visible happens at once —
-- tracer, impact, muzzle flash, recoil — while the server decides the damage
-- (CombatService) and answers with the hits: damage numbers coloured by body
-- zone and a hit marker on the crosshair (red on a kill). Other players'
-- shots arrive as tracers (WeaponShots).

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local WeaponStats = require(root.Combat.WeaponStats)

local CombatController = {}
CombatController.__index = CombatController

local FIRE_ACTION = "Reality2059Fire"
local RELOAD_ACTION = "Reality2059Reload"
local STEP_NAME = "Reality2059CombatCamera"
local TRACER_COLOR = Color3.fromRGB(150, 230, 255)
local ZONE_COLORS = table.freeze({
	head = Color3.fromRGB(255, 72, 72),
	torso = Color3.fromRGB(245, 245, 250),
	arm = Color3.fromRGB(180, 190, 210),
	leg = Color3.fromRGB(180, 190, 210),
})
local CAMERA_KICK_RECOVERY = 10
-- Most the aim can be lifted by recoil at any moment (degrees).
local MAX_CAMERA_KICK = 3

local function heldWeapon(character: Model?): Tool?
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

function CombatController.new(playerGui: PlayerGui, animation: any, isAiming: () -> boolean, onFire: (() -> ())?)
	local screen = Instance.new("ScreenGui")
	screen.Name = "CombatHUD"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 82
	screen.Enabled = false
	screen.Parent = playerGui
	-- Hit marker: four diagonal ticks around the crosshair.
	local marker = Instance.new("Frame")
	marker.Name = "HitMarker"
	marker.AnchorPoint = Vector2.new(0.5, 0.5)
	marker.Position = UDim2.fromScale(0.5, 0.5)
	marker.Size = UDim2.fromOffset(36, 36)
	marker.BackgroundTransparency = 1
	marker.Visible = false
	marker.Parent = screen
	local ticks = {}
	for _, entry in { { -1, -1, 45 }, { 1, -1, -45 }, { -1, 1, -45 }, { 1, 1, 45 } } do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.new(0.5, entry[1] * 11, 0.5, entry[2] * 11)
		tick.Size = UDim2.fromOffset(10, 2)
		tick.Rotation = entry[3]
		tick.BorderSizePixel = 0
		tick.BackgroundColor3 = Color3.new(1, 1, 1)
		tick.Parent = marker
		table.insert(ticks, tick)
	end
	-- Ammo (bottom right, above the weapon slots).
	local ammo = Instance.new("TextLabel")
	ammo.Name = "Ammo"
	ammo.AnchorPoint = Vector2.new(1, 1)
	ammo.Position = UDim2.new(1, -24, 1, -128)
	ammo.Size = UDim2.fromOffset(240, 34)
	ammo.BackgroundTransparency = 1
	ammo.Font = Enum.Font.SciFi
	ammo.TextSize = 28
	ammo.TextColor3 = Color3.fromRGB(236, 240, 255)
	ammo.TextXAlignment = Enum.TextXAlignment.Right
	ammo.Text = ""
	ammo.Parent = screen
	local effects = Instance.new("Folder")
	effects.Name = "CombatEffects"
	local self = setmetatable({
		_screen = screen,
		_marker = marker,
		_ticks = ticks,
		_ammo = ammo,
		_effects = effects,
		_animation = animation,
		_isAiming = isAiming,
		_onFire = onFire,
		_enabled = false,
		_triggerHeld = false,
		_firedThisPress = false,
		_lastShot = 0,
		_predicted = {} :: { [Tool]: number },
		_reloadingUntil = 0,
		_cameraKick = 0,
		_cameraYaw = 0,
		_appliedKick = 0,
		_appliedYaw = 0,
		_markerToken = 0,
		_remotes = nil :: any,
		_connections = {} :: { RBXScriptConnection },
	}, CombatController)
	task.spawn(function()
		local remotes = root:WaitForChild("Runtime"):WaitForChild(RemoteNames.Folder)
		self._remotes = {
			fire = remotes:WaitForChild(RemoteNames.WeaponFire),
			reload = remotes:WaitForChild(RemoteNames.WeaponReload),
			hit = remotes:WaitForChild(RemoteNames.WeaponHit),
			shots = remotes:WaitForChild(RemoteNames.WeaponShots),
		}
	end)
	return self
end

-- ------------------------------------------------------------- effects --

function CombatController:_tracer(from: Vector3, to: Vector3)
	local length = (to - from).Magnitude
	if length < 0.5 then
		return
	end
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = TRACER_COLOR
	tracer.Transparency = 0.25
	tracer.Size = Vector3.new(0.07, 0.07, length)
	tracer.CFrame = CFrame.lookAt((from + to) / 2, to)
	tracer.Parent = self._effects
	TweenService:Create(tracer, TweenInfo.new(0.09), { Transparency = 1 }):Play()
	Debris:AddItem(tracer, 0.12)
end

function CombatController:_impact(position: Vector3)
	local spark = Instance.new("Part")
	spark.Anchored = true
	spark.CanCollide = false
	spark.CanQuery = false
	spark.CanTouch = false
	spark.CastShadow = false
	spark.Shape = Enum.PartType.Ball
	spark.Material = Enum.Material.Neon
	spark.Color = Color3.fromRGB(255, 220, 150)
	spark.Size = Vector3.one * 0.35
	spark.CFrame = CFrame.new(position)
	spark.Parent = self._effects
	TweenService:Create(spark, TweenInfo.new(0.15), { Transparency = 1, Size = Vector3.one * 0.8 }):Play()
	Debris:AddItem(spark, 0.2)
end

function CombatController:_flash(at: Vector3)
	local holder = Instance.new("Part")
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(at)
	holder.Parent = self._effects
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 140)
	light.Brightness = 3
	light.Range = 8
	light.Parent = holder
	Debris:AddItem(holder, 0.05)
end

-- Floating number where the hit landed, coloured by body zone.
function CombatController:_damageNumber(position: Vector3, damage: number, zone: string)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.CFrame = CFrame.new(position + Vector3.new((math.random() - 0.5) * 0.8, 0.4, (math.random() - 0.5) * 0.8))
	anchor.Parent = self._effects
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 50)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Parent = anchor
	local color = ZONE_COLORS[zone] or Color3.new(1, 1, 1)
	local number = Instance.new("TextLabel")
	number.Size = UDim2.new(1, 0, 0, 30)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.GothamBlack
	number.Text = tostring(damage)
	number.TextSize = if zone == "head" then 30 else 24
	number.TextColor3 = color
	number.TextStrokeTransparency = 0.4
	number.Parent = gui
	local label = Instance.new("TextLabel")
	label.Position = UDim2.fromOffset(0, 28)
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = WeaponStats.Zones[zone] and WeaponStats.Zones[zone].label or ""
	label.TextSize = 12
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.5
	label.Parent = gui
	local rise = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(gui, rise, { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(number, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(label, rise, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1)
end

function CombatController:_hitMarker(killed: boolean)
	self._markerToken += 1
	local token = self._markerToken
	for _, tick in self._ticks do
		tick.BackgroundColor3 = if killed then Color3.fromRGB(255, 60, 60) else Color3.new(1, 1, 1)
	end
	self._marker.Visible = true
	task.delay(if killed then 0.35 else 0.15, function()
		if token == self._markerToken then
			self._marker.Visible = false
		end
	end)
end

-- Front of the weapon (where tracers start).
local function muzzleOf(tool: Tool): Vector3?
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return nil
	end
	local length = tool:GetAttribute("PoseLength")
	local grip = handle.CFrame * tool.Grip
	return (grip * CFrame.new(0, 0, -(if type(length) == "number" then length else 1.5))).Position
end

-- ------------------------------------------------------------ shooting --

function CombatController:_ammoOf(tool: Tool): number
	local predicted = self._predicted[tool]
	local server = tool:GetAttribute("Ammo")
	if type(server) ~= "number" then
		server = WeaponStats.Get(tool).magazine
	end
	-- The prediction runs ahead of the server; never above it.
	if predicted == nil or predicted > server then
		self._predicted[tool] = server
		return server
	end
	return predicted
end

function CombatController:_reload()
	local character = Players.LocalPlayer.Character
	local tool = heldWeapon(character)
	if not tool or os.clock() < self._reloadingUntil or not self._remotes then
		return
	end
	local stats = WeaponStats.Get(tool)
	if self:_ammoOf(tool) >= stats.magazine then
		return
	end
	self._reloadingUntil = os.clock() + stats.reloadSeconds
	self._animation:SetReloading(true)
	self._remotes.reload:FireServer()
	task.delay(stats.reloadSeconds, function()
		self._animation:SetReloading(false)
		self._predicted[tool] = stats.magazine
	end)
end

function CombatController:_fire()
	local player = Players.LocalPlayer
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local head = character and character:FindFirstChild("Head")
	local tool = heldWeapon(character)
	local camera = Workspace.CurrentCamera
	if not character or not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") or not tool or not camera or not self._remotes then
		return
	end
	if os.clock() < self._reloadingUntil then
		return
	end
	local stats = WeaponStats.Get(tool)
	local now = os.clock()
	if now - self._lastShot < 1 / stats.fireRate or (not stats.automatic and self._firedThisPress) then
		return
	end
	local ammo = self:_ammoOf(tool)
	if ammo <= 0 then
		self:_reload()
		return
	end
	self._lastShot = now
	self._firedThisPress = true
	self._predicted[tool] = ammo - 1
	if self._onFire then
		self._onFire()
	end
	-- What is under the crosshair (ignoring yourself).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, self._effects }
	local viewport = camera.ViewportSize
	local ray = camera:ViewportPointToRay(viewport.X / 2, viewport.Y / 2)
	local aimHit = Workspace:Raycast(ray.Origin, ray.Direction * stats.range, params)
	local aimPoint = if aimHit then aimHit.Position else ray.Origin + ray.Direction * stats.range
	local origin = head.Position
	local base = aimPoint - origin
	base = if base.Magnitude > 1e-3 then base.Unit else ray.Direction
	local aiming = self._isAiming()
	local spread = math.rad(if aiming then stats.aimSpread else stats.spread)
	local directions = {}
	local frame = CFrame.lookAt(Vector3.zero, base)
	for _ = 1, stats.pellets do
		local angle = math.random() * 2 * math.pi
		local radius = math.sqrt(math.random()) * spread
		table.insert(directions, frame:VectorToWorldSpace(Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, -1)).Unit)
	end
	self._remotes.fire:FireServer(origin, directions, Workspace:GetServerTimeNow())
	-- Instant feedback; the server answers with the real hits.
	local muzzle = muzzleOf(tool) or origin
	self:_flash(muzzle)
	for _, direction in directions do
		local hit = Workspace:Raycast(origin, direction * stats.range, params)
		local finish = if hit then hit.Position else origin + direction * stats.range
		self:_tracer(muzzle, finish)
		if hit then
			self:_impact(hit.Position)
		end
	end
	-- Keep the weapon readable without making sustained fire drag the camera
	-- sharply upwards. Aiming steadies both the vertical and horizontal kick.
	self._animation:Kick(stats.recoil * 0.4)
	-- Capped so a long burst lifts the aim a little, not a lot.
	self._cameraKick = math.min(self._cameraKick + stats.recoil * (if aiming then 0.25 else 0.35), MAX_CAMERA_KICK)
	self._cameraYaw = math.clamp(self._cameraYaw + (math.random() - 0.5) * stats.recoil * 0.12, -1, 1)
	if self:_ammoOf(tool) <= 0 then
		self:_reload()
	end
end

function CombatController:_updateAmmo()
	local tool = heldWeapon(Players.LocalPlayer.Character)
	if not tool then
		self._ammo.Text = ""
		return
	end
	local stats = WeaponStats.Get(tool)
	if os.clock() < self._reloadingUntil then
		self._ammo.Text = "RECARGANDO"
	else
		self._ammo.Text = string.format("%d / %d", self:_ammoOf(tool), stats.magazine)
	end
end

function CombatController:Enable()
	if self._enabled then
		return
	end
	self._enabled = true
	self._screen.Enabled = true
	self._effects.Parent = Workspace
	ContextActionService:BindAction(FIRE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self._triggerHeld = true
			self._firedThisPress = false
			self:_fire()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self._triggerHeld = false
		end
		return Enum.ContextActionResult.Pass
	end, false, Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction(RELOAD_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self:_reload()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	-- Holding the trigger, recoil on the camera, the ammo counter.
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Camera.Value + 3, function(deltaTime: number)
		if self._triggerHeld then
			self:_fire()
		end
		-- The camera keeps its own rotation from frame to frame, so only the
		-- change in the recoil offset is applied: the aim rises by the kick and
		-- then settles back where it was (applying the whole offset every
		-- frame added up and dragged the camera far upwards).
		local recovery = math.exp(-CAMERA_KICK_RECOVERY * deltaTime)
		self._cameraKick *= recovery
		self._cameraYaw *= recovery
		local camera = Workspace.CurrentCamera
		local deltaPitch = self._cameraKick - self._appliedKick
		local deltaYaw = self._cameraYaw - self._appliedYaw
		if camera and (math.abs(deltaPitch) > 1e-4 or math.abs(deltaYaw) > 1e-4) then
			camera.CFrame *= CFrame.Angles(math.rad(deltaPitch), math.rad(deltaYaw), 0)
		end
		self._appliedKick = self._cameraKick
		self._appliedYaw = self._cameraYaw
		self:_updateAmmo()
	end)
	task.spawn(function()
		while self._enabled and not self._remotes do
			task.wait()
		end
		if not self._enabled then
			return
		end
		table.insert(self._connections, self._remotes.hit.OnClientEvent:Connect(function(hits, killed)
			for _, hit in hits do
				self:_damageNumber(hit.position, hit.damage, hit.zone)
			end
			self:_hitMarker(killed == true)
		end))
		table.insert(self._connections, self._remotes.shots.OnClientEvent:Connect(function(shooter: Model, endpoints)
			local tool = heldWeapon(shooter)
			local head = shooter and shooter:FindFirstChild("Head")
			local from = (tool and muzzleOf(tool)) or (head and head:IsA("BasePart") and head.Position)
			if not from then
				return
			end
			for _, finish in endpoints do
				self:_tracer(from, finish)
			end
		end))
	end)
end

function CombatController:Disable()
	if not self._enabled then
		return
	end
	self._enabled = false
	self._triggerHeld = false
	self._cameraKick, self._cameraYaw, self._appliedKick, self._appliedYaw = 0, 0, 0, 0
	self._screen.Enabled = false
	ContextActionService:UnbindAction(FIRE_ACTION)
	ContextActionService:UnbindAction(RELOAD_ACTION)
	pcall(RunService.UnbindFromRenderStep, RunService, STEP_NAME)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self._effects:ClearAllChildren()
	self._effects.Parent = nil
	table.clear(self._predicted)
end

function CombatController:Destroy()
	self:Disable()
	self._screen:Destroy()
	self._effects:Destroy()
end

return CombatController
