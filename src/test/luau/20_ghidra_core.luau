-- The @ghidra core module against a small in-memory program.
local t = require("@test")
local ghidra = require("@ghidra")

local program = ghidra.program()
t.assertEqual(program.name, "scratch", "program.name extension property")
t.assertEqual(tostring(program.imageBase), "00000000", "imageBase is an Address")
t.assertTrue(program:getListing() ~= nil, "the Java API is still reachable")
t.assertEqual(program.functionCount, 2, "functionCount")

-- Addresses coerce from strings and numbers.
local fromNumber = ghidra.address(0x401000)
local fromString = ghidra.address("00401000")
t.assertEqual(fromNumber.offset, 0x401000, "address.offset")
t.assertEqual(tostring(fromNumber), tostring(fromString), "string and number agree")
t.assertEqual(fromNumber.space.name, "ram", "address.space")

-- Functions.
local names = {}
for func in ghidra.functions() do
	table.insert(names, func.name)
end
table.sort(names)
t.assertEqual(table.concat(names, ","), "helper,main", "ghidra.functions iterates in order")

local main = ghidra.functionAt(0x401000)
t.assertTrue(main ~= nil, "functionAt finds the entry")
t.assertEqual(main.name, "main", "function.name")
t.assertEqual(main.entry.offset, 0x401000, "function.entry")
t.assertEqual(main.size, 16, "function.size")
t.assertEqual(main:getName(), "main", "the Java method still works")

t.assertTrue(ghidra.functionContaining(0x401008) ~= nil, "functionContaining")
t.assertEqual(ghidra.functionAt(0x401234), nil, "functionAt returns nil off-entry")

-- Symbols.
local label = ghidra.symbolAt(0x401200)
t.assertTrue(label ~= nil, "symbolAt")
t.assertEqual(label.name, "a_label", "symbol.name")
t.assertEqual(label.address.offset, 0x401200, "symbol.address")

local found = ghidra.collect(ghidra.symbolsNamed("main"))
t.assertEqual(#found, 1, "symbolsNamed")

-- Memory.
local blocks = ghidra.collect(ghidra.memoryBlocks())
t.assertEqual(#blocks, 2, "the code block and the overlay block")
t.assertEqual(blocks[1].name, ".text", "memoryBlock.name")
t.assertEqual(blocks[1].size, 0x1000, "memoryBlock.size")

-- Walking outwards from an address.
t.assertEqual(ghidra.functionAfter(0x401000).entry.offset, 0x401100, "functionAfter")
t.assertEqual(ghidra.functionBefore(0x401100).entry.offset, 0x401000, "functionBefore")
t.assertEqual(ghidra.firstFunction().entry.offset, 0x401000, "firstFunction")
t.assertEqual(ghidra.lastFunction().entry.offset, 0x401100, "lastFunction")
t.assertEqual(ghidra.functionAfter(0x401100), nil, "functionAfter past the last is nil")

-- codeUnitAt only answers at the start of a code unit; the containing lookups
-- answer from the middle of one.
t.assertEqual(ghidra.codeUnitAt(0x401002), nil, "codeUnitAt inside an instruction is nil")
t.assertEqual(ghidra.instructionContaining(0x401002).address.offset, 0x401001,
	"instructionContaining")
t.assertEqual(ghidra.codeUnitContaining(0x401002).address.offset, 0x401001,
	"codeUnitContaining")
t.assertEqual(ghidra.instructionAfter(0x401000).address.offset, 0x401001, "instructionAfter")
t.assertEqual(ghidra.instructionBefore(0x401001).address.offset, 0x401000, "instructionBefore")

-- The call at 0x401004 refers to helper.
t.assertEqual(ghidra.referencedAddress(0x401004).offset, 0x401100, "referencedAddress")

-- The script itself, for the helpers that live only on GhidraScript.
t.assertTrue(ghidra.script() ~= nil, "ghidra.script()")
t.assertTrue(ghidra.script():getState() ~= nil, "the script carries its state")

t.finish("ghidra core")
