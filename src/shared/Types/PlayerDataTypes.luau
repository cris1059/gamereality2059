--!strict

local CharacterTypes = require(script.Parent.CharacterTypes)

export type SessionLease = {
	id: string,
	serverJobId: string,
	acquiredAt: number,
	expiresAt: number,
}

export type InventoryData = {
	unlockedCustomizationIds: { string },
	currency: number,
	items: { [string]: number },
	equipped: { [string]: string },
}

export type ProgressionData = {
	level: number,
	experience: number,
	completedMissionIds: { string },
}

export type PlayerData = {
	character: CharacterTypes.CharacterData,
	inventory: InventoryData,
	progression: ProgressionData,
}

export type PlayerRecord = {
	schemaVersion: number,
	session: SessionLease?,
	data: PlayerData,
	metadata: {
		createdAt: number,
		updatedAt: number,
	},
}

return {}
