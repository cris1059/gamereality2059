--!strict

-- Progressive day/night for MODO LIBRE, entirely local: the clock comes from
-- the server epoch (runtime "DayCycleEpoch"), so every client sees the same
-- hour. Lighting, atmosphere, bloom and colour grade follow
-- FreeRoamConfig.LightingKeys; city windows glow only at night. Everything is
-- restored on Stop.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local DayCycle = require(ReplicatedStorage:WaitForChild("CyberpunkOnline").World.DayCycle)

local FreeRoamLighting = {}
FreeRoamLighting.__index = FreeRoamLighting

local LIGHTING_PROPERTIES = { "ClockTime", "Brightness", "Ambient", "OutdoorAmbient", "ExposureCompensation", "GlobalShadows", "FogEnd", "FogStart", "EnvironmentDiffuseScale", "EnvironmentSpecularScale" }
local ATMOSPHERE_PROPERTIES = { "Density", "Offset", "Color", "Decay", "Glare", "Haze" }

local function sample(keys, clock: number)
	for index = 1, #keys - 1 do
		local a, b = keys[index], keys[index + 1]
		if clock >= a.time and clock <= b.time then
			local t = (clock - a.time) / math.max(b.time - a.time, 1e-3)
			-- Ease so dawn and dusk linger a little.
			t = t * t * (3 - 2 * t)
			return {
				ambient = a.ambient:Lerp(b.ambient, t),
				outdoor = a.outdoor:Lerp(b.outdoor, t),
				brightness = a.brightness + (b.brightness - a.brightness) * t,
				fog = a.fog:Lerp(b.fog, t),
				haze = a.haze + (b.haze - a.haze) * t,
				density = a.density + (b.density - a.density) * t,
				tint = a.tint:Lerp(b.tint, t),
				exposure = a.exposure + (b.exposure - a.exposure) * t,
			}
		end
	end
	return keys[1]
end

function FreeRoamLighting.new(config, runtime: Instance)
	return setmetatable({
		_config = config,
		_runtime = runtime,
		_connection = nil,
		_saved = nil,
		_created = {},
		_disabledEffects = {},
		_atmosphere = nil,
		_bloom = nil,
		_grade = nil,
		_windows = {},
		_night = nil,
		-- GraphicsConfig profile: shadows, bloom and atmosphere scale.
		_quality = { shadows = true, bloom = 1, atmosphere = 1 },
	}, FreeRoamLighting)
end

-- Applies a graphics profile now (if running) and on the next Start.
function FreeRoamLighting:SetQuality(profile)
	self._quality = profile
	if self._connection then
		Lighting.GlobalShadows = profile.shadows
		if self._bloom then
			self._bloom.Intensity = self._config.Bloom.Intensity * profile.bloom
		end
	end
end

-- Current hour (0..24) shared by every client.
function FreeRoamLighting:GetClockTime(): number
	local cycle = self._config.DayCycle
	local epoch = self._runtime:GetAttribute("DayCycleEpoch")
	if type(epoch) ~= "number" then
		return DayCycle.ClockAt(cycle, DayCycle.ElapsedFor(cycle, cycle.StartClockTime))
	end
	return DayCycle.ClockAt(cycle, Workspace:GetServerTimeNow() - epoch)
end

function FreeRoamLighting:IsNight(clock: number?): boolean
	return DayCycle.IsNight(self._config.DayCycle, clock or self:GetClockTime())
end

function FreeRoamLighting:Start()
	if self._connection then
		return
	end
	local saved = { lighting = {}, atmosphere = nil }
	for _, property in LIGHTING_PROPERTIES do
		saved.lighting[property] = (Lighting :: any)[property]
	end
	self._saved = saved
	-- Other post effects (MORPHLAB / lobby) are switched off while roaming.
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") and child.Enabled then
			child.Enabled = false
			table.insert(self._disabledEffects, child)
		end
	end
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		local values = {}
		for _, property in ATMOSPHERE_PROPERTIES do
			values[property] = (atmosphere :: any)[property]
		end
		saved.atmosphere = { instance = atmosphere, values = values }
	else
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "FreeRoamAtmosphere"
		atmosphere.Parent = Lighting
		table.insert(self._created, atmosphere)
	end
	self._atmosphere = atmosphere
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "FreeRoamBloom"
	bloom.Intensity = self._config.Bloom.Intensity
	bloom.Size = self._config.Bloom.Size
	bloom.Threshold = self._config.Bloom.Threshold
	bloom.Parent = Lighting
	table.insert(self._created, bloom)
	self._bloom = bloom
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "FreeRoamGrade"
	grade.Saturation = 0.08
	grade.Contrast = 0.06
	grade.Parent = Lighting
	table.insert(self._created, grade)
	self._grade = grade
	Lighting.GlobalShadows = self._quality.shadows
	bloom.Intensity = self._config.Bloom.Intensity * self._quality.bloom
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6

	local city = Workspace:FindFirstChild(self._config.CityModelName, true)
	self._windows = {}
	if city then
		for _, descendant in city:GetDescendants() do
			if descendant:IsA("BasePart") and descendant:GetAttribute("CityWindow") then
				table.insert(self._windows, descendant)
			end
		end
	end
	self._night = nil
	self:_update()
	self._connection = RunService.Heartbeat:Connect(function()
		self:_update()
	end)
end

function FreeRoamLighting:_setWindows(night: boolean)
	for _, window in self._windows do
		if night then
			local glow = window:GetAttribute("GlowColor")
			window.Material = Enum.Material.Neon
			window.Color = if typeof(glow) == "Color3" then glow else Color3.new(1, 1, 1)
		else
			window.Material = Enum.Material.Glass
			window.Color = self._config.WindowDayColor
		end
	end
end

function FreeRoamLighting:_update()
	local clock = self:GetClockTime()
	local values = sample(self._config.LightingKeys, clock)
	Lighting.ClockTime = clock
	Lighting.Ambient = values.ambient
	Lighting.OutdoorAmbient = values.outdoor
	Lighting.Brightness = values.brightness
	Lighting.ExposureCompensation = values.exposure
	local atmosphere = self._atmosphere
	if atmosphere then
		atmosphere.Color = values.fog
		atmosphere.Decay = values.fog:Lerp(Color3.new(0, 0, 0), 0.4)
		atmosphere.Haze = values.haze
		atmosphere.Density = values.density * self._quality.atmosphere
		atmosphere.Offset = 0.1
		atmosphere.Glare = 0.2
	end
	if self._grade then
		self._grade.TintColor = values.tint
	end
	local night = self:IsNight(clock)
	if night ~= self._night then
		self._night = night
		self:_setWindows(night)
	end
end

function FreeRoamLighting:Stop()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	-- Windows go back to the glow the server gave them.
	self:_setWindows(true)
	self._windows = {}
	for _, instance in self._created do
		instance:Destroy()
	end
	self._created = {}
	self._bloom = nil
	for _, effect in self._disabledEffects do
		if effect.Parent then
			effect.Enabled = true
		end
	end
	self._disabledEffects = {}
	local saved = self._saved
	if saved then
		for property, value in saved.lighting do
			(Lighting :: any)[property] = value
		end
		if saved.atmosphere and saved.atmosphere.instance.Parent then
			for property, value in saved.atmosphere.values do
				(saved.atmosphere.instance :: any)[property] = value
			end
		end
	end
	self._saved = nil
	self._atmosphere = nil
	self._grade = nil
end

return FreeRoamLighting
