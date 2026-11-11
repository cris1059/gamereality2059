--!strict

-- Random but valid characters (city pedestrians, the Studio preview squad):
-- every choice goes through the same validated CharacterDraft setters as
-- MORPHLAB, so any result can be built like a player's avatar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local CharacterCatalog = require(root.Catalog.CharacterCatalog)
local CharacterDraft = require(root.Character.CharacterDraft)

local RandomCharacter = {}

local function pick<T>(random: Random, list: { T }): T
	return list[random:NextInteger(1, #list)]
end

function RandomCharacter.create(random: Random)
	local draft = CharacterDraft.createDefault()
	CharacterDraft.setBodyBase(draft, pick(random, CharacterCatalog.BodyBases))
	-- Mostly natural tones; synthetic ones now and then.
	local tones = CharacterCatalog.SkinTones
	CharacterDraft.setSkinTone(draft, if random:NextNumber() < 0.85 then tones[random:NextInteger(1, 7)] else pick(random, tones))
	CharacterDraft.setFace(draft, pick(random, CharacterCatalog.Faces))
	-- Index 1 is "none" (bald): rare.
	CharacterDraft.setHair(draft, CharacterCatalog.Hair[random:NextInteger(if random:NextNumber() < 0.1 then 1 else 2, #CharacterCatalog.Hair)])
	CharacterDraft.setOutfit(draft, pick(random, CharacterCatalog.Outfits))
	if random:NextNumber() < 0.45 then
		CharacterDraft.toggleAccessory(draft, pick(random, CharacterCatalog.Accessories))
	end
	CharacterDraft.setClass(draft, pick(random, CharacterCatalog.Classes))
	for _, key in { "height", "width", "head" } do
		CharacterDraft.setBodyScale(draft, key, math.round(random:NextNumber(0.25, 0.75) * 100) / 100)
	end
	-- Index 1 is "none"; most people carry one implant or none.
	for _ = 1, random:NextInteger(0, 2) do
		local implantId = CharacterCatalog.Implants[random:NextInteger(2, #CharacterCatalog.Implants)]
		if not table.find(draft.cyberwareIds, implantId) then
			CharacterDraft.toggleImplant(draft, implantId)
		end
	end
	CharacterDraft.setColor(draft, "neonPrimary", pick(random, CharacterCatalog.NeonColors))
	CharacterDraft.setColor(draft, "neonSecondary", pick(random, CharacterCatalog.NeonColors))
	CharacterDraft.setColor(draft, "metal", pick(random, CharacterCatalog.MetalFinishes))
	draft.creationComplete = true
	return draft
end

return RandomCharacter
