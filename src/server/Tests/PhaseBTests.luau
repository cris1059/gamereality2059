--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local PlayerState = require(root.State.PlayerState)
local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local MockDataStore = require(script.Parent.Parent.Data.MockDataStore)
local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local DeepCopy = require(script.Parent.Parent.Util.DeepCopy)

local PhaseBTests = {}

local function expect(condition: boolean, message: string)
	if not condition then
		error(message, 2)
	end
end

local function testNewPlayer()
	local store = MockDataStore.new()
	local service = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-new" end,
		serverJobId = "server-a",
	})
	local result = service:Load(1)
	expect(result.state == PlayerState.NEW_PLAYER, "Missing record must be NEW_PLAYER")
	expect(store.updateCount == 1, "New load must use one atomic update")
end

local function testReadFailureIsNotNewPlayer()
	local store = MockDataStore.new()
	store:QueueFailure("injected read failure")
	local service = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-failure" end,
	})
	local result = service:Load(2)
	expect(result.state == PlayerState.DATA_ERROR, "Read failure must be DATA_ERROR")
	expect(store:Peek("player_2") == nil, "Read failure must not create or overwrite a record")
end

local function testWriteAndExistingPlayer()
	local now = 100
	local store = MockDataStore.new()
	local serviceA = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return now end,
		sessionIdFactory = function() return "session-write-a" end,
	})
	expect(serviceA:Load(3).state == PlayerState.NEW_PLAYER, "First load must be new")
	local data = serviceA:GetData(3)
	data.character.creationComplete = true
	local saveOk = serviceA:SaveCharacter(3, data.character)
	expect(saveOk, "Valid character must save")
	serviceA:Release(3)

	local serviceB = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return now end,
		sessionIdFactory = function() return "session-write-b" end,
	})
	expect(serviceB:Load(3).state == PlayerState.EXISTING_PLAYER, "Completed character must reload as existing")
end

local function testActiveSessionConflict()
	local store = MockDataStore.new()
	local optionsA = {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-conflict-a" end,
	}
	local optionsB = {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-conflict-b" end,
	}
	expect(PlayerDataService.new(store, optionsA):Load(4).state == PlayerState.NEW_PLAYER, "First lease must acquire")
	local result = PlayerDataService.new(store, optionsB):Load(4)
	expect(result.state == PlayerState.DATA_ERROR, "Concurrent load must fail closed")
	expect(result.errorCode == "SESSION_CONFLICT", "Concurrent load must report session conflict")
end

local function testExpiredRecoveryRejectsStaleWriter()
	local now = 100
	local store = MockDataStore.new()
	local serviceA = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return now end,
		sessionIdFactory = function() return "session-stale-a" end,
	})
	serviceA:Load(5)
	local staleData = serviceA:GetData(5)

	now = 111
	local serviceB = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return now end,
		sessionIdFactory = function() return "session-stale-b" end,
	})
	expect(serviceB:Load(5).state == PlayerState.NEW_PLAYER, "Expired lease must be recoverable")
	staleData.character.creationComplete = true
	local staleSaveOk, staleError = serviceA:SaveCharacter(5, staleData.character)
	expect(not staleSaveOk and staleError == "SESSION_OWNERSHIP_LOST", "Stale server must never overwrite new owner")
	local persisted = store:Peek("player_5")
	expect(persisted.session.id == "session-stale-b", "New lease owner must remain unchanged")
	expect(not persisted.data.character.creationComplete, "Stale data must not be written")
end

local function testInvalidCharacterRejected()
	local store = MockDataStore.new()
	local service = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-invalid" end,
	})
	service:Load(6)
	local data = service:GetData(6)
	data.character.appearance.hairId = "untrusted_asset_123"
	local ok, saveError = service:SaveCharacter(6, data.character)
	expect(not ok and string.find(saveError or "", "INVALID_CHARACTER", 1, true) ~= nil, "Unknown catalog ID must fail")
end

local function testMigrationFromVersionZero()
	local legacy = PlayerSchema.createDefault(50)
	legacy.schemaVersion = 0
	legacy.data.inventory = nil
	legacy.data.progression = nil
	local store = MockDataStore.new({ player_7 = DeepCopy(legacy) })
	local service = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-migration" end,
	})
	local result = service:Load(7)
	expect(result.state == PlayerState.NEW_PLAYER, "Migrated incomplete character must be new")
	local persisted = store:Peek("player_7")
	expect(persisted.schemaVersion == 3, "Migration must advance schema version")
	expect(type(persisted.data.inventory.items) == "table", "Migration must add inventory items")
	expect(type(persisted.data.inventory) == "table", "Migration must add inventory")
	expect(type(persisted.data.progression) == "table", "Migration must add progression")
end

-- Schema 2 profiles hold a character of the old custom rig: it becomes the
-- default R15 avatar (not complete, back to MORPHLAB); the rest is kept.
local function testMigrationToStandardAvatars()
	local record = PlayerSchema.createDefault(50)
	record.schemaVersion = 2
	record.data.inventory.currency = 77
	record.data.character = {
		creationComplete = true,
		rigType = "R15",
		appearance = { bodyBaseId = "base_male", skinToneId = "neutral_medium", faceId = "default", hairId = "none", hairColorId = "black", eyeId = "natural" },
		outfit = { outfitId = "vanguard", accessoryIds = {} },
		cyberwareIds = { "none" },
		bodyScales = { height = 0.5, width = 0.5, head = 0.5, bodyType = 0.5, proportion = 0.5 },
	}
	local store = MockDataStore.new({ player_8 = DeepCopy(record) })
	local service = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-avatars" end,
	})
	local result = service:Load(8)
	expect(result.state == PlayerState.NEW_PLAYER, "an old-rig character must go back to MORPHLAB")
	local persisted = store:Peek("player_8")
	expect(persisted.schemaVersion == 3, "migration must reach schema 3")
	expect(persisted.data.character.avatarVersion == 2, "the character must become a standard R15 avatar")
	expect(persisted.data.inventory.currency == 77, "migration must keep the inventory")
end

function PhaseBTests.run(): { passed: number, total: number }
	local tests = {
		{ "new player", testNewPlayer },
		{ "read failure safety", testReadFailureIsNotNewPlayer },
		{ "write and existing player", testWriteAndExistingPlayer },
		{ "active session conflict", testActiveSessionConflict },
		{ "expired recovery and stale writer", testExpiredRecoveryRejectsStaleWriter },
		{ "server character validation", testInvalidCharacterRejected },
		{ "schema migration", testMigrationFromVersionZero },
		{ "standard avatar migration", testMigrationToStandardAvatars },
	}
	local passed = 0
	for _, entry in tests do
		local name = entry[1] :: string
		local test = entry[2] :: () -> ()
		local ok, testError = pcall(test)
		if not ok then
			error(string.format("Phase B test failed (%s): %s", name, tostring(testError)), 0)
		end
		passed += 1
	end
	return { passed = passed, total = #tests }
end

return PhaseBTests
