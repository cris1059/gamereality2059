--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local GameConfig = require(root.Config.GameConfig)
local CharacterDraft = require(root.Character.CharacterDraft)
local CharacterValidator = require(root.Validation.CharacterValidator)
local PlayerSchema = require(script.Parent.PlayerSchema)

local PlayerMigrations = {}

-- Add migrations sequentially: migrations[oldVersion] returns the next version.
local migrations: { [number]: (any) -> any } = {}

migrations[0] = function(record: any)
	local createdAt = if type(record.metadata) == "table" and type(record.metadata.createdAt) == "number"
		then record.metadata.createdAt
		else os.time()
	local migrated = PlayerSchema.createDefault(createdAt)
	if type(record.data) == "table" and CharacterValidator.validate(record.data.character) then
		migrated.data.character = record.data.character
	end
	migrated.metadata.updatedAt = createdAt
	return migrated
end

-- 1 -> 2: the custom inventory's items and equipped slots. Everything else
-- (character, currency, progression, session lease) is kept as is.
migrations[1] = function(record: any)
	local inventory = record.data.inventory
	inventory.items = if type(inventory.items) == "table" then inventory.items else {}
	inventory.equipped = if type(inventory.equipped) == "table" then inventory.equipped else {}
	record.schemaVersion = 2
	return record
end

-- 2 -> 3: characters became standard R15 avatars. A character from the old
-- custom rig cannot be converted, so it is replaced by the default (not
-- complete: the player designs a new one in MORPHLAB). The rest is kept.
migrations[2] = function(record: any)
	local character = record.data.character
	if not CharacterValidator.validate(character) then
		record.data.character = CharacterDraft.createDefault()
	end
	record.schemaVersion = 3
	return record
end

function PlayerMigrations.migrate(record: any): (boolean, any?, string?)
	if type(record) ~= "table" or type(record.schemaVersion) ~= "number" then
		return false, nil, "Record has no valid schemaVersion"
	end
	if record.schemaVersion > GameConfig.DataSchemaVersion then
		return false, nil, "Record was written by a newer server"
	end
	while record.schemaVersion < GameConfig.DataSchemaVersion do
		local migration = migrations[record.schemaVersion]
		if not migration then
			return false, nil, string.format("Missing migration from schema %d", record.schemaVersion)
		end
		local ok, migrated = pcall(migration, record)
		if not ok then
			return false, nil, "Migration failed: " .. tostring(migrated)
		end
		record = migrated
	end
	return true, record, nil
end

return PlayerMigrations
