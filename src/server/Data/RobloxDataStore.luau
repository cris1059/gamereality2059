--!strict

local DataStoreService = game:GetService("DataStoreService")

local RobloxDataStore = {}
RobloxDataStore.__index = RobloxDataStore

function RobloxDataStore.new(name: string, maxAttempts: number, retryBaseSeconds: number)
	local self = setmetatable({}, RobloxDataStore)
	self._store = DataStoreService:GetDataStore(name)
	self._maxAttempts = maxAttempts
	self._retryBaseSeconds = retryBaseSeconds
	return self
end

-- True when DataStores answer from this server. In Studio this fails until
-- the place is published and "Enable Studio Access to API Services" is on.
function RobloxDataStore.Probe(name: string): (boolean, string?)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(name):GetAsync("__reality2059_probe")
	end)
	return ok, if ok then nil else tostring(result)
end

function RobloxDataStore:UpdateAsync(key: string, transform: (any?) -> any?): (boolean, any?, string?)
	local lastError = "Unknown DataStore error"
	for attempt = 1, self._maxAttempts do
		local ok, result = pcall(function()
			return self._store:UpdateAsync(key, transform)
		end)
		if ok then
			return true, result, nil
		end
		lastError = tostring(result)
		if attempt < self._maxAttempts then
			task.wait(self._retryBaseSeconds * (2 ^ (attempt - 1)))
		end
	end
	return false, nil, lastError
end

return RobloxDataStore
