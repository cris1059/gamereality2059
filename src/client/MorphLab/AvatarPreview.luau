--!strict

-- One standard R15 avatar shown in a scene: the MORPHLAB preview, the lobby
-- line-up and the city pedestrians. The server builds the catalog part
-- (AvatarService: face, hair, outfit, accessories) once per combination;
-- this clones it, stands it on a part and paints the rest locally (face,
-- skin, body scales, cyberware), so those edits are instant. Only the
-- HumanoidRootPart is anchored; R15Pose animates the joints, and the lowest
-- foot is kept on the floor every frame.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local RemoteNames = require(root.Network.RemoteNames)
local AvatarDescription = require(root.Character.AvatarDescription)
local FaceArt = require(root.Character.FaceArt)
local CharacterDraft = require(root.Character.CharacterDraft)
local R15Cyberware = require(root.Character.R15Cyberware)
local R15Pose = require(root.Character.R15Pose)

local AvatarPreview = {}
AvatarPreview.__index = AvatarPreview

local BODY_PARTS = table.freeze({
	"Head", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
})
local SCALE_VALUES = table.freeze({
	height = "BodyHeightScale",
	width = "BodyWidthScale",
	depth = "BodyDepthScale",
	head = "HeadScale",
})

local UNDERWEAR_COLOR = Color3.fromRGB(28, 30, 38)
local UNDERWEAR_TRIM = Color3.fromRGB(255, 32, 48)
local UNDERWEAR_MARGIN = 0.06

-- Catalog models already received, by items key (shared by every preview).
local templates: { [string]: Model } = {}

-- The server's model for a character's catalog items (yields on first use).
local function requestTemplate(draft): (Model?, string?)
	local key = AvatarDescription.ItemsKey(draft)
	local known = templates[key]
	if known and known.Parent then
		return known, nil
	end
	local runtime = root:WaitForChild("Runtime", 10)
	local remotes = runtime and runtime:WaitForChild(RemoteNames.Folder, 10)
	local remote = remotes and remotes:WaitForChild(RemoteNames.AvatarModel, 10)
	if not remote or not remote:IsA("RemoteFunction") then
		return nil, "AVATAR_SERVICE_UNAVAILABLE"
	end
	local ok, model, problem = pcall(function()
		return remote:InvokeServer(draft)
	end)
	if not ok then
		return nil, tostring(model)
	end
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil, if type(problem) == "string" then problem else "AVATAR_MODEL_FAILED"
	end
	templates[key] = model
	return model, nil
end

local function partBottomY(part: BasePart): number
	local half = part.Size * 0.5
	local frame = part.CFrame
	return frame.Position.Y - (math.abs(frame.RightVector.Y) * half.X + math.abs(frame.UpVector.Y) * half.Y + math.abs(frame.LookVector.Y) * half.Z)
end

function AvatarPreview.new(config)
	return setmetatable({
		_config = config,
		_model = nil :: Model?,
		_rootPart = nil :: BasePart?,
		_feet = {} :: { BasePart },
		_pose = nil :: any,
		_draft = nil :: any,
		_itemsKey = nil :: string?,
		_spawnOverride = nil :: BasePart?,
		_scene = nil :: Instance?,
		_standFrame = nil :: CFrame?,
		_currentYaw = 0,
		_targetYaw = 0,
		_stance = nil :: any?,
		_puppet = nil :: ((number) -> (CFrame?, number?, number?))?,
		_connection = nil :: RBXScriptConnection?,
		_cyberwareDirty = false,
		_token = 0,
		_template = nil :: Model?,
		-- Face animation state (drawn face, see Character/FaceArt).
		_face = nil :: any?,
		_faceKey = nil :: string?,
		_gestureTimer = 6,
		_gestureLeft = 0,
		_blinkTimer = math.random(3, 6),
		_blinkDuration = 0,
		_blinkLength = 0.14,
		_winkSide = "both",
		-- Occasional poses (SetPoseCycle).
		_poseCycle = nil :: any?,
		_poseIndex = 0,
		_poseTimer = 0,
		_posing = false,
	}, AvatarPreview)
end

-- Every idle (NumberRange, seconds) the avatar strikes the next pose of
-- `poses` for `hold` seconds. nil turns the cycle off.
function AvatarPreview:SetPoseCycle(poses: { any }?, idle: NumberRange?, hold: number?)
	if not poses or #poses == 0 then
		self._poseCycle = nil
		if self._posing and self._pose then
			self._pose:SetStance(self._stance)
		end
		self._posing = false
		return
	end
	self._poseCycle = { poses = poses, idle = idle or NumberRange.new(6, 10), hold = hold or 2.5 }
	self._poseTimer = self._poseCycle.idle.Min
