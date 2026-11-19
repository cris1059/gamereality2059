--!strict

-- The combat HUD (shooter mode: matches, training). One instance per client
-- (CombatHUD.get()), shown by FreeRoamController while in shooter mode and
-- fed by the systems that own the data:
--   * health          - the local Humanoid (server-authoritative), bound here
--                       and re-bound on every respawn;
--   * ammo / reload   - CombatController (server Ammo / Reloading + prediction);
--   * slots           - WeaponController (WeaponLoadout);
--   * hits / kills    - CombatController (WeaponHit); kills also build the
--                       streak that turns the portrait to GLOAT;
--   * match / feed    - MatchController (MatchState);
--   * crosshair state - ShooterCamera (aiming, free cursor).
-- Presentation only: it never decides anything about the game.
-- Studio test mode: DevConfig.HUDTest = true runs a loop through every state
-- (damage, healing, critical, gloat, ultimate) on top of the real HUD,
-- visual only, so the states can be judged without a real fight.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local DevConfig = require(root.Config.DevConfig)

local HUDConfig = require(script.Parent.HUDConfig)
local HealthPanel = require(script.Parent.HealthPanel)
local WeaponPanel = require(script.Parent.WeaponPanel)
local AbilityBar = require(script.Parent.AbilityBar)
local Crosshair = require(script.Parent.Crosshair)
local MatchBar = require(script.Parent.MatchBar)
local KillFeed = require(script.Parent.KillFeed)

local CombatHUD = {}
CombatHUD.__index = CombatHUD

local STEP_NAME = "Reality2059CombatHUD"

local instance: any = nil

function CombatHUD.get()
	if not instance then
		instance = CombatHUD._new()
	end
	return instance
end

function CombatHUD._new()
	local player = Players.LocalPlayer
	local screen = Instance.new("ScreenGui")
	screen.Name = "CombatHUD2059"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 85
	screen.Enabled = false
	screen.Parent = player:WaitForChild("PlayerGui")

	local self = setmetatable({
		_screen = screen,
		_health = HealthPanel.new(screen),
		_weapon = WeaponPanel.new(screen),
		_abilities = AbilityBar.new(screen),
		_crosshair = Crosshair.new(screen),
		_match = MatchBar.new(screen),
		_feed = KillFeed.new(screen),
		_enabled = false,
		_connections = {} :: { RBXScriptConnection },
		_characterConnections = {} :: { RBXScriptConnection },
		_kills = {} :: { number },
		_gloatUntil = 0,
		_dead = false,
		_profile = nil :: any,
		_test = nil :: any,
	}, CombatHUD)
	self:_place()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			self:_place()
		end)
	end
	return self
end

-- Scale everything to the screen height (design: 1080 px) and keep the
-- corner modules a margin away from the edges.
function CombatHUD:_place()
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else HUDConfig.DesignHeight
	local scale = math.clamp(height / HUDConfig.DesignHeight, HUDConfig.MinScale, HUDConfig.MaxScale)
	local margin = HUDConfig.Margin
	self._health:Place(scale, margin)
	self._weapon:Place(scale, margin)
	self._abilities:Place(scale, margin)
	self._crosshair:Place(scale)
	self._match:Place(scale, margin)
	self._feed:Place(scale, margin)
end

-- The saved character draft (class) for the identity line and portrait art.
function CombatHUD:SetProfile(draft: any)
	self._profile = draft
	self:_identity()
end

function CombatHUD:_identity()
	local player = Players.LocalPlayer
	local classId = if type(self._profile) == "table" then self._profile.classId else nil
	local info = classId and CharacterCatalog.ClassInfo[classId]
	local className = if info and (info :: any).name then (info :: any).name else "OPERADOR"
	self._health:SetIdentity(player.DisplayName, string.format("%s  ·  @%s", className, player.Name), info and info.color)
end

-- ------------------------------------------------------------ character --

function CombatHUD:_unbindCharacter()
	for _, connection in self._characterConnections do
		connection:Disconnect()
	end
	table.clear(self._characterConnections)
end

