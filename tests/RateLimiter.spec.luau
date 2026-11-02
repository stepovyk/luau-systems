local RateLimiter = require("../src/shared/Util/RateLimiter")

return function(t)
	local test, eq = t.test, t.eq

	test("rate limiter allows a burst, then refills over time", function()
		local now = 0
		local limiter = RateLimiter.new(2, 3, function()
			return now
		end)
		eq(limiter:Allow("a"), true)
		eq(limiter:Allow("a"), true)
		eq(limiter:Allow("a"), true)
		eq(limiter:Allow("a"), false)
		-- Other keys have their own bucket.
		eq(limiter:Allow("b"), true)
		now = 0.5
		eq(limiter:Allow("a"), true)
		eq(limiter:Allow("a"), false)
		now = 100
		for _ = 1, 3 do
			eq(limiter:Allow("a"), true)
		end
		eq(limiter:Allow("a"), false)
	end)

	test("forgetting a key resets it", function()
		local limiter = RateLimiter.new(1, 1, function()
			return 0
		end)
		eq(limiter:Allow("a"), true)
		eq(limiter:Allow("a"), false)
		limiter:Forget("a")
		eq(limiter:Allow("a"), true)
	end)
end
