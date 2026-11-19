--!strict

-- Procedural reload choreography, driven by ShooterAnimation for every
-- character (each client animates everyone; nothing here replicates).
-- Over the weapon's reloadSeconds the left hand:
--   0.00-0.15  goes to the magazine
--   0.15-0.30  pulls it out and lets it fall (a local copy drops with physics)
--   0.30-0.52  reaches the belt and takes a fresh one
--   0.52-0.74  brings it up and seats it
--   0.74-0.88  pulls the charging handle back and lets it snap forward
--   0.88-1.00  returns under the barrel.
-- Weapons built with a MagJoint / BoltJoint Motor6D (WeaponModels) also move
-- those parts; any other weapon gets the same hand motion over guessed points.

-- Show (all clients, for every character): the weapon rolls to present the
-- magazine well, the empty magazine spins away and its neon dies out, sparks
-- fly when the new one seats, every neon strip flashes when the bolt snaps
-- forward, and each step has a sound cue (CombatAudioConfig).

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local WeaponStats = require(root.Combat.WeaponStats)
local CombatAudio = require(root.Config.CombatAudioConfig)

local ReloadAnimation = {}

local DROP_LIFETIME = 5
local BOLT_TRAVEL = 0.3 -- studs the charging handle travels back
local SLIDE_TRAVEL = 0.17 -- studs a pistol's slide travels back
local ROLL_DEGREES = -35 -- weapon roll while the magazine is swapped
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPARK_COLORS = ColorSequence.new(Color3.fromRGB(120, 240, 255), Color3.fromRGB(255, 60, 200))
local DEAD_NEON = Color3.fromRGB(45, 12, 35)

-- Moments of the reload (fraction of it) that trigger effects.
local EVENTS = table.freeze({
	{ 0.17, "magOut" },
	{ 0.30, "drop" },
	{ 0.74, "magIn" },
	{ 0.80, "boltBack" },
	{ 0.86, "boltRelease" },
})

export type Track = {
	tool: Tool?,
	started: number?,
	duration: number,
	dropped: boolean,
	hidden: { [BasePart]: number },
	lastT: number,
	events: { string }, -- effects fired this frame (ShooterAnimation reads them)
	warp: { { number } }?, -- real fraction -> choreography fraction (own reload sound)
	sound: Sound?, -- the weapon's own reload sound, while it plays
}

export type Context = {
	tool: Tool,
	gripFrame: CFrame, -- where the weapon's grip is this frame (after the tilt)
	support: CFrame, -- the left hand's normal place under the barrel
	lowerTorso: CFrame,
	length: number,
	pistol: boolean,
	velocity: Vector3,
}

-- Choreography moments the weapon's own reload sound is lined up with
-- (CombatAudioConfig.Weapons[...].reload.marks).
local MARK_MOMENTS = table.freeze({
	{ "magOut", 0.17 }, { "magIn", 0.74 }, { "boltBack", 0.80 }, { "boltRelease", 0.86 },
})

local function weaponReload(tool: Tool): any?
	local sounds = (CombatAudio :: any).Weapons and (CombatAudio :: any).Weapons[tool.Name]
	local reload = sounds and sounds.reload
	return if reload and reload.id then reload else nil
end

-- Piecewise-linear map from the real reload fraction to the choreography's,
-- so its moments land on the sound's marks (seconds) within `duration`.
local function buildWarp(marks: any, duration: number): { { number } }?
	local points = { { 0, 0 } }
	for _, entry in MARK_MOMENTS do
		local at = marks[entry[1]]
		if type(at) ~= "number" then
			return nil
		end
		local real = math.clamp(at / duration, 0, 0.98)
		if real <= points[#points][1] then
			return nil
		end
		table.insert(points, { real, entry[2] })
	end
	table.insert(points, { 1, 1 })
	return points
end

local function warped(points: { { number } }, t: number): number
	if t >= 1 then
		return t
	end
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		if t <= b[1] then
			return a[2] + (t - a[1]) / (b[1] - a[1]) * (b[2] - a[2])
		end
	end
	return t
end

function ReloadAnimation.newTrack(): Track
	return { tool = nil, started = nil, duration = 1, dropped = false, hidden = {}, lastT = -1, events = {} }
end

local function smooth(t: number, from: number, to: number): number
	local x = math.clamp((t - from) / (to - from), 0, 1)
	return x * x * (3 - 2 * x)
end

-- 0 -> 1 -> 0 over [at, at + width].
local function bump(t: number, at: number, width: number): number
	local x = (t - at) / width
	return if x > 0 and x < 1 then math.sin(x * math.pi) else 0
end

local function playCue(parent: Instance, cue: any)
	if not CombatAudio.Enabled or not cue then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "ReloadCue"
	sound.SoundId = cue.id
	sound.Volume = cue.volume
	sound.PlaybackSpeed = cue.speed
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = cue.maxDistance or 45
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 2)
end

