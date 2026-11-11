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
})
local PISTOL_LENGTH = 2.2
local SEND_INTERVAL = 1 / 15
local BLEND_SPEED = 12
local RECOIL_RECOVERY = 12

-- Where the grip sits relative to the upper torso (studs: right, up, forward)
-- for each stance, and how far up the barrel the left hand holds.
local HOLDS = table.freeze({
	rifle = table.freeze({ hip = Vector3.new(0.55, 0.15, 1.25), aim = Vector3.new(0.38, 0.75, 1.0), support = 0.42 }),
	pistol = table.freeze({ hip = Vector3.new(0.25, 0.3, 1.75), aim = Vector3.new(0.2, 0.75, 1.75), support = 0.08 }),
})

type State = {
	joints: { [string]: Motor6D },
	weight: number,
	pitch: number,
	aim: number,
	reload: number,
	recoil: number,
	crouch: number,
	slide: number,
}

function ShooterAnimation.new(isAiming: () -> boolean)
	return setmetatable({
		_isAiming = isAiming,
		_states = {} :: { [Model]: State },
		_connection = nil :: RBXScriptConnection?,
		_remote = nil :: UnreliableRemoteEvent?,
		_sendTimer = 0,
		_localRecoil = 0,
		_localReloading = false,
		_localCrouching = false,
		_localSliding = false,
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
		if motor and motor:IsA("Motor6D") then
			joints[jointName] = motor
		end
	end
	for _, required in { "Waist", "RightShoulder", "LeftShoulder", "RightElbow", "LeftElbow", "RightWrist", "LeftWrist" } do
		if not joints[required] then
			return nil
		end
	end
	state = { joints = joints, weight = 0, pitch = 0, aim = 0, reload = 0, recoil = 0, crouch = 0, slide = 0 }
	self._states[character] = state
	character.Destroying:Connect(function()
		self._states[character] = nil
	end)
	return state
end

local function angles(x: number, y: number, z: number): CFrame
	return CFrame.Angles(math.rad(x), math.rad(y), math.rad(z))
end

-- Shortest rotation taking unit vector a onto unit vector b.
local function between(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-6 then
		return if dot > 0 then CFrame.identity else CFrame.fromAxisAngle(Vector3.xAxis, math.pi)
	end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Child part frame for a joint: Part1 = Part0 * C0 * Transform * C1^-1.
local function childFrame(parent: CFrame, motor: Motor6D, transform: CFrame): CFrame
	return parent * motor.C0 * transform * motor.C1:Inverse()
end

-- The Transform that puts Part1 at `frame` (rotation only; the joint stays put).
local function transformFor(parent: CFrame, motor: Motor6D, frame: CFrame): CFrame
	return ((parent * motor.C0):Inverse() * frame * motor.C1).Rotation
end

-- Two-bone IK for one arm: shoulder at the torso, wrist at `wrist`, elbow
-- bent towards `pole`, hand turned to `hand` (a world frame for the hand).
-- Returns the Transforms for shoulder, elbow and wrist.
local function solveArm(torso: CFrame, shoulder: Motor6D, elbow: Motor6D, wristMotor: Motor6D, wrist: Vector3, pole: Vector3, hand: CFrame): (CFrame, CFrame, CFrame)
	local upperRest = childFrame(torso, shoulder, CFrame.identity)
	local shoulderPoint = (torso * shoulder.C0).Position
	local upperLength = (elbow.C0.Position - shoulder.C1.Position).Magnitude
	local lowerLength = (wristMotor.C0.Position - elbow.C1.Position).Magnitude
	local toWrist = wrist - shoulderPoint
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
	local upperRotation = between(upperDirection, (elbowPoint - shoulderPoint).Unit) * upperRest.Rotation
	local upperFrame = CFrame.new(shoulderPoint - upperRotation:VectorToWorldSpace(shoulder.C1.Position)) * upperRotation
	local shoulderTransform = transformFor(torso, shoulder, upperFrame)

	local lowerRest = childFrame(upperFrame, elbow, CFrame.identity)
	local lowerDirection = lowerRest:VectorToWorldSpace((wristMotor.C0.Position - elbow.C1.Position).Unit)
	local lowerRotation = between(lowerDirection, (wristPoint - elbowPoint).Unit) * lowerRest.Rotation
	local lowerFrame = CFrame.new(elbowPoint - lowerRotation:VectorToWorldSpace(elbow.C1.Position)) * lowerRotation
	local elbowTransform = transformFor(upperFrame, elbow, lowerFrame)

	local wristTransform = transformFor(lowerFrame, wristMotor, hand)
	return shoulderTransform, elbowTransform, wristTransform
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
	if isLocal then
		local camera = Workspace.CurrentCamera
		pitch = if camera then math.deg(math.asin(math.clamp(camera.CFrame.LookVector.Y, -1, 1))) else 0
		aiming = self._isAiming()
		reloading = self._localReloading
		crouching = self._localCrouching
		sliding = self._localSliding
		state.recoil = self._localRecoil
	else
		local attribute = character:GetAttribute("AimPitch")
		pitch = if type(attribute) == "number" then attribute else 0
		aiming = character:GetAttribute("Aiming") == true
		reloading = character:GetAttribute("Reloading") == true
		crouching = character:GetAttribute("Crouching") == true
		sliding = character:GetAttribute("Sliding") == true
		state.recoil *= math.exp(-RECOIL_RECOVERY * deltaTime)
	end
	state.weight += ((if tool and handle and grip then 1 else 0) - state.weight) * alpha
	state.pitch += (math.clamp(pitch, -70, 70) - state.pitch) * (if isLocal then 1 else alpha)
	state.aim += ((if aiming then 1 else 0) - state.aim) * alpha
	state.reload += ((if reloading then 1 else 0) - state.reload) * alpha
	state.crouch += ((if crouching then 1 else 0) - state.crouch) * alpha
	state.slide += ((if sliding then 1 else 0) - state.slide) * alpha

	-- Legs: bent knees while crouching, leaning back with legs forward while sliding.
	if state.crouch > 0.01 or state.slide > 0.01 then
		for _, entry in { { "RightHip", "RightKnee" }, { "LeftHip", "LeftKnee" } } do
			local hip, knee = joints[entry[1]], joints[entry[2]]
			if hip and knee then
				local hipAngle = 50 * state.crouch + 75 * state.slide
				local kneeAngle = -85 * state.crouch - 25 * state.slide
				hip.Transform = hip.Transform:Lerp(angles(hipAngle, 0, 0), math.max(state.crouch, state.slide))
				knee.Transform = knee.Transform:Lerp(angles(kneeAngle, 0, 0), math.max(state.crouch, state.slide))
			end
		end
	end

	if state.weight < 0.01 or not tool or not handle or not handle:IsA("BasePart") or not grip or not grip:IsA("JointInstance") then
		return
	end
	local weight = state.weight
	local function blend(motor: Motor6D?, transform: CFrame)
		if motor then
			motor.Transform = motor.Transform:Lerp(transform, weight)
		end
	end

	-- 1. Torso and head follow the aim (and lean back in a slide).
	local p = state.pitch
	local waistTransform = angles(p * 0.35 + state.recoil * 0.25 - 15 * state.slide, 0, 0)
	blend(joints.Waist, waistTransform)
	blend(joints.Neck, angles(p * 0.35, 0, 0))
	local torso = childFrame(lowerTorso.CFrame, joints.Waist, joints.Waist.Transform)

	-- 2. Where the weapon goes: grip in front of the chest, barrel along the aim.
	local length, kind = weaponShape(tool)
	local hold = HOLDS[kind]
	local facing = rootPart.CFrame
	local aimDirection = (facing * CFrame.Angles(math.rad(p), 0, 0)).LookVector
	local offset = hold.hip:Lerp(hold.aim, state.aim)
	local right, up = torso.RightVector, torso.UpVector
	local forward = torso.LookVector
	local gripPoint = torso.Position + right * offset.X + up * offset.Y + forward * offset.Z
		- aimDirection * (state.recoil * 0.025)
	local barrel = aimDirection
	if state.reload > 0.01 then
		-- Reload: weapon tipped down and pulled in.
		barrel = (aimDirection:Lerp(-up, 0.55 * state.reload)).Unit
		gripPoint -= up * 0.45 * state.reload + forward * 0.3 * state.reload
	end
	local gripFrame = CFrame.lookAt(gripPoint, gripPoint + barrel, up)
	-- RightGrip: Handle = RightHand * C0 * C1^-1, with C1 = tool.Grip and the
	-- hand's grip frame = RightHand * C0.
	local rightHandFrame = gripFrame * grip.C0:Inverse()
	local rightWrist = (rightHandFrame * joints.RightWrist.C1).Position
	local supportPoint = gripFrame.Position + barrel * math.max(length * hold.support, 0.25) - up * 0.12
	local leftHandFrame = CFrame.lookAt(supportPoint, supportPoint + barrel, up) * CFrame.Angles(0, 0, math.rad(-80))
		* CFrame.new(0, 0, 0)
	local leftWrist = (leftHandFrame * joints.LeftWrist.C1).Position

	-- 3. Both arms reach the weapon; elbows down and out.
	local rs, re, rw = solveArm(torso, joints.RightShoulder, joints.RightElbow, joints.RightWrist, rightWrist, -up + right * 0.6 - forward * 0.2, rightHandFrame)
	blend(joints.RightShoulder, rs)
	blend(joints.RightElbow, re)
	blend(joints.RightWrist, rw)
	local ls, le, lw = solveArm(torso, joints.LeftShoulder, joints.LeftElbow, joints.LeftWrist, leftWrist, -up - right * 0.6 - forward * 0.2, leftHandFrame)
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

function ShooterAnimation:SetStance(crouching: boolean, sliding: boolean)
	self._localCrouching = crouching
	self._localSliding = sliding
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
		for _, player in Players:GetPlayers() do
			local character = player.Character
			if character then
				self:_pose(character, deltaTime, player == localPlayer)
			end
		end
		self._sendTimer -= deltaTime
		local character = localPlayer.Character
		local remote = self._remote
		if self._sendTimer <= 0 and remote and character then
			self._sendTimer = SEND_INTERVAL
			local state = self._states[character]
			remote:FireServer(if state then state.pitch else 0, self._isAiming(), self._localReloading, self._localCrouching, self._localSliding)
		end
	end)
end

function ShooterAnimation:Disable()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	table.clear(self._states)
	self._localRecoil = 0
	self._localReloading = false
	self._localCrouching = false
	self._localSliding = false
end

return ShooterAnimation
