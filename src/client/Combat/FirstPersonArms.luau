--!strict

-- First-person arms for the local player. The avatar's own forearms and hands
-- (blocky R15 parts about a stud thick) filled the bottom of the screen and
-- hid the weapon, so in first person they stay hidden and these slim local
-- copies are drawn in their place: a dark gauntlet with a neon cuff and a
-- narrower gloved hand. They follow the real parts every frame, so the pose,
-- including the reload, is exactly the one ShooterAnimation computed.
-- Local only (parented to the camera): nobody else sees them.

local RunService = game:GetService("RunService")

local FirstPersonArms = {}

local SLEEVE_COLOR = Color3.fromRGB(24, 26, 34)
local GLOVE_COLOR = Color3.fromRGB(44, 47, 60)
local CUFF_COLOR = Color3.fromRGB(0, 220, 255)
-- Proxy size as a fraction of the real part (X, Y = length, Z).
-- Sleeves cover only the wrist half of the forearm (a gauntlet): the elbow
-- half sits right under the camera.
local SLEEVE_SCALE = Vector3.new(0.3, 0.55, 0.3)
local HAND_SCALE = Vector3.new(0.4, 0.7, 0.45)
local CUFF_HEIGHT = 0.045

type Proxy = { source: string, part: BasePart, cuff: BasePart? }

local SOURCES = table.freeze({
	{ name = "LeftLowerArm", sleeve = true },
	{ name = "RightLowerArm", sleeve = true },
	{ name = "LeftHand", sleeve = false },
	{ name = "RightHand", sleeve = false },
})

local folder: Folder? = nil
local proxies: { Proxy } = {}
local shownFor: Model? = nil
-- Character whose arms are drawn this frame (nil: hidden).
local drawing: Model? = nil
local followConnection: RBXScriptConnection? = nil

local function newPart(name: string, color: Color3, material: Enum.Material): BasePart
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

local function build(camera: Camera)
	FirstPersonArms.clear()
	local holder = Instance.new("Folder")
	holder.Name = "R2059FirstPersonArms"
	for _, source in SOURCES do
		local part = newPart(source.name, if source.sleeve then SLEEVE_COLOR else GLOVE_COLOR, Enum.Material.SmoothPlastic)
		part.Parent = holder
		local cuff: BasePart? = nil
		if source.sleeve then
			cuff = newPart(source.name .. "Cuff", CUFF_COLOR, Enum.Material.Neon)
			cuff.Parent = holder
		end
		table.insert(proxies, { source = source.name, part = part, cuff = cuff })
	end
	holder.Parent = camera
	folder = holder
end

-- Puts the slim copies on the real (hidden) forearms and hands.
local function place(character: Model)
	for _, proxy in proxies do
		local real = character:FindFirstChild(proxy.source)
		if not real or not real:IsA("BasePart") then
			proxy.part.Transparency = 1
			continue
		end
		-- Keep the real arm hidden (Roblox hides the whole body in first person).
		real.LocalTransparencyModifier = 1
		local isHand = proxy.cuff == nil
		local size = real.Size * (if isHand then HAND_SCALE else SLEEVE_SCALE)
		proxy.part.Size = size
		-- Hands centred on the real hand; sleeves slid down to the wrist end (-Y).
		proxy.part.CFrame = if isHand then real.CFrame else real.CFrame * CFrame.new(0, -(real.Size.Y - size.Y) / 2, 0)
		proxy.part.Transparency = 0
		local cuff = proxy.cuff
		if cuff then
			-- At the wrist end (-Y on R15 lower arms).
			cuff.Size = Vector3.new(proxy.part.Size.X * 1.12, CUFF_HEIGHT, proxy.part.Size.Z * 1.12)
			cuff.CFrame = real.CFrame * CFrame.new(0, -real.Size.Y / 2 + 0.14, 0)
			cuff.Transparency = 0
		end
	end
end

-- Each frame (camera step): draw the slim arms over the hidden real ones
-- while in first person, hide them otherwise.
function FirstPersonArms.update(camera: Camera, character: Model?, firstPerson: boolean)
	if not firstPerson or not character then
		drawing = nil
		if folder then
			for _, proxy in proxies do
				proxy.part.Transparency = 1
				if proxy.cuff then
					proxy.cuff.Transparency = 1
				end
			end
		end
		return
	end
	if not folder or folder.Parent ~= camera or shownFor ~= character then
		build(camera)
		shownFor = character
	end
	drawing = character
	place(character)
	if not followConnection then
		-- Copy the hands again once physics has run: the character turns with
		-- the camera during the simulation, so copies made only at the camera
		-- step were a frame behind the weapon and came off it on fast turns.
		followConnection = RunService.PostSimulation:Connect(function()
			local current = drawing
			if current and current.Parent then
				place(current)
			end
		end)
	end
end

function FirstPersonArms.clear()
	drawing = nil
	if followConnection then
		followConnection:Disconnect()
		followConnection = nil
	end
	if folder then
		folder:Destroy()
	end
	folder = nil
	shownFor = nil
	table.clear(proxies)
end

return FirstPersonArms
