-- Runs the pure-Luau tests with Lune:  lune run tests/run
-- Roblox datatypes the shared modules use (Color3) come from Lune's roblox library.

local roblox = require("@lune/roblox")
local process = require("@lune/process")

_G.Color3 = roblox.Color3
Color3 = roblox.Color3

local failures = 0
local passed = 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failures += 1
		print(`FAIL  {name}\n      {err}`)
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(`{label or "value"}: expected {tostring(expected)}, got {tostring(actual)}`, 2)
	end
end

local env = { test = test, eq = eq }
require("./InventoryCore.spec")(env)
require("./RateLimiter.spec")(env)

print(`{passed} passed, {failures} failed`)
if failures > 0 then
	process.exit(1)
end
