--!strict

local Catalog = require(script.Parent.Parent.Catalog.CharacterCatalog)

local CharacterValidator = {}

-- Standard R15 avatars. Characters saved with the previous custom rig have
-- no avatarVersion and are rejected (the profile goes back to MORPHLAB).
CharacterValidator.AvatarVersion = 2

local function contains(values: { string }, candidate: unknown): boolean
	if type(candidate) ~= "string" then
		return false
	end
	for _, value in values do
		if value == candidate then
			return true
		end
	end
	return false
end

local function optionalCatalogId(values: { string }, candidate: unknown): boolean
	return candidate == nil or contains(values, candidate)
end

-- Known ids, no repeats, at most maxItems.
local function validIdList(values: unknown, catalog: { string }, maxItems: number): boolean
	if type(values) ~= "table" or #values > maxItems then
		return false
	end
	local seen = {}
	for _, value in values do
		if not contains(catalog, value) or seen[value] then
			return false
		end
		seen[value] = true
	end
	return true
end

local function inUnitRange(value: unknown): boolean
	return type(value) == "number" and value == value and value >= 0 and value <= 1
end

function CharacterValidator.validate(candidate: unknown): (boolean, string?)
	if type(candidate) ~= "table" then
		return false, "Character data must be a table"
	end
	if candidate.rigType ~= "R15" or candidate.avatarVersion ~= CharacterValidator.AvatarVersion then
		return false, "Only standard R15 avatars (version 2) are supported"
	end

	local appearance = candidate.appearance
	if type(appearance) ~= "table"
		or not contains(Catalog.BodyBases, appearance.bodyBaseId)
		or type(appearance.skinToneId) ~= "string"
		or Catalog.SkinToneColors[appearance.skinToneId] == nil
		or not contains(Catalog.Faces, appearance.faceId)
		or not contains(Catalog.Hair, appearance.hairId)
	then
		return false, "Appearance contains an unknown option"
	end

	local outfit = candidate.outfit
	if type(outfit) ~= "table"
		or not contains(Catalog.Outfits, outfit.outfitId)
		or not validIdList(outfit.accessoryIds, Catalog.Accessories, Catalog.MaxAccessories)
	then
		return false, "Outfit contains an unknown or excessive option"
	end
	local pieces = outfit.pieces
	if pieces ~= nil then
		if type(pieces) ~= "table" then
			return false, "Outfit pieces must be a table"
		end
		for slot, value in pieces do
			local options = Catalog.OutfitPieces[slot]
			if not options or not contains(options, value) then
				return false, "Outfit pieces contain an unknown slot or option"
			end
		end
	end

	if not validIdList(candidate.cyberwareIds, Catalog.Implants, Catalog.MaxImplants) then
		return false, "Cyberware contains an unknown or excessive option"
	end

	local scales = candidate.bodyScales
	if type(scales) ~= "table"
		or not inUnitRange(scales.height)
		or not inUnitRange(scales.width)
		or not inUnitRange(scales.head)
	then
		return false, "Body scales must be finite values between 0 and 1"
	end

	local colors = candidate.colors
	if colors ~= nil then
		if type(colors) ~= "table" then
			return false, "Colors must be a table"
		end
		for slot, value in colors do
			local catalog = if slot == "metal" then Catalog.MetalFinishes elseif slot == "neonPrimary" or slot == "neonSecondary" then Catalog.NeonColors else nil
			if not catalog or not contains(catalog, value) then
				return false, "Colors contain an unknown slot or option"
			end
		end
	end

	if not optionalCatalogId(Catalog.Classes, candidate.classId) then
		return false, "Unknown class"
	end

	if type(candidate.creationComplete) ~= "boolean" then
		return false, "creationComplete must be a boolean"
	end

	return true, nil
end

return CharacterValidator
