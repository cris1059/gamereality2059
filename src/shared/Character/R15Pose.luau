--!strict

-- Procedural animation for standard R15 rigs that no player controls
-- (MORPHLAB preview, lobby line-up, city pedestrians): a breathing idle, a
-- simple walk cycle and held stances (LobbyConfig.Stances), written to each
-- joint's Motor6D.Transform on Step. Those rigs anchor only their
-- HumanoidRootPart, so the joints move the limbs.
--
-- Joint space (R15 rig attachments are axis-aligned): X pitch (+ = limb
-- forward / head up), Y yaw (+ = towards the character's left), Z roll (+ =
-- a right limb outward). Stance values are degrees.

local R15Pose = {}
R15Pose.__index = R15Pose

local JOINT_PARTS = table.freeze({
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	LeftShoulder = "LeftUpperArm",
	RightShoulder = "RightUpperArm",
	LeftElbow = "LeftLowerArm",
	RightElbow = "RightLowerArm",
	LeftHip = "LeftUpperLeg",
	RightHip = "RightUpperLeg",
	LeftKnee = "LeftLowerLeg",
	RightKnee = "RightLowerLeg",
})

local TAU = 2 * math.pi
-- Walk cycle: radians of phase per stud travelled, limb swing at full stride.
local PHASE_PER_STUD = 1.15
local LEG_SWING = 32
local KNEE_BEND = 48
local ARM_SWING = 28

export type R15Pose = typeof(setmetatable({} :: {
	_joints: { [string]: Motor6D },
	_time: number,
	_phase: number,
	_speed: number,
	_walk: number,
	_stance: any?,
	_fading: any?,
	_stanceBlend: number,
}, R15Pose))

function R15Pose.new(model: Model): R15Pose?
	local joints = {}
	for jointName, partName in JOINT_PARTS do
		local part = model:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(jointName)
		if motor and motor:IsA("Motor6D") then
			joints[jointName] = motor
		end
	end
	if not joints.Waist or not joints.Neck or not joints.RightShoulder or not joints.LeftShoulder then
		return nil
	end
	return setmetatable({
		_joints = joints,
		-- Random phase so a line-up never breathes in sync.
		_time = math.random() * 20,
		_phase = 0,
		_speed = 0,
		_walk = 0,
		_stance = nil,
		_fading = nil,
		_stanceBlend = 0,
	}, R15Pose)
end

-- Held posture (LobbyConfig.Stances entry); nil returns to the plain idle.
-- The previous stance is kept while it blends out, so clearing never snaps.
function R15Pose:SetStance(stance: any?)
	if stance then
		self._fading = stance
	end
	self._stance = stance
end

-- Walking speed in studs/s (0 = standing).
function R15Pose:SetLocomotion(speed: number)
	self._speed = math.max(speed, 0)
end

local function side(value: any, key: string): number
	return if type(value) == "table" then (value[key] or 0) else 0
end

function R15Pose:_set(name: string, x: number, y: number, z: number, lift: number?)
	local joint = self._joints[name]
	if joint then
		joint.Transform = CFrame.new(0, lift or 0, 0) * CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
	end
end

function R15Pose:Step(deltaTime: number)
	self._time += deltaTime
	local t = self._time
	local blend = 1 - math.exp(-8 * deltaTime)
	self._walk += ((if self._speed > 0.4 then 1 else 0) - self._walk) * blend
	self._stanceBlend += ((if self._stance then 1 else 0) - self._stanceBlend) * blend
	self._phase = (self._phase + deltaTime * self._speed * PHASE_PER_STUD) % TAU
	local walk = self._walk
	local idle = 1 - walk
	local held = self._stanceBlend * idle
	local stance = self._stance or self._fading or {}

	-- Idle: breathing, a slow sway and a drifting gaze.
	local breath = math.sin(t * TAU / 4.2)
	local sway = math.sin(t * TAU / 7)
	local gaze = math.sin(t * TAU / 9)
	-- Walk: legs and arms in opposition; the knee bends while the leg trails.
	local stride = math.clamp(self._speed / 14, 0.45, 1.4) * walk
	local swing = math.sin(self._phase)
	local bob = math.abs(math.cos(self._phase)) * 0.07 * stride

	self:_set("Root", 0, swing * 4 * stride, 0, bob)
	self:_set("Waist",
		breath * 1.2 * idle + (stance.chestPitch or 0) * held - 3 * stride,
		sway * 1.5 * idle + (stance.spineTwist or 0) * held - swing * 6 * stride,
		(stance.lean or 0) * held)
	self:_set("Neck",
		math.sin(t * TAU / 13) * 2 * idle + (stance.headPitch or 0) * held,
		gaze * 5 * idle + (stance.headYaw or 0) * held,
		(stance.headRoll or 0) * held)
	for _, entry in { { "Right", "r", 1 }, { "Left", "l", -1 } } do
		local prefix, key, sign = entry[1], entry[2], entry[3]
		local forward = side(stance.armForward, key) * held
		local raise = side(stance.armRaise, key) * held
		-- Arms folding inward (negative raise) also turn the forearm's bend
		-- plane inward, so folded arms cross in front of the chest.
		local inward = math.clamp(-raise, 0, 30) * 1.5
		local armSwing = -sign * swing * ARM_SWING * stride
		self:_set(prefix .. "Shoulder",
			forward + breath * 1.5 * idle + armSwing,
			sign * inward,
			sign * (4 * idle + raise))
		self:_set(prefix .. "Elbow", 8 * idle + side(stance.elbow, key) * held + 15 * stride, 0, 0)
		local legSwing = sign * swing * LEG_SWING * stride
		self:_set(prefix .. "Hip", legSwing, 0, sign * (stance.legSpread or 0) * held)
		self:_set(prefix .. "Knee", -math.max(0, -legSwing / LEG_SWING) * KNEE_BEND, 0, 0)
	end
end

-- Back to the rig's bind pose.
function R15Pose:Reset()
	for _, joint in self._joints do
		joint.Transform = CFrame.new()
	end
end

return R15Pose