-- Each neon part's own colour, so overlapping flashes always fade back to it.
local neonColors: { [BasePart]: Color3 } = setmetatable({}, { __mode = "k" }) :: any

local function flashNeon(parts: { Instance })
	for _, part in parts do
		if part:IsA("BasePart") and part.Material == Enum.Material.Neon then
			local base = neonColors[part] or part.Color
			neonColors[part] = base
			part.Color = Color3.new(1, 1, 1)
			TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Color = base }):Play()
		end
	end
end

local function sparks(parent: BasePart, position: Vector3, direction: Vector3)
	local attachment = Instance.new("Attachment")
	attachment.Parent = parent
	attachment.WorldCFrame = CFrame.lookAt(position, position + direction) * CFrame.Angles(math.rad(-90), 0, 0)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = SPARK_TEXTURE
	emitter.Color = SPARK_COLORS
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
	emitter.Lifetime = NumberRange.new(0.15, 0.35)
	emitter.Speed = NumberRange.new(4, 9)
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Drag = 5
	emitter.Rate = 0
	emitter.Enabled = false
	emitter.Parent = attachment
	emitter:Emit(18)
	Debris:AddItem(attachment, 1)
end

local function joint(tool: Tool, name: string): Motor6D?
	local found = tool:FindFirstChild(name, true)
	return if found and found:IsA("Motor6D") and found.Part1 then found else nil
end

-- The magazine part and everything welded onto it (its neon strip).
local function magazineParts(tool: Tool, motor: Motor6D): { BasePart }
	local magazine = motor.Part1 :: BasePart
	local parts = { magazine }
	for _, descendant in tool:GetDescendants() do
		if descendant:IsA("WeldConstraint") and descendant.Part0 == magazine and descendant.Part1 then
			table.insert(parts, descendant.Part1)
		end
	end
	return parts
end

local function setHidden(track: Track, tool: Tool, motor: Motor6D, hidden: boolean)
	if hidden then
		for _, part in magazineParts(tool, motor) do
			if track.hidden[part] == nil then
				track.hidden[part] = part.Transparency
				part.Transparency = 1
			end
		end
	else
		for part, transparency in track.hidden do
			part.Transparency = transparency
		end
		table.clear(track.hidden)
	end
end

-- Puts the weapon's moving parts back and clears the track.
function ReloadAnimation.reset(track: Track)
	local tool = track.tool
	if tool then
		for _, name in { "MagJoint", "BoltJoint" } do
			local motor = joint(tool, name)
			if motor then
				motor.Transform = CFrame.identity
			end
		end
	end
	for part, transparency in track.hidden do
		part.Transparency = transparency
	end
	table.clear(track.hidden)
	if track.sound then
		track.sound:Destroy()
		track.sound = nil
	end
	track.warp = nil
	track.tool = nil
	track.started = nil
	track.dropped = false
	track.lastT = -1
	table.clear(track.events)
end

-- Reload progress 0..1 (past 1 while still waiting on the server), or nil
-- when this character is not reloading. Starts and resets the track.
function ReloadAnimation.progress(track: Track, reloading: boolean, tool: Tool?): number?
	if not reloading or not tool then
		if track.started or track.tool then
			ReloadAnimation.reset(track)
		end
		return nil
	end
	if track.tool ~= tool then
		ReloadAnimation.reset(track)
	end
	if not track.started then
		track.tool = tool
		track.started = os.clock()
		track.duration = math.max(WeaponStats.Get(tool).reloadSeconds, 0.3)
		track.dropped = false
		track.lastT = -1
		-- The weapon's own reload sound: from the start, with the
		-- choreography re-timed onto its marks.
		local reload = weaponReload(tool)
		if reload and CombatAudio.Enabled then
			track.warp = buildWarp(reload.marks or {}, track.duration)
			local handle = tool:FindFirstChild("Handle")
			local sound = Instance.new("Sound")
			sound.Name = "ReloadSound"
			sound.SoundId = reload.id
			sound.Volume = reload.volume or 0.8
			sound.RollOffMinDistance = 4
			sound.RollOffMaxDistance = reload.maxDistance or 80
			sound.Parent = if handle and handle:IsA("BasePart") then handle else tool
			sound:Play()
			track.sound = sound
		end
	end
	local t = (os.clock() - (track.started :: number)) / track.duration
	return if track.warp then warped(track.warp, t) else t
