--!strict

-- The character portrait inside the health module: by default a live 3D
-- bust of the player's own avatar (a still copy in a ViewportFrame, framed on
-- head and shoulders), so every outfit, hair and implant shows. If
-- HUDConfig.Portrait.Images has art for the class, that image is used
-- instead (one per state). States change the framing and the light:
--   normal   - steady cool light, straight framing
--   gloat    - closer, slightly low and turned, violet key light
--   critical - red light, darker ambient, head lowered (the glitch is drawn
--              by the health module on top)

local HUDConfig = require(script.Parent.HUDConfig)

local Portrait = {}
Portrait.__index = Portrait

export type State = "normal" | "gloat" | "critical"

type Look = { distance: number, height: number, yaw: number, pitch: number, light: Color3, ambient: Color3 }

local LOOKS: { [string]: Look } = {
	normal = { distance = 4.6, height = -0.1, yaw = 20, pitch = 4, light = Color3.fromRGB(215, 240, 255), ambient = Color3.fromRGB(120, 136, 156) },
	gloat = { distance = 3.9, height = -0.15, yaw = 28, pitch = 10, light = Color3.fromRGB(200, 150, 255), ambient = Color3.fromRGB(96, 84, 140) },
	critical = { distance = 4.4, height = 0.0, yaw = 14, pitch = -6, light = Color3.fromRGB(255, 110, 125), ambient = Color3.fromRGB(96, 58, 66) },
}

local STRIP = { "LuaSourceContainer", "Tool", "Sound", "ForceField", "BillboardGui", "ParticleEmitter", "Trail", "Beam" }

function Portrait.new(parent: GuiObject, size: Vector2, position: Vector2, zIndex: number)
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "PortraitView"
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromOffset(size.X, size.Y)
	viewport.Position = UDim2.fromOffset(position.X, position.Y)
	viewport.ZIndex = zIndex
	viewport.LightDirection = Vector3.new(-0.6, -0.4, -0.7)
	viewport.Parent = parent
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local image = Instance.new("ImageLabel")
	image.Name = "PortraitArt"
	image.BackgroundTransparency = 1
	image.Size = viewport.Size
	image.Position = viewport.Position
	image.ScaleType = Enum.ScaleType.Crop
	image.ZIndex = zIndex
	image.Visible = false
	image.Parent = parent

	return setmetatable({
		_viewport = viewport,
		_world = world,
		_camera = camera,
		_image = image,
		_model = nil :: Model?,
		_classId = "",
		_state = "normal" :: State,
		_look = table.clone(LOOKS.normal),
	}, Portrait)
end

-- The art configured for the current class and state, if any.
function Portrait:_art(): string?
	local images = HUDConfig.Portrait.Images[self._classId]
	if not images then
		return nil
	end
	return (images :: any)[self._state] or images.normal
end

-- A still copy of `character` for the bust (rebuilt on respawn or a new outfit).
function Portrait:SetCharacter(character: Model?, classId: string?)
	self._classId = classId or ""
	if self._model then
		self._model:Destroy()
		self._model = nil
	end
	local art = self:_art()
	self._image.Visible = art ~= nil
	self._viewport.Visible = art == nil
	if art then
		self._image.Image = art
		return
	end
	if not character then
		return
	end
	local wasArchivable = character.Archivable
	character.Archivable = true
	local ok, copy = pcall(function()
		return character:Clone()
	end)
	character.Archivable = wasArchivable
	if not ok or not copy then
		return
	end
	for _, descendant in copy:GetDescendants() do
		for _, className in STRIP do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end
	-- A neutral standing pose, so the copy does not keep the aiming arms in
	-- front of the face: every part is placed at its joint's rest position,
	-- walking the joints out from the root. Avatars use Motor6Ds
	-- (Part1 = Part0 * C0 * C1^-1) or AnimationConstraints / RigidConstraints
	-- (Part1 = Attachment0 * Attachment1^-1 at rest).
	type Joint = { part0: BasePart, part1: BasePart, rest: (BasePart) -> CFrame, back: (BasePart) -> CFrame }
	local joints: { Joint } = {}
	for _, descendant in copy:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.LocalTransparencyModifier = 0
		elseif descendant:IsA("Motor6D") and descendant.Part0 and descendant.Part1 then
			local motor = descendant
			table.insert(joints, {
				part0 = motor.Part0 :: BasePart,
				part1 = motor.Part1 :: BasePart,
				rest = function(part0: BasePart): CFrame
					return part0.CFrame * motor.C0 * motor.C1:Inverse()
				end,
				back = function(part1: BasePart): CFrame
					return part1.CFrame * motor.C1 * motor.C0:Inverse()
				end,
			})
		elseif (descendant:IsA("AnimationConstraint") or descendant:IsA("RigidConstraint")) then
			local a0, a1 = descendant.Attachment0, descendant.Attachment1
			local p0 = a0 and a0.Parent
			local p1 = a1 and a1.Parent
			if a0 and a1 and p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				table.insert(joints, {
					part0 = p0,
					part1 = p1,
					rest = function(part0: BasePart): CFrame
						return part0.CFrame * a0.CFrame * a1.CFrame:Inverse()
					end,
					back = function(part1: BasePart): CFrame
						return part1.CFrame * a1.CFrame * a0.CFrame:Inverse()
					end,
				})
			end
		end
	end
	-- Pieces held by WeldConstraints (implants, outfit parts) keep their
	-- offset from the part they are welded to.
	local held = {}
	for _, constraint in copy:GetDescendants() do
		if constraint:IsA("WeldConstraint") and constraint.Part0 and constraint.Part1 then
			table.insert(held, { base = constraint.Part0, piece = constraint.Part1, offset = constraint.Part0.CFrame:ToObjectSpace(constraint.Part1.CFrame) })
		end
	end
	local rootPart = copy:FindFirstChild("HumanoidRootPart")
	local placed: { [BasePart]: boolean } = {}
	if rootPart and rootPart:IsA("BasePart") then
		placed[rootPart] = true
	end
	for _ = 1, #joints do
		local progress = false
		for _, joint in joints do
			if placed[joint.part0] and not placed[joint.part1] then
				joint.part1.CFrame = joint.rest(joint.part0)
				placed[joint.part1] = true
				progress = true
			elseif placed[joint.part1] and not placed[joint.part0] then
				joint.part0.CFrame = joint.back(joint.part1)
				placed[joint.part0] = true
				progress = true
			end
		end
		if not progress then
			break
		end
	end
	for _, entry in held do
		entry.piece.CFrame = entry.base.CFrame * entry.offset
	end
	-- Accessories follow the part they are welded to.
	for _, accessory in copy:GetChildren() do
		if accessory:IsA("Accessory") then
			local handle = accessory:FindFirstChild("Handle")
			local weld = handle and handle:FindFirstChildWhichIsA("Weld")
			if handle and handle:IsA("BasePart") and weld and weld.Part0 and weld.Part1 then
				local other = if weld.Part0 == handle then weld.Part1 else weld.Part0
				handle.CFrame = if weld.Part0 == handle
					then other.CFrame * weld.C1 * weld.C0:Inverse()
					else other.CFrame * weld.C0 * weld.C1:Inverse()
			end
		end
	end
	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	copy:PivotTo(CFrame.identity)
	copy.Parent = self._world
	self._model = copy
	self:_frame()
