-- Equality and ordering on Java values.
--
-- Every push of a Java value creates a fresh userdata, so these have to compare
-- by value rather than by identity.
local t = require("@test")

local Integer = java.import("java.lang.Integer")
t.assertTrue(Integer:valueOf(7) == Integer:valueOf(7), "equal boxed values compare equal")
t.assertTrue(Integer:valueOf(7) ~= Integer:valueOf(8), "and unequal ones do not")

local list = java.new(java.import("java.util.ArrayList"))
local other = java.new(java.import("java.util.ArrayList"))
list:add("a")
t.assertTrue(list ~= other, "different lists are unequal")
other:add("a")
t.assertTrue(list == other, "lists with equal contents are equal")

-- Classes compare too.
t.assertTrue(java.import("java.lang.String") == java.import("java.lang.String"),
	"the same class imported twice")
t.assertTrue(java.import("java.lang.String") ~= java.import("java.lang.Integer"),
	"different classes")

-- Ordering, via Comparable.
t.assertTrue(Integer:valueOf(1) < Integer:valueOf(2), "less than")
t.assertTrue(Integer:valueOf(2) <= Integer:valueOf(2), "less than or equal")
t.assertTrue(Integer:valueOf(3) > Integer:valueOf(2), "greater than")
t.assertTrue(not (Integer:valueOf(3) < Integer:valueOf(2)), "and it really orders")

-- Values that are not Comparable say so rather than silently misbehaving.
local ok, err = pcall(function()
	return list < other
end)
t.assertTrue(not ok, "ordering a non-Comparable raises")
t.assertTrue(string.find(tostring(err), "cannot be ordered") ~= nil, "with a clear message")

t.finish("equality")
