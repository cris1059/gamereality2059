--!strict

-- Procedural shooter animation for every character holding a weapon (a
-- loadout Tool, see WeaponService), run each frame after Roblox's own
-- animations so it overrides the upper body:
--   1. the torso and head pitch towards where the player aims;
--   2. the weapon is placed in front of the chest (raised to the eye while
--      aiming down sights, lowered while reloading, pushed back by recoil),
--      its barrel along the aim;
--   3. both arms reach it with two-bone IK: the right hand on the grip, the
--      left hand under the barrel (on a pistol, cupping the right hand).
-- Legs keep walking, and bend for crouching / sliding (MovementController).
-- The local player's aim and stance are sent to the server (WeaponAim) and
-- come back to everyone as character attributes, so all clients pose
-- everyone the same way.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local LeanConfig = require(root.Config.LeanConfig)
local LeanPose = require(root.Combat.LeanPose)
local WeaponStats = require(root.Combat.WeaponStats)
local ReloadAnimation = require(script.Parent.ReloadAnimation)
local SlidePose = require(script.Parent.SlidePose)
local CrouchPose = require(script.Parent.CrouchPose)
local LimbIK = require(script.Parent.LimbIK)
local SlideEffects = require(script.Parent.SlideEffects)

local ShooterAnimation = {}
ShooterAnimation.__index = ShooterAnimation

local JOINTS = table.freeze({
	Root = "LowerTorso",
	Waist = "UpperTorso",
	Neck = "Head",
	RightShoulder = "RightUpperArm",
	LeftShoulder = "LeftUpperArm",
	RightElbow = "RightLowerArm",
	LeftElbow = "LeftLowerArm",
	RightWrist = "RightHand",
	LeftWrist = "LeftHand",
	RightHip = "RightUpperLeg",
	LeftHip = "LeftUpperLeg",
	RightKnee = "RightLowerLeg",
	LeftKnee = "LeftLowerLeg",
	RightAnkle = "RightFoot",
	LeftAnkle = "LeftFoot",
})
local PISTOL_LENGTH = 2.2
local SEND_INTERVAL = 1 / 15
local BLEND_SPEED = 12
local RECOIL_RECOVERY = 12
-- Weapon sway while moving (studs at walking speed, WALK_SPEED): a side
-- swing once per two steps and a small bob on each step. The walk animation
-- itself no longer moves the weapon (see the stable anchor in _pose).
local SWAY = table.freeze({
	side = 0.05,
	bob = 0.035,
	firstPerson = 0.9, -- share kept in first person
	aiming = 0.15, -- share kept on the sights
	stepsPerStud = 0.125, -- steps per stud travelled
	ease = 6, -- how fast the sway grows / settles when starting / stopping
})
local WALK_SPEED = 16
-- Seen from outside, how far (studs) an arm may slide out of its shoulder to
-- keep its hand on the weapon before the weapon itself is brought in closer.
local ARM_SLIDE = 0.1
-- Rifle stance turn (HOLDS blade): share taken by the hips, and the most the
-- waist may twist between hips and upper body (radians), and the most the
-- weapon's anchor turns off the facing following them.
local HIPS_BLADE = 0.7
local MAX_TWIST = math.rad(10)
-- Share of the lean towards the aim the hips take standing (the rest bends
-- the waist; crouched the legs let the hips take all of it).
local STANDING_TILT = 0.6
local MAX_CARRY = math.rad(45)

