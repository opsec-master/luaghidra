-- Instruction iteration and decompilation over real code.
local t = require("@test")
local ghidra = require("@ghidra")
local analysis = require("@ghidra/analysis")

-- The scratch program is disassembled when it is built.
local first = ghidra.instructionAt(0x401000)
t.assertTrue(first ~= nil, "instructionAt")
t.assertEqual(first.mnemonic, "PUSH", "instruction.mnemonic")
t.assertEqual(first.length, 1, "instruction.length")
t.assertEqual(first.address.offset, 0x401000, "instruction.address")
t.assertEqual(first:operands()[1], "RBP", "instruction:operands()")

local main = ghidra.functionAt(0x401000)
local mnemonics = {}
for instruction in main:instructions() do
	table.insert(mnemonics, instruction.mnemonic)
end
t.assertEqual(table.concat(mnemonics, " "), "PUSH MOV CALL MOV POP RET",
	"a function's instructions in order")

local viaOptions = ghidra.collect(ghidra.instructions({ set = main.body }))
t.assertEqual(#viaOptions, #mnemonics, "ghidra.instructions over an address set")

-- The call instruction knows where it goes.
local call = nil
for instruction in main:instructions() do
	if instruction.isCall then
		call = instruction
	end
end
t.assertTrue(call ~= nil, "instruction.isCall")
t.assertEqual(call:flowsTo()[1].offset, 0x401100, "instruction:flowsTo()")
t.assertTrue(#call:pcode() > 0, "instruction:pcode()")

local ret = ghidra.instructionAt(0x40100f)
t.assertTrue(ret.isTerminator, "instruction.isTerminator")
t.assertEqual(ret.fallThrough, nil, "a return has no fall-through")

-- Decompilation returns a result table rather than raising.
local result = main:decompile()
t.assertTrue(result.ok, `decompiling main succeeded: {tostring(result.error)}`)
t.assertTrue(string.find(result.c, "main") ~= nil, "the C mentions the function")
t.assertTrue(result.highFunction ~= nil, "the result carries a HighFunction")
t.assertTrue(#result.signature > 0, "the result carries a signature")

-- A bad decompile reports an error instead of raising.
local badCall = pcall(function()
	return ghidra.decompile(nil)
end)
t.assertTrue(not badCall, "decompiling nil is an error")

-- Analyzer options: what Ghidra's Analysis Options dialog shows.
local options = analysis.options()
t.assertTrue(next(options) ~= nil, "analysis.options lists the analyzers")
t.assertTrue(analysis.option("Stack") ~= nil, "analysis.option reads one")
t.assertEqual(analysis.option("Not An Analyzer"), nil, "an unknown option is nil")
t.assertTrue(analysis.optionDescription("Stack") ~= nil, "analysis.optionDescription")

ghidra.transaction("Analyzer options", function()
	analysis.setOption("Stack", false)
	t.assertEqual(analysis.option("Stack"), "false", "analysis.setOption")
	analysis.resetOptions({ "Stack" })
	t.assertEqual(analysis.option("Stack"), "true", "analysis.resetOptions")
end)

local badOption = pcall(function()
	ghidra.transaction("Bad option", function()
		analysis.setOption("Not An Analyzer", true)
	end)
end)
t.assertTrue(not badOption, "setting an unknown option is an error")

t.finish("ghidra analysis")