end

-- Strikes the next pose of the cycle right away.
function AvatarPreview:StrikePose()
	if self._poseCycle and not self._posing then
		self._poseTimer = 0
	end
end

-- Stand on a specific part instead of the scene's Platform/CharacterSpawn.
function AvatarPreview:SetSpawn(spawnPart: BasePart?)
	self._spawnOverride = spawnPart
end

-- Held posture (LobbyConfig.Stances entry); kept across rebuilds.
function AvatarPreview:SetStance(stance: any?)
	self._stance = stance
	if self._pose then
		self._pose:SetStance(stance)
	end
end

-- Ambient characters (city pedestrians): every frame the callback returns
-- where the feet stand (CFrame on the floor, facing the walking direction),
-- the walking speed and how much time to animate (nil skips the animation
-- this frame, for far characters). A nil stand leaves the model as it is.
function AvatarPreview:SetPuppet(callback: ((number) -> (CFrame?, number?, number?))?)
	self._puppet = callback
end

-- Where the avatar stands, facing the scene's camera when there is one.
function AvatarPreview:_resolveStand(scene: Instance): boolean
	local spawnPart = self._spawnOverride
	if not spawnPart then
		local platform = scene:WaitForChild("Platform", 10)
		local found = platform and platform:WaitForChild("CharacterSpawn", 10)
		spawnPart = if found and found:IsA("BasePart") then found else nil
	end
	if not spawnPart then
		return false
	end
	local feet = spawnPart.Position + Vector3.new(0, spawnPart.Size.Y * 0.5, 0)
	local cameras = scene:FindFirstChild("Cameras")
	local anchor = cameras and cameras:FindFirstChild("CinematicCamera")
	local look = if anchor and anchor:IsA("BasePart") then anchor.Position - feet else spawnPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	self._standFrame = CFrame.lookAt(feet, feet + (if flat.Magnitude > 1e-3 then flat.Unit else -Vector3.zAxis))
	return true
end

-- Shows the character in the scene (yields while the server builds a new
-- item combination). Later calls with the same scene only update.
function AvatarPreview:Show(scene: Instance, draft): (boolean, string?)
	if self._scene ~= scene or not self._standFrame then
		self._scene = scene
		if not self:_resolveStand(scene) then
			return false, "CHARACTER_SPAWN_MISSING"
		end
	end
	return self:SetDraft(draft)
end

-- Same, from a model the caller already has (the pedestrian pool), first
-- standing on `stand`.
function AvatarPreview:ShowTemplate(scene: Instance, template: Model, draft, stand: CFrame?)
	self._scene = scene
	self._standFrame = stand or self._standFrame or CFrame.new()
	self._draft = draft
	self:_mount(template, AvatarDescription.ItemsKey(draft))
end

-- Applies a (changed) character. Face, skin, scales, cyberware and colours
-- are painted locally; a different item combination swaps the model.
function AvatarPreview:SetDraft(draft): (boolean, string?)
	self._draft = draft
	local key = AvatarDescription.ItemsKey(draft)
	if self._model and key == self._itemsKey then
		self:_paint()
		return true, nil
	end
	self._token += 1
	local token = self._token
	local template, problem = requestTemplate(draft)
	-- A newer request (or Destroy) won while this one waited.
	if token ~= self._token or not self._scene then
		return false, "SUPERSEDED"
	end
	if not template then
		return false, problem
	end
	self:_mount(template, key)
	return true, nil
end

function AvatarPreview:_mount(template: Model, key: string)
	self:_unmount()
	local model = template:Clone()
	model.Name = "AvatarPreview"
	model:SetAttribute("PreviewOnly", true)
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = descendant == rootPart
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
		end
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- A preview never falls, ragdolls or shows a name.
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	-- Classic clothing from the rig template would cover the skin colour.
	for _, child in model:GetChildren() do
		if child:IsA("Shirt") or child:IsA("Pants") or child:IsA("ShirtGraphic") then
			child:Destroy()
		end
	end
	self._model = model
	self._template = template
	self._itemsKey = key
	self._posing = false
	if self._poseCycle then
		self._poseTimer = self._poseCycle.idle.Min
	end
	self._rootPart = if rootPart and rootPart:IsA("BasePart") then rootPart else nil
	self._feet = {}
	for _, name in { "LeftFoot", "RightFoot" } do
		local foot = model:FindFirstChild(name)
		if foot and foot:IsA("BasePart") then
			table.insert(self._feet, foot)
		end
	end
	self._face = nil
	self._faceKey = nil
	self._gestureLeft = 0
	self._gestureTimer = 5 + math.random() * 5
	self._blinkTimer = 3 + math.random() * 4
	self._blinkDuration = 0
	local stand = self._standFrame or CFrame.new()
	if self._rootPart then
		self._rootPart.CFrame = stand * CFrame.new(0, 3, 0)
	end
	model.Parent = self._scene
	self._pose = R15Pose.new(model)
	if self._pose then
		self._pose:SetStance(self._stance)
		self._pose:Step(0)
	end
	self:_paint()
	self:_ground(stand)
	self._connection = RunService.RenderStepped:Connect(function(deltaTime)
		self:_step(deltaTime)
	end)
