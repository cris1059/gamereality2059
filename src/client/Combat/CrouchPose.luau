--!strict

-- Crouched stance and crouch walk for any character (ShooterAnimation blends
-- it in with the eased "crouch" amount; MovementController lowers the hips):
--   * legs by two-bone IK (LimbIK) onto the floor under them (one raycast per
--     foot, so steps and slopes work), knees out ahead;
--   * walking, each foot stays planted while the body passes over it, then
--     lifts and swings ahead (a real gait cycle driven by distance travelled,
--     so it never skates, whatever the speed);
--   * the hips turn a little towards the way you walk, tip forward, shift
--     and roll onto the standing leg and dip each step; the upper body rides
--     on them (CrouchPose.carry: all the dip and shift, part of the turn and
--     roll, plus a forward lean) so the body moves as one piece, while the
--     weapon keeps to the aim;
--   * standing still, a low ready stance, left foot ahead.
-- Driven by the root's motion, so remote players (whose velocity
-- replicates) get the same gait with no extra network data.

local Workspace = game:GetService("Workspace")

local LimbIK = require(script.Parent.LimbIK)

local CrouchPose = {}

local GAIT = table.freeze({
	cycle = 3.6, -- studs travelled per full gait cycle (two steps)
	stance = 0.6, -- share of the cycle each foot is planted
	lift = 0.1, -- studs a swinging foot rises
	fullSpeed = 9, -- crouch walk speed (MovementController SPEEDS.crouch)
	hipsLean = 4, -- degrees the hips tip forward
	maxYaw = math.rad(60), -- hips turn towards the walk up to this far (strafing)
	-- Sideways the blocky legs (a stud wide each) would cross: the steps get
	-- shorter and quicker and the feet further apart, up to these shares.
	sideStride = 0.45, -- shorter cycle
	sideWidth = 0.25, -- extra studs between the feet
	sway = 2, -- degrees of roll onto the standing leg
	shift = 0.07, -- studs the hips shift over the standing leg
	dip = 0.06, -- studs the hips dip at each footfall
	width = 0.2, -- extra studs between the feet
	knees = 0.12, -- how far out the knees point (0 = straight ahead)
	-- What the upper body takes from the hips (CrouchPose.carry).
	torsoLean = 4, -- same as hipsLean: the waist stays straight -- degrees the upper body leans forward
	carryRoll = 0.6, -- share of the hips' roll
	idleAhead = 0.4, -- standing: left foot this far ahead
	idleBehind = -0.3, -- and the right foot this far behind
	heelLift = 22, -- degrees the heel rises before leaving the floor
	toeUp = 14, -- degrees the toes rise mid-swing
	floorProbe = 3, -- studs below the hips to look for the floor
})

export type Track = {
	phase: number, -- 0..1 through the gait cycle
	walk: number, -- eased 0..1 share of walking (speed)
	yaw: number, -- turn from the facing towards the walk (radians)
	hipsYaw: number, -- the hips' actual turn (walk and stance), last apply
	travel: Vector3, -- eased direction of travel (flat unit)
	side: number, -- eased 0..1: how sideways the walk is to the legs
	time: number,
	params: RaycastParams?,
}

type Joint = Motor6D | AnimationConstraint

function CrouchPose.newTrack(): Track
	return { phase = 0, walk = 0, yaw = 0, hipsYaw = 0, travel = Vector3.new(0, 0, -1), side = 0, time = 0, params = nil }
end

local function wrap(angle: number): number
	return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function ease(rate: number, deltaTime: number): number
	return 1 - math.exp(-rate * deltaTime)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- Studs per gait cycle right now (shorter steps when walking sideways).
function CrouchPose.cycle(track: Track): number
	return GAIT.cycle * (1 - GAIT.sideStride * track.side)
end

