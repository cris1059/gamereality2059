--!strict

-- Shared lean geometry, so the pose every client draws (ShooterAnimation)
-- and the hitboxes the server traces (CombatService) roll the same way.
-- lean: -1 (full left) .. 1 (full right).

local LeanConfig = require(script.Parent.Parent.Config.LeanConfig)

local LeanPose = {}

-- R15 parts above the waist: they roll with the upper body.
LeanPose.UpperParts = table.freeze({
	UpperTorso = true,
	Head = true,
	LeftUpperArm = true,
	LeftLowerArm = true,
	LeftHand = true,
	RightUpperArm = true,
	RightLowerArm = true,
	RightHand = true,
})

-- Waist roll in radians about the lower torso's Z axis (its back). Leaning
-- right lowers the right shoulder: a negative roll about +Z.
function LeanPose.roll(lean: number): number
	return -math.clamp(lean, -1, 1) * math.rad(LeanConfig.Degrees)
end

-- Rigid transform taking an upright upper-body part to its leaned place,
-- pivoting at the top of the lower torso.
function LeanPose.upperBodyTransform(lowerTorso: CFrame, lowerTorsoSize: Vector3, lean: number): CFrame
	local pivot = lowerTorso * CFrame.new(0, lowerTorsoSize.Y / 2, 0)
	local rotation = CFrame.fromAxisAngle(lowerTorso.ZVector, LeanPose.roll(lean))
	return CFrame.new(pivot.Position) * rotation * CFrame.new(-pivot.Position)
end

return LeanPose
