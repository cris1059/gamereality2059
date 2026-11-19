--!strict

-- Lower-body pose for a slide (MovementController starts it; ShooterAnimation
-- blends it in with the character's eased "slide" amount, for every player):
--   * the hips tip back, the left leg reaches out ahead nearly straight (toes
--     up, the knee bending as the slide runs out of speed) and the right leg
--     folds under the body;
--   * the hips and legs point where the character is actually sliding, which
--     may not be where it looks (the upper body keeps facing the aim: see the
--     waist in ShooterAnimation), and the whole body leans into a turn;
--   * a light judder from the ground, stronger the faster the slide.
-- Everything comes from the root part's motion, so remote players (whose
-- velocity replicates) are posed the same way with no extra network data.

local SlidePose = {}

local POSE = table.freeze({
	pelvisBack = 30, -- degrees the hips tip back
	torsoBack = 22, -- the upper body (and weapon) leans back this much (close to the hips: a bent waist opens the clothing)
	maxYaw = math.rad(100), -- legs turn towards the slide up to this far from the facing
	rollPerTurn = 0.07, -- degrees of lean per degree a second of turning
	maxRoll = 18,
	torsoRollShare = 0.45, -- share of the lean the upper body takes
	cameraRollShare = 0.3, -- share of the lean the local camera takes
	judder = 1.1, -- degrees of ground judder at full speed
	fullSpeed = 36, -- studs a second (MovementController's slide start speed)
	lead = table.freeze({ hip = 64, knee = -6, kneeSlow = -40, ankle = 24, splay = -7 }),
	trail = table.freeze({ hip = 54, knee = -160, ankle = -15, splay = 34 }),
})

export type Track = {
	heading: number?, -- world direction of travel (radians), last frame
	yaw: number, -- legs' turn from the facing towards the travel (radians)
	turn: number, -- smoothed turning rate (degrees a second, + = left)
	roll: number, -- smoothed lean into the turn (degrees)
	speed: number, -- smoothed horizontal speed
	time: number,
}

type Joint = Motor6D | AnimationConstraint

function SlidePose.newTrack(): Track
	return { heading = nil, yaw = 0, turn = 0, roll = 0, speed = 0, time = 0 }
end

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function ease(rate: number, deltaTime: number): number
	return 1 - math.exp(-rate * deltaTime)
end

-- Follows the root's motion every frame (sliding or not, so a slide starts
-- from the right heading).
function SlidePose.update(track: Track, rootPart: BasePart, deltaTime: number)
	local velocity = rootPart.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	track.speed += (speed - track.speed) * ease(10, deltaTime)
	track.time += deltaTime
	local rate = 0
	if speed > 3 then
		local heading = math.atan2(-flat.X, -flat.Z)
		if track.heading and deltaTime > 1e-4 then
			rate = math.deg(wrap(heading - track.heading)) / deltaTime
		end
		track.heading = heading
		local look = rootPart.CFrame.LookVector
		local relative = math.clamp(wrap(heading - math.atan2(-look.X, -look.Z)), -POSE.maxYaw, POSE.maxYaw)
		track.yaw += (relative - track.yaw) * ease(14, deltaTime)
	else
		track.heading = nil
		track.yaw += (0 - track.yaw) * ease(6, deltaTime)
	end
	track.turn += (math.clamp(rate, -720, 720) - track.turn) * ease(8, deltaTime)
	local roll = math.clamp(track.turn * POSE.rollPerTurn, -POSE.maxRoll, POSE.maxRoll)
	track.roll += (roll - track.roll) * ease(10, deltaTime)
end

local function blend(joint: Joint?, transform: CFrame, weight: number)
	if joint then
		joint.Transform = joint.Transform:Lerp(transform, weight)
	end
end

-- Poses hips and legs, `amount` (0..1) of the way into the slide.
function SlidePose.apply(track: Track, joints: { [string]: Joint }, amount: number)
	if amount < 0.01 then
		return
	end
	local speedFactor = math.clamp(track.speed / POSE.fullSpeed, 0, 1)
	local judder = POSE.judder * speedFactor
	local t = track.time
	local pitchJudder = math.noise(t * 14, 0.37) * judder
	local rollJudder = math.noise(t * 14, 7.13) * judder
	blend(joints.Root, CFrame.Angles(0, track.yaw, 0) * angles(POSE.pelvisBack + pitchJudder, 0, track.roll + rollJudder), amount)
	local lead, trail = POSE.lead, POSE.trail
	-- The reaching leg swings a little to the outside of a turn.
	blend(joints.LeftHip, angles(lead.hip, 0, lead.splay - track.roll * 0.4), amount)
	blend(joints.LeftKnee, angles(lead.kneeSlow + (lead.knee - lead.kneeSlow) * speedFactor, 0, 0), amount)
	blend(joints.LeftAnkle, angles(lead.ankle, 0, 0), amount)
	blend(joints.RightHip, angles(trail.hip, 0, trail.splay), amount)
	blend(joints.RightKnee, angles(trail.knee, 0, 0), amount)
	blend(joints.RightAnkle, angles(trail.ankle, 0, 0), amount)
end

-- Upper body (and weapon) lean in the slide: pitch back (degrees) and roll
-- into the turn (radians).
function SlidePose.torso(track: Track, amount: number): (number, number)
	return POSE.torsoBack * amount, math.rad(track.roll * POSE.torsoRollShare) * amount
end

-- Local camera roll into the turn (radians).
function SlidePose.cameraRoll(track: Track, amount: number): number
	return math.rad(track.roll * POSE.cameraRollShare) * amount
end

return SlidePose
