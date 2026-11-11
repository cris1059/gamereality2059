--!strict

-- Animates the city dressing built by CityDressingService: screen gradients
-- scroll slowly, screens flicker now and then, and tower windows light up at
-- night (SurfaceGui.LightInfluence 0 = self-lit) on the shared day/night
-- clock. Elements are found by the CollectionService tag in
-- CityDressingConfig.FxTag (works with streaming).

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local Config = require(root.Config.CityDressingConfig)
local FreeRoamConfig = require(root.Config.FreeRoamConfig)
local DayCycle = require(root.World.DayCycle)

local CityDressingFX = {}

local gradients: { [UIGradient]: number } = {}
local screens: { [SurfaceGui]: { base: number, next: number, endsAt: number } } = {}
local windows: { [SurfaceGui]: boolean } = {}
local random = Random.new()
local connection: RBXScriptConnection? = nil
local night: boolean? = nil
local nextNightCheck = 0

local function applyWindow(gui: SurfaceGui)
	gui.LightInfluence = if night then 0 else 1
	gui.Brightness = if night then 1.2 else 1
end

local function track(instance: Instance)
	if instance:IsA("UIGradient") then
		gradients[instance] = random:NextNumber(0, 1)
	elseif instance:IsA("SurfaceGui") and instance:GetAttribute("Fx") == "windows" then
		windows[instance] = true
		applyWindow(instance)
	elseif instance:IsA("SurfaceGui") then
		screens[instance] = { base = instance.Brightness, next = os.clock() + random:NextNumber(2, 12), endsAt = 0 }
	end
end

local function untrack(instance: Instance)
	gradients[instance :: any] = nil
	screens[instance :: any] = nil
	windows[instance :: any] = nil
end

local function isNight(): boolean
	local runtime = root:FindFirstChild("Runtime")
	local epoch = runtime and runtime:GetAttribute("DayCycleEpoch")
	local cycle = FreeRoamConfig.DayCycle
	local clock = if type(epoch) == "number"
		then DayCycle.ClockAt(cycle, Workspace:GetServerTimeNow() - epoch)
		else cycle.StartClockTime
	return DayCycle.IsNight(cycle, clock)
end

function CityDressingFX.Start()
	if connection then
		return
	end
	for _, instance in CollectionService:GetTagged(Config.FxTag) do
		track(instance)
	end
	CollectionService:GetInstanceAddedSignal(Config.FxTag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(Config.FxTag):Connect(untrack)
	connection = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		for gradient, phase in gradients do
			gradient.Offset = Vector2.new(0, math.sin(now * 0.35 + phase * 6.28) * 0.35)
		end
		for gui, state in screens do
			if now >= state.next then
				state.endsAt = now + random:NextNumber(0.05, 0.25)
				state.next = now + random:NextNumber(4, 16)
			end
			gui.Brightness = if now < state.endsAt then state.base * random:NextNumber(0.2, 0.6) else state.base
		end
		if now >= nextNightCheck then
			nextNightCheck = now + 1
			local current = isNight()
			if current ~= night then
				night = current
				for gui in windows do
					applyWindow(gui)
				end
			end
		end
	end)
end

return CityDressingFX
