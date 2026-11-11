--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local GameConfig = require(root.Config.GameConfig)
local CharacterValidator = require(root.Validation.CharacterValidator)
local CharacterDraft = require(root.Character.CharacterDraft)

local PlayerSchema = {}

function PlayerSchema.createDefault(now: number)
	return {
		schemaVersion = GameConfig.DataSchemaVersion,
		session = nil,
		data = {
			character = CharacterDraft.createDefault(),
			inventory = {
				unlockedCustomizationIds = {},
				currency = 0,
				-- Schema 2: itemId -> quantity, slot -> itemId (InventoryService).
				items = {},
				equipped = {},
			},
			progression = {
				level = 1,
				experience = 0,
				completedMissionIds = {},
			},
		},
		metadata = {
			createdAt = now,
			updatedAt = now,
		},
	}
end

local function validStringArray(value: any): boolean
	if type(value) ~= "table" then
		return false
	end
	for _, item in value do
		if type(item) ~= "string" then
			return false
		end
	end
	return true
end

-- items: string -> whole number >= 0; equipped: string -> string.
function PlayerSchema.validateItems(items: any, equipped: any): boolean
	if type(items) ~= "table" or type(equipped) ~= "table" then
		return false
	end
	for itemId, quantity in items do
		if type(itemId) ~= "string" or type(quantity) ~= "number" or quantity < 0 or quantity % 1 ~= 0 then
			return false
		end
	end
	for slot, itemId in equipped do
		if type(slot) ~= "string" or type(itemId) ~= "string" then
			return false
		end
	end
	return true
end

function PlayerSchema.validateRecord(record: any): (boolean, string?)
	if type(record) ~= "table" or record.schemaVersion ~= GameConfig.DataSchemaVersion then
		return false, "Unsupported schema version"
	end
	if type(record.data) ~= "table" or type(record.metadata) ~= "table" then
		return false, "Missing data or metadata"
	end
	local characterOk, characterError = CharacterValidator.validate(record.data.character)
	if not characterOk then
		return false, characterError
	end
	local inventory = record.data.inventory
	local progression = record.data.progression
	if type(inventory) ~= "table"
		or not validStringArray(inventory.unlockedCustomizationIds)
		or type(inventory.currency) ~= "number"
		or inventory.currency < 0
		or not PlayerSchema.validateItems(inventory.items, inventory.equipped)
		or (inventory.receipts ~= nil and not validStringArray(inventory.receipts))
	then
		return false, "Invalid inventory"
	end
	if type(progression) ~= "table"
		or type(progression.level) ~= "number"
		or progression.level < 1
		or type(progression.experience) ~= "number"
		or progression.experience < 0
		or not validStringArray(progression.completedMissionIds)
	then
		return false, "Invalid progression"
	end
	if type(record.metadata.createdAt) ~= "number" or type(record.metadata.updatedAt) ~= "number" then
		return false, "Invalid metadata"
	end
	if record.session ~= nil then
		local lease = record.session
		if type(lease) ~= "table"
			or type(lease.id) ~= "string"
			or type(lease.serverJobId) ~= "string"
			or type(lease.acquiredAt) ~= "number"
			or type(lease.expiresAt) ~= "number"
		then
			return false, "Invalid session lease"
		end
	end
	return true, nil
end

return PlayerSchema
