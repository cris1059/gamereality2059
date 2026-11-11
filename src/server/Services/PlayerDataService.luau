--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local PlayerState = require(root.State.PlayerState)
local CharacterValidator = require(root.Validation.CharacterValidator)
local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local PlayerMigrations = require(script.Parent.Parent.Data.PlayerMigrations)
local DeepCopy = require(script.Parent.Parent.Util.DeepCopy)

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

export type Options = {
	leaseSeconds: number,
	serverJobId: string?,
	clock: (() -> number)?,
	sessionIdFactory: (() -> string)?,
}

local function playerKey(userId: number): string
	return "player_" .. tostring(userId)
end

function PlayerDataService.new(store: any, options: Options)
	local self = setmetatable({}, PlayerDataService)
	self._store = store
	self._leaseSeconds = options.leaseSeconds
	self._serverJobId = options.serverJobId or game.JobId
	self._clock = options.clock or os.time
	self._sessionIdFactory = options.sessionIdFactory or function()
		return HttpService:GenerateGUID(false)
	end
	self._sessions = {} :: { [number]: { sessionId: string, record: any } }
	return self
end

function PlayerDataService:Load(userId: number): any
	if self._sessions[userId] then
		return { state = PlayerState.DATA_ERROR, errorCode = "ALREADY_LOADED", message = "Player already has a local session" }
	end

	local now = self._clock()
	local sessionId = self._sessionIdFactory()
	local createdNew = false
	local rejection: string? = nil

	local ok, result, storeError = self._store:UpdateAsync(playerKey(userId), function(current: any?)
		local record = current
		if record == nil then
			record = PlayerSchema.createDefault(now)
			createdNew = true
		else
			local migrationOk, migrated, migrationError = PlayerMigrations.migrate(record)
			if not migrationOk then
				rejection = "MIGRATION_ERROR:" .. tostring(migrationError)
				return current
			end
			record = migrated
		end

		local valid, validationError = PlayerSchema.validateRecord(record)
		if not valid then
			rejection = "CORRUPT_DATA:" .. tostring(validationError)
			return current
		end

		local lease = record.session
		if lease and lease.id ~= sessionId and lease.expiresAt > now then
			rejection = "SESSION_CONFLICT"
			return current
		end

		record.session = {
			id = sessionId,
			serverJobId = self._serverJobId,
			acquiredAt = now,
			expiresAt = now + self._leaseSeconds,
		}
		record.metadata.updatedAt = now
		return record
	end)

	if not ok then
		return { state = PlayerState.DATA_ERROR, errorCode = "READ_FAILED", message = tostring(storeError) }
	end
	if rejection then
		return { state = PlayerState.DATA_ERROR, errorCode = rejection, message = "Player data could not be safely acquired" }
	end
	if type(result) ~= "table" or not result.session or result.session.id ~= sessionId then
		return { state = PlayerState.DATA_ERROR, errorCode = "LEASE_NOT_ACQUIRED", message = "Session ownership was not confirmed" }
	end

	self._sessions[userId] = { sessionId = sessionId, record = DeepCopy(result) }
	local state = if createdNew or not result.data.character.creationComplete then PlayerState.NEW_PLAYER else PlayerState.EXISTING_PLAYER
	return { state = state, data = DeepCopy(result.data), errorCode = nil, message = nil }
end

function PlayerDataService:GetData(userId: number): any?
	local session = self._sessions[userId]
	return if session then DeepCopy(session.record.data) else nil
end

function PlayerDataService:SaveCharacter(userId: number, candidate: any): (boolean, string?)
	local valid, validationError = CharacterValidator.validate(candidate)
	if not valid then
		return false, "INVALID_CHARACTER:" .. tostring(validationError)
	end
	local localSession = self._sessions[userId]
	if not localSession then
		return false, "SESSION_NOT_LOADED"
	end

	local now = self._clock()
	local rejection: string? = nil
	local ok, result, storeError = self._store:UpdateAsync(playerKey(userId), function(current: any?)
		if type(current) ~= "table" or not current.session or current.session.id ~= localSession.sessionId then
			rejection = "SESSION_OWNERSHIP_LOST"
			return current
		end
		local recordOk, recordError = PlayerSchema.validateRecord(current)
		if not recordOk then
			rejection = "CORRUPT_DATA:" .. tostring(recordError)
			return current
		end
		current.data.character = DeepCopy(candidate)
		current.metadata.updatedAt = now
		current.session.expiresAt = now + self._leaseSeconds
		return current
	end)
	if not ok then
		return false, "WRITE_FAILED:" .. tostring(storeError)
	end
	if rejection then
		self._sessions[userId] = nil
		return false, rejection
	end
	localSession.record = DeepCopy(result)
	return true, nil
end