end

-- How much of the "weapon tipped down" pose to use: full until the bolt is
-- released, then back to the normal hold.
function ReloadAnimation.tilt(t: number?): number
	if not t then
		return 1
	end
	return 1 - smooth(t, 0.86, 1.0)
end

-- Roll of the weapon (0..1 of ROLL_DEGREES) to present the magazine well.
function ReloadAnimation.roll(t: number?): number
	if not t then
		return 0
	end
	return smooth(t, 0.04, 0.14) * (1 - smooth(t, 0.74, 0.84))
end

function ReloadAnimation.rollRadians(): number
	return math.rad(ROLL_DEGREES)
end

-- A short upward jolt of the weapon when the magazine seats and when the bolt
-- slams home (0..1).
function ReloadAnimation.jolt(t: number?): number
	if not t then
		return 0
	end
	return math.max(bump(t, 0.74, 0.05), bump(t, 0.86, 0.05))
end

local function dropMagazine(tool: Tool, motor: Motor6D, velocity: Vector3, down: Vector3, left: Vector3)
	local parts = magazineParts(tool, motor)
	local magazine = parts[1]
	local copies: { BasePart } = {}
	for _, part in parts do
		local copy = part:Clone()
		for _, child in copy:GetChildren() do
			if child:IsA("JointInstance") or child:IsA("WeldConstraint") then
				child:Destroy()
			end
		end
		copy.CFrame = part.CFrame
		copy.Anchored = false
		copy.Massless = false
		copy.CanCollide = part == magazine
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Transparency = 0
		table.insert(copies, copy)
	end
	local main = copies[1]
	for index = 2, #copies do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = main
		weld.Part1 = copies[index]
		weld.Parent = copies[index]
	end
	local holder = Instance.new("Model")
	holder.Name = "CargadorSuelto"
	for _, copy in copies do
		copy.Parent = holder
	end
	holder.Parent = Workspace
	-- Flicked out to the left with a spin, so it lands in view beside the player.
	main.AssemblyLinearVelocity = velocity + down * 3 + left * 7 + Vector3.yAxis * 3
	main.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit * 14
	-- Its neon dies out, then the whole magazine fades away.
	for _, copy in copies do
		if copy.Material == Enum.Material.Neon then
			TweenService:Create(copy, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4), { Color = DEAD_NEON }):Play()
			task.delay(1.8, function()
				if copy.Parent then
					copy.Material = Enum.Material.SmoothPlastic
				end
			end)
		end
		TweenService:Create(copy, TweenInfo.new(0.8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, DROP_LIFETIME - 1), { Transparency = 1 }):Play()
	end
	Debris:AddItem(holder, DROP_LIFETIME)
end

-- Sound, sparks and flashes for one reload event.
local function fire(event: string, tool: Tool, magJoint: Motor6D?, seatedTop: Vector3, up: Vector3)
	local handle = tool:FindFirstChild("Handle")
	if not handle or not handle:IsA("BasePart") then
		return
	end
	-- A weapon with its own reload sound already has every clack in it.
	if weaponReload(tool) then
		if event == "magIn" then
			sparks(handle, seatedTop, -up)
			if magJoint then
				flashNeon(magazineParts(tool, magJoint))
			end
		elseif event == "boltRelease" then
			flashNeon(tool:GetDescendants())
		end
		return
	end
	if event == "magOut" then
		playCue(handle, CombatAudio.MagOut)
	elseif event == "magIn" then
		playCue(handle, CombatAudio.MagIn)
		sparks(handle, seatedTop, -up)
		if magJoint then
			flashNeon(magazineParts(tool, magJoint))
		end
	elseif event == "boltBack" then
		playCue(handle, CombatAudio.BoltBack)
	elseif event == "boltRelease" then
		playCue(handle, CombatAudio.BoltRelease)
		flashNeon(tool:GetDescendants())
	end
end

