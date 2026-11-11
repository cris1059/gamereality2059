--!strict

-- Cyberware for standard R15 avatars: small part assemblies welded to the
-- body parts (Head, UpperTorso, RightLowerArm), sized from the parts' current
-- size so they follow any body scale. Used on the server for real characters
-- (replicates) and on the client for previews. Rebuild after rescaling.
--
-- Part space: -Z is the front, +X the character's right. The classic face
-- sits on the head's front face with the eyes slightly above centre.

local R15Cyberware = {}

-- style = { accent, secondary, metal, metalReflectance } (AvatarDescription.CyberwareStyle).

-- Visible size of a body part (classic heads are a Part with a SpecialMesh).
local function visibleSize(part: BasePart): Vector3
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and part.Name == "Head" then
		return Vector3.one * 1.2 * (mesh.Scale.Y / 1.25)
	end
	return part.Size
end

function R15Cyberware.Build(model: Model, implantIds: { string }, style): Folder?
	local existing = model:FindFirstChild("Cyberware")
	if existing then
		existing:Destroy()
	end
	local head = model:FindFirstChild("Head")
	local torso = model:FindFirstChild("UpperTorso")
	local forearm = model:FindFirstChild("RightLowerArm")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	local folder = Instance.new("Folder")
	folder.Name = "Cyberware"

	local function piece(name: string, body: BasePart, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
		local item = Instance.new("Part")
		item.Name = name
		item.Shape = shape or Enum.PartType.Block
		item.Size = size
		item.CFrame = body.CFrame * offset
		item.Color = color
		item.Material = material
		item.Reflectance = if material == Enum.Material.Metal then style.metalReflectance or 0 else 0
		item.Anchored = false
		item.Massless = true
		item.CanCollide = false
		item.CanQuery = false
		item.CanTouch = false
		item.CastShadow = false
		item.TopSurface = Enum.SurfaceType.Smooth
		item.BottomSurface = Enum.SurfaceType.Smooth
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = item
		weld.Parent = item
		item.Parent = folder
		return item
	end
	-- Cylinder whose axis (part X) points along the part's Z (out of the face).
	local facing = CFrame.Angles(0, math.rad(90), 0)

	local h = visibleSize(head)
	local front = -h.Z * 0.5
	local eyeY = h.Y * 0.1
	for _, implantId in implantIds do
		if implantId == "cyber_eye" then
			-- Bionic lens over the right eye with an arm to the temple.
			local x = h.X * 0.17
			piece("BionicEyeHousing", head, Vector3.new(0.06, h.X * 0.32, h.X * 0.32), CFrame.new(x, eyeY, front - 0.02) * facing, style.metal, Enum.Material.Metal, Enum.PartType.Cylinder)
			piece("BionicEyeLens", head, Vector3.new(0.07, h.X * 0.2, h.X * 0.2), CFrame.new(x, eyeY, front - 0.035) * facing, style.accent, Enum.Material.Neon, Enum.PartType.Cylinder)
			piece("BionicEyeArm", head, Vector3.new(h.X * 0.2, 0.05, 0.05), CFrame.new(h.X * 0.4, eyeY, front - 0.02), style.metal, Enum.Material.Metal)
			piece("BionicEyeTemple", head, Vector3.new(0.05, 0.05, h.Z * 0.35), CFrame.new(h.X * 0.5 + 0.02, eyeY, front + h.Z * 0.17), style.metal, Enum.Material.Metal)
		elseif implantId == "visor" then
			-- Augmented-reality band across both eyes.
			local band = piece("VisorBand", head, Vector3.new(h.X * 1.04, h.Y * 0.2, 0.05), CFrame.new(0, eyeY, front - 0.04), style.secondary, Enum.Material.Neon)
			band.Transparency = 0.4
			piece("VisorFrame", head, Vector3.new(h.X * 1.06, h.Y * 0.05, 0.08), CFrame.new(0, eyeY + h.Y * 0.12, front - 0.04), style.metal, Enum.Material.Metal)
			for _, side in { -1, 1 } do
				piece("VisorHinge", head, Vector3.new(0.08, h.Y * 0.18, h.Z * 0.3), CFrame.new(side * (h.X * 0.5 + 0.03), eyeY, front + h.Z * 0.12), style.metal, Enum.Material.Metal)
			end
		elseif implantId == "jaw_plate" then
			-- Armour on the left jaw, wrapping round the side.
			local y = -h.Y * 0.3
			piece("JawPlate", head, Vector3.new(h.X * 0.42, h.Y * 0.18, 0.06), CFrame.new(-h.X * 0.24, y, front - 0.03), style.metal, Enum.Material.Metal)
			piece("JawPlateSide", head, Vector3.new(0.06, h.Y * 0.18, h.Z * 0.45), CFrame.new(-h.X * 0.5 - 0.03, y, front + h.Z * 0.22), style.metal, Enum.Material.Metal)
			piece("JawPlateSlit", head, Vector3.new(h.X * 0.3, h.Y * 0.03, 0.065), CFrame.new(-h.X * 0.24, y, front - 0.035), style.accent, Enum.Material.Neon)
		elseif implantId == "face_circuits" then
			-- Neon traces on the left cheek running to the side of the head.
			local x = -h.X * 0.33
			local low = -h.Y * 0.26
			piece("FaceCircuit1", head, Vector3.new(0.035, h.Y * 0.32, 0.03), CFrame.new(x, -h.Y * 0.1, front - 0.012), style.accent, Enum.Material.Neon)
			piece("FaceCircuit2", head, Vector3.new(h.X * 0.17, 0.035, 0.03), CFrame.new(x - h.X * 0.085, low, front - 0.012), style.accent, Enum.Material.Neon)
			piece("FaceCircuit3", head, Vector3.new(0.03, 0.035, h.Z * 0.55), CFrame.new(-h.X * 0.5 - 0.012, low, front + h.Z * 0.27), style.accent, Enum.Material.Neon)
			for index, point in { Vector3.new(x, h.Y * 0.06, front - 0.015), Vector3.new(-h.X * 0.5 - 0.015, low, front + h.Z * 0.55) } do
				piece("FaceCircuitNode" .. index, head, Vector3.one * 0.08, CFrame.new(point), style.accent, Enum.Material.Neon, Enum.PartType.Ball)
			end
		elseif implantId == "neck_ports" and torso and torso:IsA("BasePart") then
			-- Three interface ports on the back, just under the neck.
			local t = torso.Size
			for index, x in { -0.18, 0, 0.18 } do
				local offset = CFrame.new(x * t.X, t.Y * 0.36, t.Z * 0.5 + 0.02) * facing
				piece("NeckPort" .. index, torso, Vector3.new(0.06, 0.18, 0.18), offset, style.metal, Enum.Material.Metal, Enum.PartType.Cylinder)
				piece("NeckPortLight" .. index, torso, Vector3.new(0.07, 0.09, 0.09), offset * CFrame.new(0.005, 0, 0), style.accent, Enum.Material.Neon, Enum.PartType.Cylinder)
			end
		elseif implantId == "cyber_arm" and forearm and forearm:IsA("BasePart") then
			-- Armoured right forearm: three bands and a neon strip outside.
			local a = forearm.Size
			for index, y in { 0.28, -0.05, -0.36 } do
				piece("ArmBand" .. index, forearm, Vector3.new(a.X + 0.06, a.Y * 0.12, a.Z + 0.06), CFrame.new(0, y * a.Y, 0), style.metal, Enum.Material.Metal)
			end
			piece("ArmStrip", forearm, Vector3.new(0.05, a.Y * 0.78, a.Z * 0.18), CFrame.new(a.X * 0.5 + 0.04, -0.04 * a.Y, 0), style.accent, Enum.Material.Neon)
		end
	end
	folder.Parent = model
	return folder
end

return R15Cyberware