-- Writes the inventory's items / equipped slots under the same session lease
-- rules as SaveCharacter. Currency and unlocks are left untouched.
function PlayerDataService:SaveInventory(userId: number, items: any, equipped: any): (boolean, string?)
	if not PlayerSchema.validateItems(items, equipped) then
		return false, "INVALID_INVENTORY"
	end
	local localSession = self._sessions[userId]
	if not localSession then
		return false, "SESSION_NOT_LOADED"
	end

	local now = self._clock()
	local rejection: string? = nil
	local ok, result, storeError = self._store:UpdateAsync(playerKey(userId), function(current: any?)
		if type(current) ~= "table" or not current.session or current.session.id ~= localSession.sessionId then
			rejection = "SESSION_OWNERSHIP_LOST"
			return current
		end
		local recordOk, recordError = PlayerSchema.validateRecord(current)
		if not recordOk then
			rejection = "CORRUPT_DATA:" .. tostring(recordError)
			return current
		end
		current.data.inventory.items = DeepCopy(items)
		current.data.inventory.equipped = DeepCopy(equipped)
		current.metadata.updatedAt = now
		current.session.expiresAt = now + self._leaseSeconds
		return current
	end)
	if not ok then
		return false, "WRITE_FAILED:" .. tostring(storeError)
	end
	if rejection then
		self._sessions[userId] = nil
		return false, rejection
	end
	localSession.record = DeepCopy(result)
	return true, nil
end

-- Adds purchased credits under the session lease, once per receipt: the
-- receipt id is stored with the grant in the same atomic write, so a receipt
-- Roblox delivers again is acknowledged without granting twice.
-- Returns ok, errorCode, the new balance.
function PlayerDataService:GrantCredits(userId: number, amount: number, receiptId: string, history: number): (boolean, string?, number?)
	if type(amount) ~= "number" or amount <= 0 or amount % 1 ~= 0 or type(receiptId) ~= "string" or receiptId == "" then
		return false, "INVALID_GRANT", nil
	end
	local localSession = self._sessions[userId]
	if not localSession then
		return false, "SESSION_NOT_LOADED", nil
	end
	local now = self._clock()
	local rejection: string? = nil
	local ok, result, storeError = self._store:UpdateAsync(playerKey(userId), function(current: any?)
		if type(current) ~= "table" or not current.session or current.session.id ~= localSession.sessionId then
			rejection = "SESSION_OWNERSHIP_LOST"
			return current
		end
		local recordOk, recordError = PlayerSchema.validateRecord(current)
		if not recordOk then
			rejection = "CORRUPT_DATA:" .. tostring(recordError)
			return current
		end
		local inventory = current.data.inventory
		local receipts = inventory.receipts or {}
		if table.find(receipts, receiptId) then
			return current
		end
		table.insert(receipts, receiptId)
		while #receipts > history do
			table.remove(receipts, 1)
		end
		inventory.receipts = receipts
		inventory.currency += amount
		current.metadata.updatedAt = now
		current.session.expiresAt = now + self._leaseSeconds
		return current
	end)
	if not ok then
		return false, "WRITE_FAILED:" .. tostring(storeError), nil
	end
	if rejection then
		if rejection == "SESSION_OWNERSHIP_LOST" then
			self._sessions[userId] = nil
		end
		return false, rejection, nil
	end
	localSession.record = DeepCopy(result)
	return true, nil, result.data.inventory.currency
end

function PlayerDataService:Renew(userId: number): (boolean, string?)
	local localSession = self._sessions[userId]
	if not localSession then
		return false, "SESSION_NOT_LOADED"
	end
	local now = self._clock()
	local lost = false
	local ok, result, storeError = self._store:UpdateAsync(playerKey(userId), function(current: any?)
		if type(current) ~= "table" or not current.session or current.session.id ~= localSession.sessionId then
			lost = true
			return current
		end
		current.session.expiresAt = now + self._leaseSeconds
		current.metadata.updatedAt = now
		return current
	end)
	if not ok then
		return false, "RENEW_FAILED:" .. tostring(storeError)
	end
	if lost then
		self._sessions[userId] = nil
		return false, "SESSION_OWNERSHIP_LOST"
	end
	localSession.record = DeepCopy(result)
	return true, nil
end

function PlayerDataService:Release(userId: number): (boolean, string?)
	local localSession = self._sessions[userId]
	if not localSession then
		return true, nil
	end
	local now = self._clock()
	local ok, _, storeError = self._store:UpdateAsync(playerKey(userId), function(current: any?)
		if type(current) == "table" and current.session and current.session.id == localSession.sessionId then
			current.session = nil
			current.metadata.updatedAt = now
		end
		return current
	end)
	-- Remove local write authority even if release failed; the remote lease expires.
	self._sessions[userId] = nil
	if not ok then
		return false, "RELEASE_FAILED:" .. tostring(storeError)
	end
	return true, nil
end

function PlayerDataService:HasSession(userId: number): boolean
	return self._sessions[userId] ~= nil
end

return PlayerDataService
