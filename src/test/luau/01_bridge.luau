-- Core java-bridge behaviour: imports, member access, arrays, exceptions.
local t = require("@test")

local System = java.import("java.lang.System")
t.assertTrue(System:currentTimeMillis() > 0, "static method call")

local Integer = java.import("java.lang.Integer")
t.assertEqual(Integer.MAX_VALUE, 2147483647, "static field read")
t.assertEqual(Integer:parseInt("42"), 42, "static method with argument")
t.assertEqual(Integer.MISSING_FIELD, nil, "unknown static member is nil")

local list = java.new(java.import("java.util.ArrayList"))
list:add("a")
list:add("b")
t.assertEqual(list:size(), 2, "instance method call")
t.assertEqual(list:get(0), "a", "string round-trip")
t.assertEqual(list.notAMember, nil, "unknown instance member is nil")

local arr = java.array(java.import("java.lang.String"), 2)
arr[1] = "hello"
t.assertEqual(#arr, 2, "array length")
t.assertEqual(arr[1], "hello", "array element")

-- A Java array iterates like a Luau array, since Ghidra returns plain arrays
-- from a lot of its API.
arr[2] = "world"
local seen = {}
for index, value in arr do
	seen[index] = value
end
t.assertEqual(#seen, 2, "iterating a Java array visits every element")
t.assertEqual(seen[1], "hello", "iteration yields elements in order")
t.assertEqual(seen[2], "world", "iteration yields the last element")

-- Methods reached through a non-public implementation class must still invoke:
-- reflection resolves them against classes like java.util.HashMap$KeyIterator,
-- which this module cannot access directly.
local map = java.new(java.import("java.util.HashMap"))
map:put("k", "v")
local keys = map:keySet():iterator()
t.assertTrue(keys:hasNext(), "a JDK iterator from a non-public class works")
t.assertEqual(keys:next(), "k", "and returns its element")

local ok = pcall(function()
	java.import("java.lang.Integer"):parseInt("not a number")
end)
t.assertTrue(not ok, "java exception becomes a lua error")
t.assertEqual(java.caught():getClass():getName(), "java.lang.NumberFormatException",
	"java.caught reports the original exception")

t.finish("bridge")
