--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local InventoryConfig = require(root.Config.InventoryConfig)
local InventoryService = require(script.Parent.Parent.Services.InventoryService)
local PlayerSchema = require(script.Parent.Parent.Data.PlayerSchema)
local PlayerMigrations = require(script.Parent.Parent.Data.PlayerMigrations)
local MockDataStore = require(script.Parent.Parent.Data.MockDataStore)
local PlayerDataService = require(script.Parent.Parent.Services.PlayerDataService)
local DeepCopy = require(script.Parent.Parent.Util.DeepCopy)

local InventoryTests = {}

local function expect(condition: boolean, message: string)
	if not condition then error("Inventory test failed: " .. message, 2) end
end

-- Test-only items; the real catalog is empty.
local CATALOG = {
	test_blade = { slot = "weapon" },
	test_rifle = { slot = "weapon" },
	test_food = {},
}

function InventoryTests.run(): { passed: number, total: number }
	local passed = 0

	-- Catalog entries (if any) use known categories, rarities and slots.
	local categories = {}
	for _, category in InventoryConfig.Categories do
		categories[category.id] = true
	end
	for itemId, item in InventoryConfig.Items do
		expect(categories[item.category] == true, itemId .. " has an unknown category")
		expect(InventoryConfig.Rarities[item.rarity] ~= nil, itemId .. " has an unknown rarity")
		expect(item.slot == nil or table.find(InventoryConfig.Slots, item.slot) ~= nil, itemId .. " has an unknown slot")
	end
	passed += 1

	-- Equip / swap / unequip owned items.
	local inventory = { items = { test_blade = 1, test_rifle = 1, test_food = 3 }, equipped = {} }
	expect(InventoryService.Apply(inventory, "equip", "test_blade", CATALOG), "could not equip an owned item")
	expect(InventoryService.Apply(inventory, "equip", "test_rifle", CATALOG), "could not swap")
	expect(inventory.equipped.weapon == "test_rifle", "swap failed")
	expect(InventoryService.Apply(inventory, "unequip", "test_rifle", CATALOG), "could not unequip")
	expect(inventory.equipped.weapon == nil, "slot not cleared")
	passed += 1

	-- Hostile requests change nothing.
	expect(not InventoryService.Apply(inventory, "equip", "test_food", CATALOG), "non-equippable item equipped")
	expect(not InventoryService.Apply(inventory, "equip", "fake_item", CATALOG), "unknown item accepted")
	expect(not InventoryService.Apply(inventory, "equip", 42, CATALOG), "non-string item accepted")
	expect(not InventoryService.Apply(inventory, "duplicate", "test_blade", CATALOG), "unknown action accepted")
	inventory.items.test_blade = 0
	expect(not InventoryService.Apply(inventory, "equip", "test_blade", CATALOG), "item not owned was equipped")
	expect(inventory.items.test_food == 3, "quantities changed")
	passed += 1

	-- Schema 1 -> 2 keeps the character and adds empty items / equipped.
	local legacy = PlayerSchema.createDefault(10)
	legacy.schemaVersion = 1
	legacy.data.inventory.items = nil
	legacy.data.inventory.equipped = nil
	legacy.data.inventory.currency = 25
	local migratedOk, migrated = PlayerMigrations.migrate(DeepCopy(legacy))
	expect(migratedOk and migrated.schemaVersion == 2, "schema 1 did not migrate to 2")
	expect(next(migrated.data.inventory.items) == nil, "migrated items are not empty")
	expect(migrated.data.inventory.currency == 25, "migration lost the currency")
	expect(PlayerSchema.validateRecord(migrated), "migrated record is invalid")
	passed += 1

	-- SaveInventory persists, and rejects malformed data.
	local store = MockDataStore.new()
	local service = PlayerDataService.new(store, {
		leaseSeconds = 10,
		clock = function() return 100 end,
		sessionIdFactory = function() return "session-inventory" end,
	})
	service:Load(9)
	expect(service:SaveInventory(9, { test_blade = 1 }, { weapon = "test_blade" }), "save failed")
	local persisted = store:Peek("player_9")
	expect(persisted.data.inventory.items.test_blade == 1, "items not persisted")
	expect(persisted.data.inventory.equipped.weapon == "test_blade", "equipped not persisted")
	expect(not service:SaveInventory(9, { test_blade = -1 }, {}), "negative quantity accepted")
	expect(not service:SaveInventory(9, { test_blade = 1.5 }, {}), "fractional quantity accepted")
	passed += 1

	return { passed = passed, total = 5 }
end

return InventoryTests
