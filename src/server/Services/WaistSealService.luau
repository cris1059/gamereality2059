--!strict

-- Fills the waist of every player's character from the inside.
--
-- Roblox does not draw the parts of the body hidden under layered clothing
-- (hidden surface removal, worked out in the clothing's rest pose). When the
-- waist bends or turns in a pose (crouch, aim up / down, lean, slide, walk),
-- the shirt's hem and the trousers' waistband part a little and, with no body
-- drawn behind them, the scene showed straight through the character.
--
-- An opaque dark ellipsoid sits inside the body at the waist joint, welded
-- to the hips, a little smaller than the torso so it never shows through the
-- clothing or the bare body; it is only seen through such a gap, where it
-- reads as the dark lining of the clothes. Not physical: no collisions, no
-- mass, not hit by shots or touches. Built on the server, so every player
-- sees it; rebuilt if the body is rebuilt (avatar changes).

local Players = game:GetService("Players")

local WaistSealService = {}
WaistSealService.__index = WaistSealService

local SEAL_NAME = "WaistSeal"
local SEAL = table.freeze({
	color = Color3.fromRGB(16, 16, 20),
	-- Share of the lower torso's width / depth, and height in studs (centred on
	-- the waist joint, reaching into both torso halves).
	width = 0.86,
	depth = 0.88,
	height = 1.3,
})

function WaistSealService.new()
	return setmetatable({ _connections = {} :: { RBXScriptConnection } }, WaistSealService)
end

local function build(character: Model)
	local lowerTorso = character:FindFirstChild("LowerTorso")
	local upperTorso = character:FindFirstChild("UpperTorso")
	local waist = upperTorso and upperTorso:FindFirstChild("Waist")
	if not lowerTorso or not lowerTorso:IsA("BasePart") or not upperTorso or not upperTorso:IsA("BasePart") then
		return
	end
	local old = character:FindFirstChild(SEAL_NAME)
	if old then
		old:Destroy()
	end
	-- The waist joint in the lower torso's space (Waist.C0), or its top.
	local jointOffset = if waist and (waist:IsA("Motor6D") or waist:IsA("AnimationConstraint"))
		then (waist :: any).C0.Position
		else Vector3.new(0, lowerTorso.Size.Y / 2, 0)
	local seal = Instance.new("Part")
	seal.Name = SEAL_NAME
	seal.Size = Vector3.new(lowerTorso.Size.X * SEAL.width, SEAL.height, lowerTorso.Size.Z * SEAL.depth)
	seal.Color = SEAL.color
	seal.Material = Enum.Material.SmoothPlastic
	seal.CastShadow = false
	seal.CanCollide = false
	seal.CanQuery = false
	seal.CanTouch = false
	seal.Massless = true
	seal.Anchored = false
	seal.CFrame = lowerTorso.CFrame * CFrame.new(jointOffset)
	local shape = Instance.new("SpecialMesh")
	shape.MeshType = Enum.MeshType.Sphere
	shape.Parent = seal
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = lowerTorso
	weld.Part1 = seal
	weld.Parent = seal
	seal.Parent = character
end

function WaistSealService:_watch(character: Model)
	task.defer(build, character)
	-- The body parts are replaced when the avatar changes: build it again.
	table.insert(self._connections, character.ChildAdded:Connect(function(child)
		if child.Name == "LowerTorso" or child.Name == "UpperTorso" then
			task.defer(build, character)
		end
	end))
end

function WaistSealService:Start()
	local function onPlayer(player: Player)
		if player.Character then
			self:_watch(player.Character)
		end
		table.insert(self._connections, player.CharacterAdded:Connect(function(character)
			self:_watch(character)
		end))
	end
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	table.insert(self._connections, Players.PlayerAdded:Connect(onPlayer))
end

return WaistSealService
