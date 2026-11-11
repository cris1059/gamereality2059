--!strict

local DeepCopy = require(script.Parent.Parent.Util.DeepCopy)

local MockDataStore = {}
MockDataStore.__index = MockDataStore

function MockDataStore.new(seed: { [string]: any }?)
	local self = setmetatable({}, MockDataStore)
	self._values = DeepCopy(seed or {})
	self._queuedFailures = {} :: { string }
	self.updateCount = 0
	return self
end

function MockDataStore:QueueFailure(message: string)
	table.insert(self._queuedFailures, message)
end

function MockDataStore:UpdateAsync(key: string, transform: (any?) -> any?): (boolean, any?, string?)
	self.updateCount += 1
	if #self._queuedFailures > 0 then
		return false, nil, table.remove(self._queuedFailures, 1)
	end
	local current = DeepCopy(self._values[key])
	local ok, transformed = pcall(transform, current)
	if not ok then
		return false, nil, tostring(transformed)
	end
	if transformed ~= nil then
		self._values[key] = DeepCopy(transformed)
	end
	return true, DeepCopy(self._values[key]), nil
end

function MockDataStore:Peek(key: string): any?
	return DeepCopy(self._values[key])
end

function MockDataStore:Set(key: string, value: any?)
	self._values[key] = DeepCopy(value)
end

return MockDataStore