-- Follows the root's motion every frame.
function CrouchPose.update(track: Track, rootPart: BasePart, deltaTime: number)
	local velocity = rootPart.AssemblyLinearVelocity
	local flat = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flat.Magnitude
	track.time += deltaTime
	track.walk += (math.clamp(speed / GAIT.fullSpeed, 0, 1) - track.walk) * ease(9, deltaTime)
	if speed > 0.6 then
		local direction = flat.Unit
		track.travel = (track.travel + (direction - track.travel) * ease(14, deltaTime))
		track.travel = if track.travel.Magnitude > 1e-3 then track.travel.Unit else direction
		track.phase = (track.phase + speed * deltaTime / CrouchPose.cycle(track)) % 1
		-- Hips towards the walk; backing up, towards its reverse.
		local look = rootPart.CFrame.LookVector
		local relative = wrap(math.atan2(-direction.X, -direction.Z) - math.atan2(-look.X, -look.Z))
		if math.abs(relative) > math.rad(110) then
			relative = wrap(relative - math.pi)
		end
		track.yaw += (math.clamp(relative, -GAIT.maxYaw, GAIT.maxYaw) - track.yaw) * ease(8, deltaTime)
		-- What is left over is walked sideways by the legs.
		track.side += (math.abs(math.sin(relative - track.hipsYaw)) - track.side) * ease(8, deltaTime)
	else
		track.yaw += (0 - track.yaw) * ease(5, deltaTime)
		track.side += (0 - track.side) * ease(5, deltaTime)
	end
end

local function floorBelow(track: Track, character: Model, point: Vector3, fallback: number): number
	local params = track.params
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = true
		track.params = params
	end
	local hit = Workspace:Raycast(point + Vector3.new(0, 0.6, 0), Vector3.new(0, -(GAIT.floorProbe + 0.6), 0), params)
	return if hit then hit.Position.Y else fallback
end

local function blend(joint: Joint, transform: CFrame, weight: number)
	joint.Transform = joint.Transform:Lerp(transform, weight)
end

-- The hips' roll (degrees), dip and sideways shift (studs) at this point
-- of the gait: over the standing leg (left planted in the first half).
local function gaitMotion(track: Track): (number, number, number)
	local cycle = track.phase * 2 * math.pi
	local walk = track.walk
	return GAIT.sway * math.sin(cycle) * walk,
		-GAIT.dip * (0.5 + 0.5 * math.cos(2 * cycle)) * walk,
		-GAIT.shift * math.sin(cycle) * walk
end

-- Where one foot goes this frame: offset along the walk and lift.
local function footStep(phase: number, cycle: number): (number, number, number)
	local half = cycle * GAIT.stance / 2
	if phase < GAIT.stance then
		-- Planted: slides back under the body exactly as fast as it moves.
		local s = phase / GAIT.stance
		local heel = math.clamp((s - 0.7) / 0.3, 0, 1)
		return half - 2 * half * s, 0, -GAIT.heelLift * heel
	end
	local q = (phase - GAIT.stance) / (1 - GAIT.stance)
	return -half + 2 * half * smooth(q), math.sin(math.pi * q) * GAIT.lift, GAIT.toeUp * math.sin(math.pi * q)
end

