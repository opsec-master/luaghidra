-- Basic blocks, control flow, and decompiler P-code.
local t = require("@test")
local ghidra = require("@ghidra")
local blocks = require("@ghidra/blocks")
local pcode = require("@ghidra/pcode")

local main = ghidra.functionAt(0x401000)

-- main is straight-line code with a call, so it splits at the call boundary.
local mainBlocks = ghidra.collect(blocks.of(main))
t.assertTrue(#mainBlocks >= 1, "blocks.of(function)")
t.assertEqual(mainBlocks[1].minAddress.offset, 0x401000, "the first block starts at the entry")
t.assertTrue(mainBlocks[1].size > 0, "a block is an address set")

local entryBlock = blocks.at(0x401000)
t.assertTrue(entryBlock ~= nil, "blocks.at")
t.assertEqual(entryBlock:getName(), "main", "the entry block is named for the function")
t.assertEqual(#blocks.containing(0x401001), 1, "blocks.containing")

-- Flow out of the entry block reaches the call target and the fall-through.
local destinations = {}
for successor in blocks.successors(entryBlock) do
	table.insert(destinations, successor.minAddress.offset)
end
table.sort(destinations)
t.assertTrue(#destinations >= 1, "blocks.successors")

local flows = ghidra.collect(blocks.flowsOut(entryBlock))
t.assertTrue(#flows >= 1, "blocks.flowsOut carries the flow type")
t.assertTrue(flows[1]:getFlowType() ~= nil, "and the reference exposes it")

t.assertEqual(#ghidra.collect(blocks.predecessors(blocks.at(0x401100))), 1,
	"blocks.predecessors of helper")

-- P-code from the decompiler.
local high = pcode.high(main)
t.assertTrue(high ~= nil, "pcode.high")

local ops = ghidra.collect(pcode.ops(high))
t.assertTrue(#ops > 0, "pcode.ops")
t.assertTrue(#ops[1]:getMnemonic() > 0, "a P-code op has a mnemonic")

local hasCall = false
for _, op in ops do
	if op:getMnemonic() == "CALL" then
		hasCall = true
	end
end
t.assertTrue(hasCall, "the P-code contains the call")

t.assertTrue(#ghidra.collect(pcode.blocks(high)) >= 1, "pcode.blocks")
t.assertTrue(#pcode.symbols(high) >= 0, "pcode.symbols")
t.assertTrue(#pcode.parameters(high) >= 0, "pcode.parameters")

-- Passing a function decompiles it first.
t.assertTrue(#ghidra.collect(pcode.ops(ghidra.functionAt(0x401100))) > 0,
	"pcode.ops accepts a function")

-- Luau members on p-code values, so scripts do not have to spell out getters.
t.assertEqual(ops[1].mnemonic, ops[1]:getMnemonic(), "PcodeOp.mnemonic")
t.assertEqual(ops[1].inputCount, ops[1]:getNumInputs(), "PcodeOp.inputCount")
t.assertEqual(#ops[1]:inputs(), ops[1]:getNumInputs(), "PcodeOp:inputs()")
t.assertTrue(ops[1].address ~= nil, "PcodeOp.address is the instruction address")
t.assertEqual(ops[1]:input(ops[1].inputCount + 1), nil, "PcodeOp:input past the end is nil")

local callOp = nil
for _, op in ops do
	if op.mnemonic == "CALL" then
		callOp = op
	end
end
local callTarget = callOp:input(1)
t.assertEqual(callTarget.offset, 0x401100, "Varnode.offset")
t.assertTrue(callTarget.size > 0, "Varnode.size")
t.assertTrue(callTarget.address ~= nil, "Varnode.address")
t.assertEqual(pcode.constant(callTarget), 0x401100, "pcode.constant reads an address varnode")
t.assertEqual(tostring(pcode.addressOf(callTarget)), "00401100", "pcode.addressOf")

-- Call sites carry their arguments, from either side of the call.
local calls = ghidra.collect(pcode.calls(main))
t.assertEqual(#calls, 1, "pcode.calls finds the one call main makes")
t.assertEqual(calls[1].target.offset, 0x401100, "the call target")
t.assertEqual(calls[1].targetFunction:getName(), "helper", "the call target resolves to a function")
t.assertEqual(calls[1].at.offset, 0x401004, "the call site address")
t.assertTrue(not calls[1].indirect, "a direct call is not indirect")

local sites = ghidra.collect(pcode.callsTo(ghidra.functionAt(0x401100)))
t.assertEqual(#sites, 1, "pcode.callsTo finds the call from main")
t.assertEqual(sites[1].caller:getName(), "main", "and says who makes it")
t.assertEqual(#ghidra.collect(pcode.callsTo("helper")), 1, "pcode.callsTo accepts a name")
t.assertEqual(#ghidra.collect(main:calls()), 1, "func:calls()")
t.assertEqual(#ghidra.collect(ghidra.functionAt(0x401100):callSites()), 1, "func:callSites()")

-- Slices, which the decompiler builds from the same varnodes.
local returned = nil
for _, op in ops do
	if op.mnemonic == "RETURN" and op.inputCount > 1 then
		returned = op:input(2)
	end
end
if returned ~= nil then
	t.assertTrue(#pcode.backwardSlice(returned) >= 1, "pcode.backwardSlice")
	t.assertTrue(#pcode.forwardSlice(returned) >= 1, "pcode.forwardSlice")
	t.assertTrue(#pcode.backwardSliceOps(returned) >= 0, "pcode.backwardSliceOps")
end

-- Luau members on blocks, so the flow graph reads like the rest of the API.
t.assertEqual(entryBlock.name, "main", "CodeBlock.name")
t.assertEqual(entryBlock.start.offset, 0x401000, "CodeBlock.start")
t.assertTrue(entryBlock.flow ~= nil, "CodeBlock.flow")
t.assertTrue(#ghidra.collect(entryBlock:successors()) >= 1, "block:successors()")
t.assertEqual(#ghidra.collect(blocks.at(0x401100):predecessors()), 1, "block:predecessors()")
t.assertTrue(flows[1].flow ~= nil, "CodeBlockReference.flow")
t.assertTrue(flows[1].to ~= nil, "CodeBlockReference.to")

t.finish("blocks and pcode")