-- Where the grip sits relative to the upper torso (studs: right, up, forward)
-- for each stance, and how far up the barrel the left hand holds.
-- fpHip / fpAim: the local player's own view in first person, lower, further
-- right and a little further out so hands and weapon take less of the screen
-- (tune these numbers to taste; others always see the third-person hold).
local HOLDS = table.freeze({
	rifle = table.freeze({
		-- In front of the right side of the chest, stock at the shoulder. (Earlier
		-- holds: hip (0.85, 0.55, 1.15) / aim (0.38, 0.75, 1.0), and before that
		-- hip (0.55, 0.15, 1.25): out of the left arm's reach.)
		hip = Vector3.new(0.35, 0.35, 1.05), aim = Vector3.new(0.25, 0.75, 1.05),
		fpHip = Vector3.new(0.7, -0.32, 1.75), fpAim = Vector3.new(0.3, 0.55, 1.3),
		-- Left hand: on the handguard in first person (the arm stretches to it
		-- unseen); seen from outside, at the magazine well just in front of the
		-- magazine, as far as a blocky R15 arm reaches on a 3.9-stud rifle.
		support = 0.42,
		supportOutside = 0.2,
		-- Seen from outside, the upper body turned this many degrees towards the
		-- weapon (left shoulder forward); the head stays facing forward.
		blade = 35,
	}),
	pistol = table.freeze({
		hip = Vector3.new(0.25, 0.3, 1.75), aim = Vector3.new(0.2, 0.75, 1.75),
		fpHip = Vector3.new(0.55, 0.05, 1.85), fpAim = Vector3.new(0.15, 0.6, 1.85),
		support = 0.08,
		supportOutside = 0.08,
		blade = 0,
	}),
})
-- Camera this close to the head = first person (as in ShooterCamera).
local FIRST_PERSON_RANGE = 1.5

type State = {
	joints: { [string]: Motor6D | AnimationConstraint },
	weight: number,
	pitch: number,
	aim: number,
	reload: number,
	recoil: number,
	crouch: number,
	slide: number,
	firstPerson: number, -- 0..1 blend to the first-person hold (local player)
	swayPhase: number, -- walking cycle for the weapon sway (radians)
	swayAmount: number, -- 0..1+ eased share of the sway (speed)
	drawTool: Tool?, -- the weapon being taken out, and since when (os.clock)
	drawStart: number,
	hipsYaw: number, -- the hips' turn from the facing (stance and crouch walk)
	lean: number, -- -1 (left) .. 1 (right), eased (LeanConfig)
	track: ReloadAnimation.Track, -- reload choreography (ReloadAnimation)
	slideTrack: SlidePose.Track, -- travel, turning and lean for the slide pose
	crouchTrack: CrouchPose.Track, -- gait cycle and heading for the crouch pose
}

-- aimProgress (optional): the local player's 0..1 into the sights over the
-- weapon's aim time (ShooterCamera); without it aiming eases in.
function ShooterAnimation.new(isAiming: () -> boolean, aimProgress: (() -> number)?)
	return setmetatable({
		_isAiming = isAiming,
		_aimProgress = aimProgress,
		_states = {} :: { [Model]: State },
		_connection = nil :: RBXScriptConnection?,
		_remote = nil :: UnreliableRemoteEvent?,
		_sendTimer = 0,
		_localRecoil = 0,
		_localReloading = false,
		_localCrouching = false,
		_localSliding = false,
		_localLean = 0, -- requested lean: -1, 0 or 1
		_leanAmount = 0, -- the local character's eased lean (for the camera)
		_slideAmount = 0, -- the local character's eased slide (camera)
		_slideCameraRoll = 0, -- and its lean into a turn for the camera (radians)
	}, ShooterAnimation)
end

local function equippedWeapon(character: Model): Tool?
	for _, child in character:GetChildren() do
		if child:IsA("Tool") and child:GetAttribute("LoadoutSlot") then
			return child
		end
	end
	return nil
end

-- Weapon length along its barrel and whether it is held like a pistol.
local function weaponShape(tool: Tool): (number, string)
	local cached = tool:GetAttribute("PoseLength")
	local kind = tool:GetAttribute("PoseKind")
	if type(cached) == "number" and type(kind) == "string" then
		return cached, kind
	end
	local handle = tool:FindFirstChild("Handle")
	local length = 1.5
	if handle and handle:IsA("BasePart") then
		local grip = handle.CFrame * tool.Grip
		local forward = grip.LookVector
		local low, high = math.huge, -math.huge
		for _, part in tool:GetDescendants() do
			if part:IsA("BasePart") then
				local half = part.Size / 2
				for _, corner in { Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, 1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, -1, -1), Vector3.new(-1, -1, -1) } do
					local point = part.CFrame:PointToWorldSpace(half * corner)
					local along = (point - grip.Position):Dot(forward)
					low, high = math.min(low, along), math.max(high, along)
				end
			end
		end
		if high > low then
			length = high
		end
	end
	local shapeKind = if length < PISTOL_LENGTH * 0.6 then "pistol" else "rifle"
	local class = tool:GetAttribute("WeaponClass")
	if class == "pistol" then
		shapeKind = "pistol"
	end
	tool:SetAttribute("PoseLength", length)
	tool:SetAttribute("PoseKind", shapeKind)
	return length, shapeKind
