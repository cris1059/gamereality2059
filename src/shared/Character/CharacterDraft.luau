--!strict

-- The character being edited in MORPHLAB (and what gets saved): a standard
-- R15 avatar. Every setter validates the whole draft and leaves it untouched
-- when the change is rejected.

local CharacterCatalog = require(script.Parent.Parent.Catalog.CharacterCatalog)
local CharacterValidator = require(script.Parent.Parent.Validation.CharacterValidator)

local CharacterDraft = {}

export type Draft = {
	creationComplete: boolean,
	rigType: "R15",
	avatarVersion: number,
	appearance: {
		bodyBaseId: string,
		skinToneId: string,
		faceId: string,
		hairId: string,
	},
	outfit: {
		-- Pre-split look; kept for old saves and as the HubUI fallback.
		outfitId: string,
		-- jacket / shirt / pants / shoes piece ids ("none" = not worn).
		pieces: { [string]: string }?,
		accessoryIds: { string },
	},
	cyberwareIds: { string },
	bodyScales: {
		height: number,
		width: number,
		head: number,
	},
	classId: string?,
	colors: { [string]: string }?,
}

function CharacterDraft.createDefault(): Draft
	return {
		creationComplete = false,
		rigType = "R15",
		avatarVersion = CharacterValidator.AvatarVersion,
		appearance = {
			bodyBaseId = "classic",
			skinToneId = "neutral_medium",
			faceId = "chill",
			hairId = "black_anime",
		},
		-- New characters start in underwear: every outfit piece off.
		outfit = {
			outfitId = "shadow",
			pieces = { jacket = "none", shirt = "none", pants = "none", shoes = "none" },
			accessoryIds = {},
		},
		cyberwareIds = { "none" },
		bodyScales = {
			height = 0.5,
			width = 0.5,
			head = 0.5,
		},
		classId = "runner",
		colors = {
			neonPrimary = "red",
			neonSecondary = "cyan",
			metal = "gunmetal",
		},
	}
end

function CharacterDraft.clone(source: Draft): Draft
	local copy = CharacterDraft.createDefault()
	copy.creationComplete = source.creationComplete
	copy.appearance = table.clone(source.appearance)
	copy.outfit = {
		outfitId = source.outfit.outfitId,
		pieces = if source.outfit.pieces then table.clone(source.outfit.pieces) else nil,
		accessoryIds = table.clone(source.outfit.accessoryIds),
	}
	copy.cyberwareIds = table.clone(source.cyberwareIds)
	copy.bodyScales = table.clone(source.bodyScales)
	copy.classId = source.classId
	copy.colors = if source.colors then table.clone(source.colors) else nil
	return copy
end

-- Applies `change` to the draft and keeps it only if the result validates.
local function attempt(draft: Draft, change: () -> (), restore: () -> ()): (boolean, string?)
	change()
	local valid, validationError = CharacterValidator.validate(draft)
	if not valid then
		restore()
		return false, validationError
	end
	return true, nil
end

-- Validated catalog selection for an appearance field.
local function setAppearanceId(draft: Draft, key: string, catalog: { string }, id: string): (boolean, string?)
	if not table.find(catalog, id) then
		return false, "UNKNOWN_CATALOG_ID"
	end
	local appearance = draft.appearance :: any
	local previous = appearance[key]
	return attempt(draft, function()
		appearance[key] = id
	end, function()
		appearance[key] = previous
	end)
end

function CharacterDraft.setBodyBase(draft: Draft, bodyBaseId: string): (boolean, string?)
	return setAppearanceId(draft, "bodyBaseId", CharacterCatalog.BodyBases, bodyBaseId)
end

function CharacterDraft.setSkinTone(draft: Draft, skinToneId: string): (boolean, string?)
	return setAppearanceId(draft, "skinToneId", CharacterCatalog.SkinTones, skinToneId)
end

function CharacterDraft.setFace(draft: Draft, faceId: string): (boolean, string?)
	return setAppearanceId(draft, "faceId", CharacterCatalog.Faces, faceId)
end

function CharacterDraft.setHair(draft: Draft, hairId: string): (boolean, string?)
	return setAppearanceId(draft, "hairId", CharacterCatalog.Hair, hairId)
end

-- The pieces a pre-split outfit stands for (its jacket and pants).
local function legacyPieces(outfitId: string): { [string]: string }
	local legacy = CharacterCatalog.OutfitInfo[outfitId]
	local pants = "none"
	if legacy then
		for pantsId, info in CharacterCatalog.PieceInfo.pants do
			if info.assetId == legacy.pants then
				pants = pantsId
			end
		end
	end
	return { jacket = if legacy then outfitId else "none", shirt = "none", pants = pants, shoes = "none" }
