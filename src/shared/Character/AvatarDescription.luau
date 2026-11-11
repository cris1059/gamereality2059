--!strict

-- CharacterDraft -> HumanoidDescription for a standard R15 avatar. Shared, so
-- the server (real characters, preview models) and the tests agree on every
-- catalog item.
--   Build(draft, withLook): hair, outfit and accessories on the blocky head;
--   withLook also sets skin colour (preview models are painted client-side).
--   ItemsKey(draft): the catalog combination (preview model cache key).
--   ApplyFaceExpression(model, draft): draws the face on the head (FaceArt).

local root = script.Parent.Parent
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local CharacterDraft = require(script.Parent.CharacterDraft)
local FaceArt = require(script.Parent.FaceArt)

local AvatarDescription = {}

local RIGID_TYPES = table.freeze({
	Hat = Enum.AccessoryType.Hat,
	Hair = Enum.AccessoryType.Hair,
	Face = Enum.AccessoryType.Face,
})

-- bodyBaseId is included because the body width differs per base.
function AvatarDescription.ItemsKey(draft): string
	local accessories = table.clone(draft.outfit.accessoryIds)
	table.sort(accessories)
	local pieces = CharacterDraft.pieces(draft)
	local worn = {}
	for _, slot in CharacterCatalog.OutfitSlots do
		table.insert(worn, pieces[slot] or "none")
	end
	return string.format("%s|%s|%s|%s", draft.appearance.bodyBaseId, draft.appearance.hairId, table.concat(worn, "+"), table.concat(accessories, ","))
end

-- Draws the draft's face on the model's head (slim bodies get lashes).
function AvatarDescription.ApplyFaceExpression(model: Model, draft)
	return FaceArt.Apply(model, draft.appearance.faceId, draft.appearance.bodyBaseId == "slim")
end

-- Entries for HumanoidDescription:SetAccessories (rigid and layered).
function AvatarDescription.Accessories(draft): { any }
	local list = {}
	local hair = CharacterCatalog.HairInfo[draft.appearance.hairId]
	if hair and hair.assetId > 0 then
		table.insert(list, { AssetId = hair.assetId, AccessoryType = Enum.AccessoryType.Hair, IsLayered = false })
	end
	for _, accessoryId in draft.outfit.accessoryIds do
		local info = CharacterCatalog.AccessoryInfo[accessoryId]
		if info then
			table.insert(list, { AssetId = info.assetId, AccessoryType = RIGID_TYPES[info.kind] or Enum.AccessoryType.Hat, IsLayered = false })
		end
	end
	-- Layer order: higher is worn over lower (shoes over the pants' hems,
	-- the shirt untucked, the jacket on top).
	local pieces = CharacterDraft.pieces(draft)
	local info = CharacterCatalog.PieceInfo
	local pants = info.pants[pieces.pants or ""]
	if pants then
		table.insert(list, { AssetId = pants.assetId, AccessoryType = Enum.AccessoryType.Pants, IsLayered = true, Order = 2 })
	end
	local shoes = info.shoes[pieces.shoes or ""]
	if shoes then
		table.insert(list, { AssetId = shoes.left, AccessoryType = Enum.AccessoryType.LeftShoe, IsLayered = true, Order = 3 })
		table.insert(list, { AssetId = shoes.right, AccessoryType = Enum.AccessoryType.RightShoe, IsLayered = true, Order = 3 })
	end
	local shirt = info.shirt[pieces.shirt or ""]
	if shirt then
		local kind = if shirt.type == "TShirt" then Enum.AccessoryType.TShirt else Enum.AccessoryType.Shirt
		table.insert(list, { AssetId = shirt.assetId, AccessoryType = kind, IsLayered = true, Order = 4 })
	end
	local jacket = info.jacket[pieces.jacket or ""]
	if jacket then
		table.insert(list, { AssetId = jacket.assetId, AccessoryType = Enum.AccessoryType.Jacket, IsLayered = true, Order = 6 })
	end
	return list
end

-- Body proportions: classic = standard width, slim = narrower shoulders/hips.
-- Sliders were removed; scales are now fixed by body base only.
function AvatarDescription.Scales(draft): { height: number, width: number, depth: number, head: number }
	local body = CharacterCatalog.BodyInfo[draft.appearance.bodyBaseId]
	local w = if body then body.width else 1
	return { height = 1, width = w, depth = w, head = 1 }
end

function AvatarDescription.SkinColor(draft): Color3
	return CharacterCatalog.SkinToneColors[draft.appearance.skinToneId] or CharacterCatalog.SkinToneColors.neutral_medium
end

-- COLOR slots resolved for the cyberware builder (Character/R15Cyberware).
function AvatarDescription.CyberwareStyle(draft)
	local ids = draft.colors or CharacterCatalog.DefaultColors
	local metal = CharacterCatalog.MetalFinishValues[ids.metal] or CharacterCatalog.MetalFinishValues.gunmetal
	return {
		accent = CharacterCatalog.NeonColorValues[ids.neonPrimary] or CharacterCatalog.NeonColorValues.red,
		secondary = CharacterCatalog.NeonColorValues[ids.neonSecondary] or CharacterCatalog.NeonColorValues.cyan,
		metal = metal.color,
		metalReflectance = metal.reflectance,
	}
end

function AvatarDescription.Build(draft, withLook: boolean?): HumanoidDescription
	local description = Instance.new("HumanoidDescription")
	description:SetAccessories(AvatarDescription.Accessories(draft), true)
	-- Blocky proportions for everyone: the Rthro sliders stay at 0.
	description.BodyTypeScale = 0
	description.ProportionScale = 0
	local scales = AvatarDescription.Scales(draft)
	description.HeightScale = scales.height
	description.WidthScale = scales.width
	description.DepthScale = scales.depth
	description.HeadScale = scales.head
	if withLook then
		local color = AvatarDescription.SkinColor(draft)
		description.HeadColor = color
		description.TorsoColor = color
		description.LeftArmColor = color
		description.RightArmColor = color
		description.LeftLegColor = color
		description.RightLegColor = color
	end
	return description
end

return AvatarDescription