end

-- Camera on head and shoulders for the current look.
function Portrait:_frame()
	local model = self._model
	local head = model and model:FindFirstChild("Head")
	if not model or not head or not head:IsA("BasePart") then
		return
	end
	local look = self._look
	-- Where the face points: the head's FaceFrontAttachment (R15), else its
	-- LookVector; flattened so the bust stays upright.
	local faceFront = head:FindFirstChild("FaceFrontAttachment")
	local front = if faceFront and faceFront:IsA("Attachment") then faceFront.WorldPosition - head.Position else head.CFrame.LookVector
	front = Vector3.new(front.X, 0, front.Z)
	front = if front.Magnitude > 1e-3 then front.Unit else Vector3.new(0, 0, -1)
	local target = head.Position + Vector3.new(0, -0.35 + look.height, 0)
	local facing = CFrame.lookAt(Vector3.zero, front)
	local orbit = facing * CFrame.Angles(0, math.rad(look.yaw), 0) * CFrame.Angles(math.rad(look.pitch), 0, 0)
	local offset = orbit:VectorToWorldSpace(Vector3.new(0, 0, -look.distance))
	self._camera.CFrame = CFrame.lookAt(target + offset, target)
	-- Key light from the camera's side, a little above and to one side, so
	-- the face is lit whatever way the avatar faces.
	local side = orbit:VectorToWorldSpace(Vector3.new(1, 0, 0))
	self._viewport.LightDirection = (-offset.Unit + Vector3.new(0, -0.55, 0) + side * 0.35).Unit
	self._viewport.LightColor = look.light
	self._viewport.Ambient = look.ambient
end

-- Eases framing and light to `state` over `seconds`.
function Portrait:SetState(state: State)
	if self._state == state then
		return
	end
	self._state = state
	local art = self:_art()
	if art then
		self._image.Image = art
	end
	local from = table.clone(self._look)
	local to = LOOKS[state]
	local duration = HUDConfig.Portrait.TransitionTime
	local started = os.clock()
	task.spawn(function()
		while self._state == state do
			local t = math.clamp((os.clock() - started) / duration, 0, 1)
			local e = 1 - (1 - t) * (1 - t)
			self._look = {
				distance = from.distance + (to.distance - from.distance) * e,
				height = from.height + (to.height - from.height) * e,
				yaw = from.yaw + (to.yaw - from.yaw) * e,
				pitch = from.pitch + (to.pitch - from.pitch) * e,
				light = from.light:Lerp(to.light, e),
				ambient = from.ambient:Lerp(to.ambient, e),
			}
			self:_frame()
			if t >= 1 then
				break
			end
			task.wait()
		end
	end)
end

-- Tint over the portrait (the critical glitch flickers it).
function Portrait:SetTint(color: Color3)
	self._viewport.ImageColor3 = color
	self._image.ImageColor3 = color
end

-- Small sideways jolt of the picture (glitch), in design pixels.
function Portrait:SetOffset(offset: Vector2, base: Vector2)
	local position = UDim2.fromOffset(base.X + offset.X, base.Y + offset.Y)
	self._viewport.Position = position
	self._image.Position = position
end

function Portrait:Destroy()
	self._viewport:Destroy()
	self._image:Destroy()
end

return Portrait
