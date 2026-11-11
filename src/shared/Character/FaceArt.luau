--!strict

-- Drawn faces for the blocky R15 head. A face is eyes, brows and a mouth
-- built from GUI frames, shaped by the face's entry in
-- CharacterCatalog.FaceExpressions (FaceControls-style channels, 0..1). The
-- same drawing is used on the MORPHLAB cards and, through a SurfaceGui, on
-- the avatar's head, so the face picked is exactly the face worn.

local root = script.Parent.Parent
local CharacterCatalog = require(root.Catalog.CharacterCatalog)

local FaceArt = {}

local INK = Color3.fromRGB(28, 22, 38)
local TEETH = Color3.fromRGB(240, 238, 245)
local SURFACE_NAME = "DrawnFace"
-- Gestures the preview flashes now and then (see AvatarPreview).
FaceArt.Gestures = table.freeze({ "grin", "asombro", "smile", "check_it" })

export type Handle = {
	eyes: { { frame: Frame, height: number } },
	canvas: Frame,
}

local function box(parent: Instance, name: string, size: UDim2, position: UDim2, color: Color3, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.Parent = parent
	return frame
end

local function round(frame: Frame)
	local item = Instance.new("UICorner")
	item.CornerRadius = UDim.new(0.5, 0)
	item.Parent = frame
end

-- Draws `faceId` inside `canvas` (a transparent square; features use scale
-- positions). `pixels` is the canvas size, for line widths.
function FaceArt.Draw(canvas: Frame, faceId: string, pixels: number, female: boolean?): Handle
	canvas:ClearAllChildren()
	local expression = CharacterCatalog.FaceExpressions[faceId] or {}
	local function value(channel: string): number
		return (expression :: any)[channel] or 0
	end
	local line = math.max(1.5, pixels * 0.055)
	local eyes = {}
	-- Viewer's left is the character's right.
	for _, entry in { { "Right", 0.32, 1 }, { "Left", 0.68, -1 } } do
		local side, x, inward = entry[1] :: string, entry[2] :: number, entry[3] :: number
		local open = math.clamp(1 - value(side .. "EyeClosed") + 0.5 * value(side .. "EyeUpperLidRaiser"), 0.15, 1.5)
		local height = 0.17 * open * (if female then 1.1 else 1)
		local eye = box(canvas, "Eye", UDim2.fromScale(if female then 0.13 else 0.12, height), UDim2.fromScale(x, 0.44), INK)
		round(eye)
		local glint = box(eye, "Glint", UDim2.fromScale(0.35, 0.25), UDim2.fromScale(0.68, 0.3), Color3.new(1, 1, 1), 0.15)
		round(glint)
		table.insert(eyes, { frame = eye, height = height })
		if female then
			local lash = box(canvas, "Lash", UDim2.fromScale(0.07, 0.03), UDim2.fromScale(x - inward * 0.075, 0.44 - height * 0.5 - 0.005), INK)
			lash.Rotation = inward * 35
		end
		local lower = value(side .. "BrowLowerer")
		local innerRaise = value(side .. "InnerBrowRaiser")
		local raise = 0.6 * innerRaise + 0.4 * value(side .. "OuterBrowRaiser")
		local brow = box(canvas, "Brow", UDim2.fromScale(0.22, if female then 0.04 else 0.055), UDim2.fromScale(x, 0.25 + 0.05 * lower - 0.08 * raise), INK)
		brow.Rotation = inward * (20 * lower - 14 * innerRaise)
	end
	local jaw = value("JawDrop")
	local pull = (value("LeftLipCornerPuller") + value("RightLipCornerPuller")) / 2
	local frown = (value("LeftLipCornerDepressor") + value("RightLipCornerDepressor")) / 2
	local skew = value("RightLipCornerPuller") - value("LeftLipCornerPuller")
	local lineScale = line / pixels
	if jaw >= 0.45 then
		-- Open mouth (surprise): dark oval with the tongue.
		local mouth = box(canvas, "Mouth", UDim2.fromScale(0.18 + 0.1 * jaw, 0.12 + 0.18 * jaw), UDim2.fromScale(0.5, 0.74), INK)
		round(mouth)
		local tongue = box(mouth, "Tongue", UDim2.fromScale(0.6, 0.3), UDim2.fromScale(0.5, 0.78), Color3.fromRGB(200, 80, 100))
		round(tongue)
	elseif pull >= 0.3 and jaw > 0.15 then
		-- Grin: a row of teeth between the lips.
		local width = 0.34 + 0.1 * pull
		local lips = box(canvas, "Mouth", UDim2.fromScale(width + lineScale * 2, 0.1 + lineScale * 2), UDim2.fromScale(0.5, 0.73), INK)
		round(lips)
		round(box(canvas, "Teeth", UDim2.fromScale(width, 0.1), UDim2.fromScale(0.5, 0.73), TEETH))
	else
		-- A curved line: corners up for a smile, down for a frown, one corner
		-- up for a smirk. Drawn as short segments (no clipping), so it reads
		-- the same on the cards and on the head.
		local width = 0.3 + 0.1 * pull
		local depth = 0.075 * pull - 0.06 * frown
		local tilt = 0.07 * skew
		local points = {}
		for index = 0, 8 do
			local u = index / 8 * 2 - 1
			table.insert(points, Vector2.new(0.5 + u * width / 2, 0.72 + depth * (1 - u * u) + tilt * u))
		end
		for index = 1, #points - 1 do
			local a, b = points[index], points[index + 1]
			local delta = b - a
			local bar = box(canvas, "MouthLine", UDim2.fromScale(delta.Magnitude + lineScale * 0.8, lineScale), UDim2.fromScale((a.X + b.X) / 2, (a.Y + b.Y) / 2), INK)
			bar.Rotation = math.deg(math.atan2(delta.Y, delta.X))
			round(bar)
		end
	end
	if faceId == "vampire" then
		for _, x in { 0.42, 0.58 } do
			box(canvas, "Fang", UDim2.fromScale(0.05, 0.08), UDim2.fromScale(x, 0.8), TEETH)
		end
	end
	return { eyes = eyes, canvas = canvas }
end

-- Lids: 0 = resting, 1 = shut. Eyes are { character right, character left }.
function FaceArt.SetLids(handle: Handle, right: number, left: number)
	for index, eye in handle.eyes do
		local shut = if index == 1 then right else left
		local size = eye.frame.Size
		eye.frame.Size = UDim2.fromScale(size.X.Scale, math.max(eye.height * (1 - shut), 0.012))
	end
end

-- Puts the face on the model's head (front face), replacing the classic
-- decal. Lit like the skin, never self-lit. Returns the handle, or nil.
function FaceArt.Apply(model: Model, faceId: string, female: boolean?): Handle?
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	-- Every other face source on the head goes, or its mouth shows under
	-- ours: decals and textures, a face baked into the head mesh's texture,
	-- and dynamic-head face controls.
	for _, child in head:GetChildren() do
		if child:IsA("Decal") or child:IsA("FaceControls") or child:IsA("SurfaceAppearance") then
			child:Destroy()
		end
	end
	if head:IsA("MeshPart") then
		pcall(function()
			(head :: any).TextureID = ""
		end)
	end
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	if mesh then
		mesh.TextureId = ""
	end
	local surface = head:FindFirstChild(SURFACE_NAME)
	if not surface or not surface:IsA("SurfaceGui") then
		local created = Instance.new("SurfaceGui")
		created.Name = SURFACE_NAME
		created.Face = Enum.NormalId.Front
		created.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		created.CanvasSize = Vector2.new(100, 100)
		created.LightInfluence = 1
		created.Brightness = 1
		created.Parent = head
		surface = created
	end
	local canvas = surface:FindFirstChild("Canvas")
	if not canvas or not canvas:IsA("Frame") then
		local created = Instance.new("Frame")
		created.Name = "Canvas"
		created.Size = UDim2.fromScale(1, 1)
		created.BackgroundTransparency = 1
		created.Parent = surface
		canvas = created
	end
	return FaceArt.Draw(canvas :: Frame, faceId, 100, female)
end

-- SurfaceGuis do not render inside ViewportFrames: this copies the drawn
-- face onto the head as thin parts (ovals use a sphere mesh), for portraits.
function FaceArt.ToParts(model: Model)
	local head = model:FindFirstChild("Head")
	local surface = head and head:FindFirstChild(SURFACE_NAME)
	local canvas = surface and surface:FindFirstChild("Canvas")
	if not head or not head:IsA("BasePart") or not canvas then
		return
	end
	local holder = Instance.new("Model")
	holder.Name = "FaceParts"
	holder.Parent = model
	local size = head.Size
	local function slab(cx: number, cy: number, w: number, h: number, rotation: number, depth: number, color: Color3, rounded: boolean)
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Material = Enum.Material.SmoothPlastic
		part.Color = color
		part.Size = Vector3.new(math.max(w * size.X, 0.01), math.max(h * size.Y, 0.01), 0.01)
		-- Canvas left is the head's +X side; the front face is -Z.
		part.CFrame = head.CFrame * CFrame.new((0.5 - cx) * size.X, (0.5 - cy) * size.Y, -size.Z / 2 - depth) * CFrame.Angles(0, 0, math.rad(rotation))
		if rounded then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		part.Parent = holder
	end
	local function emit(frame: Frame, cx: number, cy: number, w: number, h: number, rotation: number, depth: number)
		if frame.Visible and frame.BackgroundTransparency < 0.9 then
			local radius = frame:FindFirstChildOfClass("UICorner")
			slab(cx, cy, w, h, rotation, depth, frame.BackgroundColor3, radius ~= nil and radius.CornerRadius.Scale >= 0.3)
		end
		for _, child in frame:GetChildren() do
			if child:IsA("Frame") then
				emit(child, cx + (child.Position.X.Scale - 0.5) * w, cy + (child.Position.Y.Scale - 0.5) * h, child.Size.X.Scale * w, child.Size.Y.Scale * h, rotation + child.Rotation, depth + 0.004)
			end
		end
	end
	for _, child in canvas:GetChildren() do
		if child:IsA("Frame") then
			emit(child, child.Position.X.Scale, child.Position.Y.Scale, child.Size.X.Scale, child.Size.Y.Scale, child.Rotation, 0.006)
		end
	end
end

return FaceArt