end

-- Skin colour and body scales now; the cyberware next frame, once the
-- humanoid has rescaled the parts it is sized from.
function AvatarPreview:_paint()
	local model, draft = self._model, self._draft
	if not model or not draft then
		return
	end
	local color = AvatarDescription.SkinColor(draft)
	for _, name in BODY_PARTS do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			-- Remove SurfaceAppearance: bundle bodies ship with one and it overrides Color.
			local sa = part:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa:Destroy()
			end
			part.Color = color
			part.Reflectance = 0
			part.Material = Enum.Material.Plastic
		end
	end
	local bodyColors = model:FindFirstChildOfClass("BodyColors")
	if bodyColors then
		bodyColors.HeadColor3 = color
		bodyColors.TorsoColor3 = color
		bodyColors.LeftArmColor3 = color
		bodyColors.RightArmColor3 = color
		bodyColors.LeftLegColor3 = color
		bodyColors.RightLegColor3 = color
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local scales = AvatarDescription.Scales(draft)
		for key, valueName in SCALE_VALUES do
			local value = humanoid:FindFirstChild(valueName)
			if value and value:IsA("NumberValue") then
				value.Value = (scales :: any)[key]
			end
		end
	end
	-- The chosen face, drawn on the head (redrawn only when it changes).
	local faceKey = draft.appearance.faceId .. "|" .. draft.appearance.bodyBaseId
	if faceKey ~= self._faceKey or not self._face then
		self._faceKey = faceKey
		self._gestureLeft = 0
		self._face = AvatarDescription.ApplyFaceExpression(model, draft)
	end
	self._cyberwareDirty = true
end

-- Boxer on every body, plus a bra on the slim body. Sized from the body
-- parts after the humanoid has scaled them, so it runs with the cyberware.
function AvatarPreview:_buildUnderwear()
	local model, draft = self._model, self._draft
	if not model or not draft then
		return
	end
	local old = model:FindFirstChild("Underwear")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Underwear"

	-- yFraction: share of the part's height covered; yAnchor: 1 = top edge, 0 = centre.
	local function cover(partName: string, yFraction: number, yAnchor: number, color: Color3, margin: number?)
		local body = model:FindFirstChild(partName)
		if not body or not body:IsA("BasePart") then
			return
		end
		local pad = margin or UNDERWEAR_MARGIN
		local size = body.Size
		local height = size.Y * yFraction
		local piece = Instance.new("Part")
		piece.Name = partName .. "Cover"
		piece.Size = Vector3.new(size.X + pad, height + pad * 0.5, size.Z + pad)
		piece.Color = color
		piece.Material = Enum.Material.Fabric
		piece.Reflectance = 0
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		piece.CastShadow = false
		local offsetY = (size.Y - height) * 0.5 * yAnchor
		local weld = Instance.new("Weld")
		weld.Part0 = body
		weld.Part1 = piece
		weld.C0 = CFrame.new(0, offsetY, 0)
		weld.Parent = piece
		piece.CFrame = body.CFrame * weld.C0
		piece.Parent = folder
	end

	-- Only where nothing is worn: the rigid pieces would poke through clothes.
	local pieces = CharacterDraft.pieces(draft)
	if pieces.pants == "none" then
		cover("LowerTorso", 1, 0, UNDERWEAR_COLOR)
		cover("LeftUpperLeg", 0.45, 1, UNDERWEAR_COLOR)
		cover("RightUpperLeg", 0.45, 1, UNDERWEAR_COLOR)
		-- Waistband: thin trim along the top of the lower torso.
		cover("LowerTorso", 0.2, 1, UNDERWEAR_TRIM, UNDERWEAR_MARGIN * 2)
	end
	if draft.appearance.bodyBaseId == "slim" and pieces.shirt == "none" and pieces.jacket == "none" then
		-- Chest band, upper-middle of the torso.
		cover("UpperTorso", 0.32, 0.45, UNDERWEAR_COLOR)
	end
	folder.Parent = model
end

