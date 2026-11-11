--!strict

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(maxRequests: number, windowSeconds: number, clock: (() -> number)?)
	local self = setmetatable({}, RateLimiter)
	self._maxRequests = maxRequests
	self._windowSeconds = windowSeconds
	self._clock = clock or os.clock
	self._buckets = {} :: { [number]: { startedAt: number, count: number } }
	return self
end

function RateLimiter:Allow(userId: number): boolean
	local now = self._clock()
	local bucket = self._buckets[userId]
	if not bucket or now - bucket.startedAt >= self._windowSeconds then
		self._buckets[userId] = { startedAt = now, count = 1 }
		return true
	end
	if bucket.count >= self._maxRequests then
		return false
	end
	bucket.count += 1
	return true
end

function RateLimiter:Remove(userId: number)
	self._buckets[userId] = nil
end

return RateLimiter
