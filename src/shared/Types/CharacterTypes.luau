--!strict

-- Saved character (standard R15 avatar, avatarVersion 2). See
-- Character/CharacterDraft for the defaults and validated setters.

export type Appearance = {
	bodyBaseId: string,
	skinToneId: string,
	faceId: string,
	hairId: string,
}

export type Outfit = {
	outfitId: string,
	accessoryIds: { string },
}

-- Slider values 0..1 (CharacterCatalog.ScaleRanges maps them to scales).
export type BodyScales = {
	height: number,
	width: number,
	head: number,
}

export type CharacterData = {
	creationComplete: boolean,
	rigType: "R15",
	avatarVersion: number,
	appearance: Appearance,
	outfit: Outfit,
	cyberwareIds: { string },
	bodyScales: BodyScales,
	classId: string?,
	colors: { [string]: string }?,
}

return {}