-- Keeps the lowest foot on `stand` (and the body facing its direction).
function AvatarPreview:_ground(stand: CFrame)
	local rootPart = self._rootPart
	if not rootPart or #self._feet == 0 then
		return
	end
	local lowest = math.huge
	for _, foot in self._feet do
		lowest = math.min(lowest, partBottomY(foot))
	end
	local height = rootPart.Position.Y - lowest
	rootPart.CFrame = CFrame.new(stand.Position + Vector3.new(0, height, 0)) * stand.Rotation
end

function AvatarPreview:_step(deltaTime: number)
	local model = self._model
	if not model or not self._standFrame then
		return
	end
	if self._cyberwareDirty and self._draft then
		self._cyberwareDirty = false
		R15Cyberware.Build(model, self._draft.cyberwareIds, AvatarDescription.CyberwareStyle(self._draft))
		self:_buildUnderwear()
	end
	local puppet = self._puppet
	if puppet then
		local stand, speed, step = puppet(deltaTime)
		if stand then
			if step and self._pose then
				self._pose:SetLocomotion(speed or 0)
				self._pose:Step(step)
			end
			self:_ground(stand)
		end
		return
	end
	local cycle = self._poseCycle
	if cycle and self._pose then
		self._poseTimer -= deltaTime
		if self._poseTimer <= 0 then
			if self._posing then
				self._posing = false
				self._pose:SetStance(self._stance)
				self._poseTimer = cycle.idle.Min + math.random() * (cycle.idle.Max - cycle.idle.Min)
			else
				self._posing = true
				self._poseIndex = self._poseIndex % #cycle.poses + 1
				self._pose:SetStance(cycle.poses[self._poseIndex])
				self._poseTimer = cycle.hold
			end
		end
	end
	if self._pose then
		self._pose:Step(deltaTime)
	end
	-- Face animation: idle blink and occasional wink.
	-- Gestures: now and then the face flashes another expression, then returns.
	local draft = self._draft
	if self._face and draft then
		if self._gestureLeft > 0 then
			self._gestureLeft -= deltaTime
			if self._gestureLeft <= 0 then
				self._face = AvatarDescription.ApplyFaceExpression(model, draft)
			end
		else
			self._gestureTimer -= deltaTime
			if self._gestureTimer <= 0 then
				self._gestureTimer = 6 + math.random() * 6
				local options = {}
				for _, faceId in FaceArt.Gestures do
					if faceId ~= draft.appearance.faceId then
						table.insert(options, faceId)
					end
				end
				self._gestureLeft = 1.3
				self._face = FaceArt.Apply(model, options[math.random(1, #options)], draft.appearance.bodyBaseId == "slim")
			end
		end
	end
	local fc = self._face
	if fc then
		self._blinkTimer -= deltaTime
		if self._blinkTimer <= 0 then
			self._blinkTimer = 3 + math.random() * 5
			local r = math.random()
			self._winkSide = if r < 0.1 then "left" elseif r < 0.2 then "right" else "both"
			-- A wink is held a little longer than a blink so it reads.
			self._blinkLength = if self._winkSide == "both" then 0.14 else 0.45
			self._blinkDuration = self._blinkLength
		end
		local blink = 0
		if self._blinkDuration > 0 then
			self._blinkDuration -= deltaTime
			local t = 1 - math.max(self._blinkDuration, 0) / self._blinkLength
			blink = math.clamp(if t < 0.25 then t * 4 elseif t > 0.75 then (1 - t) * 4 else 1, 0, 1)
		end
		local leftBlink = if self._winkSide == "both" or self._winkSide == "left" then blink else 0
		local rightBlink = if self._winkSide == "both" or self._winkSide == "right" then blink else 0
		FaceArt.SetLids(fc, rightBlink, leftBlink)
	end
	local difference = (self._targetYaw - self._currentYaw + math.pi) % (2 * math.pi) - math.pi
	local alpha = 1 - math.exp(-self._config.Preview.RotationBlendSpeed * deltaTime)
	self._currentYaw += difference * alpha
	self:_ground(self._standFrame * CFrame.Angles(0, self._currentYaw, 0))
end

function AvatarPreview:Rotate(deltaRadians: number)
	self._targetYaw += deltaRadians
end

function AvatarPreview:Reset()
	self._targetYaw = 0
end

function AvatarPreview:GetModel(): Model?
	return self._model
end

function AvatarPreview:_unmount()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self._model then
		self._model:Destroy()
	end
	self._model = nil
	self._rootPart = nil
	self._feet = {}
	self._pose = nil
	self._face = nil
	self._faceKey = nil
	self._itemsKey = nil
	self._posing = false
end

function AvatarPreview:Destroy()
	self._token += 1
	self:_unmount()
	self._scene = nil
	self._standFrame = nil
	self._currentYaw = 0
	self._targetYaw = 0
end

return AvatarPreview
