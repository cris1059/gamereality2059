--!strict

-- Standard R15 avatars: the HumanoidDescription built from a draft, the
-- cyberware welded to a real rig and the procedural pose (Studio only; the
-- rig is built by Roblox from a plain description, so this yields).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local CharacterDraft = require(root.Character.CharacterDraft)
local AvatarDescription = require(root.Character.AvatarDescription)
local R15Cyberware = require(root.Character.R15Cyberware)
local R15Pose = require(root.Character.R15Pose)
local LobbyConfig = require(root.Config.LobbyConfig)
local AvatarService = require(script.Parent.Parent.Services.AvatarService)

local AvatarTests = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error("R15 avatar test failed: " .. message, 2)
	end
end

local function angleOf(frame: CFrame): number
	local _, angle = frame:ToAxisAngle()
	return math.deg(angle)
end

function AvatarTests.run(): { passed: number, total: number }
	local passed = 0

	-- Description: the catalog items and, with the look, skin and scales.
	local draft = CharacterDraft.createDefault()
	CharacterDraft.setHair(draft, "spiky_white")
	CharacterDraft.setOutfit(draft, "neon_nomad")
	CharacterDraft.toggleAccessory(draft, "visor_purple")
	local accessories = AvatarDescription.Accessories(draft)
	local ids = {}
	for _, entry in accessories do
		ids[entry.AssetId] = entry
	end
	local outfit = CharacterCatalog.OutfitInfo.neon_nomad
	expect(ids[CharacterCatalog.HairInfo.spiky_white.assetId] ~= nil, "hair missing from the description")
	expect(ids[CharacterCatalog.AccessoryInfo.visor_purple.assetId] ~= nil, "accessory missing from the description")
	expect(ids[outfit.jacket] and ids[outfit.jacket].IsLayered and ids[outfit.pants] and ids[outfit.pants].IsLayered, "outfit must be layered clothing")
	expect(ids[outfit.jacket].Order > ids[outfit.pants].Order, "the jacket must be worn over the pants")
	-- Pieces are independent: shoes and a shirt add on, pants can come off.
	expect(CharacterDraft.setPiece(draft, "shoes", "sneaker_black") and CharacterDraft.setPiece(draft, "shirt", "tee_black"), "pieces must be settable")
	expect(CharacterDraft.setPiece(draft, "pants", "none"), "a piece must be removable")
	expect(not CharacterDraft.setPiece(draft, "shoes", "flip_flops"), "unknown pieces must be rejected")
	local pieceIds = {}
	for _, entry in AvatarDescription.Accessories(draft) do
		pieceIds[entry.AssetId] = entry
	end
	local shoes = CharacterCatalog.PieceInfo.shoes.sneaker_black
	expect(pieceIds[shoes.left] and pieceIds[shoes.right], "both shoes must be worn")
	expect(pieceIds[CharacterCatalog.PieceInfo.shirt.tee_black.assetId] ~= nil, "the shirt must be worn")
	expect(pieceIds[outfit.pants] == nil, "removed pants must not be worn")
	CharacterDraft.setOutfit(draft, "neon_nomad")
	local description = AvatarDescription.Build(draft, true)
	expect(description.BodyTypeScale == 0 and description.ProportionScale == 0, "avatars must keep blocky proportions")
	expect(description.HeadColor == CharacterCatalog.SkinToneColors.neutral_medium, "skin colour must reach the description")
	-- Blocky head for everyone: the face is drawn on it (FaceArt).
	expect(description.Head == 0, "avatars must keep the classic blocky head")
	local other = CharacterDraft.clone(draft)
	CharacterDraft.setSkinTone(other, "synth_azure")
	expect(AvatarDescription.ItemsKey(other) == AvatarDescription.ItemsKey(draft), "skin tone must not change the items key")
	CharacterDraft.setFace(other, "stare")
	expect(AvatarDescription.ItemsKey(other) == AvatarDescription.ItemsKey(draft), "face expression must not change the items key")
	CharacterDraft.setBodyBase(other, "slim")
	expect(AvatarDescription.ItemsKey(other) ~= AvatarDescription.ItemsKey(draft), "body base must change the items key")
	CharacterDraft.setHair(other, "pal")
	expect(AvatarDescription.ItemsKey(other) ~= AvatarDescription.ItemsKey(draft), "a different hairstyle must change the items key")
	for _, faceId in CharacterCatalog.Faces do
		local info = CharacterCatalog.FaceInfo[faceId]
		expect(info ~= nil, "face " .. faceId .. " must have a FaceInfo entry")
		expect(CharacterCatalog.FaceExpressions[faceId] ~= nil, "face " .. faceId .. " must have a FaceExpressions entry")
	end
	description:Destroy()
	passed += 1

	-- A real R15 rig (plain description: no catalog downloads needed).
	local rig, problem = AvatarService.BuildModel(Instance.new("HumanoidDescription"))
	expect(rig ~= nil, "Roblox could not build an R15 rig: " .. tostring(problem))
	local model = rig :: Model
	for _, descendant in model:GetDescendants() do
		expect(not descendant:IsA("LuaSourceContainer"), "preview rigs must not carry scripts")
	end
	local head = model:FindFirstChild("Head")
	expect(head ~= nil and head:IsA("BasePart"), "the rig needs a Head part")
	-- The face is drawn on the head and replaces the classic decal.
	CharacterDraft.setFace(draft, "asombro")
	AvatarDescription.ApplyFaceExpression(model, draft)
	local drawn = (head :: BasePart):FindFirstChild("DrawnFace")
	expect(drawn ~= nil and drawn:IsA("SurfaceGui"), "the face must be drawn on the head")
	expect((head :: BasePart):FindFirstChild("face") == nil, "the classic face decal must be removed")
	local canvas = (drawn :: SurfaceGui):FindFirstChild("Canvas")
	expect(canvas ~= nil and canvas:FindFirstChild("Mouth") ~= nil, "asombro must draw an open mouth")

	-- Cyberware: every implant builds, welded (not anchored) to the body.
	local implants = {}
	for _, implantId in CharacterCatalog.Implants do
		if implantId ~= "none" then
			table.insert(implants, implantId)
		end
	end
	local folder = R15Cyberware.Build(model, implants, AvatarDescription.CyberwareStyle(draft))
	expect(folder ~= nil and #folder:GetChildren() >= #implants, "cyberware pieces were not built")
	for _, piece in (folder :: Folder):GetChildren() do
		expect(piece:IsA("BasePart") and not piece.Anchored and not piece.CanCollide, "cyberware must be welded, not anchored or solid")
		expect(piece:FindFirstChildOfClass("WeldConstraint") ~= nil, "cyberware piece without a weld: " .. piece.Name)
	end
	R15Cyberware.Build(model, { "none" }, AvatarDescription.CyberwareStyle(draft))
	local rebuilt = model:FindFirstChild("Cyberware")
	expect(rebuilt ~= nil and #rebuilt:GetChildren() == 0, "rebuilding must replace the previous cyberware")
	passed += 1

	-- Pose: the walk swings the hips both ways and bends the knees; standing
	-- still settles back; every stance stays finite.
	local pose = R15Pose.new(model)
	expect(pose ~= nil, "R15Pose could not find the rig's joints")
	local hip = (model:FindFirstChild("LeftUpperLeg") :: Instance):FindFirstChild("LeftHip") :: Motor6D
	local knee = (model:FindFirstChild("LeftLowerLeg") :: Instance):FindFirstChild("LeftKnee") :: Motor6D
	local forward, backward, kneeMax = 0, 0, 0
	;(pose :: any):SetLocomotion(14)
	for step = 1, 120 do
		(pose :: any):Step(1 / 30)
		if step > 30 then
			local x = hip.Transform:ToEulerAnglesXYZ()
			forward = math.max(forward, math.deg(x))
			backward = math.min(backward, math.deg(x))
			kneeMax = math.max(kneeMax, angleOf(knee.Transform))
		end
	end
	expect(forward > 15 and backward < -15, "the walk does not swing the hip both ways")
	expect(kneeMax > 15, "the walk does not bend the knee")
	;(pose :: any):SetLocomotion(0)
	for _ = 1, 90 do
		(pose :: any):Step(1 / 30)
	end
	expect(angleOf(hip.Transform) < 3, "the legs do not return to the idle")
	for name, stance in LobbyConfig.Stances do
		(pose :: any):SetStance(stance)
		for _ = 1, 30 do
			(pose :: any):Step(1 / 30)
		end
		for _, value in { ((model:FindFirstChild("RightUpperArm") :: Instance):FindFirstChild("RightShoulder") :: Motor6D).Transform:GetComponents() } do
			expect(value == value and math.abs(value) < math.huge, "stance " .. name .. " produced an invalid transform")
		end
	end
	;(pose :: any):Reset()
	model:Destroy()
	passed += 1

	return { passed = passed, total = 3 }
end

return AvatarTests
