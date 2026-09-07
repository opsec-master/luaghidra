-- Code units: comments, bytes, operands, and structured data.
local t = require("@test")
local ghidra = require("@ghidra")
local dt = require("@ghidra/datatypes")

local push = ghidra.instructionAt(0x401000)
t.assertEqual(push.length, 1, "codeUnit.length")
t.assertEqual(push.endAddress.offset, 0x401000, "codeUnit.endAddress")
t.assertEqual(push.bytes[1], 0x55, "codeUnit.bytes")
t.assertEqual(push.label, "main", "codeUnit.label")
t.assertEqual(push.program.name, "scratch", "codeUnit.program")
t.assertEqual(push.operandCount, 1, "instruction.operandCount")
t.assertEqual(push.text, "PUSH RBP", "instruction.text")
t.assertEqual(push.registerOf(push, 1):getName(), "RBP", "instruction:registerOf()")

local mov = ghidra.instructionAt(0x401009)
t.assertEqual(mov.mnemonic, "MOV", "the immediate load")
t.assertEqual(mov:scalar(2), 1, "instruction:scalar() is 1-based")
t.assertEqual(mov:scalar(1), nil, "a register operand has no scalar")

-- Comments through the code unit rather than the address.
ghidra.transaction("comments", function()
	push:setCommentText("frame setup", "PRE")
	push:setCommentText("save rbp")
end)
t.assertEqual(push:comment(), "save rbp", "codeUnit:comment() defaults to EOL")
t.assertEqual(push:comment("PRE"), "frame setup", "codeUnit:comment(kind)")
local all = push:comments()
t.assertEqual(all.EOL, "save rbp", "codeUnit:comments() collects EOL")
t.assertEqual(all.PRE, "frame setup", "and PRE")
t.assertEqual(all.POST, nil, "and omits the ones that are unset")

-- Structured data: apply a struct and walk its components.
ghidra.transaction("struct", function()
	dt.struct("Pair", {
		{ name = "first", type = "int" },
		{ name = "second", type = "int" },
	})
	dt.apply(0x401400, "Pair")
end)

local pair = ghidra.dataAt(0x401400)
t.assertEqual(pair.typeName, "Pair", "data.typeName")
t.assertEqual(pair.componentCount, 2, "data.componentCount")
local parts = pair:components()
t.assertEqual(#parts, 2, "data:components()")
t.assertEqual(parts[1].fieldName, "first", "component.fieldName")
t.assertEqual(parts[2].parent.typeName, "Pair", "component.parent")
t.assertEqual(parts[1].address.offset, 0x401400, "component.address")
t.assertEqual(parts[2].address.offset, 0x401404, "the second component follows the first")

t.finish("listing")