-- Where the left hand goes at time t (a world frame), driving the magazine
-- and charging handle on the way. Nil once the choreography is over.
function ReloadAnimation.leftHand(track: Track, t: number, context: Context): CFrame?
	if t >= 1 then
		return nil
	end
	local tool = context.tool
	local grip = context.gripFrame
	local barrel, up = grip.LookVector, grip.UpVector
	local handle = tool:FindFirstChild("Handle")
	local handleFrame = grip * tool.Grip:Inverse()
	local magJoint = joint(tool, "MagJoint")
	local boltJoint = joint(tool, "BoltJoint")

	-- Key points (world).
	local magRest: CFrame
	if magJoint then
		magRest = handleFrame * magJoint.C0 * magJoint.C1:Inverse()
	elseif context.pistol then
		magRest = grip * CFrame.new(0, -0.3, 0.05)
	else
		magRest = grip * CFrame.new(0, -0.25, -context.length * 0.2)
	end
	local seated = magRest.Position - up * (if context.pistol then 0.15 else 0.2)
	local out = seated - up * (if context.pistol then 0.4 else 0.55) + barrel * 0.1
	local belt = (context.lowerTorso * CFrame.new(-0.55, -0.05, -0.45)).Position
	local bolt: Vector3
	if boltJoint then
		bolt = (handleFrame * boltJoint.C0 * boltJoint.C1:Inverse()).Position
	elseif context.pistol then
		bolt = (grip * CFrame.new(0, 0.32, 0.15)).Position
	else
		bolt = (grip * CFrame.new(0.2, 0.25, -0.6)).Position
	end
	local travel = if context.pistol then SLIDE_TRAVEL else BOLT_TRAVEL
	if context.pistol and boltJoint then
		-- A pistol is racked by the rear of its slide (the serrations).
		bolt -= barrel * (context.length * 0.3)
	end
	local boltBack = bolt - barrel * travel
	local support = context.support.Position

	-- Hand path.
	local segments = {
		{ 0.00, 0.15, support, seated },
		{ 0.15, 0.30, seated, out },
		{ 0.30, 0.48, out, belt },
		{ 0.48, 0.52, belt, belt },
		{ 0.52, 0.66, belt, out },
		{ 0.66, 0.74, out, seated },
		{ 0.74, 0.80, seated, bolt },
		{ 0.80, 0.86, bolt, boltBack },
		{ 0.86, 0.95, boltBack, support },
	}
	local point = support
	for _, segment in segments do
		local from, to = segment[1] :: number, segment[2] :: number
		if t < to or segment == segments[#segments] then
			point = (segment[3] :: Vector3):Lerp(segment[4] :: Vector3, smooth(t, from, to))
			break
		end
	end
	-- Same palm-under-the-barrel orientation as the normal support hold.
	local hand = CFrame.lookAt(point, point + barrel, up) * CFrame.Angles(0, 0, math.rad(-80))

	-- Magazine: in the hand while it travels, gone between drop and belt.
	if magJoint and handle and handle:IsA("BasePart") then
		local carried = (t >= 0.15 and t < 0.30) or (t >= 0.48 and t < 0.74)
		local world = if carried then CFrame.new(point + (magRest.Position - seated)) * magRest.Rotation else magRest
		magJoint.Transform = magJoint.C0:Inverse() * handleFrame:Inverse() * world * magJoint.C1
	end
	-- Effects for the moments crossed since the last frame.
	table.clear(track.events)
	for _, entry in EVENTS do
		local at, event = entry[1] :: number, entry[2] :: string
		if track.lastT < at and t >= at then
			table.insert(track.events, event)
			if event == "drop" then
				if magJoint and not track.dropped then
					track.dropped = true
					dropMagazine(tool, magJoint, context.velocity, -up, -grip.RightVector)
				end
			else
				fire(event, tool, magJoint, seated + up * 0.35, up)
			end
		end
	end
	track.lastT = t
	if magJoint then
		setHidden(track, tool, magJoint, t >= 0.30 and t < 0.48)
	end
	-- Charging handle: back with the hand, then snaps forward on release.
	if boltJoint then
		local pull = if t < 0.86 then smooth(t, 0.80, 0.86) else 1 - smooth(t, 0.86, 0.88)
		local world = handleFrame * boltJoint.C0 * boltJoint.C1:Inverse()
		world = CFrame.new(world.Position - barrel * travel * pull) * world.Rotation
		boltJoint.Transform = boltJoint.C0:Inverse() * handleFrame:Inverse() * world * boltJoint.C1
	end
	return hand
end

return ReloadAnimation
