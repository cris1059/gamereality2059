--!strict

-- Joint frame helpers and a two-bone IK solver for R15 limbs, shared by the
-- arm (ShooterAnimation) and leg (CrouchPose) poses.

local LimbIK = {}

-- Shortest rotation taking unit vector a onto unit vector b.
function LimbIK.between(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-6 then
		return if dot > 0 then CFrame.identity else CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Child part frame for a joint: Part1 = Part0 * C0 * Transform * C1^-1.
function LimbIK.childFrame(parent: CFrame, motor: Motor6D | AnimationConstraint, transform: CFrame): CFrame
	return parent * motor.C0 * transform * motor.C1:Inverse()
end

-- The Transform that puts Part1 at `frame` (rotation only; the joint stays put).
function LimbIK.transformFor(parent: CFrame, motor: Motor6D | AnimationConstraint, frame: CFrame): CFrame
	return ((parent * motor.C0):Inverse() * frame * motor.C1).Rotation
end

-- Two-bone IK for one limb (arm: shoulder / elbow / wrist; leg: hip / knee
-- / ankle): root joint on `torso` (the parent part's frame), end joint at
-- `wrist`, middle joint bent towards `pole`, end part turned to `hand` (a
-- world frame for the hand or foot). Returns the three Transforms.
-- `slide` (studs): up to how much of any distance beyond the arm's reach is
-- made up by sliding the whole arm out of the shoulder towards the wrist, so
-- the hand still gets there (any amount in first person, where the upper arm
-- is not drawn; a little from outside, hidden by the turned shoulder).
function LimbIK.solve(torso: CFrame, shoulder: Motor6D | AnimationConstraint, elbow: Motor6D | AnimationConstraint, wristMotor: Motor6D | AnimationConstraint, wrist: Vector3, pole: Vector3, hand: CFrame, slide: number): (CFrame, CFrame, CFrame)
	local upperRest = LimbIK.childFrame(torso, shoulder, CFrame.identity)
	local shoulderPoint = (torso * shoulder.C0).Position
	local upperLength = (elbow.C0.Position - shoulder.C1.Position).Magnitude
	local lowerLength = (wristMotor.C0.Position - elbow.C1.Position).Magnitude
	local toWrist = wrist - shoulderPoint
	local excess = toWrist.Magnitude - (upperLength + lowerLength - 0.02)
	local slid = excess > 0 and slide > 0
	if slid then
		local amount = math.min(excess, slide)
		shoulderPoint += toWrist.Unit * amount
		upperRest = upperRest + toWrist.Unit * amount
		toWrist = wrist - shoulderPoint
	end
	local distance = math.clamp(toWrist.Magnitude, 0.05, upperLength + lowerLength - 0.02)
	local direction = if toWrist.Magnitude > 1e-4 then toWrist.Unit else -torso.UpVector
	-- Law of cosines for the elbow, pushed towards the pole.
	local along = (upperLength * upperLength - lowerLength * lowerLength + distance * distance) / (2 * distance)
	local height = math.sqrt(math.max(upperLength * upperLength - along * along, 0))
	local side = pole - direction * direction:Dot(pole)
	side = if side.Magnitude > 1e-4 then side.Unit else -torso.UpVector
	local elbowPoint = shoulderPoint + direction * along + side * height
	local wristPoint = shoulderPoint + direction * distance

	local upperDirection = upperRest:VectorToWorldSpace((elbow.C0.Position - shoulder.C1.Position).Unit)
	local upperRotation = LimbIK.between(upperDirection, (elbowPoint - shoulderPoint).Unit) * upperRest.Rotation
	local upperFrame = CFrame.new(shoulderPoint - upperRotation:VectorToWorldSpace(shoulder.C1.Position)) * upperRotation
	local shoulderTransform = if slid then (torso * shoulder.C0):Inverse() * upperFrame * shoulder.C1 else LimbIK.transformFor(torso, shoulder, upperFrame)

	local lowerRest = LimbIK.childFrame(upperFrame, elbow, CFrame.identity)
	local lowerDirection = lowerRest:VectorToWorldSpace((wristMotor.C0.Position - elbow.C1.Position).Unit)
	local lowerRotation = LimbIK.between(lowerDirection, (wristPoint - elbowPoint).Unit) * lowerRest.Rotation
	local lowerFrame = CFrame.new(elbowPoint - lowerRotation:VectorToWorldSpace(elbow.C1.Position)) * lowerRotation
	local elbowTransform = LimbIK.transformFor(upperFrame, elbow, lowerFrame)

	local wristTransform = LimbIK.transformFor(lowerFrame, wristMotor, hand)
	return shoulderTransform, elbowTransform, wristTransform
end

return LimbIK
