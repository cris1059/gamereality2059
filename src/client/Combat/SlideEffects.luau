--!strict

-- Slide effects for any character, driven each frame by ShooterAnimation with
-- its eased slide amount and SlidePose's track: neon sparks and a flicker of
-- light off the reaching heel, dust from the folded leg, a thump on landing
-- in the slide and a scrape that follows the speed. Built locally on each
-- client inside the character (it goes away with it); nothing replicates.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombatAudioConfig = require(ReplicatedStorage:WaitForChild("CyberpunkOnline").Config.CombatAudioConfig)

local SlideEffects = {}

local SPARK_TEXTURE = "rbxasset://textures/particles/fire_sparks_main.dds"
local DUST_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FULL_SPEED = 36
local SPARK_RATE = 70 -- a second at full speed
local DUST_RATE = 28
local MIN_SPEED = 7 -- below this nothing sparks or scrapes

type Rig = {
	sparks: ParticleEmitter,
	dust: ParticleEmitter,
	light: PointLight,
	scrape: Sound?,
	thump: Sound?,
	active: boolean,
}

local rigs: { [Model]: Rig } = setmetatable({}, { __mode = "k" }) :: any

local function newSound(config: any, parent: Instance, name: string, looped: boolean): Sound?
	if type(config) ~= "table" or type(config.id) ~= "string" then
		return nil
	end
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = config.id
	sound.Volume = 0
	sound.PlaybackSpeed = config.speed or 1
	sound.Looped = looped
	sound.RollOffMaxDistance = config.maxDistance or 90
	sound.Parent = parent
	return sound
end

local function build(character: Model): Rig?
	local heel = character:FindFirstChild("LeftFoot")
	local fold = character:FindFirstChild("RightFoot")
	local hips = character:FindFirstChild("LowerTorso")
	if not heel or not heel:IsA("BasePart") or not fold or not fold:IsA("BasePart") or not hips or not hips:IsA("BasePart") then
		return nil
	end
	-- Heel of the reaching foot (feet point along -Z, so the heel is +Z).
	local heelPoint = Instance.new("Attachment")
	heelPoint.Name = "SlideHeel"
	heelPoint.Position = Vector3.new(0, -heel.Size.Y / 2, heel.Size.Z * 0.35)
	heelPoint.Parent = heel
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "SlideSparks"
	sparks.Texture = SPARK_TEXTURE
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 225)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(0, 230, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 40, 200)),
	})
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new(0)
	sparks.Lifetime = NumberRange.new(0.12, 0.32)
	sparks.Speed = NumberRange.new(9, 18)
	sparks.SpreadAngle = Vector2.new(28, 40)
	sparks.Acceleration = Vector3.new(0, -45, 0)
	sparks.Drag = 2
	sparks.EmissionDirection = Enum.NormalId.Back -- behind the heel, away from the travel
	sparks.Rate = 0
	sparks.Parent = heelPoint
	local light = Instance.new("PointLight")
	light.Name = "SlideGlow"
	light.Color = Color3.fromRGB(0, 220, 255)
	light.Range = 7
	light.Brightness = 0
	light.Shadows = false
	light.Parent = heelPoint
	-- Dust where the folded leg meets the floor.
	local foldPoint = Instance.new("Attachment")
	foldPoint.Name = "SlideFold"
	foldPoint.Position = Vector3.new(0, -fold.Size.Y / 2, 0)
	foldPoint.Parent = fold
	local dust = Instance.new("ParticleEmitter")
	dust.Name = "SlideDust"
	dust.Texture = DUST_TEXTURE
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 158, 178))
	dust.LightInfluence = 1
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2.4) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.45, 0.9)
	dust.Speed = NumberRange.new(1.5, 4)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.Drag = 3
	dust.Acceleration = Vector3.new(0, 1.5, 0)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.Rate = 0
	dust.Parent = foldPoint
	local rig: Rig = {
		sparks = sparks,
		dust = dust,
		light = light,
		scrape = newSound(CombatAudioConfig.SlideScrape, hips, "SlideScrape", true),
		thump = newSound(CombatAudioConfig.SlideStart, hips, "SlideStart", false),
		active = false,
	}
	rigs[character] = rig
	return rig
end

-- `amount`: the character's eased slide (0..1); `speed`: its smoothed
-- horizontal speed; `time`: a running clock (light flicker).
function SlideEffects.update(character: Model, amount: number, speed: number, time: number)
	local rig = rigs[character]
	local sliding = amount > 0.5 and speed > MIN_SPEED
	if not rig then
		if not sliding then
			return
		end
		rig = build(character)
		if not rig then
			return
		end
	end
	local speedFactor = math.clamp(speed / FULL_SPEED, 0, 1)
	if sliding and not rig.active and rig.thump then
		rig.thump.Volume = (CombatAudioConfig.SlideStart :: any).volume or 0.5
		rig.thump:Play()
	end
	rig.active = sliding
	local strength = if sliding then amount * speedFactor else 0
	rig.sparks.Rate = SPARK_RATE * strength ^ 1.5
	rig.dust.Rate = DUST_RATE * strength
	rig.light.Brightness = if strength > 0.05 then strength * (1.6 + 0.9 * math.noise(time * 22, 1.7)) else 0
	local scrape = rig.scrape
	if scrape then
		local volume = ((CombatAudioConfig.SlideScrape :: any).volume or 0.3) * strength
		scrape.Volume = volume
		if volume > 0.01 and not scrape.IsPlaying then
			scrape:Play()
		elseif volume <= 0.01 and scrape.IsPlaying then
			scrape:Stop()
		end
	end
end

return SlideEffects
