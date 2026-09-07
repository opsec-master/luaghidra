-- java.proxy: implementing Java interfaces from Luau.
local t = require("@test")

-- A functional interface can take a bare function.
local isLong = java.proxy("java.util.function.Predicate", function(value)
	return #value > 3
end)

local list = java.new(java.import("java.util.ArrayList"))
for _, word in { "a", "bbbb", "cc", "ddddd" } do
	list:add(word)
end
list:removeIf(isLong)
t.assertEqual(list:size(), 2, "the predicate was called back into Luau")
t.assertEqual(list:get(0), "a", "and kept the right elements")

-- A table of functions implements an interface with several methods.
local comparator = java.proxy("java.util.Comparator", {
	compare = function(left, right)
		return #left - #right
	end,
})
local words = java.new(java.import("java.util.ArrayList"))
for _, word in { "ccc", "a", "bb" } do
	words:add(word)
end
words:sort(comparator)
t.assertEqual(words:get(0), "a", "the comparator sorted by length")
t.assertEqual(words:get(2), "ccc", "and put the longest last")

-- Object methods work without a handler.
t.assertTrue(string.find(tostring(comparator), "luau proxy") ~= nil, "tostring on a proxy")
t.assertTrue(comparator == comparator, "a proxy equals itself")

-- A missing handler reports the method that was called.
local missing = java.proxy("java.util.Comparator", {})
local ok, err = pcall(function()
	words:sort(missing)
end)
t.assertTrue(not ok, "a missing handler raises")
t.assertTrue(string.find(tostring(err), "compare") ~= nil, "the error names the method")

-- An error inside a handler propagates out of the Java call.
local failing = java.proxy("java.util.function.Predicate", function()
	error("handler exploded")
end)
local ok2, err2 = pcall(function()
	list:removeIf(failing)
end)
t.assertTrue(not ok2, "a failing handler raises")
t.assertTrue(string.find(tostring(err2), "handler exploded") ~= nil, "the original message survives")

-- Only interfaces can be proxied.
local notInterface = pcall(function()
	java.proxy("java.lang.String", function() end)
end)
t.assertTrue(not notInterface, "proxying a class is rejected")

t.finish("proxy")
