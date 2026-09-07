-- Program-level state: metadata, undo/redo, and analysis helpers.
local t = require("@test")
local ghidra = require("@ghidra")
local analysis = require("@ghidra/analysis")

local program = ghidra.program()
t.assertEqual(program.processor, "x86", "program.processor")
t.assertTrue(not program.bigEndian, "program.bigEndian")
t.assertEqual(program.pointerSize, 8, "program.pointerSize")
t.assertTrue(program.symbolCount > 0, "program.symbolCount")
t.assertTrue(program.globalNamespace ~= nil, "program.globalNamespace")
t.assertTrue(program.bookmarkManager ~= nil, "program.bookmarkManager")

local info = ghidra.info()
t.assertEqual(info.name, "scratch", "info.name")
t.assertEqual(info.languageId, "x86:LE:64:default", "info.languageId")
t.assertEqual(info.functionCount, 2, "info.functionCount")
t.assertEqual(info.imageBase, "00000000", "info.imageBase")

-- Undo and redo.
ghidra.transaction("rename for undo", function()
	ghidra.functionAt(0x401000):rename("renamed")
end)
t.assertEqual(ghidra.functionAt(0x401000).name, "renamed", "the rename applied")
t.assertTrue(ghidra.undo(), "ghidra.undo")
t.assertEqual(ghidra.functionAt(0x401000).name, "main", "and it reverted")
t.assertTrue(ghidra.redo(), "ghidra.redo")
t.assertEqual(ghidra.functionAt(0x401000).name, "renamed", "and it came back")
ghidra.undo()

-- Clearing and re-disassembling.
ghidra.transaction("clear", function()
	analysis.clear(0x401100, 0x401105)
end)
t.assertEqual(ghidra.instructionAt(0x401100), nil, "analysis.clear removed the code")

ghidra.transaction("redisassemble", function()
	t.assertTrue(analysis.disassemble(0x401100), "analysis.disassemble")
end)
t.assertEqual(ghidra.instructionAt(0x401100).mnemonic, "MOV", "and the code is back")

-- Creating and removing a function in the filler region.
ghidra.transaction("nop function", function()
	analysis.disassemble(0x401400)
	local created = analysis.createFunction(0x401400, "filler")
	t.assertTrue(created ~= nil, "analysis.createFunction")
end)
t.assertEqual(ghidra.functionAt(0x401400).name, "filler", "the function is there")
ghidra.transaction("remove", function()
	analysis.removeFunction(0x401400)
end)
t.assertEqual(ghidra.functionAt(0x401400), nil, "analysis.removeFunction")

-- Clearing with an address set.
ghidra.transaction("clear set", function()
	analysis.clear(ghidra.functionAt(0x401000).body)
end)
t.assertEqual(ghidra.instructionAt(0x401000), nil, "analysis.clear over an address set")

-- Registers.
t.assertTrue(ghidra.register("RAX") ~= nil, "ghidra.register")
t.assertEqual(ghidra.register("NOTAREGISTER"), nil, "an unknown register is nil")
t.assertTrue(#ghidra.registers() > 0, "ghidra.registers")
local badRegister = pcall(function()
	return ghidra.registerValue("NOTAREGISTER", 0x401000)
end)
t.assertTrue(not badRegister, "reading an unknown register raises")
-- Nothing pins RAX down in this program, so there is no value to read.
t.assertEqual(ghidra.registerValue("RAX", 0x401000), nil, "ghidra.registerValue")

-- Demangling.
local mangled = "_ZN3foo3barEv"
t.assertTrue(string.find(tostring(analysis.demangle(mangled)), "foo::bar") ~= nil,
	"analysis.demangle")
t.assertEqual(analysis.demangledName(mangled), "bar", "analysis.demangledName")
t.assertEqual(analysis.demangle("just_a_plain_name"), nil, "an unmangled name gives nil")

t.finish("program")
