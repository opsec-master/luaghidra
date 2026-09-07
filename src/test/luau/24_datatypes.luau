-- Data type lookup, structure building, and application.
local t = require("@test")
local ghidra = require("@ghidra")
local dt = require("@ghidra/datatypes")

-- Built-in types resolve by name, including pointer and array notation.
t.assertEqual(dt.resolve("int"):getLength(), 4, "int is four bytes")
t.assertEqual(dt.resolve("char[8]"):getLength(), 8, "array notation")
t.assertTrue(dt.resolve("char *"):getLength() > 0, "pointer notation")
t.assertTrue(dt.find("byte") ~= nil, "find by name")

local unknown = pcall(function()
	dt.resolve("NoSuchType")
end)
t.assertTrue(not unknown, "an unknown type is an error")

ghidra.transaction("types", function()
	local header = dt.struct("Header", {
		{ name = "magic", type = "char[4]" },
		{ name = "size", type = "uint" },
	})
	t.assertEqual(header:getLength(), 8, "struct length is the sum of its fields")

	local flags = dt.enum("Flags", { NONE = 0, READ = 1, WRITE = 2 }, 1)
	t.assertEqual(flags:getLength(), 1, "enum width")

	local data = dt.apply(0x401200, header)
	t.assertEqual(data.length, 8, "applied data covers the struct")
	t.assertEqual(data.typeName, "Header", "data.typeName")
end)

t.assertEqual(ghidra.dataAt(0x401200).typeName, "Header", "the applied type persisted")

ghidra.transaction("clear", function()
	t.assertTrue(dt.clear(0x401200), "clear removes the data")
end)

-- Finding every place a type has been applied.
ghidra.transaction("instances", function()
	dt.apply(0x401400, "Header")
	dt.apply(0x401420, "Header")
end)
t.assertEqual(#ghidra.collect(dt.instances("Header")), 2, "dt.instances")
t.assertEqual(#ghidra.collect(dt.instances("int")), 0, "dt.instances can find none")

t.finish("datatypes")