end

-- Worn pieces by slot; characters saved before the split use their outfitId.
function CharacterDraft.pieces(draft: Draft): { [string]: string }
	local stored = draft.outfit.pieces
	if type(stored) == "table" then
		return stored
	end
	return legacyPieces(draft.outfit.outfitId)
end

-- A full preset look (jacket and pants of the outfit set).
function CharacterDraft.setOutfit(draft: Draft, outfitId: string): (boolean, string?)
	if not table.find(CharacterCatalog.Outfits, outfitId) then
		return false, "UNKNOWN_OUTFIT"
	end
	local previous, previousPieces = draft.outfit.outfitId, draft.outfit.pieces
	return attempt(draft, function()
		draft.outfit.outfitId = outfitId
		draft.outfit.pieces = legacyPieces(outfitId)
	end, function()
		draft.outfit.outfitId = previous
		draft.outfit.pieces = previousPieces
	end)
end

-- One outfit piece ("none" takes it off).
function CharacterDraft.setPiece(draft: Draft, slot: string, pieceId: string): (boolean, string?)
	local options = CharacterCatalog.OutfitPieces[slot]
	if not options or not table.find(options, pieceId) then
		return false, "UNKNOWN_OUTFIT_PIECE"
	end
	local previous = draft.outfit.pieces
	local updated = table.clone(CharacterDraft.pieces(draft))
	updated[slot] = pieceId
	return attempt(draft, function()
		draft.outfit.pieces = updated
	end, function()
		draft.outfit.pieces = previous
	end)
end

-- Puts an accessory on or takes it off (CharacterCatalog.MaxAccessories at once).
function CharacterDraft.toggleAccessory(draft: Draft, accessoryId: string): (boolean, string?)
	if not table.find(CharacterCatalog.Accessories, accessoryId) then
		return false, "UNKNOWN_ACCESSORY"
	end
	local previous = draft.outfit.accessoryIds
	local updated = table.clone(previous)
	local index = table.find(updated, accessoryId)
	if index then
		table.remove(updated, index)
	else
		table.insert(updated, accessoryId)
	end
	return attempt(draft, function()
		draft.outfit.accessoryIds = updated
	end, function()
		draft.outfit.accessoryIds = previous
	end)
end

function CharacterDraft.setColor(draft: Draft, slot: string, id: string): (boolean, string?)
	if not table.find(CharacterCatalog.ColorSlots, slot) then
		return false, "UNKNOWN_COLOR_SLOT"
	end
	local colors = draft.colors or table.clone(CharacterCatalog.DefaultColors)
	draft.colors = colors
	local previous = colors[slot]
	return attempt(draft, function()
		colors[slot] = id
	end, function()
		colors[slot] = previous
	end)
end

function CharacterDraft.setClass(draft: Draft, classId: string): (boolean, string?)
	if not table.find(CharacterCatalog.Classes, classId) then
		return false, "UNKNOWN_CLASS"
	end
	local previous = draft.classId
	return attempt(draft, function()
		draft.classId = classId
	end, function()
		draft.classId = previous
	end)
end

-- Turns one implant on or off. An empty loadout is stored as { "none" }.
function CharacterDraft.toggleImplant(draft: Draft, implantId: string): (boolean, string?)
	if implantId == "none" or not table.find(CharacterCatalog.Implants, implantId) then
		return false, "UNKNOWN_IMPLANT"
	end
	local previous = draft.cyberwareIds
	local loadout = {}
	local found = false
	for _, id in previous do
		if id == implantId then
			found = true
		elseif id ~= "none" then
			table.insert(loadout, id)
		end
	end
	if not found then
		table.insert(loadout, implantId)
	end
	return attempt(draft, function()
		draft.cyberwareIds = if #loadout > 0 then loadout else { "none" }
	end, function()
		draft.cyberwareIds = previous
	end)
end

local BODY_SCALE_KEYS = table.freeze({ height = true, width = true, head = true })

function CharacterDraft.setBodyScale(draft: Draft, key: string, value: number): (boolean, string?)
	if not BODY_SCALE_KEYS[key] then
		return false, "UNKNOWN_BODY_SCALE"
	end
	local scales = draft.bodyScales :: any
	local previous = scales[key]
	return attempt(draft, function()
		scales[key] = value
	end, function()
		scales[key] = previous
	end)
end

function CharacterDraft.reset(_draft: Draft): Draft
	return CharacterDraft.createDefault()
end

return CharacterDraft