end

function ShooterAnimation:_state(character: Model): State?
	local state = self._states[character]
	if state then
		return state
	end
	local joints = {}
	for jointName, partName in JOINTS do
		local part = character:FindFirstChild(partName)
		local motor = part and part:FindFirstChild(jointName)
		if motor and (motor:IsA("Motor6D") or motor:IsA("AnimationConstraint")) then
			joints[jointName] = motor
		end
	end
	for _, required in { "Waist", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist" } do
		if not joints[required] then
			return nil
		end
	end
	local track = ReloadAnimation.newTrack()
	state = { joints = joints, weight = 0, pitch = 0, aim = 0, reload = 0, recoil = 0, crouch = 0, slide = 0, firstPerson = 0, swayPhase = 0, swayAmount = 0, drawTool = nil, drawStart = 0, hipsYaw = 0, lean = 0, track = track, slideTrack = SlidePose.newTrack(), crouchTrack = CrouchPose.newTrack() }
	self._states[character] = state
	character.Destroying:Connect(function()
		ReloadAnimation.reset(track)
		self._states[character] = nil
	end)
	return state
end

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

local childFrame = LimbIK.childFrame
local transformFor = LimbIK.transformFor
local solveArm = LimbIK.solve

-- How far `wrist` lies beyond the arm's full reach from its shoulder (zero
-- when the arm gets there), pointing away from the shoulder.
local function reachExcess(torso: CFrame, shoulder: Motor6D | AnimationConstraint, elbow: Motor6D | AnimationConstraint, wristMotor: Motor6D | AnimationConstraint, wrist: Vector3, slide: number): Vector3
	local shoulderPoint = (torso * shoulder.C0).Position
	local reach = (elbow.C0.Position - shoulder.C1.Position).Magnitude + (wristMotor.C0.Position - elbow.C1.Position).Magnitude - 0.04 + slide
	local toWrist = wrist - shoulderPoint
	local distance = toWrist.Magnitude
	if distance <= reach then
		return Vector3.zero
	end
	return toWrist.Unit * (distance - reach)
end