function CombatHUD:_bindCharacter(character: Model)
	self:_unbindCharacter()
	self._dead = false
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not self._enabled then
		return
	end
	local function refresh()
		if self._test then
			return
		end
		self._health:SetHealth(humanoid.Health, humanoid.MaxHealth)
		self._dead = humanoid.Health <= 0
	end
	table.insert(self._characterConnections, humanoid.HealthChanged:Connect(refresh))
	table.insert(self._characterConnections, humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(refresh))
	table.insert(self._characterConnections, humanoid.Died:Connect(function()
		self._dead = true
		table.clear(self._kills)
		self._gloatUntil = 0
	end))
	refresh()
	-- The bust: once now and again when the avatar's pieces finish loading.
	local classId = if type(self._profile) == "table" then self._profile.classId else nil
	local pending = false
	local function rebuild()
		if pending then
			return
		end
		pending = true
		task.delay(0.6, function()
			pending = false
			if character.Parent then
				self._health:SetCharacter(character, classId)
			end
		end)
	end
	rebuild()
	table.insert(self._characterConnections, character.ChildAdded:Connect(function(child)
		if child:IsA("Accessory") or child:IsA("Clothing") or child:IsA("BodyColors") then
			rebuild()
		end
	end))
end

-- --------------------------------------------------------------- states --

function CombatHUD:_state(): string
	local test = self._test
	if test and test.state then
		return test.state
	end
	if self._dead then
		return "dead"
	end
	local humanoid = self:_humanoid()
	if humanoid and humanoid.Health / math.max(humanoid.MaxHealth, 1) <= HUDConfig.Health.Critical then
		return "critical"
	end
	if os.clock() < self._gloatUntil then
		return "gloat"
	end
	return "normal"
end

function CombatHUD:_humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

