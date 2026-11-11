--!strict

local PlayerState = table.freeze({
	LOADING = "LOADING",
	NEW_PLAYER = "NEW_PLAYER",
	EXISTING_PLAYER = "EXISTING_PLAYER",
	DATA_ERROR = "DATA_ERROR",
})

export type Value = "LOADING" | "NEW_PLAYER" | "EXISTING_PLAYER" | "DATA_ERROR"

return PlayerState
