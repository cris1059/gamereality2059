--!strict

-- Server-owned inventory, persisted in the player profile (schema 2:
-- data.inventory.items / equipped). Clients can only read their snapshot and
-- ask to equip / unequip items they own; quantities never come from the
-- client, so nothing can be duplicated through these remotes. A change that
-- cannot be saved is rolled back.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local root = ReplicatedStorage:WaitForChild("CyberpunkOnline")
local InventoryConfig = require(root.Config.InventoryConfig)
local RemoteNames = require(root.Network.RemoteNames)
local RateLimiter = require(script.Parent.RateLimiter)

local InventoryService = {}
InventoryService.__index = InventoryService

export type Inventory = { items: { [string]: number }, equipped: { [string]: string } }

local function create(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

-- dataService: PlayerDataService (GetData / SaveInventory).
function InventoryService.new(runtime: Folder, dataService: any)
	local remotes = runtime:WaitForChild(RemoteNames.Folder)
	local self = setmetatable({
		_data = dataService,
		_inventories = {} :: { [number]: Inventory },
		_limiter = RateLimiter.new(InventoryConfig.MaxRequestsPerWindow, InventoryConfig.RequestWindowSeconds),
		_get = create(remotes, "RemoteFunction", RemoteNames.GetInventory) :: RemoteFunction,
		_action = create(remotes, "RemoteFunction", RemoteNames.InventoryAction) :: RemoteFunction,
		_changed = create(remotes, "RemoteEvent", RemoteNames.InventoryChanged) :: RemoteEvent,
	}, InventoryService)
	return self
end

-- Pure rule, exposed for the Studio tests (catalog defaults to the config).
function InventoryService.Apply(inventory: Inventory, action: any, itemId: any, catalog: { [string]: any }?): (boolean, string?)
	if type(itemId) ~= "string" or #itemId > 64 then
		return false, "INVALID_ITEM"
	end
	local item = (catalog or InventoryConfig.Items)[itemId]
	if not item then
		return false, "UNKNOWN_ITEM"
	end
	if (inventory.items[itemId] or 0) <= 0 then
		return false, "NOT_OWNED"
	end
	if not item.slot then
		return false, "NOT_EQUIPPABLE"
	end
	if action == "equip" then
		inventory.equipped[item.slot] = itemId
		return true, nil
	elseif action == "unequip" then
		if inventory.equipped[item.slot] ~= itemId then
			return false, "NOT_EQUIPPED"
		end
		inventory.equipped[item.slot] = nil
		return true, nil
	end
	return false, "INVALID_ACTION"
end

local function copy(inventory: Inventory): Inventory
	return { items = table.clone(inventory.items), equipped = table.clone(inventory.equipped) }
end

-- Cached after the profile has loaded; nil while it is still loading.
function InventoryService:_inventory(player: Player): Inventory?
	local cached = self._inventories[player.UserId]
	if cached then
		return cached
	end
	local data = self._data:GetData(player.UserId)
	local saved = data and data.inventory
	if not saved then
		return nil
	end
	local inventory = { items = saved.items or {}, equipped = saved.equipped or {} }
	self._inventories[player.UserId] = inventory
	return inventory
end

function InventoryService:Start()
	self._get.OnServerInvoke = function(player: Player)
		local inventory = self:_inventory(player)
		return if inventory then copy(inventory) else nil
	end
	self._action.OnServerInvoke = function(player: Player, action: any, itemId: any)
		if not self._limiter:Allow(player.UserId) then
			return { ok = false, errorCode = "RATE_LIMITED" }
		end
		local inventory = self:_inventory(player)
		if not inventory then
			return { ok = false, errorCode = "NO_INVENTORY" }
		end
		local before = copy(inventory)
		local ok, errorCode = InventoryService.Apply(inventory, action, itemId)
		if not ok then
			return { ok = false, errorCode = errorCode }
		end
		local saved, saveError = self._data:SaveInventory(player.UserId, inventory.items, inventory.equipped)
		if not saved then
			inventory.items, inventory.equipped = before.items, before.equipped
			return { ok = false, errorCode = "SAVE_FAILED:" .. tostring(saveError) }
		end
		self._changed:FireClient(player, copy(inventory))
		return { ok = true }
	end
	Players.PlayerRemoving:Connect(function(player)
		self._inventories[player.UserId] = nil
		self._limiter:Remove(player.UserId)
	end)
end

return InventoryService