function ShooterAnimation:_pose(character: Model, deltaTime: number, isLocal: boolean)
	local state = self:_state(character)
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not state or not lowerTorso or not lowerTorso:IsA("BasePart") or not rootPart or not rootPart:IsA("BasePart") then
		return
	end
	local joints = state.joints
	local tool = equippedWeapon(character)
	local handle = tool and tool:FindFirstChild("Handle")
	local rightHand = character:FindFirstChild("RightHand")
	local grip = rightHand and rightHand:FindFirstChild("RightGrip")
	local alpha = 1 - math.exp(-BLEND_SPEED * deltaTime)

	-- Inputs: the local camera for this player, attributes for the rest.
	local pitch, aiming, reloading, crouching, sliding
	local lean = 0
	local firstPerson = false
	if isLocal then
		local camera = Workspace.CurrentCamera
		pitch = if camera then math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))) else 0
		local head = character:FindFirstChild("Head")
		firstPerson = camera ~= nil and head ~= nil and head:IsA("BasePart")
			and (camera.CFrame.Position - head.Position).Magnitude <= FIRST_PERSON_RANGE
		aiming = self._isAiming()
		reloading = self._localReloading
		crouching = self._localCrouching
		sliding = self._localSliding
		lean = self._localLean
		state.recoil = self._localRecoil
	else
		local attribute = character:GetAttribute("AimPitch")
		pitch = if type(attribute) == "number" then attribute else 0
		aiming = character:GetAttribute("Aiming") == true
		reloading = character:GetAttribute("Reloading") == true
		crouching = character:GetAttribute("Crouching") == true
		sliding = character:GetAttribute("Sliding") == true
		local leanAttribute = character:GetAttribute("Lean")
		lean = if type(leanAttribute) == "number" then leanAttribute else 0
		state.recoil *= math.exp(-RECOIL_RECOVERY * deltaTime)
	end
	state.weight += ((if tool and handle and grip then 1 else 0) - state.weight) * alpha
	state.pitch += (math.clamp(pitch, -70, 70) - state.pitch) * (if isLocal then 1 else alpha)
	-- Sights: the local player follows the camera's timed progress; others
	-- ease in over their weapon's aim time (about 95 % by then).
	if isLocal and self._aimProgress then
		state.aim = self._aimProgress()
	else
		local aimSeconds = if tool then math.max(WeaponStats.AimSeconds(tool), 0.05) else 0.25
		state.aim += ((if aiming then 1 else 0) - state.aim) * (1 - math.exp(-3 / aimSeconds * deltaTime))
	end
	-- A weapon newly in hand comes up from low over its draw time.
	if tool ~= state.drawTool then
		state.drawTool = tool
		state.drawStart = os.clock()
	end
	state.reload += ((if reloading then 1 else 0) - state.reload) * alpha
	state.crouch += ((if crouching then 1 else 0) - state.crouch) * alpha
	state.slide += ((if sliding then 1 else 0) - state.slide) * alpha
	state.firstPerson += ((if firstPerson then 1 else 0) - state.firstPerson) * alpha
	-- No lean without a weapon in hand or mid-slide.
	local leanTarget = if tool and handle and grip and not sliding then math.clamp(lean, -1, 1) else 0
	state.lean += (leanTarget - state.lean) * (1 - math.exp(-LeanConfig.BlendSpeed * deltaTime))
	if isLocal then
		self._leanAmount = state.lean
	end

	-- Legs: the crouch stance and crouch walk (CrouchPose); the slide pose
	-- (SlidePose) on top, with its effects.
	-- A rifle stance turns the whole body towards the weapon: the hips take
	-- most of the turn (HIPS_BLADE) and the upper body the rest, so the waist
	-- never twists more than MAX_TWIST (a single R15 joint: a bigger twist
	-- shears the jacket off the trousers). Seen from outside only.
	local stanceYaw = 0
	if tool and handle then
		local _, heldKind = weaponShape(tool)
		stanceYaw = -math.rad(HOLDS[heldKind].blade) * HIPS_BLADE * (1 - state.firstPerson) * state.weight
	end
	-- The lean towards the aim (up / down, recoil) is taken by the hips too,
	-- so the waist hardly bends: layered clothing hides the body under it, and
	-- a bent waist opened a see-through gap between jacket and trousers.
	-- Crouched the legs (IK) take all of it; standing, the hips take
	-- STANDING_TILT of it. Seen from outside only.
	local outside = (1 - state.firstPerson) * state.weight
	local aimTilt = math.rad(state.pitch * 0.35 + state.recoil * 0.25) * outside
	CrouchPose.update(state.crouchTrack, rootPart, deltaTime)
	CrouchPose.apply(state.crouchTrack, character, joints, rootPart, state.crouch, stanceYaw, CFrame.Angles(aimTilt, 0, 0))
	local standing = (1 - state.crouch) * (1 - state.slide)
	local rootVelocity = rootPart.AssemblyLinearVelocity
	local standingYaw = stanceYaw * (1 - 0.5 * math.clamp(Vector3.new(rootVelocity.X, 0, rootVelocity.Z).Magnitude / WALK_SPEED, 0, 1))
	if joints.Root and standing > 0.01 and (math.abs(standingYaw) > 1e-4 or math.abs(aimTilt) > 1e-4) then
		joints.Root.Transform = CFrame.Angles(0, standingYaw * standing, 0) * CFrame.Angles(aimTilt * STANDING_TILT * standing, 0, 0) * joints.Root.Transform
	end
	state.hipsYaw = state.crouchTrack.hipsYaw * state.crouch * (1 - state.slide) + standingYaw * standing
	local slideTrack = state.slideTrack
	SlidePose.update(slideTrack, rootPart, deltaTime)
	SlidePose.apply(slideTrack, joints, state.slide)
	SlideEffects.update(character, state.slide, slideTrack.speed, slideTrack.time)
	if isLocal then
		self._slideAmount = state.slide
		self._slideCameraRoll = SlidePose.cameraRoll(slideTrack, state.slide)
	end

	local ready = tool ~= nil and handle ~= nil and handle:IsA("BasePart") and grip ~= nil and grip:IsA("JointInstance")
	local reloadTime = ReloadAnimation.progress(state.track, reloading and ready, tool)
	if state.weight < 0.01 or not tool or not handle or not handle:IsA("BasePart") or not grip or not grip:IsA("JointInstance") then
		return
	end
	local weight = state.weight
	local function blend(motor: (Motor6D | AnimationConstraint)?, transform: CFrame)
		if motor then
			motor.Transform = motor.Transform:Lerp(transform, weight)
		end
	end

	-- 1. Torso and head follow the aim (and lean back in a slide); a lean
	-- rolls the upper body at the waist, the neck taking a little back. The
	-- weapon and arms below hang off the torso, so they lean with it.
	local length, kind = weaponShape(tool)
	local hold = HOLDS[kind]
	local blade = math.rad(hold.blade) * (1 - state.firstPerson)
	local p = state.pitch
	local roll = LeanPose.roll(state.lean)
	local slideBack, slideRoll = SlidePose.torso(state.slideTrack, state.slide)
	local crouchLean = CrouchPose.torsoLean(state.crouch * (1 - state.slide))
	local waistTransform = angles(p * 0.35 + state.recoil * 0.25 + slideBack - crouchLean, 0, 0) * CFrame.Angles(0, 0, roll + slideRoll)
	blend(joints.Neck, CFrame.Angles(0, blade, 0) * angles(p * 0.35, 0, 0) * CFrame.Angles(0, 0, -roll * LeanConfig.NeckCounter))
	-- The weapon hangs off a steady copy of the torso: the root part (which
	-- does not bob) through the hips at rest and our own waist pose, so the
	-- walk animation's hip sway and bounce no longer shake it.
	-- Crouching, the upper body rides on the hips' step (CrouchPose.carry).
	-- The upper body turns with the hips, at most MAX_TWIST off (and the
	-- weapon's anchor at most MAX_CARRY off the facing).
	local hipsYaw = state.hipsYaw
	local upperYaw = hipsYaw + math.clamp(-blade - hipsYaw, -MAX_TWIST, MAX_TWIST)
	local carryYaw = math.clamp(upperYaw + blade, -MAX_CARRY, MAX_CARRY) * (1 - state.firstPerson)
	local carry = CrouchPose.carry(state.crouchTrack, state.crouch * (1 - state.slide), state.firstPerson) * CFrame.Angles(0, carryYaw, 0)
	local restHips = if joints.Root then childFrame(rootPart.CFrame, joints.Root, carry) else lowerTorso.CFrame
	local anchor = childFrame(restHips, joints.Waist, waistTransform)
	-- This frame's hips, from the root and the pose the walk animation has
	-- just written (LowerTorso.CFrame still holds last frame's pose).
	local lowerNow = if joints.Root then childFrame(rootPart.CFrame, joints.Root, joints.Root.Transform) else lowerTorso.CFrame
	-- The waist cancels the walk's hip sway so the shoulders (and both arms)
	-- stay on the steady anchor too: the turn always, the bounce as well in
	-- first person, where the body isn't seen (from outside it would pull the
	-- upper body off the hips).
	-- (The upper body itself is turned by the stance's blade; the weapon keeps
	-- to the unturned anchor, pointing where you aim.)
	-- (The stance turn goes in before the lean, as on the hips, so both
	-- tilt about the same axis and the waist does not roll.)
	local torsoTarget = childFrame(restHips * CFrame.Angles(0, -blade, 0), joints.Waist, waistTransform)
	local steadyWaist = (lowerNow * joints.Waist.C0):Inverse() * torsoTarget * joints.Waist.C1
	blend(joints.Waist, steadyWaist.Rotation:Lerp(steadyWaist, state.firstPerson))
	local torso = childFrame(lowerNow, joints.Waist, joints.Waist.Transform)

	-- 2. Where the weapon goes: grip in front of the chest, barrel along the aim.
	local facing = rootPart.CFrame
	local aimDirection = (facing * CFrame.Angles(math.rad(p), 0, 0)).LookVector
	local thirdPersonOffset = hold.hip:Lerp(hold.aim, state.aim)
	local firstPersonOffset = hold.fpHip:Lerp(hold.fpAim, state.aim)
	local offset = thirdPersonOffset:Lerp(firstPersonOffset, state.firstPerson)
	local right, up = anchor.RightVector, anchor.UpVector
	local forward = anchor.LookVector
	local gripPoint = anchor.Position + right * offset.X + up * offset.Y + forward * offset.Z
		- aimDirection * (state.recoil * 0.025)
	-- Controlled sway with movement: side swing every two steps, a bob per step.
	local velocity = rootPart.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local targetSway = if state.slide > 0.5 then 0 else math.clamp(speed / WALK_SPEED, 0, 1.4)
	state.swayAmount += (targetSway - state.swayAmount) * (1 - math.exp(-SWAY.ease * deltaTime))
	state.swayPhase = (state.swayPhase + speed * SWAY.stepsPerStud * math.pi * deltaTime) % (2 * math.pi)
	local swayScale = state.swayAmount
		* (1 + (SWAY.firstPerson - 1) * state.firstPerson)
		* (1 + (SWAY.aiming - 1) * state.aim)
	gripPoint += right * (math.sin(state.swayPhase) * SWAY.side * swayScale)
		+ up * (-math.abs(math.sin(state.swayPhase)) * SWAY.bob * swayScale)
	local barrel = aimDirection
	local drawSeconds = math.max(WeaponStats.DrawSeconds(tool), 0.01)
	local drawn = math.clamp((os.clock() - state.drawStart) / drawSeconds, 0, 1)
	local lowered = 1 - drawn * drawn * (3 - 2 * drawn)
	if lowered > 0.001 then
		-- Drawing: muzzle down and the weapon low and close, rising into the hold.
		barrel = (aimDirection:Lerp(-up, 0.6 * lowered)).Unit
		gripPoint -= up * 0.5 * lowered + forward * 0.25 * lowered
	end
	local tilt = state.reload * ReloadAnimation.tilt(reloadTime)
	if tilt > 0.01 then
		-- Reload, back to the hold once the bolt is released. Seen from outside
		-- the weapon stays on the right side (where the over-the-right-shoulder
		-- camera sees it), tipped down and out a little so the magazine swap
		-- clears the body; in first person it comes in to the middle of the
		-- screen, muzzle a little up.
		local fp = state.firstPerson
		local outsideBarrel = (aimDirection - up * 0.5 + right * 0.25).Unit
		local insideBarrel = (aimDirection + up * 0.1).Unit
		barrel = aimDirection:Lerp(outsideBarrel:Lerp(insideBarrel, fp).Unit, tilt).Unit
		local outsideShift = -up * 0.3 + right * 0.2 - forward * 0.05
		local insideShift = -up * 0.05 - forward * 0.15 - right * 0.35
		gripPoint += outsideShift:Lerp(insideShift, fp) * tilt
		gripPoint += up * 0.08 * ReloadAnimation.jolt(reloadTime) * state.reload
	end
	local roll = ReloadAnimation.rollRadians() * ReloadAnimation.roll(reloadTime) * state.reload
	local gripFrame = CFrame.lookAt(gripPoint, gripPoint + barrel, up) * CFrame.Angles(0, 0, roll)
	-- RightGrip: Handle = RightHand * C0 * C1^-1, with C1 = tool.Grip and the
	-- hand's grip frame = RightHand * C0.
	local rightHandFrame = gripFrame * grip.C0:Inverse()
	-- The left hand holds the weapon from underneath (HOLDS: support /
	-- supportOutside, a share of the weapon's length ahead of the grip).
	local armSlide = ARM_SLIDE + (10 - ARM_SLIDE) * state.firstPerson
	local supportBase = gripFrame.Position - up * 0.04 -- (just under the handguard, wrapping it)
	local supportAlong = length * (hold.supportOutside + (hold.support - hold.supportOutside) * state.firstPerson)
	local supportPoint = supportBase + barrel * supportAlong
	local leftHandFrame = CFrame.lookAt(supportPoint, supportPoint + barrel, up) * CFrame.Angles(0, 0, math.rad(-80))
	if reloadTime then
		-- Reload: the left hand works the magazine and the charging handle.
		local target = ReloadAnimation.leftHand(state.track, reloadTime, {
			tool = tool,
			gripFrame = gripFrame,
			support = leftHandFrame,
			lowerTorso = lowerTorso.CFrame,
			length = length,
			pistol = kind == "pistol",
			velocity = rootPart.AssemblyLinearVelocity,
		})
		if target then
			leftHandFrame = leftHandFrame:Lerp(target, state.reload)
		end
		if isLocal then
			-- The local player feels the magazine seat and the bolt slam home.
			for _, event in state.track.events do
				if event == "magIn" then
					self:Kick(0.8)
				elseif event == "boltRelease" then
					self:Kick(1.6)
				end
			end
		end
	end
	-- Out of an arm's reach (seen from outside), the weapon comes in towards
	-- the body by what is missing rather than a hand coming off it. Not
	-- mid-reload, when the left hand goes to the magazine on purpose, nor in
	-- first person, where the arms stretch to it instead (solveArm).
	local holding = 1 - state.reload
	if holding > 0.01 then
		for _ = 1, 2 do
			local shift = reachExcess(torso, joints.LeftShoulder, joints.LeftElbow, joints.LeftWrist, (leftHandFrame * joints.LeftWrist.C1).Position, armSlide)
				+ reachExcess(torso, joints.RightShoulder, joints.RightElbow, joints.RightWrist, (rightHandFrame * joints.RightWrist.C1).Position, armSlide)
			if shift.Magnitude < 1e-3 then
				break
			end
			shift *= -holding
			gripFrame += shift
			rightHandFrame += shift
			leftHandFrame += shift
		end
	end
	local rightWrist = (rightHandFrame * joints.RightWrist.C1).Position

	-- 3. Both arms reach the weapon; elbows down and out. The right hand holds
	-- the grip, so the weapon goes wherever that hand actually ends up; when
	-- the arm falls short of the target (fast turns, extreme pitch), the left
	-- hand is moved by the same amount so it stays on the weapon.
	local rs, re, rw = solveArm(torso, joints.RightShoulder, joints.RightElbow, joints.RightWrist, rightWrist, -up * 0.6 + right * 1.2 - forward * 0.1, rightHandFrame, armSlide)
	blend(joints.RightShoulder, rs)
	blend(joints.RightElbow, re)
	blend(joints.RightWrist, rw)
	local upperRight = childFrame(torso, joints.RightShoulder, joints.RightShoulder.Transform)
	local lowerRight = childFrame(upperRight, joints.RightElbow, joints.RightElbow.Transform)
	local handRight = childFrame(lowerRight, joints.RightWrist, joints.RightWrist.Transform)
	leftHandFrame = (handRight * grip.C0) * gripFrame:Inverse() * leftHandFrame
	local leftWrist = (leftHandFrame * joints.LeftWrist.C1).Position
	local ls, le, lw = solveArm(torso, joints.LeftShoulder, joints.LeftElbow, joints.LeftWrist, leftWrist, -up - right * 0.6 - forward * 0.2, leftHandFrame, armSlide)
	blend(joints.LeftShoulder, ls)
	blend(joints.LeftElbow, le)
	blend(joints.LeftWrist, lw)
end

-- Recoil for the local player's next frames (degrees of upward kick).
function ShooterAnimation:Kick(degrees: number)
	self._localRecoil = math.min(self._localRecoil + degrees, 6)
end

function ShooterAnimation:SetReloading(reloading: boolean)
	self._localReloading = reloading
end

-- The local character's eased slide (0..1) and its camera roll into a turn
-- (radians), for the camera.
function ShooterAnimation:GetSlide(): (number, number)
	return self._slideAmount, self._slideCameraRoll
end

function ShooterAnimation:SetStance(crouching: boolean, sliding: boolean)
	self._localCrouching = crouching
	self._localSliding = sliding
end

-- Q / E: lean that way, or straighten up if already leaning that way.
function ShooterAnimation:ToggleLean(side: number)
	self._localLean = if self._localLean == side then 0 else side
end

-- The local character's current lean, eased (-1 .. 1), for the camera.
function ShooterAnimation:GetLean(): number
	return self._leanAmount
end

function ShooterAnimation:Enable()
	if self._connection then
		return
	end
	task.spawn(function()
		local remotes = root:WaitForChild("Runtime"):WaitForChild(RemoteNames.Folder)
		local remote = remotes:WaitForChild(RemoteNames.WeaponAim)
		if remote:IsA("UnreliableRemoteEvent") then
			self._remote = remote
		end
	end)
	local localPlayer = Players.LocalPlayer
	-- PreSimulation runs after the Animator has written this frame's poses.
	self._connection = RunService.PreSimulation:Connect(function(deltaTime: number)
		self._localRecoil *= math.exp(-RECOIL_RECOVERY * deltaTime)
		debug.profilebegin("R2059 ShooterPose")
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				self:_pose(character, deltaTime, player == localPlayer)
			end
		end
		debug.profileend()
		self._sendTimer -= deltaTime
		local character = localPlayer.Character
		local remote = self._remote
		if self._sendTimer <= 0 and remote and character then
			self._sendTimer = SEND_INTERVAL
			local state = self._states[character]
			remote:FireServer(if state then state.pitch else 0, self._isAiming(), self._localReloading, self._localCrouching, self._localSliding, if state then state.lean else 0)
		end
	end)
end

function ShooterAnimation:Disable()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	for _, state in self._states do
		ReloadAnimation.reset(state.track)
	end
	table.clear(self._states)
	self._localRecoil = 0
	self._localReloading = false
	self._localCrouching = false
	self._localSliding = false
	self._localLean = 0
	self._leanAmount = 0
end

return ShooterAnimation
