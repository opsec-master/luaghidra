-- require: aliases, relative paths, caching, and error messages.
local t = require("@test")

local first = require("./fixtures/counter")
local second = require("./fixtures/counter")
t.assertTrue(first == second, "modules are cached")
t.assertEqual(first.value, 1, "module body ran once")

local ok, err = pcall(function()
	return require("nope")
end)
t.assertTrue(not ok, "bare module names are rejected")
t.assertTrue(string.find(tostring(err), "@ghidra") ~= nil, "error suggests the alias form")

local ok2 = pcall(function()
	return require("./fixtures/missing")
end)
t.assertTrue(not ok2, "missing modules raise")

-- A module that raises can be required again; the failure must not leave the
-- module marked as loading, which would look like a cycle on the retry.
for attempt = 1, 2 do
	local ok, err = pcall(function()
		return require("./fixtures/broken")
	end)
	t.assertTrue(not ok, `attempt {attempt} raises`)
	t.assertTrue(string.find(tostring(err), "cycle") == nil, `attempt {attempt} is not a cycle`)
end

t.finish("require")