-- Poses hips and legs, `amount` (0..1) of the way into the crouch.
-- `stanceYaw`: the hips' turn standing still (radians; a rifle stance turns
-- the whole body towards the weapon, see ShooterAnimation), half of it kept
-- while walking.
-- `tilt`: extra turn of the hips (the upper body's lean towards the aim),
-- so the waist itself hardly bends (layered clothing: see ShooterAnimation).
function CrouchPose.apply(track: Track, character: Model, joints: { [string]: Joint }, rootPart: BasePart, amount: number, stanceYaw: number, tilt: CFrame)
	if amount < 0.01 then
		return
	end
	local root = joints.Root
	if not root then
		return
	end
	local legs = {
		{ hip = joints.LeftHip, knee = joints.LeftKnee, ankle = joints.LeftAnkle, side = -1, offset = 0, idle = GAIT.idleAhead },
		{ hip = joints.RightHip, knee = joints.RightKnee, ankle = joints.RightAnkle, side = 1, offset = 0.5, idle = GAIT.idleBehind },
	}
	for _, leg in legs do
		if not leg.hip or not leg.knee or not leg.ankle then
			return
		end
	end
	local walk = track.walk
	-- Against the stance's turn (strafing left in a right-handed stance) the
	-- hips turn less, so the upper body (which keeps to the stance) can follow
	-- them without twisting the waist.
	local hipsYaw = math.clamp(walk * track.yaw + stanceYaw * (1 - 0.5 * walk), -GAIT.maxYaw + math.max(stanceYaw, 0), GAIT.maxYaw + math.min(stanceYaw, 0))
	track.hipsYaw = hipsYaw
	local roll, dip, shift = gaitMotion(track)
	-- Hips: towards the walk, tipped forward, over and onto the standing leg,
	-- dipping as each foot lands.
	local hips = CFrame.new(shift, dip, 0) * CFrame.Angles(0, hipsYaw, 0) * tilt * CFrame.Angles(math.rad(-GAIT.hipsLean), 0, math.rad(roll))
	blend(root, hips, amount)
	local lowerTorso = LimbIK.childFrame(rootPart.CFrame, root, root.Transform)
	-- Legs' heading: the facing turned by the hips' yaw, flat.
	local facing = rootPart.CFrame * CFrame.Angles(0, hipsYaw, 0)
	local forward = Vector3.new(facing.LookVector.X, 0, facing.LookVector.Z)
	forward = if forward.Magnitude > 1e-3 then forward.Unit else Vector3.new(0, 0, -1)
	local right = forward:Cross(Vector3.yAxis)
	local travel = track.travel
	local rootFloor = rootPart.Position.Y - rootPart.Size.Y / 2 - 2
	for _, leg in legs do
		local hip, knee, ankle = leg.hip :: Joint, leg.knee :: Joint, leg.ankle :: Joint
		local hipPoint = (lowerTorso * hip.C0).Position
		local foot = ankle.Parent
		local ankleHeight = ankle.C1.Position.Y + (if foot and foot:IsA("BasePart") then foot.Size.Y / 2 else 0.15)
		local along, lift, pitch = footStep((track.phase + leg.offset) % 1, CrouchPose.cycle(track))
		-- Blend the idle stance (along the facing) with the gait (along the walk).
		local flatHip = Vector3.new(hipPoint.X, 0, hipPoint.Z)
		local target = flatHip + right * (leg.side * (GAIT.width + GAIT.sideWidth * track.side)) + forward * (leg.idle * (1 - walk)) + travel * (along * walk)
		local floorY = floorBelow(track, character, Vector3.new(target.X, hipPoint.Y, target.Z), rootFloor)
		-- A rising heel turns the foot about its toes (so they stay on the floor).
		local halfLength = if foot and foot:IsA("BasePart") then foot.Size.Z / 2 else 0.5
		local heelRaise = if pitch < 0 then halfLength * math.sin(math.rad(-pitch * walk)) else 0
		local anklePoint = Vector3.new(target.X, floorY + ankleHeight + lift * walk + heelRaise, target.Z)
		-- Foot flat on the floor facing the legs' heading, heel / toes per the step.
		local footRotation = CFrame.lookAt(Vector3.zero, forward) * CFrame.Angles(math.rad(pitch * walk), 0, 0)
		local footFrame = CFrame.new(anklePoint) * footRotation * ankle.C1:Inverse()
		local pole = forward + right * (leg.side * GAIT.knees)
		local hipT, kneeT, ankleT = LimbIK.solve(lowerTorso, hip, knee, ankle, anklePoint, pole, footFrame, 0)
		blend(hip, hipT, amount)
		blend(knee, kneeT, amount)
		blend(ankle, ankleT, amount)
	end
end

-- How the upper body rides on the hips' step in the crouch, as a Transform
-- for the root joint at rest (ShooterAnimation builds the weapon's anchor on
-- it): all of the dip and shift, part of the roll (its turn is worked out
-- in ShooterAnimation with the stance). In first person the roll stays out
-- (it would swing the weapon across the view).
function CrouchPose.carry(track: Track, amount: number, firstPerson: number): CFrame
	if amount < 0.01 then
		return CFrame.identity
	end
	local roll, dip, shift = gaitMotion(track)
	local outside = 1 - firstPerson
	return CFrame.new(shift * amount, dip * amount, 0)
		* CFrame.Angles(0, 0, math.rad(roll * GAIT.carryRoll) * amount * outside)
end

-- Forward lean of the upper body in the crouch (degrees, positive forward).
function CrouchPose.torsoLean(amount: number): number
	return GAIT.torsoLean * amount
end

return CrouchPose
