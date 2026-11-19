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

local ContentProvider = game:GetService("ContentProvider")
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
local CombatAudio = require(root.Config.CombatAudioConfig)
local CombatHUD = require(script.Parent.Parent.HUD.CombatHUD)

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

local function playCue(parent: Instance, cue, speed: number?)
	if not CombatAudio.Enabled then return end
	local sound = Instance.new("Sound")
	sound.Name = "CombatCue"
	sound.SoundId = cue.id
	sound.Volume = cue.volume
	sound.PlaybackSpeed = speed or cue.speed
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = cue.maxDistance or 60
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- The weapon's own shot sounds (CombatAudioConfig.Weapons), if any.
local function weaponSounds(tool: Tool?): any?
	return tool and (CombatAudio.Weapons :: any)[tool.Name]
end

-- One shot: the weapon's single-shot sound, else the generic one.
local function shotCue(tool: Tool?): any
	local sounds = weaponSounds(tool)
	return (sounds and sounds.single) or CombatAudio.Shot
end

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

-- aimProgress: 0..1 into the sights (ShooterCamera); accuracy and recoil
-- follow it, so aiming pays off over the weapon's aim time.
function CombatController.new(playerGui: PlayerGui, animation: any, isAiming: () -> boolean, onFire: (() -> ())?, aimProgress: (() -> number)?)
	local screen = Instance.new("ScreenGui")
	screen.Name = "CombatHUD"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 82
	screen.Enabled = false
	screen.Parent = playerGui
	-- Health, ammo, reload and hit confirmation are drawn by the HUD
	-- (HUD/CombatHUD); this ScreenGui only carries the UI sound cues.
	local effects = Instance.new("Folder")
	effects.Name = "CombatEffects"
	local self = setmetatable({
		_screen = screen,
		_hud = CombatHUD.get(),
		-- The reload in progress (client side): which weapon, when it started,
		-- how long it takes, and whether the request was sent again.
		_reloading = nil :: { tool: Tool, started: number, duration: number, resent: boolean }?,
		-- Last server ammo seen per weapon: a rise means the server refilled it.
		_serverSeen = {} :: { [Tool]: number },
		_effects = effects,
		_animation = animation,
		_isAiming = isAiming,
		_aimProgress = aimProgress or function(): number
			return if isAiming() then 1 else 0
		end,
		_onFire = onFire,
		-- The weapon being taken out: no firing or reloading until its draw
		-- time (WeaponStats.DrawSeconds) has passed; the server checks it too.
		_drawTool = nil :: Tool?,
		_autoSound = nil :: Sound?, -- the automatic-fire loop while the trigger is held
		_autoTool = nil :: Tool?,
		_tailSound = nil :: Sound?, -- single-shot sound that rings out the last round
		_singlePool = {} :: { Sound }, -- preloaded single shots of the held weapon
		_singleNext = 1,
		_singleCue = nil :: any,
		_echoLast = setmetatable({}, { __mode = "k" }) :: any, -- last echo time per shooter
		_autoFade = nil :: Tween?,
		_autoVolume = 0,
		_drawStarted = 0,
		_drawDuration = 0,
		_enabled = false,
		_triggerHeld = false,
		_firedThisPress = false,
		_lastShot = 0,
		_predicted = {} :: { [Tool]: number },
		_cameraKick = 0,
		_cameraYaw = 0,
		_appliedKick = 0,
		_appliedYaw = 0,
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
	self._hud:Hit(killed)
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

function CombatController:_serverAmmo(tool: Tool): number
	local server = tool:GetAttribute("Ammo")
	return if type(server) == "number" then server else WeaponStats.Get(tool).magazine
end

function CombatController:_ammoOf(tool: Tool): number
	local predicted = self._predicted[tool]
	local server = self:_serverAmmo(tool)
	local seen = self._serverSeen[tool]
	self._serverSeen[tool] = server
	-- The prediction runs ahead of the server (shots already spent here) and
	-- is never above it. The server's count only ever goes up on a reload,
	-- so a rise means a full magazine: take it, even if the local reload
	-- ended first and had been pulled down to the old count.
	if predicted == nil or predicted > server or (seen ~= nil and server > seen) then
		self._predicted[tool] = server
		return server
	end
	return predicted
end

-- True while this weapon cannot fire because of a reload (ours, or one the
-- server is still finishing, e.g. after switching back to it).
-- Every frame: a different weapon in hand starts its draw.
function CombatController:_updateDraw()
	local held = heldWeapon(Players.LocalPlayer.Character)
	if held ~= self._drawTool then
		self:_prepareWeaponSounds(held)
		self._drawTool = held
		self._drawStarted = os.clock()
		self._drawDuration = if held then WeaponStats.DrawSeconds(held) else 0
	end
	local progress = if self._drawDuration > 0 then (os.clock() - self._drawStarted) / self._drawDuration else 1
	self._hud:SetDraw(held ~= nil and progress < 1, progress)
end

-- True while the weapon in hand is still being taken out.
function CombatController:_isDrawing(tool: Tool): boolean
	return tool == self._drawTool and os.clock() - self._drawStarted < self._drawDuration
end

function CombatController:_isReloading(tool: Tool): boolean
	local reloading = self._reloading
	return (reloading ~= nil and reloading.tool == tool) or tool:GetAttribute("Reloading") == true
end

function CombatController:_reload()
	local character = Players.LocalPlayer.Character
	local tool = heldWeapon(character)
	if not tool or not self._remotes or self:_isReloading(tool) or self:_isDrawing(tool) then
		return
	end
	local stats = WeaponStats.Get(tool)
	if self:_ammoOf(tool) >= stats.magazine then
		return
	end
	self:_stopAutoSound()
	self._reloading = { tool = tool, started = os.clock(), duration = stats.reloadSeconds, resent = false }
	self._animation:SetReloading(true)
	self._remotes.reload:FireServer()
end

-- Every frame: advances the reload bar and ends the reload once the server
-- has refilled the magazine (always to full), so the counter never shows a
-- partial reload.
function CombatController:_updateReload()
	local reloading = self._reloading
	local held = heldWeapon(Players.LocalPlayer.Character)
	if reloading and held ~= reloading.tool then
		-- Switched weapon (or died): this reload is no longer shown. The
		-- server still finishes it on the stowed weapon.
		self._reloading = nil
		self._animation:SetReloading(false)
		reloading = nil
	end
	if not reloading then
		-- A reload the server is finishing on this weapon (switched back).
		local serverBusy = held ~= nil and held:GetAttribute("Reloading") == true
		self._hud:SetReload(serverBusy, 1)
		return
	end
	local tool = reloading.tool
	local elapsed = os.clock() - reloading.started
	local stats = WeaponStats.Get(tool)
	local serverDone = tool:GetAttribute("Reloading") ~= true and self:_serverAmmo(tool) >= stats.magazine
	if elapsed >= reloading.duration and serverDone then
		self._reloading = nil
		self._predicted[tool] = stats.magazine
		self._animation:SetReloading(false)
		self._hud:SetReload(false, 0)
		return
	end
	-- Waiting on the server past the expected time: ask once more (the first
	-- request may have been dropped), then give up and trust the server.
	if elapsed > reloading.duration + 1.5 and not reloading.resent and self._remotes then
		reloading.resent = true
		self._remotes.reload:FireServer()
	elseif elapsed > reloading.duration + 4 then
		self._reloading = nil
		self._animation:SetReloading(false)
		self._hud:SetReload(false, 0)
		return
	end
	-- Up to 97% on the local clock; the last bit when the server confirms.
	self._hud:SetReload(true, math.min(elapsed / reloading.duration, 0.97))
end

-- Shot sound: the single shot for a trigger pull; while an automatic weapon
-- keeps firing, its recorded burst loops instead, played at the weapon's real
-- fire rate, until the firing stops. Every Sound is made and preloaded when
-- the weapon comes out (_prepareWeaponSounds): a new Sound has to load before
-- it plays, which delayed the first shots.
local SINGLE_POOL = 4 -- default single-shot Sounds taking turns (cue.voices overrides)

local function shotSound(name: string, cue: any, parent: Instance): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = cue.id
	sound.Volume = cue.volume
	sound.PlaybackSpeed = cue.speed or 1
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = cue.maxDistance or 140
	sound.Parent = parent
	return sound
end

function CombatController:_prepareWeaponSounds(tool: Tool?)
	for _, old in self._singlePool do
		old:Destroy()
	end
	table.clear(self._singlePool)
	self._singleNext = 1
	if self._autoSound then
		self._autoSound:Destroy()
		self._autoSound = nil
		self._autoTool = nil
	end
	if self._tailSound then
		self._tailSound:Destroy()
		self._tailSound = nil
	end
	if self._autoFade then
		self._autoFade:Cancel()
		self._autoFade = nil
	end
	if not tool then
		return
	end
	local handle = tool:FindFirstChild("Handle")
	local parent: Instance = if handle and handle:IsA("BasePart") then handle else tool
	local toLoad: { Instance } = {}
	local cue = shotCue(tool)
	self._singleCue = cue
	for index = 1, math.clamp(cue.voices or SINGLE_POOL, 1, 16) do
		local single = shotSound("Shot" .. index, cue, parent)
		table.insert(self._singlePool, single)
		table.insert(toLoad, single)
	end
	local function preload()
		task.spawn(function()
			pcall(function()
				ContentProvider:PreloadAsync(toLoad)
			end)
		end)
	end
	local sounds = weaponSounds(tool)
	local auto = sounds and sounds.auto
	local stats = WeaponStats.Get(tool)
	if not auto or not stats.automatic then
		preload()
		return
	end
	local speed = math.clamp(stats.fireRate * 60 / auto.rpm, 0.5, 2)
	local sound = Instance.new("Sound")
	sound.Name = "AutoFire"
	sound.SoundId = auto.id
	sound.Volume = auto.volume
	sound.Looped = true
	sound.PlaybackSpeed = speed
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = auto.maxDistance or 140
	-- Optional: keep the recorded pitch (adds a little latency).
	if auto.keepPitch and math.abs(speed - 1) > 0.01 then
		local pitch = Instance.new("PitchShiftSoundEffect")
		pitch.Octave = math.clamp(1 / speed, 0.5, 2)
		pitch.Parent = sound
	end
	sound.Parent = parent
	self._autoSound = sound
	self._autoTool = tool
	self._autoVolume = auto.volume
	-- The last shot of a burst rings out on the weapon's single-shot sound
	-- (same weapon, full natural decay), picked up where that shot is.
	table.insert(toLoad, sound)
	if sounds.single then
		local tail = shotSound("BurstTail", sounds.single, parent)
		self._tailSound = tail
		table.insert(toLoad, tail)
	end
	preload()
end

-- One single shot on the next pooled Sound (already loaded), else a new one.
function CombatController:_playSingle(tool: Tool, head: BasePart)
	local pool = self._singlePool
	if #pool == 0 or self._drawTool ~= tool or not CombatAudio.Enabled then
		playCue(head, shotCue(tool))
		return
	end
	local cue = self._singleCue
	local sound = pool[self._singleNext]
	self._singleNext = self._singleNext % #pool + 1
	-- Earlier tails still ringing step back under the new shot (cue.duck).
	local duck = cue and cue.duck
	if duck then
		for _, other in pool do
			if other ~= sound and other.IsPlaying then
				TweenService:Create(other, TweenInfo.new(0.05), { Volume = math.min(other.Volume, cue.volume * duck) }):Play()
			end
		end
	end
	sound:Stop()
	sound.Volume = if cue then cue.volume else sound.Volume
	sound.TimePosition = 0
	sound:Play()
end

function CombatController:_shotSound(tool: Tool, stats: any, head: BasePart, continuing: boolean)
	local sound = self._autoSound
	if continuing and stats.automatic and sound and self._autoTool == tool and CombatAudio.Enabled then
		if self._autoFade then
			-- Firing again during the release fade: back to full at once.
			self._autoFade:Cancel()
			self._autoFade = nil
			sound:Stop()
		end
		if not sound.IsPlaying then
			sound.Volume = self._autoVolume
			sound.TimePosition = 0
			sound:Play()
		end
		return
	end
	self:_stopAutoSound()
	self:_playSingle(tool, head)
end

-- The firing stopped: instead of cutting the loop dead (often mid-shot, with
-- the echo chopped off), it fades out over a few hundredths of a second while
-- the single-shot sound takes over at the same point of the last shot and
-- lets it ring out naturally.
local RELEASE_FADE = 0.06
local SINGLE_ONSET = 0.015 -- where the shot starts in the single-shot file

function CombatController:_stopAutoSound()
	local sound = self._autoSound
	if not sound or not sound.IsPlaying or self._autoFade then
		return
	end
	local sinceShot = os.clock() - self._lastShot
	local tail = self._tailSound
	if tail and tail.IsLoaded and sinceShot < tail.TimeLength - SINGLE_ONSET - 0.02 then
		tail:Stop()
		tail.TimePosition = SINGLE_ONSET + sinceShot
		tail:Play()
	end
	local fade = TweenService:Create(sound, TweenInfo.new(RELEASE_FADE, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { Volume = 0 })
	self._autoFade = fade
	fade.Completed:Connect(function(state)
		if state == Enum.PlaybackState.Completed and self._autoFade == fade then
			self._autoFade = nil
			sound:Stop()
			sound.Volume = self._autoVolume
		end
	end)
	fade:Play()
end

-- Distant echo of a shot at `position` (CombatAudioConfig.Echo). Others'
-- shots: louder the farther away (the direct shot fades with distance, the
-- echo carries), in 3D from the shooter, late by the speed of sound. Own
-- shots: a soft echo of the surroundings. One per shooter per minInterval.
function CombatController:_echo(position: Vector3, shooter: any, own: boolean)
	local echo = (CombatAudio :: any).Echo
	if not echo or not CombatAudio.Enabled then
		return
	end
	local now = os.clock()
	local last = self._echoLast[shooter]
	if last and now - last < echo.minInterval then
		return
	end
	self._echoLast[shooter] = now
	local camera = Workspace.CurrentCamera
	local distance = if camera then (position - camera.CFrame.Position).Magnitude else 0
	local volume, delay
	if own then
		volume, delay = echo.ownVolume, echo.ownDelay
	else
		local t = math.clamp((distance - echo.nearDistance) / (echo.farDistance - echo.nearDistance), 0, 1)
		local far = t * t * (3 - 2 * t)
		volume = echo.volume * (echo.nearShare + (1 - echo.nearShare) * far)
		delay = distance / echo.studsPerSecond
	end
	local anchor = Instance.new("Part")
	anchor.Name = "ShotEcho"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = self._effects
	local sound = Instance.new("Sound")
	sound.SoundId = echo.id
	sound.Volume = math.min(volume, 10)
	-- A little variation so repeated echoes do not sound copied.
	sound.PlaybackSpeed = 0.96 + math.random() * 0.08
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.RollOffMinDistance = 40
	sound.RollOffMaxDistance = echo.maxDistance
	sound.Parent = anchor
	task.delay(delay, function()
		if sound.Parent then
			sound:Play()
		end
	end)
	Debris:AddItem(anchor, delay + 1.8)
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
	if self:_isReloading(tool) or self:_isDrawing(tool) then
		return
	end
	local stats = WeaponStats.Get(tool)
	local now = os.clock()
	-- Second and later shots of one held trigger pull (automatic fire).
	local continuing = self._firedThisPress and self._triggerHeld
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
	self._hud:Shot()
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
	-- Accuracy builds up with the sights: hip spread to aim spread.
	local aim = math.clamp(self._aimProgress(), 0, 1)
	local spread = math.rad(stats.spread + (stats.aimSpread - stats.spread) * aim)
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
	self:_shotSound(tool, stats, head, continuing)
	self:_echo(head.Position, "self", true)
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
	self._cameraKick = math.min(self._cameraKick + stats.recoil * (0.35 - 0.1 * aim), MAX_CAMERA_KICK)
	self._cameraYaw = math.clamp(self._cameraYaw + (math.random() - 0.5) * stats.recoil * 0.12, -1, 1)
	if self:_ammoOf(tool) <= 0 then
		self:_reload()
	end
end

-- Every frame: the held weapon and its magazine for the HUD (health is
-- bound by the HUD itself to the Humanoid).
function CombatController:_updateAmmo()
	local tool = heldWeapon(Players.LocalPlayer.Character)
	if not tool then
		return
	end
	local stats = WeaponStats.Get(tool)
	local name = tool:GetAttribute("DisplayName")
	self._hud:SetWeapon(if type(name) == "string" then name else tool.Name, stats.name, stats.automatic, stats.magazine)
	self._hud:SetAmmo(self:_ammoOf(tool), stats.magazine)
end

function CombatController:Enable()
	if self._enabled then
		return
	end
	self._enabled = true
	self._screen.Enabled = true
	self._effects.Parent = Workspace
	-- Every configured shot sound loaded up front (others' shots included).
	-- As Sound instances: plain id strings are preloaded as images, which
	-- fails for audio ("Asset type does not match requested type").
	task.spawn(function()
		local sounds = {}
		local function add(cue: any)
			if type(cue) ~= "table" or type(cue.id) ~= "string" then
				return
			end
			local sound = Instance.new("Sound")
			sound.SoundId = cue.id
			table.insert(sounds, sound)
		end
		add(CombatAudio.Shot)
		if (CombatAudio :: any).Echo then
			add((CombatAudio :: any).Echo)
		end
		for _, weapon in CombatAudio.Weapons do
			for _, cue in weapon :: any do
				add(cue)
			end
		end
		pcall(function()
			ContentProvider:PreloadAsync(sounds)
		end)
		for _, sound in sounds do
			sound:Destroy()
		end
	end)
	ContextActionService:BindAction(FIRE_ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			self._triggerHeld = true
			self._firedThisPress = false
			self:_fire()
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			self._triggerHeld = false
			self:_stopAutoSound()
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
		self:_updateDraw()
		self:_updateReload()
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
			playCue(self._screen, CombatAudio.Hit, if killed then 1.1 else CombatAudio.Hit.speed)
		end))
		table.insert(self._connections, self._remotes.shots.OnClientEvent:Connect(function(shooter: Model, endpoints)
			local tool = heldWeapon(shooter)
			local head = shooter and shooter:FindFirstChild("Head")
			local from = (tool and muzzleOf(tool)) or (head and head:IsA("BasePart") and head.Position)
			if not from then
				return
			end
			if head then playCue(head, shotCue(tool)) end
			self:_echo(from, shooter, false)
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
	table.clear(self._serverSeen)
	if self._reloading then
		self._reloading = nil
		self._animation:SetReloading(false)
	end
	self._hud:SetReload(false, 0)
	self._hud:SetDraw(false, 1)
	self._drawTool = nil
	self:_prepareWeaponSounds(nil)
end

function CombatController:Destroy()
	self:Disable()
	self._screen:Destroy()
	self._effects:Destroy()
end

return CombatController
