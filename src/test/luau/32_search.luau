-- Searching bytes, patterns, strings, functions, and instructions.
local t = require("@test")
local ghidra = require("@ghidra")
local search = require("@ghidra/search")
local memory = require("@ghidra/memory")

-- main starts with 55 48 89 e5.
local hits = ghidra.collect(search.bytes("\x55\x48\x89\xe5"))
t.assertEqual(#hits, 1, "search.bytes finds the prologue")
t.assertEqual(hits[1].offset, 0x401000, "at the right address")

-- Wildcards, as a byte array with holes and as a hex pattern.
t.assertEqual(#ghidra.collect(search.bytes({ 0x55, 0x48, nil, 0xe5 })), 1,
	"search.bytes treats nil as a wildcard")
t.assertEqual(search.firstPattern("55 48 ?? e5").offset, 0x401000, "search.firstPattern")
t.assertEqual(#ghidra.collect(search.pattern("b8 ?? 00 00 00")), 2,
	"search.pattern finds both immediate loads")

-- Options.
t.assertEqual(#ghidra.collect(search.pattern("b8 ?? 00 00 00", { limit = 1 })), 1,
	"the limit option")
t.assertEqual(#ghidra.collect(search.pattern("b8 ?? 00 00 00", { from = 0x401100 })), 1,
	"the from option")
t.assertEqual(search.firstPattern("de ad be ef"), nil, "a pattern that is not there")

local badPattern = pcall(function()
	return search.firstPattern("55 zz")
end)
t.assertTrue(not badPattern, "a malformed pattern is rejected")

-- Strings.
ghidra.transaction("string", function()
	memory.write(0x401300, "hello world\0")
	require("@ghidra/datatypes").apply(0x401300, "char[12]")
end)
t.assertEqual(#ghidra.collect(search.strings("world")), 1, "search.strings")
t.assertEqual(#ghidra.collect(search.strings("nothing")), 0, "search.strings can miss")

-- Names.
t.assertEqual(#ghidra.collect(search.functions("^main$")), 1, "search.functions")
t.assertEqual(#ghidra.collect(search.functions("^")), 2, "and matches everything with ^")
t.assertTrue(#ghidra.collect(search.symbols("label")) >= 1, "search.symbols")
t.assertEqual(#ghidra.collect(search.instructions("^PUSH")), 1, "search.instructions")

t.finish("search")
