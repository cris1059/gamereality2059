--!strict

-- Character draft and catalog (standard R15 avatars).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local CharacterDraft = require(root.Character.CharacterDraft)
local CharacterValidator = require(root.Validation.CharacterValidator)

local PhaseC31Tests = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error("Phase C.3.1 test failed: " .. message, 2)
	end
end

function PhaseC31Tests.run(): { passed: number, total: number }
	local checks = 0
	local function check(condition: boolean, message: string)
		expect(condition, message)
		checks += 1
	end

	local draft = CharacterDraft.createDefault()
	check(CharacterValidator.validate(draft), "default draft must remain compatible with CharacterValidator")
	check(draft.rigType == "R15" and draft.avatarVersion == CharacterValidator.AvatarVersion, "default draft must be a standard R15 avatar")
	check(draft.appearance.skinToneId == "neutral_medium", "default tone must match PlayerSchema")
	check(draft.appearance.bodyBaseId == "classic", "default body base must be stable")

	-- Every catalog id has its data, and catalog asset ids are real numbers.
	for _, toneId in CharacterCatalog.SkinTones do
		check(CharacterCatalog.SkinToneColors[toneId] ~= nil, "every tone ID needs a visual color: " .. toneId)
	end
	for _, bodyId in CharacterCatalog.BodyBases do
		local info = CharacterCatalog.BodyInfo[bodyId]
		check(info ~= nil and info.width > 0 and info.width <= 1, "body base needs a width: " .. bodyId)
	end
	for _, faceId in CharacterCatalog.Faces do
		local info = CharacterCatalog.FaceInfo[faceId]
		local expr = CharacterCatalog.FaceExpressions[faceId]
		check(info ~= nil and type(info.name) == "string", "face needs a FaceInfo entry: " .. faceId)
		check(expr ~= nil, "face needs a FaceExpressions entry: " .. faceId)
	end
	for _, hairId in CharacterCatalog.Hair do
		local info = CharacterCatalog.HairInfo[hairId]
		check(info ~= nil and (hairId == "none") == (info.assetId == 0), "hairstyle needs an asset id: " .. hairId)
	end
	for _, outfitId in CharacterCatalog.Outfits do
		local info = CharacterCatalog.OutfitInfo[outfitId]
		check(info ~= nil and info.jacket > 0 and info.pants > 0, "outfit needs a jacket and pants: " .. outfitId)
	end
	for _, slot in CharacterCatalog.OutfitSlots do
		local options = CharacterCatalog.OutfitPieces[slot]
		check(options[1] == "none", "every outfit slot starts with none: " .. slot)
		for index = 2, #options do
			local info = CharacterCatalog.PieceInfo[slot][options[index]]
			check(info ~= nil and ((info.assetId or 0) > 0 or ((info.left or 0) > 0 and (info.right or 0) > 0)), "outfit piece needs asset ids: " .. options[index])
		end
	end
	check(CharacterDraft.pieces(CharacterDraft.createDefault()).jacket == "none", "new characters start in underwear")
	for _, accessoryId in CharacterCatalog.Accessories do
		local info = CharacterCatalog.AccessoryInfo[accessoryId]
		check(info ~= nil and info.assetId > 0 and (info.kind == "Hat" or info.kind == "Hair" or info.kind == "Face"), "accessory needs an asset id and kind: " .. accessoryId)
	end

	check(CharacterDraft.setSkinTone(draft, "neutral_dark") and draft.appearance.skinToneId == "neutral_dark", "catalog tone must update draft")
	check(not CharacterDraft.setSkinTone(draft, "unknown_external_asset") and draft.appearance.skinToneId == "neutral_dark", "unknown IDs must be rejected without mutation")
	check(CharacterDraft.setBodyBase(draft, "slim") and draft.appearance.bodyBaseId == "slim", "catalog body base must update draft")
	check(not CharacterDraft.setBodyBase(draft, "base_female") and draft.appearance.bodyBaseId == "slim", "old body bases must be rejected")

	-- Body scale sliders were removed from the UI; setBodyScale still works for
	-- legacy saved characters but the validator allows any 0..1 value.
	check(CharacterDraft.setBodyScale(draft, "height", 0.8) and draft.bodyScales.height == 0.8, "setBodyScale must still update draft for saved-character compat")

	check(CharacterDraft.setFace(draft, "vampire") and draft.appearance.faceId == "vampire", "catalog face must update draft")
	check(not CharacterDraft.setFace(draft, "laser_face") and draft.appearance.faceId == "vampire", "unknown face must not mutate draft")
	check(CharacterDraft.setHair(draft, "spiky_white") and draft.appearance.hairId == "spiky_white", "catalog hairstyle must update draft")
	check(not CharacterDraft.setHair(draft, "mohawk_9000") and draft.appearance.hairId == "spiky_white", "unknown hairstyle must not mutate draft")
	check(CharacterDraft.setOutfit(draft, "neon_nomad") and draft.outfit.outfitId == "neon_nomad", "catalog outfit must update draft")
	check(not CharacterDraft.setOutfit(draft, "tuxedo") and draft.outfit.outfitId == "neon_nomad", "unknown outfit must not mutate draft")

	-- Accessories toggle, up to MaxAccessories, never repeated.
	for index = 1, CharacterCatalog.MaxAccessories do
		check(CharacterDraft.toggleAccessory(draft, CharacterCatalog.Accessories[index]), "accessory " .. index .. " must go on")
	end
	check(not CharacterDraft.toggleAccessory(draft, CharacterCatalog.Accessories[CharacterCatalog.MaxAccessories + 1]), "accessories beyond the limit must be rejected")
	check(#draft.outfit.accessoryIds == CharacterCatalog.MaxAccessories, "a rejected accessory must not mutate draft")
	check(CharacterDraft.toggleAccessory(draft, CharacterCatalog.Accessories[1]) and not table.find(draft.outfit.accessoryIds, CharacterCatalog.Accessories[1]), "toggling again must take it off")
	local repeated = CharacterDraft.createDefault()
	repeated.outfit.accessoryIds = { "visor_cyan", "visor_cyan" }
	check(not CharacterValidator.validate(repeated), "repeated accessories must be rejected")

	check(CharacterDraft.toggleImplant(draft, "cyber_eye") and draft.cyberwareIds[1] == "cyber_eye" and #draft.cyberwareIds == 1, "installing an implant must replace the none placeholder")
	check(CharacterDraft.toggleImplant(draft, "cyber_arm") and #draft.cyberwareIds == 2, "implants must stack")
	check(CharacterDraft.toggleImplant(draft, "cyber_eye") and CharacterDraft.toggleImplant(draft, "cyber_arm") and draft.cyberwareIds[1] == "none", "removing every implant must restore none")
	check(not CharacterDraft.toggleImplant(draft, "laser_tongue") and not CharacterDraft.toggleImplant(draft, "none"), "unknown implants must be rejected")

	check(CharacterDraft.setClass(draft, "ghost") and draft.classId == "ghost", "catalog class must update draft")
	check(not CharacterDraft.setClass(draft, "pirate") and draft.classId == "ghost", "unknown class must not mutate draft")
	for _, classId in CharacterCatalog.Classes do
		local info = CharacterCatalog.ClassInfo[classId]
		check(info ~= nil and info.color ~= nil, classId .. " needs a colour")
		for _, statKey in CharacterCatalog.ClassStatKeys do
			local value = info.stats[statKey]
			check(type(value) == "number" and value >= 1 and value <= 5, classId .. " needs " .. statKey .. " between 1 and 5")
		end
	end
	check(CharacterDraft.setColor(draft, "neonPrimary", "green") and (draft.colors :: any).neonPrimary == "green", "neon colour must update draft")
	check(CharacterDraft.setColor(draft, "metal", "gold") and (draft.colors :: any).metal == "gold", "metal finish must update draft")
	check(not CharacterDraft.setColor(draft, "metal", "green"), "a neon colour is not a metal finish")
	check(not CharacterDraft.setColor(draft, "glow", "red"), "unknown colour slot must be rejected")
	local beforeColors = CharacterDraft.createDefault()
	beforeColors.colors = nil
	check(CharacterValidator.validate(beforeColors), "characters without colours stay valid")

	-- A character from the previous custom rig is not a valid R15 avatar.
	local legacy = CharacterDraft.createDefault() :: any
	legacy.avatarVersion = nil
	check(not CharacterValidator.validate(legacy), "characters without avatarVersion must be rejected")

	local copy = CharacterDraft.clone(draft)
	copy.outfit.accessoryIds[1] = "changed"
	check(draft.outfit.accessoryIds[1] ~= "changed", "clone must not share the accessory list")

	draft = CharacterDraft.reset(draft)
	check(draft.appearance.skinToneId == "neutral_medium" and draft.appearance.hairId == "black_anime", "reset must restore defaults")
	check(draft.classId == "runner" and #draft.outfit.accessoryIds == 0, "reset must restore class and accessories")

	return { passed = checks, total = checks }
end

return PhaseC31Tests
