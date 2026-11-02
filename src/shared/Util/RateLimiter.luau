--!strict
-- Per-key token bucket. Used on the server to cap how often each player may call a remote.

export type RateLimiter = {
	Allow: (self: RateLimiter, key: any) -> boolean,
	Forget: (self: RateLimiter, key: any) -> (),
}

type Bucket = { tokens: number, updated: number }

local RateLimiter = {}
RateLimiter.__index = RateLimiter

-- `burst` requests may arrive at once; after that `perSecond` requests refill each second.
function RateLimiter.new(perSecond: number, burst: number, clock: (() -> number)?): RateLimiter
	assert(perSecond > 0 and burst >= 1, "RateLimiter: perSecond must be > 0 and burst >= 1")
	local self = setmetatable({
		_rate = perSecond,
		_burst = burst,
		_clock = clock or os.clock,
		_buckets = {} :: { [any]: Bucket },
	}, RateLimiter)
	return (self :: any) :: RateLimiter
end

function RateLimiter:Allow(key: any): boolean
	local now: number = self._clock()
	local bucket = self._buckets[key]
	if not bucket then
		bucket = { tokens = self._burst, updated = now }
		self._buckets[key] = bucket
	else
		bucket.tokens = math.min(self._burst, bucket.tokens + (now - bucket.updated) * self._rate)
		bucket.updated = now
	end
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:Forget(key: any)
	self._buckets[key] = nil
end

return RateLimiter
