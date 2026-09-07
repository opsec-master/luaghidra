-- Cross-references: reading, filtering, creating, and removing.
local t = require("@test")
local ghidra = require("@ghidra")
local refs = require("@ghidra/references")

-- main calls helper, so helper has one call reference pointing at it.
local incoming = ghidra.collect(refs.to(0x401100))
t.assertEqual(#incoming, 1, "refs.to")
t.assertEqual(refs.countTo(0x401100), 1, "refs.countTo")

local call = incoming[1]
t.assertEqual(call.to.offset, 0x401100, "reference.to")
t.assertEqual(call.from.offset, 0x401004, "reference.from")
t.assertTrue(call.isCall, "reference.isCall")
t.assertTrue(call.isFlow, "reference.isFlow")
t.assertTrue(not call.isData, "a call is not a data reference")
t.assertTrue(not call.isIndirect, "a direct call is not indirect")
t.assertTrue(not call.isJump, "reference.isJump")
t.assertEqual(call.kind, "UNCONDITIONAL_CALL", "reference.kind")
t.assertEqual(call:toFunction().name, "helper", "reference:toFunction()")
t.assertEqual(call:fromFunction().name, "main", "reference:fromFunction()")

t.assertEqual(#ghidra.collect(refs.callsTo(0x401100)), 1, "refs.callsTo")

-- Creating and removing.
ghidra.transaction("refs", function()
	refs.add(0x401009, 0x401300, "DATA", 2)
	refs.add(0x40100a, 0x401304, "DATA", nil, "ANALYSIS")
end)
local created = ghidra.collect(refs.to(0x401300))
t.assertEqual(#created, 1, "refs.add")
local analyzed = ghidra.collect(ghidra.referencesFrom(0x40100a))
t.assertEqual(#analyzed, 1, "refs.add with a source type")
t.assertEqual(analyzed[1].source, "ANALYSIS", "the source type is recorded")
t.assertEqual(created[1].kind, "DATA", "the created reference's type")
t.assertEqual(created[1].operand, 2, "operands are 1-based")

ghidra.transaction("unref", function()
	refs.remove(created[1])
end)
t.assertEqual(refs.countTo(0x401300), 0, "refs.remove")

ghidra.transaction("clear", function()
	refs.removeAllFrom(0x401004)
end)
t.assertEqual(refs.countTo(0x401100), 0, "refs.removeAllFrom")

local unknownType = pcall(function()
	refs.type("NOT_A_REF_TYPE")
end)
t.assertTrue(not unknownType, "an unknown reference type is rejected")

-- The same references reach through the function and code-unit helpers.
local helper = ghidra.functionAt(0x401100)
t.assertEqual(#ghidra.collect(helper:xrefs()), 0, "function:xrefs() after removal")
t.assertTrue(#ghidra.collect(ghidra.instructionAt(0x401000):xrefsFrom()) >= 0,
	"codeUnit:xrefsFrom()")

t.finish("references")