-- A confirmed elimination by the local player (server WeaponHit): the
-- streak inside StreakWindow seconds unlocks GLOAT.
function CombatHUD:_countKill()
	local now = os.clock()
	local window = HUDConfig.Portrait.StreakWindow
	table.insert(self._kills, now)
	while #self._kills > 0 and now - self._kills[1] > window do
		table.remove(self._kills, 1)
	end
	self._health:SetStreak(#self._kills)
	if #self._kills >= HUDConfig.Portrait.GloatStreak then
		self._gloatUntil = now + HUDConfig.Portrait.GloatSeconds
	end
end

-- ------------------------------------------------------- data from others --

function CombatHUD:SetWeapon(name: string, classLabel: string, automatic: boolean, magazine: number)
	self._weapon:SetWeapon(name, classLabel, automatic, magazine)
end

function CombatHUD:SetAmmo(ammo: number, magazine: number)
	if not self._test then
		self._weapon:SetAmmo(ammo, magazine)
	end
end

function CombatHUD:SetReload(active: boolean, progress: number)
	self._weapon:SetReload(active, progress)
end

function CombatHUD:SetDraw(active: boolean, progress: number)
	self._weapon:SetDraw(active, progress)
end

function CombatHUD:SetSlots(names: { string }, equipped: number, max: number)
	self._weapon:SetSlots(names, equipped, max)
end

function CombatHUD:Shot()
	self._crosshair:Shot()
end

function CombatHUD:Hit(killed: boolean)
	self._crosshair:Hit(killed)
	if killed then
		self:_countKill()
	end
end

function CombatHUD:SetAiming(aiming: boolean)
	self._crosshair:SetAiming(aiming)
end

function CombatHUD:SetCrosshairVisible(visible: boolean)
	self._crosshair:SetVisible(visible)
end

-- MatchState view (nil hides the strip and clears the feed).
function CombatHUD:SetMatch(view: any?, teamNames: { [string]: string }?)
	if not view then
		self._match:Hide()
		self._feed:Clear()
		return
	end
	local mine = view.team or "A"
	local other = if mine == "A" then "B" else "A"
	local names = teamNames or {}
	self._match:SetMatch({
		allyScore = view.score[mine] or 0,
		rivalScore = view.score[other] or 0,
		scoreLimit = view.scoreLimit or 0,
		allyName = names[mine] or "",
		rivalName = names[other] or "",
		mode = string.format("DUELO POR EQUIPOS  ·  %s  ·  PRIMERO A %d", string.upper(view.mapName or ""), view.scoreLimit or 0),
		endsAt = view.endsAt or 0,
		phase = view.phase or "playing",
	})
	if view.event then
		local event = view.event
		local me = Players.LocalPlayer.DisplayName
		self._feed:Push({
			killer = event.killer,
			killerAlly = event.killerTeam == mine,
			victim = event.victim or "",
			victimAlly = event.victimTeam == mine,
			left = event.kind == "left",
			mine = event.killer ~= nil and event.killer == me,
			myDeath = event.kind == "kill" and event.victim == me,
		})
	end
end

function CombatHUD:SetTraining()
	self._match:SetFreeMode("ENTRENAMIENTO", "F RECOGER ARMA  ·  Q / E ASOMARSE  ·  R RECARGAR  ·  ALT + MENÚ PARA SALIR")
end

-- ---------------------------------------------------------- lifecycle --

function CombatHUD:Enable(options: { training: boolean? }?)
	if self._enabled then
		return
	end
	self._enabled = true
	self._screen.Enabled = true
	self:_identity()
	self:_place()
	local player = Players.LocalPlayer
	if player.Character then
		task.spawn(function()
			self:_bindCharacter(player.Character :: Model)
		end)
	end
	table.insert(self._connections, player.CharacterAdded:Connect(function(character)
		self:_bindCharacter(character)
	end))
	if options and options.training then
		self:SetTraining()
	end
	RunService:BindToRenderStep(STEP_NAME, Enum.RenderPriority.Last.Value, function(deltaTime: number)
		self:_step(deltaTime)
	end)
	if RunService:IsStudio() and (DevConfig :: any).HUDTest == true then
		self:_startTest()
	end
end

function CombatHUD:Disable()
	if not self._enabled then
		return
	end
	self._enabled = false
	self._screen.Enabled = false
	pcall(RunService.UnbindFromRenderStep, RunService, STEP_NAME)
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self:_unbindCharacter()
	self._match:Hide()
	self._feed:Clear()
	self._test = nil
	table.clear(self._kills)
	self._gloatUntil = 0
end

function CombatHUD:_step(deltaTime: number)
	self._health:SetState(self:_state() :: any)
	self._health:Update(deltaTime)
	self._weapon:Update(deltaTime)
	self._abilities:Update(deltaTime)
	self._crosshair:Update(deltaTime)
	self._match:Update()
	if self._test then
		self:_testStep(deltaTime)
	end
end

-- ------------------------------------------------------------ test mode --

-- A scripted loop through the states (visual only; real data resumes when
-- the loop is switched off). Each step: { seconds, apply }.
function CombatHUD:_startTest()
	self._abilities:SetAbilities({
		{ key = "Z", name = "Impulso", icon = "dash" },
		{ key = "X", name = "Escudo", icon = "shield" },
		{ key = "G", name = "Escáner", icon = "scan" },
	}, "T")
	self._test = { clock = 0, step = 0, state = nil, health = 525, max = 525, ult = 0, cooldown = 0 }
end

local TEST_STEPS = {
	{ 2.5, function(hud, test) test.state = "normal"; test.health = 525; hud._health:SetHealth(525, 525) end },
	{ 1.5, function(hud, test) test.health = 390; hud._health:SetHealth(390, 525); hud._crosshair:Hit(false) end },
	{ 1.5, function(hud, test) test.health = 250; hud._health:SetHealth(250, 525); hud._crosshair:Hit(false) end },
	{ 3.5, function(hud, test) test.state = "critical"; test.health = 110; hud._health:SetHealth(110, 525) end },
	{ 2, function(hud, test) test.state = "normal"; test.health = 420; hud._health:SetHealth(420, 525) end },
	{ 4, function(hud, test) test.state = "gloat"; hud._health:SetStreak(3); hud._crosshair:Hit(true) end },
	{ 2, function(hud, test) test.state = "dead"; hud._health:SetStreak(0); hud._health:SetHealth(0, 525) end },
}

function CombatHUD:_testStep(deltaTime: number)
	local test = self._test
	test.clock -= deltaTime
	if test.clock <= 0 then
		test.step = test.step % #TEST_STEPS + 1
		local step = TEST_STEPS[test.step]
		test.clock = step[1]
		step[2](self, test)
		self._abilities:Used(1)
		test.cooldown = 6
	end
	test.ult = (test.ult + deltaTime * 0.12) % 1.25
	self._abilities:SetUltimate(math.min(test.ult, 1))
	test.cooldown = math.max(test.cooldown - deltaTime, 0)
	self._abilities:SetCooldown(1, test.cooldown, 6)
	self._abilities:SetCooldown(2, math.max(test.cooldown - 3, 0), 6)
	self._abilities:SetCooldown(3, 0, 6)
	local ammo = 30 - math.floor((os.clock() * 4) % 31)
	self._weapon:SetAmmo(ammo, 30)
end

return CombatHUD
