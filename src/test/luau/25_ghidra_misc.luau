-- Types, tasks, iteration shapes, output, references, and strings.
local t = require("@test")
local ghidra = require("@ghidra")
local types = require("@ghidra/types")
local dt = require("@ghidra/datatypes")

-- Types resolve lazily by short name, and anything else by full name.
t.assertEqual(tostring(types.SourceType.USER_DEFINED), "USER_DEFINED", "types.SourceType")
t.assertTrue(types.of("java.lang.String") ~= nil, "types.of imports any class")
local unknown = pcall(function()
	return types.NotARealGhidraType
end)
t.assertTrue(not unknown, "an unknown short name is an error")

-- Iteration accepts Java iterators, Java arrays, and Luau tables alike.
local list = java.new(java.import("java.util.ArrayList"))
list:add("x")
list:add("y")
t.assertEqual(#ghidra.collect(list), 2, "iterate a Java Iterable")
local array = java.array(java.import("java.lang.String"), 3)
array[1], array[2], array[3] = "a", "b", "c"
t.assertEqual(table.concat(ghidra.collect(array), ""), "abc", "collect a Java array")
-- collect() indexes arrays by length rather than iterating, so a null element
-- leaves a hole instead of ending the result early.
array[2] = nil
t.assertEqual(ghidra.collect(array)[3], "c", "a null element does not truncate")
t.assertEqual(#ghidra.collect({ 1, 2, 3, 4 }), 4, "iterate a Luau array")
t.assertEqual(#ghidra.collect(ghidra.functions(), 1), 1, "collect honours the limit")

-- Tasks report progress through the monitor.
local task = ghidra.task("Counting", { max = 2 })
task:step()
task:status("halfway")
task:checkCancelled()
t.assertTrue(task:monitor() ~= nil, "task exposes its monitor")

-- Output goes to the Ghidra console rather than the capture buffer.
ghidra.log("logged from the test")
ghidra.warn("warned from the test")
ghidra.status("status from the test")

t.assertEqual(#ghidra.args(), 0, "no script arguments here")
t.assertTrue(typeof(ghidra.isHeadless()) == "boolean", "isHeadless")

-- Strings: define one, then find it through ghidra.strings().
ghidra.transaction("string", function()
	local memory = require("@ghidra/memory")
	memory.write(0x401300, "hello\0")
	dt.apply(0x401300, "char[6]")
end)

local found = nil
for data in ghidra.strings() do
	if data.address.offset == 0x401300 then
		found = data.text
	end
end
t.assertEqual(found, "hello", "ghidra.strings finds a defined string")

-- References. The call in main already produces one to helper.
t.assertEqual(#ghidra.collect(ghidra.referencesTo(0x401100)), 1, "referencesTo")
ghidra.transaction("reference", function()
	ghidra.flat():createMemoryReference(
		ghidra.flat():getInstructionAt(ghidra.address(0x401000)),
		0,
		ghidra.address(0x401300),
		types.RefType.DATA
	)
end)
t.assertEqual(#ghidra.collect(ghidra.referencesTo(0x401300)), 1, "a created reference")

-- Custom extensions registered from a script behave like the built-in ones.
java.extend("ghidra.program.model.listing.Function", {
	properties = {
		isLeaf = {
			get = function(self)
				return #self:callees() == 0
			end,
		},
	},
})
t.assertTrue(ghidra.functionAt(0x401100).isLeaf, "a script-registered extension property")
t.assertTrue(not ghidra.functionAt(0x401000).isLeaf, "main calls helper, so it is not a leaf")

t.finish("ghidra misc")
